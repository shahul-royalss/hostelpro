// Tests for the warden experience.
//
// These cover the failures that compile cleanly and are only found by a person standing in a
// corridor: a phone number normalised differently from the web app so the same resident is
// registered twice, a leave row whose embedded student went missing, a dashboard figure that
// counts one thing and opens a list of another, and a month stepper that turns December into
// month thirteen.
//
// The widget tests deliberately do NOT use NivoraTheme: it is built on google_fonts, which
// reaches for the network from inside the test binary. Nothing under test depends on the
// typeface — only on the scale's slot names, which the stock theme has too.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/warden/data/warden_models.dart';
import 'package:mobile/features/warden/data/warden_providers.dart';
import 'package:mobile/features/warden/home/warden_home_screen.dart';
import 'package:mobile/features/warden/rooms/warden_rooms_screen.dart';
import 'package:mobile/features/warden/actions/register_student_sheet.dart';
import 'package:mobile/features/warden/widgets/warden_ui.dart';

const _hostelId = 'h1';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('leave requests are read the way public.leaves declares them', () {
    Map<String, dynamic> leave({Object? student, String status = 'pending'}) => {
          'id': 'l1',
          'hostel_id': _hostelId,
          'student_id': 's1',
          'from_date': '2026-08-20',
          'to_date': '2026-08-22',
          'reason': 'Sister\'s wedding',
          'status': status,
          'decided_by': null,
          'decided_at': null,
          'decision_note': null,
          'created_at': '2026-08-18T09:00:00+00:00',
          'student': student,
        };

    test('the embedded student supplies the name a warden reads', () {
      final row = LeaveRequest.fromJson(
        leave(student: {'full_name': 'Aarav Sharma', 'phone': '9000000001'}),
      );
      expect(row.studentName, 'Aarav Sharma');
      expect(row.studentPhone, '9000000001');
    });

    test('a missing embed is null, not a crash', () {
      // The embed is evaluated under the caller's RLS. A role that cannot read students gets
      // null here, and the sheet says "Resident" rather than printing a uuid at somebody.
      final row = LeaveRequest.fromJson(leave(student: null));
      expect(row.studentName, isNull);
      expect(row.studentPhone, isNull);
    });

    test('both end dates are inclusive, so a three-day leave is three nights', () {
      final row = LeaveRequest.fromJson(leave());
      expect(row.nights, 3, reason: '20th to 22nd inclusive');
    });

    test('a same-day leave is one night, never zero', () {
      final row = LeaveRequest.fromJson({
        ...leave(),
        'from_date': '2026-08-20',
        'to_date': '2026-08-20',
      });
      expect(row.nights, 1);
    });

    test('status is matched by wire value, never by enum position', () {
      expect(LeaveStatus.tryParse('approved'), LeaveStatus.approved);
      expect(LeaveStatus.tryParse('rejected'), LeaveStatus.rejected);
      expect(LeaveStatus.tryParse('Approved'), isNull, reason: 'the match is exact');
      expect(LeaveStatus.tryParse('cancelled'), isNull);
      expect(LeaveStatus.pending.isDecided, isFalse);
      expect(LeaveStatus.rejected.isDecided, isTrue);
    });

    test('a status this build has never heard of throws rather than guessing', () {
      expect(
        () => LeaveRequest.fromJson(leave(status: 'cancelled')),
        throwsA(isA<RowShapeError>()),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('visitors are on site until check_out_at is set', () {
    Map<String, dynamic> visitor({Object? checkOut}) => {
          'id': 'v1',
          'hostel_id': _hostelId,
          'student_id': 's1',
          'visitor_name': 'Ramesh Sharma',
          'visitor_phone': '9000000099',
          'relation': 'Father',
          'check_in_at': '2026-08-24T10:00:00+00:00',
          'check_out_at': checkOut,
          'logged_by': 'u1',
          'created_at': '2026-08-24T10:00:00+00:00',
          'student': {'full_name': 'Aarav Sharma'},
        };

    test('a null check-out IS the on-site state — there is no status column', () {
      expect(VisitorLog.fromJson(visitor()).isOnSite, isTrue);
      expect(
        VisitorLog.fromJson(visitor(checkOut: '2026-08-24T13:00:00+00:00')).isOnSite,
        isFalse,
      );
    });

    test('the visited resident comes from the embed', () {
      expect(VisitorLog.fromJson(visitor()).studentName, 'Aarav Sharma');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('phone numbers normalise exactly as the web app normalises them', () {
    // Both clients write to ONE partial unique index, students_phone_active_key. If mobile
    // stored "+919876543210" where the web stored "9876543210", the same person would register
    // twice and neither client would notice.
    test('a plain ten-digit number is untouched', () {
      expect(normalisePhone('9876543210'), '9876543210');
    });

    test('separators, a +91 and a leading 0 are stripped', () {
      expect(normalisePhone('+91 98765 43210'), '9876543210');
      expect(normalisePhone('0-98765-43210'), '9876543210');
      expect(normalisePhone('(98765) 43210'), '9876543210');
    });

    test('a prefix is only stripped when exactly ten digits remain', () {
      // The web app's rule is `^91(?=\d{10}$)` and `^0(?=\d{10}$)` — a lookahead, not a blind
      // trim. "0919876543210" is thirteen digits and is left alone by both clients, so the
      // validator rejects it instead of one client silently inventing a different number.
      expect(normalisePhone('091-98765-43210'), '0919876543210');
    });

    test('a 91 that is part of a ten-digit number is NOT stripped', () {
      // 9198765432 is a valid ten-digit number beginning 91. Stripping a prefix by its digits
      // alone would turn it into eight digits and reject a real resident.
      expect(normalisePhone('9198765432'), '9198765432');
    });

    test('something that is not a phone number is left for the validator to reject', () {
      expect(normalisePhone('12345'), '12345');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('figures are rendered for an Indian PG', () {
    test('rupees group in lakhs, not in thousands', () {
      expect(money(150000), contains('1,50,000'));
      expect(money(7000), contains('7,000'));
    });

    test('a period month becomes a month a person reads', () {
      expect(monthLabel('2026-08'), 'August 2026');
      expect(monthLabel('2026-01'), 'January 2026');
    });

    test('an unparseable month is returned untouched instead of throwing on a heading', () {
      expect(monthLabel('not-a-month'), 'not-a-month');
      expect(monthLabel('2026-13'), '2026-13');
    });

    test('initials are one or two letters, and never blow up on an empty name', () {
      expect(initials('Aarav Sharma'), 'AS');
      expect(initials('Aarav'), 'A');
      expect(initials('Aarav Kumar Sharma'), 'AS', reason: 'first and last only');
      expect(initials('   '), '?');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('a dashboard number opens the list it counted', () {
    test('"needs action" is status <> resolved — what rpc_hostel_stats counts', () {
      // The home card says "3 complaints, not resolved yet" and taps through to this filter.
      // If the chip narrowed to 'open' only, the list would be shorter than the number that
      // opened it, and a number nobody can reconcile is a number nobody trusts.
      expect(ComplaintFilter.needsAction.status, isNull);
      expect(ComplaintFilter.needsAction.openOnly, isTrue);
    });

    test('every other chip is one exact status and does not also hide resolved rows', () {
      expect(ComplaintFilter.open.status, ComplaintStatus.open);
      expect(ComplaintFilter.inProgress.status, ComplaintStatus.inProgress);
      expect(ComplaintFilter.resolved.status, ComplaintStatus.resolved);
      for (final filter in ComplaintFilter.values) {
        if (filter != ComplaintFilter.needsAction) {
          expect(filter.openOnly, isFalse, reason: '${filter.name} filters by status alone');
        }
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the month stepper does arithmetic, not string surgery', () {
    ProviderContainer containerAt(String month) {
      final container = ProviderContainer(
        overrides: [currentPeriodMonthProvider.overrideWithValue(month)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('stepping back from January lands in the previous December', () {
      final container = containerAt('2026-01');
      container.read(selectedMonthProvider.notifier).step(-1);
      expect(container.read(selectedMonthProvider), '2025-12');
    });

    test('stepping forward from December lands in the next January', () {
      final container = containerAt('2026-12');
      container.read(selectedMonthProvider.notifier).step(1);
      expect(container.read(selectedMonthProvider), '2027-01');
    });

    test('the month keeps its leading zero, as the check constraint demands', () {
      // fee_payments.period_month is checked against ^\d{4}-(0[1-9]|1[0-2])$ — "2026-9" would
      // be refused by Postgres, and only at the moment somebody tried to record a payment.
      final container = containerAt('2026-10');
      container.read(selectedMonthProvider.notifier).step(-1);
      expect(container.read(selectedMonthProvider), '2026-09');
    });

    test('reset returns to the month the device is in', () {
      final container = containerAt('2026-08');
      container.read(selectedMonthProvider.notifier).step(-3);
      expect(container.read(selectedMonthProvider), '2026-05');
      container.read(selectedMonthProvider.notifier).reset();
      expect(container.read(selectedMonthProvider), '2026-08');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('a free bed is labelled by the room a warden would walk to', () {
    Bed bed(int number, String roomId) => Bed(
          id: 'b$number',
          hostelId: _hostelId,
          roomId: roomId,
          bedNumber: number,
          status: BedStatus.free,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('room and bed together', () {
      final option = FreeBed(bed: bed(2, 'r1'), roomNumber: '101', floorNumber: 1);
      expect(option.label, 'Room 101 · Bed 2');
    });

    test('a bed whose room is unknown says only what is known', () {
      final option = FreeBed(bed: bed(2, 'r1'), roomNumber: null, floorNumber: null);
      expect(option.label, 'Bed 2', reason: 'no invented room number');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the room grid draws the building from rpc_room_occupancy', () {
    testWidgets('every room appears, with the beds it has free', (tester) async {
      await _pumpRooms(tester, rooms: _threeRooms());

      expect(find.text('101'), findsOneWidget);
      expect(find.text('102'), findsOneWidget);
      expect(find.text('201'), findsOneWidget);
      // 101 is at capacity; the other two have two beds each.
      expect(find.text('Full'), findsOneWidget);
    });

    testWidgets('the heading counts the very rows it is drawing', (tester) async {
      await _pumpRooms(tester, rooms: _threeRooms());
      // 3 + 3 + 3 beds, 3 + 1 + 1 taken. Computed from the same list as the tiles, so the
      // header and the grid cannot drift apart.
      expect(find.text('5 of 9 beds occupied · 4 free'), findsOneWidget);
    });

    testWidgets('storeys are grouped and labelled', (tester) async {
      await _pumpRooms(tester, rooms: _threeRooms());
      expect(find.text('FLOOR 1'), findsOneWidget);
      expect(find.text('FLOOR 2'), findsOneWidget);
    });

    testWidgets('a hostel with no rooms says so rather than showing an empty grid',
        (tester) async {
      await _pumpRooms(tester, rooms: const []);
      expect(find.text('No rooms yet'), findsOneWidget);
    });

    testWidgets('the legend names the only two states the schema has', (tester) async {
      // public.bed_status is exactly ('free','occupied'). A "maintenance" swatch here would be
      // a colour for data that cannot exist.
      await _pumpRooms(tester, rooms: _threeRooms());
      expect(find.text('Occupied'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.textContaining('aintenance'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the home screen leads with what is waiting', () {
    testWidgets('visitors ON SITE is not the same figure as visitors TODAY', (tester) async {
      // rpc_hostel_stats counts check-ins against the IST calendar day whether or not the guest
      // has left; the headline is who has not signed out. Conflating them would tell a warden
      // five people are in the building when three of them went home at lunchtime.
      await _pumpHome(tester, stats: _stats(visitorsToday: 5), onSite: 2);

      expect(find.text('2'), findsOneWidget);
      expect(find.text('5 logged today'), findsOneWidget);
    });

    testWidgets('each queue shows its own count', (tester) async {
      await _pumpHome(tester, stats: _stats(), onSite: 2);

      expect(find.text('Rent owed'.toUpperCase()), findsOneWidget);
      expect(find.text('6'), findsOneWidget); // students unpaid
      expect(find.text('3'), findsOneWidget); // complaints not resolved
      expect(find.text('1'), findsOneWidget); // leave requests pending
      expect(find.text('₹33,800 outstanding'), findsOneWidget);
    });

    testWidgets('an expired subscription is announced before a write is refused',
        (tester) async {
      await _pumpHome(
        tester,
        stats: _stats(state: SubscriptionState.expired, daysLeft: -3),
        onSite: 0,
      );
      expect(find.text('This hostel is read-only'), findsOneWidget);
      expect(find.textContaining('lapsed 3 days ago'), findsOneWidget);
    });

    testWidgets('an active subscription says nothing at all', (tester) async {
      await _pumpHome(tester, stats: _stats(), onSite: 0);
      expect(find.text('This hostel is read-only'), findsNothing);
      expect(find.text('Subscription ending'), findsNothing);
    });

    testWidgets('the four quick actions are on screen without scrolling for them',
        (tester) async {
      await _pumpHome(tester, stats: _stats(), onSite: 0);
      expect(find.text('Add resident'), findsOneWidget);
      expect(find.text('Assign bed'), findsOneWidget);
      expect(find.text('Record payment'), findsOneWidget);
      expect(find.text('Resolve complaint'), findsOneWidget);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIXTURES
// ─────────────────────────────────────────────────────────────────────────────

List<RoomOccupancy> _threeRooms() => const [
      RoomOccupancy(
        roomId: 'r1', floorId: 'f1', floorNumber: 1,
        roomNumber: '101', capacity: 3, occupied: 3,
      ),
      RoomOccupancy(
        roomId: 'r2', floorId: 'f1', floorNumber: 1,
        roomNumber: '102', capacity: 3, occupied: 1,
      ),
      RoomOccupancy(
        roomId: 'r3', floorId: 'f2', floorNumber: 2,
        roomNumber: '201', capacity: 3, occupied: 1,
      ),
    ];

HostelStats _stats({
  int visitorsToday = 0,
  SubscriptionState state = SubscriptionState.active,
  int? daysLeft = 300,
}) =>
    HostelStats(
      totalBeds: 9,
      occupiedBeds: 5,
      activeStudents: 5,
      openComplaints: 3,
      feesCollected: 50200,
      feesPending: 33800,
      studentsPaid: 4,
      studentsUnpaid: 6,
      pendingLeaves: 1,
      visitorsToday: visitorsToday,
      pendingTasks: 0,
      revenueToday: 0,
      expensesToday: 0,
      revenueMonth: 45200,
      expensesMonth: 50400,
      subscriptionState: state,
      subscriptionDaysLeft: daysLeft,
    );

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
      totalFloors: 3,
      totalRooms: 12,
      bedsPerRoomDefault: 3,
      status: HostelStatus.active,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// Riverpod 3 does not export the `Override` type, so the override lists below are built
/// inline where the analyzer can infer them.
Future<void> _pumpRooms(WidgetTester tester, {required List<RoomOccupancy> rooms}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentHostelIdProvider.overrideWithValue(_hostelId),
        roomOccupancyProvider.overrideWith((ref, hostelId) => rooms),
      ],
      child: const MaterialApp(home: Scaffold(body: WardenRoomsScreen())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required HostelStats stats,
  required int onSite,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(_session),
        currentHostelIdProvider.overrideWithValue(_hostelId),
        currentPeriodMonthProvider.overrideWithValue('2026-08'),
        hostelStatsProvider.overrideWith((ref, query) => stats),
        hostelProvider.overrideWith((ref, id) => _hostel()),
        roomOccupancyProvider.overrideWith((ref, id) => _threeRooms()),
        visitorsOnSiteProvider.overrideWith((ref, id) => _visitors(onSite)),
      ],
      child: const MaterialApp(home: Scaffold(body: WardenHomeScreen())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

List<VisitorLog> _visitors(int count) => [
      for (var i = 0; i < count; i++)
        VisitorLog(
          id: 'v$i',
          hostelId: _hostelId,
          studentId: 's$i',
          visitorName: 'Guest $i',
          checkInAt: DateTime.now().subtract(const Duration(hours: 1)),
          createdAt: DateTime.now(),
        ),
    ];
