library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import 'widgets/common.dart';
import 'widgets/format.dart';

/// "Pay rent" — and an honest account of what that means today.
///
/// WHY THIS SHEET DOES NOT TAKE A PAYMENT. The money path in this product is deliberately
/// server-side (db/migrations/2026-08-24-payments.sql): a Razorpay ORDER has to exist before
/// anything can be charged, orders are created with the Razorpay key SECRET, and that secret
/// lives in the Next.js server action `lib/actions/payments.ts` — never in a client. The
/// database function a client CAN call, `rz_open_intent(p_order_id, p_amount_paise)`, takes an
/// order id it cannot produce. This app holds the Supabase anon key and nothing else, by
/// design, so there is no way for it to open an order without shipping a credential that would
/// be readable by anyone who downloads the APK.
///
/// So the sheet tells the resident exactly how their rent actually gets recorded, and who to
/// hand it to. A button that opened a checkout and then failed would be worse than no button:
/// it would teach residents that the app lies about money. When a server endpoint for opening
/// an order exists, this sheet is where the Razorpay checkout belongs — `razorpay_flutter` is
/// already a dependency of this project for exactly that.
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
    final contacts = ref.watch(hostelContactsProvider);

    return ConstrainedBox(
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

            AsyncSection<HostelContacts?>(
              value: contacts,
              onRetry: () => ref.invalidate(hostelContactsProvider),
              builder: (card) => _Routes(contacts: card),
            ),

            const SizedBox(height: Space.md),
            Text(
              'However you pay, the payment is recorded against your name by the hostel and '
              'shows up on this screen. Nivora does not take the money inside this app.',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Routes extends StatelessWidget {
  const _Routes({required this.contacts});
  final HostelContacts? contacts;

  @override
  Widget build(BuildContext context) {
    final warden = contacts?.wardenName;
    final wardenPhone = contacts?.wardenPhone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Route(
          icon: Icons.storefront_rounded,
          title: 'At the hostel office',
          body: warden == null
              // No warden on the contact card is a real state — the post may be vacant. Do not
              // print a name that is not there.
              ? 'Pay cash, UPI or a bank transfer at the office. Whoever takes it records the '
                  'payment against your name.'
              : 'Pay $warden in cash, by UPI or by bank transfer. They record it against your '
                  'name and it appears here.',
          detail: wardenPhone == null ? null : 'Warden · $wardenPhone',
        ),
        const SizedBox(height: Space.xs),
        _Route(
          icon: Icons.language_rounded,
          title: 'Online, in the Nivora web portal',
          body: 'Sign in with the same phone number and password on the Nivora website. '
              'Card and UPI payments there are credited to this same rent ledger.',
        ),
      ],
    );
  }
}

class _Route extends StatelessWidget {
  const _Route({required this.icon, required this.title, required this.body, this.detail});

  final IconData icon;
  final String title;
  final String body;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return OutlineCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: t.colorScheme.primary),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.textTheme.titleMedium),
                const SizedBox(height: Space.xxs),
                Text(body, style: t.textTheme.bodyMedium),
                if (detail != null) ...[
                  const SizedBox(height: Space.xs),
                  // Selectable: the number is here to be dialled or copied.
                  SelectionArea(child: Text(detail!, style: t.textTheme.titleSmall)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
