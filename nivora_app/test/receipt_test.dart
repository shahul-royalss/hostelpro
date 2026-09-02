import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/features/payments/payments.dart';
import 'package:mobile/features/payments/receipt_printer.dart';

/// Receipts, and the single property the whole feature exists for:
///
///   NOTHING IN THIS APP CAN PRINT A RECEIPT FOR MONEY THE SERVER HAS NOT CONFIRMED.
///
/// A receipt is a claim that money changed hands, and the only claim this build can make is
/// about money handed over at the warden's desk: [Receipt.forFeePayment] returns NULL unless
/// `fee_payments.amount_paid > 0`, so a month that was opened (or corrected back to nothing)
/// has no receipt to print and no way to ask for one.
///
/// The desk has its own trap, and the first group below is about it: `wd_record_payment` UPSERTS
/// AND ADDS, so the row it returns carries the month's new cumulative total rather than the
/// amount the warden just typed. A receipt built from the form's number would disagree with the
/// resident's own rent screen; one built from the returned row cannot.
///
/// WHAT USED TO BE HERE. Half this file tested `Receipt.forSettledIntent` — the online receipt,
/// guarded on `payment_intents.credited_at` so Razorpay's success callback could never print
/// one on its own. Online payment is out of v1 and that factory is gone with the checkout, so
/// the paper, printer and share tests were re-based on the desk receipt: they were never about
/// the channel, only about the machine that draws it.
///
/// Nothing here touches a network or a device.

// ─────────────────────────────────────────────────────────────────────────────
// FIXTURES — shaped like the real wire, so a schema drift breaks a test.
// ─────────────────────────────────────────────────────────────────────────────

const _feeRowId = '9b21d7aa-4a2e-4f0e-9d4c-6c0f5b2a1e33';
const _studentId = '5922bad8-faa4-42e0-b35f-73fe97b2c99d';
const _hostelId = '8fc3f95c-497a-4204-af5a-510a6c811136';

/// One public.fee_payments row, as wd_record_payment returns it.
FeePayment _feeRow({
  required double due,
  required double paid,
  required String status,
  String? mode = 'cash',
  String? paidOn = '2026-08-24',
}) =>
    FeePayment.fromJson(<String, dynamic>{
      'id': '9b21d7aa-4a2e-4f0e-9d4c-6c0f5b2a1e33',
      'hostel_id': _hostelId,
      'student_id': _studentId,
      'period_month': '2026-08',
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

/// A settled month at the desk: ₹6,200 owed, ₹6,200 received, paid in cash on the 24th.
///
/// The paper, printer and share groups all draw THIS. They are about the machine — what it
/// shows while it is feeding, what it hands over afterwards, what happens when the share sheet
/// is dismissed — and any real receipt exercises all of it.
Receipt get _deskReceipt => Receipt.forFeePayment(
      _feeRow(due: 6200, paid: 6200, status: 'paid'),
      payerName: 'Rohan Deshmukh',
      hostelName: 'Sunrise Residency',
    )!;

// ─────────────────────────────────────────────────────────────────────────────
// FAKES
// ─────────────────────────────────────────────────────────────────────────────

final class _FakeExporter implements ReceiptExporter {
  _FakeExporter([this.result = const ReceiptShared()]);

  final ReceiptExportResult result;
  Receipt? shared;
  int calls = 0;

  @override
  Future<ReceiptExportResult> share({
    required GlobalKey paperKey,
    required Receipt receipt,
    Rect? origin,
  }) async {
    calls++;
    shared = receipt;
    return result;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HARNESSES
// ─────────────────────────────────────────────────────────────────────────────

/// Pumps the receipt screen with the export replaced.
///
/// [instant] switches the platform's "remove animations" accessibility setting on, which the
/// printer honours by skipping the feed. Used wherever a test is about the paper rather than
/// about the machine.
Future<void> _showReceiptScreen(
  WidgetTester tester,
  Receipt receipt, {
  required ReceiptExporter exporter,
  bool instant = true,
}) async {
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [receiptExporterProvider.overrideWithValue(exporter)],
      child: MaterialApp(
        theme: NivoraTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: instant),
          child: ReceiptScreen(receipt: receipt),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('a receipt can only be built from a row that is evidence', () {
    test('a month with a row but no money against it is not a receipt', () {
      // A real state, not a broken one: wd_correct_payment sets a month back to zero when a
      // payment was recorded against the wrong resident, and the row stays.
      final opened = _feeRow(due: 6200, paid: 0, status: 'unpaid', mode: null, paidOn: null);
      expect(Receipt.forFeePayment(opened), isNull);
    });

    test('a receipt exists the moment the ledger has received something', () {
      final part = Receipt.forFeePayment(_feeRow(due: 6200, paid: 2000, status: 'partial'));
      expect(part, isNotNull);
      // Dated by `paid_on` — the day the money changed hands, as the desk entered it — and not
      // by when this screen happened to be opened.
      expect(part!.paidAt, DateTime.parse('2026-08-24'));
    });

    test('there is no way to print a receipt for money paid inside the app', () {
      // The online factory went with the checkout. This is a compile-time property rather than
      // a runtime one — `Receipt` has exactly one factory and it takes a fee_payments row — and
      // the assertion that stands in for it is that every receipt this build can make is
      // stamped as desk-paid.
      expect(ReceiptChannel.values, [ReceiptChannel.desk]);
      expect(_deskReceipt.channel, ReceiptChannel.desk);
      expect(_deskReceipt.metaText, contains('PAID AT THE OFFICE'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('every figure on a receipt comes off the row', () {
    test('the desk receipt carries the row amount, month and receipt number', () {
      final receipt = _deskReceipt;

      expect(receipt.amountText, '₹6,200');
      expect(receipt.periodMonth, '2026-08');
      // The fee_payments PRIMARY KEY. It is the one string that lets a warden find this
      // payment when a ledger and a cash box disagree.
      expect(receipt.reference, _feeRowId);
      expect(receipt.referenceLabel, 'RECEIPT NO');
      expect(receipt.channel, ReceiptChannel.desk);
      expect(receipt.metaText, contains('PAID AT THE OFFICE'));
      expect(receipt.metaText, contains('24 AUG 2026'));
    });

    test('a part payment at the desk prints all three figures, not a verdict of its own', () {
      final receipt = Receipt.forFeePayment(
        _feeRow(due: 6200, paid: 2000, status: 'partial'),
        payerName: 'Rohan Deshmukh',
      )!;

      final labels = {for (final line in receipt.amounts) line.label: line.value};
      expect(labels['Rent for the month'], '₹6,200');
      expect(labels['Received so far'], '₹2,000');
      expect(labels['Still to pay'], '₹4,200');
      // The status word is the TRIGGER's, so this document and every screen in the app agree
      // about the same month.
      expect(receipt.totalLabel, 'PARTLY PAID');
    });

    test('a top-up prints the ledger total, never the amount just handed over', () {
      // wd_record_payment's upsert ADDS: a warden taking a second ₹2,000 gets back a row
      // saying 4,000. Printing 2,000 here would put a number on paper that the resident's own
      // rent screen contradicts.
      final afterTopUp = _feeRow(due: 6200, paid: 4000, status: 'partial');
      final receipt = Receipt.forFeePayment(afterTopUp)!;

      expect(receipt.amountText, '₹4,000');
      expect(receipt.amountCaption, 'received for August 2026');
    });

    test('a fully paid month says so, and still prints the zero balance', () {
      final receipt = Receipt.forFeePayment(_feeRow(due: 6200, paid: 6200, status: 'paid'))!;
      expect(receipt.totalLabel, 'PAID');
      final labels = {for (final line in receipt.amounts) line.label: line.value};
      expect(labels['Still to pay'], '₹0');
    });

    test('rupees are grouped the Indian way', () {
      // ₹120,000 reads as twelve lakh to an Indian eye — out by a factor of ten.
      final receipt =
          Receipt.forFeePayment(_feeRow(due: 120000, paid: 120000, status: 'paid'))!;
      expect(receipt.amountText, '₹1,20,000');
    });

    test('a name the caller did not have prints no line at all', () {
      final receipt = Receipt.forFeePayment(_feeRow(due: 6200, paid: 6200, status: 'paid'))!;
      expect(receipt.payerName, isNull);
      expect(receipt.hostelName, isNull);
      expect(receipt.facts.map((line) => line.label), isNot(contains('Resident')));
    });

    test('an empty name is treated as no name, not as a blank line', () {
      final receipt = Receipt.forFeePayment(
        _feeRow(due: 6200, paid: 6200, status: 'paid'),
        payerName: '   ',
        hostelName: '',
      )!;
      expect(receipt.payerName, isNull);
      expect(receipt.hostelName, isNull);
    });

    test('the filename is derived from the reference, and is filesystem-safe', () {
      expect(_deskReceipt.fileStem, 'nivora-receipt-2026-08-$_feeRowId');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the printed paper', () {
    testWidgets('prints the row figures, the reference and the hostel', (tester) async {
      await _showReceiptScreen(tester, _deskReceipt, exporter: _FakeExporter());

      expect(find.text('₹6,200'), findsWidgets);
      expect(find.text('SUNRISE RESIDENCY'), findsOneWidget);
      expect(find.text('RENT RECEIPT'), findsOneWidget);
      expect(find.text('Rohan Deshmukh'), findsOneWidget);
      expect(find.text('August 2026'), findsOneWidget);
      // public.payment_mode's own label, not a word this screen invented.
      expect(find.text('Cash'), findsOneWidget);
      // In full. A truncated receipt number looks usable and is not.
      expect(find.text(_feeRowId), findsOneWidget);
      expect(find.text('RECEIPT NO'), findsOneWidget);
    });

    testWidgets('the machine feeds before it offers anything, then finishes', (tester) async {
      // Animations ON: the honest sequence a resident actually sees.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [receiptExporterProvider.overrideWithValue(_FakeExporter())],
          child: MaterialApp(
            theme: NivoraTheme.light(),
            home: ReceiptScreen(receipt: _deskReceipt),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Printing your receipt'), findsOneWidget);
      expect(find.text('Share or save'), findsNothing);

      // Mid-feed: still nothing to take away.
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Share or save'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('Printing your receipt'), findsNothing);
      expect(find.text('Share or save'), findsOneWidget);
      expect(find.text('Tear off'), findsOneWidget);
    });

    testWidgets('"remove animations" skips the feed instead of making people wait',
        (tester) async {
      await _showReceiptScreen(tester, _deskReceipt, exporter: _FakeExporter());
      // One settle, no 2.5 seconds of machinery: the accessibility setting is honoured and the
      // receipt — which is the point — is there immediately.
      expect(find.text('Share or save'), findsOneWidget);
    });

    testWidgets('tearing the sheet off does not take the receipt away with it',
        (tester) async {
      await _showReceiptScreen(tester, _deskReceipt, exporter: _FakeExporter());

      await tester.tap(find.text('Tear off'));
      await tester.pumpAndSettle();

      // The prototype throws the paper off screen here. A resident who just paid rent needs
      // the opposite: the machine goes, the receipt stays.
      expect(find.text(_feeRowId), findsOneWidget);
      expect(find.text('Tear off'), findsNothing);
      expect(find.text('Share or save'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('sharing it as a file', () {
    testWidgets('hands the exporter the receipt that is on screen', (tester) async {
      final exporter = _FakeExporter();
      await _showReceiptScreen(tester, _deskReceipt, exporter: exporter);

      await tester.tap(find.text('Share or save'));
      await tester.pumpAndSettle();

      expect(exporter.calls, 1);
      expect(exporter.shared?.reference, _feeRowId);
      expect(exporter.shared?.amountText, '₹6,200');
    });

    testWidgets('a failure says what happened and what to do', (tester) async {
      final exporter = _FakeExporter(
        const ReceiptExportFailed('Nivora could not save the receipt to this phone.'),
      );
      await _showReceiptScreen(tester, _deskReceipt, exporter: exporter);

      await tester.tap(find.text('Share or save'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Nivora could not save the receipt to this phone.'), findsOneWidget);
    });

    testWidgets('closing the share sheet is not an error and is not reported as one',
        (tester) async {
      final exporter = _FakeExporter(const ReceiptShareDismissed());
      await _showReceiptScreen(tester, _deskReceipt, exporter: exporter);

      await tester.tap(find.text('Share or save'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      // And the button comes back, rather than being left spinning.
      expect(find.text('Share or save'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the printer, as a state machine', () {
    testWidgets('a half-fed receipt is never reported as complete', (tester) async {
      final phases = <PrinterPhase>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: NivoraTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReceiptPrinterStage(
                receipt: _deskReceipt,
                paperKey: GlobalKey(),
                actions: (context, phase, tear) {
                  phases.add(phase);
                  return Text(phase.name);
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(phases.first, PrinterPhase.feeding);
      expect(phases.first.isComplete, isFalse);

      await tester.pumpAndSettle();
      expect(phases.last, PrinterPhase.printed);
      expect(phases.last.isComplete, isTrue);
    });
  });
}
