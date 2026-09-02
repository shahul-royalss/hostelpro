// Does the owner's area still LAY OUT on a real phone?
//
// WHY THIS FILE EXISTS. The other owner widget tests pump onto a 1200x4000 surface, on purpose:
// a ListView does not build what is off screen, so a phone-sized window would make "the section
// below the chart is missing" and "the section below the chart is broken" look identical. The
// cost of that is that they cannot see an overflow, because nothing on a 1200pt-wide surface is
// ever short of room.
//
// This file is the other half. It renders the same screens at the two widths Nivora actually
// ships to and at the three text scales Android offers up to Large, and fails on any layout
// exception. It is not a golden test — it asserts nothing about how the screens look, only that
// Flutter could lay them out — which is why it needs no maintenance when the design moves again.
//
// It was written because the 2x2 KPI grid restyle shipped a real one: `Row(Expanded(label),
// Text(value))` hands the value unbounded width, so `₹4,82,50,000` on a PG card never
// ellipsised, it overflowed — invisible at 1.0x on a wide surface, 151 pixels off the edge at
// 1.4x on a 320dp phone. The fixture below is deliberately hostile: a crore of collections, a
// forty-character hostel name, a suspended subscription banner and a long complaint title.
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
import 'package:mobile/features/owner/owner_pg_list_screen.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/owner/staff/owner_staff_screen.dart';
import 'package:mobile/features/owner/staff/staff_models.dart';
import 'package:mobile/features/owner/staff/staff_providers.dart';

const _period = '2026-08';
const _hostelId = 'h-sunrise';

/// 390dp is the iPhone 14 / Pixel 7 class this app is designed against; 320dp is the narrowest
/// Android phone still in the wild and the width every comment in this feature worries about.
const _widths = [Size(390, 844), Size(320, 640)];

/// 1.0 is the default, 1.3 is Android's "Large", 1.4 is the ceiling this codebase's own
/// comments keep citing.
const _scales = [1.0, 1.3, 1.4];

final _session = const NivoraSession(
  userId: 'owner-1',
  role: UserRole.owner,
  fullName: 'Ananya Venkataraghavan',
  status: 'active',
  mustChangePassword: false,
  hostelId: _hostelId,
);

final _sunrise = Hostel(
  id: _hostelId,
  name: 'Sunrise Residency Koramangala Annexe',
  address: '12 MG Road, Koramangala 4th Block, Bengaluru 560034',
  ownerUserId: 'owner-1',
  totalFloors: 3,
  totalRooms: 12,
  bedsPerRoomDefault: 3,
  status: HostelStatus.suspended,
  createdAt: DateTime.utc(2026, 3, 1),
  updatedAt: DateTime.utc(2026, 3, 1),
);

/// A crore of collections against a lakh-scale ledger — the widest money strings the `en_IN`
/// formatter can produce short of ten crore, which is what broke the PG card.
const _stats = HostelStats(
  totalBeds: 180,
  occupiedBeds: 156,
  activeStudents: 160,
  openComplaints: 12,
  feesCollected: 48250000,
  feesPending: 13750000,
  studentsPaid: 140,
  studentsUnpaid: 14,
  pendingLeaves: 3,
  visitorsToday: 0,
  pendingTasks: 7,
  revenueToday: 0,
  expensesToday: 0,
  revenueMonth: 45200000,
  expensesMonth: 50400000,
  // Drives the notice banner, which is the widest single block on the dashboard.
  subscriptionState: SubscriptionState.expiring,
  subscriptionDaysLeft: 4,
);

final _window = FinanceRangeQuery(
  hostelId: _hostelId,
  from: DateTime(2026, 7, 26),
  to: DateTime(2026, 8, 24),
);

List<FinanceDay> _series() => [
      for (var i = 0; i < 30; i++)
        FinanceDay(
          day: DateTime(2026, 7, 26 + i),
          revenue: i.isEven ? 150000 : 0,
          expense: i % 3 == 0 ? 90000 : 0,
        ),
    ];

List<ActivityItem> _activity() => [
      ActivityItem(
        kind: ActivityKind.complaint,
        id: 'c1',
        title: 'Geyser in the second floor bathroom is not heating at all',
        detail: 'Maintenance',
        at: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
        complaintStatus: ComplaintStatus.inProgress,
      ),
      ActivityItem(
        kind: ActivityKind.notice,
        id: 'n1',
        title: 'Water tanker on Sunday morning, please store what you need',
        detail: 'Notice to everyone',
        at: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      ),
    ];

List<StaffMember> _staff() => [
      StaffMember(
        id: 'u-1',
        fullName: 'Rajendra Prasad Venkataraghavan',
        role: StaffRole.manager,
        status: StaffStatus.active,
        email: 'rajendra.venkataraghavan@sunriseresidency.example.com',
        phone: '+91 98765 43210',
        createdAt: DateTime.utc(2026, 5, 4),
      ),
    ];

/// Pumps [home] at [size] and [scale] and fails if Flutter reported any layout error.
///
/// `takeException` is the assertion: an overflow arrives as a `FlutterError` on the test
/// binding, exactly like a thrown exception would, and a screen that overflows is a screen with
/// a black-and-yellow bar across it on a real phone.
Future<void> _pump(
  WidgetTester tester,
  Widget home,
  double scale,
  Size size, {
  bool statsPending = false,
  Object? statsError,
  List<StaffMember>? staff,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(_session),
        currentHostelIdProvider.overrideWithValue(_hostelId),
        currentPeriodMonthProvider.overrideWithValue(_period),
        myHostelsProvider.overrideWith((ref) => [_sunrise]),
        hostelProvider.overrideWith((ref, id) => _sunrise),
        ownerFinanceWindowProvider.overrideWithValue(_window),
        hostelStatsProvider.overrideWith((ref, q) {
          if (statsError != null) return Future<HostelStats?>.error(statsError);
          if (statsPending) return Completer<HostelStats?>().future;
          return _stats;
        }),
        dailyFinanceProvider.overrideWith((ref, q) => _series()),
        ownerActivityProvider.overrideWith((ref, id) => AsyncData(_activity())),
        ownerStaffProvider.overrideWith((ref, id) => staff ?? _staff()),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale), size: size),
          child: Scaffold(body: home),
        ),
      ),
    ),
  );
  // Never pumpAndSettle: the skeletons pulse forever by design.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull, reason: 'at ${scale}x on ${size.width}dp');
}

void main() {
  for (final scale in _scales) {
    for (final size in _widths) {
      final where = '${scale}x on ${size.width.toInt()}dp';

      testWidgets('the dashboard fits $where', (tester) async {
        await _pump(tester, const OwnerDashboardScreen(), scale, size);
      });

      // The skeleton is now the same 2x2 grid as the real thing, so it has its own way to
      // overflow and its own test.
      testWidgets('the dashboard skeleton fits $where', (tester) async {
        await _pump(tester, const OwnerDashboardScreen(), scale, size, statsPending: true);
      });

      testWidgets('a failed dashboard fits $where', (tester) async {
        await _pump(
          tester,
          const OwnerDashboardScreen(),
          scale,
          size,
          statsError: const OfflineFailure('no route to host'),
        );
      });

      testWidgets('the PG list fits $where', (tester) async {
        await _pump(tester, const OwnerPgListScreen(), scale, size);
      });

      testWidgets('the staff screen fits $where', (tester) async {
        await _pump(tester, const OwnerStaffScreen(), scale, size);
      });

      // An empty post draws a different card — the add button and the empty note — and it is
      // the one an owner sees on day one.
      testWidgets('an unstaffed PG fits $where', (tester) async {
        await _pump(
          tester,
          const OwnerStaffScreen(),
          scale,
          size,
          staff: const <StaffMember>[],
        );
      });
    }
  }
}
