library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../data/manager_providers.dart';
import '../widgets/manager_ui.dart';
import '../widgets/paged_list.dart';
import 'task_sheet.dart';

/// The jobs the owner has put on the manager.
///
/// TABLE: public.tasks, through the shared TaskRepository.
///
/// THE LIST IS NOT FILTERED BY ASSIGNEE HERE, ON PURPOSE. The select policy is
/// `owns_hostel(hostel_id) OR assigned_to = auth.uid()`, so a manager already receives their
/// own tasks and nothing else. Adding `.eq('assigned_to', me)` in Dart would restate a policy
/// in a place that cannot enforce it, and would read to the next person like the security
/// lives in the client. It does not.
///
/// THE "TO DO" CHIP IS `status <> 'done'`, which is exactly what the home screen's open count
/// is. That is deliberate: a manager who taps "4 jobs open" must land on four rows. A chip that
/// showed only 'pending' would show fewer, and a number you cannot reconcile with the list
/// behind it is a number you stop believing.
class ManagerTasksScreen extends ConsumerWidget {
  const ManagerTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);
    final filter = ref.watch(taskFilterProvider);

    if (hostelId == null) {
      return const ManagerScreen(
        title: 'Tasks',
        child: EmptyNote(
          icon: Icons.checklist_rounded,
          title: 'No hostel on this account',
          detail: 'A manager runs exactly one hostel. Ask the owner to check the assignment.',
        ),
      );
    }

    final query = TaskQuery(
      hostelId: hostelId,
      status: filter.status,
      openOnly: filter.openOnly,
    );
    final page = ref.watch(tasksProvider(query));
    final load = ref.watch(taskLoadProvider(hostelId)).value;

    return ManagerScreen(
      title: 'Tasks',
      subtitle: load == null
          ? null
          : load.isClear
              ? 'Nothing open'
              : '${plural(load.open, 'job', 'jobs')} open'
                  '${load.overdue > 0 ? ' · ${load.overdue} late' : ''}',
      child: PagedList<Task>(
        value: page,
        onRefresh: () async {
          ref.invalidate(tasksProvider(query));
          ref.invalidate(taskLoadProvider(hostelId));
        },
        onLoadMore: () => ref.read(tasksProvider(query).notifier).loadMore(),
        header: const _Filters(),
        empty: EmptyNote(
          icon: filter == TaskFilter.needsAction
              ? Icons.check_circle_outline_rounded
              : Icons.checklist_rounded,
          title: switch (filter) {
            TaskFilter.needsAction => 'Nothing waiting on you',
            TaskFilter.done => 'Nothing finished yet',
            _ => 'No ${filter.label.toLowerCase()} jobs',
          },
          detail: filter == TaskFilter.needsAction
              ? 'New jobs arrive here when the owner assigns one.'
              : null,
        ),
        itemBuilder: (context, task) => _TaskRow(task: task),
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(taskFilterProvider);
    final notifier = ref.read(taskFilterProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in TaskFilter.values) ...[
              if (f != TaskFilter.values.first) const SizedBox(width: Space.xs),
              ChoiceChip(
                label: Text(f.label),
                selected: selected == f,
                onSelected: (_) => notifier.set(f),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final due = task.dueDate;

    return TapRow(
      onTap: () => showTaskSheet(context, task: task),
      semanticLabel: '${task.title}. ${task.status.label}'
          '${due == null ? '' : '. ${dueLabel(due)}'}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: t.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.xxs),
                Row(
                  children: [
                    Pill(status: task.status),
                    if (due != null) ...[
                      const SizedBox(width: Space.xs),
                      // isOverdue comes from the Task model — due date past AND still open —
                      // so the pill and the server's own count agree on what "late" means.
                      task.isOverdue
                          ? Pill.text(label: dueLabel(due), tone: NivoraColors.error)
                          : Flexible(
                              child: Text(
                                dueLabel(due),
                                style: t.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          Icon(Icons.chevron_right_rounded,
              size: IconSize.md, color: t.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
