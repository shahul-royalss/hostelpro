library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
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

/// Choose a bed for [student]. Returns true if the bed changed.
Future<bool> showAssignBedSheet(
  BuildContext context,
  WidgetRef ref, {
  required Student student,
}) async {
  final hostelId = student.hostelId;
  final beds = await ref.read(freeBedOptionsProvider(hostelId).future);
  if (!context.mounted) return false;

  final chosen = await showGlassSheet<FreeBed>(
    context: context,
    builder: (_) => FreeBedPicker(
      beds: beds,
      title: student.hasBed ? 'Move ${student.fullName}' : 'Assign a bed',
      subtitle: '${beds.length} free',
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
  final waiting = await ref.read(studentsAwaitingBedProvider(hostelId).future);
  if (!context.mounted) return false;

  final chosen = await showGlassSheet<Student>(
    context: context,
    builder: (_) => _AwaitingBedPicker(students: waiting),
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
  final waiting = await ref.read(studentsAwaitingBedProvider(bed.hostelId).future);
  if (!context.mounted) return false;

  final chosen = await showGlassSheet<Student>(
    context: context,
    builder: (_) => _AwaitingBedPicker(students: waiting, bedLabel: bedLabel),
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
/// Goes through wd_vacate_student, which frees the bed and deactivates the login in ONE
/// transaction. Doing it as three client updates leaves a bed nobody can be assigned to and an
/// account that can still sign in if the connection drops in between — see
/// StudentRepository.vacate.
Future<bool> showCheckOutSheet(
  BuildContext context,
  WidgetRef ref, {
  required Student student,
}) async {
  final confirmed = await showGlassSheet<bool>(
    context: context,
    builder: (_) => _ConfirmSheet(
      title: 'Check out ${student.fullName}?',
      body: 'Their bed is freed, their login is deactivated and no further payments can be '
          'recorded against them. The record and its history stay — this is not a deletion.',
      confirmLabel: 'Check out',
      tone: NivoraColors.error,
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final ok = await runAction(
    context,
    success: '${student.fullName} checked out',
    action: () => ref.read(studentRepositoryProvider).vacate(student.id),
  );
  if (ok) refreshResidents(ref);
  return ok;
}

// ─────────────────────────────────────────────────────────────────────────────
// PICKERS
// ─────────────────────────────────────────────────────────────────────────────

/// Every free bed, in the order a warden walks the building.
class FreeBedPicker extends StatelessWidget {
  const FreeBedPicker({super.key, required this.beds, required this.title, this.subtitle});

  final List<FreeBed> beds;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SheetBody(
      title: title,
      subtitle: subtitle,
      child: beds.isEmpty
          ? const EmptyState(
              icon: Icons.bed_outlined,
              title: 'Every bed is taken',
              detail: 'Free one by checking a resident out, or ask the owner to add rooms.',
            )
          : Column(
              children: [
                for (final option in beds)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: TapRow(
                      onTap: () => Navigator.of(context).pop(option),
                      child: Row(
                        children: [
                          const Icon(Icons.bed_outlined, size: IconSize.lg),
                          const SizedBox(width: Space.sm),
                          Expanded(child: Text(option.label, style: t.textTheme.titleMedium)),
                          if (option.floorNumber != null)
                            Text('Floor ${option.floorNumber}', style: t.textTheme.bodySmall),
                          const SizedBox(width: Space.xs),
                          const Icon(Icons.chevron_right_rounded, size: IconSize.lg),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Residents who are registered but not in a bed.
class _AwaitingBedPicker extends StatelessWidget {
  const _AwaitingBedPicker({required this.students, this.bedLabel});
  final List<Student> students;

  /// Null when the flow started from a person rather than from a bed.
  final String? bedLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SheetBody(
      title: bedLabel == null ? 'Who needs a bed?' : 'Who goes in $bedLabel?',
      subtitle: students.isEmpty ? null : '${students.length} awaiting a bed',
      child: students.isEmpty
          ? const EmptyState(
              icon: Icons.how_to_reg_outlined,
              title: 'Everyone has a bed',
              detail: 'Register a new resident, or move someone here from another room.',
            )
          : Column(
              children: [
                for (final student in students)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: TapRow(
                      onTap: () => Navigator.of(context).pop(student),
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
                                Text('${student.phone} · joined ${shortDate(student.dateOfJoining)}',
                                    style: t.textTheme.bodySmall,
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: IconSize.lg),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// A destructive or surprising action, spelled out before it happens.
///
/// Says what WILL happen in specifics — which bed, whose login — rather than "are you sure?".
/// A warden who has read "their login is deactivated" once will not be surprised by it later.
class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.tone,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SheetBody(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(body, style: t.textTheme.bodyMedium),
          const SizedBox(height: Space.lg),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: tone),
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
