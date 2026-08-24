// Widget tests for the owner's PG list and the room/bed view.
//
// These two screens are where an owner answers "which beds are empty, and who is in the rest".
// The failure they are here to catch is the quiet one: a grid that renders nothing because the
// rows were grouped by the wrong key, or a bed sheet that shows "Occupied" forever because the
// occupant's name was never resolved.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/owner/owner_pg_detail_screen.dart';
import 'package:mobile/features/owner/owner_pg_list_screen.dart';
import 'package:mobile/features/owner/owner_providers.dart';

const _hostelId = 'h-sunrise';
const _period = '2026-08';

const _session = NivoraSession(
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
  totalFloors: 2,
  totalRooms: 3,
  bedsPerRoomDefault: 3,
  address: '12 MG Road, Pune',
  status: HostelStatus.active,
  createdAt: DateTime.utc(2026, 3, 1),
  updatedAt: DateTime.utc(2026, 3, 1),
);

const _rooms = [
  RoomOccupancy(
    roomId: 'r-101',
    floorId: 'f-1',
    floorNumber: 1,
    roomNumber: '101',
    capacity: 3,
    occupied: 3,
  ),
  RoomOccupancy(
    roomId: 'r-102',
    floorId: 'f-1',
    floorNumber: 1,
    roomNumber: '102',
    capacity: 3,
    occupied: 1,
  ),
  RoomOccupancy(
    roomId: 'r-201',
    floorId: 'f-2',
    floorNumber: 2,
    roomNumber: '201',
    capacity: 2,
    occupied: 0,
  ),
];

final _beds = [
  Bed(
    id: 'b1',
    hostelId: _hostelId,
    roomId: 'r-102',
    bedNumber: 1,
    status: BedStatus.occupied,
    studentId: 's-aarav',
    createdAt: DateTime.utc(2026, 3, 1),
    updatedAt: DateTime.utc(2026, 3, 1),
  ),
  Bed(
    id: 'b2',
    hostelId: _hostelId,
    roomId: 'r-102',
    bedNumber: 2,
    status: BedStatus.free,
    createdAt: DateTime.utc(2026, 3, 1),
    updatedAt: DateTime.utc(2026, 3, 1),
  ),
];

final _aarav = Student(
  id: 's-aarav',
  hostelId: _hostelId,
  fullName: 'Aarav Sharma',
  phone: '9000000001',
  dateOfJoining: DateTime(2026, 3, 7),
  monthlyFee: 7000,
  status: StudentStatus.active,
  createdAt: DateTime.utc(2026, 3, 7),
  updatedAt: DateTime.utc(2026, 3, 7),
);

HostelStats _stats() => const HostelStats(
      totalBeds: 8,
      occupiedBeds: 4,
      activeStudents: 4,
      openComplaints: 2,
      feesCollected: 21000,
      feesPending: 7000,
      studentsPaid: 3,
      studentsUnpaid: 1,
      pendingLeaves: 0,
      visitorsToday: 0,
      pendingTasks: 0,
      revenueToday: 0,
      expensesToday: 0,
      revenueMonth: 21000,
      expensesMonth: 9000,
      subscriptionState: SubscriptionState.active,
      subscriptionDaysLeft: 300,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<RoomOccupancy> rooms = _rooms,
  List<Hostel> owned = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(_session),
        currentHostelIdProvider.overrideWithValue(_hostelId),
        currentPeriodMonthProvider.overrideWithValue(_period),
        myHostelsProvider.overrideWith((ref) => owned.isEmpty ? [_sunrise] : owned),
        hostelProvider.overrideWith((ref, id) => _sunrise),
        hostelStatsProvider.overrideWith((ref, query) => _stats()),
        roomOccupancyProvider.overrideWith((ref, id) => rooms),
        bedsInRoomProvider.overrideWith((ref, roomId) => _beds),
        studentProvider.overrideWith((ref, id) => _aarav),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('the PG list', () {
    testWidgets('each PG carries its own occupancy and collections', (tester) async {
      await _pump(tester, const Scaffold(body: OwnerPgListScreen()));

      expect(find.text('Sunrise Residency'), findsOneWidget);
      expect(find.text('12 MG Road, Pune'), findsOneWidget);
      expect(find.text('50% occupancy — 4 beds vacant.'), findsOneWidget);
      expect(find.textContaining('₹21,000 collected in August'), findsOneWidget);
      expect(find.text('2 complaints still open.'), findsOneWidget);
      // The PG the dashboard is currently showing is marked, so the switcher and this list
      // never disagree about which one is which.
      expect(find.text('On your dashboard'), findsOneWidget);
    });

    testWidgets('an owner with no PG is told who sets one up', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(_session),
            currentPeriodMonthProvider.overrideWithValue(_period),
            myHostelsProvider.overrideWith((ref) => <Hostel>[]),
          ],
          child: const MaterialApp(home: Scaffold(body: OwnerPgListScreen())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No PG on your account yet'), findsOneWidget);
      expect(find.textContaining('account manager'), findsOneWidget);
    });
  });

  group('the room grid', () {
    testWidgets('rooms are grouped by the floor number the database stores', (tester) async {
      await _pump(tester, const OwnerPgDetailScreen(hostelId: _hostelId));

      expect(find.text('Sunrise Residency'), findsOneWidget);
      expect(find.text('Floor 1'), findsOneWidget);
      expect(find.text('Floor 2'), findsOneWidget);
      expect(find.text('101'), findsOneWidget);
      expect(find.text('102'), findsOneWidget);
      expect(find.text('201'), findsOneWidget);
    });

    testWidgets('the totals are added from the very rows that are drawn', (tester) async {
      await _pump(tester, const OwnerPgDetailScreen(hostelId: _hostelId));

      // 3 + 3 + 2 beds, 3 + 1 + 0 taken.
      expect(find.text('4 of 8 beds filled'), findsOneWidget);
      expect(find.text('50% full · 2 rooms with space · 3 rooms in total'), findsOneWidget);
    });

    testWidgets('a full room says so and a room with space says how much', (tester) async {
      await _pump(tester, const OwnerPgDetailScreen(hostelId: _hostelId));

      expect(find.text('Full'), findsOneWidget, reason: '101 is 3 of 3');
      // 102 has one of three taken and 201 is empty with two beds: both read "2 free".
      expect(find.text('2 free'), findsNWidgets(2));
      expect(find.text('0 free'), findsNothing, reason: 'a full room says Full, not 0 free');
    });

    testWidgets('a PG with no rooms explains who scaffolds them', (tester) async {
      await _pump(tester, const OwnerPgDetailScreen(hostelId: _hostelId), rooms: const []);
      expect(find.text('No rooms set up yet'), findsOneWidget);
    });

    testWidgets('tapping a room names who is in each bed', (tester) async {
      await _pump(tester, const OwnerPgDetailScreen(hostelId: _hostelId));

      await tester.tap(find.text('102'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Room 102'), findsOneWidget);
      expect(find.text('Floor 1 · 1 of 3 beds taken'), findsOneWidget);
      expect(find.text('Bed 1'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('Bed 2'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
    });
  });
}
