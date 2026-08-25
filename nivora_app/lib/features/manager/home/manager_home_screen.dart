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

    // The WHOLE AsyncValue, not `.value`. A failed hostels read and an active hostel both
    // produce a null Hostel, and this screen's safety banner hangs off that difference.
    final hostel = ref.watch(hostelProvider(hostelId));
    final load = ref.watch(taskLoadProvider(hostelId));
    final finance = ref.watch(managerFinanceProvider(hostelId));
    final firstName = (session?.fullName ?? '').split(' ').first;

    return ManagerScreen(
      title: firstName.isEmpty ? 'Today' : 'Hello, $firstName',
      subtitle: hostel.value?.name,
      actions: const [_SignOutButton()],
      child: RefreshIndicator(
        onRefresh: () async {
          // The hostel row is refreshed here too. Before, pull-to-refresh could not clear a
          // failed status read, so the one retry gesture on the screen could not reach the
          // one message on it that is about safety.
          ref.invalidate(hostelProvider(hostelId));
          ref.invalidate(taskLoadProvider(hostelId));
          ref.invalidate(managerFinanceProvider(hostelId));
          ref.invalidate(tasksProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _HostelStatus(hostelId: hostelId, hostel: hostel),

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
///
/// BOTH TILES GO THROUGH [AsyncStat] RATHER THAN READING `.value`. `load.value` is null while
/// the two HEAD requests are in flight, null when they failed, and null when RLS refused them
/// — three facts, one dash, and a dash in a figure slot is read as a zero. "Nothing is late"
/// and "we never got an answer" are opposite instructions to the person holding the phone.
///
/// The old code also chose the tile's TONE from that same null: while counting, the caption
/// read "None late" in success green. It was reassurance the server had not given.
class _Attention extends ConsumerWidget {
  const _Attention({required this.hostelId, required this.load, required this.finance});

  final String hostelId;
  final AsyncValue<TaskLoad> load;
  final AsyncValue<FinanceWindow> finance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      // start, NOT stretch: this Row sits in a ListView, so its height is unbounded and
      // stretch asks a child to be infinitely tall. The two tiles no longer have to be the
      // same height anyway — a failed tile is deliberately not shaped like a figure.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AsyncStat<TaskLoad>(
            value: load,
            // Emphasised — the one glass tile on the screen, on the figure the screen is about.
            emphasised: true,
            label: 'Jobs open',
            icon: Icons.checklist_rounded,
            loadingCaption: 'Counting',
            onTap: () => ref.read(managerTabProvider.notifier).go(2),
            onRetry: () => ref.invalidate(taskLoadProvider(hostelId)),
            figure: (tasks) => StatFigure(
              value: '${tasks.open}',
              caption: tasks.overdue > 0 ? '${tasks.overdue} past their date' : 'None late',
              tone: tasks.overdue > 0 ? NivoraColors.error : NivoraColors.success,
            ),
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: AsyncStat<FinanceWindow>(
            value: finance,
            label: 'Spent today',
            icon: Icons.trending_down_rounded,
            loadingCaption: 'Adding up',
            onTap: () => ref.read(managerTabProvider.notifier).go(1),
            onRetry: () => ref.invalidate(managerFinanceProvider(hostelId)),
            figure: (window) {
              final today = window.todayOut;
              // rpc_daily_finance zero-fills every day in the range, so a hostel that spent
              // nothing today comes back as 0 and is drawn as ₹0 — a real figure. A NULL here
              // means the reply did not contain today at all, which is a fourth thing again:
              // the read worked, and it still has nothing to say about today. It gets its own
              // words and the neutral accent, so it cannot be mistaken for a spend of zero.
              if (today == null) {
                return const StatFigure(value: '—', caption: 'No figure for today');
              }
              return StatFigure(
                value: money(today),
                caption: 'Booked against today',
                tone: NivoraColors.warning,
              );
            },
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

/// Whether this hostel can be written to — INCLUDING WHEN WE DO NOT KNOW.
///
/// THE MOST IMPORTANT WIDGET ON THIS SCREEN, and it used to be the quietest. It was written as
/// `if (hostel != null && hostel.status != active)` over `hostelProvider(id).value`. That null
/// is three different facts: the read is still in flight, the read FAILED, or the row came
/// back empty because RLS hid it. All three drew nothing at all — an ordinary screen, on a
/// suspended or lapsed hostel, with the manager finding out only when a save was refused an
/// hour later. A safety message that fails silently is worse than no safety message, because
/// its absence is read as an all-clear.
///
/// So the read's own outcome is now on the screen. Four faces, and only one of them is blank:
///   · loaded, active            — nothing. The all-clear, and the only honest way to earn it.
///   · loaded, suspended/lapsed  — the warning, in the same words as before.
///   · loaded, no row            — plain, unalarming: the row is not visible to this account.
///   · failed                    — says the check itself did not happen, and offers the retry.
///   · still loading             — says it is checking, so the blank is not mistaken for a pass.
///
/// hostels.status is kept in step with the subscription by app.subscription_state and the
/// nightly sweep, so the loaded case repeats the same flag every write is checked against.
/// This widget decides nothing; the refusal is the server's (app.hostel_writable, 42501).
class _HostelStatus extends ConsumerWidget {
  const _HostelStatus({required this.hostelId, required this.hostel});

  final String hostelId;
  final AsyncValue<Hostel?> hostel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strip = _strip(ref);
    if (strip == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: strip);
  }

  /// hasValue before hasError, as AsyncSection does it: a refresh that fails must not replace a
  /// status we already know with "could not check".
  Widget? _strip(WidgetRef ref) {
    if (hostel.hasValue) {
      final row = hostel.requireValue;
      if (row == null) {
        // The select returned nothing. Not "no hostels exist" — this manager's own row was not
        // handed back, which is either an assignment that has been removed or a policy that no
        // longer matches. Plain wording, no alarm colour: there is nothing here for the manager
        // to fix, and it must still never be silent.
        return const NoticeStrip(
          icon: Icons.help_outline_rounded,
          tone: NivoraColors.info,
          title: 'This hostel is not visible to your account',
          detail: 'Its details did not come back, so this screen cannot tell you whether new '
              'entries will be accepted. Ask the owner to check your assignment.',
        );
      }
      if (row.status == HostelStatus.active) return null;
      return NoticeStrip(
        icon: Icons.lock_clock_rounded,
        tone: NivoraColors.warning,
        title: 'This hostel is read-only',
        detail: row.status == HostelStatus.suspended
            ? 'The hostel is suspended. Expenses, menu changes and task updates will be '
                'refused until the owner sorts it out.'
            : 'The subscription has lapsed. You can still read everything; new entries will '
                'be refused until the owner renews.',
      );
    }

    if (hostel.hasError) {
      final failure = AppFailure.from(hostel.error!);
      return NoticeStrip(
        icon: Icons.error_outline_rounded,
        tone: NivoraColors.error,
        title: 'Could not check whether this hostel is read-only',
        detail: '${failure.message} Until it loads, treat a refused save as possible — the '
            'hostel may be suspended or its subscription may have lapsed.',
        action: failure.isRetryable ? () => ref.invalidate(hostelProvider(hostelId)) : null,
      );
    }

    return const NoticeStrip(
      busy: true,
      icon: Icons.lock_clock_rounded,
      tone: NivoraColors.info,
      title: 'Checking this hostel',
      detail: 'Confirming that new entries will be accepted.',
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
