/// public.menus — the mess menu, as both roles see it.
///
/// LIVED IN features/manager/data/manager_models.dart UNTIL THE RESIDENTS COULD READ IT. Two
/// roles now draw these rows: the manager writes the week, and every resident of the hostel
/// reads it (menus_select is hostel-wide — verified against the live project by impersonating
/// a student JWT, which sees exactly the rows the manager just wrote). A model that two
/// features share belongs to neither of them, and a copy under lib/features/student/ would be
/// a second definition of "what is being served" — free to drift from the one the kitchen
/// types into.
///
/// The two enums mirror public.day_of_week and public.meal_type exactly, and are parsed BY
/// WIRE VALUE like every other enum in this app — never by index. See enums.dart for why:
/// `alter type ... add value ... before` reorders a Postgres enum, and an index-based parse
/// would then start serving Tuesday's dinner on Monday.
library;

import 'enums.dart';
import 'parse.dart';

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
