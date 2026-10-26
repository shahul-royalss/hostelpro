library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/models.dart';
import '../../../shared/clay/clay.dart';
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
  const NoticeTile({super.key, required this.notice, this.author, this.expanded = false});

  /// Who wrote it, when it could be resolved. Null renders the post without a byline rather
  /// than with a placeholder: an author whose account has since been removed, or a notice read
  /// while [noticeAuthorsProvider] is still in flight, is still a notice worth reading.

  final Notice notice;
  final NoticeAuthor? author;

  /// True on the notices tab, where the whole notice is the point. False in the home summary,
  /// where two lines are enough to decide whether to open it.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final forStudentsOnly = notice.audience == NoticeAudience.students;
    final muted = t.colorScheme.onSurfaceVariant;
    final meta = t.textTheme.bodySmall?.copyWith(color: muted);
    // A notice is a post: who said it, what they said, and when. One card per notice, the same
    // flat card every list in the app sits on — no colour per notice, because a hue that
    // changed row to row would be a status code nobody had defined. The one real distinction a
    // notice carries — who it is addressed to — is said in a word, by the chip at its foot.
    return OutlineCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── THE BYLINE ────────────────────────────────────────────────────────────────
          // The shape a reader already knows from every social app: a face, a name, and when.
          // The face is the author's initials; with no author resolved yet, the megaphone
          // stands in its place and the post reads as the hostel's.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (author != null)
                InitialsDisc(name: author!.fullName)
              else
                const ClayIcon(ClayIcons.announcement, size: ClaySize.list),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      author?.fullName ?? 'Your hostel',
                      style: t.textTheme.titleSmall?.copyWith(fontFeatures: const []),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Space.hair),
                    Row(
                      children: [
                        if (author?.role != null) ...[
                          Text(author!.role!.label, style: meta),
                          Text(' · ', style: meta),
                        ],
                        Flexible(
                          child: Text(
                            relativeTime(notice.createdAt),
                            style: meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            notice.title,
            style: context.textRoles.tileTitle,
            maxLines: expanded ? 3 : 2,
            overflow: TextOverflow.ellipsis,
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
          const SizedBox(height: Space.sm),
          // "Posted 2 hours ago by Aarthi" is built from public.notice_authors(), a SECURITY
          // DEFINER read gated on the same app.can_read_hostel() predicate the announcements
          // select policy uses — a resident still cannot read public.users, and this returns a
          // name and a role for the authors of notices they can already see, and no contact
          // details.
          //
          // The date stays in the footer even though the byline above carries the relative
          // time: "3d ago" is what you want while scanning, and the actual date is what you
          // want when you are checking whether a notice still applies.
          //
          // The audience chip sits HERE and not up beside the title. Two labels of unknown
          // length competing for one row is a layout that works until someone turns their
          // text up; a Wrap cannot overflow — the chip drops under the date — and the footer
          // is where "when, and who for" belong together anyway.
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(dayLabel(notice.createdAt.toLocal()), style: meta),
              if (forStudentsOnly)
                const StatusPill(label: 'For residents', tone: ApnivaasColors.info),
            ],
          ),
        ],
      ),
    );
  }
}
