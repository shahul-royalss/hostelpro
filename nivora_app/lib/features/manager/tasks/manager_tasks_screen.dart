library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../common/refresh.dart';
import '../data/manager_models.dart';
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
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Space.md),
          child: EmptyNote(
            icon: Icons.checklist_rounded,
            title: 'No hostel on this account',
            detail: 'A manager runs exactly one hostel. Ask the owner to check the assignment.',
          ),
        ),
      );
    }

    final query = TaskQuery(
      hostelId: hostelId,
      status: filter.status,
      openOnly: filter.openOnly,
    );
    final page = ref.watch(tasksProvider(query));
    final load = ref.watch(taskLoadProvider(hostelId));

    return ManagerScreen(
      title: 'Tasks',
      subtitle: _loadLine(load),
      child: PagedList<Task>(
        value: page,
        onRefresh: () {
          ref.invalidate(tasksProvider(query));
          ref.invalidate(taskLoadProvider(hostelId));
          return settleRefresh(context, () => ref.read(tasksProvider(query).future));
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
          tone: filter == TaskFilter.needsAction ? NivoraColors.success : null,
        ),
        // EXACTLY the row the home screen's `TODAY'S TASKS` section draws — 4:1197 is the only
        // list row on either of this role's frames, and one anatomy is what makes the dashboard
        // and the tab read as the same product.
        itemBuilder: (context, task) => TaskLine(
          task: task,
          onTap: () => showTaskSheet(context, task: task),
        ),
      ),
    );
  }
}

/// The counts under the title — and what they say when there are none to give.
///
/// This is the third place taskLoadProvider is read, and it threw its error away like the
/// other two: `.value` is null while counting AND when the count failed, so a header that
/// could not be produced looked exactly like a header that was still coming. The list below
/// draws its own failure, but the list and the count are different reads: the page can arrive
/// while the two HEAD requests behind the count do not.
///
/// Null is still "counting" — an absent subtitle for a moment is honest, and there is nowhere
/// quieter to put it. "Job count unavailable" is a fourth string that no successful read can
/// produce, so it cannot be confused with "Nothing open". The retry is pull-to-refresh on the
/// list below, which invalidates taskLoadProvider along with the page.
String? _loadLine(AsyncValue<TaskLoad> load) {
  // hasValue first: a failed refresh must not blank a count already on screen.
  if (load.hasValue) {
    final l = load.requireValue;
    if (l.isClear) return 'Nothing open';
    return '${plural(l.open, 'job', 'jobs')} open'
        '${l.overdue > 0 ? ' · ${l.overdue} late' : ''}';
  }
  if (load.hasError) return 'Job count unavailable — pull down to try again';
  return null;
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
              ToggleChip(
                label: f.label,
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
