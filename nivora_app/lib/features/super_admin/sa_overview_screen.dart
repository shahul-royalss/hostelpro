library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import 'create/create_wizard_screen.dart';
import 'data/sa_models.dart';
import 'data/sa_providers.dart';
import 'widgets/sa_ui.dart';

/// SA-1 — the platform at a glance.
///
/// RPCs: public.rpc_sa_dashboard() (via the shared saStatsProvider),
///       public.rpc_sa_onboarding_series(), public.security_alerts (open count).
///
/// ── ONE HERO FIGURE, NOT A WALL OF CARDS ─────────────────────────────────────────────────
///
/// rpc_sa_dashboard returns seven numbers and the temptation is to draw seven equal tiles. Six
/// panes of equal weight say nothing about which one matters, and this screen has a clear
/// answer to that: hostels on the platform is what the business IS, so it gets the 40pt figure
/// and everything else is arranged around it in decreasing order of "does this need me today".
///
/// The band under the hero is the only part that is about ACTION. Expiring, expired and
/// unacknowledged alerts are the three things a platform admin is the only person able to fix,
/// and each one opens the tab that lists exactly what it counted — the number and the list it
/// leads to are the same query, so they cannot disagree.
///
/// ── NOTHING HERE IS COMPUTED FROM A PAGE ─────────────────────────────────────────────────
///
/// Every figure is counted by Postgres in one query. Platform-wide occupancy is deliberately
/// ABSENT: rpc_sa_dashboard does not return it, and deriving it from the twenty hostels that
/// happen to be on page one would be wrong by exactly the amount that did not fit. Occupancy is
/// shown per hostel on the Hostels tab, where the row carries its own counted beds.
class SaOverviewScreen extends ConsumerWidget {
  const SaOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(saStatsProvider);

    return SaScreen(
      title: 'Platform',
      subtitle: _greeting(ref.watch(sessionProvider)?.fullName),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
      onRefresh: () async {
        ref.invalidate(saStatsProvider);
        ref.invalidate(saOnboardingProvider);
        ref.invalidate(saOpenAlertCountProvider);
        await ref.read(saStatsProvider.future);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          saAsync<SaStats?>(
            stats,
            loading: () => const _HeroSkeleton(),
            error: (e) => SaError(error: e, onRetry: () => ref.invalidate(saStatsProvider)),
            // Zero rows is a refusal expressed as emptiness, not an empty platform. See
            // DashboardRepository.superAdminStats.
            data: (value) =>
                value == null ? const SaNotPermitted() : _Platform(stats: value),
          ),
          const SizedBox(height: Space.lg),
          const _Onboarding(),
          const SizedBox(height: Space.lg),
          _CreateBanner(
            onCreate: () => Navigator.of(context).push(CreateWizardScreen.route()),
          ),
        ],
      ),
    );
  }

  static String _greeting(String? fullName) {
    final hour = DateTime.now().hour;
    final part = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final name = (fullName ?? '').trim();
    return name.isEmpty ? part : '$part, ${name.split(RegExp(r'\s+')).first}';
  }
}

/// The hero, the attention band and the two supporting figures.
class _Platform extends ConsumerWidget {
  const _Platform({required this.stats});
  final SaStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── THE ONE ELEVATED THING ON THIS SCREEN ──
        GlassCard(
          padding: const EdgeInsets.all(Space.lg),
          semanticLabel: '${stats.totalHostels} hostels on the platform',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HOSTELS ON NIVORA', style: t.textTheme.labelSmall),
              const SizedBox(height: Space.xxs),
              Text(count(stats.totalHostels), style: t.textTheme.headlineLarge),
              const SizedBox(height: Space.xs),
              Text(
                '${plural(stats.totalOwners, 'owner')} · '
                '${plural(stats.totalStudents, 'resident')} in residence',
                style: t.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),

        // ── WHAT NEEDS THE ADMIN TODAY ──
        SaHeading(
          title: 'Needs attention',
          caption: 'An expired subscription makes a hostel read-only for everyone in it.',
        ),
        Row(
          children: [
            Expanded(
              child: _AttentionTile(
                label: 'Expiring',
                value: stats.expiringSubs,
                caption: '15 days or fewer',
                icon: Icons.schedule_rounded,
                tone: context.tones.warning,
                onTap: () => _openSubscriptions(ref, SubscriptionState.expiring),
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: _AttentionTile(
                label: 'Expired',
                value: stats.expiredSubs,
                caption: 'Read-only now',
                icon: Icons.lock_rounded,
                tone: context.tones.error,
                onTap: () => _openSubscriptions(ref, SubscriptionState.expired),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        const _AlertsTile(),
        const SizedBox(height: Space.lg),

        // ── REPORTING ──
        SaHeading(title: 'This month'),
        Row(
          children: [
            Expanded(
              child: GlassStatCard(
                label: 'Subscription revenue',
                value: money(stats.monthlySubscriptionRevenue),
                // Says exactly what the SQL sums: rows CREATED this calendar month, which is
                // new sales plus renewals — not a recurring monthly figure. Labelling it "MRR"
                // would be a different number the database does not hold.
                caption: 'Subscriptions started or renewed this month',
                icon: Icons.payments_rounded,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: GlassStatCard(
                label: 'Active subscriptions',
                value: count(stats.activeSubs),
                caption: 'of ${plural(stats.totalHostels, 'hostel')}',
                icon: Icons.verified_rounded,
                tone: NivoraColors.success,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Lands the admin on the list the number was counting, already filtered.
  static void _openSubscriptions(WidgetRef ref, SubscriptionState state) {
    ref.read(saSubscriptionFilterProvider.notifier).set(state);
    ref.read(saTabProvider.notifier).go(SaTabs.subscriptions);
  }
}

/// One of the two subscription-health tiles.
///
/// Drawn flat and tinted only when there is something to report: a red "0 expired" tile every
/// morning is how a red tile stops meaning anything by Wednesday.
class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final int value;
  final String caption;
  final IconData icon;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final quiet = value == 0;
    final accent = quiet ? t.colorScheme.outline : tone;

    return SaTapCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: IconSize.sm, color: accent),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(label.toUpperCase(),
                    style: t.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            count(value),
            style: t.textTheme.headlineMedium?.copyWith(color: quiet ? null : tone),
          ),
          const SizedBox(height: Space.xxs),
          Text(quiet ? 'None' : caption, style: t.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Unacknowledged security alerts, and the way into the console.
class _AlertsTile extends ConsumerWidget {
  const _AlertsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final open = ref.watch(saOpenAlertCountProvider);

    return saAsync<int>(
      open,
      loading: () => const SaSkeletonCard(lines: 1, height: 76),
      // An alert console that cannot be read is itself worth saying out loud, quietly.
      error: (e) => SaError(
        error: e,
        compact: true,
        onRetry: () => ref.invalidate(saOpenAlertCountProvider),
      ),
      data: (value) {
        final tone = value == 0 ? t.colorScheme.outline : context.tones.error;
        return SaTapCard(
          onTap: () => ref.read(saTabProvider.notifier).go(SaTabs.security),
          child: Row(
            children: [
              Icon(
                value == 0 ? Icons.shield_outlined : Icons.gpp_maybe_rounded,
                size: IconSize.lg,
                color: tone,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SECURITY', style: t.textTheme.labelSmall),
                    const SizedBox(height: Space.xxs),
                    Text(
                      value == 0
                          ? 'Nothing outstanding'
                          : '${plural(value, 'alert')} awaiting acknowledgement',
                      style: t.textTheme.titleMedium,
                    ),
                    const SizedBox(height: Space.xxs),
                    Text(
                      'Raised by the audit trail when it spots a pattern — a burst of failed '
                      'logins, or a session probing for rows it cannot read.',
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              Icon(Icons.chevron_right_rounded, color: t.colorScheme.outline),
            ],
          ),
        );
      },
    );
  }
}

/// Twelve months of hostels joining the platform. public.rpc_sa_onboarding_series().
///
/// DRAWN BY HAND rather than with a charting library, for twelve integers. The series is
/// generated by `generate_series` and zero-filled server-side, so a short bar is a quiet month
/// and never a gap something interpolated across — and the labels use this app's own type
/// scale, which a library's axis renderer does not.
class _Onboarding extends ConsumerWidget {
  const _Onboarding();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final series = ref.watch(saOnboardingProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaHeading(title: 'Onboarding', caption: 'Hostels added, last 12 months'),
        saAsync<List<OnboardingPoint>>(
          series,
          loading: () => const SaSkeletonCard(lines: 3, height: 150),
          error: (e) => SaError(
            error: e,
            compact: true,
            onRetry: () => ref.invalidate(saOnboardingProvider),
          ),
          data: (points) {
            if (points.isEmpty) {
              // NOT "no history yet", which is what this used to say. rpc_sa_onboarding_series
              // is a generate_series over twelve months with a count per month and
              // `where app.is_super_admin()` on the end: a Super Admin gets twelve rows on the
              // day the platform is created, because a month with nothing in it is still a row.
              // NO rows at all is the refusal, and only the refusal. Said plainly rather than
              // as a second alarm — the hero above has already said it in full.
              return const SaEmpty(
                icon: Icons.lock_outline_rounded,
                title: 'Onboarding history withheld',
                message: 'The server returns twelve months for the Super Admin whether or not '
                    'anything happened in them, so nothing coming back means this account was '
                    'not given the series — not that the platform is new.',
              );
            }
            final peak = points.fold<int>(0, (m, p) => p.hostels > m ? p.hostels : m);
            final total = points.fold<int>(0, (s, p) => s + p.hostels);
            final latest = points.last;

            return FlatSurface(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    latest.hostels == 0
                        ? 'None yet in ${monthLabel(latest.month)}'
                        : '${plural(latest.hostels, 'hostel')} in ${monthLabel(latest.month)}',
                    style: t.textTheme.titleMedium,
                  ),
                  const SizedBox(height: Space.xxs),
                  Text('${plural(total, 'hostel')} over the period',
                      style: t.textTheme.bodySmall),
                  const SizedBox(height: Space.md),
                  SizedBox(
                    height: 88,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final point in points)
                          Expanded(
                            child: _Bar(
                              // A month with no hostels still draws a 2dp stub, so twelve
                              // months read as twelve months rather than as a gap in the data.
                              fraction: peak == 0 ? 0 : point.hostels / peak,
                              value: point.hostels,
                              month: point.month,
                              highlight: point.month == latest.month,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.value,
    required this.month,
    required this.highlight,
  });

  final double fraction;
  final int value;
  final String month;
  final bool highlight;

  static const _plotHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = highlight ? t.colorScheme.primary : t.colorScheme.primary.withValues(alpha: 0.45);

    return Semantics(
      label: '${monthLabel(month)}: ${plural(value, 'hostel')}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              value == 0 ? '' : '$value',
              style: t.textTheme.labelSmall,
              maxLines: 1,
            ),
            const SizedBox(height: Space.xxs),
            Container(
              height: (_plotHeight * fraction).clamp(2.0, _plotHeight),
              decoration: BoxDecoration(
                color: tone,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.tiny)),
              ),
            ),
            const SizedBox(height: Space.xxs),
            Text(
              monthShort(month),
              style: t.textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ],
        ),
      ),
    );
  }
}

/// The way into the create wizard, stated as what it does rather than as a plus button.
class _CreateBanner extends StatelessWidget {
  const _CreateBanner({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_business_rounded,
                  size: IconSize.md, color: t.colorScheme.primary),
              const SizedBox(width: Space.xs),
              Expanded(child: Text('Onboard a hostel', style: t.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(
            'Creates the owner login, the hostel, its floors, rooms and beds, and the first '
            'subscription — or adds a second hostel under an owner who already has an account.',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded, size: IconSize.sm),
              label: const Text('Create owner & hostel'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaSkeletonCard(lines: 2, height: 148),
        SizedBox(height: Space.lg),
        Row(
          children: [
            Expanded(child: SaSkeletonCard(lines: 1, height: 110)),
            SizedBox(width: Space.sm),
            Expanded(child: SaSkeletonCard(lines: 1, height: 110)),
          ],
        ),
        SizedBox(height: Space.sm),
        SaSkeletonCard(lines: 2, height: 96),
      ],
    );
  }
}
