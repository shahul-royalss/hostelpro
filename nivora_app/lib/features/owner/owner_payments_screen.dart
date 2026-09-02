library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import '../../shared/illustrations.dart';
import 'owner_format.dart';
import 'owner_providers.dart';
import 'widgets/states.dart';

/// WHO PAID.
///
/// The dashboard already answers "how much came in this month" — `rpc_hostel_stats` gives the
/// collected figure and the count of residents still owing. It cannot answer the question an
/// owner actually asks on the phone to their warden, which is WHO: which resident, for which
/// month, how much, and which member of staff took it.
///
/// READS: public.rpc_recent_payments(hostel) — one row per resident per month that has received
/// money, most recently touched first, with the resident's name, their room, and the NAME of
/// the staff account that recorded it. That last join is why this is an RPC and not a select:
/// `fee_payments.recorded_by` is a uuid, and the `users` row behind it is not readable to every
/// role that needs the name.
///
/// ── WHAT THIS LIST IS NOT ──────────────────────────────────────────────────────────────────
///
/// IT IS NOT A TRANSACTION LOG, and it does not pretend to be one. `wd_record_payment` upserts
/// and ADDS, so the schema keeps one row per resident per month carrying a cumulative total —
/// a resident who paid ₹3,000 and then ₹3,200 is ONE row reading ₹6,200, not two rows. Drawing
/// this as a feed of individual handovers would be inventing events the database does not hold.
/// So each row is a MONTH, and the figure on it is what that month has received in total.
///
/// IT SHOWS ONLY MONTHS THAT RECEIVED SOMETHING. Who has NOT paid is the warden's collections
/// screen and the dashboard's "still owing" count; a list of payments containing rows for
/// people who paid nothing would answer neither question.
///
/// Rent is handed over at the warden's desk — there is no in-app checkout in this version — so
/// every row here was typed by a person, and the person is named on it.
class OwnerPaymentsScreen extends ConsumerWidget {
  const OwnerPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(activeHostelIdProvider);
    final owned = ref.watch(myHostelsProvider);

    // The same triage the dashboard does, and for the same reason: "no PG resolved yet" is
    // three different facts and only one of them is an error.
    if (hostelId == null) {
      return switch (owned) {
        AsyncError(:final error) => _Page(
            child: ErrorNote(error: error, onRetry: () => ref.invalidate(myHostelsProvider)),
          ),
        AsyncData() => const _Page(
            child: EmptyNote(
              icon: Icons.apartment_rounded,
              title: 'No PG on your account yet',
              message: 'Payments appear here once a PG is registered against your account.',
            ),
          ),
        _ => const _Page(child: _PaymentsSkeleton()),
      };
    }

    final payments = ref.watch(recentPaymentsProvider(hostelId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(recentPaymentsProvider(hostelId));
        // Same gesture, both reads. The spinner still waits only on the payments — a refund
        // annotation is not worth holding a refresh open for.
        ref.invalidate(hostelRefundsProvider);
        try {
          await ref
              .read(recentPaymentsProvider(hostelId).future)
              .timeout(ownerRefreshTimeout);
        } catch (_) {
          // Rendered by the body below; rethrowing would turn a handled failure into a crash.
        }
      },
      child: whenAsync(
        payments,
        loading: () => const _Page(child: _PaymentsSkeleton()),
        error: (error) => _Page(
          child: ErrorNote(
            error: error,
            onRetry: () => ref.invalidate(recentPaymentsProvider(hostelId)),
          ),
        ),
        data: (page) => page.isEmpty
            ? const _Page(
                child: EmptyNote(
                  icon: Icons.receipt_long_outlined,
                  illustration: EmptyArt.payments,
                  title: 'No payments recorded yet',
                  // Says where the money comes from, because on this build that is the whole
                  // story: nobody can pay inside the app, so an empty list means the desk has
                  // not taken anything yet.
                  message: "Rent is paid at the warden's desk. Every payment a warden "
                      'records appears here, newest first.',
                ),
              )
            : _PaymentRows(hostelId: hostelId, page: page),
      ),
    );
  }
}

/// One scrollable page with a single thing on it. Scrollable even when it holds one card, or
/// pull-to-refresh is the one gesture that cannot rescue a screen that failed to load.
class _Page extends StatelessWidget {
  const _Page({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
        children: [child],
      );
}

class _PaymentRows extends ConsumerStatefulWidget {
  const _PaymentRows({required this.hostelId, required this.page});

  final String hostelId;
  final PagedResult<RecentPayment> page;

  @override
  ConsumerState<_PaymentRows> createState() => _PaymentRowsState();
}

class _PaymentRowsState extends ConsumerState<_PaymentRows> {
  bool _loadingMore = false;
  AppFailure? _loadMoreError;

  /// Older pages are asked for BY TAP, not by scrolling to the bottom.
  ///
  /// The warden's lists auto-load because a warden scrolls a roster looking for one person and
  /// a button in the way is friction. This list is read from the top — "what has come in
  /// lately" — and the tail of it is last year. A deliberate tap also means the failure has
  /// somewhere to live: it lands on the button that caused it, under rows that stay put.
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    final failure =
        await ref.read(recentPaymentsProvider(widget.hostelId).notifier).loadMore();
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      _loadMoreError = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final items = widget.page.items;
    // A qualifier on figures this list already has, so it is taken as `.value ?? empty`: in
    // flight, or failed outright, the list draws exactly as it always did. See
    // [hostelRefundsProvider]. Not narrowed to a month — this list walks backwards through
    // months as it pages.
    final refunds =
        ref.watch(hostelRefundsProvider(StatsQuery(hostelId: widget.hostelId))).value ??
            RefundIndex.empty;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
      children: [
        const SectionLabel(label: 'Recent payments'),
        Text(
          "Rent handed over at the desk, newest first. Each row is one resident's month.",
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: Space.sm),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.sm),
          _PaymentCard(
            payment: items[i],
            refunds: refunds.forMonth(items[i].studentId, items[i].periodMonth),
          ),
        ],
        if (widget.page.hasMore) ...[
          const SizedBox(height: Space.md),
          if (_loadMoreError != null) ...[
            ErrorNote(error: _loadMoreError!, onRetry: _loadMore, compact: true),
            const SizedBox(height: Space.xs),
          ],
          OutlinedButton(
            onPressed: _loadingMore ? null : _loadMore,
            child: Text(_loadingMore ? 'Loading…' : 'Show older payments'),
          ),
        ],
      ],
    );
  }
}

/// One resident's month: what came in, against what was owed, and who took it.
class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment, this.refunds = const []});

  final RecentPayment payment;

  /// This resident's refunds for this month, from `public.payment_refunds`. Empty for very
  /// nearly every row, and empty draws nothing.
  final List<RefundInfo> refunds;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final settled = payment.balance <= 0;
    // Green for a month that is square, amber for one still short. Nothing else on this row is
    // coloured: the figure is the fact, the colour is only whether it finished the job.
    final tone = settled ? NivoraColors.success : NivoraColors.warning;

    return GlassCard(
      padding: const EdgeInsets.all(Space.md),
      // The refund is spoken immediately after the figure it qualifies, not appended at the
      // end. "Paid ₹8,500 for August, ₹2,000 of it refunded" is one claim; the same words in
      // the other order are two, and the listener has already filed the first before the
      // second arrives.
      semanticLabel: '${payment.fullName} paid ${money(payment.amountPaid)} '
          'for ${monthLabel(payment.periodMonth)}'
          '${refunds.map((r) => ', ${money(r.amount)} '
              '${r.isSettled ? 'refunded' : 'refund pending'}').join()}'
          '${settled ? '' : ', ${money(payment.balance)} still outstanding'}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(name: payment.fullName, tone: tone),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment.fullName,
                      style: t.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Space.xxs / 2),
                    Text(_placement(payment), style: t.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(payment.amountPaid),
                    style: t.textTheme.titleMedium
                        ?.copyWith(color: context.tones.resolve(tone)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xxs),
                  // The status word is the trigger's own (app.fee_status_compute), so this row
                  // and the warden's collections screen cannot disagree about the same month.
                  StatusChip(label: payment.status.label, tone: tone, dot: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Divider(color: t.colorScheme.outlineVariant, height: Strokes.hairline),
          const SizedBox(height: Space.sm),
          // ═══ WHAT AN OWNER READS THIS LIST FOR IS INCOME ═══
          //
          // Every other row here is money the hostel kept. A refunded month that showed only
          // its figure and a status word would be counted, by the person reading, as revenue
          // it is not — and this is the screen where that mistake compounds, because it is the
          // one an owner scrolls to answer "what did we take last month".
          //
          // So it is stated ABOVE the facts, not filed among them: a strip across the card
          // rather than another labelled value, because a fact that changes what the headline
          // figure MEANS cannot sit in the same visual rank as the room number.
          if (refunds.isNotEmpty) ...[
            _RefundStrip(refunds: refunds),
            const SizedBox(height: Space.sm),
          ],
          _Fact(label: 'Rent for', value: monthLabel(payment.periodMonth)),
          if (!settled)
            _Fact(label: 'Still outstanding', value: money(payment.balance)),
          _Fact(
            label: 'Received',
            value: payment.paidOn == null
                // Only reachable on a row whose date was cleared by a correction; the RPC
                // already excludes months that received nothing.
                ? 'No date recorded'
                : '${dayLabel(payment.paidOn!)}'
                    '${payment.mode == null ? '' : ' · ${payment.mode!.label}'}',
          ),
          _Fact(label: 'Recorded by', value: _recorder(payment)),
          if (payment.notes != null && payment.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(payment.notes!.trim(), style: t.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  static String _placement(RecentPayment payment) {
    if (payment.roomNumber == null) return 'No room assigned';
    if (payment.bedNumber == null) return 'Room ${payment.roomNumber}';
    return 'Room ${payment.roomNumber} · Bed ${payment.bedNumber}';
  }

  /// Who took the money.
  ///
  /// NULL IS SAID OUT LOUD rather than left blank. `recorded_by` is nullable, and its `users`
  /// row can be deleted — an empty line where a person belongs reads as "nobody took this
  /// money", which is a different and more alarming claim than "we no longer know who". The
  /// wording covers both without asserting which: it does not say the account was deleted,
  /// because a row written by a server process has no account to delete.
  ///
  /// The role is appended when the server sent one: "Priya Nair (Warden)" and "Priya Nair
  /// (Owner)" are different answers to "who has been taking cash".
  static String _recorder(RecentPayment payment) {
    final name = payment.recordedByName?.trim();
    if (name == null || name.isEmpty) return 'No staff account on record';
    final role = payment.recordedByRole;
    if (role == null || role.isEmpty) return name;
    return '$name (${_roleLabel(role)})';
  }

  /// The wire value as a word. Deliberately not a lookup into `UserRole` — the data layer keeps
  /// this as the string Postgres sent (see [RecentPayment.recordedByRole]), and a role this
  /// build does not know about should print as itself rather than disappear.
  static String _roleLabel(String wire) => switch (wire) {
        'owner' => 'Owner',
        'manager' => 'Manager',
        'warden' => 'Warden',
        'super_admin' => 'Nivora',
        _ => wire,
      };
}

/// "₹2,000 of this went back on 12 Sep" — across the card, above the facts.
///
/// TONED [NivoraColors.info], which is the one colour on this card that is not the settled /
/// short pairing. That is deliberate and it is the same decision taken on the resident's rent
/// card (see [RefundNote] in features/student/widgets/rent.dart): a refund is a fact, not a
/// fault — nobody did anything wrong — so it may not wear `error`, and it must not wear the
/// amber that already means "still owing" or the green that already means "collected". `info`
/// is a canonical token with measured ratios in both themes and no new pairing enters the
/// palette for it; `test/theme_contrast_test.dart` measures what this widget actually paints.
///
/// EVERY VALUE IS A COLUMN. The figure is `amount_paise` and the date is `processed_at` (or
/// `created_at` while an instruction is still pending); a refund whose day the server did not
/// send prints without one rather than with a guess.
///
/// SETTLED AND PENDING READ DIFFERENTLY, because an owner counting last month's income needs
/// "this money has gone" and "this money is about to go" to be two different lines.
class _RefundStrip extends StatelessWidget {
  const _RefundStrip({required this.refunds});

  /// One month's refunds. One line each — two refunds are two facts, and their total is a
  /// figure no column in this schema holds.
  final List<RefundInfo> refunds;

  /// The verb carries the status: only a PROCESSED refund has reduced the figure above it.
  static String _line(RefundInfo r) {
    final amount = money(r.amount);
    final on = r.on;
    if (!r.isSettled) {
      return on == null
          ? '$amount of this is being refunded'
          : '$amount of this is being refunded — requested ${dayLabel(on)}';
    }
    return on == null
        ? '$amount of this was refunded'
        : '$amount of this was refunded on ${dayLabel(on)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = context.tones.resolve(NivoraColors.info);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: context.tones.chipFill(accent),
        borderRadius: Radii.rControl,
        border: Border.all(color: context.tones.chipBorder(accent), width: Strokes.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.assignment_return_rounded, size: IconSize.sm, color: accent),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in refunds)
                  Text(
                    _line(r),
                    // bodySmall is 12px, which is the tightest case the chip contract covers:
                    // the fill is a 10% tint of this very tone, so the text sits on a ground
                    // made of itself. Measured 4.90:1 dark / 5.31:1 light — see NivoraSemantics
                    // and the refund group in test/theme_contrast_test.dart.
                    style: t.textTheme.bodySmall?.copyWith(color: accent),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs / 2),
      // Both halves flex, the 6:5 split used everywhere a labelled value appears in this app —
      // an unbounded value column wraps one character per line at 320dp and 1.3x text.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: Text(label, style: t.textTheme.bodySmall)),
          const SizedBox(width: Space.sm),
          Expanded(
            flex: 5,
            child: Text(value, style: t.textTheme.bodyMedium, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// The list's own shape before the first page lands.
class _PaymentsSkeleton extends StatelessWidget {
  const _PaymentsSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonCard(lines: 3, height: 148),
          SizedBox(height: Space.sm),
          SkeletonCard(lines: 3, height: 148),
          SizedBox(height: Space.sm),
          SkeletonCard(lines: 3, height: 148),
        ],
      );
}
