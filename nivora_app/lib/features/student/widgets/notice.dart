library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import 'common.dart';
import 'format.dart';

/// One notice from the owner.
///
/// THE AUDIENCE LABEL IS DESCRIPTION, NOT A FILTER. Which notices reach this device was decided
/// by the `announcements` select policy before the rows left Postgres — a resident gets the
/// ones addressed to everyone and the ones addressed to students, and nothing else. The chip
/// below only tells the reader which of those two they are looking at. Filtering on it here
/// would be decoration over a control that has already run, and would quietly start hiding rows
/// the day the policy changes.
class NoticeTile extends StatelessWidget {
  const NoticeTile({super.key, required this.notice, this.expanded = false});

  final Notice notice;

  /// True on the notices tab, where the whole notice is the point. False in the home summary,
  /// where two lines are enough to decide whether to open it.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final forStudentsOnly = notice.audience == NoticeAudience.students;
    return OutlineCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.campaign_rounded, size: IconSize.md, color: t.colorScheme.primary),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  notice.title,
                  style: t.textTheme.titleMedium,
                  maxLines: expanded ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (forStudentsOnly) ...[
                const SizedBox(width: Space.xs),
                StatusPill(label: 'For residents', tone: NivoraColors.info),
              ],
            ],
          ),
          const SizedBox(height: Space.xs),
          // SelectionArea so a resident can copy a phone number or a date out of a notice.
          SelectionArea(
            child: Text(
              notice.body.trim(),
              style: t.textTheme.bodyMedium,
              maxLines: expanded ? null : 2,
              overflow: expanded ? null : TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${dayLabel(notice.createdAt.toLocal())} · ${relativeTime(notice.createdAt)}',
            style: t.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
