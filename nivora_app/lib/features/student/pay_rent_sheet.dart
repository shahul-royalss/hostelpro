library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import '../payments/payments.dart';
import 'rent_payment_controller.dart';
import 'widgets/common.dart';
import 'widgets/format.dart';

/// "Pay rent" — a real Razorpay checkout, and an honest account of what has happened at every
/// moment of it.
///
/// ═══ WHAT THIS SHEET IS CAREFUL ABOUT ═══
/// A payment sheet is the one screen in a hostel app where a comfortable lie is expensive.
/// Razorpay's native checkout closes and reports success while the hostel's ledger still knows
/// nothing about the money — the webhook that credits it is a separate, asynchronous journey to
/// a server this phone cannot see. So this sheet NEVER draws a receipt off the back of the
/// checkout callback. It says "confirming", and it waits for the server's own record before it
/// says anything stronger. [RentPaymentState] carries the distinction; every branch below just
/// renders it.
///
/// The three states people usually collapse into "done" are kept apart here on purpose:
///   received      Razorpay has the money, the rent ledger is not credited yet.
///   credited      both. The only screen that says the rent is settled.
///   unconfirmed   we stopped waiting. The money is fine; the record is late.
/// Each gets different words, because a resident acts differently on each — and in two of the
/// three the most important sentence is "do not pay again".
///
/// ═══ NOTHING GOES TO A BROWSER ═══
/// `razorpay_flutter` opens Razorpay's own native checkout activity. No WebView, no
/// url_launcher, no redirect this app would have to host. That is the product requirement, and
/// it is also what lets the Razorpay key SECRET stay in a Supabase Edge Function instead of
/// anywhere near this APK.
Future<void> showPayRentSheet(
  BuildContext context, {
  required String periodMonth,
  required FeeLedgerRow rent,
}) {
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _PayRentSheet(periodMonth: periodMonth, rent: rent),
  );
}

class _PayRentSheet extends ConsumerWidget {
  const _PayRentSheet({required this.periodMonth, required this.rent});

  final String periodMonth;
  final FeeLedgerRow rent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final state = ref.watch(rentPaymentControllerProvider);

    // Blocks the back gesture AND the drag-to-dismiss while a checkout or a confirmation is in
    // flight. Closing here would not lose the money — the webhook settles it regardless — but it
    // would lose the resident's only view of what is happening to it.
    return PopScope(
      canPop: !state.isBusy,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Paying your rent', style: t.textTheme.titleLarge),
              const SizedBox(height: Space.xxs),
              Text(
                '${rupees(rent.balance)} outstanding for ${monthLabel(periodMonth)}, '
                'of ${rupees(rent.amountDue)}.',
                style: t.textTheme.bodyMedium,
              ),
              const SizedBox(height: Space.md),
              _Body(state: state, periodMonth: periodMonth, rent: rent),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.periodMonth, required this.rent});

  final RentPaymentState state;
  final String periodMonth;
  final FeeLedgerRow rent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    void pay() => ref.read(rentPaymentControllerProvider.notifier).pay();
    void reset() => ref.read(rentPaymentControllerProvider.notifier).reset();

    return switch (state) {
      RentPaymentIdle() => _Offer(rent: rent, periodMonth: periodMonth, onPay: pay),

      RentPaymentOpening() => const _Working(
          title: 'Setting up your payment',
          body: 'Asking your hostel for a secure payment order. This takes a moment.',
        ),

      RentPaymentAtCheckout(:final order) => _Working(
          title: 'Complete the payment',
          body: 'Finish paying in the Razorpay window. Keep the app open until it closes '
              'by itself.',
          order: order,
        ),

      // The checkout is done and the server has said nothing yet. This is the sentence that
      // stops a second payment.
      RentPaymentConfirming(:final order, :final walletName) => _Working(
          title: 'Payment received — confirming',
          body: walletName == null
              ? 'Your payment has gone through. Nivora is waiting for your hostel record to '
                  'update, which usually takes a few seconds. Please do not pay again.'
              : 'Finish the payment in $walletName if you have not already, then come back. '
                  'Nivora is watching for it. Please do not pay again.',
          order: order,
        ),

      // Money taken, ledger not credited. True, and neither of the two easy answers.
      RentPaymentReceived(:final intent) => _Verdict(
          icon: Icons.check_circle_outline_rounded,
          tone: tones.success,
          title: 'Payment received',
          body: 'Your hostel has been paid ${rupees(intent.amountRupees)} for '
              '${monthLabel(intent.periodMonth)}. It has not appeared on your rent ledger yet — '
              'that normally follows within a minute. Do not pay again.',
          reference: intent.razorpayPaymentId ?? intent.razorpayOrderId,
        ),

      // The only branch permitted to say the rent is settled — and therefore the only one that
      // can offer a receipt. `Receipt.forSettledIntent` re-checks `credited_at` for itself and
      // returns null if it is not set, so the button cannot appear a moment early even if this
      // switch were ever rearranged.
      RentPaymentCredited(:final intent) => _Verdict(
          icon: Icons.verified_rounded,
          tone: tones.success,
          title: 'Rent updated',
          body: '${rupees(intent.amountRupees)} received for ${monthLabel(intent.periodMonth)} '
              'and added to your rent record.'
              '${intent.method == null ? '' : ' Paid by ${intent.method}.'}',
          reference: intent.razorpayPaymentId ?? intent.razorpayOrderId,
          receipt: Receipt.forSettledIntent(
            intent,
            // Both are already loaded by the time a payment has settled — this sheet watches
            // the contact card on its first screen and the resident's own row keys every query
            // behind it. Either being null prints a receipt without that line rather than one
            // with a guess on it.
            payerName: ref.watch(myStudentProvider).value?.fullName,
            hostelName: ref.watch(hostelContactsProvider).value?.hostelName,
          ),
        ),

      // We stopped waiting. Not a failure, and it must not be dressed as one.
      RentPaymentUnconfirmed(:final order) => _Verdict(
          icon: Icons.schedule_rounded,
          tone: tones.info,
          title: 'Still confirming',
          body: 'Your payment left your account, but your hostel record has not caught up yet. '
              'It normally lands within a few minutes — pull down on the rent screen to check. '
              'Please do not pay again. If it is still missing tomorrow, show your warden the '
              'reference below.',
          reference: order.orderId,
        ),

      RentPaymentCancelled() => _Retry(
          tone: tones.muted,
          icon: Icons.cancel_outlined,
          title: 'Payment cancelled',
          body: 'Nothing was charged.',
          onRetry: pay,
          onDismiss: reset,
        ),

      RentPaymentFailed(:final message, :final canRetry) => _Retry(
          tone: tones.error,
          icon: Icons.error_outline_rounded,
          title: 'Payment not completed',
          body: message,
          onRetry: canRetry ? pay : null,
          onDismiss: reset,
          // A refusal is exactly the moment to name the other ways to pay.
          showDeskRoutes: true,
        ),
    };
  }
}

/// The starting state: the price, the button, and the alternatives.
class _Offer extends ConsumerWidget {
  const _Offer({required this.rent, required this.periodMonth, required this.onPay});

  final FeeLedgerRow rent;
  final String periodMonth;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final contacts = ref.watch(hostelContactsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: onPay,
          icon: const Icon(Icons.lock_rounded, size: IconSize.md),
          // The figure comes from the ledger row. The SERVER decides what is actually charged —
          // this app cannot name a price to Razorpay even if it wanted to — so if the two ever
          // disagree the payment is refused rather than taken at the wrong amount.
          label: Text('Pay ${rupees(rent.balance)} now'),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'UPI, card, net banking or a wallet, inside this app. The money goes to your '
          'hostel and is recorded against your name automatically.',
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: Space.md),
        Divider(color: t.colorScheme.outlineVariant),
        const SizedBox(height: Space.sm),
        Text('Or pay in person', style: t.textTheme.titleSmall),
        const SizedBox(height: Space.xs),
        AsyncSection<HostelContacts?>(
          value: contacts,
          onRetry: () => ref.invalidate(hostelContactsProvider),
          builder: (card) => _DeskRoute(contacts: card),
        ),
        const SizedBox(height: Space.md),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Any state where the resident's job is to wait. No dismiss button: the sheet is locked.
class _Working extends StatelessWidget {
  const _Working({required this.title, required this.body, this.order});

  final String title;
  final String body;
  final RentOrder? order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (order?.testMode ?? false) ...[
          const _TestModeNote(),
          const SizedBox(height: Space.sm),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.textTheme.titleMedium),
                  const SizedBox(height: Space.xxs),
                  Text(body, style: t.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
      ],
    );
  }
}

/// A settled-enough outcome: something true happened and there is nothing left to do here.
class _Verdict extends StatelessWidget {
  const _Verdict({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    this.reference,
    this.receipt,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String body;

  /// The Razorpay payment or order id. Shown because it is the one string that lets a warden
  /// find this payment when a ledger and a bank statement disagree — and it is selectable so it
  /// can actually be copied rather than transcribed by hand.
  final String? reference;

  /// Non-null ONLY when the server has credited the payment. Every other verdict on this sheet
  /// is about money that is still in flight, and a receipt for money in flight is the one thing
  /// this whole feature is built to refuse.
  final Receipt? receipt;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: IconSize.lg, color: tone),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.textTheme.titleMedium?.copyWith(color: tone)),
                  const SizedBox(height: Space.xxs),
                  Text(body, style: t.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
        if (reference != null) ...[
          const SizedBox(height: Space.sm),
          OutlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('REFERENCE', style: t.textTheme.labelSmall),
                const SizedBox(height: Space.xxs),
                SelectionArea(child: Text(reference!, style: t.textTheme.titleSmall)),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.md),
        if (receipt != null) ...[
          FilledButton.icon(
            onPressed: () => showReceipt(context, receipt!),
            icon: const Icon(Icons.receipt_long_rounded, size: IconSize.md),
            label: const Text('Get your receipt'),
          ),
          const SizedBox(height: Space.xs),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        ] else
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
      ],
    );
  }
}

/// A refusal or a cancellation: say what happened, offer the way back.
class _Retry extends ConsumerWidget {
  const _Retry({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    required this.onDismiss,
    this.onRetry,
    this.showDeskRoutes = false,
  });

  final Color tone;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onDismiss;
  final VoidCallback? onRetry;
  final bool showDeskRoutes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final contacts = showDeskRoutes ? ref.watch(hostelContactsProvider) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: IconSize.lg, color: tone),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.textTheme.titleMedium?.copyWith(color: tone)),
                  const SizedBox(height: Space.xxs),
                  Text(body, style: t.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
        if (contacts != null) ...[
          const SizedBox(height: Space.md),
          AsyncSection<HostelContacts?>(
            value: contacts,
            onRetry: () => ref.invalidate(hostelContactsProvider),
            builder: (card) => _DeskRoute(contacts: card),
          ),
        ],
        const SizedBox(height: Space.md),
        if (onRetry != null) ...[
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: IconSize.md),
            label: const Text('Try again'),
          ),
          const SizedBox(height: Space.xs),
        ],
        OutlinedButton(
          onPressed: () {
            onDismiss();
            Navigator.of(context).maybePop();
          },
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// A test key will not move real money. Saying so is not a debug affordance — a resident who
/// pays with a test card and sees a receipt has been misled.
class _TestModeNote extends StatelessWidget {
  const _TestModeNote();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = context.tones.warning;
    return Row(
      children: [
        Icon(Icons.science_outlined, size: IconSize.md, color: tone),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Text(
            'Test mode — this payment will not move real money.',
            style: t.textTheme.bodySmall?.copyWith(color: tone),
          ),
        ),
      ],
    );
  }
}

/// Paying at the office, which remains a real and often preferred option.
class _DeskRoute extends StatelessWidget {
  const _DeskRoute({required this.contacts});

  final HostelContacts? contacts;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final warden = contacts?.wardenName;
    final wardenPhone = contacts?.wardenPhone;

    return OutlineCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.storefront_rounded, size: IconSize.md, color: t.colorScheme.primary),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('At the hostel office', style: t.textTheme.titleMedium),
                const SizedBox(height: Space.xxs),
                Text(
                  // No warden on the contact card is a real state — the post may be vacant. Do
                  // not print a name that is not there.
                  warden == null
                      ? 'Pay cash, UPI or a bank transfer at the office. Whoever takes it '
                          'records the payment against your name.'
                      : 'Pay $warden in cash, by UPI or by bank transfer. They record it '
                          'against your name and it appears here.',
                  style: t.textTheme.bodyMedium,
                ),
                if (wardenPhone != null) ...[
                  const SizedBox(height: Space.xs),
                  // Selectable: the number is here to be dialled or copied.
                  SelectionArea(
                    child: Text('Warden · $wardenPhone', style: t.textTheme.titleSmall),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
