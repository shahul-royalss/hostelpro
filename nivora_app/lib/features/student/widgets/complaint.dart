library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import 'common.dart';
import 'format.dart';

/// The icon that stands for a complaint category.
///
/// One mapping, used by the list, the detail sheet and the category picker, so a Wi-Fi
/// complaint cannot be a router in one place and a question mark in another.
IconData complaintIcon(ComplaintCategory category) => switch (category) {
      ComplaintCategory.food => Icons.restaurant_rounded,
      ComplaintCategory.cleaning => Icons.cleaning_services_rounded,
      ComplaintCategory.maintenance => Icons.build_rounded,
      ComplaintCategory.wifi => Icons.wifi_rounded,
      ComplaintCategory.roommate => Icons.people_alt_rounded,
      ComplaintCategory.other => Icons.chat_bubble_outline_rounded,
    };

/// One of the resident's own complaints, in a list.
class ComplaintTile extends StatelessWidget {
  const ComplaintTile({super.key, required this.complaint, this.onTap});

  final Complaint complaint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = complaintTone(complaint.status);
    return OutlineCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(complaintIcon(complaint.category), size: IconSize.md, color: t.colorScheme.primary),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  complaint.title,
                  style: t.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Space.xs),
              StatusPill(label: complaint.status.label, tone: tone),
            ],
          ),
          if (complaint.description != null && complaint.description!.trim().isNotEmpty) ...[
            const SizedBox(height: Space.xxs),
            Text(
              complaint.description!.trim(),
              style: t.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: Space.xs),
          Text(
            '${complaint.category.label} · raised ${relativeTime(complaint.createdAt)}',
            style: t.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// The status history of one complaint.
///
/// Read-only by construction: `complaint_events` rows are written by a trigger, and its INSERT
/// policy admits only the service role. What is drawn here is what actually happened, not a log
/// the client contributed to.
class ComplaintTimeline extends StatelessWidget {
  const ComplaintTimeline({super.key, required this.events});

  final List<ComplaintEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const EmptyNote(
        icon: Icons.timeline_rounded,
        title: 'No updates yet',
        message: 'You will see every status change here as your warden works on it.',
        tone: NivoraColors.textMuted,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < events.length; i++)
          _Step(event: events[i], isLast: i == events.length - 1),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.event, required this.isLast});

  final ComplaintEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    // [complaintTone] is a context-free switch, so this arrives CANONICAL. The same status is
    // drawn as a resolved accent by the [StatusPill] at the top of the detail sheet, and this
    // dot sits a few hundred pixels below it — unresolved, the two would be different colours
    // for one meaning on one screen in dark mode.
    final accent = tones.resolve(complaintTone(event.status));
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The rail: a dot for this step and a line down to the next one.
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: Space.xxs),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    // The halo alpha comes from the measured chip recipe rather than the 0.35
                    // that was invented here: same tone, same decorative weight, one place.
                    border: Border.all(color: tones.chipBorder(accent), width: 3),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: Space.xxs),
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.status.label, style: t.textTheme.titleMedium),
                  const SizedBox(height: Space.xxs),
                  Text(
                    '${dayLabel(event.createdAt.toLocal())} · ${relativeTime(event.createdAt)}',
                    style: t.textTheme.labelSmall,
                  ),
                  if (event.note != null && event.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: Space.xxs),
                    Text(event.note!.trim(), style: t.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
