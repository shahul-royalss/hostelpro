/// What a receipt is allowed to say, and the one row it is allowed to say it from.
///
/// ═══ THE RULE THIS FILE ENFORCES WITH A TYPE ═══
/// A receipt is a claim that money changed hands. There is no public constructor: a [Receipt]
/// can only be built by the factory below, and it RETURNS NULL when the row it was handed is
/// not evidence.
///
///   [Receipt.forFeePayment]     null unless `fee_payments.amount_paid > 0` — a row exists for
///                               the month but nothing has been received against it. That is a
///                               real state (a month opened and then corrected back to zero)
///                               and it is not a receipt.
///
/// A caller that cannot get a [Receipt] cannot open the receipt screen. "Do not render a
/// receipt the server has not confirmed" is therefore not a rule someone has to remember; it is
/// the only way the code compiles.
///
/// ═══ ONE CHANNEL, BECAUSE THERE IS ONE WAY TO PAY ═══
/// This file used to hold a second factory, `forSettledIntent`, for rent paid inside the app
/// through Razorpay — guarded on `payment_intents.credited_at` so a checkout callback could
/// never print a receipt on its own. Online payment is out of v1 (rent is handed over at the
/// warden's desk and recorded there), so that factory, the model behind it and the whole
/// client-side checkout are gone. The Edge Functions stay deployed for a later version; when
/// they are configured, the online factory comes back with its `credited_at` guard intact and
/// [ReceiptChannel] grows its second value again.
///
/// ═══ AND NO ARITHMETIC ═══
/// Every figure below is a column, or a getter on the model that owns that column
/// ([FeePayment.balance] is the model's own clamp). Nothing here adds two amounts together. A
/// receipt that computed its own total could disagree with the ledger the warden is reading,
/// and the resident holding the receipt would be the one who found out.
library;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../data/models/models.dart';

/// How the money reached the hostel.
///
/// ONE VALUE TODAY. Rent is handed over at the desk; there is no other path money can take
/// into this app. The stamp still exists as a field rather than a hard-coded string because a
/// receipt that does not say where it came from is worth less on a disputed month, and because
/// the online value returns with online payment.
enum ReceiptChannel {
  /// Cash, UPI or a bank transfer handed over at the office and recorded by staff.
  desk('PAID AT THE OFFICE');

  const ReceiptChannel(this.stamp);

  /// The words printed beside the date. Short, because it sits on a paper meta line.
  final String stamp;
}

/// One printed line. `label` on the left, `value` on the right, exactly as given.
@immutable
class ReceiptLine {
  const ReceiptLine(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;

  /// Draws heavier. Used for the one line that answers "so what is my position".
  final bool emphasis;
}

/// A receipt, ready to print. Values only — the paper decides how they look.
@immutable
class Receipt {
  const Receipt._({
    required this.reference,
    required this.referenceLabel,
    required this.amount,
    required this.amountCaption,
    required this.periodMonth,
    required this.paidAt,
    required this.channel,
    required this.facts,
    required this.amounts,
    required this.totalLabel,
    required this.totalValue,
    this.payerName,
    this.hostelName,
  });

  /// The one string that lets a warden find this payment when a ledger and a bank statement
  /// disagree. Printed as text, in full, and selectable on screen.
  final String reference;

  /// What that string IS — 'RECEIPT NO'. A bare id with no name on it is not much use to
  /// whoever is asked to look it up.
  final String referenceLabel;

  /// The headline figure, in rupees.
  final double amount;

  /// The sentence under it. Says what the figure IS, because the same number means different
  /// things on the two kinds of receipt — see the factories.
  final String amountCaption;

  /// 'YYYY-MM', as the server chose it.
  final String periodMonth;

  final DateTime paidAt;
  final ReceiptChannel channel;

  /// Non-money lines: who, for what month, by what method.
  final List<ReceiptLine> facts;

  /// Money lines. Every value here came from a column.
  final List<ReceiptLine> amounts;

  final String totalLabel;
  final String totalValue;

  /// The resident's name, when the screen that opened this knew it. Null prints nothing —
  /// a receipt with a blank name is better than one with a guessed one.
  final String? payerName;
  final String? hostelName;

  /// A receipt for money taken at the hostel office, from the `fee_payments` row that
  /// `wd_record_payment()` — or `wd_correct_payment()` — returned.
  ///
  /// NULL WHEN NOTHING HAS BEEN RECEIVED. A `fee_payments` row can exist with `amount_paid`
  /// zero; it is a month, not a payment.
  ///
  /// A REFUNDED MONTH STILL HAS A RECEIPT, and it must. The document is evidence of what
  /// happened to this month's money, and money going back is part of what happened — a receipt
  /// withheld the moment a refund landed would take away the one piece of paper the resident
  /// needs in order to ask about it. So a refund is printed as its own money line rather than
  /// allowed to suppress the document. [refunds] is this month's rows from
  /// `public.payment_refunds`, passed in by the screen that already holds them.
  ///
  /// ═══ WHY THE HEADLINE IS THE MONTH'S TOTAL, NOT "THE AMOUNT JUST HANDED OVER" ═══
  /// `wd_record_payment` UPSERTS AND ADDS: a second payment in the same month tops up
  /// `amount_paid` rather than replacing it, and the row it returns carries the new cumulative
  /// figure. That cumulative figure is the only one that exists in the database. Printing
  /// "₹2,000 received" for a top-up would mean printing a number this app was holding in a text
  /// field rather than one the ledger agrees with — so the receipt is written as a statement of
  /// the month: what was owed, what has been received, what is still to pay. All three are
  /// columns, and all three match what the resident's own rent screen shows.
  static Receipt? forFeePayment(
    FeePayment payment, {
    String? payerName,
    String? hostelName,
    List<RefundInfo> refunds = const [],
  }) {
    if (!(payment.amountPaid > 0)) return null;

    final payer = _clean(payerName);
    final received = _money(payment.amountPaid);
    final outstanding = payment.balance;

    return Receipt._(
      reference: payment.id,
      referenceLabel: 'RECEIPT NO',
      amount: payment.amountPaid,
      amountCaption: 'received for ${receiptMonth(payment.periodMonth)}',
      periodMonth: payment.periodMonth,
      // `paid_on` is a date the warden entered and the server accepted. It is null only on a
      // row created without a payment, which this factory has already refused.
      paidAt: payment.paidOn ?? payment.updatedAt,
      channel: ReceiptChannel.desk,
      payerName: payer,
      hostelName: _clean(hostelName),
      facts: [
        if (payer != null) ReceiptLine('Resident', payer),
        ReceiptLine('Rent for', receiptMonth(payment.periodMonth)),
        if (payment.mode != null) ReceiptLine('Method', payment.mode!.label),
      ],
      amounts: [
        ReceiptLine('Rent for the month', _money(payment.amountDue)),
        ReceiptLine('Received so far', received),
        // ═══ A RECEIPT THAT DOES NOT MENTION THE REFUND IS A FALSE DOCUMENT ═══
        // This paper is the thing a resident keeps, shows their parents, and produces when a
        // ledger and a bank statement disagree. Printing "received ₹8,500" for a month that
        // gave ₹2,000 back is the same failure as the fee screen flipping to unpaid in silence,
        // only harder to correct afterwards because the resident is holding it.
        //
        // ONLY SETTLED REFUNDS GO ON THE PAPER. A pending refund is an instruction, not an
        // event; a printed document that outlives the instruction would be evidence of money
        // returned that never was. The live screens say a refund is on its way — paper does
        // not, because paper cannot be corrected once it has been shared.
        //
        // A COLUMN, NOT A DEDUCTION, and one line per refund. Each is printed beside "Received
        // so far" with neither figure adjusted by the other — same rule as everywhere else in
        // this file.
        for (final r in refunds.where((r) => r.isSettled))
          ReceiptLine('Refunded', _money(r.amount)),
        // Printed even when it is zero: "still to pay ₹0" is the sentence the resident came
        // for, and leaving it off a fully paid month makes the two receipts read differently
        // for no reason.
        ReceiptLine('Still to pay', _money(outstanding), emphasis: outstanding > 0),
      ],
      // The status word is computed by a trigger (app.fee_status_compute) from amount_due and
      // amount_paid. Printing the trigger's own verdict keeps this document and every screen in
      // the app telling one story about the same month.
      totalLabel: payment.status.label.toUpperCase(),
      totalValue: received,
    );
  }

  /// The headline, formatted.
  String get amountText => _money(amount);

  /// '24 AUG 2026' — a printed document's date, which is not the app's '24 Aug 2026'.
  String get dateText => _date.format(paidAt.toLocal()).toUpperCase();

  /// The line beside the amount: when, and how it was paid.
  String get metaText => '$dateText · ${channel.stamp}';

  /// A filename stem safe on every filesystem the share sheet might hand this to.
  ///
  /// Derived from the reference so two receipts never collide, and so a resident with a folder
  /// of them can tell which is which without opening any.
  String get fileStem {
    final safe = reference.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return 'nivora-receipt-$periodMonth-${safe.isEmpty ? 'rent' : safe}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRINTED-DOCUMENT FORMATTING
//
// A receipt has its own typographic conventions — uppercase months, no relative times, a date
// that still reads correctly in six months — so it does not borrow the student screens'
// formatters. The one rule it does share is the important one: Indian digit grouping. The
// default `#,###` pattern renders one lakh twenty thousand as `120,000`, which an Indian reader
// parses as `12,00,000` and is out by a factor of ten. Same locale, same symbol, same decision
// as features/student/widgets/format.dart.
// ─────────────────────────────────────────────────────────────────────────────

final NumberFormat _whole =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final NumberFormat _exact =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final DateFormat _date = DateFormat('d MMM yyyy');

/// Money, exactly. Paise appear only when the amount has them.
String _money(num amount) => (amount % 1 == 0 ? _whole : _exact).format(amount);

/// 'YYYY-MM' -> 'August 2026'. Returns the input unchanged when it is not that shape, so a
/// surprise from the server prints as itself rather than as some other month.
String receiptMonth(String periodMonth) {
  final parts = periodMonth.split('-');
  if (parts.length != 2) return periodMonth;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return periodMonth;
  return DateFormat('MMMM yyyy').format(DateTime(year, month));
}

String? _clean(String? value) {
  final trimmed = (value ?? '').trim();
  return trimmed.isEmpty ? null : trimmed;
}
