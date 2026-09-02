library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../student/student_providers.dart';
import '../student/widgets/format.dart';

/// PAYING RENT INSIDE THE APP.
///
/// ═══ THE ONE THING TO UNDERSTAND BEFORE CHANGING ANYTHING HERE ═══
///
/// THIS FILE NEVER CREDITS ANYBODY. Not on success, not on a signature it checked, not ever.
///
/// Razorpay reports the outcome twice, over two completely different channels:
///
///   1. to THIS HANDSET, through the checkout sheet's success callback — over a connection an
///      attacker controls both ends of, on a device they own, in a process they can hook;
///   2. to THE SERVER, as a webhook signed with HMAC-SHA256 over the raw request body, using a
///      secret that exists only in Razorpay's dashboard and the Edge Function's environment.
///
/// Only (2) moves money. `razorpay-webhook` is what writes to the ledger, and it is the only
/// thing that does. What arrives here at (1) is a HINT — worth acting on, because it tells the
/// resident something is happening, and worth nothing as proof.
///
/// The consequence is the shape of [payRent] below: on success it does NOT say "paid". It says
/// "confirming", and then it goes and READS THE LEDGER until the webhook lands. The screen only
/// ever reports what the server already believes. A resident who patches this app, or replays
/// the callback, or fakes a payment id, moves the number on their own phone for as long as it
/// takes to refresh — and moves nothing at all in the database.
///
/// So: if you are ever tempted to add a write here — an `update fee_payments`, an RPC that marks
/// a period settled, anything that takes the callback's word for it — that is the bug this
/// entire file is arranged to prevent.
///
/// ═══ WHY THERE IS NO SIGNATURE CHECK ON THIS SIDE ═══
///
/// Razorpay hands the callback a `razorpay_signature` over `order_id|payment_id`. Verifying it
/// HERE would require the key secret on the phone, which is the one thing that must never
/// happen. Verifying it on the server would be honest but pointless: the webhook already
/// verified a stronger signature over the whole body, and the ledger read below is a stronger
/// check than either — it does not ask "did Razorpay say yes", it asks "has the money arrived".
///
/// ═══ RESOURCE DISCIPLINE ═══
///
/// [Razorpay] registers native platform listeners. Every instance MUST be `clear()`ed or the
/// listeners outlive the screen and a later payment fires callbacks into a dead closure. The
/// `whenComplete` in [_openSheet] is what guarantees that on every path, including throws.

/// How long to keep asking the ledger whether the webhook has landed.
///
/// Razorpay's webhook is typically delivered in under two seconds, but "typically" is doing a
/// lot of work on a hostel's 4G. Fifteen seconds is long enough that the overwhelming majority
/// of payments resolve on screen, and short enough that a resident is not held in front of a
/// spinner when delivery is genuinely delayed — the message they get at the end of it says the
/// payment is safe and will appear, which is true, because the webhook retries for hours.
const _confirmWindow = Duration(seconds: 15);

/// The gap between ledger reads while confirming. Deliberately not tighter: each poll is a
/// round trip on the same connection the payment just used.
const _pollEvery = Duration(milliseconds: 1200);

/// What [payRent] concluded, for the caller that wants to react.
enum PayRentResult {
  /// The webhook landed and the ledger moved while the resident watched.
  confirmed,

  /// Razorpay reported success, the ledger had not caught up inside [_confirmWindow]. The money
  /// is almost certainly fine; it simply is not visible yet.
  awaitingConfirmation,

  /// The sheet was dismissed or the payment failed. Nothing moved.
  notPaid,

  /// The order could not be opened at all — offline, not deployed, nothing owed.
  couldNotStart,
}

/// Open the checkout sheet for whatever this resident owes, then wait for the ledger.
///
/// Returns rather than throwing: every failure below is something the resident has already been
/// told about on screen, and a caller re-reporting it would show the same sentence twice.
Future<PayRentResult> payRent(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);

  // ── 1. Ask the server what is owed. No amount leaves this device. ──────────────────────
  final CheckoutOrder order;
  try {
    order = await ref.read(checkoutRepositoryProvider).open();
  } on AppFailure catch (failure) {
    if (context.mounted) _say(messenger, failure.message);
    return PayRentResult.couldNotStart;
  }

  if (!context.mounted) return PayRentResult.couldNotStart;

  // ── 2. Hand it to the native sheet and wait for one of three callbacks. ────────────────
  final outcome = await _openSheet(order);

  if (!context.mounted) return PayRentResult.notPaid;

  switch (outcome) {
    case CheckoutOutcome.failed:
      // Deliberately gentle and deliberately certain. The commonest cause by far is the
      // resident closing the sheet, which is not an error and must not be dressed as one.
      _say(messenger, 'Payment cancelled. Nothing has been charged.');
      return PayRentResult.notPaid;

    case CheckoutOutcome.externalWallet:
      // The resident left for a wallet app. This handset genuinely does not know what happened
      // next, and saying either "paid" or "not paid" would be a guess. The ledger knows.
      _say(messenger, 'Finish the payment in your wallet app. Your balance will update here '
          'once it goes through.');
      return PayRentResult.awaitingConfirmation;

    case CheckoutOutcome.succeeded:
      break;
  }

  // ── 3. Razorpay told the PHONE it worked. Now ask the SERVER. ──────────────────────────
  _say(messenger, 'Payment received — confirming with your hostel…');
  final settled = await _waitForLedger(ref, owedBefore: order.amountRupees);

  if (!context.mounted) {
    return settled ? PayRentResult.confirmed : PayRentResult.awaitingConfirmation;
  }

  if (settled) {
    _say(messenger, 'Paid. Your rent for this month is settled.');
    return PayRentResult.confirmed;
  }

  // Not a failure — an honest description of a delay, with the reassurance that matters.
  _say(
    messenger,
    'Your payment went through and is being confirmed. It will appear here shortly — '
    'you do not need to pay again.',
    duration: const Duration(seconds: 6),
  );
  return PayRentResult.awaitingConfirmation;
}

/// Drive the native sheet, and guarantee the listeners are torn down.
///
/// Wrapped in a [Completer] because [Razorpay] is callback-based and everything above is not.
/// The completer is guarded on every path: the SDK will not deliver two callbacks for one
/// checkout, but a defensive `isCompleted` costs nothing and a "Future already completed" crash
/// in the middle of a payment is not a thing to discover in production.
Future<CheckoutOutcome> _openSheet(CheckoutOrder order) {
  final done = Completer<CheckoutOutcome>();
  final razorpay = Razorpay();

  void finish(CheckoutOutcome outcome) {
    if (!done.isCompleted) done.complete(outcome);
  }

  razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (_) => finish(CheckoutOutcome.succeeded));
  razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (_) => finish(CheckoutOutcome.failed));
  razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) => finish(CheckoutOutcome.externalWallet));

  try {
    razorpay.open({
      'key': order.keyId,
      'order_id': order.orderId,
      // Paise, and the SERVER'S figure. Razorpay reconciles this against the order it minted and
      // refuses a mismatch, so this line cannot overcharge or undercharge even if it were wrong.
      'amount': order.amountPaise,
      'currency': order.currency,
      'name': order.hostelName.isEmpty ? 'Nivora' : order.hostelName,
      'description': 'Rent · ${order.periodMonth}',
      'prefill': {
        'name': order.prefillName,
        'email': order.prefillEmail,
        'contact': order.prefillContact,
      },
      // No `method` block on purpose: whatever the hostel's Razorpay account has enabled is what
      // the resident is offered — UPI (both collect and intent, so GPay/PhonePe/Paytm open
      // directly), cards, netbanking, wallets. Narrowing it here would silently remove the
      // method most Indian residents actually use.
      'retry': {'enabled': true, 'max_count': 1},
      'timeout': 300,
      'theme': {'color': '#C9A96E'},
    });
  } catch (_) {
    // open() throws synchronously on a malformed options map. Treated as "did not pay", which
    // is exactly what happened: the sheet never came up and Razorpay was never contacted.
    finish(CheckoutOutcome.failed);
  }

  // clear() removes the native listeners. Without it they outlive this call and a later payment
  // delivers its result into this dead closure. See the file header.
  return done.future.whenComplete(razorpay.clear);
}

/// Poll the resident's own ledger until the webhook has moved it, or the window closes.
///
/// Returns true only when the SERVER says the balance fell. This is the actual confirmation
/// step of the whole flow — see the file header on why the callback is not.
Future<bool> _waitForLedger(WidgetRef ref, {required double owedBefore}) async {
  final deadline = DateTime.now().add(_confirmWindow);

  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(_pollEvery);

    // Thrown away and read again — a cached row is precisely the thing that would make this
    // loop spin forever against a stale answer.
    ref.invalidate(myRentThisMonthProvider);

    try {
      final row = await ref.read(myRentThisMonthProvider.future);
      // A settled month can come back either as a smaller balance or as no outstanding row at
      // all, depending on how the ledger reports a fully-paid period. Both mean the same thing.
      if (row == null || row.balance < owedBefore) return true;
    } catch (_) {
      // A failed poll is not a failed payment. Keep asking until the window closes; the caller
      // says something honest either way.
    }
  }
  return false;
}

void _say(ScaffoldMessengerState messenger, String message, {Duration? duration}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
}

/// The button a resident taps to pay, and the honest sentence underneath it.
///
/// Shows the cash-at-the-desk route as well, because it is still real: a resident with no bank
/// app, or a failed card, still walks to the office, and a screen offering only the online path
/// would strand them.
class PayRentButton extends ConsumerStatefulWidget {
  const PayRentButton({super.key, required this.amount});

  /// Display only — this is what the resident is told they owe. What they are CHARGED comes
  /// from the server inside [payRent] and is never taken from this field.
  final double amount;

  @override
  ConsumerState<PayRentButton> createState() => _PayRentButtonState();
}

class _PayRentButtonState extends ConsumerState<PayRentButton> {
  bool _busy = false;

  Future<void> _pay() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await payRent(context, ref);
    } finally {
      // A `finally`, so no path can leave the button spinning with the sheet gone.
      if (mounted) setState(() => _busy = false);
      // Whatever happened — confirmed, delayed, cancelled — the screen behind should reflect
      // the server, not the guess it was drawn with.
      if (mounted) refreshStudentData(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _pay,
          icon: _busy
              ? SizedBox.square(
                  dimension: IconSize.md,
                  child: CircularProgressIndicator(
                    strokeWidth: Strokes.glyph,
                    color: t.colorScheme.onPrimary,
                  ),
                )
              : const Icon(Icons.lock_rounded, size: IconSize.md),
          label: Text(_busy ? 'Opening…' : 'Pay ${rupees(widget.amount)} now'),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'UPI, cards, net banking and wallets. Nivora never sees your card or UPI details.',
          style: t.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
