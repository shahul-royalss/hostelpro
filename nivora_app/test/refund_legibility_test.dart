// A REFUND, MADE LEGIBLE TO THE THREE PEOPLE WHO HAVE TO SEE IT.
//
// The failure this file exists to prevent is not a crash. It is a resident opening the app,
// finding a month that said PAID last week now saying UNPAID, and concluding — reasonably —
// that the app has lost their money. Nothing on the screen contradicted them, because until
// now nothing on any screen knew the word "refund". The warden they then ask has the same
// screen. The owner reading "who paid" counts the month as income it is not.
//
// So there are four claims here, and they are ordered by who is hurt worst if one breaks:
//
//   RESIDENT  the rent card states BOTH figures — what is credited, and what came back — and
//             says in a sentence why the status moved. Their receipt says it too, because the
//             receipt is the copy they keep.
//   WARDEN    the ledger row says it in words, on the resident's own line, because the warden
//             is the one who gets asked in person and a changed status word is not an answer.
//   OWNER     a refunded month cannot sit in the "who paid" list looking like clean income.
//   NOBODY    ...sees a refund that the server has not sent. With no refund columns on the row
//             — which is every row in production today — every one of these surfaces draws
//             exactly nothing, and no figure is invented to fill the space.
//
// ═══ THE TONE IS MEASURED HERE, NOT CHOSEN HERE ═══
// A refund is a FACT, NOT A FAULT — nobody did anything wrong — so it may not wear the alarm
// colour, and the last group below proves it does not, in both themes, by reading the colour
// off the painted widget rather than trusting a comment. `test/theme_contrast_test.dart` owns
// the ratios; this file owns the identity.
//
// ═══ THE SHAPE THESE FIXTURES ARE COPIED FROM ═══
// `public.payment_refunds`, as db/migrations/2026-09-02-payment-refunds.sql creates it and as
// the live project now has it. A CHILD ROW PER REFUND, not a column: a month can be refunded
// twice, and a running-total column cannot be made idempotent against a webhook Razorpay may
// deliver more than once. Amounts are `amount_paise` (bigint). `status` is the three-value
// lifecycle — only `processed` has moved money, and only `processed` reduced
// `fee_payments.amount_paid` via rz_reverse_fee().
//
// That distinction is load-bearing all the way to the pixels: a `pending` refund has changed
// NOTHING on either side, so wording it as money returned would send a resident to a bank
// statement that disagrees with this app. Each surface below is checked for both.
//
// Nothing here touches a network.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/owner/owner_payments_screen.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/payments/payments.dart';
import 'package:mobile/features/student/widgets/rent.dart';
import 'package:mobile/features/warden/fees/warden_fees_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIXTURES — row shapes, so a wire-name drift breaks a test rather than a screen
// ─────────────────────────────────────────────────────────────────────────────

const _hostelId = '8fc3f95c-497a-4204-af5a-510a6c811136';
const _studentId = '5922bad8-faa4-42e0-b35f-73fe97b2c99d';
const _feeRowId = '9b21d7aa-4a2e-4f0e-9d4c-6c0f5b2a1e33';
const _period = '2026-08';

const _contacts = HostelContacts(
  hostelName: 'Sunrise Residency',
  wardenName: 'Priya Nair',
  wardenPhone: '9000000002',
);

/// One public.payment_refunds row. ₹2,000 back — 200000 paise, as the column holds it.
///
/// Deliberately a PARTIAL refund of a settled month: ₹8,500 was owed and received, ₹2,000 went
/// back, ₹6,500 stands. That is the case the whole feature is for — the one where a single
/// figure is not enough, and where the status word moves without the resident having done
/// anything.
Map<String, dynamic> _refundRow({
  String id = 'e1c4a0d2-3f5b-4a71-9c2e-8d6b0f3a17c5',
  int paise = 200000,
  String status = 'processed',
  String? processedAt = '2026-09-12T06:30:00.000Z',
  String? reversedAt = '2026-09-12T06:30:04.000Z',
  num? reversedAmount = 2000,
  String period = _period,
}) =>
    <String, dynamic>{
      'id': id,
      'student_id': _studentId,
      'period_month': period,
      'amount_paise': paise,
      'status': status,
      'razorpay_refund_id': 'rfnd_QxT7k2Lp9mA3Zc',
      'processed_at': processedAt,
      'reversed_amount': reversedAmount,
      'reversed_at': reversedAt,
      'created_at': '2026-09-12T06:29:00.000Z',
    };

/// A refund instructed but not yet moved — Razorpay's `refund.created`.
Map<String, dynamic> _pendingRefundRow() => _refundRow(
      id: 'a7f2b913-05de-4c88-b6a1-2e94c07f5d31',
      status: 'pending',
      processedAt: null,
      reversedAt: null,
      reversedAmount: null,
    );

RefundIndex _index(List<Map<String, dynamic>> rows) =>
    RefundIndex.of(rows.map(RefundInfo.fromJson));

/// This month's refunds for the resident every fixture here describes.
List<RefundInfo> _thisMonth(RefundIndex index) => index.forMonth(_studentId, _period);

/// The settled ₹2,000, as the screens receive it.
List<RefundInfo> get _settled => _thisMonth(_index([_refundRow()]));

/// The pending ₹2,000.
List<RefundInfo> get _pending => _thisMonth(_index([_pendingRefundRow()]));

Map<String, dynamic> _feeRowMap({
  required num due,
  required num paid,
  required String status,
}) =>
    <String, dynamic>{
      'id': _feeRowId,
      'hostel_id': _hostelId,
      'student_id': _studentId,
      'period_month': _period,
      'amount_due': due,
      'amount_paid': paid,
      'status': status,
      'paid_on': '2026-08-24',
      'mode': 'upi',
      'notes': null,
      'recorded_by': 'b3a79141-cc45-4c61-9485-4c8b6f138b4e',
      'created_at': '2026-08-24T09:15:00.000Z',
      'updated_at': '2026-09-12T09:15:00.000Z',
    };

FeePayment _payment({required num due, required num paid, required String status}) =>
    FeePayment.fromJson(_feeRowMap(due: due, paid: paid, status: status));

FeeLedgerRow _ledger({required num due, required num paid, required String status}) =>
    FeeLedgerRow.fromJson(<String, dynamic>{
      'student_id': _studentId,
      'full_name': 'Rohan Deshmukh',
      'phone': '9000000004',
      'photo_url': null,
      'room_number': '101',
      'bed_number': 3,
      'monthly_fee': due,
      'amount_due': due,
      'amount_paid': paid,
      'status': status,
      'paid_on': '2026-08-24',
      'mode': 'upi',
    });

RecentPayment _recent({required num due, required num paid, required String status}) =>
    RecentPayment.fromJson(<String, dynamic>{
      'id': _feeRowId,
      'student_id': _studentId,
      'full_name': 'Rohan Deshmukh',
      'room_number': '101',
      'bed_number': 3,
      'period_month': _period,
      'amount_due': due,
      'amount_paid': paid,
      'status': status,
      'paid_on': '2026-08-24',
      'mode': 'upi',
      'notes': null,
      'recorded_by': 'b3a79141-cc45-4c61-9485-4c8b6f138b4e',
      'recorded_by_name': 'Priya Nair',
      'recorded_by_role': 'warden',
      'recorded_at': '2026-09-12T09:15:00.000Z',
    });

// ─────────────────────────────────────────────────────────────────────────────
// HARNESSES
// ─────────────────────────────────────────────────────────────────────────────

/// A resident-side widget on a real Nivora theme.
///
/// The theme matters here in a way it does not in most widget tests: `context.tones` falls back
/// to the DARK semantics when the theme carries no [NivoraSemantics] extension, so a stock
/// Material theme would make the light-theme tone assertions below measure dark-theme colours
/// and prove nothing. Both themes are built for real.
Future<void> _showResident(
  WidgetTester tester,
  Widget child, {
  bool dark = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hostelContactsProvider.overrideWith((ref) async => _contacts),
      ],
      child: MaterialApp(
        theme: dark ? NivoraTheme.dark() : NivoraTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
}

/// The provider both staff screens read for refunds. Overridden with a plain index so the
/// screens are exercised through the real `.value ?? empty` path they use in production.
///
/// `List<Object>` and a `.cast()` at the call site: Riverpod 3 does not export `Override` from
/// its public barrel, so a helper that returns overrides cannot name their type.
List<Object> _refundOverrides(RefundIndex index) => [
      hostelRefundsProvider.overrideWith((ref, query) async => index),
    ];

class _FakeLedgerPage extends FeeLedgerNotifier {
  _FakeLedgerPage(super.query, this.rows);
  final List<FeeLedgerRow> rows;

  @override
  Future<PagedResult<FeeLedgerRow>> fetchPage(int page) async =>
      PagedResult<FeeLedgerRow>(items: rows, page: 0, pageSize: 20, hasMore: false);
}

class _FakeRecentPage extends RecentPaymentsNotifier {
  _FakeRecentPage(super.hostelId, this.rows);
  final List<RecentPayment> rows;

  @override
  Future<PagedResult<RecentPayment>> fetchPage(int page) async =>
      PagedResult<RecentPayment>(items: rows, page: 0, pageSize: 20, hasMore: false);
}

Future<void> _showWardenLedger(
  WidgetTester tester,
  List<FeeLedgerRow> rows, {
  bool dark = false,
  RefundIndex refunds = RefundIndex.empty,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentHostelIdProvider.overrideWithValue(_hostelId),
        currentPeriodMonthProvider.overrideWithValue(_period),
        // The summary above the list is a separate read; it has nothing to do with refunds and
        // an un-overridden provider would reach for a Supabase client that does not exist.
        hostelStatsProvider.overrideWith((ref, query) async => null),
        feeLedgerProvider.overrideWith2((q) => _FakeLedgerPage(q, rows)),
        ..._refundOverrides(refunds).cast(),
      ],
      child: MaterialApp(
        theme: dark ? NivoraTheme.dark() : NivoraTheme.light(),
        home: const Scaffold(body: WardenFeesScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _showOwnerPayments(
  WidgetTester tester,
  List<RecentPayment> rows, {
  bool dark = false,
  RefundIndex refunds = RefundIndex.empty,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeHostelIdProvider.overrideWithValue(_hostelId),
        myHostelsProvider.overrideWith((ref) async => const []),
        recentPaymentsProvider.overrideWith2((id) => _FakeRecentPage(id, rows)),
        ..._refundOverrides(refunds).cast(),
      ],
      child: MaterialApp(
        theme: dark ? NivoraTheme.dark() : NivoraTheme.light(),
        home: const Scaffold(body: OwnerPaymentsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every colour the given text is painted in, as a set.
///
/// A set because a screen may print the same words more than once, and because what the
/// assertions want to know is whether the RESOLVED tone is among them — never "the colour of
/// the first match", which picks an arbitrary widget.
Set<Color?> _paintedColoursOf(WidgetTester tester, Finder finder) =>
    tester.widgetList<Text>(finder).map((w) => w.style?.color).toSet();

/// The theme's semantic palette, reached exactly as a paint site reaches it.
NivoraSemantics _tonesAt(WidgetTester tester, Finder anyWidgetInTree) =>
    tester.element(anyWidgetInTree).tones;

/// The colour a refund is allowed to be, in the theme currently on screen.
Color _refundInk(WidgetTester tester, Finder anyWidgetInTree) =>
    _tonesAt(tester, anyWidgetInTree).resolve(NivoraColors.info);

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('the read path — what is true about money, and what is only instructed', () {
    test('paise become rupees, and nothing else is converted', () {
      final r = RefundInfo.fromJson(_refundRow(paise: 200000));
      expect(r.amount, 2000);
      // The ledger figure the server subtracted is kept, and is NOT the display figure — it is
      // null for the whole window between the money leaving and the reversal landing.
      expect(r.reversedAmount, 2000);
    });

    test('a processed refund is money that has moved; a pending one is not', () {
      expect(RefundInfo.fromJson(_refundRow()).isSettled, isTrue);
      expect(RefundInfo.fromJson(_pendingRefundRow()).isSettled, isFalse);
    });

    test('the date printed is processed_at for money, created_at for an instruction', () {
      // Never a substitute for the other: a pending refund must not present the day it was
      // requested as the day the money arrived. Those are different claims, and the second is
      // the one a resident would act on.
      expect(RefundInfo.fromJson(_refundRow()).on, DateTime.utc(2026, 9, 12, 6, 30));
      expect(RefundInfo.fromJson(_pendingRefundRow()).on, DateTime.utc(2026, 9, 12, 6, 29));
    });

    test('a processed refund awaiting reversal still counts as money gone', () {
      // status 'processed' with reversed_at null is the reconciliation queue: Razorpay has paid
      // the resident and the fee ledger has not caught up. The money is gone whatever the
      // ledger says, so the resident is told.
      final r = RefundInfo.fromJson(_refundRow(reversedAt: null, reversedAmount: null));
      expect(r.isSettled, isTrue);
      expect(r.reversedAt, isNull);
      expect(r.amount, 2000);
    });

    test('a FAILED refund is dropped by the index — nothing happened to explain', () {
      final index = _index([_refundRow(status: 'failed', processedAt: null, reversedAt: null)]);
      expect(_thisMonth(index), isEmpty);
      expect(index.isEmpty, isTrue);
    });

    test('the index keys on (resident, month) and answers empty for everything else', () {
      final index = _index([_refundRow()]);
      expect(_thisMonth(index), hasLength(1));
      expect(index.forMonth(_studentId, '2026-07'), isEmpty);
      expect(index.forMonth('someone-else', _period), isEmpty);
      expect(RefundIndex.empty.forMonth(_studentId, _period), isEmpty);
    });

    test('two refunds in a month are two rows, and are never added together', () {
      // The schema allows it deliberately — that is why it is a child table. Their total is a
      // figure no column holds, so this app states them and never sums them.
      final index = _index([
        _refundRow(),
        _refundRow(id: 'f0b1c2d3-4e5f-4a6b-8c9d-0e1f2a3b4c5d', paise: 50000),
      ]);
      final rows = _thisMonth(index);
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.amount), containsAll(<double>[2000, 500]));
    });

    test('settled refunds sort ahead of pending ones', () {
      // The one that explains the bill is read first.
      final rows = _thisMonth(_index([_pendingRefundRow(), _refundRow()]));
      expect(rows.first.isSettled, isTrue);
      expect(rows.last.isSettled, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('with no refunds, nothing anywhere says there were any', () {
    testWidgets('the rent card', (tester) async {
      await _showResident(
        tester,
        RentCard(periodMonth: _period, row: _ledger(due: 8500, paid: 8500, status: 'paid')),
      );
      expect(find.textContaining('refund'), findsNothing);
      expect(find.textContaining('Refund'), findsNothing);
      expect(find.byType(RefundNote), findsNothing);
    });

    testWidgets("the resident's history row", (tester) async {
      await _showResident(
        tester,
        FeePaymentTile(payment: _payment(due: 8500, paid: 8500, status: 'paid')),
      );
      expect(find.textContaining('refund'), findsNothing);
      expect(find.textContaining('Refund'), findsNothing);
    });

    test('the receipt', () {
      final receipt = Receipt.forFeePayment(_payment(due: 8500, paid: 8500, status: 'paid'))!;
      expect(receipt.amounts.map((l) => l.label), isNot(contains('Refunded')));
    });

    testWidgets("the warden's ledger", (tester) async {
      await _showWardenLedger(tester, [_ledger(due: 8500, paid: 8500, status: 'paid')]);
      expect(find.textContaining('refund'), findsNothing);
    });

    testWidgets("the owner's list", (tester) async {
      await _showOwnerPayments(tester, [_recent(due: 8500, paid: 8500, status: 'paid')]);
      expect(find.textContaining('refund'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('THE RESIDENT — the bill did not silently lose their money', () {
    testWidgets('both figures are on the card, and neither is the other subtracted',
        (tester) async {
      await _showResident(
        tester,
        RentCard(
          periodMonth: _period,
          row: _ledger(due: 8500, paid: 6500, status: 'partial'),
          refunds: _settled,
        ),
      );

      // What is credited, and what came back. Two columns, printed verbatim.
      expect(find.text('Received so far'), findsOneWidget);
      expect(find.text('₹6,500'), findsWidgets);
      expect(find.text('Refunded to you'), findsOneWidget);
      expect(find.text('₹2,000'), findsWidgets);
      // The third figure on the card is amount_due, which is what it says it is.
      expect(find.text('Rent for the month'), findsOneWidget);
    });

    testWidgets('the status word is explained, not just changed', (tester) async {
      await _showResident(
        tester,
        RentCard(
          periodMonth: _period,
          row: _ledger(due: 8500, paid: 6500, status: 'partial'),
          refunds: _settled,
        ),
      );

      expect(find.byType(RefundNote), findsOneWidget);
      expect(find.text('₹2,000 refunded on 12 Sep 2026'), findsOneWidget);
      expect(find.textContaining('₹2,000 still to pay'), findsOneWidget);
      expect(find.textContaining('Nothing has gone missing'), findsOneWidget);
    });

    testWidgets('a PENDING refund is never worded as money returned', (tester) async {
      // The failure this guards: a resident reads "refunded", checks their bank, finds nothing,
      // and now distrusts the app about the one subject it must be trusted on. Nothing has
      // moved on either side yet, so the bill is unchanged and the panel says so.
      await _showResident(
        tester,
        RentCard(
          periodMonth: _period,
          row: _ledger(due: 8500, paid: 8500, status: 'paid'),
          refunds: _pending,
        ),
      );

      expect(find.text('₹2,000 refund requested 12 Sep 2026'), findsOneWidget);
      expect(find.textContaining('Nothing has changed on this month yet'), findsOneWidget);
      // And no money line: there is no money to line up against yet.
      expect(find.text('Refunded to you'), findsNothing);
      expect(find.textContaining('went back to you'), findsNothing);
    });

    testWidgets('a refund that left the month settled says THAT instead', (tester) async {
      // An overpayment handed back. The hero still reads "paid in full", so a panel insisting
      // the month now owes something would be the card disagreeing with itself.
      await _showResident(
        tester,
        RentCard(
          periodMonth: _period,
          row: _ledger(due: 6500, paid: 6500, status: 'paid'),
          refunds: _settled,
        ),
      );

      expect(find.text('paid in full'), findsOneWidget);
      expect(find.textContaining('This month is still settled'), findsOneWidget);
      expect(find.textContaining('still to pay'), findsNothing);
    });

    testWidgets('two refunds are two lines, never one total', (tester) async {
      final rows = _thisMonth(_index([
        _refundRow(),
        _refundRow(id: 'f0b1c2d3-4e5f-4a6b-8c9d-0e1f2a3b4c5d', paise: 50000),
      ]));
      // ₹9,000 due, ₹6,000 in — so the balance is ₹3,000 and the SUM of the two refunds
      // (₹2,500) collides with nothing the ledger legitimately prints. That is the point of
      // the last assertion: if ₹2,500 ever appears here it was computed, not read.
      await _showResident(
        tester,
        RentCard(
          periodMonth: _period,
          row: _ledger(due: 9000, paid: 6000, status: 'partial'),
          refunds: rows,
        ),
      );

      expect(find.text('Refunded to you'), findsNWidgets(2));
      expect(find.text('₹2,000'), findsWidgets);
      expect(find.text('₹500'), findsWidgets);
      expect(find.text('₹2,500'), findsNothing);
    });

    testWidgets('a screen reader hears it, in the same order as a reader sees it',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _showResident(
        tester,
        RentCard(
          periodMonth: _period,
          row: _ledger(due: 8500, paid: 6500, status: 'partial'),
          refunds: _settled,
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'still to pay.*₹2,000 was refunded to you')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the history row carries it too', (tester) async {
      await _showResident(
        tester,
        FeePaymentTile(
          payment: _payment(due: 8500, paid: 6500, status: 'partial'),
          refunds: _settled,
        ),
      );
      expect(find.text('₹2,000 refunded 12 Sep 2026'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group("THE RESIDENT'S RECEIPT — the copy they keep is not a false document", () {
    test('a settled refund is a money line on the paper', () {
      final receipt = Receipt.forFeePayment(
        _payment(due: 8500, paid: 6500, status: 'partial'),
        refunds: _settled,
      )!;

      final lines = {for (final l in receipt.amounts) l.label: l.value};
      expect(lines['Rent for the month'], '₹8,500');
      expect(lines['Received so far'], '₹6,500');
      expect(lines['Refunded'], '₹2,000');
      // Beside "Received so far", not instead of it: a receipt that adjusted one figure by the
      // other would print a number the ledger never held.
      expect(receipt.amounts.map((l) => l.label).toList(),
          containsAllInOrder(['Received so far', 'Refunded']));
    });

    test('a PENDING refund never reaches the paper', () {
      // Paper outlives the instruction and cannot be corrected once it has been shared. The
      // live screens say a refund is on its way; a printed document does not.
      final receipt = Receipt.forFeePayment(
        _payment(due: 8500, paid: 8500, status: 'paid'),
        refunds: _pending,
      )!;
      expect(receipt.amounts.map((l) => l.label), isNot(contains('Refunded')));
    });

    test('a refunded month still HAS a receipt', () {
      // Withholding it would take away the one piece of paper the resident needs in order to
      // ask about the refund.
      expect(
        Receipt.forFeePayment(
          _payment(due: 8500, paid: 6500, status: 'partial'),
          refunds: _settled,
        ),
        isNotNull,
      );
    });

    test('a month refunded back to nothing still has no receipt', () {
      // The existing rule is untouched: `amount_paid = 0` is a month, not a payment, and a
      // refund does not turn it into one.
      expect(
        Receipt.forFeePayment(
          _payment(due: 8500, paid: 0, status: 'unpaid'),
          refunds: _settled,
        ),
        isNull,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('THE WARDEN — the row answers the question before it is asked', () {
    testWidgets('the ledger row says it in words, not just in a moved status', (tester) async {
      await _showWardenLedger(
        tester,
        [_ledger(due: 8500, paid: 6500, status: 'partial')],
        refunds: _index([_refundRow()]),
      );

      expect(find.text('₹2,000 refunded 12 Sep'), findsOneWidget);
      // The status word is still the trigger's own, and still says what it said.
      expect(find.text('Partly paid'), findsWidgets);
    });

    testWidgets('a pending refund is labelled as one at the desk too', (tester) async {
      await _showWardenLedger(
        tester,
        [_ledger(due: 8500, paid: 8500, status: 'paid')],
        refunds: _index([_pendingRefundRow()]),
      );
      expect(find.text('₹2,000 refund requested 12 Sep'), findsOneWidget);
    });

    testWidgets('a screen reader hears the refund on the row', (tester) async {
      final handle = tester.ensureSemantics();
      await _showWardenLedger(
        tester,
        [_ledger(due: 8500, paid: 6500, status: 'partial')],
        refunds: _index([_refundRow()]),
      );
      expect(find.bySemanticsLabel(RegExp(r'₹2,000 refunded')), findsWidgets);
      handle.dispose();
    });

    testWidgets('a failed refund is not put in front of the desk at all', (tester) async {
      await _showWardenLedger(
        tester,
        [_ledger(due: 8500, paid: 8500, status: 'paid')],
        refunds: _index([_refundRow(status: 'failed', processedAt: null, reversedAt: null)]),
      );
      expect(find.textContaining('refund'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('THE OWNER — a refunded month is not clean income', () {
    testWidgets('the card says so above the facts, not among them', (tester) async {
      await _showOwnerPayments(
        tester,
        [_recent(due: 8500, paid: 6500, status: 'partial')],
        refunds: _index([_refundRow()]),
      );

      expect(find.text('₹2,000 of this was refunded on 12 Sep'), findsOneWidget);
      // And the row still answers its own question — who paid, how much, who took it.
      expect(find.text('Rohan Deshmukh'), findsOneWidget);
      expect(find.text('Priya Nair (Warden)'), findsOneWidget);
    });

    testWidgets('money about to leave reads differently from money gone', (tester) async {
      await _showOwnerPayments(
        tester,
        [_recent(due: 8500, paid: 8500, status: 'paid')],
        refunds: _index([_pendingRefundRow()]),
      );
      expect(
        find.text('₹2,000 of this is being refunded — requested 12 Sep'),
        findsOneWidget,
      );
    });

    testWidgets('a screen reader hears it next to the figure it qualifies', (tester) async {
      final handle = tester.ensureSemantics();
      await _showOwnerPayments(
        tester,
        [_recent(due: 8500, paid: 6500, status: 'partial')],
        refunds: _index([_refundRow()]),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'paid ₹6,500 for August 2026, ₹2,000 refunded')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('THE TONE — a refund is a fact, not a fault', () {
    // Read off the painted widget in BOTH themes. Light mode alone would barely catch a
    // regression: several of this palette's inks are near neighbours there. On dark the
    // resolved values are far apart, so a refund repainted as an error is unambiguous.
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';

      testWidgets("the resident's note is the info tone on $theme, and not the alarm colour",
          (tester) async {
        await _showResident(
          tester,
          RentCard(
            periodMonth: _period,
            row: _ledger(due: 8500, paid: 6500, status: 'partial'),
            refunds: _settled,
          ),
          dark: dark,
        );

        final ink = _refundInk(tester, find.byType(RefundNote));
        final painted = _paintedColoursOf(tester, find.text('₹2,000 refunded on 12 Sep 2026'));
        expect(painted, contains(ink));

        // The three tones this app already spends on rent, none of which a refund may wear:
        // `error` is 'unpaid' and would accuse the resident of arrears for having been given
        // money back; `warning` is 'due / still owing' and would make a refunded month look
        // like one that needs chasing; `success` is 'paid', and money leaving the hostel is not
        // a collection.
        final tones = _tonesAt(tester, find.byType(RefundNote));
        expect(painted, isNot(contains(tones.error)));
        expect(painted, isNot(contains(tones.warning)));
        expect(painted, isNot(contains(tones.success)));
        // And never the CANONICAL value as type — the canonical tones are rated as graphics
        // only, which is why every paint site resolves first.
        expect(painted, isNot(contains(NivoraColors.info)));
      });

      testWidgets("the warden's ledger line is the info tone on $theme", (tester) async {
        await _showWardenLedger(
          tester,
          [_ledger(due: 8500, paid: 6500, status: 'partial')],
          refunds: _index([_refundRow()]),
          dark: dark,
        );

        final ink = _refundInk(tester, find.byType(WardenFeesScreen));
        final painted = _paintedColoursOf(tester, find.text('₹2,000 refunded 12 Sep'));
        expect(painted, contains(ink));
        expect(painted, isNot(contains(NivoraColors.error)));
      });

      testWidgets("the owner's strip is the info tone on $theme", (tester) async {
        await _showOwnerPayments(
          tester,
          [_recent(due: 8500, paid: 6500, status: 'partial')],
          refunds: _index([_refundRow()]),
          dark: dark,
        );

        final ink = _refundInk(tester, find.byType(OwnerPaymentsScreen));
        final painted =
            _paintedColoursOf(tester, find.text('₹2,000 of this was refunded on 12 Sep'));
        expect(painted, contains(ink));
        expect(painted, isNot(contains(NivoraColors.error)));
      });
    }
  });
}
