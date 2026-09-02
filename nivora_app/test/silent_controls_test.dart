// A control that does nothing when you touch it is a bug in this app, and these are the ones
// that were doing nothing.
//
// Every test here is the same shape: drive the control, then assert that SOMETHING a person can
// see came back. That is deliberately a low bar — it is the bar the 2FA back chevron and the
// bed picker both failed, and it is cheap enough to keep on every control that can fail.
//
// WHAT EACH GROUP IS ABOUT
//
//  · PULL-TO-REFRESH. Every warden and manager screen wraps its body in an [AsyncSection],
//    which renders `builder(value.requireValue)` whenever `hasValue` is true. That is the right
//    call for the section — losing your place in a 200-row roster because a lift ate one packet
//    is worse than a stale row — but it means a RELOAD that fails draws exactly what was there
//    before. These screens used to answer the gesture with a bare `ref.invalidate(...)`, so the
//    spinner retracted in the same frame and a failure was never mentioned. The gesture now
//    goes through `settleRefresh`, which bounds the wait and says what happened.
//
//  · THE SUPER ADMIN'S NEXT PAGE. Both paginated console tabs asked for it with
//    `unawaited(loadMore())`. `PagedNotifier.loadMore` RETURNS its failure rather than throwing
//    — that is its whole contract — so a page that did not load threw the reason away and left
//    a spinner turning under the rows for ever, with nothing to read and nothing to tap.
//
//  · ACKNOWLEDGING AN ALERT WITH A DEAD SESSION. `_acknowledge` read the user id and returned
//    in silence when it was null. That is a real state — the token dies while the console sits
//    open — and the button answered it with nothing at all.
//
// The widget tests deliberately do NOT use NivoraTheme where they do not have to: it is built
// on google_fonts, which reaches for the network from inside the test binary.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
// MenuDay, Meal, WeeklyMenu and weeklyMenuProvider all arrive through the two shared barrels
// above: public.menus is read by the residents as well as the manager now, so its model lives
// in lib/data/models/menu.dart and its provider in lib/data/providers.dart, and the manager
// files only re-export them.
import 'package:mobile/features/manager/menu/manager_menu_screen.dart';
import 'package:mobile/features/super_admin/data/sa_models.dart';
import 'package:mobile/features/super_admin/data/sa_providers.dart';
import 'package:mobile/features/super_admin/sa_hostels_screen.dart';
import 'package:mobile/features/super_admin/sa_security_screen.dart';
import 'package:mobile/features/warden/rooms/warden_rooms_screen.dart';
import 'package:mobile/features/warden/students/warden_students_screen.dart';

const _hostelId = 'h1';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('pull-to-refresh answers for itself', () {
    testWidgets('the warden room grid says a failed reload failed, and keeps the rooms',
        (tester) async {
      var calls = 0;
      await _pumpRooms(tester, () {
        calls++;
        if (calls == 1) return Future.value(_rooms());
        return Future<List<RoomOccupancy>>.error(Exception('SocketException: no route to host'));
      });

      expect(find.text('101'), findsOneWidget, reason: 'the grid drew from the first read');

      await _pullToRefresh(tester);

      // The grid is still there — AsyncSection holds it through a failed reload, on purpose.
      expect(find.text('101'), findsOneWidget);
      // And the gesture said what happened, because nothing else on the screen can.
      expect(find.byType(SnackBar), findsOneWidget,
          reason: 'a pull that did not land must not look identical to one that did');
    });

    testWidgets('a reload that works says nothing and holds the spinner until it lands',
        (tester) async {
      await _pumpRooms(tester, () => Future.value(_rooms()));
      await _pullToRefresh(tester);

      expect(find.text('101'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing,
          reason: 'success is the absence of a message, not a second one');
    });

    // ── AND THE GESTURE HAS TO BE ABLE TO FIRE IN THE FIRST PLACE ──────────────
    //
    // A RefreshIndicator only runs for a child that reports an over-scroll, and content that
    // already fits over-scrolls only because a controller-less vertical ListView is `primary`
    // and ScrollView hands a primary list AlwaysScrollableScrollPhysics. These two states —
    // the ones a warden pulls hardest on, because they are the ones that look wrong — were
    // relying on that inference. It now says so in both files, and these hold it to it: give
    // either list a ScrollController and the pull dies silently without them.

    testWidgets('an empty room grid can still be pulled', (tester) async {
      var calls = 0;
      await _pumpRooms(tester, () {
        calls++;
        return Future.value(const <RoomOccupancy>[]);
      });
      expect(find.text('No rooms yet'), findsOneWidget);
      expect(calls, 1);

      await _pullToRefresh(tester);
      expect(calls, greaterThan(1),
          reason: 'a hostel showing no rooms is exactly when a warden pulls to refresh');
    });

    testWidgets('an empty resident roster can still be pulled', (tester) async {
      var calls = 0;
      await _pumpStudents(tester, () => calls++);
      expect(calls, 1);

      await _pullToRefresh(tester);
      expect(calls, greaterThan(1),
          reason: 'the empty state of a paged list was inert to the one gesture on it');
    });

    testWidgets("the manager's menu week says a failed reload failed", (tester) async {
      var calls = 0;
      await _pumpMenu(tester, () {
        calls++;
        if (calls == 1) return Future.value(const WeeklyMenu.empty());
        return Future<WeeklyMenu>.error(Exception('TimeoutException after 12s'));
      });

      await _pullToRefresh(tester);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group("the super admin's next page", () {
    testWidgets('a failed page names the reason and offers a tap, not a forever spinner',
        (tester) async {
      await _pumpHostels(tester);

      // Scroll to the foot of the list, which is what asks for the next page.
      await tester.drag(find.byType(ListView).last, const Offset(0, -4000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Load more'), findsOneWidget,
          reason: 'the failed page has to be askable-for again');
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'a spinner that will never resolve is the bug this replaced');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('acknowledging a security alert', () {
    testWidgets('a session that has ended is said out loud, not swallowed', (tester) async {
      await _pumpAlertCard(tester, session: null);

      await tester.tap(find.text('Acknowledge'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SnackBar), findsOneWidget,
          reason: 'the tap used to return in silence — no spinner, no sentence, no change');
      expect(find.textContaining('Sign in again'), findsOneWidget);
    });

    testWidgets('a refusal from the server is shown in the words the server used',
        (tester) async {
      await _pumpAlertCard(
        tester,
        session: _session,
        acknowledge: () async =>
            const AccessDeniedFailure('You do not have access to that.'),
      );

      await tester.tap(find.text('Acknowledge'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('You do not have access to that.'), findsOneWidget);
    });

    // A plain `test`, not a `testWidgets`: riverpod schedules its own dispose timer and
    // testWidgets asserts on any timer still pending when the tree goes away.
    test('a list that is not loaded reports a failure rather than claiming success', () async {
      // `acknowledge` returns null for "it worked". Returning null without having written
      // anything is how the card cleared its spinner, said nothing, and left the alert open.
      final container = ProviderContainer(overrides: [
        saAlertsProvider.overrideWith2((_) => _NeverLoadingAlerts(true)),
      ]);
      addTearDown(container.dispose);

      final failure = await container
          .read(saAlertsProvider(true).notifier)
          .acknowledge(1, 'u1');

      expect(failure, isNotNull);
      expect(failure!.message, contains('nothing was acknowledged'));
    });
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// HARNESS
// ═════════════════════════════════════════════════════════════════════════════

final _session = NivoraSession(
  userId: '00000000-0000-0000-0000-0000000000aa',
  role: UserRole.superAdmin,
  fullName: 'Platform Admin',
  status: 'active',
  mustChangePassword: false,
  email: 'codewithshahul@gmail.com',
);

List<RoomOccupancy> _rooms() => [
      const RoomOccupancy(
        roomId: 'r1',
        floorId: 'f1',
        roomNumber: '101',
        floorNumber: 1,
        capacity: 3,
        occupied: 1,
      ),
    ];

/// The gesture, not a call to the callback: the point is that the CONTROL produces the message.
///
/// PUMPED PAST THE DEADLINE ON PURPOSE. A provider that throws does NOT complete `.future`:
/// riverpod 3 schedules a retry and leaves the completer pending, which is the whole reason
/// `settleRefresh` has a deadline at all. Sixteen seconds of fake time is [refreshDeadline]
/// plus the snackbar's own entrance — pumping four, as the first draft of this helper did,
/// showed nothing and proved nothing.
Future<void> _pullToRefresh(WidgetTester tester) async {
  await tester.fling(find.byType(ListView).last, const Offset(0, 400), 1200);
  await tester.pump();
  for (var i = 0; i < 32; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _pumpRooms(
  WidgetTester tester,
  Future<List<RoomOccupancy>> Function() read,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentHostelIdProvider.overrideWithValue(_hostelId),
        roomOccupancyProvider.overrideWith((ref, hostelId) => read()),
      ],
      child: const MaterialApp(home: Scaffold(body: WardenRoomsScreen())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpMenu(
  WidgetTester tester,
  Future<WeeklyMenu> Function() read,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentHostelIdProvider.overrideWithValue(_hostelId),
        weeklyMenuProvider.overrideWith((ref, hostelId) => read()),
      ],
      child: const MaterialApp(home: Scaffold(body: ManagerMenuScreen())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpStudents(WidgetTester tester, void Function() onFetch) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentHostelIdProvider.overrideWithValue(_hostelId),
        studentsProvider.overrideWith2((query) => _EmptyRoster(query, onFetch)),
      ],
      child: const MaterialApp(home: Scaffold(body: WardenStudentsScreen())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpHostels(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(_session),
        saStatsProvider.overrideWith((ref) => _stats),
        saHostelListProvider.overrideWith2((query) => _FailingSecondPage(query)),
      ],
      child: const MaterialApp(home: Scaffold(body: SaHostelsScreen())),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpAlertCard(
  WidgetTester tester, {
  required NivoraSession? session,
  Future<AppFailure?> Function()? acknowledge,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(session),
        saAlertsProvider.overrideWith2(
          (openOnly) => _StubAlerts(openOnly, [_alert], acknowledge),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [SaAlertCard(alert: _alert, openOnly: true)],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

final _alert = SecurityAlert(
  id: 1,
  at: DateTime.utc(2026, 8, 31, 4, 30),
  severity: AlertSeverity.high,
  kind: 'failed_login_burst',
  summary: 'Eleven failed sign-ins for one account in four minutes.',
  details: const {},
);

const _stats = SaStats(
  totalHostels: 12,
  totalOwners: 9,
  totalStudents: 418,
  activeSubs: 9,
  expiringSubs: 2,
  expiredSubs: 1,
  monthlySubscriptionRevenue: 184000,
);

/// Twelve rows so the list overflows the viewport and can be scrolled to its foot, and a
/// second page that always fails — which is exactly the state that used to spin for ever.
class _FailingSecondPage extends SaHostelListNotifier {
  _FailingSecondPage(super.query);

  @override
  Future<PagedResult<SaHostelRow>> fetchPage(int page) async {
    if (page > 0) throw Exception('SocketException: connection reset');
    return PagedResult<SaHostelRow>(
      items: [for (var i = 0; i < 12; i++) _hostelRow(i)],
      page: 0,
      pageSize: 12,
      hasMore: true,
    );
  }
}

SaHostelRow _hostelRow(int i) => SaHostelRow(
      hostelId: 'h$i',
      hostelName: 'Hostel $i',
      hostelStatus: HostelStatus.active,
      ownerId: 'o$i',
      ownerName: 'Owner $i',
      subState: SubscriptionState.active,
      totalBeds: 10,
      occupiedBeds: 4,
      activeStudents: 4,
      openComplaints: 0,
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// A roster with nobody on it — the [PagedList] empty state, which is one card tall.
class _EmptyRoster extends StudentsNotifier {
  _EmptyRoster(super.query, this.onFetch);
  final void Function() onFetch;

  @override
  Future<PagedResult<Student>> fetchPage(int page) async {
    onFetch();
    return const PagedResult<Student>.empty();
  }
}

class _StubAlerts extends SaAlertsNotifier {
  _StubAlerts(super.openOnly, this.rows, this._acknowledge);
  final List<SecurityAlert> rows;
  final Future<AppFailure?> Function()? _acknowledge;

  @override
  Future<List<SecurityAlert>> build() async => rows;

  @override
  Future<AppFailure?> acknowledge(int alertId, String byUserId) =>
      _acknowledge?.call() ?? Future.value();
}

/// Never finishes its first read, so `state.value` is null — the case `acknowledge` used to
/// answer with "it worked".
class _NeverLoadingAlerts extends SaAlertsNotifier {
  _NeverLoadingAlerts(super.openOnly);

  @override
  Future<List<SecurityAlert>> build() => Completer<List<SecurityAlert>>().future;
}
