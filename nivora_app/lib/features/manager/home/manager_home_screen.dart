library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../data/manager_models.dart';
import '../data/manager_providers.dart';
import '../expenses/record_money_sheet.dart';
import '../tasks/task_sheet.dart';
import '../widgets/in_out_bars.dart';
import '../widgets/manager_ui.dart';

/// What needs attention today.
///
/// NOT A DASHBOARD, AND NOT A SMALL OWNER'S DASHBOARD. A manager runs one hostel's day: the
/// jobs waiting, the money that left the building this month, and what is being cooked. There
/// is no occupancy figure, no fee collection rate, no resident count and no second hostel —
/// not because the screen chose restraint, but because RLS gives this role no access to any of
/// it, and a tile reading "0 residents" would be a fabricated number rather than a missing one.
///
/// EVERY FIGURE HERE IS COUNTED OR SUMMED BY POSTGRES:
///   · open and overdue jobs — `count(*)` over public.tasks, two HEAD requests (TaskLoad)
///   · money in / out / today  — public.rpc_daily_finance, a zero-filled row per day
///   · the trend                — the same call, sliced (FinanceWindow)
/// Nothing is derived from a loaded page, sampled or estimated. In particular the task counts
/// are NOT `page.items.length`, which would read "20" for a manager with sixty jobs waiting.
class ManagerHomeScreen extends ConsumerWidget {
  const ManagerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final hostelId = ref.watch(currentHostelIdProvider);

    if (hostelId == null) {
      return const ManagerScreen(
        title: 'Today',
        actions: [_SignOutButton()],
        child: EmptyNote(
          icon: Icons.home_work_outlined,
          title: 'No hostel on this account',
          detail: 'A manager is attached to exactly one hostel. Ask the owner to check the '
              'assignment — until then there is nothing to show.',
        ),
      );
    }

    final hostel = ref.watch(hostelProvider(hostelId)).value;
    final load = ref.watch(taskLoadProvider(hostelId));
    final finance = ref.watch(managerFinanceProvider(hostelId));
    final firstName = (session?.fullName ?? '').split(' ').first;

    return ManagerScreen(
      title: firstName.isEmpty ? 'Today' : 'Hello, $firstName',
      subtitle: hostel?.name,
      actions: const [_SignOutButton()],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(taskLoadProvider(hostelId));
          ref.invalidate(managerFinanceProvider(hostelId));
          ref.invalidate(tasksProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // hostels.status is kept in step with the subscription by app.subscription_state
            // and the nightly sweep, so this is the same flag every write is checked against.
            // Saying it here means the manager hears it before a save is refused, not after.
            if (hostel != null && hostel.status != HostelStatus.active)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: _ReadOnlyBanner(status: hostel.status),
              ),

            _Attention(hostelId: hostelId, load: load, finance: finance),

            const SectionLabel(label: 'Money this month'),
            _Month(hostelId: hostelId, finance: finance),

            const SectionLabel(label: 'Do it now'),
            _QuickActions(hostelId: hostelId),

            const SectionLabel(label: 'Next up'),
            _NextUp(hostelId: hostelId),
          ],
        ),
      ),
    );
  }
}

/// The two counts and today's spend, side by side.
class _Attention extends ConsumerWidget {
  const _Attention({required this.hostelId, required this.load, required this.finance});

  final String hostelId;
  final AsyncValue<TaskLoad> load;
  final AsyncValue<FinanceWindow> finance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = load.value;
    final today = finance.value?.todayOut;

    return Row(
      children: [
        Expanded(
          child: GlassStatCard(
            // Emphasised — the one glass tile on the screen, on the figure the screen is about.
            emphasised: true,
            label: 'Jobs open',
            value: tasks == null ? '—' : '${tasks.open}',
            caption: tasks == null
                ? 'Counting'
                : tasks.overdue > 0
                    ? '${tasks.overdue} past their date'
                    : 'None late',
            icon: Icons.checklist_rounded,
            tone: tasks != null && tasks.overdue > 0
                ? NivoraColors.error
                : NivoraColors.success,
            onTap: () => ref.read(managerTabProvider.notifier).go(2),
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: GlassStatCard(
            label: 'Spent today',
            // A dash, never a zero, while the figure is still in flight or missing. Zero is a
            // claim; a dash is the truth about what is known so far.
            value: today == null ? '—' : money(today),
            caption: 'Booked against today',
            icon: Icons.trending_down_rounded,
            tone: NivoraColors.warning,
            onTap: () => ref.read(managerTabProvider.notifier).go(1),
          ),
        ),
      ],
    );
  }
}

/// Month-to-date in, out, the difference, and the short trend under it.
class _Month extends ConsumerWidget {
  const _Month({required this.hostelId, required this.finance});

  final String hostelId;
  final AsyncValue<FinanceWindow> finance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);

    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: AsyncSection<FinanceWindow>(
        value: finance,
        onRetry: () => ref.invalidate(managerFinanceProvider(hostelId)),
        builder: (window) {
          final net = window.monthNet;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Figure(
                      label: 'Recorded in',
                      value: money(window.monthIn),
                      tone: context.tones.success,
                    ),
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'Spent',
                      value: money(window.monthOut),
                      tone: context.tones.warning,
                    ),
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'Difference',
                      value: money(net),
                      tone: net < 0 ? context.tones.error : t.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.xxs),
              // Said every time, because the number invites exactly one wrong reading. Rent
              // lives in public.fee_payments; a manager cannot read that table, this figure
              // does not contain it, and calling the difference "profit" would be a lie.
              Text(
                '${monthTitle(window.monthStart)} so far. Rent is collected separately by the '
                'warden and is not counted here.',
                style: t.textTheme.bodySmall,
              ),
              const SizedBox(height: Space.md),
              InOutBars(window: window),
            ],
          );
        },
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.tone});
  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: t.textTheme.labelSmall),
        const SizedBox(height: Space.xxs),
        Text(
          value,
          // headlineSmall is tabular — a refreshing row of figures must not shuffle sideways.
          style: t.textTheme.headlineSmall?.copyWith(color: tone),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: QuickAction(
                icon: Icons.remove_circle_outline_rounded,
                label: 'Record expense',
                tone: NivoraColors.warning,
                onTap: () => showRecordExpenseSheet(context, hostelId: hostelId),
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: QuickAction(
                icon: Icons.add_circle_outline_rounded,
                label: 'Record money in',
                tone: NivoraColors.success,
                onTap: () => showRecordRevenueSheet(context, hostelId: hostelId),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            Expanded(
              child: QuickAction(
                icon: Icons.restaurant_rounded,
                label: "Today's menu",
                onTap: () {
                  ref.read(menuDayProvider.notifier).set(MenuDay.of(DateTime.now()));
                  ref.read(managerTabProvider.notifier).go(3);
                },
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: QuickAction(
                icon: Icons.checklist_rounded,
                label: 'Work through jobs',
                onTap: () {
                  ref.read(taskFilterProvider.notifier).set(TaskFilter.needsAction);
                  ref.read(managerTabProvider.notifier).go(2);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The three jobs nearest their deadline.
///
/// SAME QUERY AS THE TASKS TAB. TaskQuery has value equality and this key — open only, no
/// status — is the one the tab's default filter builds, so opening Tasks reuses this fetch
/// rather than making a second one, and the two screens cannot show a different order. The
/// repository orders by due_date ascending with undated tasks LAST, which is why taking the
/// first three is "nearest the deadline" and not "whichever arrived first".
class _NextUp extends ConsumerWidget {
  const _NextUp({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = TaskQuery(hostelId: hostelId, openOnly: true);
    final page = ref.watch(tasksProvider(query));

    return AsyncSection<PagedResult<Task>>(
      value: page,
      onRetry: () => ref.invalidate(tasksProvider(query)),
      builder: (result) {
        if (result.isEmpty) {
          return const EmptyNote(
            icon: Icons.check_circle_outline_rounded,
            title: 'Nothing waiting on you',
            detail: 'New jobs arrive here when the owner assigns one.',
          );
        }
        final shown = result.items.take(3).toList(growable: false);
        return Column(
          children: [
            for (final task in shown) ...[
              _NextUpRow(task: task),
              const SizedBox(height: Space.xs),
            ],
            if (result.items.length > shown.length || result.hasMore)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => ref.read(managerTabProvider.notifier).go(2),
                  child: const Text('See all jobs'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NextUpRow extends StatelessWidget {
  const _NextUpRow({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final due = task.dueDate;
    return TapRow(
      onTap: () => showTaskSheet(context, task: task),
      semanticLabel: '${task.title}. ${due == null ? 'No deadline' : dueLabel(due)}',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title,
                    style: t.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.xxs),
                Row(
                  children: [
                    Pill(status: task.status),
                    if (due != null) ...[
                      const SizedBox(width: Space.xs),
                      task.isOverdue
                          ? Pill.text(label: dueLabel(due), tone: NivoraColors.error)
                          : Flexible(
                              child: Text(dueLabel(due),
                                  style: t.textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: IconSize.md, color: t.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Says the hostel is read-only BEFORE a save is refused rather than after.
///
/// The refusal itself is the server's: every insert policy goes through app.hostel_writable,
/// and an expired subscription raises 42501 with a sentence written for the user. This banner
/// does not decide anything — it repeats a status the manager can already read, early enough
/// to be useful.
class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.status});
  final HostelStatus status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = context.tones.warning;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: context.tones.chipFill(NivoraColors.warning),
        border: Border.all(color: context.tones.chipBorder(NivoraColors.warning)),
        borderRadius: Radii.rCard,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_rounded, size: IconSize.md, color: tone),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This hostel is read-only',
                    style: t.textTheme.titleSmall?.copyWith(color: tone)),
                const SizedBox(height: Space.xxs),
                Text(
                  status == HostelStatus.suspended
                      ? 'The hostel is suspended. Expenses, menu changes and task updates will '
                          'be refused until the owner sorts it out.'
                      : 'The subscription has lapsed. You can still read everything; new '
                          'entries will be refused until the owner renews.',
                  style: t.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        tooltip: 'Sign out',
        icon: const Icon(Icons.logout_rounded),
        onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
      );
}
