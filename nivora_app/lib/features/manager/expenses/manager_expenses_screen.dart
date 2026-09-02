library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../common/refresh.dart';
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
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Space.md),
          child: EmptyNote(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No hostel on this account',
            detail: 'A manager runs exactly one hostel. Ask the owner to check the assignment — '
                'until then there is nothing to show.',
          ),
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
          // 16 inside a 32dp button, which is the size the design draws a header glyph at
          // (4:454) — not 24 inside 40.
          icon: const Icon(Icons.add_rounded, size: IconSize.md),
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

/// Out / In. Two chips rather than two tabs: the role_shell tab list is the readable index of
/// this role's navigation, and a fifth destination that only ever shows a variant of the fourth
/// would make that index lie.
///
/// IT WAS A [SegmentedButton] AND IS NOT ANY MORE, for two reasons. Material's stock one is a
/// stadium with a tick in it, and there is not one capsule and not one tick in the nineteen
/// Figma frames — the design's way of saying "this is the selected one of these" is 4:1265, a
/// gold-filled chip at the control radius. And a segmented button divides its width equally
/// between fixed labels: at 1.6x text scale on a 320dp phone "Money out" and "Money in" do not
/// fit side by side, and it overflows rather than wrapping. A [Wrap] of [ToggleChip]s is the
/// design's own vocabulary AND drops to two lines when the type gets big.
class _Direction extends ConsumerWidget {
  const _Direction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final direction = ref.watch(moneyDirectionProvider);
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final d in MoneyDirection.values)
          ToggleChip(
            label: d.label,
            selected: direction == d,
            onSelected: (_) => ref.read(moneyDirectionProvider.notifier).set(d),
          ),
      ],
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
      // Bounded and spoken. AsyncSection keeps the book on screen through a failed reload,
      // so the gesture is the only thing that can report the failure — see
      // features/common/refresh.dart.
      onRefresh: () {
        ref.invalidate(managerExpensesProvider(query));
        return settleRefresh(context, () => ref.read(managerExpensesProvider(query).future));
      },
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
              ToggleChip(
                label: 'All',
                selected: selected == null,
                onSelected: (_) => notifier.set(null),
              ),
              // public.expense_category, every value, in its declared order.
              for (final c in ExpenseCategory.values) ...[
                const SizedBox(width: Space.xs),
                ToggleChip(
                  label: c.label,
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
          // A small squared badge tinted with the row's own meaning, drawn by the one widget
          // that owns that recipe. The 12% alpha this used to inline was a fifth number for a
          // thing NivoraSemantics already measures.
          ToneBadge(icon: _iconFor(expense.category), tone: NivoraColors.warning),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // body 13/400 over a 10px meta line — the design's row anatomy (4:1200/4:1201).
                // The weight in this row belongs to the AMOUNT, which is what a receipt is
                // being checked against.
                Text(
                  expense.category.label,
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface),
                ),
                const SizedBox(height: Space.xxs / 2),
                Text(
                  note == null || note.isEmpty
                      ? shortDate(expense.date)
                      : '${shortDate(expense.date)} · $note',
                  style: t.textTheme.labelSmall
                      ?.copyWith(color: context.tones.muted, letterSpacing: 0.2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          // Exact to the paise: this row is what a receipt gets checked against.
          //
          // SCALED DOWN, NEVER ELLIPSISED. At 1.6x text scale on a 320dp phone a lakh-sized
          // figure is wider than the space left beside its description, and the two ordinary
          // answers are both wrong here: `-₹2,45…` is a DIFFERENT NUMBER, and dropping the
          // paise is the rounding this row exists to avoid. BoxFit.scaleDown stops the figure
          // growing past the width available and changes nothing at ordinary text sizes.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text('-${moneyExact(expense.amount)}', style: t.textTheme.titleSmall),
            ),
          ),
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
      onRefresh: () {
        ref.invalidate(managerRevenuesProvider(hostelId));
        return settleRefresh(
            context, () => ref.read(managerRevenuesProvider(hostelId).future));
      },
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
          ToneBadge(icon: Icons.arrow_downward_rounded, tone: NivoraColors.success),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  revenue.source.label,
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface),
                ),
                const SizedBox(height: Space.xxs / 2),
                Text(
                  note == null || note.isEmpty
                      ? shortDate(revenue.date)
                      : '${shortDate(revenue.date)} · $note',
                  style: t.textTheme.labelSmall
                      ?.copyWith(color: context.tones.muted, letterSpacing: 0.2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          // Green, because the design reserves `tertiary` for the positive direction and this
          // is the one column on the screen that is money arriving. The expense row's figure
          // stays in `on-surface` — the design leaves its MONEY OUT totals uncoloured too, and
          // spending is not an error. Scaled rather than truncated, for the reason on the
          // expense row's own figure.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '+${moneyExact(revenue.amount)}',
                style: t.textTheme.titleSmall?.copyWith(color: context.tones.success),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
