/// New sign-ups and demos (round 3, R7): every self-signed-up owner with their PG, contact,
/// trial dates, plan status and demo request, filtered by date range, plan and demo status.
/// The demo's status is changed with the existing `sa_update_demo_request`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/people.dart' show demoStatuses;
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../shared/clay/clay.dart';
import '../../shared/glass/glass.dart';
import 'data/sa_round3.dart';
import 'sa_demo_requests_screen.dart' show DemoStatusForm;

final _day = DateFormat('d MMM yyyy');
final _slot = DateFormat('EEE d MMM, h a');

String saSentence(Object e) =>
    e is SignupFailure ? e.message : 'Something went wrong. Please try again.';

/// The server returns at most 200 rows per call.
const saMaxRows = 200;

StatusTone saPlanTone(String? s) => switch (s) {
      'paid' || 'manual' => StatusTone.success,
      'trial' => StatusTone.info,
      'expired' => StatusTone.error,
      _ => StatusTone.neutral,
    };

StatusTone saDemoTone(String? s) => switch (s) {
      'confirmed' => StatusTone.info,
      'done' => StatusTone.success,
      'requested' => StatusTone.warning,
      _ => StatusTone.neutral,
    };

class SaSignupsEntry extends StatelessWidget {
  const SaSignupsEntry({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        child: ListRowCard(
          icon: ClayIcons.addTenant,
          title: 'Sign-ups and demos',
          subtitle: 'New owners, their trials and demo requests',
          onTap: () => Navigator.of(context).push(SaSignupsScreen.route()),
        ),
      );
}

/// Date range, then one row of chips per filter. Shared with the deletions list.
class SaDateRangeButton extends StatelessWidget {
  const SaDateRangeButton({super.key, required this.from, required this.to, required this.onChanged});

  final DateTime? from;
  final DateTime? to;
  final void Function(DateTime? from, DateTime? to) onChanged;

  @override
  Widget build(BuildContext context) {
    final label = from == null && to == null
        ? 'Any date'
        : '${from == null ? '…' : _day.format(from!)} – ${to == null ? '…' : _day.format(to!)}';
    return Wrap(
      spacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_rounded, size: IconSize.sm),
          label: Text(label),
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2026),
              lastDate: DateTime(now.year, now.month, now.day),
              initialDateRange:
                  from != null && to != null ? DateTimeRange(start: from!, end: to!) : null,
            );
            if (picked != null) onChanged(picked.start, picked.end);
          },
        ),
        if (from != null || to != null)
          TextButton(onPressed: () => onChanged(null, null), child: const Text('Clear')),
      ],
    );
  }
}

class SaFilterChips extends StatelessWidget {
  const SaFilterChips({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final Map<String, String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.textTheme.labelLarge),
        const SizedBox(height: Space.xxs),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
            for (final e in options.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: selected == e.key,
                onSelected: (_) => onSelected(e.key),
              ),
          ],
        ),
      ],
    );
  }
}

class SaSignupsScreen extends ConsumerStatefulWidget {
  const SaSignupsScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const SaSignupsScreen());

  @override
  ConsumerState<SaSignupsScreen> createState() => _SaSignupsScreenState();
}

class _SaSignupsScreenState extends ConsumerState<SaSignupsScreen> {
  SaSignupQuery _q = const SaSignupQuery();

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(saSignupsProvider(_q));
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(
            title: 'Sign-ups and demos',
            subtitle: page.value == null ? 'Newest first' : '${page.value!.total} owners',
            leading: const HeaderBackButton(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(saSignupsProvider(_q));
                try {
                  await ref.read(saSignupsProvider(_q).future);
                } catch (_) {}
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
                children: [
                  SaDateRangeButton(
                    from: _q.from,
                    to: _q.to,
                    onChanged: (f, t) => setState(
                        () => _q = _q.copyWith(from: () => f, to: () => t, limit: 50)),
                  ),
                  const SizedBox(height: Space.sm),
                  SaFilterChips(
                    label: 'Plan',
                    options: saPlanStatuses,
                    selected: _q.planStatus,
                    onSelected: (v) =>
                        setState(() => _q = _q.copyWith(planStatus: () => v, limit: 50)),
                  ),
                  const SizedBox(height: Space.sm),
                  SaFilterChips(
                    label: 'Demo',
                    options: saDemoFilters,
                    selected: _q.demoStatus,
                    onSelected: (v) =>
                        setState(() => _q = _q.copyWith(demoStatus: () => v, limit: 50)),
                  ),
                  const SizedBox(height: Space.md),
                  switch (page) {
                    AsyncData(:final value) when value.items.isEmpty => const EmptyState(
                        icon: ClayIcons.addTenant,
                        title: 'No sign-ups match',
                        body: 'Owners who create their own account appear here.',
                      ),
                    AsyncData(:final value) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final s in value.items) ...[
                            _SignupCard(signup: s, onDemo: () => _editDemo(s)),
                            const SizedBox(height: Space.sm),
                          ],
                          if (value.total > value.items.length)
                            _q.limit < saMaxRows
                                ? OutlinedButton(
                                    onPressed: () => setState(
                                        () => _q = _q.copyWith(limit: _q.limit + 50)),
                                    child: Text(
                                        'Show more (${value.total - value.items.length} left)'),
                                  )
                                : const InfoNote(
                                    message: 'Showing the newest 200. Narrow the dates to see '
                                        'older sign-ups.',
                                  ),
                        ],
                      ),
                    AsyncError(:final error) => EmptyState.error(
                        message: saSentence(error),
                        onRetry: () => ref.invalidate(saSignupsProvider(_q)),
                      ),
                    _ => const ListSkeleton(rows: 4, semanticLabel: 'Loading sign-ups'),
                  },
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editDemo(SaSignup s) async {
    final id = s.demoId;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await showApnivaasSheet<({String status, String note})>(
      context: context,
      title: s.hostelName ?? 'Demo request',
      subtitle: [s.fullName, ?s.phone].join(' · '),
      builder: (_) => DemoStatusForm(status: s.demoStatus ?? 'requested'),
    );
    if (result == null) return;
    try {
      await ref.read(peopleApiProvider).updateDemoRequest(id, status: result.status, note: result.note);
      ref.invalidate(saSignupsProvider);
      messenger.showSnackBar(
          const SnackBar(content: Text('Demo updated'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(saSentence(e)), behavior: SnackBarBehavior.floating));
    }
  }
}

class _SignupCard extends StatelessWidget {
  const _SignupCard({required this.signup, required this.onDemo});
  final SaSignup signup;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = signup;
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final source = switch (s.signupSource) {
      'self_google' => 'Google',
      'self_facebook' => 'Facebook',
      'self_truecaller' => 'Truecaller',
      'self_email' => 'Email',
      _ => null,
    };
    final trial = s.trialStart == null && s.trialEnd == null
        ? null
        : 'Trial ${s.trialStart == null ? '…' : _day.format(s.trialStart!)} – '
            '${s.trialEnd == null ? '…' : _day.format(s.trialEnd!)}';
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
              Text(s.fullName, style: t.textTheme.titleMedium),
              StatusChip(
                label: saPlanStatuses[s.planStatus] ?? (s.planStatus ?? 'Unknown'),
                tone: saPlanTone(s.planStatus),
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: Space.xxs),
          SelectableText([?s.phone, ?s.email].join(' · '), style: t.textTheme.bodyMedium),
          Text(
            [
              if (s.signedUpAt != null) 'Signed up ${_day.format(s.signedUpAt!.toLocal())}',
              if (source != null) 'with $source',
            ].join(' '),
            style: muted,
          ),
          const Divider(height: Space.lg),
          Text(
            s.hostelName == null
                ? 'No PG yet'
                : [s.hostelName!, ?s.hostelCity].join(', '),
            style: t.textTheme.titleSmall,
          ),
          if (trial != null) Text(trial, style: t.textTheme.bodyMedium),
          if (s.planEnd != null && s.planStatus != 'trial')
            Text('Plan ends ${_day.format(s.planEnd!)}', style: muted),
          const SizedBox(height: Space.xs),
          if (s.demoId == null)
            Text('No demo booked', style: muted)
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: Space.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Demo', style: t.textTheme.labelLarge),
                          StatusChip(
                            label: demoStatuses[s.demoStatus] ?? (s.demoStatus ?? ''),
                            tone: saDemoTone(s.demoStatus),
                          ),
                        ],
                      ),
                      Text(
                        [
                          if (s.demoSlot != null) _slot.format(s.demoSlot!.toLocal()),
                          if (s.demoBedBand != null) '${s.demoBedBand} beds',
                        ].join(' · '),
                        style: muted,
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: onDemo, child: const Text('Mark')),
              ],
            ),
        ],
      ),
    );
  }
}
