library;

import 'enums.dart';
import 'parse.dart';

/// Paying rent from inside the app: the order the server opened, and the row that says whether
/// the money actually landed.
///
/// THE ONE THING TO UNDERSTAND ABOUT THIS FILE. There are two records of a payment and only one
/// of them is evidence. [RentOrder] is what the phone was handed so it could open a checkout —
/// it proves an order exists, nothing more. [PaymentIntent] is a row in
/// `public.payment_intents`, written by the server, and it is the only thing that can say a
/// payment was received or credited. The Razorpay checkout's own success callback is not
/// modelled here at all, deliberately: it fires on the device, before the webhook has been
/// delivered, and treating it as proof is how an app shows a receipt for money the hostel never
/// got. See PaymentRepository.

/// public.payment_intent_status.
///
/// The labels are written for a RESIDENT, not for an operator, and they are careful about what
/// they claim. `captured` is deliberately not "Paid": Razorpay has the money at that point but
/// the rent ledger has not been credited yet, and those are different sentences to a person who
/// is about to be asked for rent again.
enum PaymentIntentStatus implements WireValue {
  created('created', 'Awaiting confirmation'),
  captured('captured', 'Payment received'),
  failed('failed', 'Payment failed'),
  expired('expired', 'Expired');

  const PaymentIntentStatus(this.wire, this.label);

  @override
  final String wire;

  @override
  final String label;

  static PaymentIntentStatus? tryParse(String? v) => wireOrNull(PaymentIntentStatus.values, v);
}

/// One row of public.payment_intents — one Razorpay ORDER and what became of it.
///
/// WRITTEN ONLY BY THE SERVER. The table has an RLS SELECT policy and no INSERT, UPDATE or
/// DELETE policy at all, plus an explicit `revoke insert, update, delete ... from anon,
/// authenticated`. This app can read its own rows and can do nothing else to them, which is
/// exactly the property that makes a row worth trusting: if the app could write it, reading it
/// would only tell us what the app already believed.
///
/// TWO TIMESTAMPS, TWO DIFFERENT FACTS.
///   `capturedAt`  Razorpay took the money. Set by rz_record_capture() from a webhook whose
///                 HMAC signature verified.
///   `creditedAt`  public.fee_payments was credited, through the warden's own
///                 wd_record_payment(). Set by rz_credit_fee() in a SEPARATE transaction.
///
/// The gap between them is real. It is usually milliseconds, but it can persist: the credit
/// runs through every guard the warden's desk runs through, and one of them (hard rule 4.4, an
/// expired subscription) can legitimately refuse. A row with `capturedAt` set and `creditedAt`
/// null is money that was taken and is not yet on the ledger. The app must say that rather than
/// rounding it to either "paid" or "failed" — see [isMoneyTaken] and [isSettled].
class PaymentIntent {
  const PaymentIntent({
    required this.id,
    required this.studentId,
    required this.periodMonth,
    required this.amountPaise,
    required this.razorpayOrderId,
    required this.status,
    required this.createdAt,
    this.razorpayPaymentId,
    this.method,
    this.failureReason,
    this.capturedAt,
    this.creditedAt,
  });

  /// `hostel_id`, `currency`, `created_by` and `updated_at` are real columns and are
  /// deliberately not read: nothing this app draws uses them, and a select list is also a list
  /// of what leaves the database.
  static const columns =
      'id, student_id, period_month, amount_paise, razorpay_order_id, '
      'razorpay_payment_id, method, status, failure_reason, captured_at, '
      'credited_at, created_at';

  final String id;
  final String studentId;

  /// 'YYYY-MM'. Chosen by the DATABASE at order time, never by the client.
  final String periodMonth;

  /// Integer minor units — the server's figure, written at order time and never updated. Money
  /// is not a float anywhere on this path.
  final int amountPaise;

  final String razorpayOrderId;

  /// Null until a verified `payment.captured` webhook claims this order. A unique index on this
  /// column makes "the same payment can never credit twice" a property of the database rather
  /// than of a code path someone could edit away.
  final String? razorpayPaymentId;

  /// 'upi' | 'card' | 'netbanking' | ... as Razorpay reported it. Display only.
  final String? method;

  final PaymentIntentStatus status;

  /// Razorpay's own words about a failure, truncated by the server to 200 characters.
  final String? failureReason;

  final DateTime? capturedAt;
  final DateTime? creditedAt;
  final DateTime createdAt;

  /// Rupees, for display. A conversion between units, not a calculation: the authoritative
  /// figure stays [amountPaise] and this is the only place it is divided.
  double get amountRupees => amountPaise / 100;

  /// Razorpay has the money. Says nothing at all about the rent ledger.
  bool get isMoneyTaken => capturedAt != null;

  /// The money was taken AND the rent ledger was credited. The only condition under which a
  /// screen may tell a resident their rent is settled.
  bool get isSettled => creditedAt != null;

  /// Still waiting on the webhook. Not a failure — most of a payment's life is spent here, for
  /// a second or two.
  bool get isPending => status == PaymentIntentStatus.created;

  factory PaymentIntent.fromJson(Map<String, dynamic> row) {
    const src = 'payment_intents';
    return PaymentIntent(
      id: reqString(row, src, 'id'),
      studentId: reqString(row, src, 'student_id'),
      periodMonth: reqString(row, src, 'period_month'),
      amountPaise: reqInt(row, src, 'amount_paise'),
      razorpayOrderId: reqString(row, src, 'razorpay_order_id'),
      razorpayPaymentId: optString(row, 'razorpay_payment_id'),
      method: optString(row, 'method'),
      status: wireOrThrow(PaymentIntentStatus.values, row['status'], src, 'status'),
      failureReason: optString(row, 'failure_reason'),
      capturedAt: optTimestamp(row, src, 'captured_at'),
      creditedAt: optTimestamp(row, src, 'credited_at'),
      createdAt: reqTimestamp(row, src, 'created_at'),
    );
  }
}

/// What the resident's own contact details are prefilled with on the Razorpay sheet.
///
/// These come back from the server, which read them from the resident's own `students` row
/// under the resident's own RLS. They are the resident's details going back to the resident's
/// phone — no one else's, and nothing the client chose.
class CheckoutPrefill {
  const CheckoutPrefill({required this.name, required this.contact, this.email});

  final String name;
  final String contact;

  /// Null when the resident has no email on file. Razorpay treats it as optional; sending an
  /// empty string instead would put a blank, invalid address on the sheet.
  final String? email;
}

/// The answer from the `razorpay-order` Edge Function.
///
/// NOT A TABLE, and not evidence of anything. It is the handful of values a native Razorpay
/// checkout needs in order to open, and every one of them was decided by the server.
///
/// WHAT IS NOT HERE, AND WHY. There is no amount the client may set. [amountPaise] is a figure
/// to DISPLAY and to hand back to Razorpay unchanged; it was computed by the Edge Function from
/// the resident's own ledger and then recomputed independently by `rz_open_intent()` inside the
/// database, which refuses to write the intent row unless the two agree. There is likewise no
/// key SECRET here: [keyId] is the publishable `rzp_test_...` / `rzp_live_...` merchant
/// identity, which is designed to sit in a client. The secret that signs orders is a Supabase
/// function secret and never leaves the server. An APK is a zip file; anything compiled into
/// one is published.
class RentOrder {
  const RentOrder({
    required this.orderId,
    required this.keyId,
    required this.amountPaise,
    required this.amountRupees,
    required this.currency,
    required this.periodMonth,
    required this.hostelName,
    required this.studentName,
    required this.testMode,
    required this.prefill,
  });

  /// `order_...`. Shape-checked by the server before it was handed over, because this string is
  /// also a predicate on an indexed column.
  final String orderId;

  /// The PUBLISHABLE key id. Read from the same environment as the secret that signed this
  /// order, so a test order can never be paid with a live key or the reverse.
  final String keyId;

  final int amountPaise;

  /// The same figure in rupees, as the server computed it. Present so the sheet never has to
  /// divide anything to draw a price.
  final double amountRupees;

  final String currency;

  /// 'YYYY-MM' — the month this order pays for, chosen by the server clock.
  final String periodMonth;

  /// The name Razorpay puts at the top of the native sheet.
  final String hostelName;

  final String studentName;

  /// True on a `rzp_test_...` key. Shown to the resident, because a checkout that will not move
  /// real money must not look like one that will.
  final bool testMode;

  final CheckoutPrefill prefill;

  factory RentOrder.fromJson(Map<String, dynamic> row) {
    const src = 'razorpay-order';
    final raw = row['prefill'];
    final prefill = raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
    final name = reqString(row, src, 'student_name');
    final email = (optString(prefill, 'email') ?? '').trim();

    return RentOrder(
      orderId: reqString(row, src, 'order_id'),
      keyId: reqString(row, src, 'key_id'),
      amountPaise: reqInt(row, src, 'amount_paise'),
      amountRupees: reqDouble(row, src, 'amount_rupees'),
      currency: reqString(row, src, 'currency'),
      periodMonth: reqString(row, src, 'period_month'),
      hostelName: reqString(row, src, 'hostel_name'),
      studentName: name,
      testMode: reqBool(row, src, 'test_mode'),
      prefill: CheckoutPrefill(
        name: optString(prefill, 'name') ?? name,
        contact: optString(prefill, 'contact') ?? '',
        email: email.isEmpty ? null : email,
      ),
    );
  }
}
