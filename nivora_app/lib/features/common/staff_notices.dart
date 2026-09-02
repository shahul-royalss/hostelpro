/// The noticeboard as STAFF read it — one set of rows, shared by the warden and the manager.
///
/// ── WHY THIS FILE EXISTS ─────────────────────────────────────────────────────────────────
///
/// Until it did, an owner notice addressed to `all` reached three of the four roles that are
/// supposed to get it. The resident had a Notices tab; the warden and the manager had nowhere
/// at all. `app.announcements_after_insert` still wrote them a `notifications` row — measured,
/// six rows for four notices — with `link` set to `/warden` and `/manager`, so the database was
/// pointing both of them at a screen that did not exist. This is that screen's content.
///
/// ── WHAT IS SHARED AND WHAT IS NOT ───────────────────────────────────────────────────────
///
/// Shared: the rows. A notice looks the same to a warden and to a manager because it IS the
/// same notice, and two hand-maintained copies of one card is how the two roles start
/// disagreeing about what a notice looks like.
///
/// Not shared: the chrome and the async states. `WardenScreen`/`ManagerScreen` and each kit's
/// own `AsyncSection`, `FailureState`/`FailureNote` and spinner belong to their roles and are
/// already tuned to them, so each screen wraps [StaffNoticeList] in its own. This file takes
/// data that has already resolved and nothing else.
///
/// ── THERE IS NO AUDIENCE FILTER HERE AND THERE MUST NOT BE ───────────────────────────────
///
/// `announcements_select` decided which rows reached this device before they left Postgres: a
/// warden gets `all` and `warden`, a manager gets `all` and `manager`, and neither gets the
/// other's. Measured against the live tenant with one notice per audience: warden 2, manager 2,
/// resident 2, owner 4. A second filter in Dart would be a copy of a control that has already
/// run, and the day the policy changes is the day the copy silently hides rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/session.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';

/// When a notice was posted, in the shortest form that is still exact.
///
/// A FOURTH FORMATTER, AND KNOWINGLY SO. `owner_format.dart`, `student/widgets/format.dart` and
/// `super_admin/widgets/sa_ui.dart` each already carry a `relativeTime`, and each is reachable
/// only from its own role's screens. Importing one of them into a file the warden and the
/// manager share would make this feature depend on the owner's or the resident's presentation
/// layer to draw a date. The three older copies are not this change's to merge.
String noticePostedLabel(DateTime when, {DateTime? now}) {
  final at = when.toLocal();
  final from = now ?? DateTime.now();
  final gap = from.difference(at);
  // A negative gap means the device clock is behind the server's. "just now" rather than
  // "in 3 minutes", which reads as a bug in the app rather than in the clock.
  if (gap.isNegative || gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes}m ago';
  if (gap.inHours < 24) return '${gap.inHours}h ago';
  if (gap.inDays < 7) return '${gap.inDays}d ago';
  return DateFormat('d MMM').format(at);
}

/// One notice, as a member of staff reads it.
///
/// THE AUDIENCE IS NAMED, NOT FILTERED ON. A warden looking at a `warden` notice and a warden
/// looking at an `all` notice are in genuinely different situations — the first is a message to
/// them, the second is something the whole hostel has also been told, and a warden who does not
/// know which of those they are reading will re-announce a notice everyone already has. The
/// chip is that distinction and nothing more.
class StaffNoticeCard extends StatelessWidget {
  const StaffNoticeCard({super.key, required this.notice, required this.viewerRole});

  final Notice notice;

  /// Used only to word the chip — "For you" reads better on a notice addressed to this role
  /// alone than the enum's own plural does. It decides nothing about visibility.
  final UserRole viewerRole;

  bool get _addressedToThisRoleAlone => switch (notice.audience) {
        NoticeAudience.all => false,
        NoticeAudience.warden => viewerRole == UserRole.warden,
        NoticeAudience.manager => viewerRole == UserRole.manager,
        NoticeAudience.students => viewerRole == UserRole.student,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    // `all` is the quieter one on purpose: it is the ordinary case. A notice sent to this role
    // alone is the one worth catching an eye, so it carries the accent.
    final tone = tones.resolve(
      _addressedToThisRoleAlone ? NivoraColors.info : t.colorScheme.outline,
    );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(Space.xs),
                decoration: BoxDecoration(
                  color: tones.chipFill(tone),
                  borderRadius: Radii.rControl,
                ),
                child: Icon(Icons.campaign_rounded, size: IconSize.xs, color: tone),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: Space.xxs),
                  child: Text(
                    notice.title,
                    style: t.textTheme.titleMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          // SelectionArea so a phone number or a date can be copied out of a notice.
          SelectionArea(
            child: Text(notice.body.trim(), style: t.textTheme.bodyMedium),
          ),
          const SizedBox(height: Space.sm),
          // Wrap, not Row: two labels of unknown length in one row is a layout that survives
          // until someone turns their text size up.
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(noticePostedLabel(notice.createdAt), style: t.textTheme.labelSmall),
              if (_addressedToThisRoleAlone)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.xs,
                    vertical: Space.xxs / 2,
                  ),
                  decoration: BoxDecoration(
                    color: tones.chipFill(tone),
                    borderRadius: Radii.rTiny,
                    border: Border.all(
                      color: tones.chipBorder(tone),
                      width: Strokes.hairline,
                    ),
                  ),
                  child: Text(
                    'For you',
                    style: t.textTheme.labelSmall?.copyWith(color: tone),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A resolved page of notices, drawn. The caller owns the loading and failure states.
///
/// [scrollable] false embeds the rows inside a home screen's own ListView, where a nested
/// scroll view would fight the page for the gesture.
class StaffNoticeList extends ConsumerWidget {
  const StaffNoticeList({
    super.key,
    required this.hostelId,
    required this.page,
    required this.viewerRole,
    this.limit,
    this.scrollable = true,
    this.emptyMessage,
  });

  final String hostelId;
  final PagedResult<Notice> page;
  final UserRole viewerRole;

  /// Draw at most this many rows — the home screen's peek. Null draws the whole page.
  final int? limit;
  final bool scrollable;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);

    if (page.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(scrollable ? Space.md : 0),
        child: Text(
          emptyMessage ??
              'No notices yet. Anything the owner posts to this hostel appears here.',
          style: t.textTheme.bodySmall,
        ),
      );
    }

    final items = limit == null || limit! >= page.items.length
        ? page.items
        : page.items.take(limit!).toList(growable: false);

    final rows = <Widget>[
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: Space.sm),
        StaffNoticeCard(notice: items[i], viewerRole: viewerRole),
      ],
      // Only on the full screen, and only when the SERVER said there was more — never derived
      // from the row count, which would offer "older notices" on a hostel that has twenty and
      // no more.
      if (scrollable && page.hasMore) ...[
        const SizedBox(height: Space.sm),
        _LoadMore(hostelId: hostelId),
      ],
    ];

    if (!scrollable) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    }
    return ListView(
      padding: const EdgeInsets.all(Space.md),
      physics: const AlwaysScrollableScrollPhysics(),
      children: rows,
    );
  }
}

/// Appends the next page, and says so when it could not.
class _LoadMore extends ConsumerStatefulWidget {
  const _LoadMore({required this.hostelId});
  final String hostelId;

  @override
  ConsumerState<_LoadMore> createState() => _LoadMoreState();
}

class _LoadMoreState extends ConsumerState<_LoadMore> {
  bool _busy = false;
  String? _message;

  Future<void> _more() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final failure = await ref.read(noticesProvider(widget.hostelId).notifier).loadMore();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = failure?.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: _busy ? null : _more,
          child: _busy
              ? const SizedBox(
                  height: IconSize.md,
                  width: IconSize.md,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Show older notices'),
        ),
        // A control that fails says so where it was tapped. Without this the button was one
        // that visibly did nothing — the exact shape of bug the house rule forbids.
        if (_message != null) ...[
          const SizedBox(height: Space.xs),
          Text(
            _message!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
