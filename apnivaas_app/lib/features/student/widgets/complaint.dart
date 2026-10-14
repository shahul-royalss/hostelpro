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
    // The design's activity row: a round tinted glyph, then the text, then the timestamp.
    //
    // THE GLYPH SAYS THE CATEGORY AND THE TINT SAYS THE STATUS, which is exactly what the
    // mockups' own rows do (`bg-error/10 text-error` behind a wrench). The two are different
    // facts and neither replaces the other — the status is still spelled out in a WORD by the
    // pill on the footer line, because a row that distinguished open from resolved by hue alone
    // would be unreadable to the ~8% of men with a red-green deficiency, several per floor in a
    // full boys' PG.
    return OutlineCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToneBadge(icon: complaintIcon(complaint.category), tone: tone),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // Centres a one-line title against the badge beside it.
                  padding: const EdgeInsets.only(top: Space.xxs),
                  child: Text(
                    complaint.title,
                    style: t.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (complaint.description != null &&
                    complaint.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: Space.xxs),
                  Text(
                    complaint.description!.trim(),
                    style: t.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: Space.xs),
                // The status WORD sits on the footer beside the category and the age, rather
                // than opposite the title. A title of unknown length and a pill of unknown
                // length sharing one row is a layout with a breaking point — measured, this one
                // was 320dp at 1.6x — and a Wrap has none. Nothing is lost: the badge at the
                // head of the row already carries the status COLOUR, and this is the word it
                // stands for, which is the half that has to survive a red-green deficiency.
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${complaint.category.label} · raised ${relativeTime(complaint.createdAt)}',
                      style: t.textTheme.labelSmall,
                    ),
                    StatusPill(label: complaint.status.label, tone: tone),
                  ],
                ),
              ],
            ),
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
      // Compact: this sits directly under the sheet's own "PROGRESS" label, and the design's
      // raised state card there would be a card announcing a heading that has already been
      // read. The full card is for a state that IS the screen.
      return const EmptyNote(
        icon: Icons.timeline_rounded,
        title: 'No updates yet',
        message: 'You will see every status change here as your warden works on it.',
        compact: true,
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

  /// The rail's geometry, composed from the spacing scale rather than typed in as pixels.
  /// There is no token named "timeline dot" and there should not be — this is one widget's
  /// construction, and what the rule protects is that the numbers come from the ramp.
  static const _rail = Space.lg; // 20 — the column the dot and the thread share
  static const _dot = Space.sm; // 12 — the marker for one step
  static const _halo = Space.xxs; // 4  — the tinted ring, painted inside the dot
  static const _thread = Strokes.hairline * 2; // the line down to the next step

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
            width: _rail,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: Space.xxs),
                  width: _dot,
                  height: _dot,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    // The halo alpha comes from the measured chip recipe rather than the 0.35
                    // that was invented here: same tone, same decorative weight, one place.
                    border: Border.all(color: tones.chipBorder(accent), width: _halo),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: _thread,
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
