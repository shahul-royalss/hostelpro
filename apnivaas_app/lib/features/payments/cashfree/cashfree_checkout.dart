/// Cashfree's official checkout, opened inside the app (flutter_cashfree_pg_sdk).
///
/// The SDK draws Cashfree's payment page in the app and hands UPI payments to PhonePe, Google
/// Pay, Paytm, BHIM or any other UPI app on the phone. Its callbacks say only that the sheet
/// closed ("verify this order") or failed; neither marks rent paid. The caller then asks
/// cashfree-order for the order's status, which re-reads it from Cashfree on the server.
library;

import 'dart:async';

import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/cashfree_repository.dart';

/// How the checkout sheet ended, as the SDK reported it. A hint for what to say while the server
/// confirms; never a payment result.
sealed class CheckoutEnd {
  const CheckoutEnd();
}

/// The sheet closed normally: ask the server.
final class CheckoutClosed extends CheckoutEnd {
  const CheckoutClosed();
}

/// The SDK reported a failure (declined, cancelled, or it could not open).
final class CheckoutFailed extends CheckoutEnd {
  const CheckoutFailed(this.message, {this.code});
  final String message;
  final String? code;
}

abstract interface class CashfreeCheckout {
  Future<CheckoutEnd> open(CashfreeOrder order);
}

final class SdkCashfreeCheckout implements CashfreeCheckout {
  SdkCashfreeCheckout();

  final _service = CFPaymentGatewayService();

  @override
  Future<CheckoutEnd> open(CashfreeOrder order) {
    final done = Completer<CheckoutEnd>();
    _service.setCallback(
      (orderId) {
        if (!done.isCompleted) done.complete(const CheckoutClosed());
      },
      (CFErrorResponse error, String orderId) {
        if (!done.isCompleted) {
          done.complete(CheckoutFailed(error.getMessage() ?? 'The payment did not go through.', code: error.getCode()));
        }
      },
    );
    try {
      final session = CFSessionBuilder()
          .setEnvironment(order.sandbox ? CFEnvironment.SANDBOX : CFEnvironment.PRODUCTION)
          .setOrderId(order.orderId)
          .setPaymentSessionId(order.paymentSessionId)
          .build();
      final checkout = CFWebCheckoutPaymentBuilder().setSession(session).build();
      _service.doPayment(checkout);
    } on CFException catch (e) {
      if (!done.isCompleted) done.complete(CheckoutFailed(e.message));
    }
    return done.future;
  }
}

final cashfreeCheckoutProvider = Provider<CashfreeCheckout>((_) => SdkCashfreeCheckout());
