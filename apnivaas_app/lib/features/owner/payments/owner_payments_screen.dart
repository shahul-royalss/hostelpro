/// Owner → Online rent (Cashfree, 2026-11-04).
///
/// The owner's Cashfree account (where their rent is settled: their own UPI ID, verified by
/// Cashfree), the figures (collected, pending, awaiting settlement, settled, failed), every
/// tenant's online payment with its payment and settlement state, the settlement history, and a
/// refund on any successful payment. Every figure comes from the server; nothing is computed
/// from what this screen typed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/cashfree_repository.dart';
import '../../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../../common/form_parts.dart';
import '../../payments/cashfree/cashfree_pay_screen.dart' show RentPaymentTile;
import '../../student/widgets/format.dart' show monthLabel, rupees;

String _money(int paise) => rupees(paise / 100);

class OwnerPaymentsScreen extends ConsumerWidget {
  const OwnerPaymentsScreen({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const OwnerPaymentsScreen());

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(ownerPaymentAccountProvider);
    ref.invalidate(ownerRentSummaryProvider);
    ref.invalidate(ownerRentPaymentsProvider);
    ref.invalidate(ownerSettlementsProvider);
    await ref.read(ownerRentSummaryProvider.future).catchError((_) => const RentPaymentSummary());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final account = ref.watch(ownerPaymentAccountProvider);
    final summary = ref.watch(ownerRentSummaryProvider).value;
    final payments = ref.watch(ownerRentPaymentsProvider);
    final settlements = ref.watch(ownerSettlementsProvider).value ?? const <OwnerSettlement>[];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Online rent'))),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.huge),
          children: [
            switch (account) {
              AsyncData(:final value) => _AccountCard(account: value.account, configured: value.configured),
              AsyncError(:final error) => FormNote(error is SignupFailure ? error.message : 'Your payment account could not be loaded.'),
              _ => const Padding(padding: EdgeInsets.all(Space.lg), child: Center(child: CircularProgressIndicator())),
            },
            const SizedBox(height: Space.lg),
            const SectionHeader(title: 'This month and overall'),
            const SizedBox(height: Space.sm),
            // Rows that grow with their text (a fixed-height grid clipped captions at large text).
            for (final pair in <List<Widget>>[
              [
                StatTile(label: 'Collected', value: _money(summary?.collectedPaise ?? 0),
                    caption: '${_money(summary?.collectedThisMonthPaise ?? 0)} this month'),
                StatTile(label: 'Pending rent', value: _money(summary?.pendingRentPaise ?? 0), caption: 'Still owed this month'),
              ],
              [
                StatTile(label: 'Awaiting settlement', value: _money(summary?.awaitingSettlementPaise ?? 0),
                    caption: 'Paid, on its way to your UPI'),
                StatTile(label: 'Settled', value: _money(summary?.settledPaise ?? 0), caption: 'Reached your UPI ID'),
              ],
              [
                StatTile(label: 'Verified payments', value: '${summary?.verifiedCount ?? 0}', caption: 'Confirmed by Cashfree'),
                StatTile(
                  label: 'Failed settlements',
                  value: '${summary?.failedSettlements ?? 0}',
                  caption: (summary?.needsAttention ?? 0) > 0
                      ? '${summary!.needsAttention} need attention'
                      : 'Cashfree retries or tells you',
                ),
              ],
            ]) ...[
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: pair[0]),
                  const SizedBox(width: Space.xs),
                  Expanded(child: pair[1]),
                ]),
              ),
              const SizedBox(height: Space.xs),
            ],
            const SizedBox(height: Space.lg),
            const SectionHeader(title: 'Payments'),
            const SizedBox(height: Space.sm),
            switch (payments) {
              AsyncData(:final value) when value.isEmpty =>
                Text('No online payments yet.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              AsyncData(:final value) => Column(children: [
                  for (final p in value) ...[
                    RentPaymentTile(
                      payment: p,
                      showTenant: true,
                      showSettlement: true,
                      onTap: () => showPaymentDetails(context, p, canRefund: true),
                    ),
                    const SizedBox(height: Space.xs),
                  ],
                ]),
              AsyncError(:final error) => FormNote(error is SignupFailure ? error.message : 'Payments could not be loaded.'),
              _ => const Center(child: CircularProgressIndicator()),
            },
            if (settlements.isNotEmpty) ...[
              const SizedBox(height: Space.lg),
              const SectionHeader(title: 'Settlements to your UPI ID'),
              const SizedBox(height: Space.sm),
              for (final s in settlements) ...[
                FlatSurface(
                  borderRadius: Radii.rSurface,
                  padding: const EdgeInsets.all(Space.md),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.amount == null ? 'Settlement ${s.settlementId}' : rupees(s.amount!), style: t.textTheme.titleMedium),
                        Text(
                          [
                            if (s.utr != null) 'UTR ${s.utr}',
                            if (s.settledAt != null) MaterialLocalizations.of(context).formatMediumDate(s.settledAt!),
                            if (s.reason != null) s.reason!,
                          ].join(' · '),
                          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                        ),
                      ]),
                    ),
                    StatusChip(
                      label: switch (s.status) { 'SUCCESS' => 'Settled', 'FAILED' => 'Failed', 'REVERSED' => 'Reversed', _ => 'In progress' },
                      tone: switch (s.status) { 'SUCCESS' => StatusTone.success, 'FAILED' || 'REVERSED' => StatusTone.error, _ => StatusTone.info },
                    ),
                  ]),
                ),
                const SizedBox(height: Space.xs),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account, required this.configured});
  final OwnerPaymentAccount? account;
  final bool configured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final a = account;
    final (title, body, tone) = a == null
        ? ('Turn on online rent', 'Add your UPI ID and PAN. Cashfree verifies them, then tenants can pay rent in the app and it is settled straight to your UPI ID.', StatusTone.info)
        : a.verified
            ? ('Online rent is on', 'Rent is settled to ${a.upiVpa}${a.scheduleMessage == null ? '' : ' · ${a.scheduleMessage}'}.', StatusTone.success)
            : a.rejected
                ? ('Cashfree could not verify these details', a.lastError ?? 'Check your UPI ID and PAN, then submit again.', StatusTone.error)
                : ('Cashfree is verifying your details', 'Usually a few minutes. Tenants can pay online once it is done. UPI: ${a.upiVpa}', StatusTone.warning);
    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: const EdgeInsets.all(Space.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(context.tr(title), style: t.textTheme.titleMedium)),
          StatusChip(label: a == null ? 'Not set up' : a.verified ? 'Verified' : a.rejected ? 'Rejected' : 'Pending', tone: tone),
        ]),
        const SizedBox(height: Space.xs),
        Text(body, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        if (!configured) ...[
          const SizedBox(height: Space.xs),
          const FormNote('Cashfree is not connected on the server yet.', tone: FormNoteTone.warning),
        ],
        const SizedBox(height: Space.sm),
        Row(children: [
          Expanded(
            child: BusyFilledButton(
              key: const Key('cf-account-edit'),
              label: a == null ? 'Set up' : 'Change details',
              onPressed: configured
                  ? () async {
                      final saved = await Navigator.of(context).push<bool>(PaymentAccountForm.route(a));
                      if (saved == true) ref.invalidate(ownerPaymentAccountProvider);
                    }
                  : null,
            ),
          ),
          if (a != null && !a.verified) ...[
            const SizedBox(width: Space.xs),
            TextButton(
              onPressed: () async {
                try {
                  await ref.read(cashfreeApiProvider).account(refresh: true);
                } on SignupFailure catch (_) {}
                ref.invalidate(ownerPaymentAccountProvider);
              },
              child: Text(context.tr('Check status')),
            ),
          ],
        ]),
      ]),
    );
  }
}

/// The owner's Cashfree vendor details. The PAN is sent to Cashfree and never kept by Apnivaas.
class PaymentAccountForm extends ConsumerStatefulWidget {
  const PaymentAccountForm({super.key, this.existing});
  final OwnerPaymentAccount? existing;

  static Route<bool> route(OwnerPaymentAccount? existing) =>
      MaterialPageRoute(builder: (_) => PaymentAccountForm(existing: existing));

  @override
  ConsumerState<PaymentAccountForm> createState() => _PaymentAccountFormState();
}

class _PaymentAccountFormState extends ConsumerState<PaymentAccountForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.legalName);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _vpa = TextEditingController(text: widget.existing?.upiVpa);
  late final _holder = TextEditingController(text: widget.existing?.beneficiaryName);
  final _pan = TextEditingController();
  late final _gst = TextEditingController(text: widget.existing?.gstin);
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _vpa, _holder, _pan, _gst]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      await ref.read(cashfreeApiProvider).submitAccount({
        'legal_name': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'upi_vpa': _vpa.text.trim(),
        'beneficiary_name': _holder.text.trim(),
        'pan': _pan.text.trim().toUpperCase(),
        if (_gst.text.trim().isNotEmpty) 'gstin': _gst.text.trim().toUpperCase(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    String? need(String? v, String message) => (v == null || v.trim().isEmpty) ? message : null;
    InputDecoration deco(String label, String key) => InputDecoration(labelText: context.tr(label), errorText: _fieldErrors[key]);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr(widget.existing == null ? 'Turn on online rent' : 'Change payment details'))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(Space.md),
          children: [
            InfoNote(
              message: widget.existing == null
                  ? 'Cashfree settles your tenants\' rent straight to this UPI ID. It checks the details first, and it needs your PAN for that. Apnivaas keeps only the last four characters.'
                  : 'Changing these pauses online rent until Cashfree verifies the new details.',
            ),
            const SizedBox(height: Space.md),
            TextFormField(controller: _name, enabled: !_busy, textCapitalization: TextCapitalization.words,
                decoration: deco('Your name as on PAN', 'legal_name'), validator: (v) => need(v, 'Enter your name')),
            const SizedBox(height: Space.sm),
            TextFormField(controller: _pan, enabled: !_busy, textCapitalization: TextCapitalization.characters,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(10)],
                decoration: deco('PAN', 'pan'),
                validator: (v) => RegExp(r'^[A-Za-z]{5}[0-9]{4}[A-Za-z]$').hasMatch(v?.trim() ?? '') ? null : 'Enter your 10-character PAN'),
            const SizedBox(height: Space.sm),
            TextFormField(controller: _vpa, enabled: !_busy, keyboardType: TextInputType.emailAddress, autocorrect: false,
                decoration: deco('UPI ID for settlements', 'upi_vpa'),
                validator: (v) => (v ?? '').contains('@') ? null : 'Enter your UPI ID, like name@okhdfcbank'),
            const SizedBox(height: Space.sm),
            TextFormField(controller: _holder, enabled: !_busy, textCapitalization: TextCapitalization.words,
                decoration: deco('Name on the UPI account', 'beneficiary_name')),
            const SizedBox(height: Space.sm),
            TextFormField(controller: _email, enabled: !_busy, keyboardType: TextInputType.emailAddress, autocorrect: false,
                decoration: deco('Email', 'email'), validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email'),
            const SizedBox(height: Space.sm),
            TextFormField(controller: _phone, enabled: !_busy, keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: deco('Mobile number', 'phone'), validator: (v) => need(v, 'Enter your mobile number')),
            const SizedBox(height: Space.sm),
            TextFormField(controller: _gst, enabled: !_busy, textCapitalization: TextCapitalization.characters,
                decoration: deco('GSTIN (optional)', 'gstin')),
            if (_error != null) ...[const SizedBox(height: Space.sm), FormNote(_error!)],
            const SizedBox(height: Space.lg),
            BusyFilledButton(key: const Key('cf-account-submit'), label: 'Send to Cashfree for verification', busy: _busy, onPressed: _busy ? null : _submit),
            const SizedBox(height: Space.xs),
            Text(
              context.tr('Your details go to Cashfree Payments, which holds them under its own privacy policy.'),
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// A payment's details, with Refund for the owner (or the Super Admin) on a successful payment.
Future<void> showPaymentDetails(BuildContext context, RentPayment p, {required bool canRefund}) {
  return showApnivaasSheet<void>(
    context: context,
    title: '${p.tenantName ?? 'Tenant'} · ${monthLabel(p.periodMonth)}',
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final t = Theme.of(ctx);
      String row(String k, String? v) => v == null || v.isEmpty ? '' : '$k: $v';
      final lines = [
        row('Amount', _money(p.amountPaise)),
        row('Receipt', p.receiptNo),
        row('Cashfree payment ID', p.paymentId),
        row('Bank reference', p.bankReference),
        row('Order', p.orderId),
        if (p.refundedPaise > 0) row('Refunded', _money(p.refundedPaise)),
        if (p.settlementUtr != null) row('Settlement UTR', p.settlementUtr),
        if (p.creditError != null) row('Not added to rent', p.creditError),
        if (p.overpaid) 'More than was owed for this month: refund the extra.',
        if (p.failureReason != null && !p.isFinal) row('Reason', p.failureReason),
      ].where((l) => l.isNotEmpty);
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: Space.xxs), child: SelectableText(l, style: t.textTheme.bodyMedium)),
          if (canRefund && p.refundablePaise >= 100) ...[
            const SizedBox(height: Space.md),
            BusyFilledButton(
              key: const Key('cf-refund-open'),
              label: 'Refund',
              danger: true,
              onPressed: () async {
                Navigator.of(ctx).pop();
                await showRefundSheet(context, p);
              },
            ),
          ],
        ]),
      );
    }),
  );
}

/// Refund all or part of a payment. The server checks who may, and how much is left.
Future<void> showRefundSheet(BuildContext context, RentPayment p) {
  return showApnivaasSheet<void>(
    context: context,
    title: 'Refund ${p.tenantName ?? 'this payment'}',
    subtitle: 'Up to ${_money(p.refundablePaise)}. It goes back to the tenant\'s account and comes out of your Cashfree settlement.',
    builder: (ctx) => _RefundForm(payment: p),
  );
}

class _RefundForm extends ConsumerStatefulWidget {
  const _RefundForm({required this.payment});
  final RentPayment payment;

  @override
  ConsumerState<_RefundForm> createState() => _RefundFormState();
}

class _RefundFormState extends ConsumerState<_RefundForm> {
  late final _amount = TextEditingController(text: (widget.payment.refundablePaise / 100).toStringAsFixed(2));
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _refund() async {
    final rupeesValue = double.tryParse(_amount.text.trim());
    final paise = rupeesValue == null ? 0 : (rupeesValue * 100).round();
    if (paise < 100 || paise > widget.payment.refundablePaise) {
      setState(() => _error = 'Enter between ₹1 and ${_money(widget.payment.refundablePaise)}.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await ref.read(cashfreeApiProvider).refund(paymentId: widget.payment.id, amountPaise: paise, note: _note.text);
      if (!mounted) return;
      ref.invalidate(ownerRentPaymentsProvider);
      ref.invalidate(ownerRentSummaryProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(status == 'SUCCESS' ? 'Refunded.' : 'Refund sent to Cashfree. It usually completes within a few days.'),
      ));
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          key: const Key('cf-refund-amount'),
          controller: _amount,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: context.tr('Amount (₹)')),
        ),
        const SizedBox(height: Space.sm),
        TextField(controller: _note, enabled: !_busy, maxLength: 100, decoration: InputDecoration(labelText: context.tr('Reason (optional)'))),
        if (_error != null) ...[FormNote(_error!), const SizedBox(height: Space.xs)],
        BusyFilledButton(key: const Key('cf-refund-confirm'), label: 'Refund now', danger: true, busy: _busy, onPressed: _busy ? null : _refund),
      ]),
    );
  }
}
