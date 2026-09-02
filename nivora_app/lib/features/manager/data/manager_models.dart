library;

import '../../../data/models/models.dart';
// The row coercers stay private to the data layer's barrel — models.dart re-exports only
// RowShapeError and the two wire formatters. A model built outside lib/data imports parse.dart
// directly, exactly as features/warden/data/warden_models.dart does, so that a wrong column
// still names itself instead of arriving as a silent null.
import '../../../data/models/parse.dart';

/// The manager's own row shapes.
///
/// Everything the shared data layer already models — Expense, Revenue, Task, FinanceDay, and
/// now the mess menu — is used from lib/data/models and NOT redeclared here. What is left is
/// the two things only this role touches: the staff directory a task's assignment is read
/// against (public.users, narrowed by RLS to owner/manager/warden), and two derived views over
/// rows the server already returned.

/// public.menus — the mess menu — IS NOT DECLARED HERE ANY MORE.
///
/// It moved to lib/data/models/menu.dart the day the residents could read it. Two roles draw
/// those rows now: the manager writes the week, and every resident of the hostel reads it
/// (menus_select is hostel-wide). A model two features share belongs to neither of them.
///
/// The re-export below is what keeps that move invisible to this directory: every manager
/// screen and every manager test still writes `MenuDay`, `Meal`, `MenuEntry` and `WeeklyMenu`
/// off this import, and there is exactly ONE declaration of each behind it.
export '../../../data/models/menu.dart';

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
