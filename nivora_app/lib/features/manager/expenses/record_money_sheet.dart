library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../data/manager_providers.dart';
import '../widgets/manager_ui.dart';

/// Book money out (public.expenses) or money in (public.revenues).
///
/// ONE FORM FOR BOTH LEDGERS, because they are the same four fields with a different enum on
/// the front: what kind, how much, which day, and a note. Two near-identical files would drift
/// — one would gain the paise fix and the other would not.
///
/// THE MANAGER IS THE ONLY ROLE THAT MAY WRITE EITHER. rls-policies.sql puts
/// `has_role_in(hostel_id, 'manager')` on expenses_insert and revenues_insert; the owner can
/// read the books but not add to them. Nothing in this file enforces that — it is stated so
/// nobody wires this sheet into an owner screen and wonders why every save returns 42501.
///
/// THE VALIDATION HERE CATCHES TYPOS. IT DOES NOT DECIDE THE OUTCOME. The column is
/// `numeric(12,2) check (amount >= 0 and amount <= 100000000)`; the checks below are the same
/// bounds, one notch stricter at the bottom (a zero-rupee expense is a slip, not an entry), so
/// a mistake costs a keystroke rather than a round trip. If the two ever disagree, the database
/// is right.
Future<bool?> showRecordExpenseSheet(BuildContext context, {required String hostelId}) {
  return showGlassSheet<bool>(
    context: context,
    builder: (_) => _RecordMoneySheet(hostelId: hostelId, direction: MoneyDirection.out),
  );
}

Future<bool?> showRecordRevenueSheet(BuildContext context, {required String hostelId}) {
  return showGlassSheet<bool>(
    context: context,
    builder: (_) => _RecordMoneySheet(hostelId: hostelId, direction: MoneyDirection.inward),
  );
}

class _RecordMoneySheet extends ConsumerStatefulWidget {
  const _RecordMoneySheet({required this.hostelId, required this.direction});

  final String hostelId;
  final MoneyDirection direction;

  @override
  ConsumerState<_RecordMoneySheet> createState() => _RecordMoneySheetState();
}

class _RecordMoneySheetState extends ConsumerState<_RecordMoneySheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  ExpenseCategory _category = ExpenseCategory.groceries;
  RevenueSource _source = RevenueSource.mess;
  late DateTime _on = _today();
  bool _busy = false;

  bool get _isOut => widget.direction == MoneyDirection.out;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The check constraint's own ceiling, and a floor one notch above it.
  String? _validateAmount(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return 'Enter an amount';
    final value = double.tryParse(text);
    if (value == null) return 'Numbers only, for example 1250 or 1250.50';
    if (value <= 0) return 'Must be more than zero';
    if (value > 100000000) return 'Too large — the limit is ₹10,00,00,000';
    return null;
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _on,
      firstDate: DateTime(today.year - 1),
      // Not a server rule: public.expenses.date has no upper check. It is here because an
      // entry dated next Tuesday is always a slip of the finger, and the day it lands on is
      // the day the trend chart draws it.
      lastDate: today,
    );
    if (picked != null && mounted) {
      setState(() => _on = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final amount = double.parse(_amount.text.trim());
    final note = _note.text.trim();
    final repo = ref.read(financeRepositoryProvider);

    final ok = await runAction(
      context,
      success: _isOut
          ? '${moneyExact(amount)} out · ${_category.label}'
          : '${moneyExact(amount)} in · ${_source.label}',
      action: () => _isOut
          ? repo.addExpense(
              hostelId: widget.hostelId,
              category: _category,
              amount: amount,
              date: _on,
              note: note.isEmpty ? null : note,
            )
          : repo.addRevenue(
              hostelId: widget.hostelId,
              source: _source,
              amount: amount,
              date: _on,
              note: note.isEmpty ? null : note,
            ),
    );

    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      refreshMoney(ref);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return SheetBody(
      title: _isOut ? 'Record money out' : 'Record money in',
      subtitle: _isOut
          ? 'Goes to the hostel expense book'
          : 'Mess income, deposits — not rent, which the warden collects',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isOut ? 'CATEGORY' : 'SOURCE', style: t.textTheme.labelSmall),
            const SizedBox(height: Space.xs),
            // The choices ARE the Postgres enum, in its declared order. Nothing is added here
            // and nothing is hidden: a category that is not in public.expense_category cannot
            // be stored, and one that is would silently become "other".
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: _isOut
                  ? [
                      for (final c in ExpenseCategory.values)
                        ChoiceChip(
                          label: Text(c.label),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                    ]
                  : [
                      for (final s in RevenueSource.values)
                        ChoiceChip(
                          label: Text(s.label),
                          selected: _source == s,
                          onSelected: (_) => setState(() => _source = s),
                        ),
                    ],
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _amount,
              autofocus: true,
              // Paise are legal in the column, so the keyboard has to offer a decimal point.
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                helperText: 'Paise are allowed',
              ),
              validator: _validateAmount,
            ),
            const SizedBox(height: Space.md),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Date'),
              child: InkWell(
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xxs),
                  child: Row(
                    children: [
                      Expanded(child: Text(shortDate(_on), style: t.textTheme.bodyLarge)),
                      Icon(Icons.calendar_today_rounded,
                          size: IconSize.sm, color: t.colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _note,
              // expenses_note_len / revenues_note_len both cap this at 1000 characters.
              maxLength: 1000,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Vegetables from the Tuesday market',
              ),
            ),
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isOut ? 'Save expense' : 'Save entry'),
            ),
          ],
        ),
      ),
    );
  }
}
