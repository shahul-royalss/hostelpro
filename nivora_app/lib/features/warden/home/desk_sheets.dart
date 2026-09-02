library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/glass/glass.dart';
import '../actions/sheet_scaffold.dart';
import '../data/warden_models.dart';
import '../data/warden_providers.dart';
import '../students/student_sheet.dart';
import '../widgets/warden_ui.dart';

/// The two queues that live on the warden's desk rather than in a tab: leave requests waiting
/// for a decision, and visitors who have not signed out.
///
/// They are sheets, not tabs, because both are usually empty and neither is somewhere a warden
/// goes — they are things that arrive. The home screen counts them; opening the count is how you
/// deal with them.

// ─────────────────────────────────────────────────────────────────────────────
// LEAVE REQUESTS
// ─────────────────────────────────────────────────────────────────────────────

/// Approve or reject leave, one tap each.
///
/// NO DECISION NOTE IS ASKED FOR, deliberately. public.leaves.decision_note is nullable, the
/// resident is notified of the outcome by app.leaves_after_change either way, and a warden
/// standing in a corridor deciding four requests will type nothing into four text fields — they
/// will put the phone away instead, and the requests stay pending. A note can be added from the
/// web console where there is a keyboard.
///
/// The decision is guarded server-side against a second warden: WardenRepository.decideLeave
/// only matches rows still `pending`, so whoever gets there second is told the request has
/// already been decided rather than overwriting a notification that has gone out.
Future<void> showLeavesSheet(BuildContext context, {required String hostelId}) {
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _LeavesSheet(hostelId: hostelId),
  );
}

class _LeavesSheet extends ConsumerWidget {
  const _LeavesSheet({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaves = ref.watch(pendingLeavesProvider(hostelId));

    return SheetBody(
      title: 'Leave requests',
      subtitle: leaves.value == null
          ? null
          : '${leaves.requireValue.length} awaiting a decision',
      child: AsyncSection<List<LeaveRequest>>(
        value: leaves,
        onRetry: () => ref.invalidate(pendingLeavesProvider(hostelId)),
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.event_available_outlined,
              title: 'Nothing to decide',
              detail: 'Every leave request has been answered.',
              tone: NivoraColors.success,
            );
          }
          return Column(
            children: [
              for (final leave in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: _LeaveRow(leave: leave),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LeaveRow extends ConsumerStatefulWidget {
  const _LeaveRow({required this.leave});
  final LeaveRequest leave;

  @override
  ConsumerState<_LeaveRow> createState() => _LeaveRowState();
}

class _LeaveRowState extends ConsumerState<_LeaveRow> {
  bool _busy = false;

  Future<void> _decide(LeaveStatus decision) async {
    setState(() => _busy = true);
    final name = widget.leave.studentName ?? 'The resident';
    final ok = await runAction(
      context,
      success: decision == LeaveStatus.approved
          ? 'Leave approved for $name'
          : 'Leave rejected for $name',
      action: () => ref.read(wardenRepositoryProvider).decideLeave(
            leaveId: widget.leave.id,
            decision: decision,
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) refreshLeaves(ref);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final leave = widget.leave;
    // The name comes from an embedded select on students and is null only if that row was not
    // readable. Saying so is better than printing a raw uuid at somebody.
    final name = leave.studentName ?? 'Resident';

    // warden-dashboard.png's "Pending Leaves" row: the avatar, the name, the dates as a glyphed
    // line under it, and the decision as a coral cross beside a mint tick.
    //
    // The two buttons keep their WORDS. The mockup's are bare icons, and a tap that notifies a
    // resident and cannot be taken back is not a tap to leave unlabelled — a warden deciding
    // four requests one-handed in a corridor should not have to remember which glyph is which.
    // The icons are the mockup's; the labels are what makes them safe.
    return TapRow(
      onTap: () => showStudentSheet(context, studentId: leave.studentId),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(name: name, tone: NivoraColors.warning),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: t.textTheme.titleMedium,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: Space.xxs / 2),
                    MetaLine([
                      (
                        Icons.event_outlined,
                        '${shortDate(leave.fromDate)} → ${shortDate(leave.toDate)}',
                      ),
                      (
                        Icons.nightlight_outlined,
                        '${leave.nights} night${leave.nights == 1 ? '' : 's'}',
                      ),
                    ]),
                  ],
                ),
              ),
              CapsLabel(age(leave.createdAt)),
            ],
          ),
          if (leave.reason != null) ...[
            const SizedBox(height: Space.sm),
            Text(leave.reason!, style: t.textTheme.bodyMedium),
          ],
          const SizedBox(height: Space.sm),
          if (_busy)
            const InlineSpinner(replacing: 48)
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    // Here the colour DOES carry meaning — this is the destructive half of a
                    // pair — so it stays, resolved for the theme (5.83:1 light, 6.98:1 dark).
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.tones.error,
                      side: BorderSide(
                        color: context.tones.chipBorder(context.tones.error),
                        width: Strokes.hairline,
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: IconSize.md),
                    label: const Text('Reject'),
                    onPressed: () => _decide(LeaveStatus.rejected),
                  ),
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  // Approve is the primary action and the theme already says what that looks
                  // like. Repainting it #188D43 put white on green at 4.26:1.
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_rounded, size: IconSize.md),
                    label: const Text('Approve'),
                    onPressed: () => _decide(LeaveStatus.approved),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VISITORS
// ─────────────────────────────────────────────────────────────────────────────

/// Who is in the building, and signing them out again.
///
/// LOGGING A NEW VISITOR IS NOT HERE. public.visitors_insert admits the warden, so it is
/// permitted — it is simply not built in this release, and pretending otherwise with a disabled
/// button would be worse than its absence. Check-in is done from the web console for now.
Future<void> showVisitorsSheet(BuildContext context, {required String hostelId}) {
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _VisitorsSheet(hostelId: hostelId),
  );
}

class _VisitorsSheet extends ConsumerWidget {
  const _VisitorsSheet({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitors = ref.watch(visitorsOnSiteProvider(hostelId));

    return SheetBody(
      title: 'Visitors on site',
      subtitle: visitors.value == null
          ? null
          : '${visitors.requireValue.length} not signed out',
      child: AsyncSection<List<VisitorLog>>(
        value: visitors,
        onRetry: () => ref.invalidate(visitorsOnSiteProvider(hostelId)),
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.door_front_door_outlined,
              title: 'Nobody signed in',
              detail: 'Every visitor logged today has signed out again.',
              tone: NivoraColors.success,
            );
          }
          return Column(
            children: [
              for (final visitor in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: _VisitorRow(visitor: visitor),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VisitorRow extends ConsumerStatefulWidget {
  const _VisitorRow({required this.visitor});
  final VisitorLog visitor;

  @override
  ConsumerState<_VisitorRow> createState() => _VisitorRowState();
}

class _VisitorRowState extends ConsumerState<_VisitorRow> {
  bool _busy = false;

  Future<void> _checkOut() async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      success: '${widget.visitor.visitorName} signed out',
      action: () => ref.read(wardenRepositoryProvider).checkOutVisitor(widget.visitor.id),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) refreshVisitors(ref);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final visitor = widget.visitor;
    final here = DateTime.now().difference(visitor.checkInAt.toLocal());
    final duration = here.inHours >= 1
        ? '${here.inHours}h ${here.inMinutes.remainder(60)}m'
        : '${here.inMinutes}m';

    return TapRow(
      child: Row(
        children: [
          Avatar(name: visitor.visitorName, tone: NivoraColors.info),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(visitor.visitorName, style: t.textTheme.titleMedium,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.xxs / 2),
                MetaLine([
                  (Icons.badge_outlined, visitor.relation),
                  (
                    Icons.person_outline_rounded,
                    visitor.studentName == null ? null : 'for ${visitor.studentName}',
                  ),
                  (
                    Icons.schedule_rounded,
                    'in since ${timeOfDay(visitor.checkInAt)} · $duration',
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          if (_busy)
            const InlineSpinner()
          else
            // Width 96 so it hugs its label instead of inheriting the theme's full-bleed
            // minimum; the height goes back to 48, which is the tap target a warden signing
            // somebody out one-handed in a doorway actually needs.
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(96, 48)),
              onPressed: _checkOut,
              child: const Text('Sign out'),
            ),
        ],
      ),
    );
  }
}
