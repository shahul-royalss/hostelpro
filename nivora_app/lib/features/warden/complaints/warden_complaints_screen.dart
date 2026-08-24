library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
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
      subtitle: filter.label,
      child: PagedList<Complaint>(
        value: complaints,
        onRefresh: () async {
          ref.invalidate(complaintsProvider(query));
          ref.invalidate(hostelStatsProvider);
        },
        onLoadMore: () => ref.read(complaintsProvider(query).notifier).loadMore(),
        header: Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final option in ComplaintFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.xs),
                    child: ChoiceChip(
                      label: Text(option.label),
                      selected: filter == option,
                      onSelected: (_) =>
                          ref.read(complaintFilterProvider.notifier).set(option),
                    ),
                  ),
              ],
            ),
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
    final tone = toneFor(context, complaint.status);

    return TapRow(
      onTap: () => showComplaintSheet(context, complaintId: complaint.id),
      semanticLabel:
          '${complaint.title}, ${complaint.category.label}, ${complaint.status.label}, '
          'raised ${age(complaint.createdAt)}',
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: Radii.rControl,
            ),
            child: Icon(categoryIcon(complaint.category), size: 20, color: tone),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complaint.title,
                  style: t.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${complaint.category.label} · ${age(complaint.createdAt)}',
                  style: t.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          StatusPill(status: complaint.status, dense: true),
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
