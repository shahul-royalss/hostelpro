// THE PRODUCT OWNER'S COMPLAINT, HELD DOWN AS A TEST for the manager shell: "the system has
// to load fastly when we clicks on any section... it has to come active without lazy load".
// Tapping Expenses, Tasks or Menu must NEVER show a skeleton or a spinner in normal use — the
// data must already be there, warmed in the background after the home screen's own requests
// have won the network, and held warm so a revisit renders instantly while any refresh happens
// BEHIND the shown value.
//
// Every fetch below takes a real (fake-clock) 300ms, so if a tab tap had to fetch on arrival
// the arrival frame COULD NOT show data — the row assertions would fail and the spinner finder
// would fire. Passing therefore proves the tap rendered from warm state, not from a lucky
// instant network. Without this file, the next refactor of ManagerShell quietly reintroduces
// the lazy load and nobody notices until the product owner does.
//
// The widget tests stub the providers (the three FutureProviders mirror the real builds'
// holdForSession; the paged fakes inherit the real PagedNotifier.build, holds included). The
// last group then runs the REAL providers over a stubbed transport, so a holdForSession
// deleted from manager_providers.dart fails here even though the widget stubs mirror it.
//
// No NivoraTheme, same as manager_test.dart: it is built on google_fonts, which reaches for
// the network from inside the test binary. Nothing here depends on the typeface.
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/perf/session_keep_alive.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/manager/data/manager_models.dart';
import 'package:mobile/features/manager/data/manager_providers.dart';
import 'package:mobile/features/manager/manager_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _hostelId = 'h1';
const _managerId = 'u-manager';
const _ownerId = 'u-owner';

const _session = NivoraSession(
  userId: _managerId,
  role: UserRole.manager,
  fullName: 'Rahul Mehta',
  status: 'active',
  mustChangePassword: false,
  hostelId: _hostelId,
);

void main() {
  const latency = Duration(milliseconds: 300);

  /// Every request the shell can make, in the order it was DISPATCHED — the network trace the
  /// stagger assertions read.
  late List<String> log;

  List<Object> overrides() => [
        sessionProvider.overrideWithValue(_session),
        currentHostelIdProvider.overrideWithValue(_hostelId),
        // The three FutureProviders mirror the real builds: holdForSession first, then the
        // fetch. The override REPLACES the build, so without the hold here the warmed value
        // would be thrown away before the tap and these tests would test nothing. That the
        // REAL builds hold too is pinned by the 'real providers' group at the bottom.
        hostelProvider.overrideWith((ref, id) {
          holdForSession(ref);
          log.add('hostel');
          return Future.delayed(latency, () => _hostel());
        }),
        taskLoadProvider.overrideWith((ref, id) {
          holdForSession(ref);
          log.add('taskLoad');
          return Future.delayed(latency, () => const TaskLoad(open: 4, overdue: 2));
        }),
        managerFinanceProvider.overrideWith((ref, id) {
          holdForSession(ref);
          log.add('finance');
          return Future.delayed(latency, _window);
        }),
        weeklyMenuProvider.overrideWith((ref, id) {
          holdForSession(ref);
          log.add('menu');
          return Future.delayed(latency, _menu);
        }),
        // The fakes below override ONLY the fetch, so the real builds — including the
        // holdForSession that keeps a warmed page alive with no listener — still run.
        tasksProvider.overrideWith2((query) => _SlowTasks(query, log)),
        managerExpensesProvider.overrideWith2((query) => _SlowExpenses(query, log)),
        managerRevenuesProvider.overrideWith2((id) => _SlowRevenues(id, log)),
        // Pinned so the menu assertions are not a different test on Sunday.
        menuDayProvider.overrideWith(_PinnedWednesday.new),
      ];

  Future<void> pumpShell(WidgetTester tester) async {
    // Tall, so every home section (including "Next up", which shares the Tasks tab's query)
    // is genuinely mounted in the first frame, the way it is on a phone that scrolls.
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides().cast(),
        child: const MaterialApp(home: ManagerShell()),
      ),
    );
  }

  /// A destination on the bottom bar, told apart from a screen title wearing the same word.
  Finder destination(String label) =>
      find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

  /// The one shape of "still loading" a manager screen can draw. (RefreshIndicator's spinner
  /// exists only while a pull gesture is in progress, so this finder is exactly the skeleton.)
  void expectNoSpinner() {
    expect(find.byType(CircularProgressIndicator), findsNothing);
  }

  testWidgets(
      'home wins the network, warm-up is staggered behind it, and every section then '
      'arrives with data — no spinner, no refetch', (tester) async {
    log = [];
    await pumpShell(tester);

    // FRAME ONE. Home and the shell's own chrome dispatch, and nothing else: the badge's
    // count, the hostel status row, the finance window, and the "Next up" jobs (the same
    // TaskQuery the Tasks tab will watch). The spinners here are the one legitimate loading
    // face of the whole session: the genuinely cold first paint of home.
    expect(log, ['taskLoad', 'hostel', 'finance', 'tasks(open) p0']);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    // Inside the head start (the first warmer fires at +150ms): still only home's requests.
    await tester.pump(const Duration(milliseconds: 100));
    expect(log, ['taskLoad', 'hostel', 'finance', 'tasks(open) p0'],
        reason: 'warm-up must not contend with the first paint');

    // Let the stagger play out and every fake fetch land.
    await tester.pump(const Duration(milliseconds: 1400));
    expect(
      log,
      [
        'taskLoad', 'hostel', 'finance', 'tasks(open) p0',
        // +150ms warms the Tasks tab's page — same family instance home already started, so
        // no new dispatch appears for it. The next three are the reads nothing on home makes:
        'expenses(all) p0', // +300ms — the Expenses tab's default list
        'menu', // +450ms — the Menu tab's whole week
        'revenues p0', // +600ms — the "Money in" segment nothing builds until it is tapped
        // +750ms and +900ms warm taskLoad and finance — both already live (the badge and home
        // hold them), so the reads join the cache and dispatch nothing. Belt and braces.
      ],
      reason: 'one warmer per interval, in tap-likelihood order, home never re-fetched',
    );

    // Home is now fully drawn — and from here on, NOTHING may show a spinner.
    expect(find.text('4'), findsWidgets, reason: 'the jobs-open hero figure');
    expectNoSpinner();

    // ── EXPENSES, one frame after the tap. The fetch takes 300ms, so this ledger row can
    // only be here if the tap rendered from the warmed, session-held page.
    await tester.tap(destination('Expenses'));
    await tester.pump();
    expect(find.text('-₹2,450.50'), findsOneWidget,
        reason: 'arrival must render the data, not earn it');
    expectNoSpinner();

    // ── MONEY IN, one frame after the segment tap — a section nothing had built until now,
    // fetched purely by the warmer.
    await tester.tap(find.text('Money in'));
    await tester.pump();
    expect(find.text('+₹6,000'), findsOneWidget);
    expectNoSpinner();

    // ── TASKS, one frame after the tap: the page home started, the counts the badge holds.
    await tester.tap(destination('Tasks'));
    await tester.pump();
    expect(find.text('Buy vegetables for the week'), findsWidgets);
    expect(find.textContaining('jobs open'), findsOneWidget);
    expectNoSpinner();

    // ── MENU, one frame after the tap.
    await tester.tap(destination('Menu'));
    await tester.pump();
    expect(find.text('Idli, sambar, coconut chutney'), findsOneWidget);
    expectNoSpinner();

    // ── REVISIT. Back to Expenses: instant, from the kept widget and the held pages. The
    // segmented control still says Money in — the tab kept its state too.
    await tester.tap(destination('Expenses'));
    await tester.pump();
    expect(find.text('+₹6,000'), findsOneWidget);
    expectNoSpinner();

    // The whole tour — three first visits, a segment switch and a revisit — cost ZERO
    // requests beyond the seven dispatched at sign-in. That is the product owner's "like
    // Google apps" bar, measured.
    expect(log.length, 7, reason: 'a tap must never be what starts a fetch');
  });

  testWidgets(
      'a background refresh renders the held rows while it is in flight — '
      'never a blank, never a spinner', (tester) async {
    log = [];
    await pumpShell(tester);
    await tester.pump(const Duration(milliseconds: 1500)); // warm everything

    await tester.tap(destination('Expenses'));
    await tester.pump();
    expect(find.text('-₹2,450.50'), findsOneWidget);

    // Something invalidates the ledger — refreshMoney after a write, a pull-to-refresh —
    // while the manager is looking at it.
    final container = ProviderScope.containerOf(tester.element(find.byType(ManagerShell)));
    container.invalidate(managerExpensesProvider(const ExpenseQuery(hostelId: _hostelId)));
    await tester.pump();
    expect(log.last, 'expenses(all) p0', reason: 'the refetch is now in flight');

    // Mid-refresh: the PREVIOUS rows are what renders. Not a skeleton, not an empty note.
    expect(find.text('-₹2,450.50'), findsOneWidget,
        reason: 'stale-while-revalidate: the held value shows during the refresh');
    expectNoSpinner();

    // The refresh lands; the row is simply replaced in place.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('-₹2,450.50'), findsOneWidget);
    expectNoSpinner();
  });

  // ───────────────────────────────────────────────────────────────────────────
  // The REAL providers, real repositories, stubbed transport. The widget tests above mirror
  // holdForSession inside their FutureProvider stubs; this group is what fails if the hold is
  // ever removed from manager_providers.dart itself.
  // ───────────────────────────────────────────────────────────────────────────
  group('the real manager providers hold what the warm-up fetched', () {
    late int requests;
    late SupabaseClient client;
    late _MutableSession auth;
    late ProviderContainer container;

    setUp(() {
      requests = 0;
      // Answers everything the manager's tab providers can ask: selects and the finance RPC
      // get an empty JSON array; the two task counts get a content-range total.
      client = SupabaseClient(
        'https://stub.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          requests += 1;
          return http.Response(
            '[]',
            200,
            request: request,
            headers: {
              'content-type': 'application/json',
              if (request.url.path.endsWith('/tasks')) 'content-range': '*/3',
            },
          );
        }),
      );
      auth = _MutableSession(_session);
      container = ProviderContainer(overrides: [
        supabaseClientProvider.overrideWithValue(client),
        sessionProvider.overrideWith((ref) => auth.watch(ref)),
      ]);
      addTearDown(container.dispose);
      addTearDown(client.dispose);
    });

    // Lets the container's dispose scheduler run, the way an event-loop turn does in the app.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    /// Warm-then-revisit, the way the shell does it: read the future with no listener held
    /// (exactly what TabWarmer does), let the dispose scheduler run, then revisit. The value
    /// must be there synchronously and the revisit must cost zero requests.
    Future<void> expectHeld(
      String name, {
      required Future<Object?> Function() warm,
      required AsyncValue<Object?> Function() revisit,
    }) async {
      await warm();
      final before = requests;
      await settle();

      expect(revisit().hasValue, isTrue,
          reason: '$name must survive the warm read with no listener — '
              'is holdForSession still first in its build?');
      expect(requests, before, reason: '$name refetched on revisit');
    }

    test('every warmed read survives with no listener and revisits from cache', () async {
      const expenseKey = ExpenseQuery(hostelId: _hostelId);
      await expectHeld('taskLoadProvider',
          warm: () => container.read(taskLoadProvider(_hostelId).future),
          revisit: () => container.read(taskLoadProvider(_hostelId)));
      await expectHeld('managerFinanceProvider',
          warm: () => container.read(managerFinanceProvider(_hostelId).future),
          revisit: () => container.read(managerFinanceProvider(_hostelId)));
      await expectHeld('weeklyMenuProvider',
          warm: () => container.read(weeklyMenuProvider(_hostelId).future),
          revisit: () => container.read(weeklyMenuProvider(_hostelId)));
      await expectHeld('managerExpensesProvider',
          warm: () => container.read(managerExpensesProvider(expenseKey).future),
          revisit: () => container.read(managerExpensesProvider(expenseKey)));
      await expectHeld('managerRevenuesProvider',
          warm: () => container.read(managerRevenuesProvider(_hostelId).future),
          revisit: () => container.read(managerRevenuesProvider(_hostelId)));
    });

    test('sign-out drops every held read — nothing survives into the next login', () async {
      // The shell is mounted and watching, as it is at the moment a real sign-out happens.
      final sub = container.listen(weeklyMenuProvider(_hostelId), (_, _) {});
      await container.read(weeklyMenuProvider(_hostelId).future);

      auth.set(null); // sign out: holdForSession releases the link…
      await settle(); //  …the change propagates (in the app, before the next frame)…
      sub.close(); //     …and the sign-out redirect unmounts the shell.
      await settle();

      // The next manager of the same hostel signs in on this device.
      auth.set(const NivoraSession(
        userId: 'u-manager-2',
        role: UserRole.manager,
        fullName: 'Priya Nair',
        status: 'active',
        mustChangePassword: false,
        hostelId: _hostelId,
      ));
      final fresh = container.read(weeklyMenuProvider(_hostelId));
      expect(fresh.isLoading, isTrue);
      expect(fresh.value, isNull,
          reason: 'cached tenant data must not survive a sign-out, even for one frame');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIXTURES
// ─────────────────────────────────────────────────────────────────────────────

Hostel _hostel() => Hostel(
      id: _hostelId,
      name: 'Sunrise Residency',
      ownerUserId: _ownerId,
      totalFloors: 3,
      totalRooms: 12,
      bedsPerRoomDefault: 3,
      status: HostelStatus.active,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

FinanceWindow _window() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return FinanceWindow(
    days: [FinanceDay(day: today, revenue: 1000, expense: 400)],
    monthStart: DateTime(now.year, now.month),
    trendStart: today.subtract(const Duration(days: trendDays - 1)),
    today: today,
  );
}

List<Task> _tasks() => [
      Task(
        id: 't1',
        hostelId: _hostelId,
        assignedTo: _managerId,
        title: 'Buy vegetables for the week',
        status: TaskStatus.pending,
        createdBy: _ownerId,
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
      ),
    ];

List<Expense> _expenses() => [
      Expense(
        id: 'e1',
        hostelId: _hostelId,
        date: DateTime(2026, 8, 24),
        category: ExpenseCategory.groceries,
        amount: 2450.50,
        createdAt: DateTime.utc(2026, 8, 24),
        updatedAt: DateTime.utc(2026, 8, 24),
      ),
    ];

List<Revenue> _revenues() => [
      Revenue(
        id: 'r1',
        hostelId: _hostelId,
        date: DateTime(2026, 8, 23),
        source: RevenueSource.mess,
        amount: 6000,
        createdAt: DateTime.utc(2026, 8, 23),
        updatedAt: DateTime.utc(2026, 8, 23),
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
    ]);

PagedResult<T> _one<T>(List<T> items) =>
    PagedResult<T>(items: items, page: 0, pageSize: 20, hasMore: false);

/// The real notifier — real [PagedNotifier.build], real holdForSession — with only the
/// network swapped for a 300ms fake, and every dispatch written to the shared log.
class _SlowTasks extends TasksNotifier {
  _SlowTasks(super.query, this.log);
  final List<String> log;

  @override
  Future<PagedResult<Task>> fetchPage(int page) {
    log.add('tasks(${query.openOnly ? 'open' : 'all'}) p$page');
    return Future.delayed(const Duration(milliseconds: 300), () => _one(_tasks()));
  }
}

class _SlowExpenses extends ManagerExpensesNotifier {
  _SlowExpenses(super.query, this.log);
  final List<String> log;

  @override
  Future<PagedResult<Expense>> fetchPage(int page) {
    log.add('expenses(${query.category?.wire ?? 'all'}) p$page');
    return Future.delayed(const Duration(milliseconds: 300), () => _one(_expenses()));
  }
}

class _SlowRevenues extends ManagerRevenuesNotifier {
  _SlowRevenues(super.hostelId, this.log);
  final List<String> log;

  @override
  Future<PagedResult<Revenue>> fetchPage(int page) {
    log.add('revenues p$page');
    return Future.delayed(const Duration(milliseconds: 300), () => _one(_revenues()));
  }
}

/// Pins the menu screen to Wednesday, where the fixture's breakfast lives.
class _PinnedWednesday extends MenuDayState {
  @override
  MenuDay build() => MenuDay.wed;
}

/// A sessionProvider the test can flip to null and back, standing in for the AuthController
/// without touching Supabase.
class _MutableSession {
  _MutableSession(this._value);

  NivoraSession? _value;
  final _listeners = <void Function()>[];

  NivoraSession? watch(Ref ref) {
    void listener() => ref.invalidateSelf();
    _listeners.add(listener);
    ref.onDispose(() => _listeners.remove(listener));
    return _value;
  }

  void set(NivoraSession? next) {
    _value = next;
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}
