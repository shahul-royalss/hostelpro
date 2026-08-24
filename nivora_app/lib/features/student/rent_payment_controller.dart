library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/payment_repository.dart';
import 'student_providers.dart';

/// The rent payment, as a state machine, with one rule running through all of it.
///
/// ═══ THE RULE: THIS APP NEVER DECIDES THAT A PAYMENT SUCCEEDED ═══
/// Razorpay's native sheet closes and hands back a payment id long before the hostel has the
/// money on its ledger. Between those two moments a webhook has to reach the server, its HMAC
/// signature has to verify, and two database functions have to run. None of that happens on
/// this phone and none of it is visible from here.
///
/// So there is no state below that means "paid" on the strength of the checkout callback. The
/// callback moves the machine to [RentPaymentConfirming] — "payment received, confirming" —
/// and the ONLY thing that can move it to [RentPaymentCredited] is reading
/// `payment_intents.credited_at` back from the server. A fake receipt is worse than a slow one:
/// a resident who is shown "Paid" and then asked for rent again stops believing the app about
/// money, which is the only thing they opened it for.
///
/// The intermediate states are deliberately fine-grained, because the honest answers really are
/// different from one another:
///   [RentPaymentConfirming]   the money left, the server has not confirmed yet.
///   [RentPaymentReceived]     the server confirms Razorpay took it; the rent ledger has not
///                             been credited yet. Real, and sometimes lasts.
///   [RentPaymentUnconfirmed]  we stopped waiting. NOT a failure, and never drawn as one.
sealed class RentPaymentState {
  const RentPaymentState();

  /// True while something is in flight and the sheet must not be dismissed or re-submitted.
  bool get isBusy => switch (this) {
        RentPaymentOpening() || RentPaymentAtCheckout() || RentPaymentConfirming() => true,
        _ => false,
      };
}

/// Nothing has been attempted.
final class RentPaymentIdle extends RentPaymentState {
  const RentPaymentIdle();
}

/// Asking the server to open a Razorpay order.
final class RentPaymentOpening extends RentPaymentState {
  const RentPaymentOpening();
}

/// The native Razorpay sheet is on screen. Nothing to do but wait for it.
final class RentPaymentAtCheckout extends RentPaymentState {
  const RentPaymentAtCheckout(this.order);

  final RentOrder order;
}

/// The checkout returned. The server has not confirmed anything yet.
final class RentPaymentConfirming extends RentPaymentState {
  const RentPaymentConfirming({required this.order, this.walletName});

  final RentOrder order;

  /// Set when the resident chose a wallet that finishes outside the sheet, so the message can
  /// say where they are.
  final String? walletName;
}

/// The server confirms Razorpay took the money. The rent ledger is not credited YET.
///
/// A true statement that is neither "paid" nor "failed", and the reason this state exists.
final class RentPaymentReceived extends RentPaymentState {
  const RentPaymentReceived(this.intent);

  final PaymentIntent intent;
}

/// Money taken AND rent credited. The only state that may say the rent is settled.
final class RentPaymentCredited extends RentPaymentState {
  const RentPaymentCredited(this.intent);

  final PaymentIntent intent;
}

/// We stopped waiting before the server said anything conclusive.
///
/// NOT AN ERROR STATE. The payment is very probably fine; the webhook is simply slower than the
/// forty seconds anyone will stare at a spinner for. The resident is told what is true — the
/// money left their account, the hostel's record will catch up, and they should not pay twice.
final class RentPaymentUnconfirmed extends RentPaymentState {
  const RentPaymentUnconfirmed(this.order);

  final RentOrder order;
}

/// The resident backed out of the checkout. Nothing happened and nothing went wrong.
final class RentPaymentCancelled extends RentPaymentState {
  const RentPaymentCancelled();
}

/// Something refused: the server would not open an order, or the payment did not go through.
final class RentPaymentFailed extends RentPaymentState {
  const RentPaymentFailed(this.message, {this.canRetry = true});

  /// Written for the resident. Usually the server's own words — see PaymentRepository.
  final String message;
  final bool canRetry;
}

/// Drives one rent payment from "Pay" to a verdict.
///
/// autoDispose and scoped to the sheet: closing the sheet cancels the settlement watch, and the
/// checkout provider's own teardown clears the plugin's event handlers. Nothing survives to
/// deliver a result to a widget that is no longer there.
final rentPaymentControllerProvider =
    NotifierProvider.autoDispose<RentPaymentController, RentPaymentState>(
  RentPaymentController.new,
);

class RentPaymentController extends Notifier<RentPaymentState> {
  StreamSubscription<PaymentIntent>? _watch;

  @override
  RentPaymentState build() {
    ref.onDispose(() {
      _watch?.cancel();
      _watch = null;
    });
    return const RentPaymentIdle();
  }

  /// Open an order, run the native checkout, then wait for the server's verdict.
  ///
  /// Safe to call from a button that a resident taps twice: it refuses while anything is in
  /// flight. That matters more here than elsewhere — the second tap of a double tap on "Pay"
  /// must not become a second order.
  Future<void> pay() async {
    if (state.isBusy) return;

    _watch?.cancel();
    _watch = null;
    state = const RentPaymentOpening();

    final RentOrder order;
    try {
      order = await ref.read(paymentRepositoryProvider).openRentOrder();
    } on AppFailure catch (failure) {
      _set(RentPaymentFailed(failure.message, canRetry: failure.isRetryable));
      return;
    }
    if (!ref.mounted) return;

    state = RentPaymentAtCheckout(order);

    final outcome = await ref.read(razorpayCheckoutProvider).open(order);
    if (!ref.mounted) return;

    switch (outcome) {
      case CheckoutFailed(cancelled: true):
        state = const RentPaymentCancelled();

      case CheckoutFailed(:final message):
        // Razorpay's own description when it gave one. Its failure messages are written for a
        // payer ("Your payment was declined by the bank"), which is better than anything this
        // file could say about a bank it cannot see.
        state = RentPaymentFailed(
          message == null || message.trim().isEmpty
              ? 'The payment did not go through. Nothing has been charged.'
              : message.trim(),
        );

      case CheckoutExternalWallet(:final walletName):
        // The wallet finishes outside this sheet, so the SDK cannot tell us the ending. The
        // server can — start watching, exactly as for a normal submission.
        state = RentPaymentConfirming(order: order, walletName: walletName);
        _startWatching(order);

      case CheckoutSubmitted():
        state = RentPaymentConfirming(order: order);
        _startWatching(order);
    }
  }

  /// Watch `payment_intents` until the server has an answer, or until we stop waiting.
  void _startWatching(RentOrder order) {
    _watch?.cancel();
    _watch = ref.read(paymentRepositoryProvider).watchSettlement(order.orderId).listen(
      (intent) {
        if (!ref.mounted) return;
        switch (intent.status) {
          case PaymentIntentStatus.captured:
            if (intent.isSettled) {
              _set(RentPaymentCredited(intent));
            } else {
              // Razorpay has it, the ledger does not yet. Say precisely that.
              _set(RentPaymentReceived(intent));
            }
            // Either way the ledger is worth re-reading: it now shows whatever is actually
            // true, which is the only figure this app is allowed to put on screen.
            _refreshRent();

          case PaymentIntentStatus.failed:
            _set(RentPaymentFailed(
              intent.failureReason?.trim().isNotEmpty == true
                  ? intent.failureReason!.trim()
                  : 'The payment did not go through. Nothing has been charged.',
            ));

          case PaymentIntentStatus.expired:
            _set(const RentPaymentFailed(
              'That payment attempt expired before it completed. You can start again.',
            ));

          case PaymentIntentStatus.created:
            // Still waiting on the webhook. Nothing to say that is not already on screen.
            break;
        }
      },
      onDone: () {
        if (!ref.mounted) return;
        // Reached only when the poll window closed without a verdict. A state that already knows
        // something better is left alone.
        if (state is RentPaymentConfirming) {
          _set(RentPaymentUnconfirmed(order));
        }
      },
      onError: (Object _) {
        if (!ref.mounted) return;
        // A failed poll says nothing about the money. Refusing to guess is the whole point.
        if (state is RentPaymentConfirming) {
          _set(RentPaymentUnconfirmed(order));
        }
      },
    );
  }

  /// Back to the start, so the sheet can offer the payment again after a refusal.
  void reset() {
    _watch?.cancel();
    _watch = null;
    _set(const RentPaymentIdle());
  }

  /// Throw away the rent figures so every screen re-reads them from the ledger.
  ///
  /// The controller does NOT write the new balance itself. It invalidates and lets
  /// `rpc_fee_ledger` answer, because the ledger is the definition of what is owed and a number
  /// computed here would be a second definition free to disagree with the warden's screen.
  void _refreshRent() {
    ref.invalidate(myRentThisMonthProvider);
    ref.invalidate(feeLedgerProvider);
    ref.invalidate(studentFeeHistoryProvider);
  }

  /// Assign only while this provider is alive. A sheet closed mid-payment disposes the
  /// controller while the watch may still be mid-poll; writing `state` after that throws.
  void _set(RentPaymentState next) {
    if (!ref.mounted) return;
    state = next;
  }
}
