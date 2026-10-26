library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../common/refresh.dart';
import '../../../shared/clay/clay.dart' show ClayIcon, ClayIcons, ListGroup, ListRow;
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
        child: WardenEmptyState(
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

    // A count is only TRUE once the last page is in — `hasMore` is the server's own word for
    // that. While more pages exist the heading carries no number rather than reporting the
    // twenty rows that happen to be downloaded. Nor does it say "0": the empty state under it
    // already says so in words.
    final page = complaints.value;
    final total = (page != null && !page.hasMore) ? page.items.length : null;

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
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilterBar<ComplaintFilter>(
              options: ComplaintFilter.values,
              selected: filter,
              labelOf: (option) => option.label,
              onSelected: (option) => ref.read(complaintFilterProvider.notifier).set(option),
            ),
            // The heading over the queue names the filter that is actually on screen rather
            // than a fixed word, with its count opposite — so the heading and the chips cannot
            // say different things.
            SectionLabel(
              label: filter.label,
              trailing: total == null || total == 0
                  ? null
                  : Text(
                      countOf(total, 'complaint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
            ),
          ],
        ),
        // THIS LIST IS FILTERED, and that changes what empty is allowed to say. On the
        // needs-action filter an empty queue means every complaint in the hostel has been
        // dealt with — good news, and it gets the clay success art. On any other filter it only
        // means this filter matched nothing, and "nothing needs you" there would be a lie
        // while open complaints sit one chip away. That arm keeps its filter-aware wording.
        empty: filter == ComplaintFilter.needsAction
            ? const WardenEmptyState(
                icon: Icons.task_alt_rounded,
                tone: ApnivaasColors.success,
                title: 'Nothing needs action',
                detail: 'Every complaint in this hostel has been dealt with. '
                    'New ones land here first.',
              )
            : WardenEmptyState(
                icon: Icons.inbox_outlined,
                title: 'No ${filter.label.toLowerCase()} complaints',
                detail: 'Try another filter.',
              ),
        itemBuilder: (context, complaint) => _ComplaintRow(complaint: complaint),
      ),
    );
  }
}

/// One complaint, in a card of its own: what it is about as clay art, the subject in full, and
/// under it the state chip with the category and how long it has been waiting.
///
/// THE SUBJECT GETS TWO LINES. It is the one thing on the row a warden has to read to know
/// what they are walking towards, so the state moves under it instead of squeezing it to a
/// fragment opposite. The facts are the two this app really has: public.complaints carries a
/// student_id and no room at all, so no room number is invented for the row.
class _ComplaintRow extends StatelessWidget {
  const _ComplaintRow({required this.complaint});
  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // A third line from 1.3x text: a subject cut to "Geyser not heating in 2nd…" at large text
    // has lost the floor and the room, which are the words a warden walks towards.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    void open() => showComplaintSheet(context, complaintId: complaint.id);

    return ListGroup(
      children: [
        Semantics(
          button: true,
          label: '${complaint.title}, ${complaint.category.label}, ${complaint.status.label}, '
              'raised ${age(complaint.createdAt)}',
          excludeSemantics: true,
          onTap: open,
          child: InkWell(
            onTap: open,
            excludeFromSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: ListRow.minHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Row(
                  children: [
                    ClayIcon(categoryClay(complaint.category), size: ClaySize.list),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            complaint.title,
                            style: t.textTheme.titleMedium,
                            maxLines: scale >= 1.3 ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: Space.xs - Space.hair),
                          Wrap(
                            spacing: Space.xs,
                            runSpacing: Space.xxs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusPill(status: complaint.status),
                              Text(
                                '${complaint.category.label} · ${age(complaint.createdAt)}',
                                style: t.textTheme.bodySmall
                                    ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Icon(Icons.chevron_right_rounded,
                        size: IconSize.lg, color: t.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The clay art for each public.complaint_category value. Exhaustive on purpose: adding a
/// category to the enum makes this switch fail to compile rather than silently drawing the
/// wrong picture. Maintenance takes the gear — the set has no wrench — and anything without a
/// render of its own takes the complaint art itself.
String categoryClay(ComplaintCategory category) => switch (category) {
      ComplaintCategory.food => ClayIcons.food,
      ComplaintCategory.cleaning => ClayIcons.housekeeping,
      ComplaintCategory.maintenance => ClayIcons.settings,
      ComplaintCategory.wifi => ClayIcons.wifi,
      ComplaintCategory.roommate => ClayIcons.team,
      ComplaintCategory.other => ClayIcons.complaint,
    };
