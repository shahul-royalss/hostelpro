library;

import 'enums.dart';
import 'parse.dart';

/// public.tasks — work an owner assigns to a manager.
///
/// `assigned_to` is a users.id, not a students.id, and app.tasks_assignee_guard refuses an
/// assignee outside the hostel. `completed_at` is stamped by app.tasks_before_update when the
/// status reaches 'done'; sending it from the client does nothing.
class Task {
  const Task({
    required this.id,
    required this.hostelId,
    required this.assignedTo,
    required this.title,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.dueDate,
    this.completedAt,
    this.deletedAt,
  });

  static const columns =
      'id, hostel_id, assigned_to, title, description, due_date, status, created_by, '
      'completed_at, created_at, updated_at, deleted_at';

  final String id;
  final String hostelId;

  /// The manager's users.id.
  final String assignedTo;
  final String title;
  final String? description;

  /// Plain `date`, nullable — a task without a deadline is allowed.
  final DateTime? dueDate;
  final TaskStatus status;

  /// The owner who raised it.
  final String createdBy;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft delete (§4.10). Queries here filter it out; the column is carried for completeness.
  final DateTime? deletedAt;

  bool get isOpen => status.isOpen;

  /// Past its due date and still not done. Compared on the local calendar day, because "due
  /// today" means today where the hostel is, not in UTC.
  bool get isOverdue {
    final due = dueDate;
    if (due == null || !status.isOpen) return false;
    final now = DateTime.now();
    return due.isBefore(DateTime(now.year, now.month, now.day));
  }

  factory Task.fromJson(Map<String, dynamic> row) {
    const src = 'tasks';
    return Task(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      assignedTo: reqString(row, src, 'assigned_to'),
      title: reqString(row, src, 'title'),
      description: optString(row, 'description'),
      dueDate: optDate(row, src, 'due_date'),
      status: wireOrThrow(TaskStatus.values, row['status'], src, 'status'),
      createdBy: reqString(row, src, 'created_by'),
      completedAt: optTimestamp(row, src, 'completed_at'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
      deletedAt: optTimestamp(row, src, 'deleted_at'),
    );
  }
}
