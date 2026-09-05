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
///
/// ═══ AND BECAUSE IT ADDS, THIS SHEET ALSO HAS TO BE ABLE TO SET ═══
/// Adding is right for a second instalment and useless for a typo. A warden who keys ₹7,000
/// instead of ₹700 could not get back: there was no client path that lowered a figure, and
/// entering it again only made the total worse. So the sheet has a second mode — "Correct what
/// is recorded" — which calls wd_correct_payment and SETS the month's received total to an
/// exact figure. Zero is allowed there and is the point of it: it undoes a payment recorded
/// against the wrong resident, and the server clears paid_on and mode along with the amount.
///
/// THE TWO MODES ARE NEVER THE SAME BUTTON. Which arithmetic is about to happen is the only
/// thing on this sheet a warden can get catastrophically wrong, so the field label, its helper
/// line, the submit button and the panel afterwards all change with the mode. Correcting is
/// only offered when there is something recorded to correct — the server refuses otherwise,
/// with those words.
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

  /// SETTING the month's total rather than ADDING to it. See the header.
  bool _correcting = false;

  /// The row `wd_record_payment` RETURNED. Not what was typed into the form.
  ///
  /// This is what makes a desk receipt trustworthy: the figures printed on it are the ones the
  /// database wrote and handed back — including the upsert's new cumulative `amount_paid`,
  /// which for a top-up is not the number in the amount field at all. Null until the write has
  /// succeeded, which is also what keeps the form on screen until then.
  FeePayment? _recorded;

  @override
  void initState() {
    super.initState();
    // The month's row is usually still in flight here, and the listener in [build] catches its
    // arrival. It can also be warm already — the same student and month is one cache entry, and
    // a warden who closes and reopens the sheet gets it instantly — in which case there is no
    // change to listen for and this is the only prefill that happens.
    final cached = ref.read(studentMonthFeeProvider(_key));
    if (cached.hasValue) _prefill(cached.value);
  }

  /// The sheet's cache key. One record, so the same student and month is the same entry rather
  /// than a second request.
  ({String studentId, String periodMonth}) get _key =>
      (studentId: widget.studentId, periodMonth: widget.periodMonth);

  /// Open the amount field on the figure the CURRENT mode is about.
  ///
  /// NEVER CALLED FROM `build`. Assigning to a TextEditingController notifies its listeners, and
  /// TextFormField's listener calls setState — so doing this inside the section's builder threw
  /// "setState() called during build" on the frame the row arrived, which in a release build is
  /// silently a dropped frame instead. It runs from initState and from a ref.listen callback,
  /// both of which are outside the build phase.
  void _prefill(FeePayment? row) {
    if (_prefilled) return;
    _prefilled = true;
    // coalesce(fee_payments.amount_due, students.monthly_fee) — the same rule rpc_fee_ledger
    // uses, so this sheet and the list behind it never disagree.
    final due = row?.amountDue ?? widget.monthlyFee;
    final paid = row?.amountPaid ?? 0;
    final balance = (due - paid) > 0 ? due - paid : 0.0;
    // Whole rupees: the field is a starting point a warden edits, and a prefilled "7000.0"
    // invites a typo that "7000" does not.
    _amount.text = balance > 0 ? balance.toStringAsFixed(0) : '';
  }

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

    final repo = ref.read(feeDeskProvider);
    final amount = double.parse(_amount.text.trim());
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    FeePayment? row;
    final ok = await runAction(
      context,
      success: _correcting
          ? 'Corrected to ${money(amount)} for ${widget.studentName}'
          : '${money(amount)} from ${widget.studentName}',
      action: () async {
        row = _correcting
            ? await repo.correctPayment(
                studentId: widget.studentId,
                periodMonth: widget.periodMonth,
                amountPaid: amount,
                // A month corrected to nothing was not paid on a day by a method, and the
                // server nulls both. Sending them anyway would be asking it to keep a date for
                // a payment this correction is saying never happened.
                mode: amount > 0 ? _mode : null,
                paidOn: amount > 0 ? _paidOn : null,
                notes: notes,
              )
            : await repo.recordPayment(
                studentId: widget.studentId,
                periodMonth: widget.periodMonth,
                amount: amount,
                mode: _mode,
                paidOn: _paidOn,
                notes: notes,
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

  /// Switch between ADDING to the month and SETTING it, and re-prefill the field with the
  /// figure that mode is about.
  ///
  /// The prefill is the whole safety of the toggle: correcting opens on the total the ledger
  /// currently holds, so pressing Save with nothing typed is a no-op rather than a write of
  /// whatever number was left over from the other mode. The date and method open on what the
  /// row actually says too — a correction is as often "that was UPI, not cash" as it is a
  /// mistyped figure.
  void _toggleCorrecting(FeePayment row) {
    setState(() {
      _correcting = !_correcting;
      if (_correcting) {
        _amount.text = row.amountPaid.toStringAsFixed(0);
        _mode = row.mode ?? _mode;
        _paidOn = row.paidOn ?? _paidOn;
      } else {
        _amount.text = row.balance > 0 ? row.balance.toStringAsFixed(0) : '';
        // BACK TO CASH ON THE WAY OUT. Turning correction ON loads the row's own method, which
        // for an online payment is UPI. Turning it OFF used to leave that behind, so the next
        // "Record payment" — a warden taking notes at the desk — would have been written to the
        // ledger as UPI. That was survivable while a picker showed the method; with the method
        // now stated rather than chosen it would have been silent, which is worse. A new entry
        // is always cash.
        _mode = PaymentMode.cash;
      }
      _form.currentState?.validate();
    });
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
          corrected: _correcting,
          onDone: () => Navigator.of(context).pop(true),
        ),
      );
    }

    // Fires when the row lands, which is AFTER this build — see [_prefill] for why that
    // matters. Registered before the watch so the first delivery cannot be missed.
    ref.listen(studentMonthFeeProvider(_key), (_, next) {
      if (next.hasValue) _prefill(next.value);
    });
    final month = ref.watch(studentMonthFeeProvider(_key));

    // A month with nothing received against it cannot be corrected — there is no row, or the
    // row is at zero. `.value` reads through Riverpod 3's retrying-loading state, so the toggle
    // does not vanish while a refresh is in flight behind an already-drawn sheet.
    final existing = month.value;
    final correctable = existing != null && existing.amountPaid > 0;

    return SheetBody(
      title: widget.studentName,
      subtitle: 'Rent for ${monthLabel(widget.periodMonth)}',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AsyncSection<FeePayment?>(
              value: month,
              onRetry: () => ref.invalidate(studentMonthFeeProvider),
              loading: const _LedgerSkeleton(),
              builder: (row) {
                // The same coalesce rule as [_prefill], and nothing is written to the form from
                // in here: this builder only draws.
                final due = row?.amountDue ?? widget.monthlyFee;
                final paid = row?.amountPaid ?? 0;
                final balance = (due - paid) > 0 ? due - paid : 0.0;
                return _BalanceStrip(due: due, paid: paid, balance: balance, status: row?.status);
              },
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _amount,
              enabled: !_busy,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                // The label is the arithmetic. "Amount received now" is added; "Total received
                // this month" replaces — and a warden who reads only the label still cannot
                // mistake one for the other.
                labelText: _correcting ? 'Total received this month' : 'Amount received now',
                helperText: _correcting
                    ? 'Replaces the figure on the ledger. Zero clears the month.'
                    : 'Added to anything already recorded for this month',
                prefixText: '₹ ',
              ),
              // Both sets of rules are the server's, repeated here to catch a typo before it
              // costs a round trip. wd_correct_payment accepts zero (that is how a payment
              // against the wrong resident is undone) and refuses a negative total.
              validator: (v) {
                final amount = double.tryParse((v ?? '').trim());
                if (amount == null) {
                  return _correcting ? 'Enter the corrected total' : 'Enter the amount received';
                }
                if (_correcting && amount < 0) return 'A corrected total cannot be negative';
                if (!_correcting && amount <= 0) return 'Amount must be greater than zero';
                if (amount > 10000000) return 'That amount is too large';
                return null;
              },
            ),
            const SizedBox(height: Space.md),
            const CapsLabel('Paid by'),
            const SizedBox(height: Space.xs),
            // ── A WARDEN RECORDS CASH, AND ONLY CASH ────────────────────────────────────────
            //
            // This was a three-way picker: cash, UPI, bank. The product owner removed the other
            // two, and the reason is sound rather than cosmetic — a warden ticking "UPI" is
            // ASSERTING that money arrived in an account they cannot see. Nothing backs that
            // assertion up. A real UPI payment reaches this ledger through the Razorpay
            // webhook, which has an HMAC over the raw body and a payment id behind it, and a
            // resident who wants to pay that way does it from their own dashboard.
            //
            // WHAT THIS IS CAREFUL ABOUT. A correction opens on the row the ledger already
            // holds, and that row may well be an online payment — _toggleCorrecting does
            // `_mode = row.mode ?? _mode`. Dropping the other two values from a SegmentedButton
            // whose `selected` could still be one of them would have asserted at build time;
            // silently forcing it to cash would have been worse, quietly rewriting a verified
            // Razorpay payment as money over the desk. So the method is now stated rather than
            // chosen: a new entry is cash, and a correction keeps and shows whatever the row
            // actually was.
            Row(
              children: [
                Icon(
                  _mode == PaymentMode.cash
                      ? Icons.payments_rounded
                      : Icons.smartphone_rounded,
                  size: IconSize.sm,
                  color: t.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Space.xs),
                Text(_mode.label, style: t.textTheme.bodyLarge),
                if (_correcting && _mode != PaymentMode.cash) ...[
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      '— recorded online, kept as it is',
                      style: t.textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
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
              // onPrimary, not the progress theme's colour — that is scheme.primary, which is
              // this button's own fill, so the spinner was violet on violet.
              child: _busy
                  ? InlineSpinner(onFill: t.colorScheme.onPrimary)
                  : Text(_correcting ? 'Save correction' : 'Record payment'),
            ),
            // OFFERED ONLY WHEN THERE IS SOMETHING TO CORRECT. wd_correct_payment refuses a
            // month with no row ("There is nothing recorded for that month to correct."), and a
            // button that can only produce that sentence is not a button. Quiet, and below the
            // action: correcting is the rarer errand, and the common one is taking money.
            if (correctable) ...[
              const SizedBox(height: Space.xs),
              TextButton(
                onPressed: _busy ? null : () => _toggleCorrecting(existing),
                child: Text(
                  _correcting ? 'Record a payment instead' : 'Correct what is recorded',
                ),
              ),
              if (_correcting)
                Text(
                  'The ledger says ${money(existing.amountPaid)} was received for '
                  '${monthLabel(widget.periodMonth)}. Enter what it should say.',
                  style: t.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
            ],
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
  const _Recorded({
    required this.row,
    required this.studentName,
    required this.corrected,
    required this.onDone,
  });

  final FeePayment row;
  final String studentName;

  /// Whether the write that produced [row] SET the month's total rather than adding to it. Only
  /// changes the words: a correction that says "Payment recorded" is how a warden convinces
  /// themselves they took money they did not take.
  final bool corrected;

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

    // assign-bed-success.png's panel: a haloed mint tick, the outcome in words, then the
    // SUMMARY of what was written under a `label-caps` heading, then the ways on.
    //
    // Every line of that summary is a field of [row] — the composite the RPC returned — which
    // is the whole reason the panel is worth having here: it puts the ledger's own numbers in
    // front of the resident standing at the desk.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SuccessPanel(
          title: corrected ? 'Ledger corrected' : 'Payment recorded',
          message: row.amountPaid <= 0
              ? 'This month now shows nothing received.'
              : row.balance > 0
                  ? '${money(row.balance)} of this month is still outstanding.'
                  : 'This month is settled in full.',
          summaryTitle: 'Receipt summary',
          summary: [
            ('Resident', studentName),
            ('Month', monthLabel(row.periodMonth)),
            ('Now on the ledger', money(row.amountPaid)),
            if (row.paidOn != null) ('Received on', shortDate(row.paidOn!)),
            if (row.balance > 0) ('Still outstanding', money(row.balance)),
          ],
        ),
        const SizedBox(height: Space.md),
        if (receipt != null) ...[
          FilledButton.icon(
            onPressed: () => showReceipt(context, receipt),
            icon: const Icon(Icons.receipt_long_rounded, size: IconSize.md),
            label: const Text('Print a receipt'),
          ),
          const SizedBox(height: Space.xs),
          Text(
            // The second sentence is a fact about the app, not a promise this sheet makes:
            // registration always creates a login (warden-register-student mints one from the
            // resident's email or their phone), the `fees_select` policy admits the resident
            // their own rows, and their Fees screen builds the receipt from the same
            // fee_payments row this one came from — same figures, same receipt number. It is
            // here because a warden who knows that stops being the only copy of the document.
            'Prints on screen. Share it to the resident from there, or save it — they can '
            'also open it themselves on their Fees tab.',
            style: t.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.sm),
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
    // No row yet means nothing has been paid — rpc_fee_ledger reports exactly that as 'unpaid',
    // so showing the same word here keeps the sheet and the list telling one story.
    final shown = status ?? FeeStatus.unpaid;
    // resident-profile.png's figure card: `label-caps` eyebrows over their values, the state
    // marked with its own dot, and the figure that is a call to act taking the colour.
    return FlatSurface(
      weight: GlassWeight.regular,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: CapsLabel('This month')),
              StatusPill(status: shown),
            ],
          ),
          const SizedBox(height: Space.sm),
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
          CapsLabel(label, tone: tone, dot: tone != null),
          const SizedBox(height: Space.xxs),
          Text(
            value,
            style: t.textTheme.titleSmall?.copyWith(
              color: tone == null ? t.colorScheme.onSurface : context.tones.resolve(tone!),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The card's own shape before the ledger row lands — never a spinner in a box, which is a
/// grey void where the warden already knows three figures live.
class _LedgerSkeleton extends StatelessWidget {
  const _LedgerSkeleton();
  @override
  Widget build(BuildContext context) => const SkeletonBlock(lines: 2);
}
