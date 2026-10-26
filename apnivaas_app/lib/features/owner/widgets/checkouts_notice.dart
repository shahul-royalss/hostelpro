/// The owner home's "Check-outs" notice (round 3, R6): requests waiting, check-outs scheduled
/// and residents who left in the last 30 days, across every PG the owner has. Hidden when there
/// is nothing to say, and quietly absent if the read fails (the list screen has its own errors).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/stay.dart';
import '../../../data/repositories/stay_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../student/widgets/format.dart';
import '../../warden/checkout/warden_checkouts_screen.dart';

class CheckoutsNotice extends ConsumerWidget {
  const CheckoutsNotice({super.key, required this.hostelId, this.padding = EdgeInsets.zero});

  /// The PG the list opens on.
  final String? hostelId;
  final EdgeInsetsGeometry padding;

  static String summaryLine(CheckoutSummary s) => [
        if (s.pending > 0) '${s.pending} waiting',
        if (s.scheduled > 0) '${s.scheduled} scheduled',
        if (s.recent > 0) '${s.recent} checked out in 30 days',
      ].join(' · ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(ownerCheckoutSummaryProvider).value;
    if (s == null || s.isEmpty) return const SizedBox.shrink();
    final several = s.items.map((i) => i.hostelName).toSet().length > 1;
    final open = hostelId == null
        ? null
        : () => Navigator.of(context).push(CheckoutRequestsScreen.route(hostelId!));
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListRowCard(
            icon: ClayIcons.moveOut,
            title: 'Check-outs',
            subtitle: summaryLine(s),
            trailing: s.pending > 0
                ? CountBadge(count: s.pending, semanticLabel: '${s.pending} waiting')
                : null,
            semanticLabel: 'Check-outs, ${summaryLine(s)}',
            onTap: open,
          ),
          for (final item in s.items.take(3))
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: ListRow(
                avatarName: item.fullName,
                title: item.fullName,
                subtitle: _line(item, several),
                trailing: StatusChip(label: item.status.label, tone: _tone(item.status)),
                onTap: open,
              ),
            ),
        ],
      ),
    );
  }

  static String _line(CheckoutSummaryItem i, bool withPg) {
    final when = switch (i.status) {
      CheckoutStatus.completed when i.completedAt != null =>
        'Left ${dayLabel(i.completedAt!.toLocal())}',
      CheckoutStatus.accepted when i.checkoutDate != null => 'Leaves ${dayLabel(i.checkoutDate!)}',
      _ when i.preferredDate != null => 'Asked for ${dayLabel(i.preferredDate!)}',
      _ => null,
    };
    return [
      if (withPg && i.hostelName != null) i.hostelName!,
      if (i.roomNumber != null) 'Room ${i.roomNumber}',
      ?when,
    ].join(' · ');
  }

  static StatusTone _tone(CheckoutStatus s) => switch (s) {
        CheckoutStatus.pending => StatusTone.warning,
        CheckoutStatus.accepted => StatusTone.info,
        CheckoutStatus.completed => StatusTone.neutral,
        CheckoutStatus.declined || CheckoutStatus.cancelled => StatusTone.neutral,
      };
}
