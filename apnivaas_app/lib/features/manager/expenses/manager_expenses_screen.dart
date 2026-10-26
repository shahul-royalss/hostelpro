library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/finance/expense_stats_screen.dart';
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
/// MONEY IN IS ON THIS SCREEN TOO, behind the Money out / Money in chips. It is the same ledger
/// pair the home screen totals, and a revenue entry keyed with the wrong amount has to be
/// findable by the person allowed to fix it. The label never says "revenue" without saying
/// "recorded": rent is collected into public.fee_payments by the warden, is not in this table,
/// and a manager cannot read it at all.
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
          child: EmptyState(
            icon: ClayIcons.navProperty,
            title: 'No hostel on this account',
            body: 'A manager runs exactly one hostel. Ask the owner to check the assignment — '
                'until then there is nothing to show.',
          ),
        ),
      );
    }

    final out = direction == MoneyDirection.out;
    return ManagerScreen(
      title: 'Money',
      subtitle: out ? 'Everything the hostel has spent' : 'Entries booked by hand — not rent',
      actions: [
        // The charts are about EXPENSES, so the way in sits on the expense side of the switch.
        // It opens the same screen the owner opens from More: one set of figures, one widget,
        // no second place for them to drift.
        if (out)
          HeaderIconButton(
            icon: Icons.bar_chart_rounded,
            label: 'Month by month',
            onPressed: () => Navigator.of(context).push(ExpenseStatsScreen.route(hostelId)),
          ),
        // TWO KINDS OF MONEY OUT, one kind of money in.
        //
        // The product owner asked for exactly this split: "one time monthly expense" and "day
        // to day expenses". They are two different acts — a bill that belongs to a month, and
        // a purchase that belongs to a day — and the sheet asks a different question for each,
        // so the choice is made before it opens rather than as a toggle inside it.
        //
        // Revenue goes straight to its sheet: public.revenues has no kind column, and offering
        // the same choice there would be a control that writes nowhere.
        HeaderIconButton(
          icon: Icons.add_rounded,
          label: out ? 'Record an expense' : 'Record money in',
          onPressed: out
              ? () => _chooseAndRecord(context, hostelId)
              : () => showRecordRevenueSheet(context, hostelId: hostelId),
        ),
      ],
      child: out ? _ExpenseList(hostelId: hostelId) : _RevenueList(hostelId: hostelId),
    );
  }

  /// Which kind of expense, asked on a sheet of its own — each kind with its clay art and the
  /// sentence that tells the two apart — and then the recording sheet for that kind.
  static Future<void> _chooseAndRecord(BuildContext context, String hostelId) async {
    final kind = await showApnivaasSheet<ExpenseKind>(
      context: context,
      title: 'Record an expense',
      subtitle: 'A purchase belongs to a day; a bill belongs to a month.',
      builder: (sheet) => ListGroup(
        children: [
          ListRow(
            icon: ClayIcons.expense,
            title: 'Day-to-day expense',
            subtitle: 'Vegetables, gas, a repair',
            onTap: () => Navigator.of(sheet).pop(ExpenseKind.daily),
          ),
          ListRow(
            icon: ClayIcons.invoice,
            title: 'Monthly expense',
            subtitle: 'Rent, salaries, a bill — once for a month',
            onTap: () => Navigator.of(sheet).pop(ExpenseKind.monthly),
          ),
        ],
      ),
    );
    if (kind == null || !context.mounted) return;
    await showRecordExpenseSheet(context, hostelId: hostelId, kind: kind);
  }
}

/// Out / In. Two chips rather than two tabs: the role_shell tab list is the readable index of
/// this role's navigation, and a fifth destination that only ever shows a variant of the fourth
/// would make that index lie.
///
/// A [Wrap] OF [ToggleChip]s, NOT A SegmentedButton. A segmented button divides its width
/// equally between fixed labels: at 1.6x text scale on a 320dp phone "Money out" and "Money in"
/// do not fit side by side, and it overflows rather than wrapping. A Wrap of the screen's own
/// filter pills drops to two lines when the type gets big.
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
    final kind = ref.watch(expenseKindFilterProvider);
    final query = ExpenseQuery(hostelId: hostelId, category: category, kind: kind);
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
      // A filtered book that is empty says "no match for that" in the category's own art; the
      // whole book empty is the first-run face, and invites the first entry.
      empty: EmptyState(
        icon: category == null ? ClayIcons.expense : _clayFor(category),
        title: category == null
            ? 'Nothing booked yet'
            : 'Nothing under ${category.label.toLowerCase()}',
        body: category == null
            ? 'Tap + and choose a monthly or a day-to-day expense. It shows on the charts the '
                'same day.'
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
        const SizedBox(height: Space.xs),
        // KIND FIRST, THEN CATEGORY. Two axes, narrowing different things: "what do the monthly
        // bills come to" is a question about kind alone, and having to clear a category to ask
        // it would be the filter fighting the question.
        // A WRAP, NOT A ROW. Three chips do not fit 320dp at 2.0x text — the manager suite
        // pumps exactly that — and a Row has no give: it overflows with the hazard stripe
        // rather than dropping to a second line. The category row below solves the same
        // problem by scrolling horizontally; this one has few enough chips to wrap.
        //
        // "All kinds", not "All": the category row already has an "All" chip, and two controls
        // with the same word on one screen is a screen that cannot be described out loud.
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            ToggleChip(
              label: 'All kinds',
              selected: ref.watch(expenseKindFilterProvider) == null,
              onSelected: (_) => ref.read(expenseKindFilterProvider.notifier).set(null),
            ),
            for (final k in ExpenseKind.values)
              ToggleChip(
                label: k.label,
                selected: ref.watch(expenseKindFilterProvider) == k,
                onSelected: (_) => ref
                    .read(expenseKindFilterProvider.notifier)
                    .set(ref.read(expenseKindFilterProvider) == k ? null : k),
              ),
          ],
        ),
        const SizedBox(height: Space.xs),
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
        const SizedBox(height: Space.xs),
      ],
    );
  }
}

/// The clay art for a category. Decoration only — the words are always beside it, because a
/// picture is not a label and "staff" and "maintenance" are not obvious at 46dp.
String _clayFor(ExpenseCategory category) => switch (category) {
      ExpenseCategory.groceries => ClayIcons.food,
      ExpenseCategory.staff => ClayIcons.team,
      ExpenseCategory.electricity => ClayIcons.electricity,
      ExpenseCategory.water => ClayIcons.water,
      ExpenseCategory.maintenance => ClayIcons.settings,
      ExpenseCategory.other => ClayIcons.expense,
    };

/// One expense: the category's art, the category, the day and the note, and the amount.
///
/// ── DIRECTION LIVES IN THE SIGN, NOT THE HUE ─────────────────────────────────────────────
///
/// Money going out is the ordinary business of running a hostel, not a warning, so the figure
/// stays in the ink with a minus in front of it; the money-in row's figure is the one in green.
/// Amber is what an open complaint and a partly paid month wear, and a ledger with amber rows in
/// it would be the tab disagreeing with itself.
class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense});
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final note = expense.note?.trim();
    return ListRowCard(
      icon: _clayFor(expense.category),
      title: expense.category.label,
      // A MONTHLY EXPENSE IS DATED THE FIRST, and that day means nothing: the bill belongs to
      // the month. Printing "1 Sep" for it would invite somebody to "correct" it. The kind is
      // named on the row for the same reason the filter exists — two bills of the same
      // category can be different kinds.
      subtitle: [
        if (expense.kind == ExpenseKind.monthly)
          'Monthly · ${monthTitle(expense.date)}'
        else
          shortDate(expense.date),
        if (note != null && note.isNotEmpty) note,
      ].join(' · '),
      // Exact to the paise: this row is what a receipt gets checked against. NEVER ELLIPSISED
      // — `-₹2,45…` is a DIFFERENT NUMBER. The row moves the figure under the words when the
      // two do not fit side by side (narrow phones, large text) rather than cutting it.
      // Out of the semantics tree: the row's label already says the amount, once, with its
      // direction in words rather than in a minus sign a screen reader may not voice.
      trailing: ExcludeSemantics(
        child: ListRowAmount(amount: '-${moneyExact(expense.amount)}'),
      ),
      semanticLabel: '${expense.category.label}, ${moneyExact(expense.amount)} out, '
          '${shortDate(expense.date)}${note == null || note.isEmpty ? '' : ', $note'}',
    );
  }
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
        padding: EdgeInsets.only(bottom: Space.xs),
        child: _Direction(),
      ),
      empty: const EmptyState(
        icon: ClayIcons.money,
        title: 'Nothing recorded here',
        body: 'Mess income and deposits go here. Rent is collected by the warden and is '
            'counted separately.',
      ),
      itemBuilder: (context, revenue) => _RevenueRow(revenue: revenue),
    );
  }
}

/// One entry of money in. The figure is green — the one column on this tab that is money
/// arriving — and carries a plus, so the direction is said by the sign as well as the hue.
class _RevenueRow extends StatelessWidget {
  const _RevenueRow({required this.revenue});
  final Revenue revenue;

  /// The clay art for where the money came from.
  static String _clayFor(RevenueSource source) => switch (source) {
        RevenueSource.fees => ClayIcons.receipt,
        RevenueSource.mess => ClayIcons.food,
        RevenueSource.other => ClayIcons.money,
      };

  @override
  Widget build(BuildContext context) {
    final note = revenue.note?.trim();
    return ListRowCard(
      icon: _clayFor(revenue.source),
      title: revenue.source.label,
      subtitle: note == null || note.isEmpty
          ? shortDate(revenue.date)
          : '${shortDate(revenue.date)} · $note',
      trailing: ExcludeSemantics(
        child: ListRowAmount(
          amount: '+${moneyExact(revenue.amount)}',
          amountTone: StatusTone.success,
        ),
      ),
      semanticLabel: '${revenue.source.label}, ${moneyExact(revenue.amount)} in, '
          '${shortDate(revenue.date)}${note == null || note.isEmpty ? '' : ', $note'}',
    );
  }
}
