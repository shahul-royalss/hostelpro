/// Tenant → Pay rent → Pay with UPI app (R9).
///
/// Opens the tenant's UPI app with a `upi://pay` intent to the owner's UPI ID, then asks for
/// the UTR and files a payment claim. The intent's answer is never trusted: the rent shows as
/// paid only after a warden or the owner confirms the claim on the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/upi.dart';
import '../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../data/repositories/upi_repository.dart';
import '../../shared/clay/clay.dart';
import '../common/form_parts.dart';
import 'stay_screens.dart' show stayErrorText;
import 'widgets/format.dart' show monthLabel, rupees;

/// The button under Pay now; hidden until the PG has set up UPI.
class PayWithUpiButton extends ConsumerWidget {
  const PayWithUpiButton({super.key, required this.amount, required this.periodMonth});

  /// Suggested amount (the balance); the tenant may change it.
  final double amount;
  final String periodMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(upiSettingsProvider(null)).value;
    if (settings == null) return const SizedBox.shrink();
    final pending = (ref.watch(myPaymentClaimsProvider).value ?? const <PaymentClaim>[])
        .where((c) => c.status == ClaimStatus.pending)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          onPressed: () async {
            final sent = await showApnivaasSheet<bool>(
              context: context,
              builder: (_) =>
                  UpiPaySheet(settings: settings, amount: amount, periodMonth: periodMonth),
            );
            if (sent == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                behavior: SnackBarBehavior.floating,
                duration: Motion.readMessage,
                content: Text('Sent. Your warden or owner confirms it after checking their UPI '
                    'app; your rent updates then.'),
              ));
            }
          },
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('Pay with UPI app'),
        ),
        for (final c in pending) ...[
          const SizedBox(height: Space.xs),
          _PendingClaim(claim: c),
        ],
      ],
    );
  }
}

class _PendingClaim extends ConsumerStatefulWidget {
  const _PendingClaim({required this.claim});
  final PaymentClaim claim;

  @override
  ConsumerState<_PendingClaim> createState() => _PendingClaimState();
}

class _PendingClaimState extends ConsumerState<_PendingClaim> {
  bool _busy = false;

  Future<void> _cancel() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(upiApiProvider).cancelClaim(widget.claim.claimId);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(stayErrorText(e)),
      ));
    } finally {
      ref.invalidate(myPaymentClaimsProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.claim;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoNote(
          icon: Icons.hourglass_top_rounded,
          message: '${rupees(c.amount)} by UPI for ${monthLabel(c.periodMonth)} (UTR ${c.utr}) '
              'is waiting for confirmation.',
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: _busy ? null : _cancel,
            child: Text(_busy ? 'Cancelling…' : 'Cancel this report'),
          ),
        ),
      ],
    );
  }
}

enum _Step { pay, utr }

class UpiPaySheet extends ConsumerStatefulWidget {
  const UpiPaySheet({
    super.key,
    required this.settings,
    required this.amount,
    required this.periodMonth,
  });

  final UpiSettings settings;
  final double amount;
  final String periodMonth;

  @override
  ConsumerState<UpiPaySheet> createState() => _UpiPaySheetState();
}

class _UpiPaySheetState extends ConsumerState<UpiPaySheet> {
  late final _amount = TextEditingController(
      text: widget.amount % 1 == 0
          ? widget.amount.toStringAsFixed(0)
          : widget.amount.toStringAsFixed(2));
  final _utr = TextEditingController();
  _Step _step = _Step.pay;
  String? _amountError;
  String? _utrError;
  String? _note;
  FormNoteTone _noteTone = FormNoteTone.warning;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _utr.dispose();
    super.dispose();
  }

  double? get _parsedAmount {
    final v = double.tryParse(_amount.text.replaceAll(',', '').trim());
    return (v == null || v <= 0 || v > 10000000) ? null : v;
  }

  /// Opens [app] (or the chooser when null). Whatever comes back, the next step is the UTR.
  Future<void> _open([UpiApp? app]) async {
    final amount = _parsedAmount;
    if (amount == null) {
      setState(() => _amountError = 'Enter a valid amount.');
      return;
    }
    setState(() {
      _amountError = null;
      _busy = true;
    });
    final s = widget.settings;
    final pg = (s.hostelName ?? 'PG').trim();
    final uri = buildUpiUri(
      vpa: s.vpa,
      payeeName: s.payeeName,
      amount: amount,
      note: 'Rent ${monthLabel(widget.periodMonth)} $pg',
    );
    final result = await ref.read(upiLauncherProvider).launch(uri, app: app);
    if (!mounted) return;
    final hint = result.response;
    if (hint.utr != null && _utr.text.trim().isEmpty) _utr.text = hint.utr!;
    setState(() {
      _busy = false;
      _step = _Step.utr;
      _noteTone = FormNoteTone.warning;
      if (!result.opened) {
        _note = '${app?.label ?? 'No UPI app'} could not open the payment. Copy the UPI ID, pay '
            'from any UPI app, then enter the UTR here.';
      } else if (hint.saysFailure) {
        _note = 'Your UPI app said the payment did not go through. If money left your account, '
            'enter the UTR from that app.';
      } else if (hint.saysSuccess) {
        _noteTone = FormNoteTone.success;
        _note = 'Your UPI app reported a payment. Check the UTR below, then send it for '
            'confirmation.';
      } else {
        _note = null;
      }
    });
  }

  Future<void> _copyVpa() async {
    await Clipboard.setData(ClipboardData(text: widget.settings.vpa));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('UPI ID copied. Pay it from any UPI app, then enter the UTR.'),
    ));
  }

  Future<void> _submit() async {
    final amount = _parsedAmount;
    setState(() {
      _amountError = amount == null ? 'Enter a valid amount.' : null;
      _utrError = utrError(_utr.text);
      _error = null;
    });
    if (_amountError != null || _utrError != null) return;
    setState(() => _busy = true);
    try {
      await ref.read(upiApiProvider).submitClaim(
            amount: amount!,
            periodMonth: widget.periodMonth,
            utr: _utr.text,
          );
      ref.invalidate(myPaymentClaimsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        switch (f.field) {
          case 'utr':
            _utrError = f.message;
          case 'amount':
            _amountError = f.message;
          default:
            _error = f.message;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = stayErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = widget.settings;
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final validVpa = isValidVpa(s.vpa);
    final installed = ref.watch(installedUpiAppsProvider).value ?? const <UpiApp>{};
    return Padding(
      padding: EdgeInsets.fromLTRB(
          Space.lg, 0, Space.lg, Space.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitle(
              title: _step == _Step.pay ? 'Pay with a UPI app' : 'Enter the UTR',
              subtitle: _step == _Step.pay
                  ? 'Rent for ${monthLabel(widget.periodMonth)} goes straight to your PG.'
                  : 'Your warden or owner checks it in their UPI app, then confirms.',
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('To ${s.payeeName}', style: t.textTheme.titleMedium),
                      SelectableText(s.vpa, style: muted),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy UPI ID',
                  onPressed: _copyVpa,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                errorText: _amountError,
                errorMaxLines: 3,
              ),
            ),
            if (_step == _Step.utr) ...[
              const SizedBox(height: Space.sm),
              TextField(
                controller: _utr,
                enabled: !_busy,
                autofocus: _note == null,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                maxLength: 30,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]'))],
                decoration: InputDecoration(
                  labelText: 'UTR / transaction ID',
                  helperText: 'The 12-digit UTR / UPI reference in your UPI app\'s payment '
                      'details.',
                  helperMaxLines: 2,
                  errorText: _utrError,
                  errorMaxLines: 3,
                ),
              ),
            ],
            if (_note != null) ...[
              const SizedBox(height: Space.xs),
              FormNote(_note!, tone: _noteTone),
            ],
            if (_error != null) ...[const SizedBox(height: Space.xs), FormNote(_error!)],
            const SizedBox(height: Space.md),
            if (_step == _Step.pay) ...[
              if (!validVpa)
                const FormNote(
                  'This UPI ID does not look right, so it cannot open a UPI app. Copy it and '
                  'check with your PG.',
                  tone: FormNoteTone.warning,
                )
              else ...[
                Text('Pay with', style: t.textTheme.labelLarge),
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  children: [
                    for (final app in installed)
                      OutlinedButton(
                        key: ValueKey('upi-app-${app.name}'),
                        onPressed: _busy ? null : () => _open(app),
                        child: Text(app.label),
                      ),
                  ],
                ),
                if (installed.isNotEmpty) const SizedBox(height: Space.xs),
                BusyFilledButton(
                  label: installed.isEmpty ? 'Open UPI app' : 'Other UPI app',
                  icon: Icons.open_in_new_rounded,
                  busy: _busy,
                  busyLabel: 'Opening…',
                  onPressed: () => _open(),
                ),
              ],
              TextButton.icon(
                onPressed: _copyVpa,
                icon: const Icon(Icons.copy_rounded, size: IconSize.md),
                label: const Text('Copy UPI ID and pay by hand'),
              ),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _step = _Step.utr),
                child: const Text('Already paid? Enter the UTR'),
              ),
            ] else ...[
              BusyFilledButton(
                label: 'Send for confirmation',
                busy: _busy,
                busyLabel: 'Sending…',
                onPressed: _submit,
              ),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _step = _Step.pay),
                child: const Text('Back to payment options'),
              ),
            ],
            const SizedBox(height: Space.xs),
            Text(
              'Apnivaas does not hold this money and never marks it paid on its own: your PG '
              'confirms it after checking.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
