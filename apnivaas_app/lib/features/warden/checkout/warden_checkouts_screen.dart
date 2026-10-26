/// Check-out requests for one PG (round 3, R6): the warden — or the owner — accepts with a date
/// or declines with a note. Accepting on or before today runs the vacate flow at once; a later
/// date is vacated automatically that morning (docs/round3-api.md §7).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/stay.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/stay_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../../common/form_parts.dart';
import '../../student/stay_screens.dart' show stayErrorText, toneForStatus;
import '../../student/widgets/format.dart';

/// The row on the Students tab that opens the list. Hidden while nothing is pending.
class CheckoutRequestsEntry extends ConsumerWidget {
  const CheckoutRequestsEntry({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);
    final count = ref.watch(pendingCheckoutCountProvider) ?? 0;
    if (hostelId == null || count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: ListRowCard(
        icon: ClayIcons.moveOut,
        title: 'Check-out requests',
        subtitle: count == 1
            ? '1 resident wants to check out'
            : '$count residents want to check out',
        trailing: CountBadge(count: count, semanticLabel: '$count waiting'),
        semanticLabel: 'Check-out requests, $count waiting',
        onTap: () => Navigator.of(context).push(CheckoutRequestsScreen.route(hostelId)),
      ),
    );
  }
}

class CheckoutRequestsScreen extends ConsumerWidget {
  const CheckoutRequestsScreen({super.key, required this.hostelId});

  final String hostelId;

  static Route<void> route(String hostelId) =>
      MaterialPageRoute<void>(builder: (_) => CheckoutRequestsScreen(hostelId: hostelId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = checkoutRequestsProvider(hostelId);
    final requests = ref.watch(provider);

    Future<void> refresh() async {
      ref.invalidate(provider);
      try {
        await ref.read(provider.future).timeout(const Duration(seconds: 20));
      } catch (_) {
        // Drawn by the list below.
      }
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(
            title: 'Check-outs',
            subtitle: 'Residents asking to leave',
            leading: HeaderBackButton(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md, Space.huge),
                children: [
                  switch (requests) {
                    AsyncData(:final value) when value.isEmpty => const EmptyState(
                        icon: ClayIcons.moveOut,
                        title: 'No check-out requests',
                        body: 'When a resident asks to check out in the app, it appears here '
                            'for you to accept or decline.',
                      ),
                    AsyncData(:final value) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final r in value) ...[
                            CheckoutRequestCard(hostelId: hostelId, request: r),
                            const SizedBox(height: Space.md),
                          ],
                        ],
                      ),
                    AsyncError(:final error) => EmptyState.error(
                        title: 'Could not load the requests',
                        message: stayErrorText(error),
                        onRetry: refresh,
                      ),
                    _ => const ListSkeleton(rows: 3, semanticLabel: 'Loading check-out requests'),
                  },
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutRequestCard extends ConsumerStatefulWidget {
  const CheckoutRequestCard({super.key, required this.hostelId, required this.request});

  final String hostelId;
  final CheckoutRequestRow request;

  @override
  ConsumerState<CheckoutRequestCard> createState() => _CheckoutRequestCardState();
}

class _CheckoutRequestCardState extends ConsumerState<CheckoutRequestCard> {
  bool _busy = false;

  Future<void> _decide(bool accept) async {
    final r = widget.request;
    final messenger = ScaffoldMessenger.of(context);
    final answer = await showModalBottomSheet<_Decision>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DecisionSheet(request: r, accept: accept),
    );
    if (answer == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(stayApiProvider).decideCheckout(
            r.requestId,
            accept: accept,
            checkoutDate: answer.date,
            note: answer.note,
          );
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(!accept
            ? 'Request declined. ${r.fullName} has been told.'
            : result?.status == CheckoutStatus.completed
                ? '${r.fullName} is checked out and the bed is free.'
                : '${r.fullName} will be checked out on '
                    '${dayLabel(result?.checkoutDate ?? answer.date ?? r.preferredDate)}.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Motion.readMessage,
        content: Text(stayErrorText(e)),
      ));
    } finally {
      ref.invalidate(checkoutRequestsProvider(widget.hostelId));
      ref.invalidate(ownerCheckoutSummaryProvider);
      ref.invalidate(studentsProvider);
      ref.invalidate(hostelStatsProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = widget.request;
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final where = [
      if (r.roomNumber != null) 'Room ${r.roomNumber}',
      if (r.bedNumber != null) 'bed ${r.bedNumber}',
    ].join(', ');
    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(r.fullName, style: t.textTheme.titleMedium),
              StatusChip(label: r.status.label, tone: toneForStatus(r.status.name), dot: true),
            ],
          ),
          if (where.isNotEmpty || r.phone != null) ...[
            const SizedBox(height: Space.xxs),
            Text([where, ?r.phone].where((s) => s.isNotEmpty).join(' · '), style: muted),
          ],
          const SizedBox(height: Space.sm),
          Text('Preferred date: ${dayLabel(r.preferredDate)}', style: t.textTheme.bodyMedium),
          if (r.checkoutDate != null)
            Text('Check-out date: ${dayLabel(r.checkoutDate!)}', style: t.textTheme.bodyMedium),
          if (r.reason != null) ...[
            const SizedBox(height: Space.xxs),
            Text('“${r.reason!}”', style: t.textTheme.bodyMedium),
          ],
          if (r.decisionNote != null) ...[
            const SizedBox(height: Space.xxs),
            Text('Note: ${r.decisionNote!}', style: muted),
          ],
          if (r.status == CheckoutStatus.pending) ...[
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Decline'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _decide(true),
                  child: Text(_busy ? 'Saving…' : 'Accept'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Decision {
  const _Decision({this.date, this.note});
  final DateTime? date;
  final String? note;
}

class _DecisionSheet extends StatefulWidget {
  const _DecisionSheet({required this.request, required this.accept});
  final CheckoutRequestRow request;
  final bool accept;

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  final _note = TextEditingController();
  late DateTime _date = _clamp(widget.request.preferredDate);
  String? _error;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _clamp(DateTime d) {
    final first = _today.subtract(const Duration(days: 30));
    final last = _today.add(const Duration(days: 90));
    return d.isBefore(first) ? first : (d.isAfter(last) ? last : d);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _today.subtract(const Duration(days: 30)),
      lastDate: _today.add(const Duration(days: 90)),
      helpText: 'Check-out date',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = widget.request;
    final now = !_date.isAfter(_today);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          Space.lg, 0, Space.lg, Space.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitle(
              title: widget.accept ? 'Accept check-out' : 'Decline check-out',
              subtitle: widget.accept
                  ? 'Choose the day ${r.fullName} leaves. Their bed is freed and later rent '
                      'stops from that day.'
                  : '${r.fullName} will be told. Add a note if it helps.',
            ),
            const SizedBox(height: Space.md),
            if (widget.accept) ...[
              InkWell(
                onTap: _pick,
                borderRadius: BorderRadius.circular(Radii.control),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Check-out date',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(dayLabel(_date)),
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                now
                    ? 'This checks them out now: the account is unlinked and the bed is freed.'
                    : 'They stay until then; Apnivaas checks them out that morning.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Space.sm),
            ],
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: Space.sm),
            BusyFilledButton(
              label: widget.accept ? (now ? 'Check out now' : 'Accept') : 'Decline',
              danger: !widget.accept,
              onPressed: () {
                if (_note.text.trim().length > 300) {
                  setState(() => _error = 'Keep the note under 300 characters.');
                  return;
                }
                Navigator.of(context).pop(_Decision(
                  date: widget.accept ? _date : null,
                  note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                ));
              },
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}
