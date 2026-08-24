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
          padding: EdgeInsets.symmetric(vertical: Space.xxl),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
      trailing: StatusPill(status: student.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (resident) ...[
            Row(
              children: [
                Expanded(
                  child: _Action(
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
                const SizedBox(width: Space.xs),
                Expanded(
                  child: _Action(
                    icon: Icons.logout_rounded,
                    label: 'Check out',
                    tone: NivoraColors.error,
                    onTap: () async {
                      final done = await showCheckOutSheet(context, ref, student: student);
                      // The sheet is showing a resident who is no longer one; close it rather
                      // than leaving actions on screen that will now all be refused.
                      if (done && context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
          ],

          const SectionLabel(label: 'Placement'),
          _Placement(student: student),

          const SectionLabel(label: 'Details'),
          DetailRow(
            label: 'Monthly rent',
            value: money(student.monthlyFee),
            icon: Icons.currency_rupee_rounded,
          ),
          DetailRow(
            label: 'Joined',
            value: shortDate(student.dateOfJoining),
            icon: Icons.event_outlined,
          ),
          if (student.email != null)
            DetailRow(label: 'Email', value: student.email!, icon: Icons.alternate_email_rounded),
          if (student.guardianName != null)
            DetailRow(
              label: 'Guardian',
              value: student.guardianPhone == null
                  ? student.guardianName!
                  : '${student.guardianName!} · ${student.guardianPhone!}',
              icon: Icons.escalator_warning_outlined,
            ),
          if (student.permanentAddress != null)
            DetailRow(
              label: 'Address',
              value: student.permanentAddress!,
              icon: Icons.home_outlined,
            ),
          if (student.vacatedAt != null)
            DetailRow(
              label: 'Checked out',
              value: shortDate(student.vacatedAt!),
              icon: Icons.logout_rounded,
            ),
          if (student.userId == null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'No app login is linked to this resident. Accounts are issued from the web '
                'console.',
                style: t.textTheme.bodySmall,
              ),
            ),

          const SectionLabel(label: 'Rent history'),
          _FeeHistory(studentId: student.id),
        ],
      ),
    );
  }
}

/// Where this resident sleeps, resolved from the two tables that actually know.
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
    final roomId = student.roomId;
    if (roomId == null) {
      return DetailRow(
        label: 'Bed',
        value: student.isResident ? 'Not assigned yet' : 'Released on check-out',
        icon: Icons.bed_outlined,
      );
    }

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

    // Whichever half has not arrived is simply left out rather than replaced with a placeholder
    // number. "Room 101" while the bed number loads is true; "Room 101 · Bed 0" is not.
    final parts = [
      if (roomNumber != null) 'Room $roomNumber',
      if (bedNumber != null) 'Bed $bedNumber',
    ];
    return DetailRow(
      label: 'Bed',
      value: parts.isEmpty ? 'Placed' : parts.join(' · '),
      icon: Icons.bed_outlined,
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
          child: SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
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
                    SizedBox(
                      width: 108,
                      child: Text(monthLabel(row.periodMonth), style: t.textTheme.bodyMedium),
                    ),
                    Expanded(
                      child: Text(
                        row.balance > 0
                            ? '${money(row.amountPaid)} of ${money(row.amountDue)}'
                            : money(row.amountPaid),
                        style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface),
                      ),
                    ),
                    StatusPill(status: row.status, dense: true),
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

/// One of the three things a warden does to a resident.
class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.tone});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone ?? t.colorScheme.primary;
    return Material(
      color: accent.withValues(alpha: 0.10),
      borderRadius: Radii.rControl,
      child: InkWell(
        borderRadius: Radii.rControl,
        onTap: onTap,
        child: Container(
          height: 64,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(height: Space.xxs),
              Text(
                label,
                style: t.textTheme.labelSmall?.copyWith(color: accent, letterSpacing: 0),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
