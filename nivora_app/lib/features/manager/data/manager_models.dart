library;

import '../../../data/models/models.dart';
// The row coercers stay private to the data layer's barrel — models.dart re-exports only
// RowShapeError and the two wire formatters. A model built outside lib/data imports parse.dart
// directly, exactly as features/warden/data/warden_models.dart does, so that a wrong column
// still names itself instead of arriving as a silent null.
import '../../../data/models/parse.dart';

/// The manager's own row shapes.
///
/// Everything the shared data layer already models — Expense, Revenue, Task, FinanceDay — is
/// used from lib/data/models and NOT redeclared here. What follows is the three things only
/// this role touches: the mess menu (public.menus, which no other role writes), the staff
/// directory a task's assignment is read against (public.users, narrowed by RLS to
/// owner/manager/warden), and two derived views over rows the server already returned.
///
/// The two enums below mirror public.day_of_week and public.meal_type exactly, and are parsed
/// BY WIRE VALUE like every other enum in this app — never by index. See lib/data/models/
/// enums.dart for why: `alter type ... add value ... before` reorders a Postgres enum, and an
/// index-based parse would then start serving Tuesday's dinner on Monday.

/// public.day_of_week
enum MenuDay implements WireValue {
  mon('mon', 'Monday', 'Mon'),
  tue('tue', 'Tuesday', 'Tue'),
  wed('wed', 'Wednesday', 'Wed'),
  thu('thu', 'Thursday', 'Thu'),
  fri('fri', 'Friday', 'Fri'),
  sat('sat', 'Saturday', 'Sat'),
  sun('sun', 'Sunday', 'Sun');

  const MenuDay(this.wire, this.label, this.short);
  @override
  final String wire;
  @override
  final String label;

  /// Three letters, for the day strip.
  final String short;

  /// The day a date falls on. `DateTime.weekday` is 1 = Monday to 7 = Sunday, which is the
  /// same order the enum is declared in — but this maps it explicitly rather than indexing, so
  /// a future reordering of the enum breaks the compile instead of the menu.
  static MenuDay of(DateTime date) => switch (date.weekday) {
        DateTime.monday => MenuDay.mon,
        DateTime.tuesday => MenuDay.tue,
        DateTime.wednesday => MenuDay.wed,
        DateTime.thursday => MenuDay.thu,
        DateTime.friday => MenuDay.fri,
        DateTime.saturday => MenuDay.sat,
        _ => MenuDay.sun,
      };

  static MenuDay? tryParse(String? v) => wireOrNull(MenuDay.values, v);
}

/// public.meal_type. Declared in the order they are eaten, which is the order the screen draws.
enum Meal implements WireValue {
  breakfast('breakfast', 'Breakfast'),
  lunch('lunch', 'Lunch'),
  snacks('snacks', 'Snacks'),
  dinner('dinner', 'Dinner');

  const Meal(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  static Meal? tryParse(String? v) => wireOrNull(Meal.values, v);
}

/// public.menus — one meal, on one day, for one hostel.
///
/// The table is unique on (hostel_id, day_of_week, meal), so there are at most 28 rows per
/// hostel and a save is an upsert on that key rather than an insert-or-update dance in Dart.
class MenuEntry {
  const MenuEntry({
    required this.id,
    required this.hostelId,
    required this.day,
    required this.meal,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.updatedBy,
  });

  static const columns =
      'id, hostel_id, day_of_week, meal, items, updated_by, created_at, updated_at';

  final String id;
  final String hostelId;
  final MenuDay day;
  final Meal meal;

  /// Free text, as typed. The column is NOT NULL and defaults to '' — a saved empty string is
  /// a real "cleared", and is not the same thing as a row that was never written.
  final String items;
  final String? updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPlanned => items.trim().isNotEmpty;

  factory MenuEntry.fromJson(Map<String, dynamic> row) {
    const src = 'menus';
    return MenuEntry(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      day: wireOrThrow(MenuDay.values, row['day_of_week'], src, 'day_of_week'),
      meal: wireOrThrow(Meal.values, row['meal'], src, 'meal'),
      items: reqString(row, src, 'items'),
      updatedBy: optString(row, 'updated_by'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
    );
  }
}

/// The week as the menu screen reads it: at most 28 rows, indexed by day and meal.
///
/// A MISSING ROW IS NOT AN EMPTY MEAL AND IS NOT AN ERROR. A hostel that has never planned
/// Saturday's snacks simply has no row for it; [itemsFor] returns null and the screen says
/// "Not planned yet". Manufacturing a blank row here would let the same screen state that
/// there are no snacks on Saturday, which is a claim the database never made.
class WeeklyMenu {
  WeeklyMenu(List<MenuEntry> entries)
      : _byKey = {for (final e in entries) _key(e.day, e.meal): e},
        lastUpdated = entries.isEmpty
            ? null
            : entries.map((e) => e.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);

  const WeeklyMenu.empty()
      : _byKey = const {},
        lastUpdated = null;

  final Map<String, MenuEntry> _byKey;

  /// The most recent `updated_at` across the week, or null when nothing has been saved.
  final DateTime? lastUpdated;

  static String _key(MenuDay day, Meal meal) => '${day.wire}|${meal.wire}';

  MenuEntry? entryFor(MenuDay day, Meal meal) => _byKey[_key(day, meal)];

  /// What is planned, or null when there is no row and null when the row is blank. Callers
  /// render null as "not planned" rather than as an empty line.
  String? itemsFor(MenuDay day, Meal meal) {
    final entry = entryFor(day, meal);
    if (entry == null || !entry.isPlanned) return null;
    return entry.items.trim();
  }

  /// How many of the day's four meals have something written against them.
  int plannedOn(MenuDay day) => Meal.values.where((m) => itemsFor(day, m) != null).length;

  bool get isEmpty => _byKey.values.every((e) => !e.isPlanned);
}

/// public.user_role, as a LABEL on somebody else's row.
///
/// Deliberately a separate type from core/auth/session.dart's UserRole: that one is the
/// signed-in identity and carries routing meaning, this one only names who a colleague is. A
/// value this build cannot represent throws rather than being drawn as "Owner".
enum UserRoleLabel implements WireValue {
  superAdmin('super_admin', 'Super Admin'),
  owner('owner', 'Owner'),
  manager('manager', 'Manager'),
  warden('warden', 'Warden'),
  student('student', 'Student');

  const UserRoleLabel(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  static UserRoleLabel? tryParse(String? v) => wireOrNull(UserRoleLabel.values, v);
}

/// A colleague, as public.users hands them to a manager.
///
/// RLS lets a manager read only the owner, the manager and the warden of their own hostel —
/// never a resident (rls-policies.sql, users_select). This class exists so a task can say
/// "assigned by Priya Nair" instead of printing a uuid at somebody.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.role,
    required this.fullName,
    this.phone,
  });

  static const columns = 'id, role, full_name, phone';

  final String id;
  final UserRoleLabel role;
  final String fullName;
  final String? phone;

  factory StaffMember.fromJson(Map<String, dynamic> row) {
    const src = 'users';
    return StaffMember(
      id: reqString(row, src, 'id'),
      role: wireOrThrow(UserRoleLabel.values, row['role'], src, 'role'),
      fullName: reqString(row, src, 'full_name'),
      phone: optString(row, 'phone'),
    );
  }
}

/// How much work is open, counted by Postgres.
///
/// BOTH FIGURES ARE `count(*)` ON THE SERVER, not a length taken from a loaded page. A count
/// derived from page zero of a paginated list reads "20" for a manager with sixty jobs
/// waiting, which is exactly the kind of quietly wrong number a home screen must never show.
///
/// RLS narrows public.tasks to `assigned_to = auth.uid()` for a manager, so these are the
/// manager's own jobs and nobody else's — the query does not have to ask for that, and could
/// not widen it if it tried.
class TaskLoad {
  const TaskLoad({required this.open, required this.overdue});

  /// status <> 'done', not soft-deleted.
  final int open;

  /// Of those, the ones whose due_date is already past.
  final int overdue;

  bool get isClear => open == 0;
}

/// Money in and money out over one window of days, from public.rpc_daily_finance.
///
/// WHY THE TOTALS ARE SUMMED IN DART AND THAT IS STILL HONEST. The RPC emits one row for
/// EVERY day in the range, zero-filled by generate_series — so the list is complete, not a
/// sample, and adding it up is arithmetic over the server's own numbers rather than an
/// estimate. One request then serves both the month-to-date totals and the short trend
/// underneath them, instead of two.
///
/// WHAT "REVENUE" MEANS HERE, AND WHAT IT DOES NOT. This is public.revenues — mess income,
/// deposits, whatever the hostel books by hand. It is NOT rent: fee collection lives in
/// public.fee_payments, which a manager cannot read at all. Every label drawn from this class
/// says "recorded", and no screen adds the two together.
class FinanceWindow {
  const FinanceWindow({
    required this.days,
    required this.monthStart,
    required this.trendStart,
    required this.today,
  });

  /// Every day the RPC returned, oldest first.
  final List<FinanceDay> days;

  /// Local midnight on the first of the current month.
  final DateTime monthStart;

  /// Local midnight on the first day of the short trend window.
  final DateTime trendStart;

  /// Local midnight today.
  final DateTime today;

  /// The days that fall in the current calendar month, up to and including today.
  List<FinanceDay> get monthDays =>
      days.where((d) => !d.day.isBefore(monthStart)).toList(growable: false);

  /// The short window the bars are drawn from.
  List<FinanceDay> get trendDays =>
      days.where((d) => !d.day.isBefore(trendStart)).toList(growable: false);

  double get monthIn => monthDays.fold(0, (sum, d) => sum + d.revenue);
  double get monthOut => monthDays.fold(0, (sum, d) => sum + d.expense);

  /// Positive when the hostel booked more in than out this month. NOT a profit figure — rent
  /// is not in it, and the screen never calls it one.
  double get monthNet => monthIn - monthOut;

  FinanceDay? get _today {
    for (final d in days) {
      if (d.day == today) return d;
    }
    return null;
  }

  /// Today's spend, or null when today is not in the window — which should not happen, and is
  /// drawn as a dash rather than as a zero.
  double? get todayOut => _today?.expense;
  double? get todayIn => _today?.revenue;

  /// The largest single-day figure in the trend, used to scale the bars. Zero means nothing was
  /// booked in the window at all, and the chart says so in words instead of drawing a flat
  /// line that looks like data.
  double get trendPeak => trendDays.fold<double>(
        0,
        (m, d) => [m, d.revenue, d.expense].reduce((a, b) => a > b ? a : b),
      );
}
