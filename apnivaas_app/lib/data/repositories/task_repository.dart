library;

import '../models/models.dart';
import 'repository.dart';

/// Work the owner assigns to the manager.
///
/// TABLES: public.tasks.
///
/// The select policy is `owner of the hostel OR assigned_to = auth.uid()`, so this one query
/// is both the owner's board and the manager's to-do list. A manager cannot see tasks assigned
/// to anyone else, which is why there is no "all tasks" variant here.
final class TaskRepository extends Repository {
  const TaskRepository(super.db);

  /// One page of tasks. Open ones first by due date, which is the order both roles work in.
  Future<PagedResult<Task>> page({
    required String hostelId,
    int page = 0,
    int pageSize = PagedResult.defaultPageSize,
    TaskStatus? status,
    bool openOnly = false,

    /// Narrows to one assignee. The policy already does this for a manager; an OWNER uses it
    /// to look at one manager's workload.
    String? assignedTo,
  }) =>
      guard(() async {
        final bounds = rangeFor(page, pageSize);
        var query = db
            .from('tasks')
            .select(Task.columns)
            .eq('hostel_id', hostelId)
            .isFilter('deleted_at', null);

        if (status != null) {
          query = query.eq('status', status.wire);
        } else if (openOnly) {
          query = query.neq('status', TaskStatus.done.wire);
        }
        if (assignedTo != null) query = query.eq('assigned_to', assignedTo);

        final rows = await query
            // Undated tasks sort last rather than first — a task with no deadline is not
            // urgent, and nullsFirst defaults the other way for ascending order.
            .order('due_date', ascending: true, nullsFirst: false)
            .order('created_at', ascending: false)
            .range(bounds.from, bounds.to);
        return PagedResult.fromOverfetch(
          rows.map(Task.fromJson).toList(growable: false),
          page: page,
          pageSize: pageSize,
        );
      });

  Future<Task?> byId(String taskId) => guard(() async {
        // A null from here is drawn as a sentence about the reader ("not visible",
        // "belongs to another hostel", "no record for this account"). That sentence is
        // earned only when a live credential asked — a dead session makes this an
        // anonymous read whose null means nothing. See Repository.requireLiveSession.
        requireLiveSession('tasks.byId');
        final row = await db
            .from('tasks')
            .select(Task.columns)
            .eq('id', taskId)
            .maybeSingle();
        return row == null ? null : Task.fromJson(row);
      });

  /// Assign a task. Owner only.
  ///
  /// `created_by` must equal auth.uid() (insert policy) and `assigned_to` must be a user in
  /// the same hostel (app.tasks_assignee_guard) — both are checked server-side.
  Future<Task> create({
    required String hostelId,
    required String assignedTo,
    required String title,
    String? description,
    DateTime? dueDate,
  }) =>
      guardWrite(() async {
        final creator = db.auth.currentUser?.id;
        if (creator == null) {
          throw const SignedOutFailure('Sign in again to assign a task.');
        }
        final row = await db
            .from('tasks')
            .insert({
              'hostel_id': hostelId,
              'assigned_to': assignedTo,
              'title': title,
              'description': ?description,
              if (dueDate != null) 'due_date': toDateWire(dueDate),
              'created_by': creator,
            })
            .select(Task.columns)
            .single();
        return Task.fromJson(row);
      }, unresolved: 'Check the task list before assigning it again — a second task notifies '
          'the manager a second time.');

  /// Move a task's status. Both roles may call it.
  ///
  /// A manager may change ONLY the status; app.tasks_before_update reverts anything else they
  /// touch. So this method sends status alone — sending a title a manager is not allowed to
  /// change would silently do nothing and leave the UI showing an edit that did not happen.
  Future<Task> setStatus({
    required String taskId,
    required TaskStatus status,
  }) =>
      guardWrite(() async {
        final row = await db
            .from('tasks')
            .update({'status': status.wire})
            .eq('id', taskId)
            .select(Task.columns)
            .single();
        return Task.fromJson(row);
      }, unresolved: 'Reload the task before moving it again; moving it to the same status a '
          'second time is safe and notifies nobody twice.');

  /// Edit the substance of a task. Owner only — a manager's attempt is reverted by the trigger.
  Future<Task> update({
    required String taskId,
    String? title,
    String? description,
    DateTime? dueDate,
    String? assignedTo,
  }) =>
      guardWrite(() async {
        final patch = <String, dynamic>{
          'title': ?title,
          'description': ?description,
          if (dueDate != null) 'due_date': toDateWire(dueDate),
          'assigned_to': ?assignedTo,
        };
        if (patch.isEmpty) {
          throw const InvalidInputFailure('Nothing to change.');
        }
        final row = await db
            .from('tasks')
            .update(patch)
            .eq('id', taskId)
            .select(Task.columns)
            .single();
        return Task.fromJson(row);
      }, unresolved: 'Reload the task to see which details were saved; saving the same ones '
          'again is safe.');
}
