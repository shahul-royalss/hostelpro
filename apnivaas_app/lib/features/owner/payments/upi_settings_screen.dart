/// Owner → Payment settings (R9): the UPI ID and payee name tenants pay rent to directly.
/// Only the owner writes it (`ow_set_upi_settings` checks); tenants of the PG read it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/upi.dart';
import '../../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../../data/repositories/upi_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../common/form_parts.dart';
import '../../student/stay_screens.dart' show stayErrorText;
import '../../warden/claims/payment_claims_screen.dart';
import '../widgets/owner_header.dart';

class UpiSettingsScreen extends ConsumerWidget {
  const UpiSettingsScreen({super.key, required this.hostelId});

  final String hostelId;

  static Route<void> route(String hostelId) =>
      MaterialPageRoute<void>(builder: (_) => UpiSettingsScreen(hostelId: hostelId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(upiSettingsProvider(hostelId));
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OwnerSubpageHeader(title: 'UPI payments', subtitle: 'Rent straight to your UPI'),
          Expanded(
            child: switch (settings) {
              AsyncData(:final value) => _Form(hostelId: hostelId, current: value),
              AsyncError(:final error) => ListView(
                  padding: OwnerRhythm.pagePadding,
                  children: [
                    EmptyState.error(
                      message: stayErrorText(error),
                      onRetry: () => ref.invalidate(upiSettingsProvider(hostelId)),
                    ),
                  ],
                ),
              _ => ListView(
                  padding: OwnerRhythm.pagePadding,
                  children: const [ListSkeleton(rows: 2, semanticLabel: 'Loading UPI settings')],
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.hostelId, required this.current});
  final String hostelId;
  final UpiSettings? current;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final _vpa = TextEditingController(text: widget.current?.vpa ?? '');
  late final _payee = TextEditingController(text: widget.current?.payeeName ?? '');
  String? _vpaError;
  String? _payeeError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _vpa.dispose();
    _payee.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    FocusScope.of(context).unfocus();
    final vpa = remove ? '' : _vpa.text;
    setState(() {
      _vpaError = remove ? null : vpaError(vpa);
      _payeeError = remove ? null : payeeNameError(_payee.text);
      _error = null;
    });
    if (_vpaError != null || _payeeError != null) return;
    if (remove) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Turn off UPI payments?'),
          content: const Text('Tenants will no longer see "Pay with UPI app". Payments already '
              'reported can still be confirmed.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Turn off')),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await ref
          .read(upiApiProvider)
          .saveSettings(widget.hostelId, vpa: vpa, payeeName: remove ? '' : _payee.text);
      ref.invalidate(upiSettingsProvider(widget.hostelId));
      if (!mounted) return;
      if (saved != null) {
        _vpa.text = saved.vpa;
        _payee.text = saved.payeeName;
      } else if (remove) {
        _vpa.clear();
        _payee.clear();
      }
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(remove ? 'UPI payments are off.' : 'Saved. Tenants can now pay with UPI.'),
      ));
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        switch (f.field) {
          case 'upi_vpa':
            _vpaError = f.message;
          case 'payee_name':
            _payeeError = f.message;
          default:
            _error = f.message;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = stayErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: OwnerRhythm.pagePadding,
      children: [
        const InfoNote(
          icon: Icons.account_balance_rounded,
          message: 'Tenants pay this UPI ID from their own UPI app, so the money reaches you '
              'directly. Apnivaas never holds it. Check your UPI app or bank, then confirm '
              'each payment in Apnivaas.',
        ),
        const SizedBox(height: Space.sm),
        const InfoNote(
          icon: Icons.tips_and_updates_rounded,
          message: 'For the smoothest payments, use a UPI ID from PhonePe for Business, Paytm '
              'for Business or BharatPe. Some apps limit payments to personal UPI IDs.',
        ),
        const SizedBox(height: Space.lg),
        TextField(
          controller: _vpa,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'UPI ID',
            hintText: 'name@okhdfcbank',
            errorText: _vpaError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _payee,
          enabled: !_busy,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Payee name',
            helperText: 'As your UPI app shows it, so tenants know it is you',
            helperMaxLines: 2,
            errorText: _payeeError,
            errorMaxLines: 3,
          ),
        ),
        if (_error != null) ...[const SizedBox(height: Space.xs), FormNote(_error!)],
        const SizedBox(height: Space.md),
        BusyFilledButton(label: 'Save', busy: _busy, onPressed: () => _save()),
        if (widget.current != null) ...[
          const SizedBox(height: Space.xs),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => _save(remove: true),
              child: Text('Turn off UPI payments',
                  style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.error)),
            ),
          ),
          const SizedBox(height: Space.lg),
          ListRowCard(
            icon: ClayIcons.collectPayment,
            title: 'Confirm UPI payments',
            subtitle: 'Payments tenants reported, waiting for you to check',
            onTap: () => Navigator.of(context).push(PaymentClaimsScreen.route(widget.hostelId)),
          ),
        ],
      ],
    );
  }
}
