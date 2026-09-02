library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../data/warden_models.dart';
import '../data/warden_providers.dart';
import '../widgets/warden_ui.dart';
import 'sheet_scaffold.dart';

/// Putting a person in a bed, from either end.
///
/// THE TWO DIRECTIONS ARE THE SAME WRITE. Standing in a corridor a warden thinks either "where
/// does Aarav sleep?" (start from the person, choose a bed) or "who is in 204-2?" (start from
/// the bed, choose a person). Both end in one UPDATE of students.bed_id, because that is the
/// only column app.beds_guard allows a client to move — see WardenRepository.assignBed.
///
/// NOTHING HERE CHECKS WHETHER THE BED IS FREE. It offers only free beds, which is courtesy,
/// not enforcement: between the list being drawn and the tap landing, another warden on another
/// phone may have taken it. app.students_bed_guard and the students_one_active_per_bed unique
/// index settle that race server-side and come back with "Bed 2 is already occupied. Choose a
/// free bed." — which [runAction] puts on screen verbatim.
///
/// ── THE SHEET OPENS FIRST, AND THE SHEET DOES THE READING ────────────────────────────────
///
/// Every picker here used to be `await ref.read(someProvider.future)` and THEN showGlassSheet.
/// That shape cost a warden an afternoon: they tapped "Choose a bed" and got nothing — no
/// sheet, no spinner, no message — with 45 free beds in the building and RLS letting them read
/// every one. Three separate faults hide in that one line:
///
///  1. `ref.read` takes no subscription. Both bed providers are autoDispose, so the element is
///     torn down on the next tick while its own body is still suspended at an await. Riverpod 3
///     lets a disposed provider's in-flight future RESOLVE, but it does not let the resumed body
///     touch `ref` again — freeBedOptionsProvider watched its second dependency after the await
///     gap, and that threw UnmountedRefException out of `.future` at both call sites.
///  2. There was no try/catch, so that exception — and any real one, an expired token, no
///     signal — went to the zone as an unhandled async error. Identical silence.
///  3. Even with both fixed, awaiting a network read before showing anything means the control
///     does nothing for as long as the network takes.
///
/// So the await is gone. The tap shows the sheet on the frame it lands, and the sheet WATCHES
/// the provider: a real subscription for as long as the picker is on screen, which is what
/// makes the teardown impossible rather than merely unlikely. Loading, empty, failed and
/// refused are then four states of one widget that is already in front of the warden, instead
/// of four things that could happen before any widget exists. See [FreeBedPicker].
///
/// The providers stay autoDispose deliberately — a free-bed list is exactly the data that must
/// NOT be pinned for the session, because the next warden down the corridor is assigning beds
/// out of the same building.

/// Choose a bed for [student]. Returns true if the bed changed.
Future<bool> showAssignBedSheet(
  BuildContext context,
  WidgetRef ref, {
  required Student student,
}) async {
  final hostelId = student.hostelId;
  final chosen = await showGlassSheet<FreeBed>(
    context: context,
    builder: (_) => FreeBedPicker(
      hostelId: hostelId,
      title: student.hasBed ? 'Move ${student.fullName}' : 'Assign a bed',
    ),
  );
  if (chosen == null || !context.mounted) return false;

  final ok = await runAction(
    context,
    success: '${student.fullName} → ${chosen.label}',
    action: () => ref.read(wardenRepositoryProvider).assignBed(
          studentId: student.id,
          hostelId: hostelId,
          bedId: chosen.bed.id,
        ),
  );
  if (ok) refreshBeds(ref);
  return ok;
}

/// Take [student] out of their bed without checking them out of the hostel.
///
/// A real and distinct case from vacating: a resident moving rooms next week, or one whose bed
/// is being repaired. Checking them out would end their tenancy, deactivate their login and
/// stop their fee ledger — three things nobody asked for.
Future<bool> showReleaseBedSheet(
  BuildContext context,
  WidgetRef ref, {
  required Student student,
}) async {
  final confirmed = await showGlassSheet<bool>(
    context: context,
    builder: (_) => _ConfirmSheet(
      title: 'Free this bed?',
      body: '${student.fullName} stays on the roster and keeps their fee ledger. '
          'They will show as awaiting a bed until you place them again.',
      confirmLabel: 'Free the bed',
      tone: NivoraColors.warning,
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final ok = await runAction(
    context,
    success: '${student.fullName} is no longer in a bed',
    action: () => ref.read(wardenRepositoryProvider).assignBed(
          studentId: student.id,
          hostelId: student.hostelId,
          bedId: null,
        ),
  );
  if (ok) refreshBeds(ref);
  return ok;
}

/// Start from neither end: pick a resident who has no bed, then pick a bed for them.
///
/// The home screen's "Assign bed" action. Two taps rather than one because there is no obvious
/// subject — but it opens on the people who actually need placing, which is a much shorter list
/// than the roster and is exactly who a warden is thinking about.
Future<bool> showPlaceResidentSheet(
  BuildContext context,
  WidgetRef ref, {
  required String hostelId,
}) async {
  final chosen = await showGlassSheet<Student>(
    context: context,
    builder: (_) => _AwaitingBedPicker(hostelId: hostelId),
  );
  if (chosen == null || !context.mounted) return false;
  return showAssignBedSheet(context, ref, student: chosen);
}

/// Choose a person for [bed]. The other direction: offered from the room sheet.
Future<bool> showFillBedSheet(
  BuildContext context,
  WidgetRef ref, {
  required Bed bed,
  required String bedLabel,
}) async {
  final chosen = await showGlassSheet<Student>(
    context: context,
    builder: (_) => _AwaitingBedPicker(hostelId: bed.hostelId, bedLabel: bedLabel),
  );
  if (chosen == null || !context.mounted) return false;

  final ok = await runAction(
    context,
    success: '${chosen.fullName} → $bedLabel',
    action: () => ref.read(wardenRepositoryProvider).assignBed(
          studentId: chosen.id,
          hostelId: bed.hostelId,
          bedId: bed.id,
        ),
  );
  if (ok) refreshBeds(ref);
  return ok;
}

/// Check a resident out of the hostel altogether.
///
/// Goes through wd_vacate_student, which frees the bed, deactivates the login AND raises the
/// deletion request in ONE transaction. Doing it as client updates leaves a bed nobody can be
/// assigned to, an account that can still sign in, or a check-out with no request attached if
/// the connection drops in between — see StudentRepository.vacate.
///
/// ═══ THIS SHEET USED TO SAY THE OPPOSITE OF WHAT NOW HAPPENS ═══
/// Its old sentence was "The record and its history stay — this is not a deletion." That was
/// true until the owner asked for the erasure, and it is the sentence a warden would have
/// relied on when telling a departing resident what the hostel keeps. A confirm sheet whose
/// copy has gone stale is worse than no confirm sheet: the person reads it, believes it, and
/// finds out a month later. So it names the deletion, names the deadline, names what survives
/// it, and says out loud that it can be undone.
///
/// THE DATE IS SPOKEN AS A PROMISE, NOT AS A FACT. Nothing is stored yet when this is on
/// screen, so it says "one month from today" rather than printing a date this app computed —
/// `now() + interval '1 month'` is evaluated by Postgres, and the real date is read back from
/// the row afterwards by [studentErasureProvider]. A phone an hour fast must not be the thing
/// that tells somebody when their ID proof gets destroyed.
Future<bool> showCheckOutSheet(
  BuildContext context,
  WidgetRef ref, {
  required Student student,
}) async {
  final confirmed = await showGlassSheet<bool>(
    context: context,
    builder: (_) => _ConfirmSheet(
      title: 'Check out ${student.fullName}?',
      body: 'Their bed is freed and their login is deactivated.\n\n'
          'Their personal details — phone, guardian, address, ID proof and photo — are '
          'scheduled for deletion one month from today. You can cancel that any time before it '
          'runs.\n\n'
          'The rent ledger is kept permanently.',
      confirmLabel: 'Check out',
      tone: NivoraColors.error,
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final ok = await runAction(
    context,
    success: '${student.fullName} checked out — details scheduled for deletion',
    action: () => ref.read(studentRepositoryProvider).vacate(student.id),
  );
  if (ok) {
    refreshResidents(ref);
    ref.invalidate(studentErasureProvider(student.id));
  }
  return ok;
}

// ─────────────────────────────────────────────────────────────────────────────
// THE DELETION, AND THE MONTH BEFORE IT
// ─────────────────────────────────────────────────────────────────────────────

/// Whether a deletion is scheduled for one resident, and for when.
///
/// autoDispose and read at the moment the sheet opens rather than carried down from the list:
/// a warden about to cancel a deletion must not be acting on a date cached when the roster
/// last loaded. It is watched from `build`, never `ref.read(...future)` — see the note at the
/// top of this file for what that costs.
final studentErasureProvider =
    FutureProvider.autoDispose.family<ErasureSchedule?, String>((ref, studentId) {
  return ref.watch(wardenRepositoryProvider).erasure(studentId);
});

/// Withdraw a scheduled deletion.
///
/// Not styled as destructive, because it is not: it is the button that STOPS a destruction.
/// The mockup's coral belongs on check-out, not here.
Future<bool> showCancelErasureSheet(
  BuildContext context,
  WidgetRef ref, {
  required Student student,
  required DateTime dueAt,
}) async {
  final confirmed = await showGlassSheet<bool>(
    context: context,
    builder: (_) => _ConfirmSheet(
      title: 'Keep ${student.fullName}\'s details?',
      body: 'The deletion scheduled for ${shortDate(dueAt)} is cancelled and their record stays '
          'as it is. Do this when someone is coming back.\n\n'
          'Checking them out again starts a fresh one-month countdown.',
      confirmLabel: 'Keep the record',
      icon: Icons.shield_outlined,
      tone: NivoraColors.success,
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final ok = await runAction(
    context,
    success: 'Deletion cancelled — ${student.fullName}\'s details are kept',
    action: () => ref.read(wardenRepositoryProvider).cancelErasure(student.id),
  );
  if (ok) {
    ref.invalidate(studentErasureProvider(student.id));
    refreshResidents(ref);
  }
  return ok;
}

/// Schedule a deletion by hand.
///
/// The gap this fills is real and dated: everyone checked out BEFORE the erasure shipped has
/// no request against them, and so would sit in the roster with their ID proof indefinitely.
/// It is also the way back for a resident whose deletion was cancelled and who has now gone
/// for good.
Future<bool> showRequestErasureSheet(
  BuildContext context,
  WidgetRef ref, {
  required Student student,
}) async {
  final confirmed = await showGlassSheet<bool>(
    context: context,
    builder: (_) => _ConfirmSheet(
      title: 'Schedule deletion for ${student.fullName}?',
      body: 'Their personal details — phone, guardian, address, ID proof and photo — are '
          'deleted one month from today, along with any complaints they raised. You can cancel '
          'it any time before it runs.\n\n'
          'The rent ledger is kept permanently.',
      confirmLabel: 'Schedule deletion',
      tone: NivoraColors.error,
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final ok = await runAction(
    context,
    success: 'Deletion scheduled for ${student.fullName}',
    action: () => ref.read(wardenRepositoryProvider).requestErasure(student.id),
  );
  if (ok) ref.invalidate(studentErasureProvider(student.id));
  return ok;
}

/// What the resident sheet shows once somebody has been checked out.
///
/// FOUR STATES, KEPT APART. Loading is a skeleton, not a claim; a record with no request says
/// so and offers to make one; a pending one names the real stored date and the way out of it;
/// an erased one is a tombstone and says what is left. A failed read shows the server's own
/// sentence with a retry — [AsyncSection] owns that last distinction, and it is why this reads
/// its own data instead of taking a nullable date from its caller.
class ErasureBlock extends ConsumerWidget {
  const ErasureBlock({super.key, required this.student});

  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final schedule = ref.watch(studentErasureProvider(student.id));

    return AsyncSection<ErasureSchedule?>(
      value: schedule,
      onRetry: () => ref.invalidate(studentErasureProvider(student.id)),
      loading: const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.xs),
        child: SkeletonBlock(lines: 2),
      ),
      builder: (row) {
        if (row != null && row.isErased) {
          return InfoCallout(
            icon: Icons.lock_outline_rounded,
            title: 'Details deleted',
            tone: NivoraColors.info,
            child: Text(
              'Their personal details were deleted on ${shortDate(row.erasedAt!)} at their '
              'request. The rent ledger below is all that remains, and it stays.',
              style: t.textTheme.bodySmall,
            ),
          );
        }

        if (row == null || !row.isPending) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoCallout(
                icon: Icons.info_outline_rounded,
                child: Text(
                  'No deletion is scheduled. Their details stay on file until one is.',
                  style: t.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: Space.sm),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.tones.error,
                  side: BorderSide(
                    color: context.tones.chipBorder(context.tones.error),
                    width: Strokes.hairline,
                  ),
                ),
                icon: const Icon(Icons.auto_delete_outlined, size: IconSize.md),
                label: const Text('Schedule deletion'),
                onPressed: () => showRequestErasureSheet(context, ref, student: student),
              ),
            ],
          );
        }

        final due = row.dueAt!;
        final days = row.daysLeft!;
        // Said exactly, because rounding it up would be a promise about a day that may not be
        // there. The job runs nightly at 03:15, so "due" is genuinely still cancellable.
        final when = switch (days) {
          < 0 => 'due since ${shortDate(due)} — it runs on the next nightly sweep',
          0 => 'due today, ${shortDate(due)}',
          1 => 'in 1 day, on ${shortDate(due)}',
          _ => 'in $days days, on ${shortDate(due)}',
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoCallout(
              icon: Icons.schedule_outlined,
              title: 'Deletion scheduled',
              tone: NivoraColors.warning,
              child: Text(
                'Their phone, email, guardian, address, ID proof and photo — and any complaints '
                'they raised — are deleted $when. The rent ledger is kept.',
                style: t.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.shield_outlined, size: IconSize.md),
              label: const Text('Cancel the deletion'),
              onPressed: () =>
                  showCancelErasureSheet(context, ref, student: student, dueAt: due),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PICKERS
// ─────────────────────────────────────────────────────────────────────────────

/// Every free bed, in the order a warden walks the building.
///
/// assign-bed-select-bed.png groups the available beds under the storey they are on and marks
/// each one `● Available Now` in mint. The mockup's floor switcher is a segmented control and
/// its bed tiles carry a room type and a per-bed price; public.rooms has neither a type nor a
/// price (only `room_number` and `capacity`), so the groups are simply stacked in walking order
/// under the design's own section heading and each bed says what it really is.
/// IT READS ITS OWN DATA, and that is the fix, not a refactor for tidiness. Watching
/// [freeBedOptionsProvider] from `build` means the provider has a listener for exactly as long
/// as the picker is on screen — so it, `freeBedsProvider` and `roomOccupancyProvider` cannot be
/// disposed while their requests are in flight, which is what the caller's old `ref.read(…
/// .future)` could not promise. See the note at the top of this file.
///
/// It also puts all four states in the one place the warden is already looking: a spinner while
/// it loads, the rooms when they arrive, "every bed is taken" when the building really is full,
/// and the failure's own sentence when the read did not work — with a retry that is drawn only
/// when retrying could help. [AsyncSection] and [FailureState] own that last distinction.
class FreeBedPicker extends ConsumerWidget {
  const FreeBedPicker({super.key, required this.hostelId, required this.title});

  final String hostelId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(freeBedOptionsProvider(hostelId));
    // riverpod 3: AsyncValue.value, not valueOrNull. Null until the first result lands, and a
    // count is a claim about the building — so while it is unknown the sheet says nothing
    // rather than "0 free", which would be a fabricated fact about a full hostel.
    final loaded = options.value;

    return SheetBody(
      title: title,
      subtitle: loaded == null ? null : '${loaded.length} free',
      child: AsyncSection<List<FreeBed>>(
        value: options,
        onRetry: () => ref.invalidate(freeBedOptionsProvider(hostelId)),
        builder: (beds) => _FreeBedList(beds: beds),
      ),
    );
  }
}

class _FreeBedList extends StatelessWidget {
  const _FreeBedList({required this.beds});

  final List<FreeBed> beds;

  @override
  Widget build(BuildContext context) {
    // freeBedOptions already arrives in floor, room, bed order, so a sequential grouping keeps
    // it — no second sort, and the storeys come out in the order you would climb them.
    final floors = <int?, List<FreeBed>>{};
    for (final option in beds) {
      floors.putIfAbsent(option.floorNumber, () => []).add(option);
    }

    return beds.isEmpty
          ? const EmptyState(
              icon: Icons.bed_outlined,
              title: 'Every bed is taken',
              detail: 'Free one by checking a resident out, or ask the owner to add rooms.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in floors.entries) ...[
                  SectionLabel(
                    label: entry.key == null ? 'Elsewhere' : 'Floor ${entry.key}',
                    trailing: CapsLabel(
                      '${entry.value.length} free',
                      tone: NivoraColors.success,
                      dot: true,
                    ),
                  ),
                  for (final option in entry.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.xs),
                      child: TapRow(
                        onTap: () => Navigator.of(context).pop(option),
                        semanticLabel: '${option.label}, free',
                        child: Row(
                          children: [
                            const IconBadge(
                              icon: Icons.bed_outlined,
                              tone: NivoraColors.success,
                            ),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    option.label,
                                    style: Theme.of(context).textTheme.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: Space.xxs / 2),
                                  const CapsLabel(
                                    'Available now',
                                    tone: NivoraColors.success,
                                    dot: true,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: IconSize.lg),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            );
  }
}

/// Residents who are registered but not in a bed.
///
/// assign-bed-select-student.png's row: the avatar, the name, and a glyphed line of facts under
/// it. The mockup's facts are a course and a student number; public.students has neither, so the
/// two it does have — the phone that is also their login, and the day they joined — take the
/// same place.
/// Reads its own data for the same reason [FreeBedPicker] does.
///
/// `studentsAwaitingBedProvider` is the ONE-await shape and so could never throw
/// UnmountedRefException the way the bed options provider did — but a `ref.read(….future)` in
/// front of the sheet still swallowed every real failure into the zone, and still made the tap
/// do nothing for the length of a request. Same rule, same fix, and now the two pickers behave
/// identically when the network is bad, which is worth more than either fix alone.
class _AwaitingBedPicker extends ConsumerWidget {
  const _AwaitingBedPicker({required this.hostelId, this.bedLabel});

  final String hostelId;

  /// Null when the flow started from a person rather than from a bed.
  final String? bedLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(studentsAwaitingBedProvider(hostelId));
    final loaded = waiting.value;

    return SheetBody(
      title: bedLabel == null ? 'Who needs a bed?' : 'Who goes in $bedLabel?',
      subtitle: loaded == null || loaded.isEmpty ? null : '${loaded.length} awaiting a bed',
      child: AsyncSection<List<Student>>(
        value: waiting,
        onRetry: () => ref.invalidate(studentsAwaitingBedProvider(hostelId)),
        builder: (students) => _AwaitingBedList(students: students),
      ),
    );
  }
}

class _AwaitingBedList extends StatelessWidget {
  const _AwaitingBedList({required this.students});

  final List<Student> students;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return students.isEmpty
          ? const EmptyState(
              icon: Icons.how_to_reg_outlined,
              title: 'Everyone has a bed',
              detail: 'Register a new resident, or move someone here from another room.',
              tone: NivoraColors.success,
            )
          : Column(
              children: [
                for (final student in students)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: TapRow(
                      onTap: () => Navigator.of(context).pop(student),
                      semanticLabel: '${student.fullName}, awaiting a bed',
                      child: Row(
                        children: [
                          Avatar(name: student.fullName),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(student.fullName,
                                    style: t.textTheme.titleMedium,
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: Space.xxs / 2),
                                MetaLine([
                                  (Icons.phone_outlined, student.phone),
                                  (
                                    Icons.event_outlined,
                                    'joined ${shortDate(student.dateOfJoining)}',
                                  ),
                                ]),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: IconSize.lg),
                        ],
                      ),
                    ),
                  ),
              ],
            );
  }
}

/// A destructive or surprising action, spelled out before it happens.
///
/// Says what WILL happen in specifics — which bed, whose login — rather than "are you sure?".
/// A warden who has read "their login is deactivated" once will not be surprised by it later.
///
/// THE SHAPE IS move-out-clearance.png's: the consequence carried by a haloed glyph in the
/// action's own colour, the sentence under it, and a filled button that is coloured only when
/// it is genuinely destructive. That button used to take `backgroundColor: tone` with a
/// canonical #DC3F3F and the theme's default label on top of it — dark violet on red. This uses
/// the design's own pairing instead: `error-container` #93000A with `on-error-container`
/// #FFDAD6, 7.24:1, which is exactly the dark-red "Settle Dues" the mockup draws.
class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.tone,
    this.icon,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final Color tone;

  /// Overrides the glyph the tone would otherwise pick. "Cancel the deletion" is a
  /// confirmation of something PROTECTIVE, and a question mark reads as hesitancy where a
  /// shield reads as what the button does.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final destructive = tone == NivoraColors.error;
    return SheetBody(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: StateHalo(
              icon: icon ??
                  (destructive ? Icons.logout_rounded : Icons.help_outline_rounded),
              tone: tone,
            ),
          ),
          const SizedBox(height: Space.md),
          Text(body, style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: Space.lg),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: t.colorScheme.errorContainer,
                    foregroundColor: t.colorScheme.onErrorContainer,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
          const SizedBox(height: Space.xs),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
