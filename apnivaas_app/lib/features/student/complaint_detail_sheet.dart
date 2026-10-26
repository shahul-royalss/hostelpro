library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay.dart';
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The same clay art the list row uses, so the sheet and the row it was opened
                // from read as one object.
                ClayIcon(complaintClay(complaint.category), size: ClaySize.tile),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(complaint.title, style: t.textTheme.titleLarge),
                      const SizedBox(height: Space.xxs),
                      Text(
                        '${complaint.category.label} · raised '
                        '${dayLabel(complaint.createdAt.toLocal())}',
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            // Under the title rather than beside it: a long title and the chip used to share
            // one row, and the title lost.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusPill(label: complaint.status.label, tone: tone, dot: true),
            ),

            if (complaint.description != null && complaint.description!.trim().isNotEmpty) ...[
              const SizedBox(height: Space.md),
              SelectionArea(
                child: Text(complaint.description!.trim(), style: t.textTheme.bodyLarge),
              ),
            ],

            // What the hostel did, on the Mist banner with the trophy: a resolution is the one
            // good-news moment a complaint has, and it reads as one.
            if (complaint.resolutionNote != null &&
                complaint.resolutionNote!.trim().isNotEmpty) ...[
              const SizedBox(height: Space.md),
              InfoBanner(
                title: 'What the hostel did',
                message: complaint.resolvedAt == null
                    ? complaint.resolutionNote!.trim()
                    : '${complaint.resolutionNote!.trim()}\n'
                        'Closed ${dayLabel(complaint.resolvedAt!.toLocal())}',
                icon: ClayIcons.success,
              ),
            ],

            const SizedBox(height: Space.lg),
            const SectionHeader(title: 'Progress', size: SectionHeaderSize.card),
            const SizedBox(height: Space.sm),
            AsyncSection<List<ComplaintEvent>>(
              value: timeline,
              onRetry: () => ref.invalidate(complaintTimelineProvider(complaint.id)),
              loading: const SkeletonCard(lines: 3),
              builder: (events) => ComplaintTimeline(events: events),
            ),

            const SizedBox(height: Space.md),
            // Full-bleed. The theme's `Size.fromHeight(48)` fixes the height and leaves the
            // minimum WIDTH at zero, so inside this `CrossAxisAlignment.start` column every
            // button on every sheet in this feature was shrinking to hug its label. The design's
            // sheet actions run the width of the sheet.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
