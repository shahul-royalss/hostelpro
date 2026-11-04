// Cashfree rent in the app (2026-11-04): the tenant's pay screen only ever reports what the
// SERVER says (paid / failed / still pending), the owner's dashboard and account form, and the
// refund sheet. Cashfree itself is behind fakes; the server side is tested in
// db/migrations/2026-11-04-cashfree-rent.test.sql and supabase/functions/_shared/cashfree_test.ts.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/repositories/cashfree_repository.dart';
import 'package:mobile/data/repositories/signup_repository.dart' show SignupFailure;
import 'package:mobile/features/owner/payments/owner_payments_screen.dart';
import 'package:mobile/features/payments/cashfree/cashfree_checkout.dart';
import 'package:mobile/features/payments/cashfree/cashfree_pay_screen.dart';

const _order = CashfreeOrder(orderId: 'apv_2611_test01', paymentSessionId: 's1', amountPaise: 500000, periodMonth: '2026-11', sandbox: true);

RentPayment _row(PayState s, {String? reason}) => RentPayment(
      id: 'p1', orderId: _order.orderId, periodMonth: '2026-11', amountPaise: 500000, status: s,
      settlement: s == PayState.success ? SettleState.splitPending : SettleState.notStarted,
      receiptNo: s == PayState.success ? 'APV-2611-ABCDEF12' : null, paymentId: '777', tenantName: 'Asha',
      pgName: 'Lakeview PG', paidAt: DateTime(2026, 11, 4, 10), failureReason: reason,
    );

class _Api implements CashfreeApi {
  _Api({this.statuses = const [], this.orderError});
  final List<RentPayment?> statuses;
  final SignupFailure? orderError;
  int statusCalls = 0;
  final submitted = <Map<String, String>>[];
  final refunds = <(String, int)>[];
  List<RentPayment> ownerPayments = const [];
  OwnerPaymentAccount? acct;

  @override
  Future<CashfreeOrder> createOrder() async {
    if (orderError != null) throw orderError!;
    return _order;
  }

  @override
  Future<RentPayment?> orderStatus(String orderId) async {
    final i = statusCalls++;
    return statuses.isEmpty ? null : statuses[i < statuses.length ? i : statuses.length - 1];
  }

  @override
  Future<RentGateway> gateway() async => const RentGateway(gateway: 'cashfree', ready: true);
  @override
  Future<List<RentPayment>> myPayments() async => const [];
  @override
  Future<List<RentPayment>> payments({String? hostelId, int limit = 100}) async => ownerPayments;
  @override
  Future<RentPaymentSummary> ownerSummary() async =>
      const RentPaymentSummary(collectedPaise: 500000, verifiedCount: 1, awaitingSettlementPaise: 500000, pendingRentPaise: 300000);
  @override
  Future<List<OwnerSettlement>> settlements() async => const [];
  @override
  Future<({OwnerPaymentAccount? account, bool configured})> account({bool refresh = false}) async => (account: acct, configured: true);
  @override
  Future<OwnerPaymentAccount?> submitAccount(Map<String, String> fields) async {
    submitted.add(fields);
    return null;
  }

  @override
  Future<String> refund({required String paymentId, required int amountPaise, String? note}) async {
    refunds.add((paymentId, amountPaise));
    return 'PENDING';
  }
}

class _Checkout implements CashfreeCheckout {
  _Checkout(this.end);
  final CheckoutEnd end;
  int opened = 0;
  @override
  Future<CheckoutEnd> open(CashfreeOrder order) async {
    opened++;
    return end;
  }
}

Future<void> _pump(WidgetTester tester, Widget home, _Api api, [CashfreeCheckout? checkout]) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      cashfreeApiProvider.overrideWithValue(api),
      if (checkout != null) cashfreeCheckoutProvider.overrideWithValue(checkout),
    ],
    child: MaterialApp(theme: ApnivaasTheme.light(), home: home),
  ));
}

void main() {
  group('tenant pay screen: the server decides', () {
    testWidgets('paid: Cashfree confirmed it, and the receipt is one tap away', (tester) async {
      final api = _Api(statuses: [_row(PayState.initiated), _row(PayState.success)]);
      final checkout = _Checkout(const CheckoutClosed());
      await _pump(tester, const CashfreePayScreen(pollEvery: Duration.zero), api, checkout);
      await tester.pumpAndSettle();
      expect(checkout.opened, 1);
      expect(api.statusCalls, 2, reason: 'the screen asked the server until it said paid');
      expect(find.text('Rent paid'), findsOneWidget);
      expect(find.byKey(const Key('cf-receipt')), findsOneWidget);
      expect(find.textContaining('sandbox'), findsOneWidget);
    });

    testWidgets('a checkout that closes "successfully" is not paid until the server says so', (tester) async {
      final api = _Api(statuses: [_row(PayState.initiated)]);
      await _pump(tester, const CashfreePayScreen(pollEvery: Duration.zero, pollTimes: 3), api, _Checkout(const CheckoutClosed()));
      await tester.pumpAndSettle();
      expect(find.text('Rent paid'), findsNothing);
      expect(find.text('Payment is being confirmed'), findsOneWidget);
      expect(api.statusCalls, 3);
    });

    testWidgets('failed: the reason, and Try again', (tester) async {
      final api = _Api(statuses: [_row(PayState.failed, reason: 'Insufficient balance')]);
      await _pump(tester, const CashfreePayScreen(pollEvery: Duration.zero), api, _Checkout(const CheckoutFailed('Payment failed')));
      await tester.pumpAndSettle();
      expect(find.text('Payment not completed'), findsOneWidget);
      expect(find.text('Insufficient balance'), findsOneWidget);
      expect(find.byKey(const Key('cf-retry')), findsOneWidget);
    });

    testWidgets('an owner who has not set up Cashfree: the server says so, nothing opens', (tester) async {
      final api = _Api(orderError: const SignupFailure('Online rent payment is not set up for your PG yet. Please pay your PG directly.'));
      final checkout = _Checkout(const CheckoutClosed());
      await _pump(tester, const CashfreePayScreen(pollEvery: Duration.zero), api, checkout);
      await tester.pumpAndSettle();
      expect(checkout.opened, 0);
      expect(find.textContaining('not set up for your PG'), findsOneWidget);
    });
  });

  group('owner', () {
    testWidgets('dashboard: account, figures, payments, and a refund through the server', (tester) async {
      final api = _Api()..ownerPayments = [_row(PayState.success)];
      await _pump(tester, const OwnerPaymentsScreen(), api);
      await tester.pumpAndSettle();
      expect(find.text('Turn on online rent'), findsOneWidget);
      expect(find.text('Collected'), findsOneWidget);
      expect(find.text('Awaiting settlement'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Asha'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Asha'), findsOneWidget);

      await tester.tap(find.text('Asha'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cf-refund-open')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cf-refund-amount')), '1000');
      await tester.tap(find.byKey(const Key('cf-refund-confirm')));
      await tester.pumpAndSettle();
      expect(api.refunds, [('p1', 100000)]);
    });

    testWidgets('a refund above what was paid is refused before it is sent', (tester) async {
      final api = _Api()..ownerPayments = [_row(PayState.success)];
      await _pump(tester, const OwnerPaymentsScreen(), api);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Asha'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Asha'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cf-refund-open')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cf-refund-amount')), '6000');
      await tester.tap(find.byKey(const Key('cf-refund-confirm')));
      await tester.pumpAndSettle();
      expect(api.refunds, isEmpty);
      expect(find.textContaining('Enter between'), findsOneWidget);
    });

    testWidgets('account form: a bad PAN stays on the phone; a good one goes, upper-cased', (tester) async {
      final api = _Api();
      await _pump(tester, const PaymentAccountForm(), api);
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Asha Rao');
      await tester.enterText(fields.at(1), 'ABC12');
      await tester.enterText(fields.at(2), 'asha@okhdfcbank');
      await tester.enterText(fields.at(4), 'asha@example.com');
      await tester.enterText(fields.at(5), '9876543210');
      await tester.ensureVisible(find.byKey(const Key('cf-account-submit')));
      await tester.tap(find.byKey(const Key('cf-account-submit')));
      await tester.pumpAndSettle();
      expect(api.submitted, isEmpty);
      expect(find.text('Enter your 10-character PAN'), findsOneWidget);

      await tester.enterText(fields.at(1), 'abcde1234f');
      await tester.ensureVisible(find.byKey(const Key('cf-account-submit')));
      await tester.tap(find.byKey(const Key('cf-account-submit')));
      await tester.pumpAndSettle();
      expect(api.submitted.single['pan'], 'ABCDE1234F');
      expect(api.submitted.single['upi_vpa'], 'asha@okhdfcbank');
    });
  });
}
