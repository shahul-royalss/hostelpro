import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/manager/menu/manager_menu_screen.dart';
import 'package:mobile/features/student/menu_screen.dart';
import 'package:mobile/features/student/widgets/common.dart';
import 'package:mobile/features/student/widgets/menu.dart';

/// public.menus, read by the two roles that share it.
///
/// THE ONE CLAIM THESE TESTS EXIST TO STOP. A hostel that has not filled in Sunday has NO ROWS
/// for Sunday, and a screen that draws four blank meal lines under it has told a resident there
/// is no food on Sunday — which the database never said, about the one subject on this screen
/// people plan an evening around. Every test below is a variation on the difference between
/// "nobody has written this" and "there is nothing to eat".
///
/// Nothing here reaches the network: `weeklyMenuProvider` is overridden with a list that stands
/// in for the table, and the last group reads that ONE list from both the manager's screen and
/// the resident's, which is the whole of what makes a manager's edit visible to a resident.

const _hostelId = '8fc3f95c-497a-4204-af5a-510a6c811136';

final _me = Student(
  id: '5922bad8-faa4-42e0-b35f-73fe97b2c99d',
  hostelId: _hostelId,
  userId: 'b3a79141-cc45-4c61-9485-4c8b6f138b4e',
  fullName: 'Rohan Deshmukh',
  phone: '9000000004',
  monthlyFee: 6000,
  status: StudentStatus.active,
  dateOfJoining: DateTime(2026, 3, 7),
  createdAt: DateTime.utc(2026, 3, 7),
  updatedAt: DateTime.utc(2026, 8, 19),
);

/// One row of public.menus, shaped the way the manager's upsert returns it.
MenuEntry _row(MenuDay day, Meal meal, String items) => MenuEntry(
      id: '${day.wire}-${meal.wire}',
      hostelId: _hostelId,
      day: day,
      meal: meal,
      items: items,
      createdAt: DateTime.utc(2026, 8, 30),
      updatedAt: DateTime.utc(2026, 8, 31, 9),
    );

/// Whatever day it is when this suite runs. Deriving the other days by rotation rather than
/// naming Wednesday keeps these from being a different test on Sunday.
final _today = MenuDay.of(DateTime.now());
final _week = weekFrom(_today);

Future<void> _pumpStudentWeek(
  WidgetTester tester, {
  required List<MenuEntry> table,
  AppFailure? failure,
}) async {
  // Tall, because this is a lazily-built ListView: on a phone-sized test window the later days
  // are never built, and "Saturday is not on screen" would look identical to "Saturday was
  // never rendered".
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myStudentProvider.overrideWith((ref) async => _me),
        weeklyMenuProvider.overrideWith((ref, hostelId) async {
          if (failure != null) throw failure;
          return WeeklyMenu(table);
        }),
      ],
      child: const MaterialApp(home: Scaffold(body: StudentMenuScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the week a resident reads', () {
    testWidgets('all seven days render, today first and marked as today', (tester) async {
      await _pumpStudentWeek(tester, table: [
        _row(_today, Meal.breakfast, 'Idli, sambar, coconut chutney'),
        _row(_today, Meal.lunch, 'Rice, dal, beans poriyal, curd'),
        _row(_today, Meal.snacks, 'Tea and biscuits'),
        _row(_today, Meal.dinner, 'Chapati, paneer butter masala'),
        _row(_week[1], Meal.lunch, 'Lemon rice'),
      ]);

      final drawn = tester.widgetList<DayMenuCard>(find.byType(DayMenuCard));
      expect(drawn.length, 7, reason: 'a week is seven days, written or not');
      expect(
        drawn.map((c) => c.day).toList(),
        _week,
        reason: 'today first, then the days still ahead — not mon..sun regardless of the date',
      );

      // Clearly marked, and marked exactly once. StatusPill shouts its label.
      expect(find.text('TODAY'), findsOneWidget);
      expect(drawn.where((c) => c.isToday).length, 1);
      expect(drawn.first.day, _today);

      // Today's four meals, all of them, in the order they are eaten.
      expect(find.text('BREAKFAST'), findsWidgets);
      expect(find.text('Idli, sambar, coconut chutney'), findsOneWidget);
      expect(find.text('Rice, dal, beans poriyal, curd'), findsOneWidget);
      expect(find.text('Tea and biscuits'), findsOneWidget);
      expect(find.text('Chapati, paneer butter masala'), findsOneWidget);
    });

    testWidgets('a day nobody has written says so, instead of four empty meals',
        (tester) async {
      // Today is fully written; tomorrow has two of its four meals; the day after has no rows
      // at all — the state a PG that has not got to the weekend is genuinely in.
      final unwritten = _week[2];
      await _pumpStudentWeek(tester, table: [
        for (final meal in Meal.values) _row(_today, meal, 'Something for ${meal.label}'),
        _row(_week[1], Meal.breakfast, 'Poha'),
        _row(_week[1], Meal.lunch, 'Curd rice'),
      ]);

      // ONE SENTENCE FOR THE WHOLE DAY, and it names the day it is about.
      expect(find.text('No menu set for ${unwritten.label} yet.'), findsOneWidget);

      // The four unwritten days each get that sentence and NOT four "Not planned yet" lines.
      // Only tomorrow's two blank meals may say that — 2, not 2 + 4 x 4.
      expect(find.text('Not planned yet'), findsNWidgets(2));

      // And nothing anywhere states that there is no food.
      expect(find.textContaining('No dinner'), findsNothing);
      expect(find.textContaining('no food'), findsNothing);
    });

    testWidgets('a hostel that has planned nothing is told who fills it in', (tester) async {
      await _pumpStudentWeek(tester, table: const []);

      expect(find.text('No menu put up yet'), findsOneWidget);
      expect(find.textContaining('manager writes the week'), findsOneWidget);
      // Not seven copies of the same sentence, and not an error.
      expect(find.byType(DayMenuCard), findsNothing);
      expect(find.byType(ErrorNote), findsNothing);
    });

    testWidgets('a blank row is not a planned meal', (tester) async {
      // `items` is NOT NULL DEFAULT '', so a manager who clears a meal leaves a row behind. It
      // is not a meal, and it must not be drawn as an empty one.
      await _pumpStudentWeek(tester, table: [
        _row(_today, Meal.breakfast, 'Upma'),
        _row(_today, Meal.dinner, '   '),
      ]);

      expect(find.text('Upma'), findsOneWidget);
      expect(find.text('Not planned yet'), findsNWidgets(3));
      expect(find.text('No menu set for ${_today.label} yet.'), findsNothing);
    });

    testWidgets('a read that failed is a failure, never an empty week', (tester) async {
      await _pumpStudentWeek(
        tester,
        table: const [],
        failure: const OfflineFailure('Cannot reach Nivora.'),
      );

      expect(find.byType(ErrorNote), findsOneWidget);
      // The four states stay four states: this is not the "nothing planned" sentence.
      expect(find.text('No menu put up yet'), findsNothing);
      expect(find.byType(DayMenuCard), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //
  // THE SMALLEST PHONE THIS APP SUPPORTS, WITH THE LARGEST TYPE ANDROID HANDS OUT.
  //
  // `items` is free text a manager types, and a day header carries a title beside a pill. Both
  // are the shapes that ran off the right edge at 1.6x on a 320dp phone elsewhere in this app,
  // and a layout error is a black-and-yellow barber pole across a resident's dinner.
  group('the week survives 320dp at the largest text scale', () {
    testWidgets('a full week, a long dish list and the today pill all fit', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myStudentProvider.overrideWith((ref) async => _me),
            weeklyMenuProvider.overrideWith((ref, hostelId) async => WeeklyMenu([
                  _row(_today, Meal.breakfast,
                      'Idli, medu vada, sambar, coconut chutney, tomato chutney and filter coffee'),
                  _row(_today, Meal.lunch, 'Rice, dal, beans poriyal, rasam, curd, pickle'),
                  _row(_week[1], Meal.dinner, 'Chapati, paneer butter masala, jeera rice'),
                ])),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Scaffold(body: StudentMenuScreen()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('one table, both roles', () {
    testWidgets('what the manager writes is what the resident reads', (tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // public.menus, as the server holds it. Both screens below read THIS list, through the
      // one `weeklyMenuProvider` — which is the point of the test: there is no second query
      // under lib/features/student/ that could return something else.
      final table = <MenuEntry>[];

      final container = ProviderContainer(
        overrides: [
          currentHostelIdProvider.overrideWithValue(_hostelId),
          myStudentProvider.overrideWith((ref) async => _me),
          weeklyMenuProvider.overrideWith((ref, hostelId) async => WeeklyMenu(table)),
        ],
      );
      addTearDown(container.dispose);

      Future<void> show(Widget screen) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: Scaffold(body: screen)),
          ),
        );
        await tester.pumpAndSettle();
      }

      // 1. Before anyone has written anything, the manager's own screen says today is unplanned.
      await show(const ManagerMenuScreen());
      expect(find.text('Not planned yet'), findsNWidgets(Meal.values.length));

      // 2. The manager saves today's breakfast. This is the row the upsert returns — the same
      //    shape MenuEntry.fromJson builds out of MenuEntry.columns — landing in the table.
      table.add(_row(_today, Meal.breakfast, 'Upma, coconut chutney'));
      container.invalidate(weeklyMenuProvider);

      await show(const ManagerMenuScreen());
      expect(find.text('Upma, coconut chutney'), findsOneWidget);

      // 3. The resident opens the app. No new query, no second model, no copy of the string:
      //    the same provider over the same row.
      await show(const StudentMenuScreen());
      expect(find.text('Upma, coconut chutney'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      // The three meals nobody has written still say so on the resident's screen too.
      expect(find.text('Not planned yet'), findsNWidgets(Meal.values.length - 1));
    });
  });
}
