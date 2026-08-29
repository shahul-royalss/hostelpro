import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/super_admin/data/sa_models.dart';
import 'package:mobile/features/super_admin/data/sa_providers.dart';
import 'package:mobile/features/super_admin/sa_hostels_screen.dart';
import 'package:mobile/features/super_admin/sa_security_screen.dart';
import 'package:mobile/features/super_admin/sa_shell.dart';
import 'package:mobile/features/super_admin/sa_subscriptions_screen.dart';
import 'package:mobile/features/super_admin/widgets/sa_ui.dart';

/// THE PRODUCT OWNER'S COMPLAINT, HELD DOWN AS A TEST: "the system has to load fastly when we
/// clicks on any section... it has to come active without lazy load". Tapping a console tab
/// must NEVER show a skeleton or a spinner in normal use — the data must already be there,
/// warmed in the background after the Overview's own requests have won the network, and held
/// warm so a revisit renders instantly while any refresh happens BEHIND the shown value.
///
/// Every fetch below takes a real (fake-clock) 300ms, so if a tab tap had to fetch on arrival
/// the arrival frame COULD NOT show data — the row assertions would fail and the skeleton
/// finders would fire. Passing therefore proves the tap rendered from warm state, not from a
/// lucky instant network. Without this file, the next refactor of SaShell quietly
/// reintroduces the lazy load and nothing notices until the product owner does.
void main() {
  const latency = Duration(milliseconds: 300);

  const stats = SaStats(
    totalHostels: 12,
    totalOwners: 9,
    totalStudents: 418,
    activeSubs: 9,
    expiringSubs: 2,
    expiredSubs: 1,
    monthlySubscriptionRevenue: 184000,
  );

  final row = SaHostelRow(
    hostelId: '00000000-0000-0000-0000-0000000000b1',
    hostelName: 'Koramangala Residency for Working Professionals',
    hostelStatus: HostelStatus.active,
    ownerId: '00000000-0000-0000-0000-0000000000c1',
    ownerName: 'Ramesh Krishnamurthy',
    subState: SubscriptionState.expiring,
    daysLeft: 12,
    totalBeds: 48,
    occupiedBeds: 41,
    activeStudents: 41,
    openComplaints: 3,
    createdAt: DateTime.utc(2026, 1, 14),
  );

  final alert = SecurityAlert(
    id: 7,
    at: DateTime.utc(2026, 8, 28, 22, 15),
    severity: AlertSeverity.high,
    kind: 'failed_login_burst',
    summary: 'Nine failed logins for one account inside five minutes',
    details: const <String, dynamic>{},
  );

  const session = NivoraSession(
    userId: '00000000-0000-0000-0000-0000000000aa',
    role: UserRole.superAdmin,
    fullName: 'Platform Admin',
    status: 'active',
    mustChangePassword: false,
    email: 'admin@example.com',
  );

  /// Every request the console can make, in the order it was DISPATCHED — the network trace
  /// the stagger assertions read.
  late List<String> log;

  List<Object> overrides() => [
        sessionProvider.overrideWithValue(session),
        saStatsProvider.overrideWith((ref) {
          log.add('stats');
          return Future.delayed(latency, () => stats);
        }),
        saOnboardingProvider.overrideWith(
          (ref) => Future.delayed(
            latency,
            () => const [
              OnboardingPoint(month: '2026-07', hostels: 2),
              OnboardingPoint(month: '2026-08', hostels: 1),
            ],
          ),
        ),
        saOpenAlertCountProvider.overrideWith((ref) => Future.delayed(latency, () => 1)),
        // The fakes below override ONLY the fetch, so the real builds — including the
        // holdForSession that keeps warmed pages alive with no listener — still run. That is
        // the mechanism under test; stubbing it out would make every assertion vacuous.
        saHostelListProvider.overrideWith2((query) => _SlowHostels(query, log, row)),
        saAlertsProvider.overrideWith2((openOnly) => _SlowAlerts(openOnly, log, alert)),
      ];

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides().cast(),
        child: MaterialApp(
          theme: NivoraTheme.light(),
          debugShowCheckedModeBanner: false,
          home: const SaShell(),
        ),
      ),
    );
  }

  /// A destination on the bottom bar, told apart from a screen title wearing the same word.
  Finder destination(String label) =>
      find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

  /// The two shapes of "still loading" a tab could betray the contract with. The thin
  /// LinearProgressIndicator is exempt: it is the designed silent-refresh affordance and only
  /// ever draws OVER shown data.
  void expectNoSkeletonOrSpinner() {
    expect(find.byType(SaSkeleton), findsNothing);
    expect(find.byType(SaSkeletonCard), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  }

  testWidgets('the Overview wins the network, warm-up is staggered behind it, '
      'and every tab then arrives with data — no skeleton, no spinner, no refetch',
      (tester) async {
    log = [];
    await pumpShell(tester);

    // FRAME ONE. The home tab's own request is on the wire; no warmer has jumped it. The
    // skeleton here is the one legitimate skeleton in the whole session: the genuinely cold
    // first paint.
    expect(log, ['stats']);
    expect(find.byType(SaSkeleton), findsWidgets);

    // Inside the head start (first warmer fires at +150ms): still only the home request.
    await tester.pump(const Duration(milliseconds: 100));
    expect(log, ['stats'], reason: 'warm-up must not contend with the first paint');

    // Let the stagger play out and every fake fetch land.
    await tester.pump(const Duration(milliseconds: 1400));
    expect(
      log,
      [
        'stats',
        'hostels(all) p0', // +150ms — also the Subscriptions tab's default page
        'alerts(openOnly: true)', // +300ms
        'hostels(expiring) p0', // +450ms — the Overview's "expiring" deep-link target
        'hostels(expired) p0', // +600ms — and its "expired" one
      ],
      reason: 'one warmer per interval, in tap-likelihood order, home never among them',
    );

    // The Overview is now fully drawn — and from here on, NOTHING may show a skeleton.
    expect(find.textContaining('12'), findsWidgets, reason: 'the hero figure');
    expectNoSkeletonOrSpinner();

    // ── HOSTELS, one frame after the tap. The fetch takes 300ms, so this row can only be
    // here if the tap rendered from the warmed, session-held page.
    await tester.tap(destination('Hostels'));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(SaHostelsScreen), matching: find.text(row.hostelName)),
      findsOneWidget,
      reason: 'arrival must render the data, not earn it',
    );
    expectNoSkeletonOrSpinner();

    // ── SUBSCRIPTIONS, one frame after the tap — served by the SAME warmed page as Hostels
    // (the default query is value-equal), so still no new request.
    await tester.tap(destination('Subscriptions'));
    await tester.pump();
    expect(
      find.descendant(
          of: find.byType(SaSubscriptionsScreen), matching: find.text(row.hostelName)),
      findsOneWidget,
    );
    expectNoSkeletonOrSpinner();

    // ── SECURITY, one frame after the tap.
    await tester.tap(destination('Security'));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(SaSecurityScreen), matching: find.text(alert.summary)),
      findsOneWidget,
    );
    expectNoSkeletonOrSpinner();

    // ── REVISIT. Back to Hostels: instant, from the kept widget and the held page.
    await tester.tap(destination('Hostels'));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(SaHostelsScreen), matching: find.text(row.hostelName)),
      findsOneWidget,
    );
    expectNoSkeletonOrSpinner();

    // The whole tour — three first visits and a revisit — cost ZERO requests beyond the five
    // dispatched at sign-in. That is the product owner's "like Google apps" bar, measured.
    expect(log.length, 5, reason: 'tab taps must never be what starts a fetch');
  });

  testWidgets('a background refresh renders the held page while it is in flight — '
      'a revisit never blanks back to a skeleton', (tester) async {
    log = [];
    await pumpShell(tester);
    await tester.pump(const Duration(milliseconds: 1500)); // warm everything

    await tester.tap(destination('Hostels'));
    await tester.pump();
    expect(find.text(row.hostelName), findsOneWidget);

    // Something invalidates the list — a pull-to-refresh, a mutation elsewhere — while the
    // admin is looking at another tab.
    await tester.tap(destination('Security'));
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(SaShell)));
    container.invalidate(saHostelListProvider(const SaHostelQuery()));
    await tester.pump();
    expect(log.last, 'hostels(all) p0', reason: 'the refetch is now in flight');

    // Coming back mid-refresh: the PREVIOUS page is what renders. The only permitted trace of
    // the refresh is the 2dp progress line drawn over it.
    await tester.tap(destination('Hostels'));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(SaHostelsScreen), matching: find.text(row.hostelName)),
      findsOneWidget,
      reason: 'stale-while-revalidate: the held value shows during the refresh',
    );
    expectNoSkeletonOrSpinner();
    // The indeterminate 2dp line, told apart from the determinate occupancy meter each hostel
    // row draws with the same widget.
    Finder refreshLine() => find.byWidgetPredicate(
        (w) => w is LinearProgressIndicator && w.value == null,
        description: 'indeterminate LinearProgressIndicator');
    expect(refreshLine(), findsOneWidget,
        reason: 'the refresh really was still in flight when the row above rendered');

    // The refresh lands; the row is simply replaced in place.
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.descendant(of: find.byType(SaHostelsScreen), matching: find.text(row.hostelName)),
      findsOneWidget,
    );
    expect(refreshLine(), findsNothing);
  });
}

/// The real notifier — real [PagedNotifier.build], real holdForSession — with only the network
/// swapped for a 300ms fake, and every dispatch written to the shared log.
class _SlowHostels extends SaHostelListNotifier {
  _SlowHostels(super.query, this.log, this.row);
  final List<String> log;
  final SaHostelRow row;

  @override
  Future<PagedResult<SaHostelRow>> fetchPage(int page) {
    log.add('hostels(${query.subState?.name ?? 'all'}) p$page');
    return Future.delayed(
      const Duration(milliseconds: 300),
      () => PagedResult<SaHostelRow>(items: [row], page: page, pageSize: 20, hasMore: false),
    );
  }
}

/// Same shape for the security console: the real build (and its holdForSession) runs; only
/// [SaAlertsNotifier.fetch] is substituted.
class _SlowAlerts extends SaAlertsNotifier {
  _SlowAlerts(super.openOnly, this.log, this.alert);
  final List<String> log;
  final SecurityAlert alert;

  @override
  Future<List<SecurityAlert>> fetch() {
    log.add('alerts(openOnly: $openOnly)');
    return Future.delayed(const Duration(milliseconds: 300), () => [alert]);
  }
}
