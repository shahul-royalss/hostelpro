import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/perf/session_keep_alive.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/shell/role_shell.dart';
import 'package:mobile/features/student/widgets/common.dart';

import 'student_test.dart' show partialRow;

/// THE PRODUCT OWNER'S COMPLAINT, AS A TEST: "the system has to load fastly when we clicks on
/// any section... it has to come active without lazy load." Concretely — once the student shell
/// has been up for a moment, tapping any tab must render that tab's data immediately, with no
/// skeleton and no spinner, because the data was fetched in the background and held warm.
///
/// This file pumps the REAL student shell (RoleShell → StudentSection → the five screens) over
/// stubbed providers whose fetches resolve after a delay, exactly like a network would. It then
/// lets the TabWarmer run, taps every tab, and asserts on ARRIVAL — one frame after the tap,
/// before any request could possibly round-trip — that the tab shows data, not placeholders.
/// Delete the warm-up, make a screen lazy again, or let a tab-backing provider lose its
/// session hold, and these tests fail: that is their whole job.
///
/// Every stub that stands in for a session-held provider calls `holdForSession` itself, so the
/// test exercises the real lifetime mechanism: a warmed-but-never-tapped tab has NO listeners
/// between the warm read completing and the first tap, and only the hold keeps its data alive
/// across that gap. The `PagedNotifier` fakes inherit the hold from the real base class.

final _me = Student(
  id: '5922bad8-faa4-42e0-b35f-73fe97b2c99d',
  hostelId: '8fc3f95c-497a-4204-af5a-510a6c811136',
  userId: 'b3a79141-cc45-4c61-9485-4c8b6f138b4e',
  fullName: 'Rohan Deshmukh',
  phone: '9000000004',
  guardianName: 'Sunil Deshmukh',
  guardianPhone: '9811100004',
  permanentAddress: '14, Malviya Nagar, Jaipur',
  idProofType: 'Aadhaar',
  dateOfJoining: DateTime(2026, 3, 7),
  monthlyFee: 6000,
  status: StudentStatus.active,
  createdAt: DateTime.utc(2026, 3, 7),
  updatedAt: DateTime.utc(2026, 8, 19),
);

final _session = NivoraSession(
  userId: _me.userId!,
  role: UserRole.student,
  fullName: _me.fullName,
  status: 'active',
  mustChangePassword: false,
  hostelId: _me.hostelId,
);

const _contacts = HostelContacts(
  hostelName: 'Sunrise Residency',
  address: '24, 5th Cross, Koramangala 6th Block, Bengaluru 560095',
  wardenName: 'Priya Nair',
  wardenPhone: '9876500003',
  managerName: 'Rahul Mehta',
  managerPhone: '9876500002',
  ownerName: 'Ananya Rao',
);

const _roommates = [
  Roommate(studentId: 'r1', fullName: 'Ishaan Verma', phone: '9000000002', bedNumber: 2),
];

final _complaint = Complaint(
  id: '2f0c0550-6ade-4730-ba9b-d1e1eaaaeff6',
  hostelId: _me.hostelId,
  studentId: _me.id,
  category: ComplaintCategory.maintenance,
  title: 'Bathroom tap leaking on 1st floor',
  description: 'The tap near room 101 leaks continuously.',
  status: ComplaintStatus.inProgress,
  createdAt: DateTime.utc(2026, 8, 10, 19, 35),
  updatedAt: DateTime.utc(2026, 8, 19, 19, 35),
);

final _notice = Notice(
  id: 'e44c70d3-b5b6-40e5-87a4-917364ffecbb',
  hostelId: _me.hostelId,
  authorUserId: 'owner',
  title: 'Water supply maintenance on Sunday',
  body: 'The overhead tank will be cleaned this Sunday between 10 am and 1 pm.',
  audience: NoticeAudience.all,
  createdAt: DateTime.utc(2026, 8, 18, 19, 35),
  updatedAt: DateTime.utc(2026, 8, 19, 19, 35),
);

/// Every fetch takes this long — the stand-in for the network round trip. Comfortably shorter
/// than the 150ms warm stagger and much longer than the single frame a tap is given, so a tab
/// that refetched on arrival could not possibly have data in time and WOULD show its skeleton.
const _lag = Duration(milliseconds: 80);

PagedResult<T> _one<T>(List<T> items) =>
    PagedResult<T>(items: items, page: 0, pageSize: 20, hasMore: false);

Future<T> _late<T>(List<String> log, String name, T value) {
  log.add(name);
  return Future.delayed(_lag, () => value);
}

class _Ledger extends FeeLedgerNotifier {
  _Ledger(super.query, this.log);
  final List<String> log;

  @override
  Future<PagedResult<FeeLedgerRow>> fetchPage(int page) =>
      _late(log, 'ledger', _one([partialRow]));
}

/// The Fees tab's payment history. Keeps the REAL hold rule — this file overrides
/// `sessionProvider` with a student session, so [PagedNotifier.build] calls holdForSession
/// exactly as it would in the app, which is the whole subject of these tests.
class _History extends StudentFeeHistoryNotifier {
  _History(super.studentId, this.log);
  final List<String> log;

  @override
  Future<PagedResult<FeePayment>> fetchPage(int page) =>
      _late(log, 'history', _one<FeePayment>(const []));
}

class _Complaints extends ComplaintsNotifier {
  _Complaints(super.query, this.log);
  final List<String> log;

  @override
  Future<PagedResult<Complaint>> fetchPage(int page) =>
      _late(log, query.openOnly ? 'complaints-open' : 'complaints-all', _one([_complaint]));
}

class _Notices extends NoticesNotifier {
  _Notices(super.hostelId, this.log);
  final List<String> log;

  @override
  Future<PagedResult<Notice>> fetchPage(int page) => _late(log, 'notices', _one([_notice]));
}

/// The full student shell over a slow fake network, every fetch appended to [log].
///
/// Typed as List<Object> and cast at the ProviderScope because Riverpod 3 does not export
/// `Override` from its public barrel.
Future<void> _pumpShell(WidgetTester tester, List<String> log) async {
  // Tall, so every section of every tab is actually built: on a phone-sized test window the
  // sections below the fold would never mount, and "no skeleton found" would be true of a
  // skeleton that simply had not been built yet.
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final overrides = <Object>[
    sessionProvider.overrideWithValue(_session),
    currentPeriodMonthProvider.overrideWithValue('2026-08'),
    // The stubs below call holdForSession exactly as the real providers do — an override
    // replaces the whole build function, hold included, so the hold has to come along.
    myStudentProvider.overrideWith((ref) {
      holdForSession(ref);
      return _late<Student?>(log, 'me', _me);
    }),
    feeLedgerProvider.overrideWith2((query) => _Ledger(query, log)),
    complaintsProvider.overrideWith2((query) => _Complaints(query, log)),
    noticesProvider.overrideWith2((hostelId) => _Notices(hostelId, log)),
    studentFeeHistoryProvider.overrideWith2((id) => _History(id, log)),
    roommatesProvider.overrideWith((ref) {
      holdForSession(ref);
      return _late(log, 'roommates', _roommates);
    }),
    hostelContactsProvider.overrideWith((ref) {
      holdForSession(ref);
      return _late<HostelContacts?>(log, 'contacts', _contacts);
    }),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: NivoraTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const RoleShell(role: UserRole.student),
      ),
    ),
  );
}

/// Advances past every fetch and every stagger interval: five warmers, 150ms apart, each
/// waiting out an 80ms fetch, all comfortably inside two simulated seconds.
Future<void> _letWarmupRun(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The assertion the product owner asked for, in widget terms.
void _expectNoPlaceholders(String tab) {
  expect(find.byType(SkeletonCard), findsNothing,
      reason: '$tab showed a skeleton on arrival — its data was not warm');
  expect(find.byType(Skeleton), findsNothing,
      reason: '$tab showed a skeleton line on arrival — its data was not warm');
  expect(find.byType(CircularProgressIndicator), findsNothing,
      reason: '$tab showed a spinner on arrival — its data was not warm');
}

/// Taps a destination on the shell's NavigationBar and pumps EXACTLY ONE frame — the frame the
/// resident sees on arrival. No time passes, so nothing that was not already fetched could
/// possibly be drawn as data.
Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pump();
}

void main() {
  testWidgets('every tab arrives with data, no skeleton, once warm-up has run',
      (tester) async {
    final log = <String>[];
    await _pumpShell(tester, log);

    // The genuinely cold first paint of Home is the ONE place a skeleton is allowed — and
    // this expectation also proves the placeholder finders actually find placeholders, so the
    // findsNothing assertions below cannot pass vacuously.
    expect(find.byType(SkeletonCard), findsWidgets,
        reason: 'the cold first paint should show the home skeleton');

    await _letWarmupRun(tester);

    // Home settled from its own reads.
    expect(find.text('Room 101 · Bed 3'), findsOneWidget);
    _expectNoPlaceholders('Home');

    // The home tab's own requests went out first and won the network: the resident row is the
    // very first fetch, and the ledger (Home's rent card) is on the wire before the first
    // warmed read. The history and the tab's complaint list are reads NOTHING on the home
    // screen makes — only the warmer starts them, so their presence IS the warm-up working.
    expect(log.first, 'me');
    expect(log, contains('history'));
    expect(log, contains('complaints-all'));
    expect(log.indexOf('ledger'), lessThan(log.indexOf('history')),
        reason: 'warm-up must not contend with what the user is looking at');

    // Now the taps. One frame each: data on arrival, or the test fails.
    await _tapTab(tester, 'Fees');
    expect(find.text('Payment history'), findsOneWidget);
    expect(find.text('Nothing recorded yet'), findsOneWidget,
        reason: 'the warmed empty history renders as its empty state, not a skeleton');
    _expectNoPlaceholders('Fees');

    await _tapTab(tester, 'Complaints');
    expect(find.text('Bathroom tap leaking on 1st floor'), findsWidgets);
    _expectNoPlaceholders('Complaints');

    await _tapTab(tester, 'Notices');
    expect(find.text('Water supply maintenance on Sunday'), findsWidgets);
    _expectNoPlaceholders('Notices');

    await _tapTab(tester, 'Profile');
    expect(find.text('My details'), findsOneWidget);
    expect(find.text('Ishaan Verma'), findsOneWidget);
    _expectNoPlaceholders('Profile');
  });

  testWidgets('revisiting a tab renders the held value instantly and does not refetch',
      (tester) async {
    final log = <String>[];
    await _pumpShell(tester, log);
    await _letWarmupRun(tester);

    await _tapTab(tester, 'Fees');
    _expectNoPlaceholders('Fees (first visit)');

    await _tapTab(tester, 'Home');
    final fetchesBeforeReturn = List.of(log);

    await _tapTab(tester, 'Fees');
    expect(find.text('Payment history'), findsOneWidget);
    _expectNoPlaceholders('Fees (revisit)');
    expect(log, fetchesBeforeReturn,
        reason: 'a revisit must render the held value, not refetch from blank');

    // And the same when the tab was never left mounted before: Notices, twice.
    await _tapTab(tester, 'Notices');
    await _tapTab(tester, 'Home');
    final beforeNoticesReturn = List.of(log);
    await _tapTab(tester, 'Notices');
    expect(find.text('Water supply maintenance on Sunday'), findsWidgets);
    _expectNoPlaceholders('Notices (revisit)');
    expect(log, beforeNoticesReturn);
  });
}
