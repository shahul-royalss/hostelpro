library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import '../common/refresh.dart';
import 'data/sa_providers.dart';
import 'sa_hostel_detail_screen.dart';
import 'widgets/sa_ui.dart';

/// SA-3 — plan, status and expiry for every hostel, and what an expiry actually does.
///
/// RPC: public.rpc_sa_hostels(), filtered server-side on `sub_state`.
///
/// ── THE ONE SENTENCE THIS SCREEN EXISTS TO SAY ───────────────────────────────────────────
///
/// An expired subscription makes the hostel READ-ONLY. Not "shows a warning" — the database
/// refuses the write. `app.hostel_writable()` gates every write RPC and every write policy in
/// db/rls-policies.sql, so the warden cannot register a resident, the cashier cannot record a
/// payment, and the complaint that came in this morning cannot be resolved. The web app draws
/// the same conclusion from the same two columns (lib/permissions.ts:301):
///
///     writable = hostel.status === "active" && subscriptionState !== "expired"
///
/// So the expired rows lead, they say what is blocked rather than that something is wrong, and
/// the ones with fifteen days or fewer are separated out — that window is the whole point of
/// the `expiring` state existing, and it is the last moment anybody can act before a hostel
/// stops working on a Monday morning.
///
/// ── WHY THE SAME PROVIDER AS THE HOSTELS TAB ─────────────────────────────────────────────
///
/// Both tabs are a filtered read of rpc_sa_hostels, so both go through [saHostelListProvider].
/// A second query shaped "just for subscriptions" would be a second definition of what
/// `expiring` means, and the two would eventually disagree by a day.
class SaSubscriptionsScreen extends ConsumerStatefulWidget {
  const SaSubscriptionsScreen({super.key});

  @override
  ConsumerState<SaSubscriptionsScreen> createState() => _SaSubscriptionsScreenState();
}

class _SaSubscriptionsScreenState extends ConsumerState<SaSubscriptionsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Non-null when the last attempt at the next page failed. See [SaLoadMoreFooter] — this
  /// was `unawaited(...)`, and `loadMore` returns its failure rather than throwing, so a page
  /// that did not load left a spinner turning under the rows with nothing to read or tap.
  AppFailure? _loadMoreError;
  bool _loadingMore = false;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) return;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loadMoreError != null) return;
    _loadingMore = true;
    final query = SaHostelQuery(subState: ref.read(saSubscriptionFilterProvider));
    final failure = await ref.read(saHostelListProvider(query).notifier).loadMore();
    _loadingMore = false;
    if (!mounted || failure == null) return;
    setState(() => _loadMoreError = failure);
  }

  void _retryLoadMore() {
    setState(() => _loadMoreError = null);
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(saSubscriptionFilterProvider);
    final query = SaHostelQuery(subState: filter);
    final list = ref.watch(saHostelListProvider(query));

    // The same corroboration the Hostels tab does, for the same reason: this tab is the same
    // rpc_sa_hostels read, so an account that is not the Super Admin gets an empty list here
    // too — and "Nothing has lapsed. Every hostel can still be written to." is a sentence about
    // the platform that a refused account has no business being shown as if it were true.
    final verdict = saEmptyVerdict(ref.watch(saStatsProvider));

    return SaScreen(
      title: 'Subscriptions',
      subtitle: 'One subscription per hostel',
      scrollable: false,
      child: Column(
        children: [
          _Filters(selected: filter),
          Expanded(
            child: saAsync<PagedResult<SaHostelRow>>(
              list,
              loading: () => ListView(
                padding: const EdgeInsets.all(Space.md),
                children: const [
                  SaSkeletonCard(lines: 3, height: 140),
                  SizedBox(height: Space.sm),
                  SaSkeletonCard(lines: 3, height: 140),
                  SizedBox(height: Space.sm),
                  SaSkeletonCard(lines: 3, height: 140),
                ],
              ),
              error: (e) => ListView(
                padding: const EdgeInsets.all(Space.md),
                children: [
                  SaError(error: e, onRetry: () => ref.invalidate(saHostelListProvider(query))),
                ],
              ),
              data: (page) => _SubscriptionList(
                page: page,
                query: query,
                filter: filter,
                scroll: _scroll,
                loadMoreError: _loadMoreError,
                onRetryLoadMore: _retryLoadMore,
                verdict: verdict,
                onRecheck: () {
                  ref.invalidate(saStatsProvider);
                  ref.invalidate(saHostelListProvider(query));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// All / Active / Expiring / Expired. A segmented row rather than a dropdown: which slice is on
/// screen is the first thing a reader needs to know, and a dropdown hides it behind a tap.
class _Filters extends ConsumerWidget {
  const _Filters({required this.selected});
  final SubscriptionState? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void set(SubscriptionState? value) =>
        ref.read(saSubscriptionFilterProvider.notifier).set(value);

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => set(null),
          ),
          for (final state in SubscriptionState.values) ...[
            const SizedBox(width: Space.xs),
            ChoiceChip(
              label: Text(state.label),
              selected: selected == state,
              onSelected: (_) => set(selected == state ? null : state),
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
          ],
        ],
      ),
    );
  }
}

class _SubscriptionList extends ConsumerWidget {
  const _SubscriptionList({
    required this.page,
    required this.query,
    required this.filter,
    required this.scroll,
    required this.verdict,
    required this.onRecheck,
    required this.loadMoreError,
    required this.onRetryLoadMore,
  });

  final PagedResult<SaHostelRow> page;
  final SaHostelQuery query;
  final SubscriptionState? filter;
  final ScrollController scroll;

  /// What an empty page means here, from rpc_sa_dashboard. Same shape as the Hostels tab,
  /// deliberately: the two tabs read the same function, so they must be able to be empty in the
  /// same four ways. See [SaEmptyVerdict].
  final SaEmptyVerdict verdict;

  /// Re-runs both reads. The only exit from [SaEmptyVerdict.unverified].
  final VoidCallback onRecheck;

  /// The next page's failure, and the way to ask for it again.
  final AppFailure? loadMoreError;
  final VoidCallback onRetryLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (page.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(Space.md),
        children: [
          switch (verdict) {
            SaEmptyVerdict.pending => const SaSkeletonCard(lines: 2, height: 140),

            // "Nothing has lapsed" is a claim about every hostel on the platform. It cannot be
            // made from a list that came back empty for a reason nobody can name.
            SaEmptyVerdict.unverified => SaUnverified(
                title: 'No subscriptions came back, and we cannot say why',
                message: 'This tab reads the same platform list as the Hostels tab, and the '
                    'dashboard figures it checks that against could not be read. A platform '
                    'with nothing lapsed and an account that is not permitted to see the '
                    'platform both look like this.',
                onRetry: onRecheck,
                action: filter == null
                    ? null
                    : OutlinedButton.icon(
                        onPressed: () =>
                            ref.read(saSubscriptionFilterProvider.notifier).set(null),
                        icon: const Icon(Icons.filter_alt_off_rounded, size: IconSize.sm),
                        label: const Text('Show all'),
                      ),
              ),

            SaEmptyVerdict.refused => const SaNotPermitted(),

            // NOT SaNotPermitted, and not SaUnverified's "check again" either. The read
            // that would have explained this emptiness died with the access token, so the
            // only honest thing on screen is the way to get a live one.
            SaEmptyVerdict.credentialDead => const SaSessionEnded(),

            SaEmptyVerdict.confirmed => SaEmpty(
                icon: filter == SubscriptionState.expired
                    ? Icons.check_circle_outline_rounded
                    : Icons.card_membership_rounded,
                tone: NivoraDomain.money.tone,
                title: switch (filter) {
                  SubscriptionState.expired => 'Nothing has lapsed',
                  SubscriptionState.expiring => 'Nothing is close to lapsing',
                  SubscriptionState.active => 'No active subscriptions',
                  null => 'No subscriptions yet',
                },
                message: switch (filter) {
                  SubscriptionState.expired =>
                    'Every hostel on the platform can still be written to.',
                  SubscriptionState.expiring =>
                    'No hostel is inside the fifteen-day window.',
                  _ => 'A subscription is created with the hostel, in the create wizard.',
                },
              ),
          },
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(saHostelListProvider(query));
        return settleRefresh(context, () => ref.read(saHostelListProvider(query).future));
      },
      child: ListView.separated(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          Space.md,
          Space.xs,
          Space.md,
          Space.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        // +1 for the explainer at the top, +1 for the footer at the bottom.
        itemCount: page.items.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, index) {
          if (index == 0) return const _ReadOnlyExplainer();
          if (index == page.items.length + 1) {
            return SaLoadMoreFooter(
              hasMore: page.hasMore,
              shown: page.items.length,
              noun: 'hostel',
              error: loadMoreError,
              onRetry: onRetryLoadMore,
            );
          }
          final hostel = page.items[index - 1];
          return _SubscriptionCard(hostel: hostel);
        },
      ),
    );
  }
}

/// The rule, stated once at the top rather than repeated on every row.
class _ReadOnlyExplainer extends StatelessWidget {
  const _ReadOnlyExplainer();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: IconSize.md, color: t.colorScheme.outline),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              'When a subscription expires the hostel becomes read-only: its staff can still '
              'read everything, but the database refuses new residents, new payments and '
              'complaint updates until it is renewed.',
              style: t.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// One hostel's subscription, and the consequence of its state.
class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.hostel});
  final SaHostelRow hostel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = subscriptionTone(context, hostel.subState);

    return SaTapCard(
      onTap: () =>
          Navigator.of(context).push(SaHostelDetailScreen.route(hostel.hostelId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // NO GREEN CARD PLATE HERE. It was literally the glyph the tab wears, in the
              // tab's own hue, repeated on every row of a list where every row is a
              // subscription — agreement so complete that it carried no information. Worse
              // than idle: the pill at the other end of this same row is the success green
              // when the subscription is ACTIVE, so a green plate and a green pill sat on one
              // line meaning two different things. The money green keeps the tab and the
              // detail screen's own subscription heading, where it still distinguishes.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hostel.hostelName,
                        style: t.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: Space.xxs),
                    Text(hostel.ownerName,
                        style: t.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              SaSubscriptionPill(state: hostel.subState, daysLeft: hostel.daysLeft),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PERIOD', style: t.textTheme.labelSmall),
                    const SizedBox(height: Space.xxs),
                    Text(
                      hostel.subEnd == null
                          ? 'Never subscribed'
                          : '${hostel.subStart == null ? '—' : dayLabel(hostel.subStart!)}'
                              ' → ${dateLabel(hostel.subEnd!)}',
                      style: t.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('AMOUNT', style: t.textTheme.labelSmall),
                  const SizedBox(height: Space.xxs),
                  Text(
                    hostel.subAmount == null ? '—' : money(hostel.subAmount!),
                    style: t.textTheme.titleSmall,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(daysLeftLabel(hostel.daysLeft),
              style: t.textTheme.bodySmall?.copyWith(color: tone)),
          if (!hostel.isWritable) ...[
            const SizedBox(height: Space.sm),
            SaReadOnlyBand(hostel: hostel, compact: true),
          ],
        ],
      ),
    );
  }
}
