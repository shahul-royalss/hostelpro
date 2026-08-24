// Widget tests for the owner dashboard.
//
// WHAT THESE ARE FOR. The unit tests in owner_test.dart prove the sentences are right; these
// prove they reach the screen. Between the two sits everything a compiler cannot see — a
// provider read that never resolves, a card that throws on an empty list, a loading state that
// replaces the page with a spinner, an error that offers a retry button for a permission
// refusal. Each of those looks fine in an analyzer and is the first thing a user hits.
//
// No network: every provider the screen reads is overridden with a fixed value, which is
// exactly what lib/data/providers.dart was shaped for.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/owner/owner_dashboard_screen.dart';
import 'package:mobile/features/owner/owner_insights.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/owner/widgets/states.dart';
import 'package:mobile/features/shell/role_shell.dart';

const _period = '2026-08';
const _hostelId = 'h-sunrise';

final _session = const NivoraSession(
  userId: 'owner-1',
  role: UserRole.owner,
  fullName: 'Ananya Rao',
  status: 'active',
  mustChangePassword: false,
  hostelId: _hostelId,
);

final _sunrise = Hostel(
  id: _hostelId,
  name: 'Sunrise Residency',
  ownerUserId: 'owner-1',
  totalFloors: 3,
  totalRooms: 12,
  bedsPerRoomDefault: 3,
  status: HostelStatus.active,
  createdAt: DateTime.utc(2026, 3, 1),
  updatedAt: DateTime.utc(2026, 3, 1),
);

HostelStats _stats({
  int totalBeds = 36,
  int occupiedBeds = 12,
  int activeStudents = 12,
  int openComplaints = 3,
  double feesCollected = 50200,
  double feesPending = 33800,
  int studentsPaid = 6,
  int studentsUnpaid = 6,
  int pendingLeaves = 0,
  int pendingTasks = 1,
  double revenueMonth = 45200,
  double expensesMonth = 50400,
  SubscriptionState subscriptionState = SubscriptionState.active,
  int? subscriptionDaysLeft = 300,
}) {
  return HostelStats(
    totalBeds: totalBeds,
    occupiedBeds: occupiedBeds,
    activeStudents: activeStudents,
    openComplaints: openComplaints,
    feesCollected: feesCollected,
    feesPending: feesPending,
    studentsPaid: studentsPaid,
    studentsUnpaid: studentsUnpaid,
    pendingLeaves: pendingLeaves,
    visitorsToday: 0,
    pendingTasks: pendingTasks,
    revenueToday: 0,
    expensesToday: 0,
    revenueMonth: revenueMonth,
    expensesMonth: expensesMonth,
    subscriptionState: subscriptionState,
    subscriptionDaysLeft: subscriptionDaysLeft,
  );
}

final _window = FinanceRangeQuery(
  hostelId: _hostelId,
  from: DateTime(2026, 7, 26),
  to: DateTime(2026, 8, 24),
);

List<FinanceDay> _series() => [
  for (var i = 0; i < 30; i++)
    FinanceDay(
      day: DateTime(2026, 7, 26 + i),
      revenue: i.isEven ? 1500 : 0,
      expense: i % 3 == 0 ? 900 : 0,
    ),
];

/// Everything the dashboard reads, pinned to a fixed value.
///
/// Returned inline rather than as a typed variable: riverpod 3 does not export the `Override`
/// type, so the list has to be inferred at the point it is handed to [ProviderScope].
Future<void> _pumpDashboard(
  WidgetTester tester, {
  HostelStats? stats,
  Object? statsError,
  bool statsPending = false,
  List<Hostel> owned = const [],
  AsyncValue<List<ActivityItem>>? activity,
  bool throughShell = false,
}) async {
  // A phone-sized surface only builds what fits on it, and a ListView does not build what is
  // off screen — so a 600pt window would make "the section below the chart is missing" and
  // "the section below the chart is broken" look identical. The dashboard is one scroll on a
  // real phone; here it is given room to render in one frame.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(_session),
        currentHostelIdProvider.overrideWithValue(_hostelId),
        currentPeriodMonthProvider.overrideWithValue(_period),
        myHostelsProvider.overrideWith((ref) => owned.isEmpty ? [_sunrise] : owned),
        ownerFinanceWindowProvider.overrideWithValue(_window),
        hostelStatsProvider.overrideWith((ref, query) {
          // Future.error, not a synchronous throw: riverpod 3 swallows a sync throw from an
          // override and leaves the provider loading forever, which would test nothing.
          if (statsError != null) return Future<HostelStats?>.error(statsError);
          if (statsPending) return Completer<HostelStats?>().future;
          return stats ?? _stats();
        }),
        dailyFinanceProvider.overrideWith((ref, query) => _series()),
        ownerActivityProvider.overrideWith((ref, hostelId) => activity ?? AsyncData(_activity())),
      ],
      child: MaterialApp(
        // The app's own theme is built on google_fonts, which would try to fetch a font file
        // over the network from inside the test binary. The layout under test does not depend
        // on the typeface — only on the scale's slot names, which the stock theme also has.
        home: throughShell
            ? const RoleShell(role: UserRole.owner)
            : const Scaffold(body: OwnerDashboardScreen()),
      ),
    ),
  );
  // Never pumpAndSettle here: the skeletons pulse forever by design, so a settle would hang
  // the moment one of them is on screen.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

List<ActivityItem> _activity() => [
  ActivityItem(
    kind: ActivityKind.complaint,
    id: 'c1',
    title: 'Geyser not heating',
    detail: 'Maintenance',
    at: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
    complaintStatus: ComplaintStatus.open,
  ),
  ActivityItem(
    kind: ActivityKind.notice,
    id: 'n1',
    title: 'Water tanker on Sunday',
    detail: 'Notice to everyone',
    at: DateTime.now().toUtc().subtract(const Duration(days: 1)),
  ),
];

void main() {
  testWidgets('the hero is the month\'s collections, with what it means underneath', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    // Not asserted against a fixed greeting: "Good morning" depends on the clock the test
    // happens to run under, and a test that fails at 5pm is worse than no test.
    expect(find.textContaining('Ananya'), findsOneWidget);
    expect(find.text('Sunrise Residency'), findsOneWidget);
    expect(find.text('COLLECTED IN AUGUST'), findsOneWidget);
    expect(find.text('₹50,200'), findsOneWidget);
    expect(find.text('₹33,800 still to collect from 6 residents.'), findsOneWidget);
    expect(find.text('6 of 12 residents have paid in full.'), findsOneWidget);
  });

  testWidgets('a first load is a skeleton of the real layout, not a spinner', (tester) async {
    await _pumpDashboard(tester, statsPending: true);

    // The brief's line, under test: no full-screen spinner. The page keeps its shape and fills
    // in, so nothing jumps when the numbers land.
    expect(find.byType(Skeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The greeting is not behind the query, so it is readable immediately.
    expect(find.textContaining('Ananya'), findsOneWidget);
  });

  testWidgets('occupancy states the figure and the vacancy', (tester) async {
    await _pumpDashboard(tester);

    expect(find.text('12 of 36 beds filled'), findsOneWidget);
    expect(find.text('33% occupancy — 24 beds vacant.'), findsOneWidget);
  });

  testWidgets('only outstanding things appear under NEEDS YOU', (tester) async {
    await _pumpDashboard(tester);

    expect(find.text('6 residents have not paid'), findsOneWidget);
    expect(find.text('3 complaints still open'), findsOneWidget);
    expect(find.text('1 task not done'), findsOneWidget);
    // pending_leaves is zero for this hostel, so it is absent rather than shown as "0".
    expect(find.textContaining('leave request'), findsNothing);
  });

  testWidgets('a clear morning gets a real empty state, not a row of zeroes', (tester) async {
    await _pumpDashboard(
      tester,
      stats: _stats(
        openComplaints: 0,
        pendingTasks: 0,
        studentsUnpaid: 0,
        studentsPaid: 12,
        feesPending: 0,
        feesCollected: 84000,
        occupiedBeds: 12,
        activeStudents: 12,
      ),
    );

    expect(find.text('Nothing is waiting on you'), findsOneWidget);
    expect(find.text('Every resident has paid this month.'), findsOneWidget);
  });

  testWidgets('the month totals are labelled apart from the 30-day chart', (tester) async {
    await _pumpDashboard(tester);

    expect(find.text('AUGUST SO FAR'), findsOneWidget);
    expect(find.text('₹45,200'), findsOneWidget);
    expect(find.text('₹50,400'), findsOneWidget);
    // The month is running at a loss, and the net figure says so rather than hiding the sign.
    expect(find.text('-₹5,200'), findsOneWidget);
    expect(find.textContaining('Fee collections are counted separately'), findsOneWidget);
  });

  testWidgets('recent activity puts complaints and notices on one timeline', (tester) async {
    await _pumpDashboard(tester);

    expect(find.text('Geyser not heating'), findsOneWidget);
    expect(find.text('Water tanker on Sunday'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('an empty feed says what would appear there', (tester) async {
    await _pumpDashboard(tester, activity: const AsyncData(<ActivityItem>[]));
    expect(find.text('Nothing has happened yet'), findsOneWidget);
  });

  testWidgets('a lapsed subscription is stated, and offers no button it cannot honour', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      stats: _stats(subscriptionState: SubscriptionState.expired, subscriptionDaysLeft: -3),
    );

    expect(find.text('Subscription expired 3 days ago'), findsOneWidget);
    expect(find.textContaining('read-only'), findsOneWidget);
    // Renewal is a Super Admin write. A "Renew" button here would be a dead end.
    expect(find.widgetWithText(FilledButton, 'Renew'), findsNothing);
  });

  testWidgets('being offline says so, and offers the retry that could actually work', (
    tester,
  ) async {
    await _pumpDashboard(tester, statsError: const OfflineFailure('no route to host'));

    expect(find.text('No connection'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Try again'), findsOneWidget);
  });

  testWidgets('a refusal by row-level security offers no retry', (tester) async {
    await _pumpDashboard(tester, statsError: const AccessDeniedFailure('rls said no'));

    expect(find.text('Not your PG'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Try again'), findsNothing);
  });

  testWidgets('an owner with one PG gets a line of text, not a menu of one', (tester) async {
    await _pumpDashboard(tester);
    expect(find.text('Sunrise Residency'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
  });

  // Two pumps of two different ProviderScopes in one test would NOT re-run the overridden
  // providers — riverpod keeps the elements it already created — so the second case gets its
  // own test rather than a second pumpWidget.
  testWidgets('an owner with several PGs gets a switcher', (tester) async {
    final second = Hostel(
      id: 'h-moon',
      name: 'Moonlight Stay',
      ownerUserId: 'owner-1',
      totalFloors: 2,
      totalRooms: 8,
      bedsPerRoomDefault: 2,
      status: HostelStatus.active,
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
    await _pumpDashboard(tester, owned: [_sunrise, second]);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
  });

  testWidgets('the shell puts the dashboard behind the owner\'s first tab', (tester) async {
    // The one line features/shell/role_shell.dart needs from this feature. Without it the
    // screens below are unreachable, which no analyzer would ever mention.
    await _pumpDashboard(tester, throughShell: true);

    expect(find.text('COLLECTED IN AUGUST'), findsOneWidget);
    expect(find.text('This screen is not built yet.'), findsNothing);
  });
}
