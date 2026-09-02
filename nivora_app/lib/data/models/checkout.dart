library;

import 'parse.dart';

/// AN ORDER THE SERVER OPENED, AND THE ONLY THING THE CHECKOUT SHEET IS ALLOWED TO KNOW.
///
/// ── WHY EVERY FIELD ARRIVES FROM THE SERVER ──────────────────────────────────────────────
///
/// `razorpay-order` never reads its request body — not parsed, not inspected. There is no amount
/// parameter, no student parameter and no period parameter, because a parameter is a thing an
/// attacker can choose. The amount below was derived from the caller's own identity, under their
/// own RLS, and then derived a SECOND time inside `rz_open_intent`, which refuses to write the
/// intent row if the two figures disagree.
///
/// So this class carries no setters and no arithmetic. It cannot compute a total, apply a
/// discount, or adjust for anything — every one of those would be the client having an opinion
/// about a number the server already settled. It is a receipt for a decision made elsewhere.
///
/// ── [keyId] IS PUBLISHABLE AND THE SECRET IS NOT HERE ────────────────────────────────────
///
/// `rzp_test_…` / `rzp_live_…` is designed to sit in a client; it can open a checkout sheet and
/// nothing else. Razorpay's KEY SECRET — the credential that authorises money movement — stays
/// in the Edge Function process and never appears in a response body, so it can never appear in
/// this object. If a field named anything like `secret` ever turns up on this class, something
/// has gone badly wrong upstream.
///
/// (That credential's env-var name is deliberately NOT written out anywhere under lib/:
/// scripts/release.sh greps this tree for it and refuses to ship on a hit. The grep is blunt on
/// purpose — it cannot tell code from prose, and a money guard that exempts comments is a money
/// guard with a hole in it. Keeping the name out of client source costs nothing.)
class CheckoutOrder {
  const CheckoutOrder({
    required this.orderId,
    required this.keyId,
    required this.amountPaise,
    required this.amountRupees,
    required this.currency,
    required this.periodMonth,
    required this.hostelName,
    required this.studentName,
    required this.testMode,
    required this.prefillName,
    required this.prefillEmail,
    required this.prefillContact,
  });

  /// `order_…` from Razorpay. The key the webhook later claims the payment against.
  final String orderId;

  /// The PUBLISHABLE key. See the class comment.
  final String keyId;

  /// What Razorpay charges, in paise. The sheet shows this; nothing recomputes it.
  final int amountPaise;

  /// The same figure in rupees, for prose. Display only — [amountPaise] is what is charged.
  final double amountRupees;

  final String currency;
  final String periodMonth;
  final String hostelName;
  final String studentName;

  /// True while the project is on a `rzp_test_…` key. The sheet says so out loud: a resident
  /// who is about to type a real card number deserves to know no money will move.
  final bool testMode;

  final String prefillName;
  final String prefillEmail;
  final String prefillContact;

  /// [source] names the endpoint in any [RowShapeError], so a malformed response says which
  /// function produced it rather than just which key was missing.
  static CheckoutOrder fromJson(Map<String, dynamic> row, {String source = 'razorpay-order'}) {
    final prefill = row['prefill'];
    final p = prefill is Map ? prefill.cast<String, dynamic>() : const <String, dynamic>{};
    return CheckoutOrder(
      orderId: reqString(row, source, 'order_id'),
      keyId: reqString(row, source, 'key_id'),
      amountPaise: reqInt(row, source, 'amount_paise'),
      amountRupees: reqDouble(row, source, 'amount_rupees'),
      currency: optString(row, 'currency') ?? 'INR',
      periodMonth: reqString(row, source, 'period_month'),
      hostelName: optString(row, 'hostel_name') ?? '',
      studentName: optString(row, 'student_name') ?? '',
      // Absent means "not stated", and the safe reading of an unstated test flag is LIVE — a
      // sheet that wrongly says "test mode" invites a resident to treat a real charge as a
      // rehearsal, which is the more expensive of the two mistakes.
      testMode: row['test_mode'] == true,
      prefillName: optString(p, 'name') ?? '',
      prefillEmail: optString(p, 'email') ?? '',
      prefillContact: optString(p, 'contact') ?? '',
    );
  }
}

/// HOW A CHECKOUT ENDED, from the phone's point of view only.
///
/// NONE OF THESE MOVE MONEY. The ledger is credited by `razorpay-webhook`, which Razorpay calls
/// server-to-server with a signature over the raw body. This enum is what the SHEET saw, which
/// is a different and much weaker claim: [succeeded] means "Razorpay told this handset the
/// payment went through", not "the resident has been credited". The screen that receives it
/// still has to go and look at the ledger.
enum CheckoutOutcome {
  /// Razorpay reported success to the handset. Confirmation is the webhook's job.
  succeeded,

  /// The resident closed the sheet, or the payment failed. No money moved.
  failed,

  /// The resident left for a wallet app. The outcome is genuinely unknown from here.
  externalWallet,
}
