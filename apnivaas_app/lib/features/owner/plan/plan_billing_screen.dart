/// PLAN & BILLING (spec Flow 8, docs/self-signup-api.md §7): where the PG's plan stands, the
/// three plans with their per-month price and saving, and "Pay ₹X" through Razorpay.
///
/// THE APP NEVER SENDS AN AMOUNT. It sends a hostel id and a plan id; `subscription-order`
/// reads the price from `platform_plans` and mints the order. Checkout success activates
/// nothing by itself: the three values the SDK hands back go to `verify`, which checks the
/// signature and the captured payment before extending the plan — and the Razorpay webhook does
/// the same if the app dies in between, so on resume this screen simply reads the status again.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/failure.dart';
import '../../../data/models/people.dart';
import '../../../data/people_providers.dart';
import '../../../data/repositories/people_repository.dart';
import '../../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../owner_format.dart' show money;
import '../widgets/owner_header.dart';

final _date = DateFormat('d MMM yyyy');

String _sentence(Object error) => switch (error) {
      SignupFailure(:final message) => message,
      AppFailure(:final message) => message,
      _ => 'Something went wrong. Please try again.',
    };

/// What the checkout sheet reported. Only [PlanCheckoutPaid] carries anything to verify.
sealed class PlanCheckoutResult {
  const PlanCheckoutResult();
}

final class PlanCheckoutPaid extends PlanCheckoutResult {
  const PlanCheckoutPaid({required this.orderId, required this.paymentId, required this.signature});
  final String orderId;
  final String paymentId;
  final String signature;
}

final class PlanCheckoutCancelled extends PlanCheckoutResult {
  const PlanCheckoutCancelled();
}

final class PlanCheckoutFailed extends PlanCheckoutResult {
  const PlanCheckoutFailed(this.message);
  final String? message;
}

typedef PlanCheckout = Future<PlanCheckoutResult> Function(PlanOrder order);

/// The native sheet. A seam so a widget test can stand in for Razorpay.
final planCheckoutProvider = Provider<PlanCheckout>((_) => razorpayPlanCheckout);

/// Drives the existing razorpay_flutter plugin, UPI first, and always clears its listeners.
Future<PlanCheckoutResult> razorpayPlanCheckout(PlanOrder order) {
  final done = Completer<PlanCheckoutResult>();
  final razorpay = Razorpay();

  void finish(PlanCheckoutResult r) {
    if (!done.isCompleted) done.complete(r);
  }

  razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (Object? r) {
    final ok = r is PaymentSuccessResponse ? r : null;
    final paymentId = ok?.paymentId ?? '';
    final signature = ok?.signature ?? '';
    finish(paymentId.isEmpty || signature.isEmpty
        // A "success" with nothing to verify activates nothing; the webhook may still.
        ? const PlanCheckoutFailed(null)
        : PlanCheckoutPaid(
            orderId: ok?.orderId ?? order.orderId,
            paymentId: paymentId,
            signature: signature,
          ));
  });
  razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (Object? r) {
    final failure = r is PaymentFailureResponse ? r : null;
    finish(failure?.code == Razorpay.PAYMENT_CANCELLED
        ? const PlanCheckoutCancelled()
        : PlanCheckoutFailed(failure?.message));
  });
  razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) => finish(const PlanCheckoutFailed(null)));

  try {
    razorpay.open({
      'key': order.keyId,
      'order_id': order.orderId,
      // Paise, the SERVER'S figure; Razorpay refuses anything that does not match the order.
      'amount': order.amountPaise,
      'currency': order.currency,
      'name': 'Apnivaas',
      'description': '${order.planName} plan · ${order.hostelName}',
      'prefill': {
        if (order.prefillName != null) 'name': order.prefillName,
        if (order.prefillEmail != null) 'email': order.prefillEmail,
      },
      // UPI PREFERRED: a UPI block first, every other method the account has still below it.
      'config': {
        'display': {
          'blocks': {
            'upi': {
              'name': 'Pay with UPI',
              'instruments': [
                {'method': 'upi'},
              ],
            },
          },
          'sequence': ['block.upi'],
          'preferences': {'show_default_blocks': true},
        },
      },
      'retry': {'enabled': true, 'max_count': 1},
      'timeout': 300,
      'theme': {
        'color':
            '#${(ApnivaasColors.forest.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      },
    });
  } catch (_) {
    finish(const PlanCheckoutFailed(null));
  }
  return done.future.whenComplete(razorpay.clear);
}

/// Status line for a plan, the same words everywhere.
({String title, String detail, StatusTone tone}) planStatusWords(PlanStatus s) {
  final end = s.endDate == null ? null : _date.format(s.endDate!);
  return switch (s.state) {
    PlanState.trial => (
        title: 'Free trial',
        detail: end == null ? 'Your first month is free.' : 'Trial ends $end',
        tone: StatusTone.info,
      ),
    PlanState.active => (
        title: 'Active',
        detail: end == null ? 'Your plan is active.' : 'Active until $end',
        tone: StatusTone.success,
      ),
    PlanState.expiring => (
        title: 'Ending soon',
        detail: [
          if (end != null) 'Active until $end',
          if (s.daysLeft != null) '${s.daysLeft} ${s.daysLeft == 1 ? 'day' : 'days'} left',
        ].join(' · '),
        tone: StatusTone.warning,
      ),
    PlanState.expired => (
        title: 'Ended',
        detail: end == null
            ? 'Your plan has ended — choose a plan'
            : 'Ended $end. Your plan has ended — choose a plan',
        tone: StatusTone.error,
      ),
    PlanState.unknown => (title: 'Plan', detail: end == null ? '' : 'Until $end', tone: StatusTone.neutral),
  };
}

class PlanBillingScreen extends ConsumerStatefulWidget {
  const PlanBillingScreen({super.key, required this.hostelId});

  final String hostelId;

  static Route<void> route(String hostelId) =>
      MaterialPageRoute<void>(builder: (_) => PlanBillingScreen(hostelId: hostelId));

  @override
  ConsumerState<PlanBillingScreen> createState() => _PlanBillingScreenState();
}

class _PlanBillingScreenState extends ConsumerState<PlanBillingScreen> {
  String? _selected;
  bool _paying = false;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    // Back from a UPI app, or the app was killed after checkout: the webhook may have activated
    // the plan meanwhile, so read the status again.
    _life = AppLifecycleListener(onResume: () {
      if (mounted) ref.invalidate(planStatusProvider(widget.hostelId));
    });
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  void _say(ScaffoldMessengerState m, String text) => m.showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: Motion.readMessage,
      ));

  Future<void> _pay(PlanOption plan) async {
    if (_paying) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _paying = true);
    try {
      final api = ref.read(peopleApiProvider);
      final order = await api.createPlanOrder(hostelId: widget.hostelId, planId: plan.planId);
      final result = await ref.read(planCheckoutProvider)(order);
      switch (result) {
        case PlanCheckoutCancelled():
          _say(messenger, 'Payment cancelled. Nothing was charged.');
        case PlanCheckoutFailed(:final message):
          _say(
            messenger,
            message == null || message.trim().isEmpty
                ? 'The payment did not go through. If money left your account, your plan will '
                    'switch on automatically within a few minutes.'
                : 'The payment did not go through: ${message.trim()}',
          );
        case PlanCheckoutPaid(:final orderId, :final paymentId, :final signature):
          try {
            final done = await api.verifyPlanPayment(
              orderId: orderId,
              paymentId: paymentId,
              signature: signature,
            );
            final until = done.periodEnd == null ? '' : ' until ${_date.format(done.periodEnd!)}';
            _say(messenger, 'Payment received. Your ${plan.name} plan is active$until.');
          } catch (e) {
            // "processing" and "could not confirm" both end with the webhook switching the plan
            // on; the sentence says so. Show it as it is.
            _say(messenger, _sentence(e));
          }
      }
    } catch (e) {
      _say(messenger, _sentence(e));
    } finally {
      ref.invalidate(planStatusProvider(widget.hostelId));
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(planStatusProvider(widget.hostelId));
    final catalog = ref.watch(planCatalogProvider);
    final plans = catalog.value ?? const <PlanOption>[];
    final selectedId = _selected ??
        (plans.where((p) => p.planId == 'yearly').firstOrNull ?? plans.firstOrNull)?.planId;
    final selected = plans.where((p) => p.planId == selectedId).firstOrNull;
    final pg = watchActiveHostelName(ref) ?? status.value?.hostelName;

    return Scaffold(
      body: Column(
        children: [
          OwnerSubpageHeader(title: 'Plan & billing', subtitle: pg),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(planStatusProvider(widget.hostelId));
                ref.invalidate(planCatalogProvider);
                try {
                  await ref
                      .read(planStatusProvider(widget.hostelId).future)
                      .timeout(const Duration(seconds: 20));
                } catch (_) {}
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: OwnerRhythm.pagePadding,
                children: [
                  switch (status) {
                    AsyncData(:final value) => _StatusCard(status: value),
                    AsyncError(:final error) => EmptyState.error(
                        compact: true,
                        message: _sentence(error),
                        onRetry: () => ref.invalidate(planStatusProvider(widget.hostelId)),
                      ),
                    _ => const ListSkeleton(rows: 1, semanticLabel: 'Loading your plan'),
                  },
                  const SizedBox(height: OwnerRhythm.sectionGap),
                  const SectionHeader(title: 'Choose a plan', size: SectionHeaderSize.card),
                  const SizedBox(height: OwnerRhythm.headingGap),
                  switch (catalog) {
                    AsyncData() when plans.isEmpty => const EmptyState(
                        compact: true,
                        icon: ClayIcons.invoice,
                        title: 'No plans to show',
                        body: 'Plans could not be listed right now. Pull down to try again.',
                      ),
                    AsyncData() => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final p in plans) ...[
                            PlanCard(
                              plan: p,
                              selected: p.planId == selectedId,
                              onTap: _paying ? null : () => setState(() => _selected = p.planId),
                            ),
                            const SizedBox(height: Space.sm),
                          ],
                        ],
                      ),
                    AsyncError(:final error) => EmptyState.error(
                        compact: true,
                        message: _sentence(error),
                        onRetry: () => ref.invalidate(planCatalogProvider),
                      ),
                    _ => const ListSkeleton(rows: 3, semanticLabel: 'Loading plans'),
                  },
                  const SizedBox(height: Space.md),
                  FilledButton(
                    onPressed: selected == null || _paying ? null : () => _pay(selected),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: _paying
                        ? const SizedBox.square(
                            dimension: IconSize.md,
                            child: CircularProgressIndicator(strokeWidth: Strokes.focus),
                          )
                        : Text(selected == null ? 'Pay' : 'Pay ${money(selected.amount)}'),
                  ),
                  const SizedBox(height: Space.sm),
                  const InfoNote(
                    icon: Icons.lock_outline_rounded,
                    message: 'Paid securely through Razorpay — UPI, cards or netbanking. Your plan '
                        'switches on as soon as the payment is confirmed; a new plan starts '
                        'after the current one ends, so no days are lost.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final PlanStatus status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final words = planStatusWords(status);
    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          const ClayIcon(ClayIcons.invoice, size: ClaySize.list),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Your plan', style: t.textTheme.titleMedium),
                    StatusChip(label: words.title, tone: words.tone),
                  ],
                ),
                if (words.detail.isNotEmpty) ...[
                  const SizedBox(height: Space.xxs),
                  Text(words.detail, style: t.textTheme.bodyMedium),
                ],
                if (status.lastPaidAt != null)
                  Text(
                    'Last payment ${_date.format(status.lastPaidAt!)}',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One plan: the per-month price large, what is paid and for how long, and the saving.
class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.plan, required this.selected, required this.onTap});

  final PlanOption plan;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final months = plan.months == 1 ? '1 month' : '${plan.months} months';
    final paid = plan.months == 1
        ? '${money(plan.amount)} every month'
        : '${money(plan.amount)} for $months';
    final free = plan.bonusMonths > 0
        ? ' + ${plan.bonusMonths == 1 ? '1 month' : '${plan.bonusMonths} months'} free'
        : '';
    final ring = selected ? t.colorScheme.primary : t.colorScheme.outlineVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: '${plan.name}, ${money(plan.pricePerMonth)} a month, $paid$free'
          '${plan.savingVsMonthly > 0 ? ', save ${money(plan.savingVsMonthly)}' : ''}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? t.colorScheme.primaryContainer.withValues(alpha: 0.35) : t.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rSurface,
          side: BorderSide(color: ring, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: Space.xs,
                        runSpacing: Space.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(plan.name, style: t.textTheme.titleMedium),
                          if (plan.savingVsMonthly > 0)
                            StatusChip(
                              label: 'Save ${money(plan.savingVsMonthly)}',
                              tone: StatusTone.success,
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.xxs),
                      Text('$paid$free', style: muted),
                    ],
                  ),
                ),
                const SizedBox(width: Space.xs),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(plan.pricePerMonth), style: t.textTheme.titleLarge),
                    Text('a month', style: muted),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Your plan has ended — choose a plan", on the owner's home, only when it has.
class PlanEndedBanner extends ConsumerWidget {
  const PlanEndedBanner({super.key, required this.hostelId});

  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(planStatusProvider(hostelId)).value;
    if (status == null || !status.ended) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
      child: ActionBanner(
        title: 'Your plan has ended — choose a plan',
        message: 'This PG is read-only until a plan is active again.',
        icon: ClayIcons.invoice,
        actionLabel: 'Choose a plan',
        actionSemanticLabel: 'Open plan and billing',
        onAction: () => Navigator.of(context).push(PlanBillingScreen.route(hostelId)),
      ),
    );
  }
}
