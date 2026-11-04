/// Super Admin → a hostel's online rent payments (Cashfree, 2026-11-04), with Refund for
/// disputes. The Super Admin reads every hostel's payments under RLS; cashfree-refund checks the
/// second factor and the payment again on the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/cashfree_repository.dart';
import '../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../shared/clay/clay.dart';
import '../common/form_parts.dart';
import '../owner/payments/owner_payments_screen.dart' show showPaymentDetails;
import '../payments/cashfree/cashfree_pay_screen.dart' show RentPaymentTile;

class SaRentPaymentsScreen extends ConsumerWidget {
  const SaRentPaymentsScreen({super.key, required this.hostelId, required this.hostelName});
  final String hostelId;
  final String hostelName;

  static Route<void> route(String hostelId, String hostelName) =>
      MaterialPageRoute(builder: (_) => SaRentPaymentsScreen(hostelId: hostelId, hostelName: hostelName));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hostelRentPaymentsProvider(hostelId));
    return Scaffold(
      appBar: AppBar(title: Text('${context.tr('Online payments')} · $hostelName')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(hostelRentPaymentsProvider(hostelId).future),
        child: switch (async) {
          AsyncData(:final value) when value.isEmpty => ListView(children: const [
              SizedBox(height: Space.huge),
              EmptyState(title: 'No online payments', body: 'Cashfree rent payments for this PG show here.', icon: ClayIcons.money),
            ]),
          AsyncData(:final value) => ListView(
              padding: const EdgeInsets.all(Space.md),
              children: [
                for (final p in value) ...[
                  RentPaymentTile(
                    payment: p,
                    showTenant: true,
                    showSettlement: true,
                    onTap: () => showPaymentDetails(context, p, canRefund: true),
                  ),
                  const SizedBox(height: Space.xs),
                ],
              ],
            ),
          AsyncError(:final error) => ListView(children: [
              const SizedBox(height: Space.huge),
              FormNote(error is SignupFailure ? error.message : 'Payments could not be loaded.'),
            ]),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}
