import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/data/repositories/payment_repository.dart';
import 'package:mobile/features/student/rent_payment_controller.dart';

/// Paying rent in the app, and the one property worth more than all the others: THE APP NEVER
/// SAYS A PAYMENT SUCCEEDED UNTIL THE SERVER SAYS SO.
///
/// Razorpay's checkout reports success on the device, seconds before the webhook that actually
/// credits the rent ledger reaches the server. Every test below exists to pin down that gap —
/// that the checkout callback moves the machine to "confirming" and never further on its own,
/// that "Razorpay has the money" and "your rent is credited" stay distinguishable, and that
/// giving up waiting is not rendered as a failure.
///
/// Nothing here touches a network, a database or a device. `paymentRepositoryProvider` is typed
/// by [RentPayments] and `razorpayCheckoutProvider` by [RazorpayCheckout] precisely so both can
/// be replaced here.

// ─────────────────────────────────────────────────────────────────────────────
// FIXTURES — shaped like the real wire, so a schema drift breaks a test.
// ─────────────────────────────────────────────────────────────────────────────

const _orderId = 'order_QkP2xRZ7bT4nQe';
const _paymentId = 'pay_QkP31mLd9wYzAb';

/// Exactly the envelope the razorpay-order Edge Function returns: `ok()` wraps the payload in
/// `{ ok, data }`, and this is the `data` half.
Map<String, dynamic> orderJson({bool testMode = true}) => <String, dynamic>{
      'order_id': _orderId,
      'key_id': 'rzp_test_TTZjgz6pssJVJs',
      'amount_paise': 620000,
      'amount_rupees': 6200,
      'currency': 'INR',
      'period_month': '2026-08',
      'hostel_name': 'Sunrise Residency',
      'student_name': 'Rohan Deshmukh',
      'test_mode': testMode,
      'prefill': {'name': 'Rohan Deshmukh', 'email': '', 'contact': '9000000004'},
    };

/// One public.payment_intents row.
Map<String, dynamic> intentJson({
  required String status,
  String? paymentId,
  String? capturedAt,
  String? creditedAt,
  String? method,
  String? failureReason,
}) =>
    <String, dynamic>{
      'id': '1f6d2b8e-2c3a-4f51-9d70-2a1f0b5c7e11',
      'student_id': '5922bad8-faa4-42e0-b35f-73fe97b2c99d',
      'period_month': '2026-08',
      'amount_paise': 620000,
      'razorpay_order_id': _orderId,
      'razorpay_payment_id': paymentId,
      'method': method,
      'status': status,
      'failure_reason': failureReason,
      'captured_at': capturedAt,
      'credited_at': creditedAt,
      'created_at': '2026-08-24T09:15:00.000Z',
    };

// ─────────────────────────────────────────────────────────────────────────────
// FAKES
// ─────────────────────────────────────────────────────────────────────────────

final class _FakePayments implements RentPayments {
  _FakePayments({this.order, this.orderError, this.settlements = const []});

  final RentOrder? order;
  final AppFailure? orderError;

  /// The states the server reports, in order. An empty list is a webhook that never arrived.
  final List<PaymentIntent> settlements;

  int openCalls = 0;

  @override
  Future<RentOrder> openRentOrder() async {
    openCalls++;
    final failure = orderError;
    if (failure != null) throw failure;
    return order!;
  }

  @override
  Future<PaymentIntent?> intentForOrder(String orderId) async =>
      settlements.isEmpty ? null : settlements.last;

  @override
  Stream<PaymentIntent> watchSettlement(
    String orderId, {
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(seconds: 40),
  }) async* {
    for (final intent in settlements) {
      yield intent;
    }
    // Falling off the end is the real stream's "we stopped waiting" — the timeout path.
  }
}

final class _FakeCheckout implements RazorpayCheckout {
  _FakeCheckout(this.outcome);

  final CheckoutOutcome outcome;
  int opens = 0;
  bool disposed = false;

  @override
  Future<CheckoutOutcome> open(RentOrder order) async {
    opens++;
    return outcome;
  }

  @override
  void dispose() => disposed = true;
}

ProviderContainer _container({required _FakePayments payments, required _FakeCheckout checkout}) {
  final container = ProviderContainer(
    overrides: [
      paymentRepositoryProvider.overrideWithValue(payments),
      razorpayCheckoutProvider.overrideWithValue(checkout),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<RentPaymentState> _pay(ProviderContainer container) async {
  // Keeps the autoDispose controller alive for the duration of the test.
  final sub = container.listen(rentPaymentControllerProvider, (_, _) {});
  addTearDown(sub.close);
  await container.read(rentPaymentControllerProvider.notifier).pay();
  return container.read(rentPaymentControllerProvider);
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('models', () {
    test('RentOrder carries the server figure and never invents one', () {
      final order = RentOrder.fromJson(orderJson());

      expect(order.orderId, _orderId);
      expect(order.amountPaise, 620000);
      expect(order.amountRupees, 6200);
      expect(order.periodMonth, '2026-08');
      // rzp_test_ → say so on screen, because this payment moves no real money.
      expect(order.testMode, isTrue);
      // The publishable key is the ONLY Razorpay credential that may reach a phone.
      expect(order.keyId, startsWith('rzp_test_'));
    });

    test('an empty prefill email becomes null rather than a blank address', () {
      expect(RentOrder.fromJson(orderJson()).prefill.email, isNull);
    });

    test('a missing column in the order response is named, not silently null', () {
      final broken = orderJson()..remove('amount_paise');
      expect(
        () => RentOrder.fromJson(broken),
        throwsA(isA<RowShapeError>().having((e) => e.column, 'column', 'amount_paise')),
      );
    });

    test('captured but not credited is NEITHER paid nor failed', () {
      final intent = PaymentIntent.fromJson(intentJson(
        status: 'captured',
        paymentId: _paymentId,
        capturedAt: '2026-08-24T09:15:20.000Z',
        method: 'upi',
      ));

      // The whole point of keeping two timestamps: Razorpay has the money, the ledger does not.
      expect(intent.isMoneyTaken, isTrue);
      expect(intent.isSettled, isFalse);
      expect(intent.isPending, isFalse);
      expect(intent.amountRupees, 6200);
    });

    test('credited_at is what makes a payment settled', () {
      final intent = PaymentIntent.fromJson(intentJson(
        status: 'captured',
        paymentId: _paymentId,
        capturedAt: '2026-08-24T09:15:20.000Z',
        creditedAt: '2026-08-24T09:15:21.000Z',
      ));
      expect(intent.isSettled, isTrue);
    });

    test('an enum value this build has never heard of throws instead of guessing', () {
      expect(
        () => PaymentIntent.fromJson(intentJson(status: 'refunded')),
        throwsA(isA<RowShapeError>().having((e) => e.column, 'column', 'status')),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the payment state machine', () {
    test('a successful checkout says CONFIRMING, not paid', () async {
      // The server has not reported anything yet — exactly the moment after the native sheet
      // closes. Nothing in the app may claim the rent is settled here.
      final payments = _FakePayments(order: RentOrder.fromJson(orderJson()));
      final checkout = _FakeCheckout(
        const CheckoutSubmitted(orderId: _orderId, paymentId: _paymentId),
      );

      final state = await _pay(_container(payments: payments, checkout: checkout));

      expect(state, isA<RentPaymentConfirming>());
      expect(state, isNot(isA<RentPaymentCredited>()));
      expect(checkout.opens, 1);
    });

    test('only credited_at from the server produces "rent updated"', () async {
      final payments = _FakePayments(
        order: RentOrder.fromJson(orderJson()),
        settlements: [
          PaymentIntent.fromJson(intentJson(
            status: 'captured',
            paymentId: _paymentId,
            capturedAt: '2026-08-24T09:15:20.000Z',
            creditedAt: '2026-08-24T09:15:21.000Z',
            method: 'upi',
          )),
        ],
      );
      final checkout = _FakeCheckout(
        const CheckoutSubmitted(orderId: _orderId, paymentId: _paymentId),
      );
      final container = _container(payments: payments, checkout: checkout);

      await _pay(container);
      await pumpEventQueue();

      final state = container.read(rentPaymentControllerProvider);
      expect(state, isA<RentPaymentCredited>());
      expect((state as RentPaymentCredited).intent.isSettled, isTrue);
    });

    test('captured-but-uncredited stops at RECEIVED and never reaches credited', () async {
      // rz_credit_fee runs in its own transaction and can legitimately refuse — an expired
      // subscription, for one. The money is real and the ledger entry is missing, and the app
      // has to be able to say that without rounding it to either neighbour.
      final payments = _FakePayments(
        order: RentOrder.fromJson(orderJson()),
        settlements: [
          PaymentIntent.fromJson(intentJson(
            status: 'captured',
            paymentId: _paymentId,
            capturedAt: '2026-08-24T09:15:20.000Z',
            method: 'upi',
          )),
        ],
      );
      final container = _container(
        payments: payments,
        checkout: _FakeCheckout(
          const CheckoutSubmitted(orderId: _orderId, paymentId: _paymentId),
        ),
      );

      await _pay(container);
      await pumpEventQueue();

      final state = container.read(rentPaymentControllerProvider);
      expect(state, isA<RentPaymentReceived>());
      expect((state as RentPaymentReceived).intent.isSettled, isFalse);
    });

    test('a webhook that never arrives ends UNCONFIRMED, which is not a failure', () async {
      final payments = _FakePayments(order: RentOrder.fromJson(orderJson()));
      final container = _container(
        payments: payments,
        checkout: _FakeCheckout(
          const CheckoutSubmitted(orderId: _orderId, paymentId: _paymentId),
        ),
      );

      await _pay(container);
      await pumpEventQueue();

      final state = container.read(rentPaymentControllerProvider);
      expect(state, isA<RentPaymentUnconfirmed>());
      // The distinction that matters: a resident told "failed" pays twice.
      expect(state, isNot(isA<RentPaymentFailed>()));
    });

    test('a server-recorded failure carries the server words', () async {
      final payments = _FakePayments(
        order: RentOrder.fromJson(orderJson()),
        settlements: [
          PaymentIntent.fromJson(intentJson(
            status: 'failed',
            failureReason: 'Your payment was declined by the bank.',
          )),
        ],
      );
      final container = _container(
        payments: payments,
        checkout: _FakeCheckout(
          const CheckoutSubmitted(orderId: _orderId, paymentId: _paymentId),
        ),
      );

      await _pay(container);
      await pumpEventQueue();

      final state = container.read(rentPaymentControllerProvider);
      expect(state, isA<RentPaymentFailed>());
      expect((state as RentPaymentFailed).message, 'Your payment was declined by the bank.');
    });

    test('backing out of the checkout is a cancellation, not an error', () async {
      final container = _container(
        payments: _FakePayments(order: RentOrder.fromJson(orderJson())),
        checkout: _FakeCheckout(const CheckoutFailed(cancelled: true)),
      );

      expect(await _pay(container), isA<RentPaymentCancelled>());
    });

    test('an external wallet still waits for the server rather than guessing', () async {
      // The wallet finishes outside the sheet, so the SDK cannot report the ending. Confirming
      // is the honest state; only the server can close it.
      final container = _container(
        payments: _FakePayments(order: RentOrder.fromJson(orderJson())),
        checkout: _FakeCheckout(const CheckoutExternalWallet('paytm')),
      );

      final state = await _pay(container);
      expect(state, isA<RentPaymentConfirming>());
      expect((state as RentPaymentConfirming).walletName, 'paytm');
    });

    test('a refusal from the order endpoint is shown in the server own words', () async {
      final payments = _FakePayments(
        orderError: const InvalidInputFailure('Your rent for this month is already settled.'),
      );
      final container = _container(
        payments: payments,
        checkout: _FakeCheckout(const CheckoutFailed(cancelled: true)),
      );

      final state = await _pay(container);
      expect(state, isA<RentPaymentFailed>());
      expect(
        (state as RentPaymentFailed).message,
        'Your rent for this month is already settled.',
      );
      // Nothing to retry: the balance is zero and will still be zero on a second tap.
      expect(state.canRetry, isFalse);
    });

    test('an offline order attempt is retryable', () async {
      final container = _container(
        payments: _FakePayments(orderError: const OfflineFailure('Cannot reach Nivora.')),
        checkout: _FakeCheckout(const CheckoutFailed(cancelled: true)),
      );

      final state = await _pay(container);
      expect((state as RentPaymentFailed).canRetry, isTrue);
    });

    test('a second tap while a payment is in flight does not open a second order', () async {
      // A double tap on "Pay" must not become two Razorpay orders, and two orders for one
      // month is exactly the shape of an accidental double payment.
      final payments = _FakePayments(order: RentOrder.fromJson(orderJson()));
      final checkout = _FakeCheckout(
        const CheckoutSubmitted(orderId: _orderId, paymentId: _paymentId),
      );
      final container = _container(payments: payments, checkout: checkout);

      final sub = container.listen(rentPaymentControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final notifier = container.read(rentPaymentControllerProvider.notifier);

      await Future.wait([notifier.pay(), notifier.pay()]);

      expect(payments.openCalls, 1);
      expect(checkout.opens, 1);
    });

    test('every busy state locks the sheet, every finished one releases it', () {
      final order = RentOrder.fromJson(orderJson());

      expect(const RentPaymentOpening().isBusy, isTrue);
      expect(RentPaymentAtCheckout(order).isBusy, isTrue);
      expect(RentPaymentConfirming(order: order).isBusy, isTrue);

      expect(const RentPaymentIdle().isBusy, isFalse);
      expect(RentPaymentUnconfirmed(order).isBusy, isFalse);
      expect(const RentPaymentCancelled().isBusy, isFalse);
      expect(const RentPaymentFailed('nope').isBusy, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the checkout options', () {
    test('carry the order and never a secret', () {
      // Guards the one mistake that would matter most in this file: the phone is given the
      // PUBLISHABLE key id and an order the server minted. There is no field here an attacker
      // could set to change what they are charged — the amount is the server's, echoed back.
      final order = RentOrder.fromJson(orderJson());

      expect(order.keyId, isNot(contains('secret')));
      expect(order.keyId, matches(RegExp(r'^rzp_(test|live)_[A-Za-z0-9]+$')));
      expect(order.orderId, matches(RegExp(r'^order_[A-Za-z0-9]{6,30}$')));
      expect(order.amountPaise, order.amountRupees * 100);
    });
  });
}
