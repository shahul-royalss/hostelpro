library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/finance/expense_stats_screen.dart';
import '../../../shared/motion/settle.dart';
import '../../auth/verify_email_screen.dart';
import '../../common/refresh.dart';
import '../../common/staff_hostel_switcher.dart';
import '../../shell/staff_profile_sheet.dart';
import '../../warden/notices/warden_notices_screen.dart';
import '../../../core/auth/session.dart' show UserRole;
import '../../../shared/person_avatar.dart';
import '../data/manager_models.dart';
import '../data/manager_providers.dart';
import '../expenses/record_money_sheet.dart';
import '../tasks/task_sheet.dart';
import '../widgets/in_out_bars.dart';
import '../widgets/manager_ui.dart';

/// What needs attention today.
///
/// NOT A SMALL OWNER'S DASHBOARD. A manager runs one hostel's day: the jobs waiting, the money
/// that left the building this month, and what is being cooked. There is no occupancy figure,
/// no fee collection rate, no resident count and no second hostel — not because the screen
/// chose restraint, but because RLS gives this role no access to any of it, and a tile reading
/// "0 residents" would be a fabricated number rather than a missing one.
///
/// EVERY FIGURE HERE IS COUNTED OR SUMMED BY POSTGRES:
///   · open and overdue jobs — `count(*)` over public.tasks, two HEAD requests (TaskLoad)
///   · money in / out / today  — public.rpc_daily_finance, a zero-filled row per day
///   · the trend                — the same call, sliced (FinanceWindow)
/// Nothing is derived from a loaded page, sampled or estimated. In particular the task counts
/// are NOT `page.items.length`, which would read "20" for a manager with sixty jobs waiting.
///
/// ── THE SHAPE EVERY ROLE'S HOME SHARES ───────────────────────────────────────────────────
///
/// The forest header with the date over the greeting, then the PG, then an overview strip of
/// clay tiles, the quick actions, the jobs nearest their deadline and the month's money. The
/// four reads behind it are the four it always made; the shape is new, the questions are not.
///
/// THE QUICK ACTIONS OPEN SHEETS, NOT TABS. The "Do it now" grid came off on 2026-09-12
/// because every one of its buttons led somewhere the tab bar already goes. These four do not:
/// three open the recording sheets directly — the most common thing a manager does, two taps
/// sooner than the Expenses tab's + — and the fourth opens the month-by-month charts, which no
/// tab carries.
///
/// THE NOTICEBOARD IS STILL NOT HERE, on purpose: a manager's instructions arrive as TASKS,
/// which carry a due date and a status, where the noticeboard was a second inbox with neither.
///
/// THE MONEY CARD IS IN AGAINST OUT, NOT A CATEGORY BREAKDOWN. A share-per-category needs
/// `sum(amount) group by category` over the month, and the only other route to public.expenses
/// from this screen is the paginated list, whose first page is twenty rows. "Groceries 42%"
/// computed from twenty rows of a hostel with four hundred is a number that looks like a
/// measurement and is not one — the same defect as counting open tasks from page zero, which
/// this role's own providers exist to avoid. So the card shows the series Postgres really does
/// return: money in against money out, one pair per day.
class ManagerHomeScreen extends ConsumerWidget {
  const ManagerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(sessionProvider)?.fullName.trim() ?? '';
    final hostelId = ref.watch(currentHostelIdProvider);

    if (hostelId == null) {
      return Column(
        children: [
          _HomeHeader(name: name),
          const Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(Space.md),
              child: EmptyState(
                icon: ClayIcons.navProperty,
                title: 'No hostel on this account',
                body: 'Ask the owner to give you access to a PG. Until then there is nothing to '
                    'show.',
              ),
            ),
          ),
        ],
      );
    }

    // The WHOLE AsyncValue, not `.value`. A failed hostels read and an active hostel both
    // produce a null Hostel, and this screen's safety banner hangs off that difference.
    final hostel = ref.watch(hostelProvider(hostelId));
    final load = ref.watch(taskLoadProvider(hostelId));
    final finance = ref.watch(managerFinanceProvider(hostelId));

    return Column(
      children: [
        // A fixed object the page passes under, not the first row of the scroll view: a
        // greeting that scrolls off the forest lands in the theme's ink on whatever is under it.
        _HomeHeader(name: name, hostelId: hostelId),
        Expanded(
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
              // So a PG the owner has just given this manager access to brings the Switch PG
              // control with it on a pull, rather than only after the next sign-in.
              ref.invalidate(myStaffHostelsProvider);
              return settleRefresh(
                  context, () => ref.read(managerFinanceProvider(hostelId).future));
            },
            // NO HORIZONTAL PADDING ON THE LIST: the overview strip bleeds to the screen edge and
            // brings the gutter as its own padding, so every other section is held off the edge
            // by [_Gutter].
            child: ListView(
              padding: const EdgeInsets.only(top: Space.lg, bottom: Space.huge),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // First, and above the PG: an unproved address is this manager's own, and the
                // one thing on the screen about the ACCOUNT rather than the building.
                const _Gutter(child: VerifyEmailBanner()),
                // Which PG every figure below belongs to, and the Switch PG control for a
                // manager with two or more. The header carries the greeting and not the property.
                _Gutter(child: StaffHostelBar(hostelId: hostelId)),
                _HostelStatus(hostelId: hostelId, hostel: hostel),
                const _Gutter(top: Space.xl, child: SectionHeader(title: 'Overview')),
                const SizedBox(height: Space.sm),
                _Overview(hostelId: hostelId, load: load, finance: finance),
                _Gutter(
                  top: Space.xl,
                  child: _QuickActions(hostelId: hostelId, hostelName: hostel.value?.name),
                ),
                _Gutter(top: Space.xl, child: _TodaysTasks(hostelId: hostelId)),
                _Gutter(top: Space.xl, child: _MoneySection(hostelId: hostelId, finance: finance)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The forest header: today's date over the greeting, and the account at the leading edge.
///
/// The PG is NOT the title here: it is named, with its Switch PG control, by [StaffHostelBar]
/// directly beneath — which also does the work of noticing when the PG moved on another device
/// — and saying it twice a thumb apart would be the header and the card arguing about whose
/// fact it is.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.name, this.hostelId});

  final String name;
  final String? hostelId;

  /// "Saturday, 24 October". The day is what a manager's morning is organised around.
  static final _today = DateFormat('EEEE, d MMMM');

  @override
  Widget build(BuildContext context) {
    // First name only: a full name read aloud is a database row, not a greeting.
    final first = name.split(RegExp(r'\s+')).first;
    return AppHeader(
      greeting: _today.format(DateTime.now()),
      title: first.isEmpty ? 'Today' : 'Hello, $first',
      // Profile, "Change photo", two-factor, Switch PG, change password and sign out.
      leading: MyHeaderAvatar(onTap: () => showStaffProfile(context)),
      actions: [
        if (hostelId != null)
          // No badge: nothing records which notices this manager has read.
          HeaderIconButton(
            icon: Icons.notifications_none_rounded,
            label: 'Notices',
            onPressed: () => Navigator.of(context)
                .push(WardenNoticesScreen.route(hostelId!, viewerRole: UserRole.manager)),
          ),
      ],
    );
  }
}

/// A section of the page, held off the screen edge.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.child, this.top = 0});
  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(Space.md, top, Space.md, 0),
        child: child,
      );
}

/// The overview strip: the month's spending on the forest tile, then the job load, today's
/// spending and the money booked in.
///
/// THE FOREST TILE IS THE MONTH'S SPENDING, the figure a manager is asked about first. The job
/// tile is beside it, where the eye lands next, and it is the one tile allowed a colour: "2 past
/// their date" as a red chip, "None late" as a green one. Each tile opens what it counts.
///
/// ── THREE TILES, ONE READ, AND THEREFORE ONE FAILURE ─────────────────────────────────────
///
/// The three money tiles all come out of `managerFinanceProvider`. That is one request, so it
/// has one outcome, and printing "Cannot reach Apnivaas" three times across a strip would say
/// three times over what happened once. When the finance read fails or is still in flight, the
/// money tiles collapse to a SINGLE tile in their place — the failure's own sentence, with a
/// retry only where retrying could work. The job tile is a different read and keeps its own
/// face throughout, which is the whole point of four states looking different.
///
/// BOTH HALVES GO THROUGH [AsyncStat] RATHER THAN READING `.value`. `load.value` is null while
/// the two HEAD requests are in flight, null when they failed, and null when RLS refused them
/// — three facts, one dash, and a dash in a figure slot is read as a zero. "Nothing is late"
/// and "we never got an answer" are opposite instructions to the person holding the phone.
///
/// THE COLD FIRST PAINT IS A SKELETON. Before either read has answered there is nothing for any
/// tile to say, so the strip draws its own outline; from the first answer on, each tile wears
/// the face its own read has earned.
///
/// NO CAPTION CLAIMS MORE THAN THE DATA. "94% of budget spent" needs a budget, and there is no
/// budget column anywhere in db/schema.sql. "↑ 14% vs last month" needs last month, which this
/// screen does not fetch. Each tile carries a caption it can actually stand behind, or none.
class _Overview extends ConsumerWidget {
  const _Overview({required this.hostelId, required this.load, required this.finance});

  final String hostelId;
  final AsyncValue<TaskLoad> load;
  final AsyncValue<FinanceWindow> finance;

  static bool _waiting(AsyncValue<Object?> v) => !v.hasValue && !v.hasError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_waiting(load) && _waiting(finance)) {
      return const Settle(
        state: 'loading',
        child: StatCarouselSkeleton(semanticLabel: 'Loading the overview'),
      );
    }

    void openLedger() => ref.read(managerTabProvider.notifier).go(1);

    final jobs = AsyncStat<TaskLoad>(
      value: load,
      icon: ClayIcons.tasks,
      label: 'Jobs open',
      loadingCaption: 'Counting',
      onTap: () => ref.read(managerTabProvider.notifier).go(2),
      onRetry: () => ref.invalidate(taskLoadProvider(hostelId)),
      figure: (tasks) => StatFigure(
        value: '${tasks.open}',
        caption: tasks.overdue > 0 ? '${tasks.overdue} past their date' : 'None late',
        tone: tasks.overdue > 0 ? ApnivaasColors.error : ApnivaasColors.success,
      ),
    );

    if (!finance.hasValue) {
      // One tile for one read, beside the job tile.
      final money = finance.hasError
          ? FailedStat(
              label: 'Money',
              icon: ClayIcons.expense,
              error: finance.error!,
              onRetry: () => ref.invalidate(managerFinanceProvider(hostelId)),
            )
          : const StatCard(
              label: 'Money', value: '—', caption: 'Adding up', icon: ClayIcons.expense);
      return Settle(state: 'partial', child: StatCarousel(children: [money, jobs]));
    }

    final window = finance.requireValue;
    final today = window.todayOut;

    return Settle(
      state: 'data',
      child: StatCarousel(
        children: [
          StatCard(
            hero: true,
            icon: ClayIcons.expense,
            label: 'Spent this month',
            value: money(window.monthOut),
            caption: monthTitle(window.monthStart),
            onTap: openLedger,
          ),
          jobs,
          StatCard(
            icon: ClayIcons.receipt,
            label: 'Spent today',
            // rpc_daily_finance zero-fills every day in the range, so a hostel that spent
            // nothing today comes back as 0 and is drawn as ₹0 — a real figure. A NULL here
            // means the reply did not contain today at all, which is a different thing again:
            // the read worked, and it still has nothing to say about today. It gets its own
            // words, so it cannot be mistaken for a spend of zero.
            value: today == null ? '—' : money(today),
            caption: today == null ? 'No figure for today' : 'Booked against today',
            onTap: openLedger,
          ),
          StatCard(
            icon: ClayIcons.money,
            label: 'Recorded in',
            value: money(window.monthIn),
            // public.fee_payments is unreadable to this role, so the difference between money
            // in and money out is NOT the hostel's profit. This tile is where that is said.
            caption: 'Mess and deposits, not rent',
            onTap: openLedger,
          ),
        ],
      ),
    );
  }
}

/// The things a manager does most, one tap from the home screen.
///
/// Three recording sheets — the same ones the Expenses tab's + opens, with the same checks and
/// the same write — and the month-by-month charts the owner reads from More. See the class note
/// on [ManagerHomeScreen] for why these four and not the tabs again.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.hostelId, required this.hostelName});

  final String hostelId;
  final String? hostelName;

  // SHORT WORDS ON PURPOSE. A tile is about 75dp wide on a 360dp phone, and at the 1.4x text the
  // app allows, "Day-to-day" or "Month by month" no longer fit a line and end in an ellipsis.
  // Every word here fits at that size; the spoken label is the full sentence.
  @override
  Widget build(BuildContext context) {
    return QuickActionGrid(
      actions: [
        QuickActionTile(
          icon: ClayIcons.expense,
          label: 'Add expense',
          semanticLabel: 'Record a day-to-day expense',
          onTap: () => showRecordExpenseSheet(context, hostelId: hostelId),
        ),
        QuickActionTile(
          icon: ClayIcons.invoice,
          label: 'Monthly bill',
          semanticLabel: 'Record a monthly expense',
          onTap: () =>
              showRecordExpenseSheet(context, hostelId: hostelId, kind: ExpenseKind.monthly),
        ),
        QuickActionTile(
          icon: ClayIcons.money,
          label: 'Record money in',
          onTap: () => showRecordRevenueSheet(context, hostelId: hostelId),
        ),
        QuickActionTile(
          icon: ClayIcons.analytics,
          label: 'Expense charts',
          semanticLabel: 'Expenses month by month',
          onTap: () => Navigator.of(context)
              .push(ExpenseStatsScreen.route(hostelId, hostelName: hostelName)),
        ),
      ],
    );
  }
}

/// "Today's tasks" — the three jobs nearest their deadline, then the way to the rest.
///
/// SAME QUERY AS THE TASKS TAB. TaskQuery has value equality and this key — open only, no
/// status — is the one the tab's default filter builds, so opening Tasks reuses this fetch
/// rather than making a second one, and the two screens cannot show a different order. The
/// repository orders by due_date ascending with undated tasks LAST, which is why taking the
/// first three is "nearest the deadline" and not "whichever arrived first".
///
/// The heading's "View all" opens the tab, which carries the filters and the finished jobs —
/// neither of which is here at any length — so it is there whether or not this list is
/// truncating one.
class _TodaysTasks extends ConsumerWidget {
  const _TodaysTasks({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = TaskQuery(hostelId: hostelId, openOnly: true);
    final page = ref.watch(tasksProvider(query));

    return Section(
      label: "Today's tasks",
      actionLabel: 'View all',
      onAction: () => ref.read(managerTabProvider.notifier).go(2),
      child: AsyncSection<PagedResult<Task>>(
        value: page,
        onRetry: () => ref.invalidate(tasksProvider(query)),
        loading: const ListSkeleton(semanticLabel: 'Loading tasks'),
        builder: (result) {
          if (result.isEmpty) {
            // The trophy, because an empty to-do list is the good news on this screen — and
            // only here and on the Tasks tab's own "To do" filter does an empty list earn it.
            return const SectionCard(
              padding: EdgeInsets.zero,
              child: EmptyState(
                compact: true,
                icon: ClayIcons.success,
                title: 'Nothing waiting on you',
                body: 'New jobs arrive here when the owner assigns one.',
              ),
            );
          }
          final shown = result.items.take(3).toList(growable: false);
          return ListGroup(
            children: [
              for (final task in shown)
                TaskLine(
                  task: task,
                  grouped: true,
                  onTap: () => showTaskSheet(context, task: task),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The month's money: the difference between what came in and what went out, over the daily
/// bars it is the sum of — the only aggregate this role can actually read beyond the tiles.
///
/// The difference is never called profit: rent is collected into public.fee_payments by the
/// warden, which this role cannot read, so "in minus out" here is the hand-kept ledgers' balance
/// and nothing more. It turns red only when the month is under water, which is a state; a
/// positive difference stays in the ink, because it is not a claim of anything.
///
/// THE MOCKUP'S BUDGET METER IS NOT DRAWN: there is no budget column to be the denominator,
/// and the percentage would have to be invented.
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
        loading: const _MoneySkeleton(),
        builder: (window) {
          final net = window.monthNet;
          return SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, box) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Difference this month',
                                style: t.textTheme.titleSmall?.copyWith(fontFeatures: const []),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: Space.hair),
                            Text(
                              monthTitle(window.monthStart),
                              style: t.textTheme.bodySmall
                                  ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      // CAPPED AND SCALED, NEVER CUT. A hostel that books in lakhs plus a phone
                      // at 1.6x text is ₹12,34,567 at 35px, wider than a 320dp card has left
                      // beside its label. The figure takes up to three fifths of the row and
                      // shrinks inside that rather than ellipsising — `₹12,34…` is a different
                      // number — and the label gives way first.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            money(net),
                            // Tabular, so a refreshing figure does not shuffle sideways.
                            style: t.textTheme.headlineMedium?.copyWith(
                              color: net < 0 ? context.tones.error : t.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.md),
                InOutBars(window: window),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The money card's outline: the heading line, the figure, and the plot.
class _MoneySkeleton extends StatelessWidget {
  const _MoneySkeleton();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SkeletonPulse(
      semanticLabel: 'Loading the money in and out',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: Radii.rSurface,
          border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
        ),
        child: const Padding(
          padding: EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(widthFactor: 0.5),
              SizedBox(height: Space.xs),
              Skeleton(widthFactor: 0.3),
              SizedBox(height: Space.lg),
              Skeleton(height: Space.huge * 2, radius: Radii.rControl),
            ],
          ),
        ),
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
/// So the read's own outcome is now on the screen. Five faces, and only one of them is blank:
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
    return _Gutter(top: Space.md, child: strip);
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
          tone: ApnivaasColors.info,
          title: 'This hostel is not visible to your account',
          detail: 'Its details did not come back, so this screen cannot tell you whether new '
              'entries will be accepted. Ask the owner to check your assignment.',
        );
      }
      if (row.status == HostelStatus.active) return null;
      return NoticeStrip(
        icon: Icons.lock_clock_rounded,
        tone: ApnivaasColors.warning,
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
        tone: ApnivaasColors.error,
        title: 'Could not check whether this hostel is read-only',
        detail: '${failure.message} Until it loads, treat a refused save as possible — the '
            'hostel may be suspended or its subscription may have lapsed.',
        action: failure.isRetryable ? () => ref.invalidate(hostelProvider(hostelId)) : null,
      );
    }

    return const NoticeStrip(
      busy: true,
      icon: Icons.lock_clock_rounded,
      tone: ApnivaasColors.info,
      title: 'Checking this hostel',
      detail: 'Confirming that new entries will be accepted.',
    );
  }
}
