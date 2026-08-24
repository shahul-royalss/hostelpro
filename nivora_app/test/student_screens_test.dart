import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/student/fees_screen.dart';
import 'package:mobile/features/student/home_screen.dart';
import 'package:mobile/features/student/notices_screen.dart';
import 'package:mobile/features/student/raise_complaint_sheet.dart';
import 'package:mobile/features/student/profile_screen.dart';
import 'package:mobile/features/student/student_providers.dart';

import 'student_test.dart' show partialRow, unpaidRow;

/// The whole screens, composed, with the data layer replaced at its edges.
///
/// The leaf widgets are covered in student_test.dart; this file is about the wiring between
/// them — that Home reads the rent row it thinks it does, that Profile shows a roommate's name
/// and phone and NOTHING ELSE, and that a resident with no payments sees an outstanding balance
/// and an empty history at the same time without the screen contradicting itself.
///
/// Every override below replaces a provider from lib/data/providers.dart, so nothing here
/// reaches the network and nothing depends on what a seeded database happens to contain today.

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
  Roommate(studentId: 'r2', fullName: 'Aarav Sharma', phone: '9000000001', bedNumber: 1),
];

final _openComplaint = Complaint(
  id: '2f0c0550-6ade-4730-ba9b-d1e1eaaaeff6',
  hostelId: '8fc3f95c-497a-4204-af5a-510a6c811136',
  studentId: _me.id,
  category: ComplaintCategory.maintenance,
  title: 'Bathroom tap leaking on 1st floor',
  description: 'The tap near room 101 leaks continuously and the floor stays wet.',
  status: ComplaintStatus.inProgress,
  createdAt: DateTime.utc(2026, 8, 10, 19, 35),
  updatedAt: DateTime.utc(2026, 8, 19, 19, 35),
);

final _notice = Notice(
  id: 'e44c70d3-b5b6-40e5-87a4-917364ffecbb',
  hostelId: '8fc3f95c-497a-4204-af5a-510a6c811136',
  authorUserId: 'owner',
  title: 'Water supply maintenance on Sunday',
  body: 'The overhead tank will be cleaned this Sunday between 10 am and 1 pm.',
  audience: NoticeAudience.all,
  createdAt: DateTime.utc(2026, 8, 18, 19, 35),
  updatedAt: DateTime.utc(2026, 8, 19, 19, 35),
);

PagedResult<T> one<T>(List<T> items) =>
    PagedResult<T>(items: items, page: 0, pageSize: 20, hasMore: false);

/// A paginated family provider answers from a list instead of Postgres.
class _FakeComplaints extends ComplaintsNotifier {
  _FakeComplaints(super.query, this.items);
  final List<Complaint> items;

  @override
  Future<PagedResult<Complaint>> fetchPage(int page) async => one(items);
}

class _FakeNotices extends NoticesNotifier {
  _FakeNotices(super.hostelId, this.items);
  final List<Notice> items;

  @override
  Future<PagedResult<Notice>> fetchPage(int page) async => one(items);
}

Future<void> showScreen(
  WidgetTester tester,
  Widget screen, {
  FeeLedgerRow? rent,

  /// False stands in for a staff account, or anyone else with no `students` row.
  bool resident = true,
  List<Complaint> complaints = const [],
  List<Notice> notices = const [],
  PagedResult<FeePayment>? history,
}) async {
  // A tall viewport, because these are lazily-built lists: on a 600dp test window the sections
  // below the fold are never built, and "the notice is not on screen" would look identical to
  // "the notice was never rendered". The screens themselves are designed for a phone; this is
  // about making the whole of one visible to the finder at once.
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Pinned so a test is not a different test in September.
        currentPeriodMonthProvider.overrideWithValue('2026-08'),
        myStudentProvider.overrideWith((ref) async => resident ? _me : null),
        myRentThisMonthProvider.overrideWith((ref) async => rent),
        roommatesProvider.overrideWith((ref) async => _roommates),
        hostelContactsProvider.overrideWith((ref) async => _contacts),
        studentFeeHistoryProvider
            .overrideWith((ref, id) async => history ?? one<FeePayment>(const [])),
        // A family override replaces every instance at once and is handed no argument, so the
        // fakes carry a stand-in key. Nothing reads it: fetchPage is overridden, and the key
        // only exists so the real notifier can build a query.
        complaintsProvider.overrideWith2(
            (_) => _FakeComplaints(const ComplaintQuery(hostelId: 'h'), complaints)),
        noticesProvider.overrideWith2((_) => _FakeNotices('h', notices)),
        // THE TRIPWIRE. Present on every screen test in this file, checked in tearDown.
        hostelStatsProvider.overrideWith((ref, query) {
          statsWereRead = true;
          return null;
        }),
      ],
      child: MaterialApp(
        theme: NivoraTheme.light(),
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Set by the `hostelStatsProvider` override in [showScreen]; asserted after every test.
bool statsWereRead = false;

void main() {
  setUp(() => statsWereRead = false);
  tearDown(() {
    expect(statsWereRead, isFalse,
        reason: 'A student screen asked for hostel statistics — see the note in the '
            'rpc_hostel_stats test, and in StudentHomeScreen.');
  });

  testWidgets('home leads with what is owed, then the room, then what is outstanding',
      (tester) async {
    await showScreen(
      tester,
      const StudentHomeScreen(),
      rent: partialRow,
      complaints: [_openComplaint],
      notices: [_notice],
    );

    expect(find.text('Good morning, Rohan').evaluate().length +
        find.text('Good afternoon, Rohan').evaluate().length +
        find.text('Good evening, Rohan').evaluate().length, 1);
    expect(find.text('Sunrise Residency'), findsOneWidget);

    // Rent, first and loudest.
    expect(find.text('RENT · AUGUST'), findsOneWidget);
    expect(find.text('still to pay'), findsOneWidget);

    // Room and bed, from the same ledger row.
    expect(find.text('Room 101 · Bed 3'), findsOneWidget);
    expect(find.text('Sharing with 2 other residents'), findsOneWidget);

    // What is open, and what was announced.
    expect(find.text('1 complaint still open'), findsOneWidget);
    expect(find.text('Bathroom tap leaking on 1st floor'), findsOneWidget);
    expect(find.text('Water supply maintenance on Sunday'), findsOneWidget);
  });

  testWidgets('home with nothing outstanding says so rather than showing an empty list',
      (tester) async {
    await showScreen(tester, const StudentHomeScreen(), rent: partialRow);

    expect(find.text('Nothing open'), findsOneWidget);
    expect(find.text('Nothing outstanding'), findsOneWidget);
    expect(find.text('No notices yet'), findsOneWidget);
  });

  testWidgets('no student screen reads rpc_hostel_stats', (tester) async {
    // `rpc_hostel_stats` is SECURITY INVOKER, so a student CAN call it and it does answer —
    // with occupancy, collections and subscription figures computed over only the rows RLS
    // lets them see. Verified live: as a resident it returns "3 beds, 1 resident, ₹3,000
    // collected", which is that person's own room and own rent wearing the clothes of a
    // management report. Nothing leaks, and it would still be a fabricated statistic.
    //
    // The check itself runs in tearDown for EVERY test in this file. This one exists to walk
    // all four screens past it in one go, so a new screen cannot pick up the habit unnoticed.
    for (final screen in <Widget>[
      const StudentHomeScreen(),
      const StudentFeesScreen(),
      const StudentProfileScreen(),
      const StudentNoticesScreen(),
    ]) {
      await showScreen(tester, screen, rent: partialRow, notices: [_notice]);
    }
  });

  testWidgets('a resident who has paid nothing sees a balance AND an empty history',
      (tester) async {
    await showScreen(tester, const StudentFeesScreen(), rent: unpaidRow);

    // Not a contradiction: fee_payments only gains a row when money is recorded.
    expect(find.text('₹6,200'), findsWidgets);
    expect(find.text('still to pay'), findsOneWidget);
    expect(find.text('Nothing recorded yet'), findsOneWidget);
  });

  testWidgets('the fee history lists every month with its own figures', (tester) async {
    await showScreen(
      tester,
      const StudentFeesScreen(),
      rent: partialRow,
      history: one([
        FeePayment(
          id: 'f1', hostelId: 'h', studentId: _me.id, periodMonth: '2026-08',
          amountDue: 6000, amountPaid: 3000, status: FeeStatus.partial,
          paidOn: DateTime(2026, 8, 16), mode: PaymentMode.upi,
          createdAt: DateTime.utc(2026, 8, 16), updatedAt: DateTime.utc(2026, 8, 16),
        ),
        FeePayment(
          id: 'f2', hostelId: 'h', studentId: _me.id, periodMonth: '2026-07',
          amountDue: 6000, amountPaid: 6000, status: FeeStatus.paid,
          paidOn: DateTime(2026, 7, 4), mode: PaymentMode.cash,
          createdAt: DateTime.utc(2026, 7, 4), updatedAt: DateTime.utc(2026, 7, 4),
        ),
      ]),
    );

    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('July 2026'), findsOneWidget);
    expect(find.text('Received 16 Aug 2026 · UPI'), findsOneWidget);
    expect(find.text('Received 4 Jul 2026 · Cash'), findsOneWidget);
  });

  testWidgets('profile shows a roommate name, phone and bed — and nothing more',
      (tester) async {
    await showScreen(tester, const StudentProfileScreen(), rent: partialRow);

    expect(find.text('Ishaan Verma'), findsOneWidget);
    expect(find.text('9000000002'), findsOneWidget);
    expect(find.text('Bed 2'), findsOneWidget);

    // Hard rule §4.8: a resident may see three fields about another resident. The roommate
    // rows must not have grown a rent figure, a guardian or a tap into a fuller profile.
    expect(find.text('₹6,000 a month'), findsOneWidget); // the resident's OWN rent, once
    expect(find.text('Sunil Deshmukh'), findsOneWidget); // the resident's OWN guardian, once
    expect(find.textContaining('Ishaan').evaluate().length, 1);
  });

  testWidgets('profile carries the contact card students cannot get from a join',
      (tester) async {
    await showScreen(tester, const StudentProfileScreen(), rent: partialRow);

    expect(find.text('Priya Nair · 9876500003'), findsOneWidget);
    expect(find.text('Rahul Mehta · 9876500002'), findsOneWidget);
    expect(find.text('Ananya Rao'), findsOneWidget);
  });

  testWidgets('the noticeboard renders the notices RLS returned', (tester) async {
    await showScreen(tester, const StudentNoticesScreen(), notices: [_notice]);

    expect(find.text('Water supply maintenance on Sunday'), findsOneWidget);
    expect(
      find.textContaining('The overhead tank will be cleaned'),
      findsOneWidget,
    );
  });

  testWidgets('an empty noticeboard says what would appear there', (tester) async {
    await showScreen(tester, const StudentNoticesScreen());
    expect(find.text('No notices yet'), findsOneWidget);
  });

  testWidgets('the complaint form refuses an empty submission before it reaches the server',
      (tester) async {
    // Client-side validation here is COURTESY, not control: the insert policy decides whether
    // the row may exist at all. What this proves is that a resident is told which field is
    // wrong, in the same words the web app uses, without a round trip to find out.
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: NivoraTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showRaiseComplaintSheet(context, me: _me),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Raise a complaint'), findsOneWidget);

    // Nothing chosen, nothing typed.
    await tester.tap(find.text('Send to my warden'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a category.'), findsOneWidget);

    // A category, but still no title.
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to my warden'));
    await tester.pumpAndSettle();
    expect(find.text('Give your complaint a short title'), findsOneWidget);

    // Two characters is still not a title — the same 3-character floor the web app enforces.
    await tester.enterText(find.byType(TextFormField).first, 'ab');
    await tester.tap(find.text('Send to my warden'));
    await tester.pumpAndSettle();
    expect(find.text('Give your complaint a short title'), findsOneWidget);
  });

  testWidgets('an account with no resident row is told so, not shown an error',
      (tester) async {
    // `StudentRepository.me()` returns null for anyone without a students row — a warden who
    // reaches this route, or a registration that was never finished. An exception there reads
    // like a bug in the app; a sentence reads like an answer.
    await showScreen(tester, const StudentHomeScreen(), resident: false);

    expect(find.text('No resident record for this account'), findsOneWidget);
    expect(find.textContaining('ask your warden'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
