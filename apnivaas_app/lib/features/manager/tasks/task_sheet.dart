library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../data/manager_providers.dart';
import '../widgets/manager_ui.dart';

/// One job: what it is, who asked for it, and the only thing a manager can change about it.
///
/// TABLE: public.tasks.
///
/// WHAT A MANAGER MAY ACTUALLY DO HERE, AND WHY THE FORM IS SHAPED LIKE THAT. The owner raises
/// a task and assigns it; the manager moves it along. That is not a UI decision — app
/// .tasks_before_update raises "Managers can only update the task status." on any change to
/// the title, description, due date, assignee or creator, and tasks_insert requires
/// `owns_hostel(hostel_id)`, which a manager never satisfies. So this sheet offers exactly one
/// control: the status. There is no edit field that would be silently reverted, and no "new
/// task" button that would always fail.
///
/// The assignment IS shown, in words, for the same reason: it is the part of the row a manager
/// needs and cannot alter. Seeing "raised by Anita Rao, assigned to you" is how a manager knows
/// who to go back to when a job cannot be done — and the names come from public.users, which
/// RLS lets a manager read for the owner, the manager and the warden of their own hostel only.
Future<bool?> showTaskSheet(BuildContext context, {required Task task}) {
  return showGlassSheet<bool>(
    context: context,
    builder: (_) => _TaskSheet(task: task),
  );
}

class _TaskSheet extends ConsumerStatefulWidget {
  const _TaskSheet({required this.task});
  final Task task;

  @override
  ConsumerState<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends ConsumerState<_TaskSheet> {
  bool _busy = false;

  Future<void> _setStatus(TaskStatus status) async {
    if (status == widget.task.status) return;
    setState(() => _busy = true);

    final repo = ref.read(taskRepositoryProvider);
    final ok = await runAction(
      context,
      success: 'Marked ${status.label.toLowerCase()}',
      // Sends the status ALONE. The trigger reverts anything else a manager touches, so a
      // wider patch would look like it worked and change nothing.
      action: () => repo.setStatus(taskId: widget.task.id, status: status),
    );

    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      refreshTasks(ref);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final task = widget.task;
    final session = ref.watch(sessionProvider);
    final hostelId = ref.watch(currentHostelIdProvider);
    // The same discard as everywhere else in this role: `.value ?? {}` made a name that is
    // still arriving, a name lookup that FAILED and a colleague who has genuinely been
    // deactivated all come out as the same empty map — and the fallbacks below then state
    // "The owner" as a fact. Keeping the AsyncValue lets a name we could not read say so
    // instead of guessing, while a colleague RLS no longer returns keeps the plain wording
    // that was written for exactly that case.
    final staff = hostelId == null ? null : ref.watch(staffNamesProvider(hostelId));
    final names = staff?.value ?? const <String, String>{};
    // hasValue first, as AsyncSection does it.
    final unresolved = staff == null || staff.hasValue
        ? null
        : staff.hasError
            ? 'Name unavailable'
            : 'Looking up the name…';

    final due = task.dueDate;
    final description = task.description?.trim();

    return SheetBody(
      title: task.title,
      subtitle: due == null ? 'No deadline' : dueLabel(due),
      trailing: Pill(status: task.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (description != null && description.isNotEmpty) ...[
            Text(description, style: t.textTheme.bodyMedium),
            const SizedBox(height: Space.md),
          ],

          DetailRow(
            icon: Icons.person_outline_rounded,
            label: 'Assigned to',
            // The signed-in manager is the only person a task of theirs can be assigned to —
            // RLS returns no other. Saying "you" is shorter and truer than repeating a name.
            value: task.assignedTo == session?.userId
                ? 'You'
                : names[task.assignedTo] ?? unresolved ?? 'Someone else',
          ),
          DetailRow(
            icon: Icons.outbox_rounded,
            label: 'Raised by',
            // A name is only available while that colleague is active and readable. A missing
            // one is said as "The owner", never printed as a uuid — but only once the lookup
            // has actually come back. Naming the owner on the strength of a failed read is a
            // claim about a person, made from no data at all.
            value: names[task.createdBy] ?? unresolved ?? 'The owner',
          ),
          DetailRow(
            icon: Icons.event_rounded,
            label: 'Due',
            value: due == null ? 'No date set' : '${shortDate(due)} · ${dueLabel(due)}',
          ),
          if (task.completedAt != null)
            DetailRow(
              icon: Icons.check_circle_outline_rounded,
              label: 'Finished',
              // Stamped by app.tasks_before_update when the status reaches 'done'. The client
              // never sends it, so this is the server's own record of when the job closed.
              value: shortDate(task.completedAt!),
            ),

          const SizedBox(height: Space.lg),
          const SectionLabel(label: 'Move it along'),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final status in TaskStatus.values)
                ToggleChip(
                  label: status.label,
                  selected: task.status == status,
                  onSelected: _busy ? null : (_) => _setStatus(status),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Only the status is yours to change. The owner sets the title, the deadline and '
            'who it goes to.',
            style: t.textTheme.bodySmall,
          ),
          if (_busy) ...[
            const SizedBox(height: Space.md),
            const Center(
              child: SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ],
        ],
      ),
    );
  }
}
