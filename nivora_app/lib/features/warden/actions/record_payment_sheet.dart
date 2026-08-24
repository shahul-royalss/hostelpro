library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../../payments/payments.dart';
import '../data/warden_providers.dart';
import '../widgets/warden_ui.dart';
import 'sheet_scaffold.dart';

/// Take rent.
///
/// OPENS ON THE SERVER'S NUMBERS, NOT THE CALLER'S. Whichever screen launched it passes only a
/// student and a month; the amount due and the amount already paid are re-read through
/// studentMonthFeeProvider. A ledger row read two minutes ago may already be out of date — a
/// second warden may have taken a part payment at the other desk — and prefilling a balance
/// from a stale row is how a resident is charged twice for the same month.
///
/// EVERY RULE IS THE SERVER'S. wd_record_payment refuses a payment of zero or less, one above
/// ₹1,00,00,000, one dated in the future, and any payment at all for a resident who has been
/// checked out, each with a sentence written for the person at the desk. The checks repeated in
/// this form exist to catch a typo before it costs a round trip, NOT to decide the outcome — if
/// the two ever disagree, the database is right.
///
/// The write is an UPSERT THAT ADDS: a second payment in the same month tops up amount_paid
/// rather than replacing it, which is why the field is labelled "Amount received now" and
/// prefilled with the balance rather than the total.
Future<bool?> showRecordPaymentSheet(
  BuildContext context, {
  required String studentId,
  required String studentName,
  required double monthlyFee,
  required String periodMonth,
}) {
  return showGlassSheet<bool>(
    context: context,
    builder: (_) => _RecordPaymentSheet(
      studentId: studentId,
      studentName: studentName,
      monthlyFee: monthlyFee,
      periodMonth: periodMonth,
    ),
  );
}

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({
    required this.studentId,
    required this.studentName,
    required this.monthlyFee,
    required this.periodMonth,
  });

  final String studentId;
  final String studentName;
  final double monthlyFee;
  final String periodMonth;

  @override
  ConsumerState<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  PaymentMode _mode = PaymentMode.cash;
  DateTime _paidOn = DateTime.now();
  bool _busy = false;

  /// Set once, when the existing row first arrives, so a refresh does not overwrite an amount
  /// the warden has started typing.
  bool _prefilled = false;

  /// The row `wd_record_payment` RETURNED. Not what was typed into the form.
  ///
  /// This is what makes a desk receipt trustworthy: the figures printed on it are the ones the
  /// database wrote and handed back — including the upsert's new cumulative `amount_paid`,
  /// which for a top-up is not the number in the amount field at all. Null until the write has
  /// succeeded, which is also what keeps the form on screen until then.
  FeePayment? _recorded;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final repo = ref.read(feeRepositoryProvider);
    FeePayment? row;
    final ok = await runAction(
      context,
      success: '${money(double.parse(_amount.text.trim()))} from ${widget.studentName}',
      action: () async {
        row = await repo.recordPayment(
          studentId: widget.studentId,
          periodMonth: widget.periodMonth,
          amount: double.parse(_amount.text.trim()),
          mode: _mode,
          paidOn: _paidOn,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );
      },
    );

    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;

    refreshFees(ref);
    if (!mounted) return;

    // Stay on the sheet and offer the receipt rather than closing straight away. A warden
    // taking cash at the door usually has the resident standing in front of them, and that is
    // the one moment a receipt is worth anything. "Done" is right there for the rest of the
    // time — a busy desk is not made to sit through a receipt it did not ask for.
    setState(() => _recorded = row);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime(now.year - 1),
      // wd_record_payment refuses `p_paid_on > current_date + 1`. Today is the honest ceiling:
      // the one-day grace exists for a server clock in another zone, not to backdate forwards.
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _paidOn = picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final recorded = _recorded;

    if (recorded != null) {
      return SheetBody(
        title: widget.studentName,
        subtitle: 'Rent for ${monthLabel(widget.periodMonth)}',
        child: _Recorded(
          row: recorded,
          studentName: widget.studentName,
          onDone: () => Navigator.of(context).pop(true),
        ),
      );
    }

    final existing = ref.watch(studentMonthFeeProvider(
      (studentId: widget.studentId, periodMonth: widget.periodMonth),
    ));

    return SheetBody(
      title: widget.studentName,
      subtitle: 'Rent for ${monthLabel(widget.periodMonth)}',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AsyncSection<FeePayment?>(
              value: existing,
              onRetry: () => ref.invalidate(studentMonthFeeProvider),
              loading: const _LedgerSkeleton(),
              builder: (row) {
                // coalesce(fee_payments.amount_due, students.monthly_fee) — the same rule
                // rpc_fee_ledger uses, so this sheet and the list behind it never disagree.
                final due = row?.amountDue ?? widget.monthlyFee;
                final paid = row?.amountPaid ?? 0;
                final balance = (due - paid) > 0 ? due - paid : 0.0;

                if (!_prefilled) {
                  _prefilled = true;
                  // Whole rupees: the field is a starting point a warden edits, and a
                  // prefilled "7000.0" invites a typo that "7000" does not.
                  _amount.text = balance > 0 ? balance.toStringAsFixed(0) : '';
                }

                return _BalanceStrip(due: due, paid: paid, balance: balance, status: row?.status);
              },
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _amount,
              enabled: !_busy,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount received now',
                helperText: 'Added to anything already recorded for this month',
                prefixText: '₹ ',
              ),
              validator: (v) {
                final amount = double.tryParse((v ?? '').trim());
                if (amount == null) return 'Enter the amount received';
                if (amount <= 0) return 'Amount must be greater than zero';
                if (amount > 10000000) return 'That amount is too large';
                return null;
              },
            ),
            const SizedBox(height: Space.md),
            Text('Paid by', style: t.textTheme.labelSmall),
            const SizedBox(height: Space.xs),
            SegmentedButton<PaymentMode>(
              segments: [
                for (final mode in PaymentMode.values)
                  ButtonSegment(value: mode, label: Text(mode.label)),
              ],
              selected: {_mode},
              onSelectionChanged: _busy ? null : (s) => setState(() => _mode = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: Space.md),
            InkWell(
              borderRadius: Radii.rControl,
              onTap: _busy ? null : _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Received on',
                  prefixIcon: Icon(Icons.event_outlined),
                  suffixIcon: Icon(Icons.chevron_right_rounded),
                ),
                child: Text(shortDate(_paidOn), style: t.textTheme.bodyLarge),
              ),
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              controller: _notes,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: Space.lg),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the database wrote, and the offer of a receipt for it.
///
/// EVERY FIGURE HERE IS FROM [row], the composite `wd_record_payment` returned. Nothing is
/// echoed back from the form: the amount field held what the warden intended to record, and the
/// row holds what the ledger now says — which for a second payment in the same month is a
/// larger, cumulative number, because the RPC's upsert ADDS. Showing the form's number here
/// would be showing the warden a total the resident's own screen will not agree with.
class _Recorded extends ConsumerWidget {
  const _Recorded({required this.row, required this.studentName, required this.onDone});

  final FeePayment row;
  final String studentName;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    // Null only if the row came back with nothing received against it, which wd_record_payment
    // cannot produce — it refuses an amount of zero or less. Guarded anyway, because "offer a
    // receipt only when there is one" is the rule, not a thing to assume.
    final receipt = Receipt.forFeePayment(
      row,
      payerName: studentName,
      hostelName: ref.watch(hostelContactsProvider).value?.hostelName,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_rounded, size: 22, color: NivoraColors.success),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment recorded', style: t.textTheme.titleMedium),
                  const SizedBox(height: Space.xxs),
                  Text(
                    '${money(row.amountPaid)} received for '
                    '${monthLabel(row.periodMonth)}'
                    '${row.balance > 0 ? ' · ${money(row.balance)} still outstanding' : ''}.',
                    style: t.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        if (receipt != null) ...[
          FilledButton.icon(
            onPressed: () => showReceipt(context, receipt),
            icon: const Icon(Icons.receipt_long_rounded, size: 20),
            label: const Text('Print a receipt'),
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Prints on screen. Share it to the resident from there, or save it.',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
        ],
        OutlinedButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}

/// Due, paid and outstanding, side by side. Three numbers a warden reads before they take money.
class _BalanceStrip extends StatelessWidget {
  const _BalanceStrip({
    required this.due,
    required this.paid,
    required this.balance,
    required this.status,
  });

  final double due;
  final double paid;
  final double balance;
  final FeeStatus? status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // No row yet means nothing has been paid — rpc_fee_ledger reports exactly that as 'unpaid',
    // so showing the same word here keeps the sheet and the list telling one story.
    final shown = status ?? FeeStatus.unpaid;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: Radii.rCard,
        border: Border.all(color: t.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Figure(label: 'Due', value: money(due)),
              _Figure(label: 'Paid', value: money(paid)),
              _Figure(
                label: 'Outstanding',
                value: money(balance),
                tone: balance > 0 ? NivoraColors.error : NivoraColors.success,
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Align(alignment: Alignment.centerLeft, child: StatusPill(status: shown)),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.tone});
  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: t.textTheme.labelSmall),
          const SizedBox(height: Space.xxs),
          Text(
            value,
            style: t.textTheme.titleSmall?.copyWith(color: tone),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _LedgerSkeleton extends StatelessWidget {
  const _LedgerSkeleton();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: Radii.rCard,
        border: Border.all(color: t.colorScheme.outlineVariant),
      ),
      child: const SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
