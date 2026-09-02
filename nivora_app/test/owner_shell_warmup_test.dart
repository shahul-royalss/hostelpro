// The product owner's complaint, held down for the OWNER shell: "the system has to load
// fastly when we clicks on any section... it has to come active without lazy load."
//
// WHAT THESE PROVE. The owner shell (OwnerSection, behind RoleShell) warms every tab's data in
// the background while the Dashboard is on screen, so that tapping PGs, More (staff), or the
// placeholder tabs NEVER lands on a skeleton or spinner once the shell has been up for a
// moment — and that a revisit renders from the held value without refetching. The one place a
// skeleton is still allowed — the genuinely cold first paint, before warm-up has had a chance
// to run — is asserted too, because it is what proves the skeleton finder can detect a
// regression at all.
//
// HOW THE STUBS ARE SHAPED. Every provider a tab reads is overridden with a stub that resolves
// after a real delay (the fake clock stands in for the network), COUNTS its fetches, and calls
// holdForSession(ref) first thing — mirroring what the production providers in
// lib/data/providers.dart and staff_providers.dart do (an override replaces the provider's
// whole build, so the mirror is what keeps the lifetime under test honest; the hold/refresh/
// sign-out semantics of holdForSession itself are proven in perf_warmup_test.dart). The fetch
// counters are what turn "no skeleton" from a rendering accident into a cache assertion: a tab
// tap that refetched would still eventually draw numbers, but the counter would move.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/perf/session_keep_alive.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/owner/owner_insights.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/owner/owner_tabs.dart';
import 'package:mobile/features/owner/staff/staff_models.dart';
import 'package:mobile/features/owner/staff/staff_providers.dart';
import 'package:mobile/features/owner/widgets/states.dart';
import 'package:mobile/features/shell/role_shell.dart';

const _period = '2026-08';
const _sunriseId = 'h-sunrise';
const _lakeviewId = 'h-lakeview';

/// How long every stubbed "network call" takes. Long enough that a screen built before it
/// resolves must show its skeleton; short against the 150ms warm-up stagger's total.
const _lag = Duration(milliseconds: 200);

const _session = NivoraSession(
  userId: 'owner-1',
  role: UserRole.owner,
  fullName: 'Ananya Rao',
  status: 'active',
  mustChangePassword: false,
  hostelId: _sunriseId,
);

Hostel _hostel(String id, String name) => Hostel(
      id: id,
      name: name,
      ownerUserId: 'owner-1',
      totalFloors: 3,
      totalRooms: 12,
      bedsPerRoomDefault: 3,
      status: HostelStatus.active,
      createdAt: DateTime.utc(2026, 3, 1),
      updatedAt: DateTime.utc(2026, 3, 1),
    );

HostelStats _stats() => const HostelStats(
      totalBeds: 36,
      occupiedBeds: 12,
      activeStudents: 12,
      openComplaints: 3,
      feesCollected: 50200,
      feesPending: 33800,
      studentsPaid: 6,
      studentsUnpaid: 6,
      pendingLeaves: 0,
      visitorsToday: 0,
      pendingTasks: 1,
      revenueToday: 0,
      expensesToday: 0,
      revenueMonth: 45200,
      expensesMonth: 50400,
      subscriptionState: SubscriptionState.active,
      subscriptionDaysLeft: 300,
    );

final _window = FinanceRangeQuery(
  hostelId: _sunriseId,
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

List<StaffMember> _staff() => [
      StaffMember(
        id: 'u-m1',
        role: StaffRole.manager,
        fullName: 'Ravi Kulkarni',
        status: StaffStatus.active,
        createdAt: DateTime.utc(2026, 5, 12),
        email: 'ravi@example.com',
        phone: '9876543210',
      ),
    ];

List<ActivityItem> _activity() => [
      ActivityItem(
        kind: ActivityKind.notice,
        id: 'n1',
        title: 'Water tanker on Sunday',
        detail: 'Notice to everyone',
        at: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      ),
    ];

List<RecentPayment> _payments() => [
      RecentPayment(
        id: 'fp-1',
        studentId: 'st-1',
        fullName: 'Rohan Deshmukh',
        roomNumber: '101',
        bedNumber: 2,
        periodMonth: _period,
        amountDue: 6200,
        amountPaid: 6200,
        status: FeeStatus.paid,
        paidOn: DateTime(2026, 8, 24),
        mode: PaymentMode.cash,
        recordedBy: 'u-w1',
        recordedByName: 'Priya Nair',
        recordedByRole: 'warden',
        recordedAt: DateTime.utc(2026, 8, 24, 11, 30),
      ),
    ];

/// The Payments tab's one page, delayed and counted like every other stub here.
class _RecentPayments extends RecentPaymentsNotifier {
  _RecentPayments(super.hostelId);

  @override
  Future<PagedResult<RecentPayment>> fetchPage(int page) {
    _paymentsFetches += 1;
    return Future<PagedResult<RecentPayment>>.delayed(
      _lag,
      () => PagedResult(items: _payments(), page: 0, pageSize: 20, hasMore: false),
    );
  }
}

/// Fetch counters, reset per test. A revisit that stays at the old count is the proof that the
/// held value — not a refetch — is what rendered.
final _statsFetches = <String, int>{};
int _staffFetches = 0;
int _paymentsFetches = 0;
int _financeFetches = 0;
int _hostelsFetches = 0;

Future<void> _pumpShell(WidgetTester tester) async {
  _statsFetches.clear();
  _staffFetches = 0;
  _paymentsFetches = 0;
  _financeFetches = 0;
  _hostelsFetches = 0;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(_session),
        currentPeriodMonthProvider.overrideWithValue(_period),
        ownerFinanceWindowProvider.overrideWithValue(_window),
        // Delayed like a real query; the two-PG list is what makes the PGs tab's per-card
        // stats a genuine warm (the second PG's figures are read by no home-tab widget).
        myHostelsProvider.overrideWith((ref) {
          _hostelsFetches += 1;
          return Future.delayed(
            _lag,
            () => [_hostel(_sunriseId, 'Sunrise Residency'), _hostel(_lakeviewId, 'Lakeview')],
          );
        }),
        hostelStatsProvider.overrideWith((ref, query) {
          holdForSession(ref);
          _statsFetches[query.hostelId] = (_statsFetches[query.hostelId] ?? 0) + 1;
          return Future<HostelStats?>.delayed(_lag, _stats);
        }),
        dailyFinanceProvider.overrideWith((ref, query) {
          holdForSession(ref);
          _financeFetches += 1;
          return Future<List<FinanceDay>>.delayed(_lag, _series);
        }),
        recentPaymentsProvider.overrideWith2(_RecentPayments.new),
        ownerStaffProvider.overrideWith((ref, hostelId) {
          holdForSession(ref);
          _staffFetches += 1;
          return Future<List<StaffMember>>.delayed(_lag, _staff);
        }),
        // Composed from two held list providers in production; pinned here so the home tab's
        // activity feed is not what this file is testing.
        ownerActivityProvider.overrideWith((ref, hostelId) => AsyncData(_activity())),
      ],
      // Stock theme, not the app's: NivoraTheme is built on google_fonts, which would try to
      // fetch a font file over the network from inside the test binary. context.tones falls
      // back to NivoraSemantics.light without the extension.
      child: const MaterialApp(home: RoleShell(role: UserRole.owner)),
    ),
  );
}

/// Advances past the warm-up: stubs resolve at 200ms, and the warmers fire at ~150ms
/// (cash flow), ~300ms (per-PG stats), ~450ms (staff), each resolving one lag later.
Future<void> _letWarmupRun(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// The one assertion the product owner asked for, applied to whatever is on (or stacked
/// behind) the screen: no skeleton, no spinner.
void _expectNoLoadingUi() {
  expect(find.byType(Skeleton), findsNothing);
  expect(find.byType(SkeletonCard), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

void main() {
  testWidgets('after warm-up, every tab arrives drawn — no skeleton, no spinner, no refetch',
      (tester) async {
    await _pumpShell(tester);
    await tester.pump();

    // The genuinely cold first paint of the home tab is the one skeleton the contract allows.
    expect(find.byType(Skeleton), findsWidgets);

    await _letWarmupRun(tester);

    // Warm-up fetched every tab's data in the background, exactly once each: both PGs' card
    // stats (the active PG's request was the Dashboard's own; the warmer joined it), the
    // staff roster, and the 30-day cash-flow window — which on a phone sits below the
    // Dashboard's fold, so the warmer is the only thing that fetched it at all.
    expect(_statsFetches, {_sunriseId: 1, _lakeviewId: 1});
    expect(_staffFetches, 1);
    expect(_paymentsFetches, 1);
    expect(_financeFetches, 1);
    expect(_hostelsFetches, 1);

    // PGs: both cards drawn on the arrival frame, figures included.
    await tester.tap(find.text('PGs'));
    await tester.pump();
    _expectNoLoadingUi();
    expect(find.text('Sunrise Residency'), findsWidgets);
    expect(find.text('Lakeview'), findsWidgets);

    // Students is a real screen now, and it is warmed like the rest: the roster's first page
    // is already in hand, so the tap lands on residents rather than on a skeleton. The
    // placeholder this used to assert is gone from the owner's shell entirely.
    await tester.tap(find.text('Students'));
    await tester.pump();
    _expectNoLoadingUi();
    expect(find.textContaining('not built yet'), findsNothing);

    // Payments: "who paid" is warmed like every other tab, so the first frame after the tap
    // already carries the resident, the figure and the name of the warden who took it.
    await tester.tap(find.text('Payments'));
    await tester.pump();
    _expectNoLoadingUi();
    expect(find.text('Rohan Deshmukh'), findsOneWidget);
    expect(find.text('₹6,200'), findsOneWidget);
    expect(find.text('Priya Nair (Warden)'), findsOneWidget);

    // More: the staff roster is already there.
    await tester.tap(find.text('More'));
    await tester.pump();
    _expectNoLoadingUi();
    expect(find.text('Ravi Kulkarni'), findsOneWidget);

    // Back to the Dashboard: the hero figure is still standing.
    await tester.tap(find.text('Dashboard'));
    await tester.pump();
    _expectNoLoadingUi();
    expect(find.text('₹50,200'), findsWidgets);

    // And around the whole shell again: not one of those taps fetched anything.
    await tester.tap(find.text('PGs'));
    await tester.pump();
    _expectNoLoadingUi();
    expect(_statsFetches, {_sunriseId: 1, _lakeviewId: 1});
    expect(_staffFetches, 1);
    expect(_paymentsFetches, 1);
    expect(_financeFetches, 1);
    expect(_hostelsFetches, 1);
  });

  testWidgets('before warm-up has run, a cold tab still shows its honest skeleton',
      (tester) async {
    // The control: if skeletons were unfindable (renamed widget, changed loading UI), the
    // assertions above would pass vacuously. This pins that the finder sees them when they
    // are genuinely due — and that the allowance stays limited to the cold start.
    await _pumpShell(tester);
    await tester.pump();

    await tester.tap(find.text('PGs'));
    await tester.pump();
    expect(find.byType(SkeletonCard), findsWidgets,
        reason: 'nothing is warm yet: the list has not loaded and may honestly say so');

    // Drain: once the stubs resolve, the same screen fills in with no further taps.
    await _letWarmupRun(tester);
    _expectNoLoadingUi();
    expect(find.text('Lakeview'), findsWidgets);
  });

  testWidgets('a background refresh updates in place — the old numbers hold the screen',
      (tester) async {
    await _pumpShell(tester);
    await tester.pump();
    await _letWarmupRun(tester);

    await tester.tap(find.text('PGs'));
    await tester.pump();
    expect(find.text('Lakeview'), findsWidgets);

    // What a silent background refresh does: invalidate while the tab is on screen.
    final container = ProviderScope.containerOf(tester.element(find.byType(OwnerSection)));
    container.invalidate(
      hostelStatsProvider(const StatsQuery(hostelId: _sunriseId, periodMonth: _period)),
    );
    container.invalidate(
      hostelStatsProvider(const StatsQuery(hostelId: _lakeviewId, periodMonth: _period)),
    );
    await tester.pump();

    // The refetches are in flight — and the screen is still the previous figures, not a
    // skeleton. AsyncValue keeps the prior value because holdForSession kept the provider
    // alive; whenAsync's skipLoadingOnRefresh renders it.
    expect(_statsFetches, {_sunriseId: 2, _lakeviewId: 2});
    _expectNoLoadingUi();
    expect(find.text('Sunrise Residency'), findsWidgets);
    expect(find.text('Lakeview'), findsWidgets);

    // Let the refresh land so no stub timer outlives the test.
    await tester.pump(_lag);
    _expectNoLoadingUi();
  });
}
