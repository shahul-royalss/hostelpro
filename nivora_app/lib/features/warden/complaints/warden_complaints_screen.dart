library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../common/refresh.dart';
import '../data/warden_providers.dart';
import '../widgets/paged_list.dart';
import '../widgets/warden_ui.dart';
import 'complaint_sheet.dart';

/// The complaint queue.
///
/// DEFAULTS TO "NEEDS ACTION", which is `status <> 'resolved'` — the same predicate
/// rpc_hostel_stats counts as open_complaints. A queue that opens on everything ever filed is a
/// list nobody works; a queue that opens on the same set the dashboard counted is one a warden
/// can finish.
///
/// Ordered newest first by the repository, which is the right way round for a queue that is
/// worked continuously: the oldest complaint in a hostel is usually the one nobody can fix.
class WardenComplaintsScreen extends ConsumerWidget {
  const WardenComplaintsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);
    if (hostelId == null) {
      return const WardenScreen(
        title: 'Complaints',
        child: EmptyState(
          icon: Icons.report_problem_rounded,
          title: 'No hostel on this account',
          detail: 'A warden is attached to one hostel. Ask the owner to check the assignment.',
        ),
      );
    }

    final filter = ref.watch(complaintFilterProvider);
    final query = ComplaintQuery(
      hostelId: hostelId,
      status: filter.status,
      openOnly: filter.openOnly,
    );
    final complaints = ref.watch(complaintsProvider(query));

    return WardenScreen(
      title: 'Complaints',
      child: PagedList<Complaint>(
        value: complaints,
        // Bounded, and it SPEAKS. Invalidating and returning left the spinner to retract in
        // the same frame — a pull that looked ignored — and AsyncSection keeps the rows a
        // warden is reading through a failed reload, so a queue that did not refresh said
        // nothing at all. See features/common/refresh.dart.
        onRefresh: () {
          ref.invalidate(complaintsProvider(query));
          ref.invalidate(hostelStatsProvider);
          return settleRefresh(context, () => ref.read(complaintsProvider(query).future));
        },
        onLoadMore: () => ref.read(complaintsProvider(query).notifier).loadMore(),
        header: Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // `chips` (4:747): the gold-filled chip is the filter that is on.
              FilterBar<ComplaintFilter>(
                options: ComplaintFilter.values,
                selected: filter,
                labelOf: (option) => option.label,
                onSelected: (option) =>
                    ref.read(complaintFilterProvider.notifier).set(option),
              ),
              // The design's list header over the queue. It names the filter that is actually
              // on screen rather than a fixed word, so the heading and the chips cannot say
              // different things.
              SectionLabel(label: filter.label),
            ],
          ),
        ),
        empty: EmptyState(
          icon: filter == ComplaintFilter.needsAction
              ? Icons.check_circle_outline_rounded
              : Icons.inbox_outlined,
          title: filter == ComplaintFilter.needsAction
              ? 'Nothing outstanding'
              : 'No ${filter.label.toLowerCase()} complaints',
          detail: filter == ComplaintFilter.needsAction
              ? 'Every complaint in this hostel has been resolved.'
              : 'Try another filter.',
          // An empty queue is the good outcome here, and the halo says so in mint rather than
          // in the neutral grey a missing list gets.
          tone: filter == ComplaintFilter.needsAction ? NivoraColors.success : null,
        ),
        itemBuilder: (context, complaint) => _ComplaintRow(complaint: complaint),
      ),
    );
  }
}

class _ComplaintRow extends StatelessWidget {
  const _ComplaintRow({required this.complaint});
  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    // warden-maintenance-dashboard.png's ticket card: the subject on its own line with the
    // state chip opposite it, a hairline, then the facts underneath in glyphed metadata. The
    // mockup's facts are a room and a resident's name; the complaints query returns neither
    // (public.complaints carries a student_id and no room at all), so the two this app really
    // has take their place rather than a room number being invented.
    return TapRow(
      onTap: () => showComplaintSheet(context, complaintId: complaint.id),
      padding: const EdgeInsets.all(Space.md),
      semanticLabel:
          '${complaint.title}, ${complaint.category.label}, ${complaint.status.label}, '
          'raised ${age(complaint.createdAt)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  complaint.title,
                  style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Space.xs),
              // `complaint-card` (4:710) heads its row with the category badge and puts the
              // age opposite it, both above the body copy. The status is the badge here
              // because the CATEGORY is already spoken by the glyph on the meta line, and
              // "which of these do I still have to do something about" is the question a queue
              // is opened to answer.
              StatusPill(status: complaint.status),
            ],
          ),
          const SizedBox(height: Space.xs),
          MetaLine([
            (categoryIcon(complaint.category), complaint.category.label),
            (Icons.schedule_rounded, age(complaint.createdAt)),
          ]),
        ],
      ),
    );
  }
}

/// One icon per public.complaint_category value. Exhaustive on purpose: adding a category to
/// the enum makes this switch fail to compile rather than silently drawing the wrong picture.
IconData categoryIcon(ComplaintCategory category) => switch (category) {
      ComplaintCategory.food => Icons.restaurant_rounded,
      ComplaintCategory.cleaning => Icons.cleaning_services_rounded,
      ComplaintCategory.maintenance => Icons.handyman_rounded,
      ComplaintCategory.wifi => Icons.wifi_rounded,
      ComplaintCategory.roommate => Icons.groups_rounded,
      ComplaintCategory.other => Icons.help_outline_rounded,
    };
