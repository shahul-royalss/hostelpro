library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/perf/session_keep_alive.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import 'manager_models.dart';
import 'manager_repository.dart';

export '../../../data/providers.dart' show menuRepositoryProvider, weeklyMenuProvider;

/// Providers for the manager's four tabs.
///
/// HAND-WRITTEN, matching lib/data/providers.dart — no codegen, nothing to regenerate.
/// Anything the shared file already exposes is used from there and NOT redeclared:
/// financeRepositoryProvider, taskRepositoryProvider, tasksProvider, hostelProvider,
/// currentHostelIdProvider and sessionProvider all come straight off lib/data.
///
/// LIFETIMES follow the policy at the top of lib/data/providers.dart. The providers that BACK
/// A TAB — the task counts, the finance window, the weekly menu, and the two paged ledgers —
/// call `holdForSession` (the paged ones inherit it from PagedNotifier), so ManagerShell's
/// warm-up (see its initState) is not wasted and a revisited tab renders instantly from the
/// held value while any refresh happens behind it. The holds cannot leak: every one is a
/// family keyed by hostelId, so a different hostel is a different cache entry, and
/// holdForSession itself drops everything on sign-out or a change of user. The staff lookups
/// stay plain autoDispose — they back the task SHEET, not a tab.
///
/// ── ONE DELIBERATE ABSENCE: rpc_hostel_stats ────────────────────────────────────────────
///
/// Every other staff dashboard in this app opens with hostelStatsProvider. The manager's does
/// not, and it must not. That RPC is SECURITY INVOKER, so its counts are evaluated under the
/// caller's RLS — and a manager cannot read public.students, public.complaints, public.beds'
/// residents or public.fee_payments at all. The call would succeed and return a row whose
/// `active_students`, `open_complaints`, `fees_collected` and `students_unpaid` are all 0.
/// Not "unavailable": zero. Drawing that is fabricating data, which is the one thing this
/// codebase refuses to do. The manager's figures therefore come from the two tables and the
/// one RPC the role can genuinely read: public.tasks (counted server-side), public.expenses
/// and public.revenues (via rpc_daily_finance).

final managerRepositoryProvider = Provider<ManagerRepository>(
  (ref) => ManagerRepository(ref.watch(supabaseClientProvider)),
);

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN STATE
// ─────────────────────────────────────────────────────────────────────────────

/// Which of the four tabs is showing.
///
/// Lifted out of the shell so the home screen can act on a number rather than only print it:
/// "3 jobs overdue" is a fact, "3 jobs overdue — tap to work through them" is a tool.
class ManagerTab extends Notifier<int> {
  @override
  int build() => 0;

  void go(int index) => state = index;
}

final managerTabProvider = NotifierProvider<ManagerTab, int>(ManagerTab.new);

/// Which slice of public.tasks the Tasks tab is showing.
///
/// [needsAction] is `status <> 'done'` — pending AND in progress together. That is exactly
/// what [TaskLoad.open] counts, which is what lets the home screen's number and the list it
/// opens agree. A chip that showed only 'pending' would land the manager on a shorter list
/// than the figure they tapped, and a number you cannot reconcile is a number you stop
/// trusting.
enum TaskFilter {
  needsAction('To do'),
  pending('Pending'),
  inProgress('In progress'),
  done('Done');

  const TaskFilter(this.label);
  final String label;

  TaskStatus? get status => switch (this) {
        TaskFilter.needsAction => null,
        TaskFilter.pending => TaskStatus.pending,
        TaskFilter.inProgress => TaskStatus.inProgress,
        TaskFilter.done => TaskStatus.done,
      };

  bool get openOnly => this == TaskFilter.needsAction;
}

class TaskFilterState extends Notifier<TaskFilter> {
  @override
  TaskFilter build() => TaskFilter.needsAction;

  void set(TaskFilter filter) => state = filter;
}

final taskFilterProvider = NotifierProvider<TaskFilterState, TaskFilter>(TaskFilterState.new);

/// Which direction the money screen is showing. The manager writes both ledgers
/// (rls-policies.sql: expenses_insert and revenues_insert are both `has_role_in(…, 'manager')`),
/// so both are listable — otherwise a mis-keyed revenue entry could be created and never found.
enum MoneyDirection {
  out('Money out'),
  inward('Money in');

  const MoneyDirection(this.label);
  final String label;
}

class MoneyDirectionState extends Notifier<MoneyDirection> {
  @override
  MoneyDirection build() => MoneyDirection.out;

  void set(MoneyDirection value) => state = value;
}

final moneyDirectionProvider =
    NotifierProvider<MoneyDirectionState, MoneyDirection>(MoneyDirectionState.new);

/// Which category the expense list is narrowed to. Null is everything.
class ExpenseFilterState extends Notifier<ExpenseCategory?> {
  @override
  ExpenseCategory? build() => null;

  void set(ExpenseCategory? category) => state = category;
}

final expenseFilterProvider =
    NotifierProvider<ExpenseFilterState, ExpenseCategory?>(ExpenseFilterState.new);

/// Which day of the week the menu screen is showing. Starts on today.
class MenuDayState extends Notifier<MenuDay> {
  @override
  MenuDay build() => MenuDay.of(DateTime.now());

  void set(MenuDay day) => state = day;
}

final menuDayProvider = NotifierProvider<MenuDayState, MenuDay>(MenuDayState.new);

// ─────────────────────────────────────────────────────────────────────────────
// FAMILY KEYS
// ─────────────────────────────────────────────────────────────────────────────

/// Which expenses to list. Value equality, or Riverpod caches two entries for one query.
final class ExpenseQuery {
  const ExpenseQuery({required this.hostelId, this.category});

  final String hostelId;
  final ExpenseCategory? category;

  @override
  bool operator ==(Object other) =>
      other is ExpenseQuery && other.hostelId == hostelId && other.category == category;

  @override
  int get hashCode => Object.hash(hostelId, category);
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGINATED LISTS
// ─────────────────────────────────────────────────────────────────────────────

/// Expenses, newest day first, optionally one category. public.expenses.
///
/// The shared `expensesProvider` is keyed on a hostel id alone and cannot carry the category
/// filter this screen needs, so the manager has its own notifier over the SAME repository
/// method. No second query path to the table, just a second cache key.
///
/// PagedNotifier's default hold applies to every category variant too, and that is bounded on
/// purpose: the key space is one hostel times ExpenseCategory.values plus "All" — seven
/// entries at most, unlike a search box's per-keystroke keys, which is the case the
/// holdWhileSignedIn override exists for.
final managerExpensesProvider = AsyncNotifierProvider.autoDispose
    .family<ManagerExpensesNotifier, PagedResult<Expense>, ExpenseQuery>(
  ManagerExpensesNotifier.new,
);

class ManagerExpensesNotifier extends PagedNotifier<Expense> {
  ManagerExpensesNotifier(this.query);
  final ExpenseQuery query;

  @override
  Future<PagedResult<Expense>> fetchPage(int page) =>
      ref.read(financeRepositoryProvider).expenses(
            hostelId: query.hostelId,
            page: page,
            category: query.category,
          );
}

/// Revenue entries, newest day first. public.revenues.
final managerRevenuesProvider = AsyncNotifierProvider.autoDispose
    .family<ManagerRevenuesNotifier, PagedResult<Revenue>, String>(
  ManagerRevenuesNotifier.new,
);

class ManagerRevenuesNotifier extends PagedNotifier<Revenue> {
  ManagerRevenuesNotifier(this.hostelId);
  final String hostelId;

  @override
  Future<PagedResult<Revenue>> fetchPage(int page) =>
      ref.read(financeRepositoryProvider).revenues(hostelId: hostelId, page: page);
}

// ─────────────────────────────────────────────────────────────────────────────
// SINGLE READS
// ─────────────────────────────────────────────────────────────────────────────

/// How many jobs are open and how many are late. public.tasks, counted by Postgres.
///
/// Session-held: this one figure is read by the home tile, the Tasks-tab header AND the badge
/// on the navigation bar — one family instance, one pair of HEAD requests, and the badge rides
/// on whatever fetch is already live rather than making its own.
final taskLoadProvider =
    FutureProvider.autoDispose.family<TaskLoad, String>((ref, hostelId) {
  holdForSession(ref);
  final now = DateTime.now();
  return ref.watch(managerRepositoryProvider).taskCounts(
        hostelId: hostelId,
        today: DateTime(now.year, now.month, now.day),
      );
});

/// How many days of in-and-out the home screen draws.
const trendDays = 14;

/// Money in and out, day by day. public.rpc_daily_finance.
///
/// ONE REQUEST SERVES BOTH the month-to-date totals and the short trend beneath them: the
/// window fetched starts at whichever is earlier, the first of the month or [trendDays] ago,
/// and [FinanceWindow] slices it. Two providers would be two round trips for overlapping days.
///
/// The dates are normalised to local midnight before they reach the query, so the family key
/// is stable for the whole day. Passing `DateTime.now()` would mint a new cache entry on every
/// rebuild and refetch the series on every frame.
final managerFinanceProvider =
    FutureProvider.autoDispose.family<FinanceWindow, String>((ref, hostelId) async {
  holdForSession(ref);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monthStart = DateTime(now.year, now.month);
  // DateTime normalises a negative day into the previous month, so this is safe on the 3rd.
  final trendStart = DateTime(now.year, now.month, now.day - (trendDays - 1));
  final from = monthStart.isBefore(trendStart) ? monthStart : trendStart;

  final days = await ref.watch(financeRepositoryProvider).daily(
        hostelId: hostelId,
        from: from,
        to: today,
      );
  return FinanceWindow(
    days: days,
    monthStart: monthStart,
    trendStart: trendStart,
    today: today,
  );
});

// THE MESS MENU FOR THE WEEK — public.menus — IS DECLARED IN lib/data/providers.dart AND
// RE-EXPORTED FROM THIS FILE (see the export beside the imports), because the manager is no
// longer the only role that reads these rows: a resident's home screen now watches the same
// provider. The re-export keeps that invisible to this directory — the manager screens, and
// the manager tests that override `weeklyMenuProvider` off this import, are addressing the one
// and only instance of it.

/// Owner, manager and warden of this hostel, by name. public.users.
final hostelStaffProvider =
    FutureProvider.autoDispose.family<List<StaffMember>, String>((ref, hostelId) {
  return ref.watch(managerRepositoryProvider).staff(hostelId);
});

/// user id to display name, for a task's assignment lines.
///
/// A name that is not in the map is drawn as "Someone else", never as a uuid: a colleague may
/// have been deactivated since the task was raised, and RLS then stops returning their row.
final staffNamesProvider =
    FutureProvider.autoDispose.family<Map<String, String>, String>((ref, hostelId) async {
  final staff = await ref.watch(hostelStaffProvider(hostelId).future);
  return {for (final s in staff) s.id: s.fullName};
});

// ─────────────────────────────────────────────────────────────────────────────
// REFRESH AFTER A WRITE
//
// The server is the only thing that knows the new truth — the day series is aggregated by
// Postgres and `completed_at` is stamped by a trigger this client never sees — so the response
// to a successful write is to re-read, never to patch a local copy into agreement.
//
// The lists are deliberately narrow. The shell keeps all four tabs alive, so an over-broad
// invalidate is four refetches on a phone that may be on 3G in a store room.
// ─────────────────────────────────────────────────────────────────────────────

/// An expense or a revenue entry was booked.
void refreshMoney(WidgetRef ref) {
  ref.invalidate(managerExpensesProvider);
  ref.invalidate(managerRevenuesProvider);
  ref.invalidate(managerFinanceProvider);
}

/// A task moved along the workflow. The counts move with it.
void refreshTasks(WidgetRef ref) {
  ref.invalidate(tasksProvider);
  ref.invalidate(taskLoadProvider);
}

/// A meal was written.
void refreshMenu(WidgetRef ref) {
  ref.invalidate(weeklyMenuProvider);
}
