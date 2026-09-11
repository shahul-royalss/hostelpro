library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../owner_providers.dart';
import '../staff/owner_staff_screen.dart';
import '../staff/staff_models.dart';
import '../staff/staff_providers.dart';
import '../widgets/states.dart';

/// THE OWNER PUTS A JOB ON A MANAGER.
///
/// The product owner: "owner can send tasks separately to manager, not as notice."
///
/// ── WHY A TASK AND NOT A NOTICE ──────────────────────────────────────────────────────────
///
/// They were the same thing from the manager's side until 2026-09-12: a notice addressed to
/// `manager` arrived on a noticeboard, and a task arrived on the Tasks tab, and neither the
/// owner nor the manager could tell you which one an instruction would come as. A notice has no
/// due date, no status and nobody answerable for it — so "fix the geyser" sent as a notice could
/// not be chased, and could not be marked done. Notices now reach wardens and residents only
/// (announcements_select), and this screen is the other half of that decision.
///
/// ── WHAT THE DATABASE ALREADY DECIDES ────────────────────────────────────────────────────
///
/// `tasks_insert` admits the hostel's owner and nobody else. `app.tasks_assignee_guard` refuses
/// any assignee who is not an ACTIVE MANAGER OF THE SAME HOSTEL — so the picker below is drawn
/// from that same set rather than being a filter this screen invented. `app.tasks_before_update`
/// lets a manager change the status and nothing else. `app.tasks_after_change` notifies the
/// manager on assignment and the owner when the status moves, which is why nothing here sends a
/// message of its own.
///
/// READS:  public.tasks (tasksProvider), public.users (ownerStaffProvider).
/// WRITES: public.tasks, through TaskRepository.
class OwnerTasksScreen extends ConsumerWidget {
  const OwnerTasksScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const OwnerTasksScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final hostelId = ref.watch(activeHostelIdProvider);

    return Scaffold(
      body: Column(
        children: [
          GlassHeader(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: Space.xxs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tasks',
                        style: t.textTheme.titleLarge?.copyWith(color: t.colorScheme.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Jobs you have put on your manager',
                        style: t.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (hostelId != null)
                  IconButton(
                    tooltip: 'Assign a task',
                    icon: const Icon(Icons.add_rounded, size: IconSize.lg),
                    onPressed: () => showAssignTaskSheet(context, hostelId: hostelId),
                  ),
              ],
            ),
          ),
          Expanded(
            child: hostelId == null
                ? const Padding(
                    padding: EdgeInsets.all(Space.md),
                    child: EmptyNote(
                      icon: Icons.apartment_rounded,
                      title: 'No PG selected',
                      message: 'Tasks belong to a PG. Pick one on the PGs tab first.',
                    ),
                  )
                : _TaskList(hostelId: hostelId),
          ),
        ],
      ),
    );
  }
}

class _TaskList extends ConsumerWidget {
  const _TaskList({required this.hostelId});

  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // NOT filtered to open tasks. The owner's question here is "what did I ask for, and did it
    // happen" — a list that hid the finished ones could not answer the second half.
    final query = TaskQuery(hostelId: hostelId);
    final page = ref.watch(tasksProvider(query));
    final staff = ref.watch(ownerStaffProvider(hostelId)).value ?? const <StaffMember>[];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(tasksProvider(query));
        try {
          await ref.read(tasksProvider(query).future).timeout(ownerRefreshTimeout);
        } catch (_) {
          // Rendered by the body below; rethrowing here would make it unhandled.
        }
      },
      child: whenAsync(
        page,
        loading: () => ListView(
          padding: const EdgeInsets.all(Space.md),
          children: const [
            SkeletonCard(lines: 2),
            SizedBox(height: Space.md),
            SkeletonCard(lines: 2),
          ],
        ),
        error: (error) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Space.md),
          children: [
            ErrorNote(error: error, onRetry: () => ref.invalidate(tasksProvider(query))),
          ],
        ),
        data: (result) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Space.md),
          children: [
            if (result.isEmpty)
              const EmptyNote(
                icon: Icons.checklist_rounded,
                title: 'Nothing assigned yet',
                message: 'A task carries a due date and a status, so you can see whether it '
                    'happened. Tap + to assign the first one.',
                tone: NivoraColors.info,
              )
            else
              for (final task in result.items) ...[
                _TaskCard(task: task, staff: staff),
                const SizedBox(height: Space.sm),
              ],
            if (result.hasMore) ...[
              const SizedBox(height: Space.xs),
              Center(
                child: TextButton(
                  onPressed: () => ref.read(tasksProvider(query).notifier).loadMore(),
                  child: const Text('Load older tasks'),
                ),
              ),
            ],
            const SizedBox(height: Space.xl),
          ],
        ),
      ),
    );
  }
}

/// One job: what it is, who has it, when it is due, and where it has got to.
class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.staff});

  final Task task;

  /// So the assignee's user id can be shown as a NAME. public.tasks stores the id only.
  final List<StaffMember> staff;

  static final DateFormat _due = DateFormat('d MMM');

  String get _assignee {
    for (final member in staff) {
      if (member.id == task.assignedTo) return member.fullName;
    }
    // A manager who was deactivated after the task was assigned is no longer in the list. The
    // task is still real and still theirs; saying "a manager" is truer than showing a uuid.
    return 'a manager';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final done = task.status == TaskStatus.done;
    final tone = done
        ? NivoraColors.success
        : task.isOverdue
            ? NivoraColors.error
            : NivoraColors.warning;

    final description = task.description?.trim();
    return GlassCard(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(task.title, style: t.textTheme.titleMedium),
              ),
              const SizedBox(width: Space.xs),
              StatusChip(label: task.status.label, tone: tone, dot: true),
            ],
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: Space.xxs),
            Text(description, style: t.textTheme.bodySmall),
          ],
          const SizedBox(height: Space.sm),
          Text(
            [
              _assignee,
              if (task.dueDate != null)
                task.isOverdue && !done
                    ? 'was due ${_due.format(task.dueDate!)}'
                    : 'due ${_due.format(task.dueDate!)}',
            ].join(' · '),
            style: t.textTheme.bodySmall?.copyWith(color: context.tones.muted),
          ),
        ],
      ),
    );
  }
}

/// Assigning one.
Future<bool?> showAssignTaskSheet(BuildContext context, {required String hostelId}) {
  return showGlassSheet<bool>(
    context: context,
    builder: (_) => _AssignTaskSheet(hostelId: hostelId),
  );
}

class _AssignTaskSheet extends ConsumerStatefulWidget {
  const _AssignTaskSheet({required this.hostelId});

  final String hostelId;

  @override
  ConsumerState<_AssignTaskSheet> createState() => _AssignTaskSheetState();
}

class _AssignTaskSheetState extends ConsumerState<_AssignTaskSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();

  DateTime? _due;
  String? _assignee;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? today,
      firstDate: DateTime(today.year, today.month, today.day),
      // A year is past any real job. The column has no bound; this one stops a mis-typed year
      // from producing a task that is never due.
      lastDate: DateTime(today.year + 1, today.month, today.day),
    );
    if (picked != null && mounted) {
      setState(() => _due = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _submit(List<StaffMember> managers) async {
    if (_busy) return;
    if (_form.currentState?.validate() != true) return;
    final assignee = _assignee ?? (managers.length == 1 ? managers.first.id : null);
    if (assignee == null) {
      setState(() => _error = 'Choose who this is for.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(taskRepositoryProvider).create(
            hostelId: widget.hostelId,
            assignedTo: assignee,
            title: _title.text.trim(),
            description:
                _description.text.trim().isEmpty ? null : _description.text.trim(),
            dueDate: _due,
          );
      // The list is keyed on a TaskQuery; the whole family goes, because assigning a task is
      // rare and every open filter of it is now out of date.
      ref.invalidate(tasksProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppFailure.from(error).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final staff = ref.watch(ownerStaffProvider(widget.hostelId));
    // THE PICKER IS THE DATABASE'S OWN SET. app.tasks_assignee_guard refuses anyone who is not
    // an active manager of this hostel, so offering anybody else would be offering a refusal.
    final managers = [
      for (final member in staff.value ?? const <StaffMember>[])
        if (member.role == StaffRole.manager && member.isActive) member,
    ];
    final error = _error;

    if (staff.hasValue && managers.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Assign a task', style: t.textTheme.titleLarge),
          const SizedBox(height: Space.md),
          const EmptyNote(
            icon: Icons.manage_accounts_rounded,
            title: 'No active manager',
            message: 'A task goes to a manager, and this PG has none right now. Add one and '
                'the task can go out the same minute.',
            compact: true,
            tone: NivoraColors.info,
          ),
          const SizedBox(height: Space.md),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const OwnerStaffScreen()),
              );
            },
            icon: const Icon(Icons.person_add_alt_rounded, size: IconSize.md),
            label: const Text('Add a manager'),
          ),
        ],
      );
    }

    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Assign a task', style: t.textTheme.titleLarge),
          const SizedBox(height: Space.xxs),
          Text(
            'It arrives on their Tasks tab as a notification, with the due date on it.',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'What needs doing',
              hintText: 'Service the geyser on the second floor',
              counterText: '',
            ),
            validator: (raw) {
              final v = (raw ?? '').trim();
              if (v.length < 3) return 'Say what the job is';
              return null;
            },
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _description,
            maxLength: 1000,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Details (optional)',
              hintText: 'The plumber comes on Tuesdays; ask at the desk for the key.',
            ),
          ),
          const SizedBox(height: Space.sm),
          if (managers.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: _assignee,
              decoration: const InputDecoration(labelText: 'Who it is for'),
              items: [
                for (final member in managers)
                  DropdownMenuItem(value: member.id, child: Text(member.fullName)),
              ],
              onChanged: _busy ? null : (value) => setState(() => _assignee = value),
            ),
            const SizedBox(height: Space.md),
          ] else if (managers.length == 1) ...[
            // One manager: naming them is information, a dropdown with one entry is furniture.
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Who it is for'),
              child: Text(managers.first.fullName, style: t.textTheme.bodyLarge),
            ),
            const SizedBox(height: Space.md),
          ],
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Due (optional)'),
            child: InkWell(
              onTap: _busy ? null : _pickDue,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xxs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _due == null
                            ? 'No date'
                            : DateFormat('d MMM yyyy').format(_due!),
                        style: t.textTheme.bodyLarge,
                      ),
                    ),
                    if (_due != null)
                      IconButton(
                        tooltip: 'Clear the date',
                        icon: const Icon(Icons.close_rounded, size: IconSize.md),
                        onPressed: _busy ? null : () => setState(() => _due = null),
                      ),
                    Icon(Icons.calendar_today_rounded,
                        size: IconSize.sm, color: t.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: Space.sm),
            Semantics(
              liveRegion: true,
              child: Text(error,
                  style: t.textTheme.bodyMedium?.copyWith(color: context.tones.error)),
            ),
          ],
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: _busy ? null : () => _submit(managers),
            child: _busy
                ? SizedBox.square(
                    dimension: IconSize.md,
                    child: CircularProgressIndicator(
                        strokeWidth: Strokes.glyph, color: t.colorScheme.onPrimary),
                  )
                : const Text('Assign it'),
          ),
          const SizedBox(height: Space.xs),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
