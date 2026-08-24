// Tests for the manager experience.
//
// These cover the failures that compile cleanly and would only be found by somebody standing
// in a hostel kitchen: a month total that quietly counts last month's days, a task count taken
// from page zero of a paginated list, a menu that claims there is no dinner on Sunday when
// nobody has ever written one down, an expense category the database cannot store — and the
// big one for this role, a dashboard figure that RLS zeroes out and the screen prints anyway.
//
// The widget tests deliberately do NOT use NivoraTheme: it is built on google_fonts, which
// reaches for the network from inside the test binary. Nothing under test depends on the
// typeface — only on the scale's slot names, which the stock theme has too.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/manager/data/manager_models.dart';
import 'package:mobile/features/manager/data/manager_providers.dart';
import 'package:mobile/features/manager/expenses/manager_expenses_screen.dart';
import 'package:mobile/features/manager/home/manager_home_screen.dart';
import 'package:mobile/features/manager/manager_shell.dart';
import 'package:mobile/features/manager/menu/manager_menu_screen.dart';
import 'package:mobile/features/manager/tasks/manager_tasks_screen.dart';
import 'package:mobile/features/manager/widgets/manager_ui.dart';
import 'package:mobile/features/shell/role_shell.dart';

const _hostelId = 'h1';
const _managerId = 'u-manager';
const _ownerId = 'u-owner';

void main() {
  setUp(() => _statsWereRead = false);

  // ───────────────────────────────────────────────────────────────────────────
  group('public.menus is read the way schema.sql declares it', () {
    Map<String, dynamic> row({
      String day = 'wed',
      String meal = 'lunch',
      String items = 'Rice, dal, beans poriyal',
    }) =>
        {
          'id': 'm1',
          'hostel_id': _hostelId,
          'day_of_week': day,
          'meal': meal,
          'items': items,
          'updated_by': _managerId,
          'created_at': '2026-08-01T09:00:00+00:00',
          'updated_at': '2026-08-20T09:00:00+00:00',
        };

    test('day and meal are matched by wire value, never by enum position', () {
      final entry = MenuEntry.fromJson(row(day: 'sun', meal: 'snacks'));
      expect(entry.day, MenuDay.sun);
      expect(entry.meal, Meal.snacks);
      expect(MenuDay.tryParse('Mon'), isNull, reason: 'the match is exact');
      expect(Meal.tryParse('brunch'), isNull);
    });

    test('a day this build has never heard of throws rather than guessing', () {
      // public.day_of_week is exactly mon..sun. Anything else means the database has moved
      // and this build has not — which must be loud, not silently rendered as Monday.
      expect(() => MenuEntry.fromJson(row(day: 'caturday')), throwsA(isA<RowShapeError>()));
      expect(() => MenuEntry.fromJson(row(meal: 'supper')), throwsA(isA<RowShapeError>()));
    });

    test('MenuDay.of maps every weekday the way Dart numbers them', () {
      // 2026-08-24 is a Monday. Seven consecutive days must give seven distinct enum values in
      // the right order — an off-by-one here serves Tuesday's food on Monday.
      const expected = [
        MenuDay.mon, MenuDay.tue, MenuDay.wed, MenuDay.thu,
        MenuDay.fri, MenuDay.sat, MenuDay.sun,
      ];
      for (var i = 0; i < 7; i++) {
        expect(MenuDay.of(DateTime(2026, 8, 24 + i)), expected[i]);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('a meal nobody has written down is not an empty meal', () {
    MenuEntry entry(MenuDay day, Meal meal, String items) => MenuEntry(
          id: '${day.wire}-${meal.wire}',
          hostelId: _hostelId,
          day: day,
          meal: meal,
          items: items,
          createdAt: DateTime.utc(2026, 8, 1),
          updatedAt: DateTime.utc(2026, 8, 20),
        );

    test('a missing row reads as null, not as an empty string', () {
      final week = WeeklyMenu([entry(MenuDay.mon, Meal.lunch, 'Rice, sambar')]);
      expect(week.itemsFor(MenuDay.mon, Meal.lunch), 'Rice, sambar');
      expect(week.itemsFor(MenuDay.mon, Meal.dinner), isNull);
      expect(week.itemsFor(MenuDay.sun, Meal.lunch), isNull);
    });

    test('a saved-but-blank row also reads as not planned', () {
      // The column is NOT NULL default '', so clearing a meal leaves a row behind. Both states
      // mean the same thing to a reader and must render the same way.
      final week = WeeklyMenu([
        entry(MenuDay.tue, Meal.snacks, ''),
        entry(MenuDay.tue, Meal.dinner, '   '),
      ]);
      expect(week.itemsFor(MenuDay.tue, Meal.snacks), isNull);
      expect(week.itemsFor(MenuDay.tue, Meal.dinner), isNull);
      expect(week.isEmpty, isTrue);
    });

    test('the day strip counts only the meals that are actually planned', () {
      final week = WeeklyMenu([
        entry(MenuDay.wed, Meal.breakfast, 'Idli'),
        entry(MenuDay.wed, Meal.lunch, 'Rice'),
        entry(MenuDay.wed, Meal.snacks, ''),
      ]);
      expect(week.plannedOn(MenuDay.wed), 2);
      expect(week.plannedOn(MenuDay.thu), 0);
    });

    test('lastUpdated is the newest row in the week, not the first one read', () {
      final week = WeeklyMenu([
        entry(MenuDay.mon, Meal.lunch, 'A'),
        MenuEntry(
          id: 'later',
          hostelId: _hostelId,
          day: MenuDay.fri,
          meal: Meal.dinner,
          items: 'B',
          createdAt: DateTime.utc(2026, 8, 1),
          updatedAt: DateTime.utc(2026, 8, 23),
        ),
      ]);
      expect(week.lastUpdated, DateTime.utc(2026, 8, 23));
      expect(const WeeklyMenu.empty().lastUpdated, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the month totals count the month, and only the month', () {
    // The RPC is asked for one window that covers BOTH the month so far and the last fourteen
    // days. Early in a month those are different ranges, and the totals must not quietly
    // include the tail of the previous month that the trend needs.
    FinanceWindow crossMonth() {
      final days = <FinanceDay>[
        for (var d = 23; d <= 31; d++)
          FinanceDay(day: DateTime(2026, 7, d), revenue: 100, expense: 200),
        for (var d = 1; d <= 5; d++)
          FinanceDay(day: DateTime(2026, 8, d), revenue: 1000, expense: 400),
      ];
      return FinanceWindow(
        days: days,
        monthStart: DateTime(2026, 8),
        trendStart: DateTime(2026, 7, 23),
        today: DateTime(2026, 8, 5),
      );
    }

    test('July is in the trend and out of the month total', () {
      final w = crossMonth();
      expect(w.trendDays.length, 14, reason: '9 days of July plus 5 of August');
      expect(w.monthDays.length, 5);
      expect(w.monthIn, 5000, reason: '5 x 1000, with no July revenue in it');
      expect(w.monthOut, 2000, reason: '5 x 400');
      expect(w.monthNet, 3000);
    });

    test('a month that spent more than it booked reads negative', () {
      final w = FinanceWindow(
        days: [
          FinanceDay(day: DateTime(2026, 8, 1), revenue: 500, expense: 4000),
          FinanceDay(day: DateTime(2026, 8, 2), revenue: 0, expense: 1500),
        ],
        monthStart: DateTime(2026, 8),
        trendStart: DateTime(2026, 8),
        today: DateTime(2026, 8, 2),
      );
      expect(w.monthNet, -5000);
    });

    test("today's spend is today's row, and a missing today is null rather than zero", () {
      final w = crossMonth();
      expect(w.todayOut, 400);
      expect(w.todayIn, 1000);

      final noToday = FinanceWindow(
        days: [FinanceDay(day: DateTime(2026, 8, 1), revenue: 1, expense: 2)],
        monthStart: DateTime(2026, 8),
        trendStart: DateTime(2026, 8),
        today: DateTime(2026, 8, 5),
      );
      expect(noToday.todayOut, isNull,
          reason: 'a dash is honest about what is unknown; a zero is a claim');
    });

    test('the bar scale is the peak of the TREND, not of the whole fetched window', () {
      final w = FinanceWindow(
        days: [
          // Outside the trend, and much larger — it must not flatten the bars.
          FinanceDay(day: DateTime(2026, 8, 1), revenue: 99000, expense: 0),
          FinanceDay(day: DateTime(2026, 8, 10), revenue: 300, expense: 900),
          FinanceDay(day: DateTime(2026, 8, 11), revenue: 100, expense: 100),
        ],
        monthStart: DateTime(2026, 8),
        trendStart: DateTime(2026, 8, 10),
        today: DateTime(2026, 8, 11),
      );
      expect(w.trendPeak, 900);
    });

    test('an empty series totals zero without throwing', () {
      final w = FinanceWindow(
        days: const [],
        monthStart: DateTime(2026, 8),
        trendStart: DateTime(2026, 8),
        today: DateTime(2026, 8, 5),
      );
      expect(w.monthIn, 0);
      expect(w.trendPeak, 0);
      expect(w.todayOut, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('money and dates are said the way an Indian hostel reads them', () {
    test('grouping is lakh-style, not thousand-style', () {
      // 1,200,000 would be read as twelve lakh by a machine and as one point two crore by
      // nobody. The en_IN pattern is the whole point.
      expect(money(1200000), '₹12,00,000');
      expect(money(18500), '₹18,500');
    });

    test('a ledger row keeps its paise; a summary does not invent them', () {
      // public.expenses.amount is numeric(12,2). Rounding it away on the one screen where a
      // figure is checked against a receipt is how a ledger stops reconciling.
      expect(moneyExact(1250), '₹1,250');
      expect(moneyExact(1250.75), '₹1,250.75');
      expect(moneyExact(1250.5), '₹1,250.50');
    });

    test('short money uses Indian units', () {
      expect(moneyShort(120000), '₹1.2L');
      expect(moneyShort(2500), '₹2.5k');
      expect(moneyShort(900), '₹900');
    });

    test('a due date is compared on the calendar day, not on elapsed hours', () {
      // 23:00 today and 01:00 tomorrow are two hours apart and are not the same answer.
      final lateTonight = DateTime(2026, 8, 25, 23, 0);
      expect(dueLabel(DateTime(2026, 8, 25), now: lateTonight), 'Due today');
      expect(dueLabel(DateTime(2026, 8, 26), now: lateTonight), 'Due tomorrow');
      expect(dueLabel(DateTime(2026, 8, 24), now: lateTonight), '1 day late');
      expect(dueLabel(DateTime(2026, 8, 20), now: lateTonight), '5 days late');
      expect(dueLabel(DateTime(2026, 8, 28), now: lateTonight), 'Due Friday');
      expect(dueLabel(DateTime(2026, 9, 30), now: lateTonight), 'Due 30 Sep');
    });

    test('counts are pluralised once, here', () {
      expect(plural(1, 'job', 'jobs'), '1 job');
      expect(plural(0, 'job', 'jobs'), '0 jobs');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the filter a number opens is the filter the number counted', () {
    test("'To do' is status <> done — the same set TaskLoad.open counts", () {
      // If this chip narrowed to 'pending' only, tapping "4 jobs open" would land on a shorter
      // list than the figure said, and a figure you cannot reconcile is one you stop trusting.
      expect(TaskFilter.needsAction.status, isNull);
      expect(TaskFilter.needsAction.openOnly, isTrue);

      expect(TaskFilter.pending.status, TaskStatus.pending);
      expect(TaskFilter.pending.openOnly, isFalse);
      expect(TaskFilter.done.status, TaskStatus.done);
    });

    test('the home screen and the tasks tab build the SAME query key', () {
      // Both use hostel + openOnly with no status. TaskQuery has value equality, so this is
      // one cache entry and one request, and the two screens cannot show a different order.
      const fromHome = TaskQuery(hostelId: _hostelId, openOnly: true);
      final fromTab = TaskQuery(
        hostelId: _hostelId,
        status: TaskFilter.needsAction.status,
        openOnly: TaskFilter.needsAction.openOnly,
      );
      expect(fromHome, fromTab);
      expect(fromHome.hashCode, fromTab.hashCode);
    });

    test('an expense query is keyed by its category, so two filters are two caches', () {
      const all = ExpenseQuery(hostelId: _hostelId);
      const groceries = ExpenseQuery(hostelId: _hostelId, category: ExpenseCategory.groceries);
      expect(all == groceries, isFalse);
      expect(all, const ExpenseQuery(hostelId: _hostelId));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the shell is wired up', () {
    testWidgets('a manager gets their own shell, not the "not built yet" placeholder',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(_session),
            // Null hostel keeps every screen on its empty state, so this test is about the
            // BRANCH in role_shell.dart and touches no repository.
            currentHostelIdProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(home: RoleShell(role: UserRole.manager)),
        ),
      );
      await tester.pump();

      expect(find.byType(ManagerShell), findsOneWidget);
      // The exact symptom this task existed to remove.
      expect(find.textContaining('not built yet'), findsNothing);
    });

    testWidgets('the four destinations match role_shell.dart, in order', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(_session),
            currentHostelIdProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(home: ManagerShell()),
        ),
      );
      await tester.pump();

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        bar.destinations
            .cast<NavigationDestination>()
            .map((d) => d.label)
            .toList(growable: false),
        const ['Home', 'Expenses', 'Tasks', 'Menu'],
      );
      // A manager is not a small owner: no portfolio, no residents, no rent collection.
      expect(find.text('Students'), findsNothing);
      expect(find.text('Payments'), findsNothing);
      expect(find.text('PGs'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the home screen leads with work and money, and invents neither', () {
    testWidgets('the job count is the SERVER count, and the caption says how many are late',
        (tester) async {
      await _pumpHome(tester, load: const TaskLoad(open: 4, overdue: 2));

      expect(find.text('4'), findsOneWidget);
      expect(find.text('2 past their date'), findsOneWidget);
    });

    testWidgets('a clear list says so rather than showing a red count', (tester) async {
      await _pumpHome(tester, load: const TaskLoad(open: 0, overdue: 0), tasks: const []);

      expect(find.text('0'), findsOneWidget);
      expect(find.text('None late'), findsOneWidget);
      expect(find.text('Nothing waiting on you'), findsWidgets);
    });

    testWidgets('the month figures are the sum of the days the RPC returned', (tester) async {
      // 5 x 1000 in and 5 x 400 out, plus a tail of July that must NOT be counted.
      await _pumpHome(tester);

      expect(find.text('₹5,000'), findsOneWidget); // recorded in
      expect(find.text('₹2,000'), findsOneWidget); // spent
      expect(find.text('₹3,000'), findsOneWidget); // difference
      expect(find.text('₹400'), findsOneWidget); // spent today
    });

    testWidgets('the difference is never called profit, and rent is named as missing',
        (tester) async {
      await _pumpHome(tester);

      expect(find.textContaining('Profit'), findsNothing);
      expect(find.textContaining('profit'), findsNothing);
      // public.fee_payments is unreadable to this role. Saying so is the difference between a
      // gap and a wrong number.
      expect(find.textContaining('Rent is collected separately'), findsOneWidget);
    });

    testWidgets('nothing on the screen claims a figure this role cannot read', (tester) async {
      await _pumpHome(tester);

      // Every one of these would come back as 0 from rpc_hostel_stats under a manager's RLS.
      expect(find.textContaining('Occupancy'), findsNothing);
      expect(find.textContaining('residents'), findsNothing);
      expect(find.textContaining('Complaints'), findsNothing);
      expect(find.textContaining('Collected'), findsNothing);
    });

    testWidgets('an expired subscription is announced before a save is refused',
        (tester) async {
      await _pumpHome(tester, hostelStatus: HostelStatus.readonly);

      expect(find.text('This hostel is read-only'), findsOneWidget);
      expect(find.textContaining('subscription has lapsed'), findsOneWidget);
    });

    testWidgets('an active hostel says nothing about subscriptions at all', (tester) async {
      await _pumpHome(tester);
      expect(find.text('This hostel is read-only'), findsNothing);
    });

    testWidgets('the jobs nearest their deadline are the ones shown', (tester) async {
      await _pumpHome(tester);

      expect(find.text('Buy vegetables for the week'), findsOneWidget);
      expect(find.text('2 days late'), findsWidgets);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the expense screen offers exactly the categories the schema has', () {
    testWidgets('six categories, no more and no fewer', (tester) async {
      await _pumpExpenses(tester);

      // public.expense_category is exactly these six. A seventh would be unstorable; a hidden
      // one would make real money invisible.
      for (final label in const [
        'Groceries', 'Staff', 'Electricity', 'Water', 'Maintenance', 'Other',
      ]) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
      }
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(7));

      // Categories from the COMPLAINT enum, which is a different type on a different table.
      expect(find.widgetWithText(ChoiceChip, 'Wi-Fi'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Rent'), findsNothing);
    });

    testWidgets('a row shows its exact amount, its day and its note', (tester) async {
      await _pumpExpenses(tester);

      expect(find.text('-₹2,450.50'), findsOneWidget);
      expect(find.textContaining('Vegetables from the Tuesday market'), findsOneWidget);
    });

    testWidgets('an empty book invites the first entry instead of showing a blank page',
        (tester) async {
      await _pumpExpenses(tester, expenses: const []);
      expect(find.text('Nothing booked yet'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the menu screen never claims a meal that was never written', () {
    testWidgets('all four meals appear, and the unplanned one says so', (tester) async {
      await _pumpMenu(tester);

      expect(find.text('BREAKFAST'), findsOneWidget);
      expect(find.text('LUNCH'), findsOneWidget);
      expect(find.text('SNACKS'), findsOneWidget);
      expect(find.text('DINNER'), findsOneWidget);

      expect(find.text('Idli, sambar, coconut chutney'), findsOneWidget);
      // No row for dinner on the selected day.
      expect(find.text('Not planned yet'), findsWidgets);
      expect(find.textContaining('No dinner'), findsNothing);
    });

    testWidgets('the day strip shows how much of each day is planned', (tester) async {
      await _pumpMenu(tester);

      // Wednesday has breakfast and lunch written; the rest of the week has nothing.
      expect(find.text('2/4'), findsOneWidget);
      expect(find.text('0/4'), findsNWidgets(6));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the tasks screen shows the workflow and who owns it', () {
    testWidgets('a late job is flagged; an on-time one is not', (tester) async {
      await _pumpTasks(tester);

      expect(find.text('Buy vegetables for the week'), findsOneWidget);
      expect(find.text('2 days late'), findsOneWidget);
      expect(find.text('Due tomorrow'), findsOneWidget);
      expect(find.text('Pending'), findsWidgets);
    });

    testWidgets('the header count comes from the server, not from the loaded page',
        (tester) async {
      // Two rows on screen, nine open on the server. Counting the rows would say "2".
      await _pumpTasks(tester, load: const TaskLoad(open: 9, overdue: 3));
      expect(find.text('9 jobs open · 3 late'), findsOneWidget);
    });

    testWidgets('an empty to-do list is good news and is worded as such', (tester) async {
      await _pumpTasks(tester, tasks: const []);
      expect(find.text('Nothing waiting on you'), findsOneWidget);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIXTURES
// ─────────────────────────────────────────────────────────────────────────────

const _session = NivoraSession(
  userId: _managerId,
  role: UserRole.manager,
  fullName: 'Rahul Mehta',
  status: 'active',
  mustChangePassword: false,
  hostelId: _hostelId,
);

Hostel _hostel(HostelStatus status) => Hostel(
      id: _hostelId,
      name: 'Sunrise Residency',
      ownerUserId: _ownerId,
      totalFloors: 3,
      totalRooms: 12,
      bedsPerRoomDefault: 3,
      status: status,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Five days of August at 1000 in / 400 out, behind nine days of July that belong to the trend
/// window only. The month totals must be 5000 and 2000.
FinanceWindow _window() => FinanceWindow(
      days: [
        for (var d = 23; d <= 31; d++)
          FinanceDay(day: DateTime(2026, 7, d), revenue: 7777, expense: 8888),
        for (var d = 1; d <= 5; d++)
          FinanceDay(day: DateTime(2026, 8, d), revenue: 1000, expense: 400),
      ],
      monthStart: DateTime(2026, 8),
      trendStart: DateTime(2026, 7, 23),
      today: DateTime(2026, 8, 5),
    );

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// Two jobs, pinned RELATIVE to the clock so "2 days late" and "Due tomorrow" stay true in
/// September. Task.isOverdue and dueLabel both compare against DateTime.now().
List<Task> _tasks() {
  final today = _midnight(DateTime.now());
  return [
    Task(
      id: 't1',
      hostelId: _hostelId,
      assignedTo: _managerId,
      title: 'Buy vegetables for the week',
      description: 'Enough for Monday through Thursday.',
      dueDate: today.subtract(const Duration(days: 2)),
      status: TaskStatus.pending,
      createdBy: _ownerId,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    ),
    Task(
      id: 't2',
      hostelId: _hostelId,
      assignedTo: _managerId,
      title: 'Get the water tank cleaned',
      dueDate: today.add(const Duration(days: 1)),
      status: TaskStatus.pending,
      createdBy: _ownerId,
      createdAt: DateTime.utc(2026, 8, 2),
      updatedAt: DateTime.utc(2026, 8, 2),
    ),
  ];
}

List<Expense> _expenses() => [
      Expense(
        id: 'e1',
        hostelId: _hostelId,
        date: DateTime(2026, 8, 24),
        category: ExpenseCategory.groceries,
        amount: 2450.50,
        note: 'Vegetables from the Tuesday market',
        createdAt: DateTime.utc(2026, 8, 24),
        updatedAt: DateTime.utc(2026, 8, 24),
      ),
      Expense(
        id: 'e2',
        hostelId: _hostelId,
        date: DateTime(2026, 8, 22),
        category: ExpenseCategory.electricity,
        amount: 8600,
        createdAt: DateTime.utc(2026, 8, 22),
        updatedAt: DateTime.utc(2026, 8, 22),
      ),
    ];

WeeklyMenu _menu() => WeeklyMenu([
      MenuEntry(
        id: 'm1',
        hostelId: _hostelId,
        day: MenuDay.wed,
        meal: Meal.breakfast,
        items: 'Idli, sambar, coconut chutney',
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 20),
      ),
      MenuEntry(
        id: 'm2',
        hostelId: _hostelId,
        day: MenuDay.wed,
        meal: Meal.lunch,
        items: 'Rice, dal, beans poriyal',
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 20),
      ),
    ]);

PagedResult<T> _one<T>(List<T> items) =>
    PagedResult<T>(items: items, page: 0, pageSize: 20, hasMore: false);

/// A paginated family provider answers from a list instead of Postgres.
class _FakeTasks extends TasksNotifier {
  _FakeTasks(super.query, this.items);
  final List<Task> items;

  @override
  Future<PagedResult<Task>> fetchPage(int page) async => _one(items);
}

class _FakeExpenses extends ManagerExpensesNotifier {
  _FakeExpenses(super.query, this.items);
  final List<Expense> items;

  @override
  Future<PagedResult<Expense>> fetchPage(int page) async => _one(items);
}

/// Pins the menu screen to one day, so the test is not a different test on Sunday.
class _PinnedDay extends MenuDayState {
  _PinnedDay(this.day);
  final MenuDay day;

  @override
  MenuDay build() => day;
}

/// THE TRIPWIRE. rpc_hostel_stats is SECURITY INVOKER, and under a manager's RLS its resident,
/// complaint and fee columns all come back as 0 — not as "unavailable". Any manager screen
/// that reads it is printing fabricated numbers, so every pump below fails the test if it does.
bool _statsWereRead = false;

/// Overrides shared by every screen test here.
///
/// A top-level `final` rather than a function, because Riverpod 3 does not export the
/// `Override` type — the element type can be inferred from a literal but cannot be written
/// down as a return type.
final _baseOverrides = [
  sessionProvider.overrideWithValue(_session),
  currentHostelIdProvider.overrideWithValue(_hostelId),
  hostelStatsProvider.overrideWith((ref, query) {
    _statsWereRead = true;
    return null;
  }),
];

/// A tall viewport, because these are lazily-built lists: on a 600dp test window the sections
/// below the fold are never built, and "the trend is not on screen" would look identical to
/// "the trend was never rendered".
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpHome(
  WidgetTester tester, {
  TaskLoad load = const TaskLoad(open: 4, overdue: 2),
  List<Task>? tasks,
  HostelStatus hostelStatus = HostelStatus.active,
}) async {
  _tallView(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._baseOverrides,
        hostelProvider.overrideWith((ref, id) => _hostel(hostelStatus)),
        taskLoadProvider.overrideWith((ref, id) => load),
        managerFinanceProvider.overrideWith((ref, id) => _window()),
        // A family override replaces every instance at once and is handed no argument, so the
        // fake carries a stand-in key. Nothing reads it — fetchPage is overridden.
        tasksProvider.overrideWith2(
          (_) => _FakeTasks(const TaskQuery(hostelId: _hostelId), tasks ?? _tasks()),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: ManagerHomeScreen())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(_statsWereRead, isFalse,
      reason: 'A manager screen asked rpc_hostel_stats for figures RLS zeroes out for '
          'this role. See the note at the top of manager_providers.dart.');
}

Future<void> _pumpExpenses(WidgetTester tester, {List<Expense>? expenses}) async {
  _tallView(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._baseOverrides,
        managerExpensesProvider.overrideWith2(
          (_) => _FakeExpenses(
            const ExpenseQuery(hostelId: _hostelId),
            expenses ?? _expenses(),
          ),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: ManagerExpensesScreen())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(_statsWereRead, isFalse);
}

Future<void> _pumpMenu(WidgetTester tester) async {
  _tallView(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._baseOverrides,
        menuDayProvider.overrideWith(() => _PinnedDay(MenuDay.wed)),
        weeklyMenuProvider.overrideWith((ref, id) => _menu()),
      ],
      child: const MaterialApp(home: Scaffold(body: ManagerMenuScreen())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(_statsWereRead, isFalse);
}

Future<void> _pumpTasks(
  WidgetTester tester, {
  TaskLoad load = const TaskLoad(open: 2, overdue: 1),
  List<Task>? tasks,
}) async {
  _tallView(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._baseOverrides,
        taskLoadProvider.overrideWith((ref, id) => load),
        tasksProvider.overrideWith2(
          (_) => _FakeTasks(const TaskQuery(hostelId: _hostelId), tasks ?? _tasks()),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: ManagerTasksScreen())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(_statsWereRead, isFalse);
}
