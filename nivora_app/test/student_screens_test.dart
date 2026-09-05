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
import 'package:mobile/features/student/widgets/common.dart';

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

/// One row of public.menus, for the home screen's "today" section.
MenuEntry _meal(MenuDay day, Meal meal, String items) => MenuEntry(
      id: '${day.wire}-${meal.wire}',
      hostelId: '8fc3f95c-497a-4204-af5a-510a6c811136',
      day: day,
      meal: meal,
      items: items,
      createdAt: DateTime.utc(2026, 8, 30),
      updatedAt: DateTime.utc(2026, 8, 31, 9),
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

/// One resident's months, as a fixed page.
///
/// `holdWhileSignedIn` is off because the real one asks `sessionProvider` — which these tests
/// do not stand up — and the hold is not what any of them are about.
class _FakeHistory extends StudentFeeHistoryNotifier {
  _FakeHistory(super.studentId, this.page);
  final PagedResult<FeePayment> page;

  @override
  bool get holdWhileSignedIn => false;

  @override
  Future<PagedResult<FeePayment>> fetchPage(int _) async => page;
}

/// The same family provider, refusing. Used to prove a failed read looks like a failed read.
class _FailingComplaints extends ComplaintsNotifier {
  _FailingComplaints(super.query, this.failure);
  final AppFailure failure;

  @override
  Future<PagedResult<Complaint>> fetchPage(int page) async => throw failure;
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

  /// A read that FAILS rather than returning nothing. The two look identical to any code that
  /// branches on `provider.value == null`, and they are not the same event: "no roommates" and
  /// "we could not find out" send a resident to different places.
  AppFailure? rentFailure,
  AppFailure? roommatesFailure,
  AppFailure? complaintsFailure,
  AppFailure? menuFailure,

  /// The week's food. DEFAULTS TO A HOSTEL THAT HAS PLANNED NOTHING, which is the state the
  /// live tenant is actually in — no rows in public.menus at all — and which every test in this
  /// file that is not about the menu should be looking at, because it draws a sentence rather
  /// than an error panel and so cannot be mistaken for one.
  WeeklyMenu? menu,
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
        myRentThisMonthProvider.overrideWith((ref) async {
          if (rentFailure != null) throw rentFailure;
          return rent;
        }),
        roommatesProvider.overrideWith((ref) async {
          if (roommatesFailure != null) throw roommatesFailure;
          return _roommates;
        }),
        hostelContactsProvider.overrideWith((ref) async => _contacts),
        studentFeeHistoryProvider
            .overrideWith2((id) => _FakeHistory(id, history ?? one<FeePayment>(const []))),
        // A family override replaces every instance at once and is handed no argument, so the
        // fakes carry a stand-in key. Nothing reads it: fetchPage is overridden, and the key
        // only exists so the real notifier can build a query.
        complaintsProvider.overrideWith2(
          (_) => complaintsFailure == null
              ? _FakeComplaints(const ComplaintQuery(hostelId: 'h'), complaints)
              : _FailingComplaints(const ComplaintQuery(hostelId: 'h'), complaintsFailure),
        ),
        noticesProvider.overrideWith2((_) => _FakeNotices('h', notices)),
        weeklyMenuProvider.overrideWith((ref, hostelId) async {
          if (menuFailure != null) throw menuFailure;
          return menu ?? const WeeklyMenu.empty();
        }),
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

  testWidgets("today's food sits under the rent card, never above it", (tester) async {
    // THE OWNER'S ONE CONSTRAINT ON WHERE THIS WENT: money first, food second. Rent is why
    // this app gets opened; the menu is what gets read most often after it. Anything that
    // pushes "still to pay" off the first screen is a regression, and it is a regression a
    // screenshot review would not catch on a tall test window.
    final today = MenuDay.of(DateTime.now());
    await showScreen(
      tester,
      const StudentHomeScreen(),
      rent: partialRow,
      complaints: [_openComplaint],
      menu: WeeklyMenu([
        _meal(today, Meal.breakfast, 'Idli, sambar, coconut chutney'),
        _meal(today, Meal.dinner, 'Chapati, dal fry'),
      ]),
    );

    final rent = tester.getTopLeft(find.text('RENT · AUGUST')).dy;
    final food = tester.getTopLeft(find.text("Today's food")).dy;
    final complaints = tester.getTopLeft(find.text('Your complaints')).dy;
    expect(rent, lessThan(food), reason: 'rent must stay first on the screen');
    expect(food, lessThan(complaints), reason: 'food is asked about more often than a ticket');

    // Today's two written meals, and the two nobody has written — said as unwritten, not as
    // an empty plate.
    expect(find.text('Idli, sambar, coconut chutney'), findsOneWidget);
    expect(find.text('Chapati, dal fry'), findsOneWidget);
    expect(find.text('Not planned yet'), findsNWidgets(2));

    // And the rest of the week is one tap away rather than twenty-eight lines down the page.
    expect(find.text('WHOLE WEEK'), findsOneWidget);
  });

  testWidgets('a hostel that has planned nothing is not an error on the home screen',
      (tester) async {
    // The live tenant is in exactly this state: public.menus is empty. It is a sentence about
    // who fills the menu in, not a failed read — the two must never look the same.
    await showScreen(tester, const StudentHomeScreen(), rent: partialRow);

    expect(find.text('No menu put up yet'), findsOneWidget);
    expect(find.byType(ErrorNote), findsNothing);
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
    expect(find.text('₹6,000 per month'), findsOneWidget); // the resident's OWN rent, once
    expect(find.text('Sunil Deshmukh'), findsOneWidget); // the resident's OWN guardian, once
    expect(find.textContaining('Ishaan').evaluate().length, 1);
  });

  testWidgets('profile no longer carries the hostel contact card, and offers the account '
      'actions instead', (tester) async {
    await showScreen(tester, const StudentProfileScreen(), rent: partialRow);

    // THE CARD MOVED OFF THIS SCREEN, it was not withdrawn. st_hostel_contacts() and the
    // resident's right to read those three staff fields are unchanged — the home screen still
    // shows them, and hostelContactsProvider still backs the payment receipt. What changed is
    // that a resident's own profile is about the resident: "students don't need that section
    // in profile". This asserts the removal so it cannot drift back in unnoticed.
    expect(find.text('Priya Nair · 9876500003'), findsNothing);
    expect(find.text('Rahul Mehta · 9876500002'), findsNothing);
    expect(find.text('Your hostel'), findsNothing);

    // And the slot it left is doing something a resident actually needs. Sign-out was only
    // ever the header icon and the password change was only reachable by being forced into it.
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
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

  // ───────────────────────────────────────────────────────────────────────────
  // A FAILURE MUST LOOK LIKE A FAILURE — once, in the right place, at the right volume.
  //
  // `provider.value` is null while a read is in flight AND when it failed AND when RLS hid the
  // row. Every test below exists because some piece of this screen used to collapse two of
  // those three into one picture, and the analyzer cannot see any of it.

  testWidgets('one failed ledger read draws one error panel, not two', (tester) async {
    // Home draws the rent card and the room card from the SAME `rpc_fee_ledger` row. They were
    // two AsyncSections bound to one AsyncValue, so a single failed read stacked the identical
    // panel twice — the first thing a resident sees, visibly broken.
    await showScreen(
      tester,
      const StudentHomeScreen(),
      rentFailure: const ServerFailure('502'),
    );

    expect(find.byType(ErrorNote), findsOneWidget);
    expect(find.text('Nivora is busy'), findsOneWidget);
    // And it must not be mistaken for the "no ledger row for you this month" state, which is a
    // real and completely different answer.
    expect(find.text('No rent record yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed roommate read does not silently delete the sharing line',
      (tester) async {
    // `roommates.value?.length` swallowed this: the line just disappeared, which reads as a
    // room with nobody else in it.
    await showScreen(
      tester,
      const StudentHomeScreen(),
      rent: partialRow,
      roommatesFailure: const OfflineFailure('no route to host'),
    );

    // The room and bed came from the ledger and are unaffected.
    expect(find.text('Room 101 · Bed 3'), findsOneWidget);
    expect(
      find.text('Could not check who else is in this room. Pull down to try again.'),
      findsOneWidget,
    );
    expect(find.text('You have the room to yourself'), findsNothing);
    // One failed secondary read is not a reason to put a panel over the rent card.
    expect(find.byType(ErrorNote), findsNothing);
  });

  testWidgets('a failed complaints read leaves no count standing over it', (tester) async {
    // The heading counts what is open. A count is a claim, and there is nothing to back it up
    // when the read that produced it failed.
    await showScreen(
      tester,
      const StudentHomeScreen(),
      rent: partialRow,
      complaintsFailure: const ServerFailure('502'),
    );

    expect(find.text('Your complaints'), findsOneWidget);
    expect(find.byType(ErrorNote), findsOneWidget);
    expect(find.textContaining('still open'), findsNothing);
    // "Nothing open" is the answer for a SUCCESSFUL read that came back empty.
    expect(find.text('Nothing open'), findsNothing);
    expect(find.text('Nothing outstanding'), findsNothing);
  });

  testWidgets('a refusal is not dressed up as a retry', (tester) async {
    // 42501 from `st_my_roommates()`. Retrying cannot change an RLS decision, so the copy must
    // not send a resident back to a gesture that will refuse them again.
    await showScreen(
      tester,
      const StudentHomeScreen(),
      rent: partialRow,
      roommatesFailure: const AccessDeniedFailure('insufficient_privilege'),
    );

    expect(find.text('Who else is in this room is not available to you.'), findsOneWidget);
    expect(find.textContaining('Pull down'), findsNothing);
  });

  testWidgets('profile states one roommate failure, in one place', (tester) async {
    // Profile draws the roommate read twice over — a count on the room card and the list
    // beneath it. Only the list, which is the richer of the two, owns the failure.
    await showScreen(
      tester,
      const StudentProfileScreen(),
      rent: partialRow,
      roommatesFailure: const ServerFailure('502'),
    );

    expect(find.byType(ErrorNote), findsOneWidget);
    expect(find.text('Room 101 · Bed 3'), findsOneWidget);
    // "No roommates listed" means the read SUCCEEDED and the room is empty.
    expect(find.text('No roommates listed'), findsNothing);
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
