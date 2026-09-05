library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/session.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/dashboard.dart';
import '../../../shared/glass/glass.dart';
import '../../common/refresh.dart';
import '../../common/staff_notices.dart';
import '../notices/manager_notices_screen.dart';
import '../data/manager_models.dart';
import '../../auth/verify_email_screen.dart';
import '../data/manager_providers.dart';
import '../expenses/record_money_sheet.dart';
import '../tasks/task_sheet.dart';
import '../widgets/in_out_bars.dart';
import '../widgets/manager_ui.dart';

/// What needs attention today. Figma `4:1159`, `screen-manager-dashboard`.
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
///
/// ── THE FRAME'S RHYTHM, AND THE ONE THING ON IT THAT COULD NOT BE BUILT ───────────────────
///
/// 4:1159 is three blocks: a 2x2 KPI grid, `TODAY'S TASKS` over boxed rows, and
/// `CATEGORIZED EXPENSES` over a stacked bar with a percentage legend. The first two are here,
/// in that order and in that dress.
///
/// THE THIRD IS NOT, and it is the one thing on either of this role's frames that the database
/// cannot answer. A share-per-category needs `sum(amount) group by category`, and nothing in
/// db/schema.sql produces one: `rpc_daily_finance` returns a revenue and an expense TOTAL per
/// day and no breakdown, and the only other route to public.expenses is the paginated list,
/// whose first page is twenty rows. "Groceries 42%" computed from twenty rows of a hostel with
/// four hundred is a number that looks like a measurement and is not one — the same defect as
/// counting open tasks from page zero, which this role's own providers exist to avoid. So the
/// slot keeps the design's shape (eyebrow, bar, legend) and is filled with the series Postgres
/// really does return: money in against money out, one pair per day, zero-filled by
/// generate_series so a flat stretch is a quiet week and not a gap.
class ManagerHomeScreen extends ConsumerWidget {
  const ManagerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final hostelId = ref.watch(currentHostelIdProvider);

    if (hostelId == null) {
      return const ManagerScreen(
        title: 'Today',
        masthead: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Space.md),
          child: EmptyNote(
            icon: Icons.home_work_outlined,
            title: 'No hostel on this account',
            detail: 'A manager is attached to exactly one hostel. Ask the owner to check the '
                'assignment — until then there is nothing to show.',
          ),
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
      masthead: true,
      child: RefreshIndicator(
        // The hostel row is refreshed here too. Before, pull-to-refresh could not clear a
        // failed status read, so the one retry gesture on the screen could not reach the one
        // message on it that is about safety.
        //
        // The WAIT is on the money, which is what this screen is mostly made of. Bounded and
        // spoken: AsyncSection keeps the figures already drawn through a failed reload, so
        // without this a pull that did not land looked exactly like one that did. See
        // features/common/refresh.dart.
        onRefresh: () {
          ref.invalidate(hostelProvider(hostelId));
          ref.invalidate(taskLoadProvider(hostelId));
          ref.invalidate(managerFinanceProvider(hostelId));
          ref.invalidate(tasksProvider);
          return settleRefresh(
              context, () => ref.read(managerFinanceProvider(hostelId).future));
        },
        // The frame's own body: `p-[16px] gap-[16px]`, groups announced by an uppercase
        // eyebrow rather than wrapped in a titled card. See SectionLabel.
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const VerifyEmailBanner(),
            _HostelStatus(hostelId: hostelId, hostel: hostel),
            // Banded like every other role's home — see shared/dashboard.dart. The tiles below
            // were already tinted, one figure each, so this names the groups rather than
            // rebuilding them.
            const DashboardBand(label: 'Essentials'),
            _KpiGrid(hostelId: hostelId, load: load, finance: finance),
            const SizedBox(height: Space.md),
            const DashboardBand(label: 'Today'),
            _TodaysTasks(hostelId: hostelId),
            const SizedBox(height: Space.md),
            _NoticesSection(hostelId: hostelId),
            const SizedBox(height: Space.md),
            _MoneySection(hostelId: hostelId, finance: finance),
            const SizedBox(height: Space.md),
            const DashboardBand(label: 'Tools'),
            _QuickActions(hostelId: hostelId),
          ],
        ),
      ),
    );
  }
}

/// The 2x2 grid at the top of the frame — 4:1177.
///
/// Four tiles, all the same size, all 16/700: money out today, money out this month, money in
/// this month, and the job load. There is no hero card any more — the design has nothing on
/// this screen at 48px and nothing on a shadowed pane, and the emphasis comes instead from the
/// single tile that is allowed a colour (4:1193, the overdue count in red).
///
/// ── THREE TILES, ONE READ, AND THEREFORE ONE FAILURE ─────────────────────────────────────
///
/// The three money tiles all come out of `managerFinanceProvider`. That is one request, so it
/// has one outcome, and printing "Cannot reach Nivora" three times across a grid would say
/// three times over what happened once. When the finance read fails or is still in flight, the
/// money half of the grid collapses to a SINGLE card in its place — the failure's own sentence,
/// with a retry only where retrying could work. The job tile is a different read and keeps its
/// own face throughout, which is the whole point of four states looking different.
///
/// BOTH HALVES GO THROUGH [AsyncStat] RATHER THAN READING `.value`. `load.value` is null while
/// the two HEAD requests are in flight, null when they failed, and null when RLS refused them
/// — three facts, one dash, and a dash in a figure slot is read as a zero. "Nothing is late"
/// and "we never got an answer" are opposite instructions to the person holding the phone.
///
/// THE MOCKUP'S CAPTIONS ARE NOT COPIED. "94% of budget spent" needs a budget, and there is no
/// budget column anywhere in db/schema.sql — not on public.hostels, not on public.expenses.
/// "↑ 14% vs last month" needs last month, which this screen does not fetch, and a percentage
/// change against a month that booked nothing is a divide by zero. "Utilities, Food stock"
/// needs the per-category breakdown that does not exist. Each tile carries a caption it can
/// actually stand behind, or none.
class _KpiGrid extends ConsumerWidget {
  const _KpiGrid({required this.hostelId, required this.load, required this.finance});

  final String hostelId;
  final AsyncValue<TaskLoad> load;
  final AsyncValue<FinanceWindow> finance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = AsyncStat<TaskLoad>(
      value: load,
      label: 'Jobs open',
      loadingCaption: 'Counting',
      onTap: () => ref.read(managerTabProvider.notifier).go(2),
      onRetry: () => ref.invalidate(taskLoadProvider(hostelId)),
      figure: (tasks) => StatFigure(
        value: '${tasks.open}',
        caption: tasks.overdue > 0 ? '${tasks.overdue} past their date' : 'None late',
        tone: tasks.overdue > 0 ? NivoraColors.error : NivoraColors.success,
      ),
    );

    if (!finance.hasValue) {
      // One card for one read. It sits beside the job tile so the grid keeps its shape.
      final money = finance.hasError
          ? FailedStat(
              label: 'Money',
              error: finance.error!,
              onRetry: () => ref.invalidate(managerFinanceProvider(hostelId)),
            )
          : const StatCard(label: 'Money', value: '—', caption: 'Adding up');
      return _Pair(left: money, right: jobs);
    }

    final window = finance.requireValue;
    final today = window.todayOut;

    return Column(
      children: [
        _Pair(
          left: StatCard(
            label: 'Spent today',
            // rpc_daily_finance zero-fills every day in the range, so a hostel that spent
            // nothing today comes back as 0 and is drawn as ₹0 — a real figure. A NULL here
            // means the reply did not contain today at all, which is a different thing again:
            // the read worked, and it still has nothing to say about today. It gets its own
            // words, so it cannot be mistaken for a spend of zero.
            value: today == null ? '—' : money(today),
            caption: today == null ? 'No figure for today' : 'Booked against today',
            onTap: () => ref.read(managerTabProvider.notifier).go(1),
          ),
          right: StatCard(
            label: 'Spent this month',
            value: money(window.monthOut),
            caption: monthTitle(window.monthStart),
            onTap: () => ref.read(managerTabProvider.notifier).go(1),
          ),
        ),
        const SizedBox(height: Space.xs),
        _Pair(
          left: StatCard(
            label: 'Recorded in',
            value: money(window.monthIn),
            caption: 'Mess and deposits, not rent',
            onTap: () => ref.read(managerTabProvider.notifier).go(1),
          ),
          right: jobs,
        ),
      ],
    );
  }
}

/// Two tiles side by side at the frame's 8dp gutter, each taking half the width.
class _Pair extends StatelessWidget {
  const _Pair({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: Space.xs),
            Expanded(child: right),
          ],
        ),
      );
}

/// `TODAY'S TASKS` — 4:1195. The three jobs nearest their deadline, then the way to the rest.
///
/// SAME QUERY AS THE TASKS TAB. TaskQuery has value equality and this key — open only, no
/// status — is the one the tab's default filter builds, so opening Tasks reuses this fetch
/// rather than making a second one, and the two screens cannot show a different order. The
/// repository orders by due_date ascending with undated tasks LAST, which is why taking the
/// first three is "nearest the deadline" and not "whichever arrived first".
///
/// THREE ROWS AND A FOOTER IS THE DESIGN'S OWN SHAPE — its section holds exactly three. The
/// footer is not the design's (it draws none), and it is shown whenever there is a list to go
/// to rather than only when this section is truncating one: the tab it opens carries the
/// filters and the finished jobs, which are not here at any length.
class _TodaysTasks extends ConsumerWidget {
  const _TodaysTasks({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = TaskQuery(hostelId: hostelId, openOnly: true);
    final page = ref.watch(tasksProvider(query));

    return Section(
      label: "Today's tasks",
      child: AsyncSection<PagedResult<Task>>(
        value: page,
        onRetry: () => ref.invalidate(tasksProvider(query)),
        builder: (result) {
          if (result.isEmpty) {
            return const EmptyNote(
              icon: Icons.check_circle_outline_rounded,
              title: 'Nothing waiting on you',
              detail: 'New jobs arrive here when the owner assigns one.',
              tone: NivoraColors.success,
            );
          }
          final shown = result.items.take(3).toList(growable: false);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final task in shown) ...[
                TaskLine(task: task, onTap: () => showTaskSheet(context, task: task)),
                const SizedBox(height: Space.xs),
              ],
              const SizedBox(height: Space.xxs),
              CapsButton(
                label: 'View all tasks',
                onTap: () => ref.read(managerTabProvider.notifier).go(2),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// What the owner has posted to this hostel.
///
/// ── THIS SECTION IS WHY THE MANAGER NOW HAS A NOTICEBOARD AT ALL ─────────────────────────
///
/// `app.announcements_after_insert` has always written this role a `notifications` row when the
/// owner posts to `all` or to `manager` — with `link` set to `/manager` — and until this
/// section existed there was nothing behind that link. The notification was real and the
/// destination was not.
///
/// TWO ROWS, NOT THE PAGE. The manager's home screen is a list of things that need attention
/// today; the whole noticeboard belongs on its own screen, which [ManagerNoticesScreen] is.
class _NoticesSection extends ConsumerWidget {
  const _NoticesSection({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(noticesProvider(hostelId));

    return Section(
      label: 'Notices',
      child: AsyncSection<PagedResult<Notice>>(
        value: page,
        onRetry: () => ref.invalidate(noticesProvider(hostelId)),
        builder: (result) {
          if (result.isEmpty) {
            // The noticeboard's own blue on the glyph — identity, not a verdict. An empty
            // noticeboard is neither good news nor bad, which is why this is the DOMAIN tone
            // and not the reassuring green a cleared task list earns: the megaphone is blue on
            // every screen it appears on, and here it says "this is the noticeboard, and it is
            // empty" rather than congratulating anybody. See NivoraDomain.
            return EmptyNote(
              icon: Icons.campaign_outlined,
              title: 'No notices yet',
              detail: 'Anything the owner posts to this hostel appears here.',
              // NO TONE: an empty noticeboard is neither good news nor bad, which is the reason
              // the warden's, the owner's and both of the resident's identical empties give.
              // This card was the only one of the five that coloured it, so it was the outlier
              // rather than the example — and EmptyNote's own contract is "pass a tone only
              // where empty genuinely means something".
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaffNoticeList(
                hostelId: hostelId,
                page: result,
                viewerRole: UserRole.manager,
                limit: 2,
                // Embedded in this screen's own ListView: a nested scroll view here would
                // fight the page for the gesture.
                scrollable: false,
              ),
              const SizedBox(height: Space.sm),
              CapsButton(
                label: 'View all notices',
                onTap: () =>
                    Navigator.of(context).push(ManagerNoticesScreen.route(hostelId)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The frame's third block — `CATEGORIZED EXPENSES` (4:1213), filled with the only aggregate
/// this role can actually read.
///
/// The design draws a stacked bar of category shares and a four-dot legend of percentages.
/// There is no query behind that — see the class note on [ManagerHomeScreen]. What is here
/// instead is money IN against money OUT, day by day, straight off `rpc_daily_finance`, with
/// the month's difference stated above it.
///
/// THE MOCKUP'S BUDGET METER IS ALSO NOT DRAWN, for the same reason: there is no budget column
/// to be the denominator, and the percentage would have to be invented.
class _MoneySection extends ConsumerWidget {
  const _MoneySection({required this.hostelId, required this.finance});

  final String hostelId;
  final AsyncValue<FinanceWindow> finance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);

    return Section(
      label: 'Money in and out',
      child: AsyncSection<FinanceWindow>(
        value: finance,
        onRetry: () => ref.invalidate(managerFinanceProvider(hostelId)),
        builder: (window) {
          final net = window.monthNet;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Difference this month',
                        style: t.textTheme.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: Space.xs),
                  // Flexible, not bare: a hostel that books in lakhs plus a phone at 1.6x
                  // text scale is ₹12,34,567 at 26px, which is wider than a 320dp row has
                  // left. The figure wins the space it needs and the label gives way first.
                  Flexible(
                    child: Text(
                      money(net),
                      // headlineSmall is 16/700 tabular — a refreshing figure must not shuffle
                      // sideways. Red only when the month is under water, which is a state; a
                      // positive difference stays cream, because it is not a claim of profit.
                      style: t.textTheme.headlineSmall?.copyWith(
                        color: net < 0 ? context.tones.error : t.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
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
              const SizedBox(height: Space.sm),
              InOutBars(window: window),
            ],
          );
        },
      ),
    );
  }
}

/// The four things this role does most.
///
/// NOT IN THE DESIGN — `screen-manager-dashboard` is a reading screen with no action grid on
/// it at all. These are kept because they are real features (two write sheets and two tabs),
/// and each is drawn as a [DomainButton] IN THE COLOUR OF WHERE IT GOES: the two ledger
/// entries in money's green, the menu in food's saffron, the jobs in the amber of open work.
/// Four shortcuts in four tints say four destinations before a word is read, which a row of
/// identical hairline boxes never could; see [NivoraDomain] for the rule. The screen's one
/// cream [FilledButton] is not here — none of these is the action the dashboard exists for.
///
/// The Stitch mockup's version of this was four expense CATEGORIES — Utilities, Consumables,
/// Repairs, Other — as one-tap shortcuts. Those were never built and still are not: an expense
/// needs an amount and a date before it can be written, so a tile that books one in a single
/// tap would have to invent both.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Section(
      label: 'Do it now',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DomainButton(
                  domain: NivoraDomain.money,
                  icon: Icons.remove_circle_outline_rounded,
                  label: 'Record expense',
                  onPressed: () => showRecordExpenseSheet(context, hostelId: hostelId),
                ),
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: DomainButton(
                  domain: NivoraDomain.money,
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Record money in',
                  onPressed: () => showRecordRevenueSheet(context, hostelId: hostelId),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(
                child: DomainButton(
                  domain: NivoraDomain.food,
                  label: "Today's menu",
                  onPressed: () {
                    ref.read(menuDayProvider.notifier).set(MenuDay.of(DateTime.now()));
                    ref.read(managerTabProvider.notifier).go(3);
                  },
                ),
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: DomainButton(
                  domain: NivoraDomain.complaints,
                  // The role's own jobs glyph — the same one on the Tasks tab — rather than the
                  // domain's warning triangle, which is what a COMPLAINT wears.
                  icon: Icons.checklist_rounded,
                  label: 'Work through jobs',
                  onPressed: () {
                    ref.read(taskFilterProvider.notifier).set(TaskFilter.needsAction);
                    ref.read(managerTabProvider.notifier).go(2);
                  },
                ),
              ),
            ],
          ),
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


