library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import 'create/create_wizard_screen.dart';
import 'data/sa_providers.dart';
import 'sa_hostel_detail_screen.dart';
import 'widgets/sa_ui.dart';

/// SA-2 — every hostel on the platform, searchable, paginated, tap-through to detail.
///
/// RPC: public.rpc_sa_hostels().
///
/// ── THE SEARCH IS SERVER-SIDE, AND THAT IS THE WHOLE POINT ───────────────────────────────
///
/// PostgREST applies filters to the RESULT of a set-returning function, so the `ilike` runs in
/// Postgres over every hostel and this device is sent only the matches. A search that filtered
/// the twenty rows already on the phone would quietly fail to find hostel twenty-one — the
/// exact failure that looks like "we never onboarded them" and is not.
///
/// Keystrokes are debounced ([_debounce]) rather than fired per character: each distinct query
/// is a distinct provider instance and a distinct request, and typing "Koramangala" would
/// otherwise be eleven of them.
class SaHostelsScreen extends ConsumerStatefulWidget {
  const SaHostelsScreen({super.key});

  @override
  ConsumerState<SaHostelsScreen> createState() => _SaHostelsScreenState();
}

class _SaHostelsScreenState extends ConsumerState<SaHostelsScreen> {
  /// Long enough that a normal typing speed produces one request per word, short enough that a
  /// pause feels like the list is keeping up.
  static const _debounce = Duration(milliseconds: 320);

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(saHostelFilterProvider).search ?? '';
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // 400dp before the end: far enough that the next page usually lands before the reader
    // reaches the gap, close enough that it is not fetched for a flick that turns around.
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) return;
    final query = ref.read(saHostelFilterProvider);
    unawaited(ref.read(saHostelListProvider(query).notifier).loadMore());
  }

  void _search(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (!mounted) return;
      ref.read(saHostelFilterProvider.notifier).search(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final query = ref.watch(saHostelFilterProvider);
    final list = ref.watch(saHostelListProvider(query));

    // What an empty page from rpc_sa_hostels means, corroborated by rpc_sa_dashboard. This used
    // to be `stats.value == null && !stats.isLoading`, which is also true of a dashboard that
    // FAILED — so a platform admin whose connection dropped was told they were not permitted.
    final verdict = saEmptyVerdict(ref.watch(saStatsProvider));

    return SaScreen(
      title: 'Hostels',
      scrollable: false,
      actions: [
        IconButton(
          tooltip: 'Create owner & hostel',
          onPressed: () => Navigator.of(context).push(CreateWizardScreen.route()),
          icon: const Icon(Icons.add_business_rounded),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.xs),
            child: TextField(
              controller: _controller,
              onChanged: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Hostel, owner, email or address',
                prefixIcon: const Icon(Icons.search_rounded, size: IconSize.md),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded, size: IconSize.md),
                        onPressed: () {
                          _timer?.cancel();
                          _controller.clear();
                          ref.read(saHostelFilterProvider.notifier).search(null);
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          _StatusFilters(query: query),
          Expanded(
            child: saAsync<PagedResult<SaHostelRow>>(
              list,
              loading: () => ListView(
                padding: const EdgeInsets.all(Space.md),
                children: const [
                  SaSkeletonCard(lines: 3, height: 150),
                  SizedBox(height: Space.sm),
                  SaSkeletonCard(lines: 3, height: 150),
                  SizedBox(height: Space.sm),
                  SaSkeletonCard(lines: 3, height: 150),
                ],
              ),
              error: (e) => ListView(
                padding: const EdgeInsets.all(Space.md),
                children: [
                  SaError(error: e, onRetry: () => ref.invalidate(saHostelListProvider(query))),
                ],
              ),
              data: (page) => _HostelList(
                page: page,
                query: query,
                scroll: _scroll,
                onClearFilters: () {
                  _timer?.cancel();
                  _controller.clear();
                  ref.read(saHostelFilterProvider.notifier).clear();
                  setState(() {});
                },
                verdict: verdict,
                // Both reads, because either one being stale is what leaves this screen unable
                // to say what its own emptiness means.
                onRecheck: () {
                  ref.invalidate(saStatsProvider);
                  ref.invalidate(saHostelListProvider(query));
                },
              ),
            ),
          ),
          if (list.isLoading && list.hasValue)
            LinearProgressIndicator(minHeight: 2, backgroundColor: t.colorScheme.surface),
        ],
      ),
    );
  }
}

/// The two status filters, as chips rather than a dropdown: three subscription states and three
/// hostel states are six taps, and a dropdown hides which one is currently on.
class _StatusFilters extends ConsumerWidget {
  const _StatusFilters({required this.query});
  final SaHostelQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        children: [
          for (final state in SubscriptionState.values) ...[
            FilterChip(
              label: Text(state.label),
              selected: query.subState == state,
              onSelected: (on) =>
                  ref.read(saHostelFilterProvider.notifier).subscription(on ? state : null),
              avatar: Icon(
                switch (state) {
                  SubscriptionState.active => Icons.verified_rounded,
                  SubscriptionState.expiring => Icons.schedule_rounded,
                  SubscriptionState.expired => Icons.lock_rounded,
                },
                size: IconSize.xs,
                color: subscriptionTone(context, state),
              ),
            ),
            const SizedBox(width: Space.xs),
          ],
          FilterChip(
            label: const Text('Suspended'),
            selected: query.hostelStatus == HostelStatus.suspended,
            onSelected: (on) => ref
                .read(saHostelFilterProvider.notifier)
                .hostel(on ? HostelStatus.suspended : null),
          ),
        ],
      ),
    );
  }
}

class _HostelList extends ConsumerWidget {
  const _HostelList({
    required this.page,
    required this.query,
    required this.scroll,
    required this.onClearFilters,
    required this.verdict,
    required this.onRecheck,
  });

  final PagedResult<SaHostelRow> page;
  final SaHostelQuery query;
  final ScrollController scroll;
  final VoidCallback onClearFilters;

  /// What an empty page MEANS, read off rpc_sa_dashboard: still being decided, undecidable, a
  /// refusal, or a real emptiness. One empty result cannot tell those apart; two can, and a
  /// dashboard that FAILED can tell nothing at all. See [SaEmptyVerdict].
  final SaEmptyVerdict verdict;

  /// Re-runs both reads. The only exit from [SaEmptyVerdict.unverified].
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (page.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(Space.md),
        children: [
          switch (verdict) {
            // The dashboard has not answered yet, so neither has this screen. A skeleton says
            // "still working", which is the one honest thing available before the answer lands.
            SaEmptyVerdict.pending => const SaSkeletonCard(lines: 2, height: 150),

            // The list is empty and the read that would explain it failed. Nothing is claimed
            // about the platform or about this account, and the way out is on the panel.
            SaEmptyVerdict.unverified => SaUnverified(
                title: 'No hostels came back, and we cannot say why',
                message: 'The platform list answered with nothing in it, and the dashboard '
                    'figures this console checks that against could not be read. Until that '
                    'read succeeds, an empty platform and an account that is not permitted to '
                    'see one look identical from here.',
                onRetry: onRecheck,
                action: query.isFiltered
                    ? OutlinedButton.icon(
                        onPressed: onClearFilters,
                        icon: const Icon(Icons.filter_alt_off_rounded, size: IconSize.sm),
                        label: const Text('Clear filters'),
                      )
                    : null,
              ),

            SaEmptyVerdict.refused => const SaNotPermitted(),

            // Only here is the emptiness a fact, so only here is an empty state drawn.
            SaEmptyVerdict.confirmed => query.isFiltered
                ? SaEmpty(
                    icon: Icons.search_off_rounded,
                    title: 'No hostel matches that',
                    message: 'Nothing on the platform matches the current search and filters.',
                    action: OutlinedButton.icon(
                      onPressed: onClearFilters,
                      icon: const Icon(Icons.filter_alt_off_rounded, size: IconSize.sm),
                      label: const Text('Clear filters'),
                    ),
                  )
                : SaEmpty(
                    icon: Icons.apartment_rounded,
                    title: 'No hostels yet',
                    message: 'The first one appears here the moment it is created.',
                    action: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(CreateWizardScreen.route()),
                      icon: const Icon(Icons.add_rounded, size: IconSize.sm),
                      label: const Text('Create owner & hostel'),
                    ),
                  ),
          },
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(saHostelListProvider(query));
        await ref.read(saHostelListProvider(query).future);
      },
      child: ListView.separated(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          Space.md,
          Space.sm,
          Space.md,
          Space.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: page.items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, index) {
          if (index == page.items.length) return _ListFooter(page: page);
          final hostel = page.items[index];
          return SaHostelCard(
            hostel: hostel,
            onTap: () => Navigator.of(context).push(
              SaHostelDetailScreen.route(hostel.hostelId),
            ),
          );
        },
      ),
    );
  }
}

/// The end of the list: either "loading more", or the honest total on screen.
class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.page});
  final PagedResult<SaHostelRow> page;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Center(
        child: page.hasMore
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            // "20 hostels shown" would be a claim about the platform; this is a claim about the
            // list, which is the only one this screen can make honestly.
            : Text('${plural(page.items.length, 'hostel')} shown',
                style: t.textTheme.bodySmall),
      ),
    );
  }
}

/// One hostel, as the platform admin needs to read it in a scroll: who owns it, whether it is
/// writable, how full it is, and what its subscription is doing.
class SaHostelCard extends StatelessWidget {
  const SaHostelCard({super.key, required this.hostel, this.onTap});

  final SaHostelRow hostel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return SaTapCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hostel.hostelName,
                        style: t.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: Space.xxs),
                    Text(
                      hostel.ownerName,
                      style: t.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              SaSubscriptionPill(state: hostel.subState, daysLeft: hostel.daysLeft),
            ],
          ),
          const SizedBox(height: Space.sm),
          SaMeter(
            rate: hostel.occupancyRate,
            label: 'Occupancy',
            caption: '${count(hostel.occupiedBeds)} of ${plural(hostel.totalBeds, 'bed')} '
                'taken · ${plural(hostel.activeStudents, 'resident')}',
          ),
          if (hostel.openComplaints > 0 || !hostel.isWritable) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                if (!hostel.isWritable)
                  SaPill(
                    label: hostel.hostelStatus == HostelStatus.active
                        ? 'Read-only'
                        : hostel.hostelStatus.label,
                    tone: context.tones.error,
                    icon: Icons.lock_rounded,
                  ),
                if (!hostel.isWritable && hostel.openComplaints > 0)
                  const SizedBox(width: Space.xs),
                if (hostel.openComplaints > 0)
                  SaPill(
                    label: '${count(hostel.openComplaints)} open',
                    tone: context.tones.warning,
                    icon: Icons.report_problem_rounded,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
