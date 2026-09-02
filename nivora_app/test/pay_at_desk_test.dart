// PAY AT THE WARDEN'S DESK — the whole loop, from the resident who is told where to pay to the
// owner who finds out who did.
//
// Rent can now be paid INSIDE the app (features/payments/pay_rent.dart) — and cash at the desk
// did not go away, because a resident with no bank app, a declined card, or notes in hand still
// walks to the office. Both routes have to be present and honest, and this file is the gate on
// that:
//
//   STUDENT   the fees screen keeps the real ledger figures, offers the checkout with the
//             ledger's own figure on it, and still says where the desk is. (The rent card's own
//             version of this is in student_test.dart; here it is the whole screen.)
//   WARDEN    a payment can be recorded, and a MISTAKE CAN BE UNDONE. wd_record_payment upserts
//             and ADDS, so before wd_correct_payment there was no way back from a mistyped
//             figure — the sheet's two modes are the difference and they must never be
//             confusable.
//   OWNER     "who paid" is answerable: resident, amount, month, and the member of staff who
//             took it.
//
// Nothing here touches a network. `feeDeskProvider` is typed by [RentDesk] and
// `recentPaymentsProvider` is a family notifier, so both are replaced at the container edge.
//
// The stock Material theme is used rather than NivoraTheme, as in warden_test.dart: NivoraTheme
// is built on google_fonts, and `context.tones` falls back to NivoraSemantics.light without it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/data/repositories/fee_repository.dart';
import 'package:mobile/features/owner/owner_payments_screen.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/student/fees_screen.dart';
import 'package:mobile/features/student/widgets/common.dart';
import 'package:mobile/features/student/widgets/rent.dart';
import 'package:mobile/features/student/student_providers.dart';
import 'package:mobile/features/warden/actions/record_payment_sheet.dart';
import 'package:mobile/features/warden/data/warden_providers.dart';

const _hostelId = '8fc3f95c-497a-4204-af5a-510a6c811136';
const _studentId = '5922bad8-faa4-42e0-b35f-73fe97b2c99d';
const _period = '2026-08';

/// `fee_payments.id` — and therefore the RECEIPT NUMBER, printed in full on the paper. The one
/// string that ties the resident's copy to the warden's when a ledger and a cash box disagree.
const _feeRowId = '9b21d7aa-4a2e-4f0e-9d4c-6c0f5b2a1e33';
const _julyRowId = 'c4f0a1de-77bb-4a51-9f2e-2b8a1c6d0e94';

const _contacts = HostelContacts(
  hostelName: 'Sunrise Residency',
  wardenName: 'Priya Nair',
  wardenPhone: '9000000002',
);

/// One public.fee_payments row, exactly as wd_record_payment / wd_correct_payment return it.
FeePayment _row({
  required double due,
  required double paid,
  required String status,
  String? mode = 'cash',
  String? paidOn = '2026-08-24',
  String id = _feeRowId,
  String period = _period,
}) =>
    FeePayment.fromJson(<String, dynamic>{
      'id': id,
      'hostel_id': _hostelId,
      'student_id': _studentId,
      'period_month': period,
      'amount_due': due,
      'amount_paid': paid,
      'status': status,
      'paid_on': paidOn,
      'mode': mode,
      'notes': null,
      'recorded_by': 'b3a79141-cc45-4c61-9485-4c8b6f138b4e',
      'created_at': '2026-08-24T09:15:00.000Z',
      'updated_at': '2026-08-24T09:15:00.000Z',
    });

/// The resident's own ledger row, as rpc_fee_ledger returns it.
FeeLedgerRow _ledger({required double due, required double paid, required String status}) =>
    FeeLedgerRow.fromJson(<String, dynamic>{
      'student_id': _studentId,
      'full_name': 'Rohan Deshmukh',
      'phone': '9000000004',
      'photo_url': null,
      'room_number': '101',
      'bed_number': 2,
      'monthly_fee': due,
      'amount_due': due,
      'amount_paid': paid,
      'status': status,
      'paid_on': paid > 0 ? '2026-08-16' : null,
      'mode': paid > 0 ? 'upi' : null,
    });

RecentPayment _payment({
  String id = 'fp-1',
  String name = 'Rohan Deshmukh',
  double due = 6200,
  double paid = 6200,
  FeeStatus status = FeeStatus.paid,
  String? recordedByName = 'Priya Nair',
  String? recordedByRole = 'warden',
}) =>
    RecentPayment(
      id: id,
      studentId: _studentId,
      fullName: name,
      roomNumber: '101',
      bedNumber: 2,
      periodMonth: _period,
      amountDue: due,
      amountPaid: paid,
      status: status,
      paidOn: DateTime(2026, 8, 24),
      mode: PaymentMode.cash,
      recordedBy: recordedByName == null ? null : 'u-w1',
      recordedByName: recordedByName,
      recordedByRole: recordedByRole,
      recordedAt: DateTime.utc(2026, 8, 24, 11, 30),
    );

// ─────────────────────────────────────────────────────────────────────────────
// FAKES
// ─────────────────────────────────────────────────────────────────────────────

/// The desk, with both writes recorded exactly as the sheet sent them.
///
/// The point of keeping both call logs is that the two RPCs mean OPPOSITE things about the same
/// field: `wd_record_payment(amount)` adds, `wd_correct_payment(amountPaid)` sets. A test that
/// only checked "a write happened" would pass while the sheet called the wrong one.
final class _FakeDesk implements RentDesk {
  final recorded = <Map<String, Object?>>[];
  final corrections = <Map<String, Object?>>[];

  /// What the server hands back. Defaults to a settled month.
  FeePayment result = _row(due: 6200, paid: 6200, status: 'paid');

  Object? failWith;

  @override
  Future<FeePayment> recordPayment({
    required String studentId,
    required String periodMonth,
    required double amount,
    required PaymentMode mode,
    DateTime? paidOn,
    String? notes,
  }) async {
    recorded.add({
      'studentId': studentId,
      'periodMonth': periodMonth,
      'amount': amount,
      'mode': mode,
      'paidOn': paidOn,
      'notes': notes,
    });
    if (failWith != null) throw failWith!;
    return result;
  }

  @override
  Future<FeePayment> correctPayment({
    required String studentId,
    required String periodMonth,
    required double amountPaid,
    PaymentMode? mode,
    DateTime? paidOn,
    String? notes,
  }) async {
    corrections.add({
      'studentId': studentId,
      'periodMonth': periodMonth,
      'amountPaid': amountPaid,
      'mode': mode,
      'paidOn': paidOn,
      'notes': notes,
    });
    if (failWith != null) throw failWith!;
    return result;
  }
}

class _FakeRecentPayments extends RecentPaymentsNotifier {
  _FakeRecentPayments(super.hostelId, this.rows, {this.hasMore = false});

  final List<RecentPayment> rows;
  final bool hasMore;

  @override
  Future<PagedResult<RecentPayment>> fetchPage(int page) async =>
      PagedResult(items: rows, page: page, pageSize: 20, hasMore: hasMore);
}

/// The resident's own months, and A RECORD OF WHOSE MONTHS WERE ASKED FOR.
///
/// [asked] is the point of the class as much as the rows are. `studentFeeHistoryProvider` is a
/// family keyed by student id, and the only thing standing between a resident and someone
/// else's receipt on the CLIENT is that the screen never asks for another key — the control
/// itself is the `fees_select` policy, which admits `student_id = app.current_student_id()`
/// (verified against the live project: under one resident's JWT the predicate is true for their
/// own row and false for the other resident's). A family override sees every key that is built,
/// so a screen that reached for a second resident's history would be caught here.
final _historyKeysAsked = <String>[];

class _FakeHistory extends StudentFeeHistoryNotifier {
  _FakeHistory(super.studentId, this.pages);

  /// One entry per page, in order. The last one is the end of the record.
  final List<List<FeePayment>> pages;
  int fetches = 0;

  /// Never reads `sessionProvider` — these tests have no auth controller behind it, and the
  /// hold is not what any of them are about.
  @override
  bool get holdWhileSignedIn => false;

  @override
  Future<PagedResult<FeePayment>> fetchPage(int page) async {
    fetches++;
    _historyKeysAsked.add(studentId);
    return PagedResult(
      items: page < pages.length ? pages[page] : const [],
      page: page,
      pageSize: 20,
      hasMore: page < pages.length - 1,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HARNESSES
// ─────────────────────────────────────────────────────────────────────────────

/// Opens the warden's real record-payment sheet over a fake desk.
///
/// [existing] is what `studentMonthFeeProvider` answers with — the row the sheet re-reads on
/// open rather than trusting whatever the screen behind it was holding.
Future<void> _openDeskSheet(
  WidgetTester tester, {
  required _FakeDesk desk,
  FeePayment? existing,
  double monthlyFee = 6200,
}) async {
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feeDeskProvider.overrideWithValue(desk),
        studentMonthFeeProvider.overrideWith((ref, key) async => existing),
        hostelContactsProvider.overrideWith((ref) async => _contacts),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showRecordPaymentSheet(
                  context,
                  studentId: _studentId,
                  studentName: 'Rohan Deshmukh',
                  monthlyFee: monthlyFee,
                  periodMonth: _period,
                ),
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
}

/// The resident's whole Fees screen, with the ledger and history replaced.
Future<void> _showFeesScreen(
  WidgetTester tester, {
  required FeeLedgerRow? rent,
  HostelContacts? contacts = _contacts,

  /// The months on the resident's record, a page at a time. Empty by default: a resident whose
  /// warden has never recorded anything, which is what every test about the desk panel wants.
  List<List<FeePayment>> history = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final me = Student(
    id: _studentId,
    hostelId: _hostelId,
    userId: 'b3a79141-cc45-4c61-9485-4c8b6f138b4e',
    fullName: 'Rohan Deshmukh',
    phone: '9000000004',
    dateOfJoining: DateTime(2026, 3, 7),
    monthlyFee: 6200,
    status: StudentStatus.active,
    createdAt: DateTime.utc(2026, 3, 7),
    updatedAt: DateTime.utc(2026, 8, 19),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentPeriodMonthProvider.overrideWithValue(_period),
        myStudentProvider.overrideWith((ref) async => me),
        myRentThisMonthProvider.overrideWith((ref) async => rent),
        hostelContactsProvider.overrideWith((ref) async => contacts),
        studentFeeHistoryProvider.overrideWith2(
          (id) => _FakeHistory(id, history.isEmpty ? const [<FeePayment>[]] : history),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: StudentFeesScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

/// The owner's Payments tab, over a fixed page of rows.
Future<void> _showOwnerPayments(WidgetTester tester, List<RecentPayment> rows,
    {bool hasMore = false}) async {
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeHostelIdProvider.overrideWithValue(_hostelId),
        // Watched by the screen for its no-PG triage even when a hostel is already resolved;
        // left un-overridden it would reach for a Supabase client that does not exist.
        myHostelsProvider.overrideWith((ref) async => const []),
        recentPaymentsProvider
            .overrideWith2((id) => _FakeRecentPayments(id, rows, hasMore: hasMore)),
      ],
      child: const MaterialApp(home: Scaffold(body: OwnerPaymentsScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('the resident can pay in the app, and is still told where the desk is', () {
    testWidgets('the fees screen keeps the real figures and points at the desk',
        (tester) async {
      await _showFeesScreen(tester, rent: _ledger(due: 6200, paid: 0, status: 'unpaid'));

      // The ledger's own columns, unchanged by any of this.
      expect(find.text('₹6,200'), findsWidgets);
      expect(find.text('UNPAID'), findsOneWidget);
      expect(find.text('still to pay'), findsOneWidget);

      // And the action, which is a sentence rather than a button.
      expect(find.text('Or pay cash at the desk'), findsOneWidget);
      expect(find.textContaining('Hand ₹6,200 to Priya Nair'), findsOneWidget);
      expect(find.textContaining('Desk: 9000000002'), findsOneWidget);

      // THE SCREEN NOW TAKES MONEY. The cream FilledButton is the app's one "do it now"
      // affordance and paying rent is what it is spent on here. The figure on it is the
      // ledger's, not one this widget computed — same source as the hero above it.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Pay ₹6,200 now'), findsOneWidget);
    });

    testWidgets('a settled month is not sent to the desk at all', (tester) async {
      await _showFeesScreen(tester, rent: _ledger(due: 6200, paid: 6200, status: 'paid'));

      expect(find.text('paid in full'), findsOneWidget);
      expect(find.text('Or pay cash at the desk'), findsNothing);
    });

    testWidgets('the panel is not dressed as an error', (tester) async {
      await _showFeesScreen(tester, rent: _ledger(due: 6200, paid: 0, status: 'unpaid'));

      // The desk panel is a second route, not a failure — so none of the vocabulary a failure
      // uses appears anywhere on the screen.
      expect(find.textContaining('Try again'), findsNothing);
      expect(find.textContaining('could not'), findsNothing);
      expect(find.textContaining('unavailable'), findsNothing);
      expect(find.textContaining('went wrong'), findsNothing);
      expect(find.byType(ErrorNote), findsNothing);
      // What it says instead: where the office is, and what happens after you go there.
      expect(find.textContaining('Hand ₹6,200 to'), findsOneWidget);
      expect(
        find.textContaining('It appears here as soon as your warden records it'),
        findsOneWidget,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // THE HALF THE OWNER ASKED FOR: the warden takes the cash, and the RESIDENT gets a receipt.
  //
  // A status word flipping to "Paid" is not a receipt. These tests are the resident's side of
  // wd_record_payment: the month's own `fee_payments` row reaches the rent card and the history
  // row, both open the printed document built from it, and the document says what the ledger
  // says — including when what the ledger says is "you still owe ₹3,000".
  group("the resident can see and open the receipt for what they handed over", () {
    setUp(_historyKeysAsked.clear);

    testWidgets('a month paid in full reads as cleared, on the card and on the paper',
        (tester) async {
      await _showFeesScreen(
        tester,
        rent: _ledger(due: 9500, paid: 9500, status: 'paid'),
        history: [
          [_row(due: 9500, paid: 9500, status: 'paid')],
        ],
      );

      // The card: settled, and nothing asking for money.
      expect(find.text('paid in full'), findsOneWidget);
      expect(find.text('PAID'), findsWidgets);
      expect(find.text('Or pay cash at the desk'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'View receipt'));
      await tester.pumpAndSettle();

      // The paper. `totalLabel` is app.fee_status_compute's own verdict, uppercased — the
      // receipt does not decide for itself whether a month is settled.
      expect(find.text('RENT RECEIPT'), findsOneWidget);
      expect(find.text('PAID'), findsWidgets);
      expect(find.text('₹9,500'), findsWidgets);
      // Printed even at zero: "still to pay ₹0" is the sentence the resident came for.
      expect(find.text('₹0'), findsOneWidget);
      expect(find.text(_feeRowId), findsOneWidget, reason: 'the receipt number, in full');
      expect(find.text('Rohan Deshmukh'), findsOneWidget);
      expect(find.text('SUNRISE RESIDENCY'), findsOneWidget);
    });

    testWidgets('a part payment is NOT cleared, and the receipt says exactly what came in',
        (tester) async {
      // The owner's own example: ₹6,500 taken against ₹9,500.
      await _showFeesScreen(
        tester,
        rent: _ledger(due: 9500, paid: 6500, status: 'partial'),
        history: [
          [_row(due: 9500, paid: 6500, status: 'partial')],
        ],
      );

      // The card refuses to call it settled, and still points at the desk for the rest.
      expect(find.text('paid in full'), findsNothing);
      expect(find.text('still to pay'), findsOneWidget);
      expect(find.text('PARTLY PAID'), findsWidgets);
      expect(find.textContaining('Hand ₹3,000 to Priya Nair'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'View receipt'));
      await tester.pumpAndSettle();

      // Three figures, all columns: owed, received, outstanding. A receipt that printed only
      // the ₹6,500 would read as a settled month to anyone holding it.
      expect(find.text('₹9,500'), findsWidgets);
      expect(find.text('₹6,500'), findsWidgets);
      expect(find.text('₹3,000'), findsWidgets);
      expect(find.text('PARTLY PAID'), findsWidgets);
      expect(find.text('PAID'), findsNothing, reason: 'a part payment never reads as cleared');
    });

    testWidgets('a past month opens its own receipt from the history row', (tester) async {
      await _showFeesScreen(
        tester,
        rent: _ledger(due: 9500, paid: 0, status: 'unpaid'),
        history: [
          [
            _row(
              due: 9500,
              paid: 9500,
              status: 'paid',
              id: _julyRowId,
              period: '2026-07',
              paidOn: '2026-07-05',
            ),
          ],
        ],
      );

      // The row says so before it is touched — a card that is merely tappable looks exactly
      // like one that is not.
      expect(find.text('July 2026'), findsOneWidget);
      expect(find.text('View receipt'), findsOneWidget);

      await tester.tap(find.byType(FeePaymentTile));
      await tester.pumpAndSettle();

      // JULY's row, not the month the screen happens to be showing.
      expect(find.text(_julyRowId), findsOneWidget);
      expect(find.text('July 2026'), findsWidgets);
      expect(find.text(_feeRowId), findsNothing);
    });

    testWidgets('a month that received nothing offers no receipt at all', (tester) async {
      // A real state: wd_correct_payment sets a month back to zero when the payment was
      // recorded against the wrong resident, and the row stays behind. It is a month, not a
      // payment, and Receipt.forFeePayment refuses to build one from it.
      await _showFeesScreen(
        tester,
        rent: _ledger(due: 9500, paid: 0, status: 'unpaid'),
        history: [
          [_row(due: 9500, paid: 0, status: 'unpaid', mode: null, paidOn: null)],
        ],
      );

      expect(find.text('August 2026'), findsWidgets, reason: 'the month is still on the record');
      expect(find.text('View receipt'), findsNothing);
      expect(
        tester.widget<OutlineCard>(find.byType(OutlineCard).first).onTap,
        isNull,
        reason: 'a row with no receipt behind it must not respond to a tap',
      );
    });

    testWidgets("a resident's screen never asks for another resident's months",
        (tester) async {
      await _showFeesScreen(
        tester,
        rent: _ledger(due: 9500, paid: 9500, status: 'paid'),
        history: [
          [_row(due: 9500, paid: 9500, status: 'paid')],
        ],
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'View receipt'));
      await tester.pumpAndSettle();

      // THE CLIENT HALF OF "you cannot open someone else's receipt". The control itself is
      // server-side — the `fees_select` policy admits `student_id = app.current_student_id()`,
      // and a receipt can only be built from a `fee_payments` row — so what this app owes is
      // simply never to ask for a key that is not the signed-in resident's own. Every id the
      // family was built with is recorded, and there is exactly one.
      expect(_historyKeysAsked, isNotEmpty);
      expect(_historyKeysAsked.toSet(), {_studentId});
    });

    testWidgets('two years of rent pages instead of being cut off at one page',
        (tester) async {
      // Fee history is permanent — no step of app.apply_retention() touches fee_payments — so
      // the client must not be the place where a record gets shortened. This screen used to
      // show one page and tell the resident to ask their warden for anything older.
      await _showFeesScreen(
        tester,
        rent: _ledger(due: 9500, paid: 9500, status: 'paid'),
        history: [
          [_row(due: 9500, paid: 9500, status: 'paid')],
          [
            _row(
              due: 9500,
              paid: 9500,
              status: 'paid',
              id: _julyRowId,
              period: '2026-07',
              paidOn: '2026-07-05',
            ),
          ],
        ],
      );

      expect(find.text('August 2026'), findsWidgets);
      expect(find.text('July 2026'), findsNothing);
      expect(find.textContaining('Ask your warden for anything older'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Show earlier months'));
      await tester.pumpAndSettle();

      // Appended under the months already on screen, not swapped for them.
      expect(find.text('August 2026'), findsWidgets);
      expect(find.text('July 2026'), findsOneWidget);
      expect(find.text('That is every month on your record.'), findsOneWidget);
      expect(find.text('Show earlier months'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the warden takes money at the desk', () {
    testWidgets('a first payment is recorded for the balance the ledger shows',
        (tester) async {
      final desk = _FakeDesk();
      await _openDeskSheet(tester, desk: desk, existing: null);

      // Opened on the SERVER's numbers: nothing recorded yet, so the whole month is due and
      // the amount field is prefilled with it.
      expect(find.text('Amount received now'), findsOneWidget);
      expect(find.widgetWithText(TextField, '6200'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();

      expect(desk.corrections, isEmpty, reason: 'a first payment is not a correction');
      expect(desk.recorded, hasLength(1));
      expect(desk.recorded.single['amount'], 6200.0);
      expect(desk.recorded.single['periodMonth'], _period);
      expect(desk.recorded.single['mode'], PaymentMode.cash);

      // The panel afterwards reads the ROW THE SERVER RETURNED, not the form.
      expect(find.text('Payment recorded'), findsOneWidget);
      expect(find.text('This month is settled in full.'), findsOneWidget);
      expect(find.text('Print a receipt'), findsOneWidget);
    });

    testWidgets('a second payment tops up: the field asks for the balance, not the total',
        (tester) async {
      final desk = _FakeDesk()..result = _row(due: 6200, paid: 6200, status: 'paid');
      await _openDeskSheet(
        tester,
        desk: desk,
        existing: _row(due: 6200, paid: 3000, status: 'partial'),
      );

      // ₹3,200 outstanding, and that is what the warden is asked for — because the RPC ADDS.
      expect(find.widgetWithText(TextField, '3200'), findsOneWidget);
      expect(find.textContaining('Added to anything already recorded'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();

      expect(desk.recorded.single['amount'], 3200.0);
      // The receipt summary prints the LEDGER's cumulative figure (₹6,200), which is not the
      // ₹3,200 that was just handed over.
      expect(find.text('₹6,200'), findsWidgets);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('a mistake at the desk can be undone', () {
    testWidgets('correcting SETS the month total and says so, rather than adding to it',
        (tester) async {
      // The mistake this exists for: ₹700 keyed as ₹7,000.
      final desk = _FakeDesk()..result = _row(due: 6200, paid: 700, status: 'partial');
      await _openDeskSheet(
        tester,
        desk: desk,
        existing: _row(due: 6200, paid: 7000, status: 'paid'),
      );

      await tester.tap(find.text('Correct what is recorded'));
      await tester.pumpAndSettle();

      // The label is the arithmetic, and the field opens on what the ledger currently says.
      expect(find.text('Total received this month'), findsOneWidget);
      expect(find.widgetWithText(TextField, '7000'), findsOneWidget);
      expect(find.textContaining('Replaces the figure on the ledger'), findsOneWidget);
      expect(find.textContaining('The ledger says ₹7,000 was received'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '7000'), '700');
      await tester.tap(find.widgetWithText(FilledButton, 'Save correction'));
      await tester.pumpAndSettle();

      // wd_correct_payment, not wd_record_payment. Sending 700 to the latter would have made
      // the ledger read ₹7,700 — the exact failure this whole path exists to prevent.
      expect(desk.recorded, isEmpty);
      expect(desk.corrections, hasLength(1));
      expect(desk.corrections.single['amountPaid'], 700.0);
      expect(desk.corrections.single['mode'], PaymentMode.cash);

      // And the panel does not claim money was taken.
      expect(find.text('Ledger corrected'), findsOneWidget);
      expect(find.text('Payment recorded'), findsNothing);
      expect(find.text('₹5,500 of this month is still outstanding.'), findsOneWidget);
    });

    testWidgets('zero undoes the month, and sends no date or method with it', (tester) async {
      // A payment recorded against the wrong resident. The month goes back to nothing, and a
      // month that received nothing was not paid on a day by a method.
      final desk = _FakeDesk()
        ..result = _row(due: 6200, paid: 0, status: 'unpaid', mode: null, paidOn: null);
      await _openDeskSheet(
        tester,
        desk: desk,
        existing: _row(due: 6200, paid: 6200, status: 'paid'),
      );

      await tester.tap(find.text('Correct what is recorded'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '6200'), '0');
      await tester.tap(find.widgetWithText(FilledButton, 'Save correction'));
      await tester.pumpAndSettle();

      expect(desk.corrections.single['amountPaid'], 0.0);
      expect(desk.corrections.single['mode'], isNull);
      expect(desk.corrections.single['paidOn'], isNull);
      expect(find.text('Ledger corrected'), findsOneWidget);
      expect(find.text('This month now shows nothing received.'), findsOneWidget);
      // Nothing was received, so there is nothing to print a receipt for.
      expect(find.text('Print a receipt'), findsNothing);
    });

    testWidgets('a month with nothing recorded is not offered a correction', (tester) async {
      // wd_correct_payment refuses it ("There is nothing recorded for that month to correct."),
      // and a button whose only possible outcome is that sentence is not a button.
      final desk = _FakeDesk();
      await _openDeskSheet(tester, desk: desk, existing: null);

      expect(find.text('Correct what is recorded'), findsNothing);
      expect(find.text('Record payment'), findsOneWidget);
    });

    testWidgets('a row at zero cannot be corrected either', (tester) async {
      final desk = _FakeDesk();
      await _openDeskSheet(
        tester,
        desk: desk,
        existing: _row(due: 6200, paid: 0, status: 'unpaid', mode: null, paidOn: null),
      );

      expect(find.text('Correct what is recorded'), findsNothing);
    });

    testWidgets('switching back to recording restores the balance, not the total',
        (tester) async {
      // The prefill is the safety of the toggle: whichever mode is on screen, the figure in
      // the field is the one that mode is about.
      final desk = _FakeDesk();
      await _openDeskSheet(
        tester,
        desk: desk,
        existing: _row(due: 6200, paid: 4000, status: 'partial'),
      );

      expect(find.widgetWithText(TextField, '2200'), findsOneWidget);

      await tester.tap(find.text('Correct what is recorded'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '4000'), findsOneWidget);

      await tester.tap(find.text('Record a payment instead'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '2200'), findsOneWidget);
      expect(find.text('Amount received now'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the owner can see who paid', () {
    testWidgets('a payment names the resident, the month, the figure and the staff member',
        (tester) async {
      await _showOwnerPayments(tester, [_payment()]);

      expect(find.text('Rohan Deshmukh'), findsOneWidget);
      expect(find.text('₹6,200'), findsOneWidget);
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('Room 101 · Bed 2'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      // The whole reason this is an RPC and not a select: `recorded_by` is a uuid, and the
      // answer an owner wants is a person.
      expect(find.text('Priya Nair (Warden)'), findsOneWidget);
      expect(find.text('24 Aug · Cash'), findsOneWidget);
    });

    testWidgets('a part payment shows what is still outstanding', (tester) async {
      await _showOwnerPayments(
        tester,
        [_payment(paid: 2000, status: FeeStatus.partial)],
      );

      expect(find.text('₹2,000'), findsOneWidget);
      expect(find.text('Partly paid'), findsOneWidget);
      expect(find.text('Still outstanding'), findsOneWidget);
      expect(find.text('₹4,200'), findsOneWidget);
    });

    testWidgets('a recorder who is no longer on the platform is said out loud', (tester) async {
      // `recorded_by` is nullable and the users row behind it can be deleted. A blank line
      // where a person belongs reads as "nobody took this money".
      await _showOwnerPayments(
        tester,
        [_payment(recordedByName: null, recordedByRole: null)],
      );

      expect(find.text('No staff account on record'), findsOneWidget);
    });

    testWidgets('two residents are two rows, newest first as the server ordered them',
        (tester) async {
      await _showOwnerPayments(tester, [
        _payment(id: 'fp-1', name: 'Rohan Deshmukh'),
        _payment(id: 'fp-2', name: 'Aarav Sharma', paid: 5000, status: FeeStatus.partial),
      ]);

      final rohan = tester.getTopLeft(find.text('Rohan Deshmukh')).dy;
      final aarav = tester.getTopLeft(find.text('Aarav Sharma')).dy;
      expect(rohan, lessThan(aarav), reason: 'the RPC ordered them; the screen does not re-sort');
    });

    testWidgets('no payments yet is an empty state, not a failure', (tester) async {
      await _showOwnerPayments(tester, const []);

      expect(find.text('No payments recorded yet'), findsOneWidget);
      expect(find.textContaining("Rent is paid at the warden's desk"), findsOneWidget);
      // An empty list is not a refusal. rpc_recent_payments RAISES for a caller who may not
      // see a hostel's money, precisely so this screen never has to guess which it was.
      expect(find.textContaining('Try again'), findsNothing);
    });

    testWidgets('older pages are asked for by tap, not by guessing', (tester) async {
      await _showOwnerPayments(tester, [_payment()], hasMore: true);
      expect(find.text('Show older payments'), findsOneWidget);
    });
  });
}
