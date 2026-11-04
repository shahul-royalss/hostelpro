/// Paying rent through Cashfree (2026-11-04): open the order, hand over to Cashfree's checkout
/// (any UPI app), then wait for the SERVER to confirm. The screen never decides the outcome: it
/// asks cashfree-order for the order's status, which re-reads it from Cashfree's API, and shows
/// what the database then says — paid with a receipt, failed with a reason, or still pending.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/cashfree_repository.dart';
import '../../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../../common/form_parts.dart';
import '../../student/widgets/format.dart' show monthLabel, rupees;
import '../receipt.dart';
import '../receipt_screen.dart';
import 'cashfree_checkout.dart';

enum _Phase { starting, checkout, confirming, success, failed, pending }

class CashfreePayScreen extends ConsumerStatefulWidget {
  const CashfreePayScreen({super.key, this.pollEvery = const Duration(seconds: 2), this.pollTimes = 20});

  final Duration pollEvery;
  final int pollTimes;

  static Route<bool> route() => MaterialPageRoute(builder: (_) => const CashfreePayScreen());

  @override
  ConsumerState<CashfreePayScreen> createState() => _CashfreePayScreenState();
}

class _CashfreePayScreenState extends ConsumerState<CashfreePayScreen> {
  _Phase _phase = _Phase.starting;
  CashfreeOrder? _order;
  RentPayment? _payment;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.starting;
      _message = null;
    });
    final api = ref.read(cashfreeApiProvider);
    try {
      final order = await api.createOrder();
      if (!mounted) return;
      setState(() {
        _order = order;
        _phase = _Phase.checkout;
      });
      final end = await ref.read(cashfreeCheckoutProvider).open(order);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.confirming;
        if (end is CheckoutFailed) _message = end.message;
      });
      await _confirm(order.orderId);
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _message = f.message;
      });
    }
  }

  /// Polls the server's view of the order. Each call re-reads Cashfree on the server.
  Future<void> _confirm(String orderId) async {
    final api = ref.read(cashfreeApiProvider);
    RentPayment? last;
    for (var i = 0; i < widget.pollTimes && mounted; i++) {
      try {
        last = await api.orderStatus(orderId);
      } on SignupFailure {
        last = null;
      }
      if (!mounted) return;
      final s = last?.status;
      if (s == PayState.success || s == PayState.refunded) {
        setState(() {
          _payment = last;
          _phase = _Phase.success;
        });
        return;
      }
      // A failed or dropped attempt on a still-open order may be retried in the same checkout,
      // so only a SDK-reported failure plus a failed server state ends the wait early.
      if ((s == PayState.failed || s == PayState.cancelled) && _message != null) {
        setState(() {
          _payment = last;
          _phase = _Phase.failed;
          _message = last?.failureReason ?? _message;
        });
        return;
      }
      await Future<void>.delayed(widget.pollEvery);
    }
    if (!mounted) return;
    setState(() {
      _payment = last;
      _phase = (last?.status == PayState.failed || last?.status == PayState.cancelled) ? _Phase.failed : _Phase.pending;
      if (_phase == _Phase.failed) _message = last?.failureReason ?? _message ?? 'The payment did not go through.';
    });
  }

  void _openReceipt(RentPayment p) {
    final receipt = Receipt.forOnlinePayment(
      receiptNo: p.receiptNo ?? p.orderId,
      amount: p.amountPaise / 100,
      periodMonth: p.periodMonth,
      paidAt: p.paidAt ?? DateTime.now(),
      paymentId: p.paymentId ?? p.orderId,
      bankReference: p.bankReference,
      refunded: p.refundedPaise / 100,
      payerName: p.tenantName,
      hostelName: p.pgName,
    );
    if (receipt == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReceiptScreen(receipt: receipt)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final amount = _payment?.amountPaise ?? _order?.amountPaise;
    final busy = _phase == _Phase.starting || _phase == _Phase.checkout || _phase == _Phase.confirming;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('Pay rent')), automaticallyImplyLeading: !busy),
        body: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            const SizedBox(height: Space.lg),
            Center(
              child: switch (_phase) {
                _Phase.success => const ClayIcon(ClayIcons.success, size: 112),
                _Phase.failed => Icon(Icons.error_outline_rounded, size: 88, color: t.colorScheme.error),
                _Phase.pending => Icon(Icons.hourglass_top_rounded, size: 88, color: t.colorScheme.primary),
                _ => const SizedBox.square(dimension: 72, child: CircularProgressIndicator(strokeWidth: 3)),
              },
            ),
            const SizedBox(height: Space.lg),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                context.tr(switch (_phase) {
                  _Phase.starting => 'Setting up your payment…',
                  _Phase.checkout => 'Complete the payment in Cashfree',
                  _Phase.confirming => 'Confirming your payment…',
                  _Phase.success => 'Rent paid',
                  _Phase.failed => 'Payment not completed',
                  _Phase.pending => 'Payment is being confirmed',
                }),
                textAlign: TextAlign.center,
                style: t.textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: Space.xs),
            if (amount != null)
              Text(
                '${rupees(amount / 100)} · ${monthLabel(_payment?.periodMonth ?? _order?.periodMonth ?? '')}',
                textAlign: TextAlign.center,
                style: t.textTheme.titleMedium,
              ),
            const SizedBox(height: Space.sm),
            Text(
              context.tr(switch (_phase) {
                _Phase.starting => 'Apnivaas is opening a secure Cashfree payment for exactly what you owe.',
                _Phase.checkout => 'Choose PhonePe, Google Pay, Paytm, BHIM or any UPI app.',
                _Phase.confirming => 'Cashfree is telling Apnivaas whether the money arrived. This takes a few seconds.',
                _Phase.success => 'Cashfree confirmed it and your rent is updated. Your PG has been told.',
                _Phase.failed => 'No money was taken for this attempt. If your bank shows a debit, it is returned automatically.',
                _Phase.pending => 'Your bank has not confirmed yet. Your rent updates by itself when it does, and you will get a notification.',
              }),
              textAlign: TextAlign.center,
              style: muted,
            ),
            if (_phase == _Phase.failed && _message != null) ...[
              const SizedBox(height: Space.md),
              FormNote(_message!),
            ],
            if (_order?.sandbox == true) ...[
              const SizedBox(height: Space.md),
              const InfoNote(message: 'Test mode: this uses Cashfree sandbox, and no real money moves.'),
            ],
            const SizedBox(height: Space.xl),
            if (_phase == _Phase.success && _payment != null) ...[
              BusyFilledButton(
                key: const Key('cf-receipt'),
                label: 'See and share receipt',
                icon: Icons.receipt_long_rounded,
                onPressed: () => _openReceipt(_payment!),
              ),
              const SizedBox(height: Space.xs),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(context.tr('Done'))),
            ] else if (_phase == _Phase.failed) ...[
              BusyFilledButton(key: const Key('cf-retry'), label: 'Try again', onPressed: _start),
              const SizedBox(height: Space.xs),
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.tr('Close'))),
            ] else if (_phase == _Phase.pending) ...[
              BusyFilledButton(
                label: 'Check again',
                onPressed: _order == null ? null : () {
                  setState(() => _phase = _Phase.confirming);
                  _confirm(_order!.orderId);
                },
              ),
              const SizedBox(height: Space.xs),
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.tr('Close'))),
            ],
          ],
        ),
      ),
    );
  }
}

/// The tenant's Cashfree payments, newest first, each opening its receipt once paid.
class RentPaymentHistoryScreen extends ConsumerWidget {
  const RentPaymentHistoryScreen({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const RentPaymentHistoryScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myRentPaymentsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Online payments'))),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myRentPaymentsProvider.future),
        child: switch (async) {
          AsyncData(:final value) when value.isEmpty => ListView(children: const [
              SizedBox(height: Space.huge),
              EmptyState(title: 'No online payments yet', body: 'Rent you pay in the app shows here with its receipt.', icon: ClayIcons.money),
            ]),
          AsyncData(:final value) => ListView(
              padding: const EdgeInsets.all(Space.md),
              children: [
                for (final p in value) ...[
                  RentPaymentTile(
                    payment: p,
                    onTap: p.isFinal
                        ? () {
                            final r = Receipt.forOnlinePayment(
                              receiptNo: p.receiptNo ?? p.orderId,
                              amount: p.amountPaise / 100,
                              periodMonth: p.periodMonth,
                              paidAt: p.paidAt ?? p.createdAt ?? DateTime.now(),
                              paymentId: p.paymentId ?? p.orderId,
                              bankReference: p.bankReference,
                              refunded: p.refundedPaise / 100,
                              payerName: p.tenantName,
                              hostelName: p.pgName,
                            );
                            if (r != null) {
                              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReceiptScreen(receipt: r)));
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: Space.xs),
                ],
              ],
            ),
          AsyncError(:final error) => ListView(children: [
              const SizedBox(height: Space.huge),
              EmptyState.error(
                message: error is SignupFailure ? error.message : 'Your payments could not be loaded.',
                onRetry: () => ref.invalidate(myRentPaymentsProvider),
              ),
            ]),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

/// One payment: month and amount, its payment state, and (for owners) its settlement state.
class RentPaymentTile extends StatelessWidget {
  const RentPaymentTile({super.key, required this.payment, this.onTap, this.showSettlement = false, this.showTenant = false});

  final RentPayment payment;
  final VoidCallback? onTap;
  final bool showSettlement;
  final bool showTenant;

  static (String, StatusTone) payLabel(PayState s) => switch (s) {
        PayState.success => ('Paid', StatusTone.success),
        PayState.refunded => ('Refunded', StatusTone.neutral),
        PayState.failed => ('Failed', StatusTone.error),
        PayState.cancelled => ('Cancelled', StatusTone.neutral),
        PayState.pending => ('Pending', StatusTone.warning),
        PayState.initiated => ('Started', StatusTone.neutral),
      };

  static (String, StatusTone) settleLabel(SettleState s) => switch (s) {
        SettleState.settled => ('Settled', StatusTone.success),
        SettleState.settlementFailed => ('Settlement failed', StatusTone.error),
        SettleState.splitPending || SettleState.splitCreated || SettleState.settlementPending =>
          ('Awaiting settlement', StatusTone.info),
        SettleState.notStarted => ('Not settled', StatusTone.neutral),
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (pay, payTone) = payLabel(payment.status);
    final (settle, settleTone) = settleLabel(payment.settlement);
    final title = showTenant && payment.tenantName != null ? payment.tenantName! : monthLabel(payment.periodMonth);
    final subtitle = [
      if (showTenant) monthLabel(payment.periodMonth),
      if (payment.receiptNo != null) payment.receiptNo!,
      if (payment.refundedPaise > 0) 'Refunded ${rupees(payment.refundedPaise / 100)}',
    ].join(' · ');
    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: const EdgeInsets.all(Space.md),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.textTheme.titleMedium),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: Space.xxs),
                Wrap(spacing: Space.xs, runSpacing: Space.xxs, children: [
                  StatusChip(label: pay, tone: payTone),
                  if (showSettlement && payment.isFinal) StatusChip(label: settle, tone: settleTone),
                  if (showSettlement && (payment.overpaid || payment.creditError != null))
                    const StatusChip(label: 'Needs attention', tone: StatusTone.warning),
                ]),
              ],
            ),
          ),
          Text(rupees(payment.amountPaise / 100), style: t.textTheme.titleMedium),
        ],
      ),
    );
  }
}
