library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
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

/// Who is in the building, signing them in, and signing them out again.
///
/// Check-in lives in this sheet's header rather than as a separate desk tile: the warden who
/// opens "Visitors on site" is the one standing at the gate, and the person in front of them is
/// either arriving or leaving. Both actions belong on the one screen that shows who is here.
/// See [showCheckInVisitorSheet].
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
      trailing: TextButton.icon(
        onPressed: () => showCheckInVisitorSheet(context, hostelId: hostelId),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: IconSize.sm),
        label: const Text('Sign in'),
      ),
      child: AsyncSection<List<VisitorLog>>(
        value: visitors,
        onRetry: () => ref.invalidate(visitorsOnSiteProvider(hostelId)),
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.door_front_door_outlined,
              title: 'Nobody signed in',
              detail: 'When a visitor arrives, use Sign in above to log who they are here for.',
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

// ─────────────────────────────────────────────────────────────────────────────
// SIGNING A VISITOR IN
// ─────────────────────────────────────────────────────────────────────────────

/// Who has arrived, and which resident they are here for.
///
/// This was "done from the web console for now" until the client demo made that sentence
/// untenable: a warden standing at the gate with a phone is the whole reason the app exists,
/// and telling them to go and find a laptop is not a feature gap, it is the product not
/// working. The insert is admitted by visitors_insert for the warden's own hostel, and the
/// resident's tenancy is checked by app.assert_student_in_hostel BEFORE INSERT — so the only
/// thing this sheet has to get right is asking the two questions in the order a person would.
Future<void> showCheckInVisitorSheet(BuildContext context, {required String hostelId}) {
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _CheckInVisitorSheet(hostelId: hostelId),
  );
}

class _CheckInVisitorSheet extends ConsumerStatefulWidget {
  const _CheckInVisitorSheet({required this.hostelId});
  final String hostelId;

  @override
  ConsumerState<_CheckInVisitorSheet> createState() => _CheckInVisitorSheetState();
}

class _CheckInVisitorSheetState extends ConsumerState<_CheckInVisitorSheet> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _phone = TextEditingController();
  String _term = '';
  Student? _resident;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _relation.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final resident = _resident;
    if (resident == null) {
      setState(() => _error = 'Choose the resident they are here to see.');
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = "Enter the visitor's name.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await runAction(
      context,
      success: '${_name.text.trim()} signed in for ${resident.fullName}',
      action: () => ref.read(wardenRepositoryProvider).checkInVisitor(
            hostelId: widget.hostelId,
            studentId: resident.id,
            visitorName: _name.text,
            relation: _relation.text,
            visitorPhone: _phone.text,
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      refreshVisitors(ref);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Active residents only: somebody on leave or vacated is not in the building to be visited.
    // The search is Postgres's `ilike` over name and phone, exactly as the Residents tab does
    // it, so a warden who knows the roster by phone number is served too.
    final query = StudentQuery(
      hostelId: widget.hostelId,
      search: _term.isEmpty ? null : _term,
      status: StudentStatus.active,
    );
    final residents = ref.watch(studentsProvider(query));
    final chosen = _resident;

    return SheetBody(
      title: 'Sign in a visitor',
      subtitle: chosen == null ? 'Who are they here to see?' : 'Visiting ${chosen.fullName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            enabled: !_busy,
            onChanged: (v) => setState(() => _term = v.trim()),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'Find the resident',
              hintText: 'Name or phone',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: Space.sm),
          residents.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Space.md),
              child: Center(child: InlineSpinner()),
            ),
            error: (e, _) => Text(
              AppFailure.from(e).message,
              style: t.textTheme.bodySmall?.copyWith(color: context.tones.error),
            ),
            data: (page) => page.items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.sm),
                    child: Text(
                      _term.isEmpty
                          ? 'No active residents in this hostel yet.'
                          : 'No resident matches "$_term".',
                      style: t.textTheme.bodyMedium,
                    ),
                  )
                : Column(
                    children: [
                      // Eight is the most a sheet can show above the form without the form
                      // leaving the screen; the search narrows it long before that matters.
                      for (final s in page.items.take(8))
                        _ResidentRow(
                          student: s,
                          selected: chosen?.id == s.id,
                          onTap: _busy ? null : () => setState(() => _resident = s),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: "Visitor's name",
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _relation,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Relation',
                    hintText: 'Father, friend',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: TextField(
                  controller: _phone,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.call_outlined),
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.sm),
            Text(_error!, style: t.textTheme.bodySmall?.copyWith(color: context.tones.error)),
          ],
          const SizedBox(height: Space.md),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: IconSize.md, height: IconSize.md, child: InlineSpinner())
                : const Icon(Icons.login_rounded, size: IconSize.sm),
            label: Text(_busy ? 'Signing in' : 'Sign in'),
          ),
        ],
      ),
    );
  }
}

class _ResidentRow extends StatelessWidget {
  const _ResidentRow({required this.student, required this.selected, required this.onTap});
  final Student student;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = selected ? context.tones.resolve(NivoraColors.brand) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xxs),
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.rControl,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xs),
          child: Row(
            children: [
              Avatar(name: student.fullName, tone: NivoraColors.people),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(student.fullName,
                        style: t.textTheme.titleMedium?.copyWith(color: tone),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(student.phone, style: t.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: IconSize.lg,
                color: tone ?? t.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
