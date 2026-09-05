// The product owner's complaint, held down as a test: "the system has to load fastly when we
// clicks on any section... it has to come active without lazy load." For the warden shell that
// means two things, and this file asserts both against the real WardenShell:
//
//  1. ORDER. The home tab's requests go out first and alone — the other tabs' first pages are
//     fetched in the background afterwards, one stagger interval apart, so warm-up never
//     contends with what the warden is looking at. (Before this shell gated its children, all
//     five screens fired their queries in the very first frame.)
//  2. NO SKELETON ON A TAP. Once the shell has been up for a moment, tapping any tab renders
//     rows in its arrival frame — never a SkeletonBlock, never a CircularProgressIndicator —
//     and a background refresh happens BEHIND the rows a revisit is already showing.
//
// The fakes resolve after a real (fake-clock) delay, because instantly-complete futures would
// hide exactly the gap this shell exists to close.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/shared/wordmark.dart';
import 'package:mobile/shared/glass/glass.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/warden/data/warden_models.dart';
import 'package:mobile/features/warden/data/warden_providers.dart';
import 'package:mobile/features/warden/warden_shell.dart';
import 'package:mobile/features/warden/widgets/warden_ui.dart';

const _hostelId = 'h1';

/// How long every fake takes to answer. Comfortably shorter than one stagger interval, so by
/// the time a warmer mounts the NEXT tab the previous tab's page has already landed.
const _latency = Duration(milliseconds: 60);

/// One stagger step of the shell's TabWarmer, as pumped by the tests.
const _tick = Duration(milliseconds: 150);

/// Every fetch any fake dispatched, in the order the network would have seen them.
final _log = <String>[];

int _fetches(String tag) => _log.where((e) => e == tag).length;

void main() {
  testWidgets('home wins the network; the other tabs warm one interval apart', (tester) async {
    await _pumpShell(tester);

    // THE FIRST FRAME. Only the home tab (and the nav-bar badges, off the same stats key) has
    // asked the network for anything. Before this shell staggered its children, 'students',
    // 'ledger' and 'complaints' were all in this log already, contending with the dashboard.
    expect(_log, contains('stats'));
    expect(_log, isNot(contains('students')));
    expect(_log, isNot(contains('ledger')));
    expect(_log, isNot(contains('complaints')));

    await tester.pump(_latency); // home's data lands — nothing else has fired meanwhile
    expect(_log, isNot(contains('students')));

    await tester.pump(_tick); // first stagger step: the resident roster
    expect(_log, contains('students'));
    expect(_log, isNot(contains('ledger')), reason: 'warmers are staggered, not batched');
    expect(_log, isNot(contains('complaints')));

    await tester.pump(_tick); // second: the fee ledger
    expect(_log, contains('ledger'));
    expect(_log, isNot(contains('complaints')));

    await tester.pump(_tick); // third: the complaints queue
    expect(_log, contains('complaints'));

    await tester.pump(_tick); // fourth: the rooms tab mounts
    await tester.pump(_tick); // everything in flight lands

    // The rooms tab cost the network nothing new: home's building section, the resident rows
    // and the room grid all watch the one roomOccupancyProvider instance, fetched once.
    expect(_fetches('rooms'), 1);
    // And the fees summary + nav badges reused home's stats fetch rather than repeating it.
    expect(_fetches('stats'), 1);
    expect(_fetches('students'), 1);
    expect(_fetches('ledger'), 1);
    expect(_fetches('complaints'), 1);
  });

  testWidgets('after warm-up, every tab arrives with rows — no skeleton, no spinner',
      (tester) async {
    await _pumpShell(tester);
    await _warmUp(tester);

    await _tapTab(tester, 'Students');
    expect(find.text('Aarav Sharma'), findsOneWidget);
    _expectNoLoadingIndicators('Students');

    await _tapTab(tester, 'Rooms');
    expect(find.text('101'), findsOneWidget);
    _expectNoLoadingIndicators('Rooms');

    await _tapTab(tester, 'Payments');
    expect(find.text('Meera Iyer'), findsOneWidget);
    _expectNoLoadingIndicators('Payments');

    await _tapTab(tester, 'Complaints');
    expect(find.text('Geyser not heating in 2nd floor bathroom'), findsOneWidget);
    _expectNoLoadingIndicators('Complaints');

    await _tapTab(tester, 'Home');
    // The warden's home header is the masthead now — the signature centred with the account
    // avatar beside it — so "Hello, Priya" is no longer written there. Her initials are, and
    // that is what identifies the tab as hers. The greeting was the old header's job.
    expect(find.byType(AccountAvatar), findsOneWidget);
    expect(find.byType(NivoraWordmark), findsOneWidget);
    _expectNoLoadingIndicators('Home');
  });

  testWidgets('a revisit renders the held rows instantly, and a refresh runs behind them',
      (tester) async {
    await _pumpShell(tester);
    await _warmUp(tester);

    await _tapTab(tester, 'Students');
    expect(find.text('Aarav Sharma'), findsOneWidget);
    await _tapTab(tester, 'Home');
    expect(_fetches('students'), 1, reason: 'leaving a tab must not throw its pages away');

    // A write happened somewhere: the roster is invalidated, exactly as refreshResidents does.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WardenShell)),
      listen: false,
    );
    container.invalidate(studentsProvider);
    await tester.pump(); // the refetch is dispatched…

    await _tapTab(tester, 'Students'); // …and the warden comes back MID-refresh
    expect(_fetches('students'), 2, reason: 'the refresh really is in flight');
    expect(find.text('Aarav Sharma'), findsOneWidget,
        reason: 'stale-while-revalidate: the held rows render, never a blank');
    _expectNoLoadingIndicators('Students, revisited mid-refresh');

    await tester.pump(_latency); // the refresh lands behind rows that never left the screen
    expect(find.text('Aarav Sharma'), findsOneWidget);
  });

  testWidgets('a tap that beats the warmer still cold-loads that tab, exactly as before',
      (tester) async {
    await _pumpShell(tester);
    await tester.pump(_latency); // home is up; the complaints warmer is still ~400ms away

    await _tapTab(tester, 'Complaints');
    expect(_log, contains('complaints'),
        reason: 'the tap itself mounts the screen and dispatches its first page');
    await tester.pump(_latency);
    expect(find.text('Geyser not heating in 2nd floor bathroom'), findsOneWidget);

    // Let the remaining warmers finish cleanly: one pump fires their timers (the mounts all
    // build in its final frame), the next lands the fetches those builds dispatched.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(_latency);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HARNESS
// ─────────────────────────────────────────────────────────────────────────────

void _expectNoLoadingIndicators(String where) {
  expect(find.byType(SkeletonBlock), findsNothing,
      reason: '$where must render from warm data, not repaint a skeleton');
  expect(find.byType(CircularProgressIndicator), findsNothing,
      reason: '$where must never greet a tap with a spinner');
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  // ONE frame: this is the instant the tab appears under the warden's thumb. Everything the
  // no-skeleton contract promises must already be true here, without settling.
  await tester.pump();
}

/// Runs the whole warm-up: home's fetch, then the four staggered mounts, then lets every
/// request in flight land. Mirrors ~800ms of a real phone's timeline on the fake clock.
Future<void> _warmUp(WidgetTester tester) async {
  await tester.pump(_latency);
  for (var i = 0; i < 4; i++) {
    await tester.pump(_tick);
  }
  await tester.pump(_tick);
}

Future<void> _pumpShell(WidgetTester tester) async {
  _log.clear();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(_session),
        currentPeriodMonthProvider.overrideWithValue('2026-08'),
        hostelStatsProvider.overrideWith((ref, query) async {
          _log.add('stats');
          await Future<void>.delayed(_latency);
          return _stats();
        }),
        hostelProvider.overrideWith((ref, id) async {
          _log.add('hostel');
          await Future<void>.delayed(_latency);
          return _hostel();
        }),
        visitorsOnSiteProvider.overrideWith((ref, id) async {
          _log.add('visitors');
          await Future<void>.delayed(_latency);
          return const <VisitorLog>[];
        }),
        roomOccupancyProvider.overrideWith((ref, id) async {
          _log.add('rooms');
          await Future<void>.delayed(_latency);
          return _rooms();
        }),
        // The real notifiers run — holdForSession, paging, the lot — only fetchPage is faked.
        studentsProvider.overrideWith2(_FakeStudents.new),
        feeLedgerProvider.overrideWith2(_FakeLedger.new),
        complaintsProvider.overrideWith2(_FakeComplaints.new),
      ],
      child: const MaterialApp(home: WardenShell()),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FAKES — the real PagedNotifiers with the network swapped for a delayed page
// ─────────────────────────────────────────────────────────────────────────────

PagedResult<T> _one<T>(List<T> items) =>
    PagedResult<T>(items: items, page: 0, pageSize: 20, hasMore: false);

class _FakeStudents extends StudentsNotifier {
  _FakeStudents(super.query);
  @override
  Future<PagedResult<Student>> fetchPage(int page) async {
    _log.add('students');
    await Future<void>.delayed(_latency);
    return _one([_student()]);
  }
}

class _FakeLedger extends FeeLedgerNotifier {
  _FakeLedger(super.query);
  @override
  Future<PagedResult<FeeLedgerRow>> fetchPage(int page) async {
    _log.add('ledger');
    await Future<void>.delayed(_latency);
    return _one([_ledgerRow()]);
  }
}

class _FakeComplaints extends ComplaintsNotifier {
  _FakeComplaints(super.query);
  @override
  Future<PagedResult<Complaint>> fetchPage(int page) async {
    _log.add('complaints');
    await Future<void>.delayed(_latency);
    return _one([_complaint()]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FIXTURES
// ─────────────────────────────────────────────────────────────────────────────

const _session = NivoraSession(
  userId: 'u-warden',
  role: UserRole.warden,
  fullName: 'Priya Nair',
  status: 'active',
  mustChangePassword: false,
  hostelId: _hostelId,
);

Hostel _hostel() => Hostel(
      id: _hostelId,
      name: 'Sunrise Residency',
      ownerUserId: 'u-owner',
      totalFloors: 2,
      totalRooms: 2,
      bedsPerRoomDefault: 3,
      status: HostelStatus.active,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

List<RoomOccupancy> _rooms() => const [
      RoomOccupancy(
        roomId: 'r1',
        floorId: 'f1',
        floorNumber: 1,
        roomNumber: '101',
        capacity: 3,
        occupied: 1,
      ),
      RoomOccupancy(
        roomId: 'r2',
        floorId: 'f2',
        floorNumber: 2,
        roomNumber: '201',
        capacity: 3,
        occupied: 0,
      ),
    ];

Student _student() => Student(
      id: 's1',
      hostelId: _hostelId,
      fullName: 'Aarav Sharma',
      phone: '9000000001',
      dateOfJoining: DateTime(2026, 2, 1),
      monthlyFee: 7000,
      status: StudentStatus.active,
      roomId: 'r1',
      bedId: 'b1',
      createdAt: DateTime(2026, 2, 1),
      updatedAt: DateTime(2026, 2, 1),
    );

FeeLedgerRow _ledgerRow() => const FeeLedgerRow(
      studentId: 's2',
      fullName: 'Meera Iyer',
      phone: '9000000002',
      monthlyFee: 7000,
      amountDue: 7000,
      amountPaid: 0,
      status: FeeStatus.unpaid,
    );

Complaint _complaint() => Complaint(
      id: 'c1',
      hostelId: _hostelId,
      studentId: 's1',
      category: ComplaintCategory.maintenance,
      title: 'Geyser not heating in 2nd floor bathroom',
      status: ComplaintStatus.open,
      createdAt: DateTime(2026, 8, 20, 9, 30),
      updatedAt: DateTime(2026, 8, 20, 9, 30),
    );

HostelStats _stats() => const HostelStats(
      totalBeds: 6,
      occupiedBeds: 1,
      activeStudents: 1,
      openComplaints: 1,
      feesCollected: 0,
      feesPending: 7000,
      studentsPaid: 0,
      studentsUnpaid: 1,
      pendingLeaves: 0,
      visitorsToday: 0,
      pendingTasks: 0,
      revenueToday: 0,
      expensesToday: 0,
      revenueMonth: 0,
      expensesMonth: 0,
      subscriptionState: SubscriptionState.active,
      subscriptionDaysLeft: 300,
    );
