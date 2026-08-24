library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../data/manager_providers.dart';
import '../widgets/manager_ui.dart';
import '../widgets/paged_list.dart';
import 'record_money_sheet.dart';

/// The hostel's day-to-day book: what went out, what came in, and a way to add to either.
///
/// TABLES: public.expenses, public.revenues. Both are readable by the owner and the manager
/// and WRITABLE ONLY BY THE MANAGER (rls-policies.sql) — this screen is where those two
/// ledgers are kept.
///
/// THE CATEGORY CHIPS ARE public.expense_category, IN FULL. Six values, in the order the type
/// declares them, with no invented seventh and none of the six hidden. A filter that offered a
/// category the enum does not have would return an empty list and look like a hostel that
/// never buys anything; one that quietly dropped a category would hide real money.
///
/// MONEY IN IS ON THIS SCREEN TOO, behind a segmented control. It is the same ledger pair the
/// home screen totals, and a revenue entry keyed with the wrong amount has to be findable by
/// the person allowed to fix it. The label never says "revenue" without saying "recorded":
/// rent is collected into public.fee_payments by the warden, is not in this table, and a
/// manager cannot read it at all.
class ManagerExpensesScreen extends ConsumerWidget {
  const ManagerExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);
    final direction = ref.watch(moneyDirectionProvider);

    if (hostelId == null) {
      return const ManagerScreen(
        title: 'Money',
        child: EmptyNote(
          icon: Icons.account_balance_wallet_outlined,
          title: 'No hostel on this account',
          detail: 'A manager runs exactly one hostel. Ask the owner to check the assignment — '
              'until then there is nothing to show.',
        ),
      );
    }

    return ManagerScreen(
      title: 'Money',
      subtitle: direction == MoneyDirection.out
          ? 'Everything the hostel has spent'
          : 'Entries booked by hand — not rent',
      actions: [
        IconButton(
          tooltip: direction == MoneyDirection.out ? 'Record an expense' : 'Record money in',
          icon: const Icon(Icons.add_rounded),
          onPressed: () => direction == MoneyDirection.out
              ? showRecordExpenseSheet(context, hostelId: hostelId)
              : showRecordRevenueSheet(context, hostelId: hostelId),
        ),
      ],
      child: direction == MoneyDirection.out
          ? _ExpenseList(hostelId: hostelId)
          : _RevenueList(hostelId: hostelId),
    );
  }
}

/// Out / In. A segmented control rather than two tabs: the role_shell tab list is the readable
/// index of this role's navigation, and a fifth destination that only ever shows a variant of
/// the fourth would make that index lie.
class _Direction extends ConsumerWidget {
  const _Direction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final direction = ref.watch(moneyDirectionProvider);
    return SegmentedButton<MoneyDirection>(
      showSelectedIcon: false,
      segments: [
        for (final d in MoneyDirection.values)
          ButtonSegment<MoneyDirection>(value: d, label: Text(d.label)),
      ],
      selected: {direction},
      onSelectionChanged: (s) => ref.read(moneyDirectionProvider.notifier).set(s.first),
    );
  }
}

class _ExpenseList extends ConsumerWidget {
  const _ExpenseList({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(expenseFilterProvider);
    final query = ExpenseQuery(hostelId: hostelId, category: category);
    final page = ref.watch(managerExpensesProvider(query));

    return PagedList<Expense>(
      value: page,
      onRefresh: () async => ref.invalidate(managerExpensesProvider(query)),
      onLoadMore: () => ref.read(managerExpensesProvider(query).notifier).loadMore(),
      header: const _ExpenseFilters(),
      empty: EmptyNote(
        icon: Icons.receipt_long_outlined,
        title: category == null
            ? 'Nothing booked yet'
            : 'Nothing under ${category.label.toLowerCase()}',
        detail: category == null
            ? 'Tap + to record the first expense. It shows on the trend the same day.'
            : 'Clear the filter to see the rest of the book.',
      ),
      itemBuilder: (context, expense) => _ExpenseRow(expense: expense),
    );
  }
}

class _ExpenseFilters extends ConsumerWidget {
  const _ExpenseFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(expenseFilterProvider);
    final notifier = ref.read(expenseFilterProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Direction(),
        const SizedBox(height: Space.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: selected == null,
                onSelected: (_) => notifier.set(null),
              ),
              // public.expense_category, every value, in its declared order.
              for (final c in ExpenseCategory.values) ...[
                const SizedBox(width: Space.xs),
                ChoiceChip(
                  label: Text(c.label),
                  selected: selected == c,
                  onSelected: (_) => notifier.set(selected == c ? null : c),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
      ],
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense});
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final note = expense.note?.trim();
    return TapRow(
      semanticLabel: '${expense.category.label}, ${moneyExact(expense.amount)}, '
          '${shortDate(expense.date)}',
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.tones.warning.withValues(alpha: 0.12),
              borderRadius: Radii.rControl,
            ),
            child: Icon(_iconFor(expense.category),
                size: IconSize.md, color: context.tones.warning),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.category.label, style: t.textTheme.titleSmall),
                Text(
                  note == null || note.isEmpty
                      ? shortDate(expense.date)
                      : '${shortDate(expense.date)} · $note',
                  style: t.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          // Exact to the paise: this row is what a receipt gets checked against.
          Text('-${moneyExact(expense.amount)}', style: t.textTheme.titleSmall),
        ],
      ),
    );
  }

  /// A glyph per category. Decoration only — the words are always there next to it, because an
  /// icon is not a label and "staff" and "maintenance" look alike at 18dp.
  static IconData _iconFor(ExpenseCategory category) => switch (category) {
        ExpenseCategory.groceries => Icons.shopping_basket_rounded,
        ExpenseCategory.staff => Icons.badge_rounded,
        ExpenseCategory.electricity => Icons.bolt_rounded,
        ExpenseCategory.water => Icons.water_drop_rounded,
        ExpenseCategory.maintenance => Icons.handyman_rounded,
        ExpenseCategory.other => Icons.more_horiz_rounded,
      };
}

class _RevenueList extends ConsumerWidget {
  const _RevenueList({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(managerRevenuesProvider(hostelId));

    return PagedList<Revenue>(
      value: page,
      onRefresh: () async => ref.invalidate(managerRevenuesProvider(hostelId)),
      onLoadMore: () => ref.read(managerRevenuesProvider(hostelId).notifier).loadMore(),
      header: const Padding(
        padding: EdgeInsets.only(bottom: Space.sm),
        child: _Direction(),
      ),
      empty: const EmptyNote(
        icon: Icons.savings_outlined,
        title: 'Nothing recorded here',
        detail: 'Mess income and deposits go here. Rent is collected by the warden and is '
            'counted separately.',
      ),
      itemBuilder: (context, revenue) => _RevenueRow(revenue: revenue),
    );
  }
}

class _RevenueRow extends StatelessWidget {
  const _RevenueRow({required this.revenue});
  final Revenue revenue;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final note = revenue.note?.trim();
    return TapRow(
      semanticLabel: '${revenue.source.label}, ${moneyExact(revenue.amount)}, '
          '${shortDate(revenue.date)}',
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.tones.success.withValues(alpha: 0.12),
              borderRadius: Radii.rControl,
            ),
            child: Icon(Icons.arrow_downward_rounded,
                size: IconSize.md, color: context.tones.success),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(revenue.source.label, style: t.textTheme.titleSmall),
                Text(
                  note == null || note.isEmpty
                      ? shortDate(revenue.date)
                      : '${shortDate(revenue.date)} · $note',
                  style: t.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          Text('+${moneyExact(revenue.amount)}', style: t.textTheme.titleSmall),
        ],
      ),
    );
  }
}
