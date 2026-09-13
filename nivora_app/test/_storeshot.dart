// A DEV TOOL, not a test — `flutter test` skips it because the name does not end in _test.
// Run it explicitly: `flutter test test/_storeshot.dart`, then look in build/store-shots/.
//
// WHAT THIS IS FOR, and how it differs from _shot.dart. That one exists to catch chrome bugs
// during development and says so in its own header: "Icons render as squares here — the test
// runner stubs the icon font — so check glyphs on a device, not in these." A square where an
// icon should be is fine in a dev shot and fatal in a Play Store screenshot, so this file loads
// the REAL MaterialIcons font off the Flutter SDK before rendering anything.
//
// It also captures at the device pixel ratio rather than at 1. _shot.dart writes ~393x873 PNGs,
// which are below Play's 1080px-per-side bar for promotion eligibility; these come out at the
// exact sizes Play asks for.
//
// EVERY PIXEL HERE IS THE REAL APP. Same widgets, same theme, same layout code — only the data
// is fabricated, and it describes a hostel that does not exist so that no resident's name,
// photograph or rent ever appears in a public store listing.
//
// THE DATA IS THE POINT OF THIS FILE'S SECOND HALF. A store screenshot of a skeleton, of
// "Nothing yet", or worst of all of "That did not load", is a screenshot of the app failing.
// Every provider each role's first tab reads is overridden below with a plausible month at
// Sunrise Residency, so the four shots show the product doing its job.
//
// THE ONE API TRAP. Most of these are FutureProviders and take `(ref, arg) => value`. The
// paginated lists — notices, complaints, tasks, expenses, revenues, fee history — are
// AsyncNotifierProvider FAMILIES, and a family's plain `overrideWith` is deprecated in riverpod
// 3.4.2 and is handed no family argument. Those use `overrideWith2(_Fake.new)` with a subclass
// of the real notifier that swaps out fetchPage only, which is the pattern the rest of the
// suite already uses (see test/owner_notices_test.dart, test/manager_test.dart).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not on the main barrel in riverpod 3.4.2 — it lives here.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/version/release_check.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/manager/data/manager_models.dart';
import 'package:mobile/features/manager/data/manager_providers.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/shell/role_shell.dart';
import 'package:mobile/features/student/student_providers.dart';
import 'package:mobile/features/warden/data/warden_models.dart';
import 'package:mobile/features/warden/data/warden_providers.dart';

const _hostelId = 'h-sunrise';

/// Anchored to the wall clock, not to a fixed month. Half of what these screens draw —
/// "Good evening · 12 Sep 2026", `relativeTime`, `dueLabel`, `MenuDay.of(now)` — is computed
/// from `DateTime.now()` and cannot be overridden, so a hard-coded period would put
/// "RENT · AUGUST" under a September greeting and make the shot look stale.
final _now = DateTime.now();
final _period = '${_now.year}-${_now.month.toString().padLeft(2, '0')}';

/// Local midnight today. Task due dates and the finance window key off it.
final _today = DateTime(_now.year, _now.month, _now.day);

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

/// Play's phone and 7-inch slots: exactly 9:16, 1080 on the short side so the listing is
/// eligible for promotion. The logical width is a real phone's, so the layout is the one a
/// phone actually gets rather than a stretched tablet.
// 400 x 2.7 = 1080 exactly, and 400*16/9 x 2.7 = 1920 exactly. A logical width chosen to
// divide cleanly: 392.73 at 2.75 produced 1081x1921, which is not 9:16 and looks careless.
const _phone = _Canvas(logicalWidth: 400, dpr: 2.7, tag: 'phone');

/// Play's 10-inch slot: still 9:16, but laid out at a tablet's logical width so the app's own
/// responsive breakpoints do whatever they really do at that size.
const _tablet10 = _Canvas(logicalWidth: 800, dpr: 1.8, tag: 'tablet10');

class _Canvas {
  const _Canvas({required this.logicalWidth, required this.dpr, required this.tag});
  final double logicalWidth;
  final double dpr;
  final String tag;

  /// 9:16 exactly, in logical pixels.
  double get logicalHeight => logicalWidth * 16 / 9;
  Size get physical => Size(logicalWidth * dpr, logicalHeight * dpr);
}

// ─────────────────────────────────────────────────────────────────────────────
// THE DEMO HOSTEL
//
// Sunrise Residency: 3 floors x 12 rooms x 3 beds = 36 beds, 31 of them taken. Every count
// below agrees with that arithmetic, because two cards on one screen contradicting each other
// is exactly the kind of thing a reviewer notices. Rents are 6,000–9,000, expenses run in the
// hundreds to low thousands, names are Indian and invented, and every phone number is in the
// 90000000xx block so none of them can ring a real person.
// ─────────────────────────────────────────────────────────────────────────────

/// One page of anything. The paginated fakes all hand back a single complete page.
PagedResult<T> _page<T>(List<T> items) =>
    PagedResult<T>(items: items, page: 0, pageSize: PagedResult.defaultPageSize, hasMore: false);

// ── Notices, read by the owner dashboard, the warden home and the resident home ──────────
//
// createdAt is relative to now on purpose: the labels are "5h ago" / "2d ago" for anything
// inside a week and a bare date after that, so fixed timestamps would rot into stale dates.
final _notices = <Notice>[
  Notice(
    id: 'ntc-1',
    hostelId: _hostelId,
    authorUserId: 'owner-1',
    title: 'Water tanker on Saturday at 7 am',
    body: 'The municipal supply is off all Saturday morning. A tanker is booked for 7 am — '
        'please fill your buckets on Friday night.',
    audience: NoticeAudience.all,
    createdAt: _now.subtract(const Duration(hours: 5)),
    updatedAt: _now.subtract(const Duration(hours: 5)),
  ),
  Notice(
    id: 'ntc-2',
    hostelId: _hostelId,
    authorUserId: 'owner-1',
    title: 'Rent for this month is due on the 5th',
    body: 'Pay at the desk or by UPI. A receipt is issued the moment it is recorded.',
    audience: NoticeAudience.students,
    createdAt: _now.subtract(const Duration(days: 2)),
    updatedAt: _now.subtract(const Duration(days: 2)),
  ),
  Notice(
    id: 'ntc-3',
    hostelId: _hostelId,
    authorUserId: 'owner-1',
    title: 'Mess menu changes from Monday',
    body: 'Tuesday dinner moves to South Indian. The full week is on the Menu tab.',
    audience: NoticeAudience.warden,
    createdAt: _now.subtract(const Duration(days: 6)),
    updatedAt: _now.subtract(const Duration(days: 6)),
  ),
];

class _ShotNotices extends NoticesNotifier {
  _ShotNotices(super.hostelId);

  @override
  Future<PagedResult<Notice>> fetchPage(int page) async => _page(_notices);
}

// ── Complaints ───────────────────────────────────────────────────────────────────────────
// One still open and one resolved, so the "Still open" tile answers 1 rather than a dash.
final _complaints = <Complaint>[
  Complaint(
    id: 'cmp-1',
    hostelId: _hostelId,
    studentId: 'stu-204-2',
    category: ComplaintCategory.maintenance,
    title: 'Bathroom tap leaking on the second floor',
    description: 'The tap next to room 204 runs continuously and the floor stays wet.',
    status: ComplaintStatus.inProgress,
    createdAt: _now.subtract(const Duration(days: 3)),
    updatedAt: _now.subtract(const Duration(days: 1)),
  ),
  Complaint(
    id: 'cmp-2',
    hostelId: _hostelId,
    studentId: 'stu-204-2',
    category: ComplaintCategory.wifi,
    title: 'Wi-Fi drops in the evening',
    description: 'Between 8 pm and 10 pm the second floor loses the connection.',
    status: ComplaintStatus.resolved,
    resolutionNote: 'A second access point was installed on the second-floor landing.',
    resolvedAt: _now.subtract(const Duration(days: 8)),
    createdAt: _now.subtract(const Duration(days: 14)),
    updatedAt: _now.subtract(const Duration(days: 8)),
  ),
];

class _ShotComplaints extends ComplaintsNotifier {
  _ShotComplaints(super.query);

  @override
  Future<PagedResult<Complaint>> fetchPage(int page) async =>
      _page(query.openOnly ? _complaints.where((c) => c.isOpen).toList() : _complaints);
}

// ── The week's food, used by the manager's Menu tab and the resident's "Today's food" ─────
//
// EVERY DAY IS PLANNED, and that is not padding. Both screens ask `MenuDay.of(DateTime.now())`,
// so a menu covering one weekday renders an empty tile whenever the shot is retaken on another.
const _plate = <Meal, String>{
  Meal.breakfast: 'Poha, boiled egg, filter coffee',
  Meal.lunch: 'Rajma chawal, jeera aloo, curd, salad',
  Meal.snacks: 'Masala chai, veg cutlet',
  Meal.dinner: 'Roti, paneer butter masala, dal tadka, rice',
};

final _weekMenu = WeeklyMenu([
  for (final day in MenuDay.values)
    for (final meal in Meal.values)
      MenuEntry(
        id: 'menu-${day.wire}-${meal.wire}',
        hostelId: _hostelId,
        day: day,
        meal: meal,
        items: _plate[meal]!,
        createdAt: DateTime.utc(2026, 3, 1),
        updatedAt: _now.subtract(const Duration(days: 1)),
      ),
]);

// ── OWNER ────────────────────────────────────────────────────────────────────────────────

/// Chosen so no card on the owner dashboard falls into an empty or alarm state:
/// subscription active (no warning strip), beds > 0 (occupancy reads 86%, not "—"),
/// fees pending > 0 (the collection meter has something to draw), and pending leaves and
/// tasks > 0 so "Needs you" renders two real rows instead of collapsing away.
const _ownerStats = HostelStats(
  totalBeds: 36,
  occupiedBeds: 31,
  activeStudents: 31,
  openComplaints: 3,
  feesCollected: 216000,
  feesPending: 24000,
  studentsPaid: 28,
  studentsUnpaid: 3,
  pendingLeaves: 2,
  visitorsToday: 4,
  pendingTasks: 3,
  revenueToday: 8600,
  expensesToday: 4820,
  revenueMonth: 231500,
  expensesMonth: 86400,
  subscriptionState: SubscriptionState.active,
  subscriptionDaysLeft: 214,
);

/// The cashflow well. Built FROM THE QUERY rather than from a fixed date, because the family
/// key comes out of `ownerFinanceWindowProvider`, which reads the clock — there is no single
/// FinanceRangeQuery this file could name. The chart needs one non-zero value or it draws its
/// own empty card instead of a plot.
List<FinanceDay> _ownerFinance(FinanceRangeQuery q) {
  final count = q.to.difference(q.from).inDays + 1;
  return [
    for (var i = 0; i < count; i++)
      FinanceDay(
        day: q.from.add(Duration(days: i)),
        // Rent lands in a weekly pulse; the rest is mess income and deposits.
        revenue: i % 7 == 1 ? 42000 : (i % 3 == 0 ? 6500 : 2800),
        // One heavier grocery-and-maintenance day a week gives the expense line some shape.
        expense: i % 7 == 6 ? 8500 : (i % 2 == 0 ? 4200 : 2100),
      ),
  ];
}

// ── WARDEN ───────────────────────────────────────────────────────────────────────────────

/// The same 36 beds and 31 residents the owner sees, so the two shots agree.
const _wardenStats = HostelStats(
  totalBeds: 36,
  occupiedBeds: 31,
  activeStudents: 31,
  openComplaints: 3,
  feesCollected: 216000,
  feesPending: 24000,
  studentsPaid: 28,
  studentsUnpaid: 3,
  pendingLeaves: 2,
  visitorsToday: 7,
  pendingTasks: 4,
  revenueToday: 8600,
  expensesToday: 3150,
  revenueMonth: 231500,
  expensesMonth: 86400,
  subscriptionState: SubscriptionState.active,
  subscriptionDaysLeft: 214,
);

/// Three guests signed in and not yet signed out. Only the count reaches the home tab; the
/// names appear in the visitors sheet, which a screenshot never opens.
final _onSite = <VisitorLog>[
  VisitorLog(
    id: 'v-1',
    hostelId: _hostelId,
    studentId: 'stu-101-1',
    visitorName: 'Meera Deshpande',
    relation: 'Mother',
    visitorPhone: '9000000021',
    checkInAt: _today.add(const Duration(hours: 10, minutes: 20)),
    createdAt: _today.add(const Duration(hours: 10, minutes: 20)),
    studentName: 'Aditya Deshpande',
  ),
  VisitorLog(
    id: 'v-2',
    hostelId: _hostelId,
    studentId: 'stu-202-3',
    visitorName: 'Rohit Kulkarni',
    relation: 'Brother',
    visitorPhone: '9000000022',
    checkInAt: _today.add(const Duration(hours: 12, minutes: 5)),
    createdAt: _today.add(const Duration(hours: 12, minutes: 5)),
    studentName: 'Sneha Kulkarni',
  ),
  VisitorLog(
    id: 'v-3',
    hostelId: _hostelId,
    studentId: 'stu-303-2',
    visitorName: 'Farhan Qureshi',
    relation: 'Friend',
    visitorPhone: '9000000023',
    checkInAt: _today.add(const Duration(hours: 16, minutes: 40)),
    createdAt: _today.add(const Duration(hours: 16, minutes: 40)),
    studentName: 'Imran Qureshi',
  ),
];

/// 12 rooms x 3 beds = 36, 31 occupied — the arithmetic both stat blocks report, so the
/// occupancy tile and the floor meter cannot contradict each other.
const _rooms = <RoomOccupancy>[
  RoomOccupancy(roomId: 'r-101', floorId: 'f-1', floorNumber: 1, floorName: 'First floor', roomNumber: '101', capacity: 3, occupied: 3),
  RoomOccupancy(roomId: 'r-102', floorId: 'f-1', floorNumber: 1, floorName: 'First floor', roomNumber: '102', capacity: 3, occupied: 3),
  RoomOccupancy(roomId: 'r-103', floorId: 'f-1', floorNumber: 1, floorName: 'First floor', roomNumber: '103', capacity: 3, occupied: 2),
  RoomOccupancy(roomId: 'r-104', floorId: 'f-1', floorNumber: 1, floorName: 'First floor', roomNumber: '104', capacity: 3, occupied: 3),
  RoomOccupancy(roomId: 'r-201', floorId: 'f-2', floorNumber: 2, floorName: 'Second floor', roomNumber: '201', capacity: 3, occupied: 3),
  RoomOccupancy(roomId: 'r-202', floorId: 'f-2', floorNumber: 2, floorName: 'Second floor', roomNumber: '202', capacity: 3, occupied: 2),
  RoomOccupancy(roomId: 'r-203', floorId: 'f-2', floorNumber: 2, floorName: 'Second floor', roomNumber: '203', capacity: 3, occupied: 3),
  RoomOccupancy(roomId: 'r-204', floorId: 'f-2', floorNumber: 2, floorName: 'Second floor', roomNumber: '204', capacity: 3, occupied: 3),
  RoomOccupancy(roomId: 'r-301', floorId: 'f-3', floorNumber: 3, floorName: 'Third floor', roomNumber: '301', capacity: 3, occupied: 3),
  RoomOccupancy(roomId: 'r-302', floorId: 'f-3', floorNumber: 3, floorName: 'Third floor', roomNumber: '302', capacity: 3, occupied: 3),
  RoomOccupancy(roomId: 'r-303', floorId: 'f-3', floorNumber: 3, floorName: 'Third floor', roomNumber: '303', capacity: 3, occupied: 2),
  RoomOccupancy(roomId: 'r-304', floorId: 'f-3', floorNumber: 3, floorName: 'Third floor', roomNumber: '304', capacity: 3, occupied: 1),
];

// ── MANAGER ──────────────────────────────────────────────────────────────────────────────

const _managerId = 'u-1';
const _ownerId = 'owner-1';

/// Money in and out, built the way managerFinanceProvider builds it: the window starts at
/// whichever is earlier, the first of the month or `trendDays` ago, and FinanceWindow slices
/// it into the month totals and the short trend.
///
/// The day list is gap-free and its last entry IS today, which is what makes `todayOut`
/// resolve to a figure rather than the "no figure for today" dash — FinanceWindow finds today
/// by exact DateTime equality, so both sides must be local midnight. Revenue slightly exceeds
/// expense so "Difference this month" comes out positive, and is drawn in cream rather than red.
FinanceWindow _financeWindow() {
  final monthStart = DateTime(_today.year, _today.month);
  final trendStart = DateTime(_today.year, _today.month, _today.day - (trendDays - 1));
  final from = monthStart.isBefore(trendStart) ? monthStart : trendStart;

  // Indexed by day of the month, so the bars have an organic shape and the same day always
  // looks the same. The two spikes are a gas-cylinder run and the month's electricity bill.
  const out = <double>[
    4820, 6150, 3980, 9250, 5340, 4610, 8720, 3760, 5980, 9300,
    4450, 6890, 5120, 7640, 4275, 7310, 5860, 3990, 6420, 8150,
    4730, 5240, 9180, 4560, 6070, 3820, 7940, 5310, 4680, 6530, 5170,
  ];
  const income = <double>[
    9200, 7450, 12800, 6300, 8900, 11400, 7100, 9750, 6800, 13200,
    8400, 7900, 10600, 6950, 9300, 8100, 11900, 7600, 8850, 10200,
    7350, 9600, 6700, 12100, 8250, 9050, 7800, 10800, 6400, 9450, 8600,
  ];

  final days = <FinanceDay>[];
  for (var d = from; !d.isAfter(_today); d = DateTime(d.year, d.month, d.day + 1)) {
    final i = (d.day - 1) % out.length;
    days.add(FinanceDay(day: d, revenue: income[i], expense: out[i]));
  }
  return FinanceWindow(
    days: days,
    monthStart: monthStart,
    trendStart: trendStart,
    today: _today,
  );
}

/// Four open jobs in due-date order, which is the order the repository returns them and the
/// order the home tile calls "nearest the deadline". Exactly one is past its date, agreeing
/// with TaskLoad(open: 4, overdue: 1).
List<Task> _managerTasks() => [
      Task(
        id: 't-1',
        hostelId: _hostelId,
        assignedTo: _managerId,
        title: 'Settle the milk vendor bill for last week',
        description: 'Ravi Dairy, 84 litres a day.',
        dueDate: DateTime(_today.year, _today.month, _today.day - 1),
        status: TaskStatus.inProgress,
        createdBy: _ownerId,
        createdAt: DateTime.utc(2026, 3, 2),
        updatedAt: DateTime.utc(2026, 3, 2),
      ),
      Task(
        id: 't-2',
        hostelId: _hostelId,
        assignedTo: _managerId,
        title: 'Replace the RO filter cartridges on all three floors',
        dueDate: _today,
        status: TaskStatus.pending,
        createdBy: _ownerId,
        createdAt: DateTime.utc(2026, 3, 3),
        updatedAt: DateTime.utc(2026, 3, 3),
      ),
      Task(
        id: 't-3',
        hostelId: _hostelId,
        assignedTo: _managerId,
        title: 'Get the kitchen chimney serviced before the festival week',
        dueDate: DateTime(_today.year, _today.month, _today.day + 2),
        status: TaskStatus.pending,
        createdBy: _ownerId,
        createdAt: DateTime.utc(2026, 3, 4),
        updatedAt: DateTime.utc(2026, 3, 4),
      ),
      Task(
        id: 't-4',
        hostelId: _hostelId,
        assignedTo: _managerId,
        title: 'Collect the mess deposit slips from rooms 204 and 303',
        dueDate: DateTime(_today.year, _today.month, _today.day + 5),
        status: TaskStatus.pending,
        createdBy: _ownerId,
        createdAt: DateTime.utc(2026, 3, 5),
        updatedAt: DateTime.utc(2026, 3, 5),
      ),
    ];

/// For the Expenses tab. Monthly rows carry the first of the month they belong to.
List<Expense> _managerExpenses() => [
      Expense(
        id: 'e-1',
        hostelId: _hostelId,
        date: _today,
        category: ExpenseCategory.groceries,
        amount: 4820,
        note: 'Vegetables and rice, morning market',
        createdAt: DateTime.utc(2026, 3, 1),
        updatedAt: DateTime.utc(2026, 3, 1),
      ),
      Expense(
        id: 'e-2',
        hostelId: _hostelId,
        date: DateTime(_today.year, _today.month),
        category: ExpenseCategory.electricity,
        kind: ExpenseKind.monthly,
        amount: 9240,
        note: 'Three-phase meter, August reading',
        createdAt: DateTime.utc(2026, 3, 1),
        updatedAt: DateTime.utc(2026, 3, 1),
      ),
      Expense(
        id: 'e-3',
        hostelId: _hostelId,
        date: DateTime(_today.year, _today.month, _today.day - 2),
        category: ExpenseCategory.maintenance,
        amount: 1450,
        note: 'Plumber, second-floor tap',
        createdAt: DateTime.utc(2026, 3, 1),
        updatedAt: DateTime.utc(2026, 3, 1),
      ),
    ];

/// For the "Money in" segment.
List<Revenue> _managerRevenues() => [
      Revenue(
        id: 'rev-1',
        hostelId: _hostelId,
        date: _today,
        source: RevenueSource.mess,
        amount: 9200,
        note: 'Guest meal coupons',
        createdAt: DateTime.utc(2026, 3, 1),
        updatedAt: DateTime.utc(2026, 3, 1),
      ),
    ];

class _ShotTasks extends TasksNotifier {
  _ShotTasks(super.query);

  @override
  Future<PagedResult<Task>> fetchPage(int page) async => _page(_managerTasks());
}

class _ShotExpenses extends ManagerExpensesNotifier {
  _ShotExpenses(super.query);

  @override
  Future<PagedResult<Expense>> fetchPage(int page) async => _page(_managerExpenses());
}

class _ShotRevenues extends ManagerRevenuesNotifier {
  _ShotRevenues(super.hostelId);

  @override
  Future<PagedResult<Revenue>> fetchPage(int page) async => _page(_managerRevenues());
}

/// Pins the Menu tab to one weekday, so the shot is not a different shot on Sunday.
class _PinnedMenuDay extends MenuDayState {
  _PinnedMenuDay(this.day);
  final MenuDay day;

  @override
  MenuDay build() => day;
}

// ── RESIDENT ─────────────────────────────────────────────────────────────────────────────

const _residentId = 'stu-204-2';

/// `fullName` matches the session's on purpose: the shell's masthead draws the session name
/// and the greeting card draws this one. Two different names in one screenshot reads as a bug.
/// `email` is deliberately null — that is what keeps VerifyEmailBanner, the first child of
/// Home's list, collapsed to nothing.
final _resident = Student(
  id: _residentId,
  hostelId: _hostelId,
  userId: 'u-1',
  fullName: 'Ananya Rao',
  phone: '9000000004',
  guardianName: 'Suresh Rao',
  guardianPhone: '9000000014',
  permanentAddress: '14, Vidyaranyapura, Bengaluru 560097',
  idProofType: 'Aadhaar',
  dateOfJoining: DateTime(2026, 3, 7),
  monthlyFee: 7500,
  status: StudentStatus.active,
  roomId: 'r-204',
  bedId: 'bed-204-2',
  createdAt: DateTime.utc(2026, 3, 7),
  updatedAt: DateTime.utc(2026, 3, 7),
);

/// `balance` is a getter — 7500 − 4500 — so the card headlines "₹3,000 still to pay" with the
/// PARTLY PAID pill and a meter two-thirds along.
final _rentRow = FeeLedgerRow(
  studentId: _residentId,
  fullName: 'Ananya Rao',
  phone: '9000000004',
  monthlyFee: 7500,
  amountDue: 7500,
  amountPaid: 4500,
  status: FeeStatus.partial,
  roomNumber: '204',
  bedNumber: 2,
  paidOn: DateTime(_today.year, _today.month, 5),
  mode: PaymentMode.upi,
);

const _contacts = HostelContacts(
  hostelName: 'Sunrise Residency',
  address: '24, 5th Cross, Koramangala 6th Block, Bengaluru 560095',
  rules: 'The main gate closes at 11 pm. Guests are signed in at the desk.',
  wardenName: 'Priya Nair',
  wardenPhone: '9000000003',
  managerName: 'Rahul Mehta',
  managerPhone: '9000000002',
  ownerName: 'Vikram Shetty',
);

const _roommates = <Roommate>[
  Roommate(studentId: 'stu-204-1', fullName: 'Ishaan Verma', phone: '9000000005', bedNumber: 1),
  Roommate(studentId: 'stu-204-3', fullName: 'Aarav Sharma', phone: '9000000006', bedNumber: 3),
];

/// Warmed rather than drawn on Home, so the Fees tab is right too.
final _feeHistory = <FeePayment>[
  FeePayment(
    id: 'pay-current',
    hostelId: _hostelId,
    studentId: _residentId,
    periodMonth: _period,
    amountDue: 7500,
    amountPaid: 4500,
    status: FeeStatus.partial,
    paidOn: DateTime(_today.year, _today.month, 5),
    mode: PaymentMode.upi,
    createdAt: DateTime.utc(2026, 3, 5),
    updatedAt: DateTime.utc(2026, 3, 5),
  ),
  FeePayment(
    id: 'pay-previous',
    hostelId: _hostelId,
    studentId: _residentId,
    periodMonth: '${_today.year}-${(_today.month - 1).toString().padLeft(2, '0')}',
    amountDue: 7500,
    amountPaid: 7500,
    status: FeeStatus.paid,
    paidOn: DateTime(_today.year, _today.month - 1, 3),
    mode: PaymentMode.cash,
    createdAt: DateTime.utc(2026, 3, 3),
    updatedAt: DateTime.utc(2026, 3, 3),
  ),
];

class _ShotFeeHistory extends StudentFeeHistoryNotifier {
  _ShotFeeHistory(super.studentId);

  @override
  Future<PagedResult<FeePayment>> fetchPage(int page) async => _page(_feeHistory);
}

// ─────────────────────────────────────────────────────────────────────────────
// THE OVERRIDES
//
// PER ROLE, not one shared list: the owner and the warden both read hostelStatsProvider and
// want different figures on it, and the same provider cannot be overridden twice in one scope.
// ─────────────────────────────────────────────────────────────────────────────

List<Override> _overridesFor(UserRole role) => [
      // ── Everything every role's shell reads ───────────────────────────────────────────
      sessionProvider.overrideWithValue(NivoraSession(
        userId: 'u-1',
        role: role,
        fullName: 'Ananya Rao',
        status: 'active',
        mustChangePassword: false,
        hostelId: _hostelId,
      )),
      currentHostelIdProvider.overrideWithValue(_hostelId),
      currentPeriodMonthProvider.overrideWithValue(_period),
      myHostelsProvider.overrideWith((ref) => [_sunrise]),
      hostelProvider.overrideWith((ref, id) => _sunrise),
      // UpdateBannerHost wraps every role shell. Null means "you are on the current build",
      // which is the only honest thing for a store screenshot to say.
      latestReleaseProvider.overrideWith((ref) => null),
      noticesProvider.overrideWith2(_ShotNotices.new),
      complaintsProvider.overrideWith2(_ShotComplaints.new),
      weeklyMenuProvider.overrideWith((ref, id) => _weekMenu),

      // ── Role by role ──────────────────────────────────────────────────────────────────
      if (role == UserRole.owner) ...[
        hostelStatsProvider.overrideWith((ref, q) => _ownerStats),
        dailyFinanceProvider.overrideWith((ref, q) => _ownerFinance(q)),
        // ownerActivityProvider is left alone deliberately: it is derived from
        // complaintsProvider and noticesProvider, both of which are stubbed above, so it
        // already resolves to real rows rather than an error.
      ],

      if (role == UserRole.warden) ...[
        hostelStatsProvider.overrideWith((ref, q) => _wardenStats),
        visitorsOnSiteProvider.overrideWith((ref, id) => _onSite),
        roomOccupancyProvider.overrideWith((ref, id) => _rooms),
      ],

      if (role == UserRole.manager) ...[
        // The manager's dashboard deliberately does NOT read rpc_hostel_stats — under a
        // manager's RLS the resident-scoped counts come back zeroed. Null keeps any warmer
        // that touches it out of an error state without putting a wrong figure on screen.
        hostelStatsProvider.overrideWith((ref, q) => null),
        taskLoadProvider.overrideWith((ref, id) => const TaskLoad(open: 4, overdue: 1)),
        managerFinanceProvider.overrideWith((ref, id) => _financeWindow()),
        tasksProvider.overrideWith2(_ShotTasks.new),
        managerExpensesProvider.overrideWith2(_ShotExpenses.new),
        managerRevenuesProvider.overrideWith2(_ShotRevenues.new),
        menuDayProvider.overrideWith(() => _PinnedMenuDay(MenuDay.wed)),
      ],

      if (role == UserRole.student) ...[
        // A resident may not call rpc_hostel_stats at all; nothing on their screens asks for
        // it, and null rather than a pending future keeps a stray warmer off the spinner.
        hostelStatsProvider.overrideWith((ref, q) => null),
        myStudentProvider.overrideWith((ref) => _resident),
        myRentThisMonthProvider.overrideWith((ref) => _rentRow),
        hostelContactsProvider.overrideWith((ref) => _contacts),
        roommatesProvider.overrideWith((ref) => _roommates),
        studentFeeHistoryProvider.overrideWith2(_ShotFeeHistory.new),
      ],
    ];

/// THE WHOLE REASON THIS FILE EXISTS.
///
/// A widget test ships with a stub icon font, so every `Icon` paints as a filled box. Loading
/// the real font from the SDK cache is what turns these from debugging aids into something that
/// can go in front of a customer. The path is the Flutter SDK's own artifact cache; if a future
/// SDK moves it, this throws loudly rather than silently producing squares again.
Future<void> _loadRealFonts() async {
  final flutterRoot = File(Platform.resolvedExecutable).parent.parent.parent.path;
  final candidates = <String>[
    '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    'C:/Users/shahu/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  ];
  final icons = candidates.map(File.new).firstWhere(
        (f) => f.existsSync(),
        orElse: () => throw StateError(
          'MaterialIcons font not found. Looked in:\n  ${candidates.join('\n  ')}\n'
          'Without it every icon renders as a square and these shots are unusable.',
        ),
      );
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData())))
      .load();

  // The app's own typeface, so the screenshots carry the product's actual typography.
  for (final entry in {
    'Inter': ['google_fonts/Inter-Regular.ttf', 'google_fonts/Inter-SemiBold.ttf', 'google_fonts/Inter-Bold.ttf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    var found = false;
    for (final path in entry.value) {
      final f = File(path);
      if (!f.existsSync()) continue;
      found = true;
      loader.addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
    }
    if (found) await loader.load();
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, _Canvas canvas, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // runAsync: PNG encoding is real work on a real thread, and the fake async zone a widget test
  // runs in never lets it finish. Without this the run hangs with no output at all.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: canvas.dpr);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/store-shots').createSync(recursive: true);
    final file = File('build/store-shots/${canvas.tag}-$name.png');
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('WROTE ${file.path}  ${image.width}x${image.height}');
  });
}

Future<void> _shootRole(WidgetTester tester, _Canvas canvas, UserRole role, String name) async {
  tester.view.physicalSize = canvas.physical;
  tester.view.devicePixelRatio = canvas.dpr;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overridesFor(role),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: NivoraTheme.light(),
          home: RoleShell(role: role),
        ),
      ),
    ),
  );
  await tester.pump();
  // Long enough for every shell's tab warmer to finish firing (the warden's mounts four more
  // tabs at 150ms intervals) and for the overridden futures to have resolved into data.
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump(const Duration(milliseconds: 300));

  // Images decode on a real thread the fake clock never reaches, so an un-precached Image
  // paints as nothing at all — which is how a brand mark once vanished from a shot entirely.
  final images = find.byType(Image);
  for (var i = 0; i < images.evaluate().length; i++) {
    final widget = tester.widget<Image>(images.at(i));
    await tester.runAsync(() => precacheImage(widget.image, tester.element(images.at(i))));
  }
  await tester.pump();

  await _capture(tester, key, canvas, name);
}

void main() {
  setUpAll(_loadRealFonts);

  const roles = <UserRole, String>{
    UserRole.owner: 'owner',
    UserRole.warden: 'warden',
    UserRole.manager: 'manager',
    UserRole.student: 'resident',
  };

  for (final canvas in <_Canvas>[_phone, _tablet10]) {
    for (final entry in roles.entries) {
      testWidgets('${canvas.tag} ${entry.value}', (t) async {
        await _shootRole(t, canvas, entry.key, entry.value);
      });
    }
  }
}
