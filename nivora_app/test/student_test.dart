import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/features/student/student_section.dart';
import 'package:mobile/features/student/complaints_screen.dart';
import 'package:mobile/features/student/fees_screen.dart';
import 'package:mobile/features/student/home_screen.dart';
import 'package:mobile/features/student/notices_screen.dart';
import 'package:mobile/features/student/profile_screen.dart';
import 'package:mobile/features/student/widgets/common.dart';
import 'package:mobile/features/student/widgets/complaint.dart';
import 'package:mobile/features/student/widgets/format.dart';
import 'package:mobile/features/student/widgets/notice.dart';
import 'package:mobile/features/student/widgets/rent.dart';

/// What the student screens PRESENT, tested without a network.
///
/// The presentational widgets take models rather than reading providers, which is what makes
/// this file possible: every case below is a real row shape taken from the live project, handed
/// straight to the widget that draws it. The three fee states and the three complaint states
/// all exist in the seeded data and all three of each are covered here — the unpaid case in
/// particular, because that is the resident who most needs the screen to be right and the one a
/// demo with everything paid would never exercise.

// ─────────────────────────────────────────────────────────────────────────────
// FIXTURES — shapes copied from real rows returned by nimxvgzscbanhtvgnjll.
// ─────────────────────────────────────────────────────────────────────────────

/// Aarav Sharma, room 101 bed 1: ₹7,000 due, ₹7,000 paid on 19 Aug by UPI.
const paidRow = FeeLedgerRow(
  studentId: 'a15b7eb8-6620-421c-acc0-f9bd05be4b29',
  fullName: 'Aarav Sharma',
  phone: '9000000001',
  roomNumber: '101',
  bedNumber: 1,
  monthlyFee: 7000,
  amountDue: 7000,
  amountPaid: 7000,
  status: FeeStatus.paid,
  paidOn: null,
  mode: PaymentMode.upi,
);

/// Rohan Deshmukh, room 101 bed 3: ₹6,000 due, ₹3,000 in.
final partialRow = FeeLedgerRow(
  studentId: '5922bad8-faa4-42e0-b35f-73fe97b2c99d',
  fullName: 'Rohan Deshmukh',
  phone: '9000000004',
  roomNumber: '101',
  bedNumber: 3,
  monthlyFee: 6000,
  amountDue: 6000,
  amountPaid: 3000,
  status: FeeStatus.partial,
  paidOn: DateTime(2026, 8, 16),
  mode: PaymentMode.upi,
);

/// Siddharth Bose, room 201 bed 2: ₹6,200 due and NOTHING recorded. Note `amountPaid` is the
/// integer 0 on the wire — the ledger coalesces a missing payment row to zero, which is exactly
/// why the parse layer widens every numeric rather than casting it.
const unpaidRow = FeeLedgerRow(
  studentId: 'b26cb239-9b73-431f-a801-ad1cd8d5ba36',
  fullName: 'Siddharth Bose',
  phone: '9000000012',
  roomNumber: '201',
  bedNumber: 2,
  monthlyFee: 6200,
  amountDue: 6200,
  amountPaid: 0,
  status: FeeStatus.unpaid,
);

Complaint complaint({
  required String title,
  ComplaintStatus status = ComplaintStatus.open,
  ComplaintCategory category = ComplaintCategory.maintenance,
  String? description,
}) =>
    Complaint(
      id: 'c-$title',
      hostelId: 'h',
      studentId: 's',
      category: category,
      title: title,
      description: description,
      status: status,
      createdAt: DateTime.utc(2026, 8, 10, 19, 35),
      updatedAt: DateTime.utc(2026, 8, 19, 19, 35),
    );

Future<void> show(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: NivoraTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('money', () {
    test('whole rupees show no paise', () {
      expect(rupees(7000), '₹7,000');
      expect(rupees(0), '₹0');
    });

    test('paise are shown when they exist', () {
      // Rounding a resident's own balance to the nearest rupee is a small lie about their
      // money, on the one screen where they check it against their bank.
      expect(rupees(6500.5), '₹6,500.50');
    });

    test('grouping is Indian, not thousands', () {
      // ₹120,000 would be read as twelve lakh by the people this app is for.
      expect(rupees(120000), '₹1,20,000');
      expect(rupees(1250000), '₹12,50,000');
    });
  });

  group('months and dates', () {
    test('a period month becomes a month name', () {
      expect(monthLabel('2026-08'), 'August 2026');
      expect(monthEyebrow('2026-08'), 'AUGUST');
    });

    test('an unexpected period month is shown as itself, not as a wrong month', () {
      expect(monthLabel('not-a-month'), 'not-a-month');
      expect(monthLabel('2026-13'), '2026-13');
      expect(monthLabel('2026'), '2026');
    });

    test('a date renders as a day', () {
      expect(dayLabel(DateTime(2026, 8, 19)), '19 Aug 2026');
    });

    test('relative time never says something happened in the future', () {
      final now = DateTime(2026, 8, 24, 12);
      // A device clock running behind the server would otherwise produce "in 3 minutes".
      expect(relativeTime(now.add(const Duration(minutes: 3)), now: now), 'just now');
      expect(relativeTime(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
      expect(relativeTime(now.subtract(const Duration(hours: 5)), now: now), '5h ago');
      expect(relativeTime(now.subtract(const Duration(days: 3)), now: now), '3d ago');
      expect(relativeTime(DateTime(2026, 8, 1), now: now), '1 Aug 2026');
    });
  });

  group('words', () {
    test('counts are pluralised', () {
      expect(countLabel(1, 'complaint'), '1 complaint');
      expect(countLabel(3, 'complaint'), '3 complaints');
      expect(countLabel(2, 'other resident'), '2 other residents');
    });

    test('a greeting falls back rather than addressing an empty string', () {
      expect(firstName('Rohan Deshmukh'), 'Rohan');
      expect(firstName('  '), 'there');
      expect(firstName(null), 'there');
    });

    test('the greeting follows the clock', () {
      expect(greetingFor(DateTime(2026, 8, 24, 9)), 'Good morning');
      expect(greetingFor(DateTime(2026, 8, 24, 13)), 'Good afternoon');
      expect(greetingFor(DateTime(2026, 8, 24, 20)), 'Good evening');
    });
  });

  group('failures tell a resident what to do', () {
    test('a retry is offered only where retrying could work', () {
      expect(errorGuidance(const OfflineFailure('x')).canRetry, isTrue);
      expect(errorGuidance(const ServerFailure('x')).canRetry, isTrue);
      // Nothing about tapping again changes an RLS refusal or a lapsed subscription.
      expect(errorGuidance(const AccessDeniedFailure('x')).canRetry, isFalse);
      expect(errorGuidance(const ReadOnlyFailure('x')).canRetry, isFalse);
    });

    test('a lapsed subscription is its own conversation, not a permission error', () {
      expect(errorGuidance(const ReadOnlyFailure('x')).title, 'Your hostel is read-only');
      expect(errorGuidance(const AccessDeniedFailure('x')).title, 'Not available to you');
    });

    test('the database wording is passed through where it was written for a user', () {
      // Every raise_exception in db/schema.sql carries a message meant for a person.
      const failure = InvalidInputFailure('That student has been checked out.');
      expect(errorGuidance(failure).next, 'That student has been checked out.');
    });

    test('anything unrecognised still produces guidance rather than a crash', () {
      expect(errorGuidance(StateError('boom')).canRetry, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('RentCard', () {
    testWidgets('an unpaid month leads with what is owed and offers to pay', (tester) async {
      var tapped = false;
      await show(
        tester,
        RentCard(periodMonth: '2026-08', row: unpaidRow, onPay: () => tapped = true),
      );

      expect(find.text('RENT · AUGUST'), findsOneWidget);
      expect(find.text('₹6,200'), findsWidgets);
      expect(find.text('still to pay'), findsOneWidget);
      expect(find.text('UNPAID'), findsOneWidget);
      expect(find.text('Received so far'), findsOneWidget);

      await tester.tap(find.text('Pay rent'));
      expect(tapped, isTrue);
    });

    testWidgets('a part payment shows the balance, not the rent', (tester) async {
      await show(tester, RentCard(periodMonth: '2026-08', row: partialRow, onPay: () {}));

      // The hero figure answers "what do I still owe", which is not "what is my rent".
      expect(find.text('₹3,000'), findsNWidgets(2)); // outstanding, and received so far
      expect(find.text('₹6,000'), findsOneWidget); // rent for the month
      expect(find.text('PARTLY PAID'), findsOneWidget);
      expect(find.textContaining('16 Aug 2026'), findsOneWidget);
      expect(find.textContaining('UPI'), findsOneWidget);
    });

    testWidgets('a paid month says so and does not offer to pay again', (tester) async {
      await show(tester, RentCard(periodMonth: '2026-08', row: paidRow, onPay: () {}));

      expect(find.text('paid in full'), findsOneWidget);
      expect(find.text('PAID'), findsOneWidget);
      expect(find.text('Pay rent'), findsNothing);
    });

    testWidgets('no ledger row says so rather than drawing zero rupees', (tester) async {
      await show(tester, const RentCard(periodMonth: '2026-08', row: null));

      expect(find.text('No rent record yet'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
    });
  });

  group('FeePaymentTile', () {
    testWidgets('shows due, paid, pending, date and method', (tester) async {
      await show(
        tester,
        FeePaymentTile(
          payment: FeePayment(
            id: 'f1',
            hostelId: 'h',
            studentId: 's',
            periodMonth: '2026-08',
            amountDue: 6000,
            amountPaid: 3000,
            status: FeeStatus.partial,
            paidOn: DateTime(2026, 8, 16),
            mode: PaymentMode.upi,
            notes: 'Balance promised by the 25th',
            createdAt: DateTime.utc(2026, 8, 16),
            updatedAt: DateTime.utc(2026, 8, 16),
          ),
        ),
      );

      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('DUE'), findsOneWidget);
      expect(find.text('PAID'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('₹6,000'), findsOneWidget);
      expect(find.text('₹3,000'), findsNWidgets(2)); // paid, and still pending
      expect(find.text('Received 16 Aug 2026 · UPI'), findsOneWidget);
      expect(find.text('Balance promised by the 25th'), findsOneWidget);
    });

    testWidgets('a row with no payment date says so instead of inventing one', (tester) async {
      await show(
        tester,
        FeePaymentTile(
          payment: FeePayment(
            id: 'f2',
            hostelId: 'h',
            studentId: 's',
            periodMonth: '2026-07',
            amountDue: 6000,
            amountPaid: 0,
            status: FeeStatus.unpaid,
            createdAt: DateTime.utc(2026, 7, 1),
            updatedAt: DateTime.utc(2026, 7, 1),
          ),
        ),
      );

      expect(find.text('No payment date recorded'), findsOneWidget);
    });
  });

  group('RoomBedCard', () {
    testWidgets('names the room and the bed', (tester) async {
      await show(tester, const RoomBedCard(roomNumber: '101', bedNumber: 3, roommates: 2));

      expect(find.text('Room 101 · Bed 3'), findsOneWidget);
      expect(find.text('Sharing with 2 other residents'), findsOneWidget);
    });

    testWidgets('an unplaced resident is told what happens next', (tester) async {
      await show(tester, const RoomBedCard(roomNumber: null, bedNumber: null));

      expect(find.text('Not assigned yet'), findsOneWidget);
      expect(find.textContaining('warden'), findsOneWidget);
    });
  });

  group('complaints', () {
    testWidgets('a tile carries the title, the category and the state', (tester) async {
      await show(
        tester,
        ComplaintTile(
          complaint: complaint(
            title: 'Bathroom tap leaking on 1st floor',
            status: ComplaintStatus.inProgress,
            description: 'The tap near room 101 leaks continuously.',
          ),
        ),
      );

      expect(find.text('Bathroom tap leaking on 1st floor'), findsOneWidget);
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.textContaining('Maintenance'), findsOneWidget);
    });

    testWidgets('the timeline shows every step the hostel took', (tester) async {
      await show(
        tester,
        ComplaintTimeline(
          events: [
            ComplaintEvent(
              id: 'e1',
              hostelId: 'h',
              complaintId: 'c',
              status: ComplaintStatus.open,
              note: 'Complaint raised',
              createdAt: DateTime.utc(2026, 8, 10, 19, 35),
            ),
            ComplaintEvent(
              id: 'e2',
              hostelId: 'h',
              complaintId: 'c',
              status: ComplaintStatus.inProgress,
              createdAt: DateTime.utc(2026, 8, 19, 19, 35),
            ),
          ],
        ),
      );

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Complaint raised'), findsOneWidget);
    });

    testWidgets('an empty timeline explains itself', (tester) async {
      await show(tester, const ComplaintTimeline(events: []));
      expect(find.text('No updates yet'), findsOneWidget);
    });
  });

  group('notices', () {
    Notice notice(NoticeAudience audience) => Notice(
          id: 'n1',
          hostelId: 'h',
          authorUserId: 'u',
          title: 'Water supply maintenance on Sunday',
          body: 'The overhead tank will be cleaned this Sunday between 10 am and 1 pm.',
          audience: audience,
          createdAt: DateTime.utc(2026, 8, 18, 19, 35),
          updatedAt: DateTime.utc(2026, 8, 18, 19, 35),
        );

    testWidgets('a notice addressed to residents is labelled as such', (tester) async {
      await show(tester, NoticeTile(notice: notice(NoticeAudience.students)));
      expect(find.text('FOR RESIDENTS'), findsOneWidget);
    });

    testWidgets('a notice to everyone carries no audience label', (tester) async {
      await show(tester, NoticeTile(notice: notice(NoticeAudience.all)));
      expect(find.text('FOR RESIDENTS'), findsNothing);
      expect(find.text('Water supply maintenance on Sunday'), findsOneWidget);
    });
  });

  group('tabs', () {
    test('the five destinations map to the five screens', () {
      expect(studentTabs.length, 5);
      expect(studentTabs.map((t) => t.label).toList(),
          ['Home', 'Fees', 'Complaints', 'Notices', 'Profile']);
      expect(studentScreenFor(0), isA<StudentHomeScreen>());
      expect(studentScreenFor(1), isA<StudentFeesScreen>());
      expect(studentScreenFor(2), isA<StudentComplaintsScreen>());
      expect(studentScreenFor(3), isA<StudentNoticesScreen>());
      expect(studentScreenFor(4), isA<StudentProfileScreen>());
    });

    test('an index the shell should never send still resolves to a screen', () {
      // The shell clamps, but a body that threw on a bad index would take the whole app down
      // for a navigation bug that is otherwise invisible.
      expect(studentScreenFor(99), isA<StudentProfileScreen>());
      expect(studentScreenFor(-1), isA<StudentProfileScreen>());
    });
  });
}
