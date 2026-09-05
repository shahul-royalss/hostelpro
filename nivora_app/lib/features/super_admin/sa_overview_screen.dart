library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/dashboard.dart';
import '../../shared/glass/glass.dart';
import '../auth/verify_email_screen.dart';
import '../common/refresh.dart';
import '../settings/security_screen.dart';
import 'create/create_wizard_screen.dart';
import 'data/sa_models.dart';
import 'data/sa_providers.dart';
import 'widgets/sa_ui.dart';

/// SA-1 — the platform at a glance. FIGMA `screen-dashboard`, node 4:125.
///
/// RPCs: public.rpc_sa_dashboard() (via the shared saStatsProvider),
///       public.rpc_sa_onboarding_series(), public.security_alerts (open count).
///
/// ── THE MOCKUP'S SHAPE, WHICH IS NOT THE SHAPE THIS SCREEN HAD ───────────────────────────
///
/// 4:125 is one document, not a stack of cards. Four small KPI tiles two-up, a hairline, a
/// section in 12px caps, a hairline, another section, and so on to the bottom. Nothing on it is
/// set larger than 16px. This screen used to lead with a 32pt hero figure inside a full-width
/// pane and then four more full-width panes under it — a shape that made every number look
/// equally like the point and pushed the two sections that are actually about ACTION
/// (subscription health, outstanding alerts) below the fold on a 360dp phone.
///
/// The order is the mockup's: KPIs · subscription health · onboarding · security. What sits
/// above them, and is not in the mockup at all, is the create banner — see [_CreateBanner].
///
/// ── NOTHING HERE IS COMPUTED FROM A PAGE ─────────────────────────────────────────────────
///
/// Every figure is counted by Postgres in one query. Platform-wide occupancy is deliberately
/// ABSENT: rpc_sa_dashboard does not return it, and deriving it from the twenty hostels that
/// happen to be on page one would be wrong by exactly the amount that did not fit. Occupancy is
/// shown per hostel on the Hostels tab, where the row carries its own counted beds.
///
/// ── AND THE SECURITY SECTION IS A COUNT, NOT A LIST ──────────────────────────────────────
///
/// 4:201 draws the two most recent alerts in full. This screen may not read them. The product
/// owner's requirement — held down by test/super_admin_warmup_test.dart — is that the Overview
/// has the network to ITSELF for its first paint, and that the other three tabs' data is warmed
/// behind it on a stagger. Watching `saAlertsProvider` here would put a fourth request in the
/// first frame, contend with `rpc_sa_dashboard`, and make the Security tab's warm-up arrive
/// twice. The count that `saOpenAlertCountProvider` already reads is what this screen is
/// entitled to, so the section is drawn in the mockup's row anatomy around that one number.
class SaOverviewScreen extends ConsumerWidget {
  const SaOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(saStatsProvider);

    return SaScreen(
      title: 'Platform overview',
      subtitle: _greeting(ref.watch(sessionProvider)?.fullName),
      actions: [
        // Two-factor enrolment. Every role's header carries one — see
        // features/settings/security_screen.dart.
        SaIconButton(
          icon: Icons.shield_outlined,
          tooltip: 'Security',
          onPressed: () => openSecurity(context),
        ),
        SaIconButton(
          icon: Icons.logout_rounded,
          tooltip: 'Sign out',
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
        ),
      ],
      // Bounded, and it says so when it fails. This used to be a bare
      // `await ref.read(saStatsProvider.future)`: on a backend that accepts the socket and
      // never answers, riverpod's own retry schedule held the spinner for over two minutes and
      // then threw the failure out of the callback unhandled. See features/common/refresh.dart.
      onRefresh: () {
        ref.invalidate(saStatsProvider);
        ref.invalidate(saOnboardingProvider);
        ref.invalidate(saOpenAlertCountProvider);
        return settleRefresh(context, () => ref.read(saStatsProvider.future));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The super admin is the account this matters most for: creating an owner is the
          // single most consequential mint in the product, and requireVerifiedEmail() in
          // sa-create-owner will refuse it until this banner is answered.
          const VerifyEmailBanner(),
          _CreateBanner(
            onCreate: () => Navigator.of(context).push(CreateWizardScreen.route()),
          ),
          const SaSectionRule(),
          // The same band labels the other four dashboards carry. This screen keeps its own
          // SaSectionRule dividers — they are part of the super admin's denser, more clerical
          // look and there is no reason to flatten that — but a reader moving between roles
          // now finds the groups named the same way everywhere.
          const DashboardBand(label: 'Platform'),
          saAsync<SaStats?>(
            stats,
            loading: () => const _PlatformSkeleton(),
            error: (e) => SaError(error: e, onRetry: () => ref.invalidate(saStatsProvider)),
            // Zero rows is a refusal expressed as emptiness, not an empty platform. See
            // DashboardRepository.superAdminStats.
            data: (value) =>
                value == null ? const SaNotPermitted() : _Platform(stats: value),
          ),
          const SaSectionRule(),
          const DashboardBand(label: 'Onboarding'),
          const _Onboarding(),
          const SaSectionRule(),
          const DashboardBand(label: 'Security'),
          const _Security(),
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

/// The KPI block and the subscription-health bar — 4:140 and 4:160.
class _Platform extends ConsumerWidget {
  const _Platform({required this.stats});
  final SaStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 4:141 and 4:150 — two rows of two, 8dp apart, in the mockup's own order.
        _KpiRow(
          left: SaKpiTile(
            label: 'Subscription revenue',
            value: money(stats.monthlySubscriptionRevenue),
            // Says exactly what the SQL sums: rows CREATED this calendar month, which is new
            // sales plus renewals — not a recurring monthly figure. Labelling the tile "MRR"
            // would be a different number the database does not hold.
            semantics: 'Subscription revenue, from subscriptions started or renewed this '
                'calendar month: ${money(stats.monthlySubscriptionRevenue)}',
          ),
          right: SaKpiTile(
            label: 'Hostels',
            value: count(stats.totalHostels),
            semantics: 'Hostels on Nivora: ${count(stats.totalHostels)}',
          ),
        ),
        const SizedBox(height: Space.xs),
        _KpiRow(
          left: SaKpiTile(
            label: 'Owners',
            value: count(stats.totalOwners),
            semantics: 'Owner accounts that can sign in and run a property: '
                '${count(stats.totalOwners)}',
          ),
          right: SaKpiTile(
            label: 'Residents',
            value: count(stats.totalStudents),
            semantics: 'Residents in residence across every hostel: '
                '${count(stats.totalStudents)}',
          ),
        ),
        const SaSectionRule(),
        // NO DOMAIN PLATE ON THIS HEADING. Its body is the segmented health bar, whose first
        // segment is the success green for "Active" — 8dp below a money-green card plate, the
        // same hue would have carried two meanings in one section: "this is the billing area"
        // above and "these hostels are fine" below. The KPI block directly above wears the
        // caps whisper with no plate, so this section matches it. The money glyph is kept
        // where no status colour sits beside it — the empty face in [_Health], the rows on the
        // Subscriptions tab's detail surfaces.
        const SaHeading(
          title: 'Subscription health',
        ),
        _Health(stats: stats),
      ],
    );
  }
}

/// Two KPI tiles side by side, both as tall as the taller one.
///
/// [IntrinsicHeight] IS THE POINT OF THIS WIDGET. `CrossAxisAlignment.stretch` cannot do the job
/// on its own: the whole screen lives inside a `SingleChildScrollView`, so the Row's own height
/// constraint is unbounded and "stretch to my height" resolves to infinity — the layout assert
/// this class was written to fix. Two small tiles is the size of subtree an intrinsic pass is
/// cheap on, and the alternative — letting a two-line label leave a visible step in the middle
/// of the grid — is the one thing that makes a KPI block look broken.
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: Space.xs),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// The design's segmented health bar — 4:162 with the legend at 4:166.
///
/// ── THE DENOMINATOR IS NOT `totalHostels` ────────────────────────────────────────────────
///
/// `app.subscription_state(h.id)` returns exactly one of active / expiring / expired per hostel,
/// so the three counts are mutually exclusive and their SUM is the number of hostels the server
/// actually classified. That sum is the denominator, and [SaSegmentBar] gets it by construction
/// from the flex factors. Dividing by `totalHostels` instead would silently fold "has no
/// subscription at all" into the picture as missing percentage points, and a bar that fails to
/// reach the end of its own track invites exactly the wrong conclusion — that something lapsed —
/// when the truth is that a hostel was never sold one.
class _Health extends ConsumerWidget {
  const _Health({required this.stats});
  final SaStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classified = stats.activeSubs + stats.expiringSubs + stats.expiredSubs;
    if (classified == 0) {
      return SaEmpty(
        icon: Icons.receipt_long_outlined,
        title: 'No subscriptions yet',
        message: 'Nothing on the platform has been sold a subscription, so there is no health '
            'to report. The first one is created with the hostel.',
        tone: NivoraDomain.money.tone,
      );
    }

    // Each band opens the list its number was counting, already filtered — the number and the
    // list it leads to are the same query, so they cannot disagree.
    return SaSegmentBar(
      segments: [
        SaSegment(
          label: 'Active',
          value: stats.activeSubs,
          tone: NivoraColors.success,
          onTap: () => _openSubscriptions(ref, SubscriptionState.active),
        ),
        SaSegment(
          label: 'Expiring',
          value: stats.expiringSubs,
          tone: NivoraColors.warning,
          onTap: () => _openSubscriptions(ref, SubscriptionState.expiring),
        ),
        SaSegment(
          label: 'Expired',
          value: stats.expiredSubs,
          tone: NivoraColors.error,
          onTap: () => _openSubscriptions(ref, SubscriptionState.expired),
        ),
      ],
    );
  }
}

/// Lands the admin on the list the number was counting, already filtered.
void _openSubscriptions(WidgetRef ref, SubscriptionState state) {
  ref.read(saSubscriptionFilterProvider.notifier).set(state);
  ref.read(saTabProvider.notifier).go(SaTabs.subscriptions);
}

/// Twelve months of hostels joining the platform — the mockup's growth chart at 4:177.
/// public.rpc_sa_onboarding_series().
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

    return saAsync<List<OnboardingPoint>>(
      series,
      loading: () => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SaHeading(
            title: 'Hostel onboarding',
            domain: NivoraDomain.rooms,
            icon: Icons.apartment_rounded,
          ),
          SaSkeletonCard(lines: 3, height: 132),
        ],
      ),
      error: (e) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SaHeading(
            title: 'Hostel onboarding',
            domain: NivoraDomain.rooms,
            icon: Icons.apartment_rounded,
          ),
          SaError(
            error: e,
            compact: true,
            onRetry: () => ref.invalidate(saOnboardingProvider),
          ),
        ],
      ),
      data: (points) {
        if (points.isEmpty) {
          // NOT "no history yet". rpc_sa_onboarding_series is a generate_series over twelve
          // months with a count per month and `where app.is_super_admin()` on the end: a Super
          // Admin gets twelve rows on the day the platform is created, because a month with
          // nothing in it is still a row. NO rows at all is the refusal, and only the refusal.
          // Said plainly rather than as a second alarm — the block above has already said it
          // in full.
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SaHeading(
                title: 'Hostel onboarding',
                domain: NivoraDomain.rooms,
                icon: Icons.apartment_rounded,
              ),
              SaEmpty(
                icon: Icons.lock_outline_rounded,
                title: 'Onboarding history withheld',
                message: 'The server returns twelve months for the Super Admin whether or not '
                    'anything happened in them, so nothing coming back means this account was '
                    'not given the series — not that the platform is new.',
              ),
            ],
          );
        }

        final total = points.fold<int>(0, (s, p) => s + p.hostels);
        final latest = points.last;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 4:178 puts the section label on the left and one figure in the gold on the right.
            SaHeading(
              title: 'Hostel onboarding',
              caption: 'Added per month, last ${plural(points.length, 'month')} · '
                  '${plural(total, 'hostel')} over the period',
              accent: _momLabel(points),
              domain: NivoraDomain.rooms,
              icon: Icons.apartment_rounded,
            ),
            const SizedBox(height: Space.xs),
            SaBarChart(
              bars: [
                for (final point in points)
                  SaBar(
                    label: monthShort(point.month),
                    value: point.hostels,
                    caption: '${monthLabel(point.month)}: ${plural(point.hostels, 'hostel')}',
                  ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              latest.hostels == 0
                  ? 'None yet in ${monthLabel(latest.month)}'
                  : '${plural(latest.hostels, 'hostel')} in ${monthLabel(latest.month)}',
              style: t.textTheme.titleSmall,
            ),
          ],
        );
      },
    );
  }
}

/// The gold figure the design puts at the right of the growth section's title — 4:180, `+14% MoM`.
///
/// ARITHMETIC ON THE SERIES THE SERVER RETURNED, not a stored metric and not an invented one:
/// `rpc_sa_onboarding_series` hands back a count per month, and the change from the previous
/// month to the latest is a function of two of those counts. This is the one place a derived
/// figure is allowed on this screen, and it is allowed because both of its inputs are on the
/// chart directly beneath it.
///
/// NULL RATHER THAN A NUMBER whenever the change cannot be stated honestly: with fewer than two
/// months there is nothing to compare, and from a previous month of ZERO every percentage is
/// either undefined or absurd — one hostel after a quiet month is not "+100% growth". The slot
/// is simply not drawn in those cases, which is what an accent slot is for.
///
/// The previous month is NAMED. "+14% MoM" leaves the reader to guess which two months; naming
/// one of them costs three characters and removes the guess.
String? _momLabel(List<OnboardingPoint> points) {
  if (points.length < 2) return null;
  final now = points[points.length - 1].hostels;
  final before = points[points.length - 2].hostels;
  if (before == 0) return null;
  final pct = ((now - before) / before * 100).round();
  return '${pct > 0 ? '+' : ''}$pct% vs ${monthShort(points[points.length - 2].month)}';
}

/// Unacknowledged security alerts, and the way into the console — 4:201.
///
/// A COUNT AND NOT THE MOCKUP'S TWO ROWS. See the class note on [SaOverviewScreen]: reading the
/// alert log here would cost the Overview its uncontended first paint, which is the thing the
/// warm-up tests exist to protect. The row below is the mockup's alert-row anatomy — the tinted
/// caps badge, the sentence in cream, one meta line — around the number this screen may read.
class _Security extends ConsumerWidget {
  const _Security();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final open = ref.watch(saOpenAlertCountProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SaHeading(title: 'Security alerts', domain: NivoraDomain.security),
        saAsync<int>(
          open,
          loading: () => const SaSkeletonCard(lines: 1, height: 72),
          // An alert console that cannot be read is itself worth saying out loud, quietly.
          error: (e) => SaError(
            error: e,
            compact: true,
            onRetry: () => ref.invalidate(saOpenAlertCountProvider),
          ),
          data: (value) {
            final quiet = value == 0;
            final tone = quiet ? NivoraColors.textMuted : NivoraColors.error;
            return FlatSurface(
              weight: GlassWeight.regular,
              padding: const EdgeInsets.all(Space.xs),
              onTap: () => ref.read(saTabProvider.notifier).go(SaTabs.security),
              child: Row(
                children: [
                  StateBadge(label: quiet ? 'Clear' : 'Open', tone: tone),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quiet
                              ? 'Nothing outstanding'
                              : '${plural(value, 'alert')} awaiting acknowledgement',
                          style: t.textTheme.bodyMedium
                              ?.copyWith(color: t.colorScheme.onSurface),
                        ),
                        const SizedBox(height: Space.xxs / 2),
                        Text(
                          'Raised by the audit trail when it spots a pattern — a burst of '
                          'failed logins, or a session probing for rows it cannot read.',
                          style: t.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: IconSize.md,
                    color: t.colorScheme.outline,
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

/// The way into the create wizard, stated as what it does rather than as a plus button.
///
/// NOT IN 4:125, AND KEPT ANYWAY. The mockup's dashboard has no controls on it at all — it is a
/// reporting screen. Onboarding an owner is the one thing only this console can do, and burying
/// it behind a plus glyph in the header would trade a legible action for a faithful screenshot.
/// It is drawn in the design's own language — raised surface, caps label, the cream filled
/// button — and it sits above the first hairline so the mockup's document starts, intact, below
/// it.
class _CreateBanner extends StatelessWidget {
  const _CreateBanner({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FlatSurface(
      weight: GlassWeight.regular,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // The building's violet, not the gold: this tile is about a hostel, and the
              // brand colour was only ever holding the glyph up. The cream button below is
              // still the screen's one loud object.
              const DomainIcon(
                domain: NivoraDomain.rooms,
                icon: Icons.add_business_rounded,
                size: DomainIconSize.sm,
              ),
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

class _PlatformSkeleton extends StatelessWidget {
  const _PlatformSkeleton();

  @override
  Widget build(BuildContext context) {
    // Mirrors what actually arrives: two rows of two short tiles, then the health section.
    // A skeleton whose shape differs from the loaded screen makes the content appear to jump.
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SaSkeletonCard(lines: 1, height: 72)),
            SizedBox(width: Space.xs),
            Expanded(child: SaSkeletonCard(lines: 1, height: 72)),
          ],
        ),
        SizedBox(height: Space.xs),
        Row(
          children: [
            Expanded(child: SaSkeletonCard(lines: 1, height: 72)),
            SizedBox(width: Space.xs),
            Expanded(child: SaSkeletonCard(lines: 1, height: 72)),
          ],
        ),
        SaSectionRule(),
        SaSkeletonCard(lines: 2, height: 108),
      ],
    );
  }
}
