// PAYING RENT IN THE APP — the properties that keep the money path honest.
//
// The checkout flow itself (features/payments/pay_rent.dart) drives a NATIVE SDK and cannot run
// under `flutter test`. What CAN be pinned down here is everything around it, and the things
// worth pinning are not the happy path — they are the four ways this path could quietly start
// lying:
//
//   1. the client sending an AMOUNT (the ₹1-order-for-a-₹9000-room attack)
//   2. a refusal that leaves a resident unsure whether their money moved
//   3. a `test_mode` flag that defaults the wrong way and lets a real charge look like a rehearsal
//   4. a settled month still offering to take money
//
// The webhook is what credits the ledger; none of that is re-tested here (razorpay_webhook and
// the signature suite own it). This file is about the phone.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/repositories/checkout_repository.dart';
import 'package:mobile/features/payments/pay_rent.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A wire row. [testMode] null means the KEY IS ABSENT ENTIRELY, which is the case the
/// "unstated reads as live" test is about — not a present-but-null value.
Map<String, dynamic> _orderJson({Object? testMode = true}) {
  final row = <String, dynamic>{
    'order_id': 'order_TEST0000000001',
    'key_id': 'rzp_test_TWpPcB96YvjHjY',
    'amount_paise': 620000,
    'amount_rupees': 6200,
    'currency': 'INR',
    'period_month': '2026-09',
    'hostel_name': 'Sunrise PG',
    'student_name': 'Aarav Sharma',
    'prefill': {'name': 'Aarav Sharma', 'email': '', 'contact': '9000000001'},
  };
  if (testMode != null) row['test_mode'] = testMode;
  return row;
}

void main() {
  group('the order is the server\'s decision, and the client only reads it', () {
    test('every figure comes off the wire, and none is computed here', () {
      final order = CheckoutOrder.fromJson(_orderJson());

      expect(order.orderId, 'order_TEST0000000001');
      expect(order.amountPaise, 620000);
      expect(order.amountRupees, 6200);
      expect(order.currency, 'INR');
      expect(order.periodMonth, '2026-09');
      expect(order.prefillContact, '9000000001');
    });

    test('the class carries no way to change what is charged', () {
      // A COMPILE-TIME PROPERTY, asserted as prose because there is no other way to assert it:
      // every field on CheckoutOrder is `final` and the class has no method that returns a
      // modified copy. If someone adds `copyWith(amountPaise: …)` this test's comment is the
      // thing that should stop them, because the type system will not.
      //
      // What CAN be checked is that two reads of the same wire row are equal in the only field
      // that matters, i.e. nothing in construction derives or adjusts it.
      final a = CheckoutOrder.fromJson(_orderJson());
      final b = CheckoutOrder.fromJson(_orderJson());
      expect(a.amountPaise, b.amountPaise);
      expect(a.amountPaise, 620000, reason: 'the wire value, unrounded and unscaled');
    });

    test('a missing amount is a shape error, never a zero-rupee order', () {
      final row = _orderJson()..remove('amount_paise');
      // Falling back to 0 here would mint a free order. It must refuse instead.
      expect(() => CheckoutOrder.fromJson(row), throwsA(isA<RowShapeError>()));
    });

    test('an unstated test_mode reads as LIVE, not as a rehearsal', () {
      // The dangerous default is the other one. A sheet that wrongly says "test mode" invites a
      // resident to treat a real charge as practice; a sheet that wrongly says "live" only makes
      // them more careful. So absence must resolve to false.
      expect(CheckoutOrder.fromJson(_orderJson(testMode: null)).testMode, isFalse);
      expect(CheckoutOrder.fromJson(_orderJson(testMode: 'yes')).testMode, isFalse,
          reason: 'only a real boolean true means test mode');
      expect(CheckoutOrder.fromJson(_orderJson(testMode: true)).testMode, isTrue);
    });
  });

  group('a refusal always says whether the money moved', () {
    test('offline says nothing was charged, in those words', () {
      const offline = FunctionsFetchException(reasonPhrase: 'connection failed');
      final failure = CheckoutRepository.failureFrom(offline);

      expect(failure, isA<OfflineFailure>());
      // The reassurance is the POINT of this branch. A resident who fears a half-made payment
      // refreshes, retries, and pays twice — so the sentence has to close that door explicitly.
      expect(failure.message, contains('not started'));
      expect(failure.message, contains('Nothing has been charged'));
    });

    test('a 404 with no body means NOT DEPLOYED, and sends the resident to the desk', () {
      // The gateway answers 404 with an empty body when razorpay-order is absent from the
      // project. Reading that as "you owe nothing" would cost the resident a late fee.
      const notDeployed = FunctionException(status: 404);
      final failure = CheckoutRepository.failureFrom(notDeployed);

      expect(failure, isA<NotFoundFailure>());
      expect(failure.message, contains('not available on this server'));
      expect(failure.message, contains('pay your warden'));
    });

    test('a 404 the function wrote itself is passed through verbatim', () {
      const spoken = FunctionException(
        status: 404,
        details: {'ok': false, 'error': 'You are not registered at a hostel yet.'},
      );
      expect(CheckoutRepository.failureFrom(spoken).message,
          'You are not registered at a hostel yet.');
    });

    test('a lapsed subscription is the owner\'s conversation, not a permission error', () {
      const billing = FunctionException(
        status: 403,
        details: {'ok': false, 'error': 'This hostel is read-only until the subscription is renewed.'},
      );
      expect(CheckoutRepository.failureFrom(billing), isA<ReadOnlyFailure>());
    });

    test('a plain 403 stays a permission refusal', () {
      const denied = FunctionException(status: 403);
      expect(CheckoutRepository.failureFrom(denied), isA<AccessDeniedFailure>());
    });

    test('an expired session asks for a sign-in rather than blaming the payment', () {
      const expired = FunctionException(status: 401);
      final failure = CheckoutRepository.failureFrom(expired);
      expect(failure, isA<SignedOutFailure>());
      expect(failure.message, contains('Sign in again'));
    });

    test('nothing owed is an ordinary answer, not a fault', () {
      const nothingDue = FunctionException(
        status: 400,
        details: {'ok': false, 'error': 'You have nothing to pay this month.'},
      );
      final failure = CheckoutRepository.failureFrom(nothingDue);
      expect(failure, isA<InvalidInputFailure>());
      expect(failure.message, 'You have nothing to pay this month.');
    });

    test('a 5xx says payments are down AND that nothing was charged', () {
      const upstream = FunctionException(status: 502);
      final failure = CheckoutRepository.failureFrom(upstream);
      expect(failure, isA<ServerFailure>());
      // Razorpay refusing to mint an order means no order, which means no payment. Say so.
      expect(failure.message, contains('Nothing has been charged'));
    });
  });

  group('the checkout outcome is a hint about the sheet, not a claim about the ledger', () {
    test('every outcome is one the screen must still verify against the server', () {
      // Three, and only three. Adding a fourth that means "confirmed" would be the bug the whole
      // of pay_rent.dart is arranged to prevent: confirmation is a LEDGER READ, and no value
      // reported by the handset is allowed to stand in for it.
      expect(CheckoutOutcome.values, hasLength(3));
      expect(
        CheckoutOutcome.values.map((e) => e.name).toSet(),
        {'succeeded', 'failed', 'externalWallet'},
      );
    });

    test('the result the flow returns distinguishes confirmed from merely reported', () {
      // `confirmed` is only ever produced by _waitForLedger returning true. The existence of a
      // separate `awaitingConfirmation` is what stops "Razorpay said yes" being rendered as
      // "paid" — see the header of pay_rent.dart.
      expect(PayRentResult.values, contains(PayRentResult.confirmed));
      expect(PayRentResult.values, contains(PayRentResult.awaitingConfirmation));
      expect(PayRentResult.confirmed, isNot(PayRentResult.awaitingConfirmation));
    });
  });
}
