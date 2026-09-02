library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../actions/assign_bed_sheet.dart';
import '../actions/record_payment_sheet.dart';
import '../actions/sheet_scaffold.dart';
import '../actions/student_credentials_dialog.dart';
import '../data/warden_providers.dart';
import '../widgets/warden_ui.dart';

/// One resident: who they are, where they sleep, what they owe, and the three things a warden
/// does about it.
///
/// READ FRESH FROM public.students, not handed down from the list that opened it. The row in a
/// list is a snapshot from whenever that page was fetched; the sheet is where somebody acts, so
/// it re-reads. That also makes it correct from every entry point — a bed on the room grid, a
/// row on the fee ledger, a name in the resident list — without each caller carrying a full
/// Student around.
Future<void> showStudentSheet(BuildContext context, {required String studentId}) {
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _StudentSheet(studentId: studentId),
  );
}

class _StudentSheet extends ConsumerWidget {
  const _StudentSheet({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(studentProvider(studentId));

    return AsyncSection<Student?>(
      value: student,
      onRetry: () => ref.invalidate(studentProvider(studentId)),
      loading: const SheetBody(
        title: 'Resident',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: Space.md),
          child: SkeletonBlock(lines: 3),
        ),
      ),
      builder: (row) {
        if (row == null) {
          return const SheetBody(
            title: 'Resident',
            child: EmptyState(
              icon: Icons.person_off_outlined,
              title: 'That record is not visible',
              detail: 'It may have been removed, or it belongs to another hostel.',
            ),
          );
        }
        return _Loaded(student: row);
      },
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final month = ref.watch(selectedMonthProvider);
    final resident = student.isResident;

    return SheetBody(
      title: student.fullName,
      subtitle: student.phone,
      // `sheet-header` (4:796): avatar, name, second line, state badge hard right.
      leading: Avatar(
        name: student.fullName,
        tone: toneFor(context, student.status),
        size: Space.xxxl,
      ),
      trailing: StatusPill(status: student.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (resident) ...[
            // resident-profile.png pairs TWO buttons under the name — one quiet, one filled —
            // and puts the destructive one alone at the very bottom of the page as a coral
            // outline. That is the shape below: the two everyday actions here, check-out after
            // everything a warden should have read first.
            Row(
              children: [
                Expanded(
                  child: _Action(
                    filled: true,
                    icon: Icons.payments_rounded,
                    label: 'Payment',
                    onTap: () => showRecordPaymentSheet(
                      context,
                      studentId: student.id,
                      studentName: student.fullName,
                      monthlyFee: student.monthlyFee,
                      periodMonth: month,
                    ),
                  ),
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: _Action(
                    icon: student.hasBed ? Icons.swap_horiz_rounded : Icons.bed_rounded,
                    label: student.hasBed ? 'Move bed' : 'Assign bed',
                    onTap: () => showAssignBedSheet(context, ref, student: student),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
          ],

          _Placement(student: student),

          const SectionLabel(label: 'Personal details'),
          DetailRow(
            label: 'Monthly rent',
            value: money(student.monthlyFee),
          ),
          DetailRow(
            label: 'Joined',
            value: shortDate(student.dateOfJoining),
          ),
          if (student.email != null)
            DetailRow(label: 'Email', value: student.email!),
          if (student.guardianName != null)
            DetailRow(
              label: 'Guardian',
              value: student.guardianPhone == null
                  ? student.guardianName!
                  : '${student.guardianName!} · ${student.guardianPhone!}',
            ),
          if (student.permanentAddress != null)
            DetailRow(
              label: 'Address',
              value: student.permanentAddress!,
            ),
          if (student.vacatedAt != null)
            DetailRow(
              label: 'Checked out',
              value: shortDate(student.vacatedAt!),
              tone: NivoraColors.error,
            ),
          if (student.userId == null) ...[
            const SizedBox(height: Space.xs),
            InfoCallout(
              icon: Icons.info_outline_rounded,
              child: Text(
                'No app login is linked to this resident. Accounts are issued from the web '
                'console.',
                style: t.textTheme.bodySmall,
              ),
            ),
          ],

          const SectionLabel(label: 'Rent history'),
          _FeeHistory(studentId: student.id),

          // ── WHAT HAPPENS TO THEIR DETAILS ────────────────────────────────────────────
          // Only for somebody already checked out. For a current resident the question does
          // not arise, and putting a deletion control next to a live tenancy invites the tap
          // nobody meant to make. [ErasureBlock] reads the real stored date itself — see the
          // check-out flow in actions/assign_bed_sheet.dart.
          if (!resident) ...[
            // NOT 'Personal details' — that heading is already above, over the facts
            // themselves. This section is about what HAPPENS to them now the tenancy is over.
            const SectionLabel(label: 'Data deletion'),
            ErasureBlock(student: student),
          ],

          // ── SIGN-IN DETAILS ──────────────────────────────────────────────────────────
          // Only while they still live here: a checked-out login is deactivated, so offering
          // to mint a password for it would be offering something that cannot be used.
          if (resident) ...[
            const SectionLabel(label: 'Sign-in details'),
            _CredentialsBlock(student: student),
          ],

          if (resident) ...[
            const SizedBox(height: Space.lg),
            // The mockup's "Initiate Move-Out / Transfer": full width, coral outline, coral
            // label, and the last thing on the page. Check-out ends a tenancy, deactivates a
            // login and stops a fee ledger; it does not belong in a row of everyday taps.
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.tones.error,
                side: BorderSide(
                  color: context.tones.chipBorder(context.tones.error),
                  width: Strokes.hairline,
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: IconSize.md),
              label: const Text('Check out of the hostel'),
              onPressed: () async {
                final done = await showCheckOutSheet(context, ref, student: student);
                // The sheet is showing a resident who is no longer one; close it rather than
                // leaving actions on screen that will now all be refused.
                if (done && context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Where this resident sleeps — resident-profile.png's CURRENT ASSIGNMENT card.
///
/// The mockup's anatomy exactly: a `label-caps` eyebrow with a bed glyph opposite it, the
/// room and bed as the card's title, a hairline, then the supporting facts underneath. The
/// mockup's second fact is a roommate; this sheet does not read the room's other residents and
/// is not about to start, so the pair here is the check-in date the row already carries.
///
/// students carries room_id and bed_id — ids, not numbers. The room number comes from
/// rpc_room_occupancy (already loaded for the room grid, so usually free) and the bed number
/// from public.beds for that room. Neither is guessed: a resident with no bed says so, which is
/// itself the thing a warden needs to see.
class _Placement extends ConsumerWidget {
  const _Placement({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final roomId = student.roomId;

    String placement;
    if (roomId == null) {
      placement = student.isResident ? 'Not assigned yet' : 'Released on check-out';
    } else {
      final rooms = ref.watch(roomOccupancyProvider(student.hostelId)).value;
      final beds = ref.watch(bedsInRoomProvider(roomId)).value;

      String? roomNumber;
      for (final room in rooms ?? const <RoomOccupancy>[]) {
        if (room.roomId == roomId) {
          roomNumber = room.roomNumber;
          break;
        }
      }
      int? bedNumber;
      for (final bed in beds ?? const <Bed>[]) {
        if (bed.id == student.bedId) {
          bedNumber = bed.bedNumber;
          break;
        }
      }

      // Whichever half has not arrived is simply left out rather than replaced with a
      // placeholder number. "Room 101" while the bed number loads is true; "Room 101 · Bed 0"
      // is not.
      final parts = [
        if (roomNumber != null) 'Room $roomNumber',
        if (bedNumber != null) 'Bed $bedNumber',
      ];
      placement = parts.isEmpty ? 'Placed' : parts.join(' · ');
    }

    return GlassCard(
      padding: const EdgeInsets.all(Space.md),
      semanticLabel: 'Current assignment: $placement',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: CapsLabel('Current assignment')),
              Icon(Icons.bed_outlined, size: IconSize.lg, color: t.colorScheme.primary),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(placement, style: t.textTheme.titleLarge),
          const SizedBox(height: Space.sm),
          Divider(color: t.colorScheme.outlineVariant, height: Strokes.hairline),
          const SizedBox(height: Space.sm),
          MetaLine([
            (Icons.event_outlined, 'Check-in ${shortDate(student.dateOfJoining)}'),
            (Icons.currency_rupee_rounded, '${money(student.monthlyFee)} a month'),
          ]),
        ],
      ),
    );
  }
}

/// The last few months of rent, newest first.
class _FeeHistory extends ConsumerWidget {
  const _FeeHistory({required this.studentId});
  final String studentId;

  static const _shown = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final history = ref.watch(studentFeeHistoryProvider(studentId));

    return AsyncSection<PagedResult<FeePayment>>(
      value: history,
      onRetry: () => ref.invalidate(studentFeeHistoryProvider(studentId)),
      loading: const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.md),
        child: Center(
          child: InlineSpinner(),
        ),
      ),
      builder: (page) {
        if (page.isEmpty) {
          return Text(
            'No payment has been recorded for this resident yet.',
            style: t.textTheme.bodySmall,
          );
        }
        final rows = page.items.take(_shown).toList(growable: false);
        return Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xxs),
                child: Row(
                  children: [
                    // Flex rather than a fixed 108: "September 2026" at 1.4x is wider than
                    // that, and the amount beside it was the half getting squeezed.
                    Expanded(
                      flex: 4,
                      child: Text(monthLabel(row.periodMonth),
                          style: t.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      flex: 5,
                      child: Text(
                        row.balance > 0
                            ? '${money(row.amountPaid)} of ${money(row.amountDue)}'
                            : money(row.amountPaid),
                        style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface),
                      ),
                    ),
                    StatusPill(status: row.status),
                  ],
                ),
              ),
            if (page.items.length > _shown || page.hasMore)
              Padding(
                padding: const EdgeInsets.only(top: Space.xxs),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Earlier months are on the web console.',
                      style: t.textTheme.bodySmall),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One of the two everyday things a warden does to a resident.
///
/// resident-profile.png puts a pair of buttons under the name: one quiet, one filled violet.
/// This used to be a pair of 64dp tinted tiles with the icon stacked over the label, which is
/// a shape the design uses for Quick Actions on a dashboard and nowhere else. A button that
/// looks like a button is also the difference between "I can do this" and "this is a stat".
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The one the design fills. At most one per row.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(icon, size: IconSize.md);
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    return filled
        ? FilledButton.icon(onPressed: onTap, icon: glyph, label: text)
        : OutlinedButton.icon(onPressed: onTap, icon: glyph, label: text);
  }
}

/// Recovering a lost password, and correcting an address.
///
/// THE PASSWORD IS NEVER STORED, so there is nothing here to "show" — only to REPLACE. The
/// owner originally asked for the temporary password to be kept on the student list and read
/// back; that was declined, because a readable password lets any staff member sign in AS a
/// resident and turns a database leak into working logins. Regenerating answers the real
/// problem (the slip got lost) and leaves nothing worth stealing.
class _CredentialsBlock extends ConsumerStatefulWidget {
  const _CredentialsBlock({required this.student});
  final Student student;

  @override
  ConsumerState<_CredentialsBlock> createState() => _CredentialsBlockState();
}

class _CredentialsBlockState extends ConsumerState<_CredentialsBlock> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (e) {
      if (mounted) setState(() => _error = AppFailure.from(e).message);
    } finally {
      // A `finally`, so no path can leave the buttons disabled forever. That exact bug shipped
      // once on the change-password screen and left a dead slab with no way out.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() => _run(() async {
        final creds = await ref
            .read(wardenRepositoryProvider)
            .resetStudentPassword(widget.student.id);
        if (!mounted) return;
        // The same show-once dialog registration uses: copyable, and dismissible only by
        // confirming it has been saved. One place in the app shows a password, and this is it.
        await StudentCredentialsDialog.show(context, credentials: creds);
      });

  Future<void> _editEmail() => _run(() async {
        final next = await showStudentEmailSheet(context, student: widget.student);
        if (next == null || !mounted) return;
        final loginId = await ref
            .read(wardenRepositoryProvider)
            .setStudentEmail(widget.student.id, next.isEmpty ? null : next);
        refreshResidents(ref);
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              // Both consequences, because both surprise people: what they type now, and that
              // the address has to be proved again (users_update_guard clears the old proof).
              'They now sign in as $loginId, and will be asked to verify the new address.',
            ),
          ),
        );
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final error = _error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.student.email?.trim().isNotEmpty ?? false
              ? 'Signs in with ${widget.student.email!.trim()}'
              : 'Signs in with their phone number, ${widget.student.phone}',
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _reset,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: IconSize.md,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.key_rounded, size: IconSize.md),
                label: const Text('New password'),
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _editEmail,
                icon: const Icon(Icons.alternate_email_rounded, size: IconSize.md),
                label: const Text('Edit email'),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: Space.xs),
          Text(error, style: t.textTheme.bodySmall?.copyWith(color: context.tones.error)),
        ],
      ],
    );
  }
}

/// Ask for the resident's email address. Returns the new value, '' to clear it back to a
/// phone-only login, or null if the warden backed out.
///
/// Deliberately a sheet and not an inline field: changing the address changes what the person
/// TYPES to sign in, and clears the proof they had already given. That is worth a decision,
/// not a stray keystroke in a scrolling form.
Future<String?> showStudentEmailSheet(
  BuildContext context, {
  required Student student,
}) {
  final controller = TextEditingController(text: student.email ?? '');
  final formKey = GlobalKey<FormState>();

  return showGlassSheet<String>(
    context: context,
    builder: (sheetContext) {
      final t = Theme.of(sheetContext);
      return Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Email address', style: t.textTheme.titleLarge),
            const SizedBox(height: Space.xxs),
            Text(
              'This is what ${student.fullName} types to sign in. Leaving it empty puts them '
              'back on their phone number, ${student.phone}.',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'name@example.com',
              ),
              validator: (raw) {
                final v = (raw ?? '').trim();
                if (v.isEmpty) return null; // clearing is allowed and meaningful
                // Deliberately loose. The server is the authority on what it will accept, and
                // a clever regex here would only reject addresses that are in fact valid.
                final ok = v.contains('@') &&
                    !v.startsWith('@') &&
                    !v.endsWith('@') &&
                    !v.contains(' ') &&
                    v.split('@').last.contains('.');
                return ok ? null : 'That does not look like an email address.';
              },
            ),
            const SizedBox(height: Space.lg),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.of(sheetContext).pop(controller.text.trim());
              },
              child: const Text('Save address'),
            ),
            const SizedBox(height: Space.xs),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    },
  );
}
