library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';
import 'common.dart';
import 'format.dart';

/// The rent cards — the one thing a resident opens this app to check.
///
/// THE RULE EVERY WIDGET IN THIS FILE FOLLOWS: no arithmetic. Every figure shown is either a
/// column Postgres returned (`amount_due`, `amount_paid`) or a getter on the model that owns it
/// (`balance`, which clamps an overpayment to zero because an overpayment is not a debt). The
/// UI never adds two amounts together, so what is drawn here cannot drift from what the
/// warden's collections screen shows for the same person.

/// This month's rent, stated plainly and without a number that is not in the database.
///
/// [row] is the resident's own row of `rpc_fee_ledger`. Null means the ledger had nothing for
/// them this month, which is a real state (registration not finished, or checked out) and is
/// said out loud rather than drawn as ₹0.
class RentCard extends StatelessWidget {
  const RentCard({
    super.key,
    required this.periodMonth,
    required this.row,
    this.onPay,
  });

  /// 'YYYY-MM'. Shown as a month name, never as a due date: `fee_payments` has a period and a
  /// `paid_on`, and no due-date column exists anywhere in the schema. Inventing "due on the
  /// 5th" would be putting a rule on screen that the database does not hold.
  final String periodMonth;
  final FeeLedgerRow? row;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rent = row;

    if (rent == null) {
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RENT · ${monthEyebrow(periodMonth)}', style: t.textTheme.labelSmall),
            const SizedBox(height: Space.xs),
            Text('No rent record yet', style: t.textTheme.headlineMedium),
            const SizedBox(height: Space.xxs),
            Text(
              'Your warden has not set up this month for you. Ask at the office if you think '
              'that is wrong.',
              style: t.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final tone = feeTone(rent.status);
    // [feeTone] is context-free, so what it returns is CANONICAL — legible as a shape in both
    // themes and as nothing else. The hero figure below is 32px TYPE, so it is painted with the
    // resolved value; [StatusPill] still gets the canonical one and resolves it for itself.
    final accent = context.tones.resolve(tone);
    final owes = rent.balance > 0;

    return GlassCard(
      semanticLabel: _spoken(rent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('RENT · ${monthEyebrow(periodMonth)}',
                    style: t.textTheme.labelSmall),
              ),
              StatusPill(
                label: rent.status.label,
                tone: tone,
                icon: switch (rent.status) {
                  FeeStatus.paid => Icons.check_circle_rounded,
                  FeeStatus.partial => Icons.timelapse_rounded,
                  FeeStatus.unpaid => Icons.error_outline_rounded,
                },
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          // The hero figure is what is OUTSTANDING when anything is outstanding, and what was
          // paid when nothing is. A resident checking this screen is answering one question,
          // and it is not "what is my rent".
          Text(
            rupees(owes ? rent.balance : rent.amountPaid),
            style: t.textTheme.headlineLarge?.copyWith(color: owes ? accent : null),
          ),
          const SizedBox(height: Space.xxs),
          Text(owes ? 'still to pay' : 'paid in full', style: t.textTheme.bodyMedium),
          const SizedBox(height: Space.sm),
          Divider(color: t.colorScheme.outlineVariant),
          const SizedBox(height: Space.xs),
          _Line(label: 'Rent for the month', value: rupees(rent.amountDue)),
          _Line(label: 'Received so far', value: rupees(rent.amountPaid)),
          if (rent.paidOn != null)
            _Line(
              label: 'Last payment',
              value: '${dayLabel(rent.paidOn!)}'
                  '${rent.mode == null ? '' : ' · ${rent.mode!.label}'}',
            ),
          if (owes && onPay != null) ...[
            const SizedBox(height: Space.md),
            FilledButton.icon(
              onPressed: onPay,
              icon: const Icon(Icons.account_balance_wallet_rounded, size: IconSize.md),
              label: const Text('Pay rent'),
            ),
          ],
        ],
      ),
    );
  }

  /// One sentence for a screen reader, instead of six disconnected fragments.
  String _spoken(FeeLedgerRow rent) {
    final month = monthLabel(periodMonth);
    if (rent.balance > 0) {
      return 'Rent for $month: ${rupees(rent.balance)} still to pay '
          'of ${rupees(rent.amountDue)}.';
    }
    return 'Rent for $month: paid in full, ${rupees(rent.amountPaid)}.';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.textTheme.bodyMedium)),
          Text(value, style: t.textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// One month of the resident's own payment history.
///
/// Every column a person needs to check a month against their bank: what was owed, what was
/// received, what is still pending, when it landed and how it was paid.
class FeePaymentTile extends StatelessWidget {
  const FeePaymentTile({super.key, required this.payment});

  final FeePayment payment;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = feeTone(payment.status);
    return OutlineCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(monthLabel(payment.periodMonth), style: t.textTheme.titleMedium),
              ),
              StatusPill(label: payment.status.label, tone: tone),
            ],
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(child: _Cell(label: 'Due', value: rupees(payment.amountDue))),
              Expanded(child: _Cell(label: 'Paid', value: rupees(payment.amountPaid))),
              Expanded(
                child: _Cell(
                  label: 'Pending',
                  value: rupees(payment.balance),
                  tone: payment.balance > 0 ? tone : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            payment.paidOn == null
                // A row with no paid_on exists only where a month was opened without a
                // payment. Say that, rather than printing a date that is not there.
                ? 'No payment date recorded'
                : 'Received ${dayLabel(payment.paidOn!)}'
                    '${payment.mode == null ? '' : ' · ${payment.mode!.label}'}',
            style: t.textTheme.bodySmall,
          ),
          if (payment.notes != null && payment.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: Space.xxs),
            Text(payment.notes!.trim(), style: t.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, this.tone});
  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Canonical in, resolved at the paint site: this is 14px type, and the canonical reds and
    // ambers are only rated as graphics.
    final accent = tone == null ? null : context.tones.resolve(tone!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: t.textTheme.labelSmall),
        const SizedBox(height: Space.xxs),
        Text(
          value,
          style: t.textTheme.titleSmall?.copyWith(color: accent),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Where the resident lives, from the same ledger row that carries their rent.
///
/// `room_number` and `bed_number` come through joins RLS permits — a resident may read the
/// hostel's rooms, and only the beds in their OWN room. There is no cheaper single read that
/// names a resident's room: `students` stores ids, not numbers.
class RoomBedCard extends StatelessWidget {
  const RoomBedCard({super.key, required this.roomNumber, required this.bedNumber, this.roommates});

  final String? roomNumber;
  final int? bedNumber;

  /// Who else is in the room — as the read that answers it, not as a number.
  ///
  /// An [AsyncValue] and not an `int?` because null could not tell three different facts apart:
  /// the read is still in flight, it came back empty, and it failed. Those are three different
  /// sentences, and "you have the room to yourself" is very nearly the opposite of "we could not
  /// find out" — while a line that simply vanishes reads as the first one.
  ///
  /// THE WHOLE VALUE, NOT A MAPPED COUNT. `roommates.whenData((m) => m.length)` looked like the
  /// tidy way to hand this a number and it is a trap: `whenData` dispatches on the RUNTIME TYPE,
  /// and Riverpod 3 represents a failed read that it is still retrying as an `AsyncLoading` that
  /// CARRIES the error. `whenData` takes the loading branch for it and returns a bare
  /// `AsyncLoading`, throwing the error away — so the card would show a placeholder for a read
  /// that had already failed, for the whole ~38 seconds the default ten-retry backoff takes.
  ///
  /// Null (the parameter itself) means this card is not drawing the line at all, which is what
  /// Profile does: the full roommate list sits directly beneath it there and owns that failure.
  final AsyncValue<List<Roommate>>? roommates;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (roomNumber == null) {
      return OutlineCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YOUR ROOM', style: t.textTheme.labelSmall),
            const SizedBox(height: Space.xxs),
            Text('Not assigned yet', style: t.textTheme.titleMedium),
            const SizedBox(height: Space.xxs),
            Text('Your warden will place you in a room and bed.',
                style: t.textTheme.bodySmall),
          ],
        ),
      );
    }

    return OutlineCard(
      child: Row(
        children: [
          Icon(Icons.meeting_room_rounded, size: IconSize.lg, color: t.colorScheme.primary),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR ROOM', style: t.textTheme.labelSmall),
                const SizedBox(height: Space.xxs),
                Text(
                  bedNumber == null
                      ? 'Room $roomNumber'
                      : 'Room $roomNumber · Bed $bedNumber',
                  style: t.textTheme.titleMedium,
                ),
                ?_sharing(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The sharing line, in whichever state the roommate read is actually in.
  ///
  /// Four outcomes, four appearances. In flight is a placeholder the size of the line it will
  /// become; an empty room is stated out loud; a failure says so and points at the
  /// pull-to-refresh every screen that draws this card already has; and a refusal is said
  /// plainly, with no retry affordance for something retrying cannot fix.
  ///
  /// Branched by hand rather than through `when`, because the precedence matters and the flags
  /// bury it: A KNOWN FAILURE OUTRANKS A STALE COUNT. If a refresh failed, the number this
  /// device is holding is no longer something the card can vouch for, and stating it anyway is
  /// the quiet kind of wrong — it looks exactly like a fact.
  Widget? _sharing(BuildContext context) {
    final mates = roommates;
    if (mates == null) return null;
    final t = Theme.of(context);

    final Widget line;
    if (mates.hasError) {
      line = Text(
        errorGuidance(mates.error!).canRetry
            ? 'Could not check who else is in this room. Pull down to try again.'
            : 'Who else is in this room is not available to you.',
        style: t.textTheme.bodySmall?.copyWith(color: context.tones.muted),
      );
    } else if (mates.hasValue) {
      final count = mates.requireValue.length;
      line = Text(
        count == 0
            ? 'You have the room to yourself'
            : 'Sharing with ${countLabel(count, 'other resident')}',
        style: t.textTheme.bodySmall,
      );
    } else {
      line = const Skeleton(widthFactor: 0.6, height: Space.sm - Space.xxs / 2);
    }

    return Padding(padding: const EdgeInsets.only(top: Space.xxs), child: line);
  }
}
