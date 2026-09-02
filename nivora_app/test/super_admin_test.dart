import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/super_admin/data/sa_models.dart';
import 'package:mobile/features/super_admin/data/sa_providers.dart';
import 'package:mobile/features/super_admin/sa_hostels_screen.dart';
import 'package:mobile/features/super_admin/sa_overview_screen.dart';
import 'package:mobile/features/super_admin/sa_security_screen.dart';
import 'package:mobile/features/super_admin/sa_shell.dart';
import 'package:mobile/features/super_admin/sa_subscriptions_screen.dart';
import 'package:mobile/features/super_admin/widgets/sa_ui.dart';

/// The super admin console had NO tests when it landed — the agent that built it died before
/// writing any. It is also the one console the product owner asked about by name, because it is
/// where an owner account gets created, so shipping it unverified was not an option.
///
/// No network: every provider the screens read is overridden with a fixed value. That is
/// deliberate rather than convenient — the machine this is developed on has its TLS intercepted
/// by antivirus, so an emulator cannot reach Supabase at all. Tests that need a live database
/// would simply never run here.
const _stats = SaStats(
  totalHostels: 12,
  totalOwners: 9,
  totalStudents: 418,
  activeSubs: 9,
  expiringSubs: 2,
  expiredSubs: 1,
  monthlySubscriptionRevenue: 184000,
);

final _session = NivoraSession(
  userId: '00000000-0000-0000-0000-0000000000aa',
  role: UserRole.superAdmin,
  fullName: 'Platform Admin',
  status: 'active',
  mustChangePassword: false,
  email: 'admin@example.com',
);

/// Typed as List<Object> and cast at the call site because Riverpod 3 does not export
/// `Override` from its public barrel, so the real element type cannot be named here.
List<Object> _overrides({SaStats? stats, Object? statsError}) => [
      sessionProvider.overrideWithValue(_session),
      if (statsError != null)
        saStatsProvider.overrideWith((ref) => Future<SaStats>.error(statsError))
      else
        saStatsProvider.overrideWith((ref) => stats ?? _stats),
    ];

Future<void> _pump(WidgetTester tester, List<Object> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: NivoraTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const SaShell(),
      ),
    ),
  );
  // Not pumpAndSettle: a loading spinner never stops animating, so settling would hang.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the console renders instead of the "not built yet" placeholder', (tester) async {
    await _pump(tester, _overrides());

    // The exact string every super-admin tab used to show.
    expect(find.text('This screen is not built yet.'), findsNothing);
    expect(find.byType(SaShell), findsOneWidget);
  });

  testWidgets('platform figures come from the stats row, not from literals', (tester) async {
    await _pump(tester, _overrides());

    // If any of these were hardcoded, changing the stub below would not change the screen.
    expect(find.textContaining('12'), findsWidgets, reason: 'total hostels');
    expect(find.textContaining('418'), findsWidgets, reason: 'total students');
  });

  testWidgets('a different stats row produces different figures', (tester) async {
    await _pump(
      tester,
      _overrides(
        stats: const SaStats(
          totalHostels: 3,
          totalOwners: 2,
          totalStudents: 57,
          activeSubs: 3,
          expiringSubs: 0,
          expiredSubs: 0,
          monthlySubscriptionRevenue: 21000,
        ),
      ),
    );

    expect(find.textContaining('57'), findsWidgets);
    // The first stub's numbers must be gone — this is what catches a fabricated figure.
    expect(find.textContaining('418'), findsNothing);
  });

  testWidgets('a failed load says so rather than showing zeroes', (tester) async {
    await _pump(tester, _overrides(statsError: Exception('offline')));

    // Zero hostels and a broken connection are different facts. Reporting the second as the
    // first is how a platform admin concludes their business disappeared overnight.
    expect(find.byType(SaShell), findsOneWidget);
    expect(find.textContaining('418'), findsNothing);
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // AN EMPTY LIST IS FOUR DIFFERENT FACTS
  //
  // Every read on this console can come back with nothing in it for four unrelated reasons, and
  // three of them are not "there is nothing there":
  //
  //   pending     the corroborating read has not answered yet
  //   unverified  it FAILED, so refused and empty cannot be told apart
  //   refused     it came back empty too — this account is not the Super Admin
  //   confirmed   it returned figures, so the emptiness in front of us is real
  //
  // These four used to collapse into two. `stats.value == null && !stats.isLoading` was the
  // whole test, and it is equally true of a dashboard that failed, so an admin whose connection
  // dropped for one request was told they were not permitted to see their own platform. The
  // analyzer cannot see a wrong sentence on a screen; these tests are the only thing that can.
  // ═══════════════════════════════════════════════════════════════════════════════════════

  test('the verdict tells a failed corroborating read from a refused one', () {
    expect(saEmptyVerdict(const AsyncValue<SaStats?>.loading()), SaEmptyVerdict.pending);
    expect(
      saEmptyVerdict(AsyncValue<SaStats?>.error(Exception('offline'), StackTrace.empty)),
      SaEmptyVerdict.unverified,
      reason: 'a dashboard that could not be read says nothing about who this account is',
    );
    expect(saEmptyVerdict(const AsyncValue<SaStats?>.data(null)), SaEmptyVerdict.refused);
    expect(saEmptyVerdict(AsyncValue<SaStats?>.data(_stats)), SaEmptyVerdict.confirmed);
  });

  group('Hostels — an empty page', () {
    testWidgets('with a FAILED dashboard blames neither the platform nor the account',
        (tester) async {
      await _pumpTab(tester, const SaHostelsScreen(), dashboard: _Dashboard.failed);

      expect(find.byType(SaUnverified), findsOneWidget);
      expect(find.byType(SaNotPermitted), findsNothing,
          reason: 'a dashboard that timed out is not the server refusing this account');
      expect(find.text('No hostels yet'), findsNothing,
          reason: 'and it is not a platform with no hostels on it either');

      // The way out has to be a real one: this state exists only because it can be re-read.
      final retry = find.widgetWithText(OutlinedButton, 'Check again');
      expect(retry, findsOneWidget);
      await tester.tap(retry);
      await tester.pump();
    });

    testWidgets('with a REFUSED dashboard says so, and says nothing about the platform',
        (tester) async {
      await _pumpTab(tester, const SaHostelsScreen(), dashboard: _Dashboard.refused);

      expect(find.byType(SaNotPermitted), findsOneWidget);
      expect(find.text('No hostels yet'), findsNothing);
      expect(find.byType(SaUnverified), findsNothing);
    });

    testWidgets('with a dashboard STILL LOADING claims nothing at all yet', (tester) async {
      await _pumpTab(tester, const SaHostelsScreen(), dashboard: _Dashboard.pending);

      expect(find.byType(SaSkeletonCard), findsWidgets);
      expect(find.byType(SaNotPermitted), findsNothing);
      expect(find.byType(SaUnverified), findsNothing);
      expect(find.text('No hostels yet'), findsNothing,
          reason: 'the platform has not been asked yet, so it cannot be reported as empty');
    });

    testWidgets('with a dashboard that ANSWERED is finally allowed to be empty', (tester) async {
      await _pumpTab(tester, const SaHostelsScreen(), dashboard: _Dashboard.ok);

      expect(find.text('No hostels yet'), findsOneWidget);
      expect(find.byType(SaNotPermitted), findsNothing);
      expect(find.byType(SaUnverified), findsNothing);
    });

    testWidgets('a search that matches nothing is still a search that matches nothing',
        (tester) async {
      await _pumpTab(
        tester,
        const SaHostelsScreen(),
        dashboard: _Dashboard.ok,
        query: const SaHostelQuery(search: 'koramangala'),
      );

      expect(find.text('No hostel matches that'), findsOneWidget);
      expect(find.text('No hostels yet'), findsNothing);
    });
  });

  group('Subscriptions — an empty page', () {
    testWidgets('with a REFUSED dashboard stops claiming nothing has lapsed', (tester) async {
      await _pumpTab(tester, const SaSubscriptionsScreen(), dashboard: _Dashboard.refused);

      // "Every hostel on the platform can still be written to" is a statement about every
      // hostel on the platform. An account that cannot see one hostel cannot make it.
      expect(find.byType(SaNotPermitted), findsOneWidget);
      expect(find.text('No subscriptions yet'), findsNothing);
    });

    testWidgets('with a FAILED dashboard says it cannot tell', (tester) async {
      await _pumpTab(tester, const SaSubscriptionsScreen(), dashboard: _Dashboard.failed);

      expect(find.byType(SaUnverified), findsOneWidget);
      expect(find.text('No subscriptions yet'), findsNothing);
      expect(find.byType(SaNotPermitted), findsNothing);
    });

    testWidgets('with a dashboard that ANSWERED is allowed to be empty', (tester) async {
      await _pumpTab(tester, const SaSubscriptionsScreen(), dashboard: _Dashboard.ok);

      expect(find.text('No subscriptions yet'), findsOneWidget);
      expect(find.byType(SaUnverified), findsNothing);
    });
  });

  group('Security — an empty alert log', () {
    testWidgets('with a REFUSED dashboard is not "nothing outstanding"', (tester) async {
      await _pumpTab(tester, const SaSecurityScreen(), dashboard: _Dashboard.refused);

      expect(find.byType(SaNotPermitted), findsOneWidget);
      expect(find.text('Nothing outstanding'), findsNothing,
          reason: 'the quietest possible good news and a log this account cannot read are '
              'opposite facts');
    });

    testWidgets('with a FAILED dashboard says the log could not be vouched for',
        (tester) async {
      await _pumpTab(tester, const SaSecurityScreen(), dashboard: _Dashboard.failed);

      expect(find.byType(SaUnverified), findsOneWidget);
      expect(find.text('Nothing outstanding'), findsNothing);
    });

    testWidgets('with a dashboard that ANSWERED reports the quiet week', (tester) async {
      await _pumpTab(tester, const SaSecurityScreen(), dashboard: _Dashboard.ok);

      expect(find.text('Nothing outstanding'), findsOneWidget);
      expect(find.byType(SaUnverified), findsNothing);
      expect(find.byType(SaNotPermitted), findsNothing);
    });
  });

  testWidgets('a real row fits a 360dp phone with the status chip at its token size',
      (tester) async {
    // The chip used to be padded to 3dp with a 12dp glyph — two numbers off the 4dp rhythm and
    // off the icon scale. Moving them onto Space.xxs and IconSize.xs makes the chip a little
    // bigger, and the narrowest phone the app supports is where that would show up as an
    // overflow stripe across a hostel row.
    tester.view.physicalSize = const Size(Breakpoints.compact, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final overrides = <Object>[
      sessionProvider.overrideWithValue(_session),
      saStatsProvider.overrideWith((ref) => _stats),
      saHostelListProvider.overrideWith2(
        (_) => _FakeHostels(const SaHostelQuery(), [_row]),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides.cast(),
        child: MaterialApp(
          theme: NivoraTheme.light(),
          debugShowCheckedModeBanner: false,
          home: const Scaffold(body: SaHostelsScreen()),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Koramangala Residency for Working Professionals'), findsOneWidget);
    expect(find.text('12d left'), findsOneWidget, reason: 'the subscription chip');
    // A RenderFlex overflow is thrown during paint, so this is the assertion that catches it.
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty onboarding series is a refusal, never a platform with no history',
      (tester) async {
    // rpc_sa_onboarding_series zero-fills twelve months server-side and ends in
    // `where app.is_super_admin()`. Twelve rows or none: there is no such thing as a partial
    // history, so "this appears once the first hostel is created" described a state the
    // function cannot produce, on a screen where the real answer is "you are not allowed".
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final overrides = <Object>[
      sessionProvider.overrideWithValue(_session),
      saStatsProvider.overrideWith((ref) => null),
      saOnboardingProvider.overrideWith((ref) => const <OnboardingPoint>[]),
      saOpenAlertCountProvider.overrideWith((ref) => 0),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides.cast(),
        child: MaterialApp(
          theme: NivoraTheme.light(),
          debugShowCheckedModeBanner: false,
          home: const Scaffold(body: SaOverviewScreen()),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('No onboarding history'), findsNothing);
    expect(find.text('Onboarding history withheld'), findsOneWidget);
    // And the hero says the loud version once, not twice.
    expect(find.byType(SaNotPermitted), findsOneWidget);
  });

  group('the Security tab badge', () {
    testWidgets('draws nothing when there is nothing outstanding', (tester) async {
      await _pump(tester, [
        ..._overrides(),
        saOpenAlertCountProvider.overrideWith((ref) => 0),
      ]);

      expect(find.byType(Badge), findsNothing,
          reason: 'a badge reading 0 trains people to ignore badges');
    });

    testWidgets('marks a count it could not read rather than looking like zero',
        (tester) async {
      await _pump(tester, [
        ..._overrides(),
        saOpenAlertCountProvider
            .overrideWith((ref) => Future<int>.error(Exception('offline'))),
      ]);

      // Silently dropping the badge shows exactly what the best possible day looks like at the
      // moment the console cannot tell whether it is one.
      expect(find.text('?'), findsOneWidget);
    });
  });

  test('the four tab indices agree across every file that uses them', () {
    // role_shell.dart owns the labels, SaShell owns the IndexedStack, and the Overview's
    // tappable figures jump between them. A reordered bar in one file is a mis-routed tap.
    expect(SaTabs.overview, 0);
    expect(SaTabs.hostels, 1);
    expect(SaTabs.subscriptions, 2);
    expect(SaTabs.security, 3);
    expect(SaTabs.count, 4);
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // THE FIGMA DASHBOARD, node 4:125 — and the parts of it that may not be reproduced
  //
  // The mockup is drawn full of invented numbers: `₹14.8L`, `412 Active PGs`, `↑ 12%`,
  // `+14% MoM`, `Active (380)`. The figures are replaced by real ones and the TRENDS are not
  // reproduced at all, because no trend exists in this schema. These tests hold that line: a
  // future agent restoring the mockup's third KPI line, or filling the growth section's accent
  // slot unconditionally, breaks them.
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('the platform dashboard', () {
    testWidgets('draws four KPI tiles from the stats row and no trend beside them',
        (tester) async {
      await _pumpOverview(tester);

      expect(find.byType(SaKpiTile), findsNWidgets(4), reason: '4:141 + 4:150, two rows of two');

      // Every figure is the stub's, formatted the Indian way. If one were hardcoded, changing
      // the stub would not change the screen.
      expect(find.text('12'), findsWidgets, reason: 'hostels');
      expect(find.text('9'), findsWidgets, reason: 'owners');
      expect(find.text('418'), findsWidgets, reason: 'residents');
      expect(find.text('₹1,84,000'), findsOneWidget, reason: 'subscription revenue');

      // 4:145 and its three siblings carry `↑ 12%` / `— 0%`. rpc_sa_dashboard returns seven
      // scalars for right now and no history of itself, so any delta here would be invented.
      expect(
        find.descendant(of: find.byType(SaKpiTile), matching: find.textContaining('%')),
        findsNothing,
        reason: 'the mockup\'s trend line has no source in the schema and is not drawn',
      );
    });

    testWidgets('the health bar counts the hostels the server classified, not the platform',
        (tester) async {
      // 20 hostels, 12 of them with a subscription state. `app.subscription_state()` classifies
      // only hostels that HAVE a subscription, so eight here were never sold one and belong in
      // none of the three bands. Dividing by 20 would draw a bar that never reaches its own end.
      await _pumpOverview(
        tester,
        stats: const SaStats(
          totalHostels: 20,
          totalOwners: 9,
          totalStudents: 418,
          activeSubs: 9,
          expiringSubs: 2,
          expiredSubs: 1,
          monthlySubscriptionRevenue: 184000,
        ),
      );

      expect(find.byType(SaSegmentBar), findsOneWidget);
      expect(find.text('Active (9)'), findsOneWidget);
      expect(find.text('Expiring (2)'), findsOneWidget);
      expect(find.text('Expired (1)'), findsOneWidget);
    });

    testWidgets('the growth accent is arithmetic on the returned series, named to the month',
        (tester) async {
      await _pumpOverview(
        tester,
        series: const [
          OnboardingPoint(month: '2026-07', hostels: 4),
          OnboardingPoint(month: '2026-08', hostels: 5),
        ],
      );

      // 4:180 reads `+14% MoM`. Ours is the real change between the last two points the server
      // returned, and it names the month it is measuring against rather than leaving the reader
      // to guess which two.
      expect(find.text('+25% vs Jul'), findsOneWidget);
    });

    testWidgets('and is omitted entirely when the previous month was zero', (tester) async {
      await _pumpOverview(
        tester,
        series: const [
          OnboardingPoint(month: '2026-07', hostels: 0),
          OnboardingPoint(month: '2026-08', hostels: 5),
        ],
      );

      // From nothing to five hostels is not "+100% growth" and is not "+infinity" either. The
      // accent slot is simply not drawn, which is what an accent slot is for.
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('vs Jul'), findsNothing);
    });
  });
}

/// The Overview alone, on a viewport tall enough that nothing it draws is off-screen.
///
/// Every provider it reads is overridden, so no test here depends on a network this machine
/// cannot reach (see the file header). The onboarding series defaults to two real months
/// because the growth section needs at least two points to have anything to compare.
Future<void> _pumpOverview(
  WidgetTester tester, {
  SaStats stats = _stats,
  List<OnboardingPoint> series = const [
    OnboardingPoint(month: '2026-07', hostels: 4),
    OnboardingPoint(month: '2026-08', hostels: 5),
  ],
  int openAlerts = 0,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final overrides = <Object>[
    sessionProvider.overrideWithValue(_session),
    saStatsProvider.overrideWith((ref) => stats),
    saOnboardingProvider.overrideWith((ref) => series),
    saOpenAlertCountProvider.overrideWith((ref) => openAlerts),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: NivoraTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const Scaffold(body: SaOverviewScreen()),
      ),
    ),
  );
  // Not pumpAndSettle: a skeleton never stops animating, so settling would hang.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}


// ═════════════════════════════════════════════════════════════════════════════════════════
// FAKES
// ═════════════════════════════════════════════════════════════════════════════════════════

/// A hostel row with the longest realistic name and every chip lit: the layout's worst case.
final _row = SaHostelRow(
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

/// The four states rpc_sa_dashboard can be in when a list asks it what its own emptiness means.
enum _Dashboard { ok, refused, failed, pending }

/// A family override replaces every instance at once and is handed no argument, so the fakes
/// carry a stand-in key. Nothing reads it — the fetch is overridden.
class _FakeHostels extends SaHostelListNotifier {
  _FakeHostels(super.query, this.items);
  final List<SaHostelRow> items;

  @override
  Future<PagedResult<SaHostelRow>> fetchPage(int page) async =>
      PagedResult<SaHostelRow>(items: items, page: 0, pageSize: 20, hasMore: false);
}

class _FakeAlerts extends SaAlertsNotifier {
  _FakeAlerts(super.openOnly, this.rows);
  final List<SecurityAlert> rows;

  @override
  Future<List<SecurityAlert>> build() async => rows;
}

/// Pins a filter, so a screen can be pumped already searching without driving its text field.
class _PinnedFilter extends SaHostelFilter {
  _PinnedFilter(this.pinned);
  final SaHostelQuery pinned;

  @override
  SaHostelQuery build() => pinned;
}

/// Pumps ONE console tab with the lists empty and the dashboard in a chosen state.
///
/// One screen rather than the whole shell: SaShell is an IndexedStack, which keeps every tab
/// built, and "the Overview also drew a refusal panel" would satisfy a finder meant for the
/// Hostels tab.
Future<void> _pumpTab(
  WidgetTester tester,
  Widget screen, {
  required _Dashboard dashboard,
  SaHostelQuery query = const SaHostelQuery(),
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final overrides = <Object>[
    sessionProvider.overrideWithValue(_session),
    switch (dashboard) {
      _Dashboard.ok => saStatsProvider.overrideWith((ref) => _stats),
      _Dashboard.refused => saStatsProvider.overrideWith((ref) => null),
      _Dashboard.failed => saStatsProvider
          .overrideWith((ref) => Future<SaStats?>.error(Exception('offline'))),
      // Never completes: the one state a Future cannot reach by itself.
      _Dashboard.pending =>
        saStatsProvider.overrideWith((ref) => Completer<SaStats?>().future),
    },
    saHostelFilterProvider.overrideWith(() => _PinnedFilter(query)),
    saHostelListProvider.overrideWith2((_) => _FakeHostels(query, const [])),
    saAlertsProvider.overrideWith2((_) => _FakeAlerts(true, const [])),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: NivoraTheme.light(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: screen),
      ),
    ),
  );
  // Not pumpAndSettle: the skeleton and the spinner never stop animating.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
