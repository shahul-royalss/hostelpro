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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/manager/data/manager_models.dart';
import 'package:mobile/features/manager/data/manager_providers.dart';
import 'package:mobile/features/manager/expenses/manager_expenses_screen.dart';
import 'package:mobile/features/manager/home/manager_home_screen.dart';
import 'package:mobile/features/manager/manager_shell.dart';
import 'package:mobile/features/manager/menu/manager_menu_screen.dart';
import 'package:mobile/features/manager/tasks/manager_tasks_screen.dart';
import 'package:mobile/features/manager/tasks/task_sheet.dart';
import 'package:mobile/features/manager/widgets/manager_ui.dart';
import 'package:mobile/features/shell/role_shell.dart';
import 'package:mobile/shared/glass/glass.dart';

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
      // Scoped to the category strip, which is the screen's one horizontal scroller. The
      // out/in switch beside it is now the same ToggleChip the Figma frames use for a
      // selected tab (4:1265) rather than a Material SegmentedButton, so an unscoped count of
      // this widget type would be counting two different controls.
      expect(
        find.descendant(
            of: find.byType(SingleChildScrollView), matching: find.byType(ChoiceChip)),
        findsNWidgets(7),
      );

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

  // ───────────────────────────────────────────────────────────────────────────
  //
  // THE DEFECT CLASS THESE EXIST FOR. `provider.value` is null while a read is in flight, null
  // when it failed and null when RLS refused it. Every screen in this role branched on that
  // null, so three different facts drew one picture: a dash, or a blank, or no badge — each of
  // which a person reads as "nothing to report". The analyzer cannot see any of it, and a test
  // that stubs the provider with data cannot either. So these stub it with a FAILURE and with a
  // read that never answers, and check that the two look different from each other and from a
  // genuine zero.
  //
  // The rule: loading, empty, failed and refused are four states and must look different.
  group('loading, empty, failed and refused do not share a face', () {
    // OfflineFailure is retryable; AccessDeniedFailure is not. AppFailure already draws that
    // line, and the screens are supposed to honour it rather than always offering a button.
    const offline = OfflineFailure('Cannot reach Nivora. Check your connection and try again.');
    const refused = AccessDeniedFailure('You do not have access to that.');

    // ── the read-only banner: the safety message ────────────────────────────
    testWidgets('a hostel-status read that FAILED says so instead of drawing nothing',
        (tester) async {
      await _pumpHome(tester, hostelError: offline);

      // Before: null hostel, no banner, an ordinary-looking screen on a hostel that may be
      // suspended — and the manager finds out when a save is refused.
      expect(find.text('Could not check whether this hostel is read-only'), findsOneWidget);
      expect(find.textContaining('Cannot reach Nivora'), findsWidgets);
      // Retryable, so the retry is drawn — and it is wired to hostelProvider, which
      // pull-to-refresh could not reach before this change.
      expect(find.widgetWithText(OutlinedButton, 'Try again'), findsOneWidget);
    });

    testWidgets('a REFUSED hostel read says so and offers no retry it cannot honour',
        (tester) async {
      await _pumpHome(tester, hostelError: refused);

      expect(find.text('Could not check whether this hostel is read-only'), findsOneWidget);
      expect(find.textContaining('You do not have access'), findsWidgets);
      // A button that will be refused again teaches people the buttons do nothing.
      expect(find.widgetWithText(OutlinedButton, 'Try again'), findsNothing);
    });

    testWidgets('a hostel row that came back EMPTY is not the same as one that failed',
        (tester) async {
      await _pumpHome(tester, hostelMissing: true);

      expect(find.text('This hostel is not visible to your account'), findsOneWidget);
      // Not the failure wording, and not the read-only warning either.
      expect(find.text('Could not check whether this hostel is read-only'), findsNothing);
      expect(find.text('This hostel is read-only'), findsNothing);
    });

    testWidgets('while the status is still being checked the screen says that, not nothing',
        (tester) async {
      await _pumpHome(tester, hostelPending: true);

      expect(find.text('Checking this hostel'), findsOneWidget);
      expect(find.text('Could not check whether this hostel is read-only'), findsNothing);
      expect(find.text('This hostel is read-only'), findsNothing);
    });

    testWidgets('an active hostel is the ONLY thing that earns a blank strip', (tester) async {
      await _pumpHome(tester);
      expect(find.byType(NoticeStrip), findsNothing);
    });

    testWidgets('a lapsed subscription still reads exactly as it did', (tester) async {
      await _pumpHome(tester, hostelStatus: HostelStatus.readonly);

      expect(find.text('This hostel is read-only'), findsOneWidget);
      expect(find.textContaining('subscription has lapsed'), findsOneWidget);
      expect(find.byType(NoticeStrip), findsOneWidget);
    });

    // ── the two figures on the home screen ──────────────────────────────────
    testWidgets('a job count that FAILED is not drawn as a dash', (tester) async {
      await _pumpHome(tester, loadError: offline);

      // The old tile printed '—' and captioned it 'Counting' forever.
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(find.text('Counting'), findsNothing);
      // And it must not have quietly claimed the good news either.
      expect(find.text('None late'), findsNothing);
    });

    testWidgets('a job count still COUNTING shows a dash and claims nothing', (tester) async {
      await _pumpHome(tester, loadPending: true);

      expect(find.text('—'), findsOneWidget);
      expect(find.text('Counting'), findsOneWidget);
      // The bug in the old tone expression: while counting, `overdue > 0` was false, so the
      // tile said "None late" in success green on the strength of no data at all.
      expect(find.text('None late'), findsNothing);
      expect(find.text('Not available'), findsNothing);
    });

    testWidgets("a failed finance read does not print a dash for today's spend",
        (tester) async {
      await _pumpHome(tester, financeError: offline);

      expect(find.text('—'), findsNothing);
      expect(find.text('₹400'), findsNothing);
      expect(find.text('Not available'), findsOneWidget);
      // The month block underneath is an AsyncSection and already failed loudly; the point
      // here is that the tile above it stopped disagreeing with it.
      expect(find.textContaining('Cannot reach Nivora'), findsWidgets);
    });

    testWidgets('a day the server genuinely had nothing for is its own fourth state',
        (tester) async {
      // The read SUCCEEDED and still has no row for today. That is not loading, not a
      // failure, and — because rpc_daily_finance zero-fills — not a spend of zero either.
      await _pumpHome(
        tester,
        window: FinanceWindow(
          days: [FinanceDay(day: DateTime(2026, 8, 4), revenue: 1000, expense: 400)],
          monthStart: DateTime(2026, 8),
          trendStart: DateTime(2026, 7, 23),
          today: DateTime(2026, 8, 5),
        ),
      );

      expect(find.text('No figure for today'), findsOneWidget);
      expect(find.text('Not available'), findsNothing);
      expect(find.text('Booked against today'), findsNothing);
    });

    testWidgets('a real zero is still printed as a figure, never as a dash', (tester) async {
      await _pumpHome(
        tester,
        window: FinanceWindow(
          days: [FinanceDay(day: DateTime(2026, 8, 5), revenue: 0, expense: 0)],
          monthStart: DateTime(2026, 8),
          trendStart: DateTime(2026, 7, 23),
          today: DateTime(2026, 8, 5),
        ),
      );

      expect(find.text('₹0'), findsWidgets);
      expect(find.text('No figure for today'), findsNothing);
    });

    // ── the tasks header ────────────────────────────────────────────────────
    testWidgets('a failed count in the Tasks header is not silence', (tester) async {
      await _pumpTasks(tester, loadError: offline);

      expect(find.textContaining('Job count unavailable'), findsOneWidget);
      expect(find.text('Nothing open'), findsNothing);
    });

    testWidgets('a count still in flight leaves the header blank, not wrong', (tester) async {
      await _pumpTasks(tester, loadPending: true);

      expect(find.textContaining('Job count unavailable'), findsNothing);
      expect(find.text('Nothing open'), findsNothing);
      expect(find.textContaining('jobs open'), findsNothing);
    });

    testWidgets('a genuine zero says "Nothing open" and nothing else', (tester) async {
      await _pumpTasks(tester, load: const TaskLoad(open: 0, overdue: 0), tasks: const []);

      expect(find.text('Nothing open'), findsOneWidget);
      expect(find.textContaining('Job count unavailable'), findsNothing);
    });

    // ── the Tasks tab badge ─────────────────────────────────────────────────
    testWidgets('an overdue count that FAILED is not pixel-identical to zero', (tester) async {
      await _pumpShell(tester, loadError: offline);

      expect(find.descendant(of: find.byType(Badge), matching: find.text('!')), findsOneWidget);
    });

    testWidgets('a real zero draws no badge at all', (tester) async {
      await _pumpShell(tester, load: const TaskLoad(open: 3, overdue: 0));

      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('a real count still draws the number', (tester) async {
      await _pumpShell(tester, load: const TaskLoad(open: 9, overdue: 3));

      expect(find.descendant(of: find.byType(Badge), matching: find.text('3')), findsOneWidget);
      expect(find.descendant(of: find.byType(Badge), matching: find.text('!')), findsNothing);
    });

    testWidgets('a count still in flight draws no badge and no mark', (tester) async {
      await _pumpShell(tester, loadPending: true);

      expect(find.byType(Badge), findsNothing);
    });

    // ── names on the task sheet ─────────────────────────────────────────────
    testWidgets('a colleague RLS no longer returns still reads as before', (tester) async {
      // The lookup SUCCEEDED and has no row for this user — deactivated, or no longer
      // readable. That is the case the plain fallback was written for, and it keeps it.
      await _openTaskSheet(tester, names: const {});

      expect(find.text('The owner'), findsOneWidget);
      expect(find.text('Name unavailable'), findsNothing);
    });

    testWidgets('a name lookup that FAILED does not name somebody anyway', (tester) async {
      await _openTaskSheet(tester, namesError: offline);

      expect(find.text('Name unavailable'), findsWidgets);
      // "Raised by: The owner" on the strength of a failed read is a claim about a person
      // made from no data at all.
      expect(find.text('The owner'), findsNothing);
    });

    testWidgets('a name still being looked up says so', (tester) async {
      await _openTaskSheet(tester, namesPending: true);

      expect(find.text('Looking up the name…'), findsWidgets);
      expect(find.text('The owner'), findsNothing);
      expect(find.text('Name unavailable'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //
  // THE RESTYLE ITSELF. These pin the decisions that separate Figma `4:1159` /
  // `4:1236` from the Stitch mockup the screens were built against before it. They are
  // structural rather than pixel assertions: which widget draws a group, how many panes are
  // on a page, which fill a selected tab takes. A pixel test would fail on a font metric.
  group('the manager screens are the Figma frames, not the Stitch card stack', () {
    testWidgets('a group is announced by an uppercase eyebrow, not wrapped in a titled card',
        (tester) async {
      await _pumpHome(tester);

      // 4:1196 and 4:1214: `text-[#6f747a] text-[11px] uppercase`, no box under it. The string
      // is uppercased by SectionLabel, because a TextStyle cannot.
      expect(find.text("TODAY'S TASKS"), findsOneWidget);
      expect(find.text('MONEY IN AND OUT'), findsOneWidget);
      expect(find.text('DO IT NOW'), findsOneWidget);

      // The Stitch headings these replaced — sentence case, inside a card, behind a glyph.
      expect(find.text('Task board'), findsNothing);
      expect(find.text('Money this month'), findsNothing);
    });

    testWidgets('the dashboard has exactly one pane on it, and it is the header',
        (tester) async {
      await _pumpHome(tester);

      // Every frame in the file is flat: an opaque fill and a 1px hairline, no shadow and no
      // second rung of elevation. The old screen put its jobs figure on a raised pane as "the
      // one hero per screen"; 4:1159 has no hero and nothing lifted off the ground.
      expect(find.byType(GlassSurface), findsOneWidget);
      expect(
        find.descendant(of: find.byType(GlassHeader), matching: find.byType(GlassSurface)),
        findsOneWidget,
      );
    });

    testWidgets('the KPI grid is four equal tiles — 4:1177', (tester) async {
      await _pumpHome(tester);
      expect(find.byType(StatCard), findsNWidgets(4));
    });

    testWidgets('three tiles fed by one read report one failure, not three', (tester) async {
      // Spent today, spent this month and recorded in all come out of managerFinanceProvider.
      // That is one request with one outcome, so a failure collapses them to a single card
      // beside the job tile — which still keeps its own face, because it is a different read.
      await _pumpHome(
        tester,
        financeError: const OfflineFailure('Cannot reach Nivora.'),
      );

      expect(find.byType(FailedStat), findsOneWidget);
      expect(find.byType(StatCard), findsOneWidget, reason: 'the job tile is unaffected');
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('the selected day tab is the gold fill; the rest are the raised surface',
        (tester) async {
      // 4:1265 is `bg-[#c9a96e]` with `text-[#0b0d0f]`; 4:1262 is `bg-[#171a1e]` under a
      // hairline. The scheme is read from the tree rather than named, because these widget
      // tests deliberately run on the stock theme — see the note at the top of this file.
      await _pumpMenu(tester);
      final scheme = Theme.of(tester.element(find.text('WED'))).colorScheme;

      Color fillUnder(String day) => tester
          .widgetList<Material>(
              find.ancestor(of: find.text(day), matching: find.byType(Material)))
          .first
          .color!;

      expect(fillUnder('WED'), scheme.primary, reason: 'Wednesday is the pinned day');
      expect(fillUnder('MON'), scheme.surfaceContainer);
    });

    testWidgets('a planned meal takes the gold heading, an unplanned one the muted ink',
        (tester) async {
      // 4:1283 sets every meal name in the accent — but every meal on that frame is planned.
      // The unplanned case is the one the frame does not draw, and it has to stay visibly
      // different, because "how much of today is written" is the whole question this screen
      // answers.
      await _pumpMenu(tester);
      final scheme = Theme.of(tester.element(find.text('BREAKFAST'))).colorScheme;

      expect(tester.widget<Text>(find.text('BREAKFAST')).style?.color, scheme.primary);
      expect(tester.widget<Text>(find.text('DINNER')).style?.color, isNot(scheme.primary));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //
  // THE SMALLEST PHONE THIS APP SUPPORTS, WITH THE LARGEST TYPE ANDROID HANDS OUT.
  //
  // Every one of these caught a real overflow while the Figma restyle was being written, and
  // none of them was visible at 1.0x on a 390dp test window: a two-tile row, a legend, a
  // status-and-due meta line and a lakh-sized ledger figure each fit at ordinary size and each
  // ran off the right edge at 1.6x on a 320dp phone. A layout error is a black-and-yellow
  // barber pole across a manager's screen in the field, and the analyzer cannot see one.
  //
  // The figures are deliberately the widest the columns allow — seven-figure rupees, a
  // three-figure job count, a task title that fills two lines.
  group('every manager screen survives 320dp at the largest text scale', () {
    Future<void> pumpNarrow(WidgetTester tester, Widget screen,
        {Object? finance}) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _narrowOverrides(finance: finance).cast(),
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Scaffold(body: screen),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }

    testWidgets('home', (tester) async => pumpNarrow(tester, const ManagerHomeScreen()));

    testWidgets('home with the money read still in flight', (tester) async {
      // The KPI grid collapses its three money tiles to one card here, so this is a different
      // layout from the loaded one and gets its own probe.
      await pumpNarrow(
        tester,
        const ManagerHomeScreen(),
        finance: managerFinanceProvider.overrideWith((ref, id) => _pending<FinanceWindow>()),
      );
    });

    testWidgets('home with the money read failed', (tester) async {
      await pumpNarrow(
        tester,
        const ManagerHomeScreen(),
        finance: managerFinanceProvider.overrideWith((ref, id) =>
            Future<FinanceWindow>.error(
                const OfflineFailure('Cannot reach Nivora. Check your connection.'))),
      );
    });

    testWidgets('expenses', (tester) async =>
        pumpNarrow(tester, const ManagerExpensesScreen()));

    testWidgets('tasks', (tester) async => pumpNarrow(tester, const ManagerTasksScreen()));

    testWidgets('menu', (tester) async => pumpNarrow(tester, const ManagerMenuScreen()));
  });

  // ───────────────────────────────────────────────────────────────────────────
  //
  // tokens.dart is the single source for colour, spacing, radius, icon size and duration.
  // These are the values manager_ui.dart had inlined where warden_ui.dart — the copy that was
  // already correct — reads the token.
  group('manager_ui paints through tokens, not through literals', () {
    testWidgets('a status pill takes the control radius, not a hardcoded 999', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Pill(status: TaskStatus.pending))),
      );

      final box = tester
          .widget<Container>(
              find.descendant(of: find.byType(Pill), matching: find.byType(Container)))
          .decoration! as BoxDecoration;
      // tokens.dart reserves Radii.pill for shapes that can never take a second line. A status
      // pill takes control — which is also what warden_ui's StatusPill uses.
      expect(box.borderRadius, Radii.rControl);
    });

    testWidgets('an empty section and a failed one both draw the shared state card, not two '
        'inventions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(children: [
              EmptyNote(icon: Icons.check_circle_outline_rounded, title: 'Nothing here'),
              FailureNote(error: OfflineFailure('offline')),
            ]),
          ),
        ),
      );

      // Figma 4:1562, `screen-empty-error-skeleton`, draws empty and error as the SAME raised
      // card with the same hairline, differing only in the caps tag and the body. Both of this
      // role's notes are now that shared card — 36 and 32 used to be two people guessing at an
      // icon size in two separate hand-rolled columns.
      expect(find.byType(StateCard), findsNWidgets(2));

      // The tag is a real word, not the spec frame's own "ERROR STATE" label for a designer.
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('EMPTY STATE'), findsNothing);

      // ONE glyph on the pair, and it belongs to the empty state: 4:1588 gives the error card
      // no icon at all, because its sentence is the message. A red pictogram over a section
      // that merely did not load reads as "the app is broken".
      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      expect(icons.length, 1);
      // It sits inside the design's 1.5px outlined square (4:1579), so it is a step down from
      // the old bare 32dp glyph rather than the same number in a new place.
      expect(icons.single.size, IconSize.xl - Space.xs);

      // Offline is retryable, but nothing was wired to retry it — so no button is offered. A
      // control that cannot help is worse than no control.
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
    });

    testWidgets('a quick action and a detail row use the token icon sizes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(children: [
              QuickAction(icon: Icons.add, label: 'Add', onTap: () {}),
              const DetailRow(label: 'Raised by', value: 'Priya', icon: Icons.person_outline),
            ]),
          ),
        ),
      );

      expect(
        tester.widget<Icon>(find.descendant(
                of: find.byType(QuickAction), matching: find.byType(Icon)))
            .size,
        IconSize.md,
      );
      expect(
        tester.widget<Icon>(
            find.descendant(of: find.byType(DetailRow), matching: find.byType(Icon))).size,
        IconSize.sm,
      );
    });

    test('a failure snackbar is given the reading budget the token names', () {
      // runAction used a bare Duration(seconds: 5) where Motion.readMessage is defined for
      // exactly this. The token is the assertion: if it moves, the snackbar moves with it.
      expect(Motion.readMessage, const Duration(seconds: 5));
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

class _FakeRevenues extends ManagerRevenuesNotifier {
  _FakeRevenues(super.hostelId, this.items);
  final List<Revenue> items;

  @override
  Future<PagedResult<Revenue>> fetchPage(int page) async => _one(items);
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

/// A read that never answers. The point of the class: "still loading" has to be reachable in a
/// test, or the state that is supposed to look different from a failure cannot be checked.
Future<T> _pending<T>() => Completer<T>().future;

/// The widest content every column can legally hold, for the 320dp / 1.6x probes.
///
/// Seven-figure rupees (a real hostel books in lakhs), a job count in three digits, and a task
/// title long enough to wrap. Nothing here is drawn by any other test — these fixtures exist to
/// make the columns as wide as the database allows them to be.
FinanceWindow _wideWindow() => FinanceWindow(
      days: [
        for (var d = 1; d <= 5; d++)
          FinanceDay(day: DateTime(2026, 8, d), revenue: 1234567, expense: 987654),
      ],
      monthStart: DateTime(2026, 8),
      trendStart: DateTime(2026, 7, 23),
      today: DateTime(2026, 8, 5),
    );

List<Task> _wideTasks() {
  final today = _midnight(DateTime.now());
  return [
    Task(
      id: 'w1',
      hostelId: _hostelId,
      assignedTo: _managerId,
      title: 'Approve the kitchen vegetable purchase list for the whole of next week',
      dueDate: today.subtract(const Duration(days: 12)),
      status: TaskStatus.inProgress,
      createdBy: _ownerId,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    ),
    Task(
      id: 'w2',
      hostelId: _hostelId,
      assignedTo: _managerId,
      title: 'Review shift roster for mess staff',
      dueDate: today,
      status: TaskStatus.done,
      createdBy: _ownerId,
      createdAt: DateTime.utc(2026, 8, 2),
      updatedAt: DateTime.utc(2026, 8, 2),
    ),
  ];
}

List<Expense> _wideExpenses() => [
      Expense(
        id: 'w-e1',
        hostelId: _hostelId,
        date: DateTime(2026, 8, 24),
        category: ExpenseCategory.maintenance,
        amount: 1234567.89,
        note: 'Annual servicing of both lifts, the borewell pump and the kitchen chimney',
        createdAt: DateTime.utc(2026, 8, 24),
        updatedAt: DateTime.utc(2026, 8, 24),
      ),
    ];

/// Every read a manager screen makes, stubbed. [finance] replaces the finance override rather
/// than being appended to it — Riverpod asserts when one family is overridden twice in a
/// container, so the stalled and failed variants have to swap it out, not stack on top.
List<Object> _narrowOverrides({Object? finance}) => [
      ..._baseOverrides,
      hostelProvider.overrideWith((ref, id) => _hostel(HostelStatus.active)),
      taskLoadProvider.overrideWith((ref, id) => const TaskLoad(open: 128, overdue: 41)),
      finance ?? managerFinanceProvider.overrideWith((ref, id) => _wideWindow()),
      tasksProvider.overrideWith2(
        (_) => _FakeTasks(const TaskQuery(hostelId: _hostelId), _wideTasks()),
      ),
      managerExpensesProvider.overrideWith2(
        (_) => _FakeExpenses(const ExpenseQuery(hostelId: _hostelId), _wideExpenses()),
      ),
      managerRevenuesProvider.overrideWith2((_) => _FakeRevenues(_hostelId, const [])),
      menuDayProvider.overrideWith(() => _PinnedDay(MenuDay.wed)),
      weeklyMenuProvider.overrideWith((ref, id) => _menu()),
    ];

/// The task sheet, opened the way a manager opens it. The name map is the read under test.
Future<void> _openTaskSheet(
  WidgetTester tester, {
  Map<String, String>? names,
  Object? namesError,
  bool namesPending = false,
}) async {
  _tallView(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._baseOverrides,
        staffNamesProvider.overrideWith((ref, id) {
          if (namesPending) return _pending<Map<String, String>>();
          if (namesError != null) return Future<Map<String, String>>.error(namesError);
          return names ?? const <String, String>{};
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              // t1 is assigned to the signed-in manager and raised by the owner, so
              // "Assigned to" says "You" and "Raised by" exercises the name map.
              onPressed: () => showTaskSheet(context, task: _tasks().first),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The whole shell, because the Tasks badge is the one thing on it that reports a number and
/// the IndexedStack keeps every tab alive. Every read the four tabs make is stubbed, so this
/// stays a test about the badge.
Future<void> _pumpShell(
  WidgetTester tester, {
  TaskLoad load = const TaskLoad(open: 4, overdue: 2),
  Object? loadError,
  bool loadPending = false,
}) async {
  _tallView(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._baseOverrides,
        hostelProvider.overrideWith((ref, id) => _hostel(HostelStatus.active)),
        taskLoadProvider.overrideWith((ref, id) {
          if (loadPending) return _pending<TaskLoad>();
          if (loadError != null) return Future<TaskLoad>.error(loadError);
          return load;
        }),
        managerFinanceProvider.overrideWith((ref, id) => _window()),
        tasksProvider.overrideWith2(
          (_) => _FakeTasks(const TaskQuery(hostelId: _hostelId), _tasks()),
        ),
        managerExpensesProvider.overrideWith2(
          (_) => _FakeExpenses(const ExpenseQuery(hostelId: _hostelId), _expenses()),
        ),
        // The shell's background warm-up reaches the revenues list too, even though no test
        // here ever shows it — unstubbed, the warmer would touch the real repository.
        managerRevenuesProvider.overrideWith2((_) => _FakeRevenues(_hostelId, const [])),
        menuDayProvider.overrideWith(() => _PinnedDay(MenuDay.wed)),
        weeklyMenuProvider.overrideWith((ref, id) => _menu()),
      ],
      child: const MaterialApp(home: ManagerShell()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(_statsWereRead, isFalse);
}

Future<void> _pumpHome(
  WidgetTester tester, {
  TaskLoad load = const TaskLoad(open: 4, overdue: 2),
  List<Task>? tasks,
  HostelStatus hostelStatus = HostelStatus.active,
  FinanceWindow? window,
  // Each of the three reads on this screen can be made to fail, to stall, or (for the hostel)
  // to come back empty — the four outcomes the screen has to tell apart.
  Object? hostelError,
  bool hostelMissing = false,
  bool hostelPending = false,
  Object? loadError,
  bool loadPending = false,
  Object? financeError,
}) async {
  _tallView(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._baseOverrides,
        hostelProvider.overrideWith((ref, id) {
          if (hostelPending) return _pending<Hostel?>();
          if (hostelError != null) return Future<Hostel?>.error(hostelError);
          if (hostelMissing) return null;
          return _hostel(hostelStatus);
        }),
        taskLoadProvider.overrideWith((ref, id) {
          if (loadPending) return _pending<TaskLoad>();
          if (loadError != null) return Future<TaskLoad>.error(loadError);
          return load;
        }),
        managerFinanceProvider.overrideWith((ref, id) {
          if (financeError != null) return Future<FinanceWindow>.error(financeError);
          return window ?? _window();
        }),
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
  Object? loadError,
  bool loadPending = false,
}) async {
  _tallView(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._baseOverrides,
        taskLoadProvider.overrideWith((ref, id) {
          if (loadPending) return _pending<TaskLoad>();
          if (loadError != null) return Future<TaskLoad>.error(loadError);
          return load;
        }),
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
