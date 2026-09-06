import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';
import 'data/sa_models.dart';
import 'data/sa_providers.dart';

/// WHERE THIS HOSTEL'S RENT GOES — the only screen in the product that can change it.
///
/// ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────
///
/// NIVORA carries other people's money. A resident paying rent is paying their PG's owner, and
/// the platform's job is to see it reaches them rather than pooling in an account with no
/// lawful way to release it. Until this card the destination could only be set in SQL — which
/// meant in practice it was never set, and `rz_open_intent` refuses online payment for any
/// hostel that has no destination.
///
/// ── WHY ONLY A SUPER ADMIN ────────────────────────────────────────────────────────────────
///
/// An owner who could edit this could point a neighbour's rent at their own account. The write
/// goes through `sa_set_hostel_payout_account`, which re-checks `is_super_admin()` server-side,
/// refuses both modes at once, validates the `acc_` shape and writes the audit trail. This
/// screen is a convenience over that function and never the authority for it.
class SaPayoutCard extends ConsumerWidget {
  const SaPayoutCard({super.key, required this.hostelId, required this.ownerName});

  final String hostelId;
  final String? ownerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final payout = ref.watch(saPayoutProvider(hostelId));

    return payout.when(
      loading: () => const FlatSurface(padding: EdgeInsets.all(Space.md), child: Text('Checking where rent settles…')),
      error: (e, _) => FlatSurface(
        padding: const EdgeInsets.all(Space.md),
        child: Row(
          children: [
            Expanded(child: Text('Could not read the payout setting. $e')),
            TextButton(
              onPressed: () => ref.invalidate(saPayoutProvider(hostelId)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (p) => FlatSurface(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  p.canTakePayments ? Icons.verified_rounded : Icons.block_rounded,
                  size: IconSize.md,
                  color: p.canTakePayments ? context.tones.success : t.colorScheme.error,
                ),
                const SizedBox(width: Space.xs),
                Expanded(child: Text(_headline(p), style: t.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(_detail(p), style: t.textTheme.bodySmall),
            const SizedBox(height: Space.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _edit(context, ref, p),
                icon: const Icon(Icons.account_balance_rounded, size: IconSize.sm),
                label: const Text('Change'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _headline(SaPayout p) {
    if (p.directValid) return 'Settles directly to the platform account';
    if (p.accountId != null) return 'Routed to the owner’s linked account';
    if (p.directStale) return 'Paused — approved for a previous owner';
    return 'Online payment is off for this hostel';
  }

  String _detail(SaPayout p) {
    final owner = ownerName ?? 'this owner';
    if (p.directValid) {
      return 'The Razorpay account NIVORA is configured with belongs to $owner, so rent lands '
          'with them without being transferred.';
    }
    if (p.accountId != null) {
      return 'Rent is transferred to ${p.accountId} on capture, so it settles into the owner’s '
          'own bank rather than the platform’s.';
    }
    if (p.directStale) {
      return 'This hostel changed hands. The direct approval names the previous owner, so it is '
          'no longer honoured — re-approve it or add a linked account.';
    }
    return 'Residents are told to pay their warden in cash. Nothing is collected online until '
        'this is set.';
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, SaPayout current) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _PayoutDialog(
        hostelId: hostelId,
        ownerName: ownerName,
        current: current,
      ),
    );
    if (changed == true) ref.invalidate(saPayoutProvider(hostelId));
  }
}

class _PayoutDialog extends ConsumerStatefulWidget {
  const _PayoutDialog({
    required this.hostelId,
    required this.ownerName,
    required this.current,
  });

  final String hostelId;
  final String? ownerName;
  final SaPayout current;

  @override
  ConsumerState<_PayoutDialog> createState() => _PayoutDialogState();
}

class _PayoutDialogState extends ConsumerState<_PayoutDialog> {
  late bool _direct = widget.current.directValid;
  late final TextEditingController _account =
      TextEditingController(text: widget.current.accountId ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final owner = widget.ownerName ?? 'this owner';

    return AlertDialog(
      title: const Text('Where does this rent settle?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A radio pair, not two switches: the database has a check constraint refusing both
            // modes at once, and an interface that can express an impossible state invites it.
            //
            // RadioGroup rather than per-tile groupValue/onChanged, which Flutter deprecated
            // after 3.32 — the analyzer flags them, and a deprecation warning left in a file
            // about moving money is noise over the part worth reading.
            RadioGroup<bool>(
              groupValue: _direct,
              // RadioGroup.onChanged is not nullable, so the busy guard lives inside it rather
              // than disabling the callback. Same effect: a tap while saving does nothing.
              onChanged: (v) {
                if (_busy) return;
                setState(() => _direct = v ?? false);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<bool>(
                    value: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Directly, with no transfer'),
                    subtitle: Text(
                      'Only when the Razorpay account NIVORA is configured with belongs to '
                      '$owner. Their rent is already landing in it.',
                      style: t.textTheme.bodySmall,
                    ),
                  ),
                  RadioListTile<bool>(
                    value: false,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Route to their linked account'),
                    subtitle: Text(
                      'For every owner who is not the account holder.',
                      style: t.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            if (!_direct) ...[
              const SizedBox(height: Space.sm),
              TextField(
                controller: _account,
                enabled: !_busy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Razorpay linked account',
                  hintText: 'acc_XXXXXXXXXXXX',
                  helperText: 'From Razorpay Route, once the owner has completed their KYC.',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                _error!,
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: IconSize.sm,
                  height: IconSize.sm,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final account = _account.text.trim();

    // Caught here so the obvious mistake costs no round trip. The database validates the same
    // shape again, because this dialog is a convenience and not the authority.
    if (!_direct && account.isEmpty) {
      setState(() => _error = 'Enter the linked account, or choose direct settlement.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(saRepositoryProvider).setPayout(
            widget.hostelId,
            accountId: _direct ? null : account,
            direct: _direct,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }
}
