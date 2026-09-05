library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';
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
    // The mockups draw a notice as an accented card led by a tinted glyph. The rail is `primary`
    // on every notice and the glyph is the NOTICES domain on every notice — one colour each,
    // never a colour per notice: a hue that changed row to row would be a status code nobody had
    // defined, and which notices reach this device was already decided by the select policy. The
    // one real distinction the row carries — who the notice is addressed to — is said in a word,
    // by the pill. The blue megaphone is the same mark that heads the Notices section on Home
    // and lights the Notices tab, which is what makes a notice recognisably a notice wherever it
    // turns up. See [NivoraDomain].
    return OutlineCard(
      accent: t.colorScheme.primary,
      // The rail eats into the leading edge, so the content is inset past it rather than
      // starting under it.
      padding: const EdgeInsets.fromLTRB(Space.md + Space.xs, Space.md, Space.md, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── THE BYLINE ────────────────────────────────────────────────────────────────
          // A notice is somebody in the building saying something, and until now it read as a
          // system message from nobody. The author line is the post's header, in the shape a
          // reader already knows from every social app: a face, a name, and when.
          //
          // The face is the author's initials disc, NOT the notices megaphone. The megaphone
          // moved to a small mark beside the timestamp — it still says "this is a notice"
          // wherever the card turns up, which is the job it was doing, but it is no longer
          // occupying the position a reader looks at to find out WHO.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (author != null) ...[
                InitialsAvatar(name: author!.fullName, size: Space.xl + Space.xxs),
                const SizedBox(width: Space.sm),
              ] else ...[
                const DomainIcon(
                  domain: NivoraDomain.notices,
                  icon: Icons.campaign_rounded,
                  size: DomainIconSize.sm,
                ),
                const SizedBox(width: Space.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      author?.fullName ?? 'Your hostel',
                      style: t.textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Space.xxs),
                    Row(
                      children: [
                        if (author?.role != null) ...[
                          Text(author!.role!.label, style: t.textTheme.labelSmall),
                          Text(' · ', style: t.textTheme.labelSmall),
                        ],
                        Flexible(
                          child: Text(
                            relativeTime(notice.createdAt),
                            style: t.textTheme.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (author != null) ...[
                const SizedBox(width: Space.xs),
                Icon(Icons.campaign_rounded,
                    size: IconSize.sm, color: t.colorScheme.primary),
              ],
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            notice.title,
            style: t.textTheme.titleMedium,
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
          // "Posted 2 hours ago by Aarthi" is now built. It took public.notice_authors(), a
          // SECURITY DEFINER read gated on the same app.can_read_hostel() predicate the
          // announcements select policy uses — a resident still cannot read public.users, and
          // this returns a name and a role for the authors of notices they can already see,
          // and no contact details. The old note here said the name "is not built"; it was
          // right about why, and the answer was a narrow exception rather than a wider policy.
          //
          // The date stays in the footer even though the byline above carries the relative
          // time: "3d ago" is what you want while scanning, and the actual date is what you
          // want when you are checking whether a notice still applies.
          //
          // The audience pill sits HERE and not up beside the title, which is where it used to
          // be. Two labels of unknown length competing for one row is a layout that works until
          // someone turns their text up: measured at 320dp and 1.3x, "FOR RESIDENTS" and a
          // three-line title overran the card. A Wrap cannot overflow — the pill drops under the
          // timestamp — and the footer is where "when, and who for" belong together anyway.
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(dayLabel(notice.createdAt.toLocal()), style: t.textTheme.labelSmall),
              if (forStudentsOnly)
                const StatusPill(label: 'For residents', tone: NivoraColors.info),
            ],
          ),
        ],
      ),
    );
  }
}
