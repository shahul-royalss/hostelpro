library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/models.dart';
import '../../../data/repositories/repository.dart';
import 'manager_models.dart';

/// The queries the manager needs that no other role does.
///
/// TABLES: public.users, public.tasks (counts only).
///
/// Everything else this role reads or writes already has a repository: expenses and revenues
/// go through FinanceRepository, the task list and its status changes through TaskRepository,
/// the hostel row through HostelRepository. Adding a fourth path to public.expenses here would
/// give two files an opinion about the same table.
///
/// NONE OF THE FILTERS BELOW ARE A SECURITY CONTROL. `.eq('hostel_id', …)` is here so the
/// server returns the rows this screen asked for; what stops a manager reading another
/// hostel's books is row-level security, evaluated against the JWT. The clearest example is
/// [taskCounts], which does not filter on the assignee at all: RLS already narrows
/// public.tasks to `assigned_to = auth.uid()` for a manager, and no client-side predicate
/// could widen or narrow that.
final class ManagerRepository extends Repository {
  const ManagerRepository(super.db);

  // ───────────────────────────────────────────────────────────────────────────
  // THE MESS MENU IS NOT HERE ANY MORE
  //
  // public.menus moved to lib/data/repositories/menu_repository.dart, because the manager is
  // no longer the only role that touches it: the manager writes the week and every resident of
  // the hostel now reads it on their home screen. Leaving the query here and adding a second
  // one under lib/features/student/ would give two files an opinion about one table — which is
  // exactly what the note above forbids for public.expenses.
  // ───────────────────────────────────────────────────────────────────────────

  // ───────────────────────────────────────────────────────────────────────────
  // STAFF
  // ───────────────────────────────────────────────────────────────────────────

  /// The owner, the manager and the warden of this hostel.
  ///
  /// Used to put a NAME against a task's `created_by` and `assigned_to`. The role filter
  /// mirrors the users_select policy rather than trying to do its job: a manager who asked for
  /// students here would get an empty list from the server, not a leak.
  Future<List<StaffMember>> staff(String hostelId) => guard(() async {
        final rows = await db
            .from('users')
            .select(StaffMember.columns)
            .eq('hostel_id', hostelId)
            .inFilter('role', const ['owner', 'manager', 'warden'])
            .isFilter('deleted_at', null)
            .order('role');
        return rows.map(StaffMember.fromJson).toList(growable: false);
      });

  // ───────────────────────────────────────────────────────────────────────────
  // TASK LOAD
  // ───────────────────────────────────────────────────────────────────────────

  /// How many jobs are open, and how many of those are late.
  ///
  /// TWO HEAD REQUESTS, NO ROWS. `.count()` sends `Prefer: count=exact` and returns the number
  /// alone — the home screen needs the figure, not the rows behind it, and a manager with a
  /// long backlog should not pay for them to be serialised.
  ///
  /// [today] is passed in rather than read from the clock here so the caller decides which
  /// day boundary applies and the method stays testable. Overdue is `due_date < today`, which
  /// matches Task.isOverdue on the client exactly — the same task must not be late on the
  /// dashboard and on time in the list.
  Future<TaskLoad> taskCounts({
    required String hostelId,
    required DateTime today,
  }) =>
      guard(() async {
        final open = await db
            .from('tasks')
            .count(CountOption.exact)
            .eq('hostel_id', hostelId)
            .isFilter('deleted_at', null)
            .neq('status', TaskStatus.done.wire);

        final overdue = await db
            .from('tasks')
            .count(CountOption.exact)
            .eq('hostel_id', hostelId)
            .isFilter('deleted_at', null)
            .neq('status', TaskStatus.done.wire)
            .lt('due_date', toDateWire(today));

        return TaskLoad(open: open, overdue: overdue);
      });
}
