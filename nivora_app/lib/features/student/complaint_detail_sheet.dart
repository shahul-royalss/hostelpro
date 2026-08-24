library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import 'widgets/common.dart';
import 'widgets/complaint.dart';
import 'widgets/format.dart';

/// One of the resident's complaints, with everything the hostel has done about it.
///
/// The timeline is a separate read (`complaint_events`) because it is a separate table and it
/// is only worth fetching for the one complaint being looked at. Its select policy admits the
/// complaint's own student, so this returns the resident's history and nobody else's.
Future<void> showComplaintDetailSheet(BuildContext context, {required Complaint complaint}) {
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _ComplaintDetailSheet(complaint: complaint),
  );
}

class _ComplaintDetailSheet extends ConsumerWidget {
  const _ComplaintDetailSheet({required this.complaint});

  final Complaint complaint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final tone = complaintTone(complaint.status);
    final timeline = ref.watch(complaintTimelineProvider(complaint.id));

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(complaintIcon(complaint.category), size: 20, color: t.colorScheme.primary),
                const SizedBox(width: Space.xs),
                Expanded(child: Text(complaint.title, style: t.textTheme.titleLarge)),
                const SizedBox(width: Space.xs),
                StatusPill(label: complaint.status.label, tone: tone),
              ],
            ),
            const SizedBox(height: Space.xxs),
            Text(
              '${complaint.category.label} · raised ${dayLabel(complaint.createdAt.toLocal())}',
              style: t.textTheme.labelSmall,
            ),

            if (complaint.description != null && complaint.description!.trim().isNotEmpty) ...[
              const SizedBox(height: Space.md),
              SelectionArea(
                child: Text(complaint.description!.trim(), style: t.textTheme.bodyLarge),
              ),
            ],

            if (complaint.resolutionNote != null &&
                complaint.resolutionNote!.trim().isNotEmpty) ...[
              const SizedBox(height: Space.md),
              OutlineCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WHAT THE HOSTEL DID', style: t.textTheme.labelSmall),
                    const SizedBox(height: Space.xxs),
                    Text(complaint.resolutionNote!.trim(), style: t.textTheme.bodyMedium),
                    if (complaint.resolvedAt != null) ...[
                      const SizedBox(height: Space.xs),
                      Text('Closed ${dayLabel(complaint.resolvedAt!.toLocal())}',
                          style: t.textTheme.labelSmall),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: Space.md),
            Text('PROGRESS', style: t.textTheme.labelSmall),
            const SizedBox(height: Space.sm),
            AsyncSection<List<ComplaintEvent>>(
              value: timeline,
              onRetry: () => ref.invalidate(complaintTimelineProvider(complaint.id)),
              loading: const SkeletonCard(lines: 3),
              builder: (events) => ComplaintTimeline(events: events),
            ),

            const SizedBox(height: Space.md),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
