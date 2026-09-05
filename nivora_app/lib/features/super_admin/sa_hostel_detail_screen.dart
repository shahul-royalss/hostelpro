library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import '../common/refresh.dart';
import 'data/sa_models.dart';
import 'data/sa_providers.dart';
import 'widgets/sa_ui.dart';

/// One hostel, as the platform sees it.
///
/// RPCs / TABLES:
///   public.rpc_sa_hostels()   — the summary row (owner, subscription, beds, complaints)
///   public.rpc_hostel_stats() — this month's operating figures. `security invoker`, and
///                               `hostels_select` admits a Super Admin to every hostel, so the
///                               same function the warden's dashboard uses answers here too
///   public.hostels            — floors and rooms, which the summary row does not carry
///   public.subscriptions      — the billing history
///
/// ── WHY THE SUMMARY IS RE-READ RATHER THAN PASSED IN ─────────────────────────────────────
///
/// The list could hand this screen the row that was tapped, and it would render instantly. It
/// would also be a snapshot: the days-left figure ages, and a renewal recorded from the web in
/// the meantime would leave this page confidently showing "Expired" over a hostel that is not.
/// One id in, one fresh read out.
class SaHostelDetailScreen extends ConsumerWidget {
  const SaHostelDetailScreen({super.key, required this.hostelId});

  final String hostelId;

  static Route<void> route(String hostelId) => MaterialPageRoute<void>(
        builder: (_) => SaHostelDetailScreen(hostelId: hostelId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(saHostelProvider(hostelId));

    return SaPage(
      eyebrow: 'HOSTEL',
      title: summary.value?.hostelName ?? 'Hostel',
      onRefresh: () {
        ref.invalidate(saHostelProvider(hostelId));
        ref.invalidate(saSubscriptionHistoryProvider(hostelId));
        ref.invalidate(hostelProvider(hostelId));
        return settleRefresh(context, () => ref.read(saHostelProvider(hostelId).future));
      },
      child: saAsync<SaHostelRow?>(
        summary,
        loading: () => const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SaSkeletonCard(lines: 2, height: 120),
            SizedBox(height: Space.md),
            SaSkeletonCard(lines: 3, height: 160),
            SizedBox(height: Space.md),
            SaSkeletonCard(lines: 3, height: 160),
          ],
        ),
        error: (e) => SaError(error: e, onRetry: () => ref.invalidate(saHostelProvider(hostelId))),
        data: (hostel) {
          if (hostel == null) {
            // rpc_sa_hostels ends in `where app.is_super_admin()`, so no row is either "gone"
            // or "not permitted" — and the old copy said both in one breath, which told the
            // reader neither. The dashboard read decides which one it is.
            return switch (saEmptyVerdict(ref.watch(saStatsProvider))) {
              SaEmptyVerdict.pending => const SaSkeletonCard(lines: 2, height: 120),
              SaEmptyVerdict.unverified => SaUnverified(
                  title: 'This hostel did not come back',
                  message: 'The platform read returned no row for it, and the dashboard read '
                      'that would say whether this account can see platform data at all could '
                      'not be reached. A hostel that has been removed and a hostel this '
                      'account is not admitted to look the same from here.',
                  onRetry: () {
                    ref.invalidate(saStatsProvider);
                    ref.invalidate(saHostelProvider(hostelId));
                  },
                ),
              SaEmptyVerdict.refused => const SaNotPermitted(),

            // NOT SaNotPermitted, and not SaUnverified's "check again" either. The read
            // that would have explained this emptiness died with the access token, so the
            // only honest thing on screen is the way to get a live one.
            SaEmptyVerdict.credentialDead => const SaSessionEnded(),
              SaEmptyVerdict.confirmed => const SaEmpty(
                  icon: Icons.apartment_rounded,
                  title: 'Hostel not found',
                  message: 'This account can read platform data, and the platform has no such '
                      'hostel — it has been removed. Go back and pick another from the list.',
                ),
            };
          }
          return _Detail(hostel: hostel);
        },
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.hostel});
  final SaHostelRow hostel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The consequence first. Everything below is reporting; this is the thing to act on.
        if (!hostel.isWritable) ...[
          SaReadOnlyBand(hostel: hostel),
          const SizedBox(height: Space.md),
        ],

        GlassCard(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // The same violet building that headed this hostel's row in the list, so
                  // the tap lands on something recognisably the same object. Not a
                  // DomainCard: this card carries two status pills, and state wins a surface.
                  const DomainIcon(domain: NivoraDomain.rooms, icon: Icons.apartment_rounded),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    // 16/700 — the design's card title (4:1543). Nothing in the Figma file is
                    // set at 20, and a hostel's name is a card title, not a hero figure.
                    child: Text(hostel.hostelName, style: t.textTheme.titleMedium),
                  ),
                  const SizedBox(width: Space.xs),
                  SaSubscriptionPill(state: hostel.subState, daysLeft: hostel.daysLeft),
                ],
              ),
              const SizedBox(height: Space.xs),
              Row(
                children: [
                  SaPill(
                    label: hostel.hostelStatus.label,
                    tone: hostelTone(context, hostel.hostelStatus),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      'On Nivora since ${dateLabel(hostel.createdAt.toLocal())}',
                      style: t.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              if (hostel.address != null) ...[
                const SizedBox(height: Space.sm),
                Text(hostel.address!, style: t.textTheme.bodyMedium),
              ],
              const SizedBox(height: Space.md),
              SaMeter(
                rate: hostel.occupancyRate,
                label: 'Occupancy',
                caption: '${count(hostel.occupiedBeds)} of '
                    '${plural(hostel.totalBeds, 'bed')} taken',
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),

        const SaHeading(title: 'Owner', domain: NivoraDomain.people),
        _OwnerCard(hostel: hostel),
        const SizedBox(height: Space.lg),

        SaHeading(
          title: 'Subscription',
          caption: daysLeftLabel(hostel.daysLeft),
          domain: NivoraDomain.money,
          icon: Icons.card_membership_rounded,
        ),
        _SubscriptionCard(hostel: hostel),
        const SizedBox(height: Space.lg),

        const SaHeading(title: 'Structure', domain: NivoraDomain.rooms),
        _StructureCard(hostelId: hostel.hostelId, hostel: hostel),
        const SizedBox(height: Space.lg),

        SaHeading(
          title: 'This month',
        ),
        _OperatingCard(hostelId: hostel.hostelId, openComplaints: hostel.openComplaints),
      ],
    );
  }
}

/// Who to ring. The email and the phone are the two things a platform admin copies off this
/// screen, so both are one tap rather than a long-press-and-hope.
class _OwnerCard extends StatelessWidget {
  const _OwnerCard({required this.hostel});
  final SaHostelRow hostel;

  @override
  Widget build(BuildContext context) {
    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaDetailRow(label: 'Name', value: hostel.ownerName),
          SaDetailRow(
            label: 'Login',
            value: hostel.ownerEmail ?? 'No email on record',
            trailing: hostel.ownerEmail == null
                ? null
                : SaCopyButton(text: hostel.ownerEmail!, label: 'email address'),
          ),
          SaDetailRow(
            label: 'Phone',
            value: hostel.ownerPhone ?? 'No phone on record',
            trailing: hostel.ownerPhone == null
                ? null
                : SaCopyButton(text: hostel.ownerPhone!, label: 'phone number'),
          ),
        ],
      ),
    );
  }
}

/// The current period and everything before it.
class _SubscriptionCard extends ConsumerWidget {
  const _SubscriptionCard({required this.hostel});
  final SaHostelRow hostel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final history = ref.watch(saSubscriptionHistoryProvider(hostel.hostelId));

    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hostel.subEnd == null)
            Text(
              'No subscription has ever been recorded for this hostel, so every write is '
              'refused. Create one from the web console to bring it online.',
              style: t.textTheme.bodyMedium,
            )
          else ...[
            SaDetailRow(
              label: 'Current period',
              value: '${hostel.subStart == null ? '—' : dateLabel(hostel.subStart!)} → '
                  '${dateLabel(hostel.subEnd!)}',
            ),
            SaDetailRow(
              label: 'Amount',
              value: hostel.subAmount == null ? '—' : money(hostel.subAmount!),
            ),
            SaDetailRow(
              label: 'State',
              value: '${hostel.subState.label} · ${daysLeftLabel(hostel.daysLeft)}',
              tone: subscriptionTone(context, hostel.subState),
            ),
          ],
          const SizedBox(height: Space.sm),
          Divider(height: Space.md, color: t.colorScheme.outlineVariant),
          Text('HISTORY', style: t.textTheme.labelSmall),
          const SizedBox(height: Space.xs),
          saAsync<List<SubscriptionRecord>>(
            history,
            loading: () => const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SaSkeleton(height: 16),
                SizedBox(height: Space.xs),
                SaSkeleton(width: 200, height: 16),
              ],
            ),
            error: (e) => SaError(error: e, compact: true),
            data: (records) {
              if (records.isEmpty) {
                return const SaEmpty(
                  icon: Icons.history_rounded,
                  title: 'No periods recorded',
                  compact: true,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final record in records) _HistoryRow(record: record),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One paid period. Renewals INSERT a row rather than moving the end date, so this list is the
/// billing history rather than an audit of edits.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record});
  final SubscriptionRecord record;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${dateLabel(record.startDate)} → ${dateLabel(record.endDate)}',
                  style: t.textTheme.bodyMedium,
                ),
                if (record.notes != null)
                  Text(record.notes!, style: t.textTheme.bodySmall, maxLines: 2),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          Text(money(record.amount), style: t.textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// Floors, rooms and beds, read from public.hostels.
///
/// Only a Super Admin can change these (sa_update_hostel_structure, grow-only), so a platform
/// admin looking at a hostel that has outgrown its scaffold is looking at their own job.
class _StructureCard extends ConsumerWidget {
  const _StructureCard({required this.hostelId, required this.hostel});
  final String hostelId;
  final SaHostelRow hostel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = ref.watch(hostelProvider(hostelId));

    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: saAsync<Hostel?>(
        row,
        loading: () => const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SaSkeleton(height: 16),
            SizedBox(height: Space.xs),
            SaSkeleton(width: 220, height: 16),
          ],
        ),
        error: (e) => SaError(error: e, compact: true),
        data: (value) {
          if (value == null) {
            // Not "this hostel has no floors" — a scaffolded hostel with nothing in it still
            // returns a row. No row means the read did not land: removed, or not admitted.
            return const SaEmpty(
              icon: Icons.layers_outlined,
              title: 'Structure did not load',
              message: 'The hostel record came back with no row in it, which is not the same '
                  'as a hostel with no rooms. Pull down to read it again.',
              compact: true,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaDetailRow(label: 'Floors', value: count(value.totalFloors)),
              SaDetailRow(label: 'Rooms', value: count(value.totalRooms)),
              SaDetailRow(
                label: 'Beds',
                value: '${count(hostel.totalBeds)} scaffolded · '
                    '${count(value.bedsPerRoomDefault)} per room by default',
              ),
            ],
          );
        },
      ),
    );
  }
}

/// This month's operating figures, from public.rpc_hostel_stats.
class _OperatingCard extends ConsumerWidget {
  const _OperatingCard({required this.hostelId, required this.openComplaints});
  final String hostelId;
  final int openComplaints;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(currentPeriodMonthProvider);
    final stats = ref.watch(
      hostelStatsProvider(StatsQuery(hostelId: hostelId, periodMonth: period)),
    );

    return saAsync<HostelStats?>(
      stats,
      loading: () => const SaSkeletonCard(lines: 3, height: 170),
      error: (e) => SaError(
        error: e,
        onRetry: () => ref.invalidate(
          hostelStatsProvider(StatsQuery(hostelId: hostelId, periodMonth: period)),
        ),
      ),
      data: (value) {
        if (value == null) {
          // NOT A QUIET MONTH. rpc_hostel_stats is a single `select` of scalar subqueries, so a
          // hostel with nothing happening in it comes back as a ROW OF ZEROES; no row at all
          // means the read did not produce one. Drawing zeroes here would be inventing figures,
          // and titling it "no activity" would be inventing a month.
          return const SaEmpty(
            icon: Icons.query_stats_rounded,
            title: 'Figures did not load',
            message: 'The server returned no figures row for this hostel. A month with nothing '
                'in it still comes back as zeroes, so this is a read that did not land rather '
                'than a quiet month. Pull down to try it again.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: GlassStatCard(
                    label: 'Fees collected',
                    value: money(value.feesCollected),
                    caption: '${count(value.studentsPaid)} paid, '
                        '${count(value.studentsUnpaid)} outstanding',
                    icon: Icons.receipt_long_rounded,
                    tone: NivoraColors.success,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: GlassStatCard(
                    label: 'Fees pending',
                    value: money(value.feesPending),
                    caption: monthLabel(period),
                    icon: Icons.pending_actions_rounded,
                    tone: NivoraColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: GlassStatCard(
                    label: 'Open complaints',
                    value: count(openComplaints),
                    caption: 'Open and in progress',
                    icon: Icons.report_problem_rounded,
                    tone: openComplaints > 0 ? NivoraColors.warning : null,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: GlassStatCard(
                    label: 'Residents',
                    value: count(value.activeStudents),
                    caption: '${count(value.pendingLeaves)} on leave request',
                    icon: Icons.people_alt_rounded,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
