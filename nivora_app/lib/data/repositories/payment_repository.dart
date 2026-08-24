library;

import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'repository.dart';

/// Rent, paid from inside the app.
///
/// TABLES: public.payment_intents (SELECT only — the app has no write path to it at all).
/// EDGE FUNCTIONS: razorpay-order.
/// RPCs: none directly. `rz_open_intent` is called by the Edge Function, as the student.
///
/// ═══ WHY THE AMOUNT IS NOT A PARAMETER ANYWHERE IN THIS FILE ═══
/// [openRentOrder] sends NO BODY. Not an amount, not a student id, not a month. The Edge
/// Function reads the caller's identity from the JWT, derives the outstanding balance from that
/// resident's own ledger, and then `rz_open_intent()` derives it a SECOND time inside the
/// database and refuses to write the intent row unless the two agree. If this method took an
/// amount, it would be an amount an attacker could choose, and a 9,000-rupee room could be paid
/// for with one rupee. It does not take one, so that bug is not available.
///
/// ═══ AND WHY SUCCESS IS NOT SOMETHING THIS APP DECIDES ═══
/// The Razorpay checkout hands back a payment id and a signature the moment the native sheet
/// closes. Neither is settlement. The money is recorded only when Razorpay's webhook reaches
/// the server, its HMAC signature verifies, and `rz_record_capture()` / `rz_credit_fee()` run.
/// That is asynchronous and happens somewhere this device cannot see. So the client's only
/// honest move after a "success" callback is to WATCH `payment_intents` for the server's
/// verdict — [watchSettlement] — and to say "confirming" until it arrives. Verifying the
/// checkout signature here would be theatre: the secret it is signed with is not on the device,
/// and could not safely be.
///
/// ═══ WHY THIS ONE REPOSITORY HAS AN INTERFACE IN FRONT OF IT ═══
/// [RentPayments] exists so the payment state machine can be tested. Every other repository in
/// this directory is exercised through the providers that wrap it; this one is driven by a
/// controller with eight states, three of which are about money that has moved but not landed,
/// and those are the states worth pinning down in `flutter test`. Typing the provider by the
/// interface is what lets a test supply a fake without a network, a device, or a Razorpay
/// account.
abstract interface class RentPayments {
  /// Open a Razorpay order for whatever the caller still owes this month.
  Future<RentOrder> openRentOrder();

  /// The server's record of one order, or null if it has not landed yet.
  Future<PaymentIntent?> intentForOrder(String orderId);

  /// Follow one order until the server has a verdict, or until the window closes.
  Stream<PaymentIntent> watchSettlement(
    String orderId, {
    Duration interval,
    Duration timeout,
  });
}

final class PaymentRepository extends Repository implements RentPayments {
  const PaymentRepository(super.db);

  /// Open a Razorpay order for whatever this resident still owes this month.
  ///
  /// The bearer token goes with the request automatically — supabase_flutter's functions client
  /// signs every call with the current session's access token, which is what the function turns
  /// into a person via `auth.getUser()`. An anon-key call is a structurally valid project JWT
  /// with no user behind it and is refused there.
  ///
  /// Reuses an order the resident already has open for the same month and the same amount
  /// (the function does that, not this method), so dismissing the sheet and tapping Pay again
  /// does not litter the intent table with rows that look like failed payments.
  @override
  Future<RentOrder> openRentOrder() => guard(() async {
        final FunctionResponse response;
        try {
          // No `body:`. See the class doc — the absence is the security property.
          response = await db.functions.invoke('razorpay-order');
        } on FunctionException catch (error, stack) {
          Error.throwWithStackTrace(_fromFunction(error), stack);
        }

        final envelope = response.data;
        if (envelope is! Map) {
          throw RowShapeError(
            'razorpay-order',
            '(body)',
            'expected a JSON object envelope',
          );
        }
        final data = envelope['data'];
        if (data is! Map) {
          throw RowShapeError(
            'razorpay-order',
            'data',
            'the function answered without an order — check its logs',
          );
        }
        return RentOrder.fromJson(data.cast<String, dynamic>());
      });

  /// The server's record of one order, or null if it has not landed yet.
  ///
  /// RLS-scoped by `payment_intents_select`, which admits `student_id = app.current_student_id()`
  /// for a resident. The `.eq()` below picks the row out; it is not what stops this reading
  /// somebody else's payment.
  @override
  Future<PaymentIntent?> intentForOrder(String orderId) => guard(() async {
        final row = await db
            .from('payment_intents')
            .select(PaymentIntent.columns)
            .eq('razorpay_order_id', orderId)
            .maybeSingle();
        return row == null ? null : PaymentIntent.fromJson(row);
      });

  /// Follow one order until the server says what happened to it.
  ///
  /// POLLED, NOT SUBSCRIBED, on purpose. Realtime would need `payment_intents` added to the
  /// publication and a channel opened for a wait that is normally two seconds long; a handful
  /// of small indexed reads on a row the resident is already allowed to see costs less and has
  /// nothing to leave running if the sheet is closed mid-flight.
  ///
  /// Yields every state it observes, so the UI can move from "confirming" to "received" to
  /// "credited" as the server does, rather than sitting on a spinner and then jumping.
  ///
  /// THE STREAM ENDS WITHOUT A VERDICT IF [timeout] ELAPSES. That is not an error and must not
  /// be drawn as one: a webhook that has not arrived in forty seconds usually arrives in five
  /// minutes, and the money is not lost either way. The caller's job at that point is to say so
  /// honestly. See RentPaymentController.
  @override
  Stream<PaymentIntent> watchSettlement(
    String orderId, {
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(seconds: 40),
  }) async* {
    final deadline = DateTime.now().add(timeout);
    PaymentIntentStatus? lastStatus;
    bool lastCredited = false;

    while (DateTime.now().isBefore(deadline)) {
      PaymentIntent? intent;
      try {
        intent = await intentForOrder(orderId);
      } on AppFailure {
        // A dropped poll is not a verdict. Keep waiting: the money's fate is decided on the
        // server whether or not this phone can currently reach it.
        intent = null;
      }

      if (intent != null && (intent.status != lastStatus || intent.isSettled != lastCredited)) {
        lastStatus = intent.status;
        lastCredited = intent.isSettled;
        yield intent;

        // Terminal states. `captured` is NOT terminal until it is credited — that second step
        // is a separate transaction and is exactly the gap a resident deserves to be told about.
        if (intent.isSettled ||
            intent.status == PaymentIntentStatus.failed ||
            intent.status == PaymentIntentStatus.expired) {
          return;
        }
      }

      await Future<void>.delayed(interval);
    }
  }

  /// Turns an Edge Function failure into the same sealed [AppFailure] the rest of the data
  /// layer throws.
  ///
  /// Worth doing carefully rather than collapsing to "something went wrong": the function
  /// answers a 409 with "Your rent for this month is already settled" and a 503 with "Online
  /// payment isn't set up yet. You can still pay at the warden desk." Those sentences were
  /// written for the resident and are more useful than anything this file could invent.
  static AppFailure _fromFunction(FunctionException error) {
    final message = _messageFrom(error.details);

    // status 0 — the request never left the phone.
    if (error is FunctionsFetchException || error.status == 0) {
      return OfflineFailure(
        'Cannot reach Nivora. Check your connection and try again.',
        technical: error.toString(),
      );
    }

    return switch (error.status) {
      401 => SignedOutFailure(
          message ?? 'Your session has ended. Sign in again to continue.',
          technical: error.toString(),
        ),
      403 => AccessDeniedFailure(
          message ?? 'You do not have access to that.',
          technical: error.toString(),
        ),
      404 => NotFoundFailure(
          message ?? 'Your student record could not be found. Contact your warden.',
          technical: error.toString(),
        ),
      // 409 is "already settled" / "nothing to pay" and 503 is "not configured". Both are
      // sentences a resident can act on, and neither is worth retrying.
      409 || 400 => InvalidInputFailure(
          message ?? 'That payment could not be started. Reload and try again.',
          technical: error.toString(),
        ),
      503 => ServerFailure(
          message ?? "Online payment isn't set up yet. You can still pay at the warden desk.",
          technical: error.toString(),
        ),
      _ => ServerFailure(
          message ?? 'Nivora could not start that payment. Try again in a moment.',
          technical: error.toString(),
        ),
    };
  }

  /// The function's own `{ ok: false, error: "..." }` body, when there is one.
  static String? _messageFrom(Object? details) {
    if (details is Map) {
      final error = details['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE NATIVE CHECKOUT
//
// Lives beside the repository because it is the other half of the same boundary: one side asks
// the server for an order, the other hands that order to Razorpay's own Android/iOS SDK. It is
// behind an interface for one reason — `razorpay_flutter` is a MethodChannel plugin, and a
// widget test has no platform to answer it. Tests override [razorpayCheckoutProvider] with a
// fake and drive the whole payment state machine without a device.
//
// NO WEBVIEW, NO BROWSER. `Razorpay.open()` starts Razorpay's native checkout activity. That is
// the product requirement, and it is also why the key secret can stay on the server: nothing
// about this flow needs a redirect URL the app would have to host.
// ─────────────────────────────────────────────────────────────────────────────

/// What the checkout can tell us. Deliberately three cases, because they are three different
/// conversations with the resident and collapsing them loses the one that matters.
sealed class CheckoutOutcome {
  const CheckoutOutcome();
}

/// The sheet closed with a payment id. NOT a receipt — see [PaymentRepository.watchSettlement].
final class CheckoutSubmitted extends CheckoutOutcome {
  const CheckoutSubmitted({required this.orderId, this.paymentId});

  /// Razorpay echoes back the order the payment was made against. Checked by the caller against
  /// the order it opened, because the plugin re-delivers responses it could not hand over
  /// earlier (see [RazorpayCheckout.open]).
  final String? orderId;
  final String? paymentId;
}

/// The resident dismissed the sheet, or the payment did not go through.
final class CheckoutFailed extends CheckoutOutcome {
  const CheckoutFailed({required this.cancelled, this.message});

  /// True when the resident backed out. Nothing went wrong and they must not be told it did.
  final bool cancelled;
  final String? message;
}

/// The resident chose a wallet that finishes outside this sheet.
final class CheckoutExternalWallet extends CheckoutOutcome {
  const CheckoutExternalWallet(this.walletName);

  final String? walletName;
}

/// Opens Razorpay's native checkout. One implementation for the device, one for tests.
abstract interface class RazorpayCheckout {
  /// Opens the sheet for [order] and completes with whatever the SDK reports.
  ///
  /// Completes exactly once per call.
  Future<CheckoutOutcome> open(RentOrder order);

  /// Releases the plugin's event handlers. MUST be called — see the implementation.
  void dispose();
}

/// The real thing.
///
/// ═══ WHY dispose() IS NOT OPTIONAL ═══
/// `Razorpay.on()` registers handlers on an EventEmitter that the plugin instance owns, and the
/// handlers close over this object. A screen that creates a Razorpay and walks away leaves them
/// registered; open the rent sheet three times and a single checkout result is delivered to
/// three listeners, two of which belong to widgets that are gone. `clear()` is what removes
/// them, and it also cancels the plugin's merchant-event stream subscription.
///
/// ═══ WHY EVERY RESPONSE IS CHECKED AGAINST THE ORDER WE OPENED ═══
/// `Razorpay.on()` calls the plugin's `resync`, which asks the platform for a response it could
/// not deliver earlier — for instance because Android killed the Flutter activity while the
/// resident was in their UPI app. That is a genuinely useful feature and a genuine hazard: the
/// first thing a fresh listener hears can be the ghost of a PREVIOUS checkout. The caller
/// compares [CheckoutSubmitted.orderId] with the order it opened and ignores anything else.
final class PluginRazorpayCheckout implements RazorpayCheckout {
  PluginRazorpayCheckout();

  Razorpay? _razorpay;
  Completer<CheckoutOutcome>? _pending;

  /// The order the sheet currently on screen was opened for. Every success response is checked
  /// against it — see the class doc on resync.
  String? _expectedOrderId;

  @override
  Future<CheckoutOutcome> open(RentOrder order) {
    // One checkout at a time. A second tap while the native sheet is up would otherwise leave
    // the first completer forever unfinished and its spinner turning.
    final inFlight = _pending;
    if (inFlight != null && !inFlight.isCompleted) return inFlight.future;

    final completer = Completer<CheckoutOutcome>();
    _pending = completer;
    _expectedOrderId = order.orderId;

    final razorpay = _razorpay ??= Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onWallet);

    razorpay.open(<String, dynamic>{
      // The PUBLISHABLE key, as the server handed it over. Never a secret.
      'key': order.keyId,
      // Both are sent. Razorpay charges what the ORDER says, not what this map says — the
      // amount here only has to agree, and the server decided both.
      'order_id': order.orderId,
      'amount': order.amountPaise,
      'currency': order.currency,
      'name': order.hostelName,
      'description': 'Rent for ${order.periodMonth}',
      // Seconds. Without it a sheet left open on a locked phone stays open indefinitely and the
      // order ages out underneath it.
      'timeout': 300,
      // Razorpay's in-sheet retry is off so that exactly one place decides what happens after a
      // failure: our own sheet, which can re-open the same still-valid order.
      'retry': <String, dynamic>{'enabled': false},
      'prefill': <String, dynamic>{
        'name': order.prefill.name,
        'contact': order.prefill.contact,
        // Omitted rather than sent empty: a blank address on the sheet is worse than none.
        if (order.prefill.email != null) 'email': order.prefill.email,
      },
    });

    return completer.future;
  }

  void _onSuccess(PaymentSuccessResponse response) {
    final orderId = response.orderId;
    // THE RESYNC GUARD. The plugin re-delivers a response it could not hand over earlier — the
    // resident finished in their UPI app after Android killed the Flutter activity, say. That
    // stale success can arrive moments after this sheet opened, for a completely different
    // order, and accepting it would leave the resident watching "confirming..." for a payment
    // they are not making while the real sheet is still in front of them. Dropping it costs
    // nothing: the webhook, not this callback, is what settles the old payment.
    if (orderId != null && _expectedOrderId != null && orderId != _expectedOrderId) return;
    _finish(CheckoutSubmitted(orderId: orderId, paymentId: response.paymentId));
  }

  void _onError(PaymentFailureResponse response) {
    _finish(CheckoutFailed(
      cancelled: response.code == Razorpay.PAYMENT_CANCELLED,
      message: response.message,
    ));
  }

  void _onWallet(ExternalWalletResponse response) {
    _finish(CheckoutExternalWallet(response.walletName));
  }

  void _finish(CheckoutOutcome outcome) {
    final completer = _pending;
    // A resync can deliver a response when nothing is waiting for one. Dropping it here is
    // correct: the webhook, not this callback, is what settles a payment, so a result nobody
    // asked for costs the resident nothing.
    if (completer == null || completer.isCompleted) return;
    _pending = null;
    _expectedOrderId = null;
    completer.complete(outcome);
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _razorpay = null;
    _expectedOrderId = null;
    final completer = _pending;
    if (completer != null && !completer.isCompleted) {
      // The screen is gone. Whoever was awaiting this is gone too, but an uncompleted completer
      // is a leak, so close it as a dismissal rather than leaving it dangling.
      completer.complete(const CheckoutFailed(cancelled: true));
    }
    _pending = null;
  }
}
