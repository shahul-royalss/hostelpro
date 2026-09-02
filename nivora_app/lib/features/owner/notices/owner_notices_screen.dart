library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../../../shared/illustrations.dart';
import '../owner_format.dart';
import '../owner_providers.dart';
import '../widgets/states.dart';
import 'compose_notice_sheet.dart';
import 'notice_providers.dart';

/// Everything the owner has posted to one PG, newest first, with a way to write another and a
/// way to take one back.
///
/// READS: public.announcements, through `noticesProvider` → `NoticeRepository.page` — the same
/// provider the resident's notices tab watches. The owner sees more rows than a resident does,
/// and NOT because this screen asks differently: `announcements_select` admits an owner to
/// every audience in their own hostel and a resident to `all` and `students` only. Measured on
/// the live tenant, four notices posted one per audience: owner 4, manager 2 (all + manager),
/// warden 2 (all + warden), resident 2 (all + students). There is no audience filter in this
/// file and there must not be one.
///
/// WHAT "DELETE" MEANS HERE. `deleted_at` is stamped; the row stays. The notice leaves every
/// noticeboard at once because the select policy excludes soft-deleted rows for everybody,
/// owner included — so this screen cannot show the owner what they retracted, and does not
/// pretend to. What it CANNOT take back is the notification: the fan-out already happened, on
/// insert, and those rows are not deleted with it. The confirm dialog says so, because an owner
/// who thinks retracting un-rings the bell will retract instead of posting a correction.
class OwnerNoticesScreen extends ConsumerWidget {
  const OwnerNoticesScreen({super.key, required this.hostelId});

  /// Pushed rather than given a tab. The owner's five slots are spoken for in
  /// features/shell/role_shell.dart, which is shared with every other role and is the file a
  /// reader goes to to learn what a role's navigation is — quietly renaming one of its labels
  /// from inside the notices feature is how two files start disagreeing about which tab is
  /// third. The dashboard's own Notices section is the way in.
  static Route<void> route(String hostelId) => MaterialPageRoute<void>(
        builder: (_) => OwnerNoticesScreen(hostelId: hostelId),
      );

  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final hostel = ref.watch(hostelProvider(hostelId));
    final notices = ref.watch(noticesProvider(hostelId));

    return Scaffold(
      body: Column(
        children: [
          GlassHeader(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: Space.xxs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notices',
                        style: t.textTheme.titleLarge?.copyWith(color: t.colorScheme.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        hostel.value?.name ?? 'PG',
                        style: t.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(noticesProvider(hostelId));
                try {
                  await ref.read(noticesProvider(hostelId).future).timeout(ownerRefreshTimeout);
                } catch (_) {
                  // Rendered by the body below; rethrowing would make it unhandled.
                }
              },
              child: whenAsync(
                notices,
                loading: () => ListView(
                  padding: const EdgeInsets.all(Space.md),
                  children: const [
                    SkeletonCard(),
                    SizedBox(height: Space.sm),
                    SkeletonCard(),
                    SizedBox(height: Space.sm),
                    SkeletonCard(),
                  ],
                ),
                error: (error) => ListView(
                  padding: const EdgeInsets.all(Space.md),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    ErrorNote(
                      error: error,
                      onRetry: () => ref.invalidate(noticesProvider(hostelId)),
                    ),
                  ],
                ),
                data: (page) => _NoticeList(
                  hostelId: hostelId,
                  hostelName: hostel.value?.name,
                  page: page,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showComposeNoticeSheet(
          context,
          hostelId: hostelId,
          hostelName: hostel.value?.name,
        ),
        icon: const Icon(Icons.campaign_rounded),
        label: const Text('New notice'),
      ),
    );
  }
}

class _NoticeList extends ConsumerWidget {
  const _NoticeList({required this.hostelId, required this.hostelName, required this.page});

  final String hostelId;
  final String? hostelName;
  final PagedResult<Notice> page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (page.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(Space.md),
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          // No tone. An empty noticeboard is neither good news nor bad — it is a PG where
          // nothing has needed saying yet.
          EmptyNote(
            icon: Icons.campaign_outlined,
            illustration: EmptyArt.notices,
            title: 'No notices yet',
            message: 'Write one and it goes out to whoever you address it to, with a '
                'notification, straight away.',
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge * 2),
      physics: const AlwaysScrollableScrollPhysics(),
      // One extra row at the end when the server said there was more, so a long noticeboard
      // pages rather than stopping silently at twenty.
      itemCount: page.items.length + (page.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, i) {
        if (i >= page.items.length) {
          return _LoadMore(hostelId: hostelId);
        }
        return OwnerNoticeCard(notice: page.items[i], hostelId: hostelId);
      },
    );
  }
}

class _LoadMore extends ConsumerStatefulWidget {
  const _LoadMore({required this.hostelId});
  final String hostelId;

  @override
  ConsumerState<_LoadMore> createState() => _LoadMoreState();
}

class _LoadMoreState extends ConsumerState<_LoadMore> {
  bool _busy = false;
  AppFailure? _failure;

  Future<void> _more() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final failure = await ref.read(noticesProvider(widget.hostelId).notifier).loadMore();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    // A control that can fail says so where it was tapped, rather than leaving a button that
    // visibly does nothing.
    if (_failure != null) {
      return ErrorNote(error: _failure!, compact: true, onRetry: _more);
    }
    return Center(
      child: TextButton(
        onPressed: _busy ? null : _more,
        child: _busy
            ? const SizedBox(
                height: IconSize.md,
                width: IconSize.md,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Show older notices'),
      ),
    );
  }
}

/// One posted notice, as its author sees it.
///
/// DIFFERENT FROM THE RESIDENT'S TILE ON PURPOSE. `student/widgets/notice.dart` labels a notice
/// only when it is residents-only, because a resident is looking at their own two audiences and
/// the distinction that matters to them is "is this just for us". The owner is looking at four,
/// and WHO THEY SENT IT TO is the first thing they need to check — so the audience is always
/// named here, and it is the row's colour as well as its word.
///
/// PUBLIC because owner_notices_test.dart drives the retraction through it.
class OwnerNoticeCard extends ConsumerStatefulWidget {
  const OwnerNoticeCard({super.key, required this.notice, required this.hostelId});

  final Notice notice;
  final String hostelId;

  @override
  ConsumerState<OwnerNoticeCard> createState() => _OwnerNoticeCardState();
}

class _OwnerNoticeCardState extends ConsumerState<OwnerNoticeCard> {
  bool _busy = false;
  AppFailure? _failure;

  /// The audience's colour. Not decoration: `all` is the loud one — it reaches residents AND
  /// both staff — and a staff-only notice is the quiet one. Canonical tones, resolved at the
  /// paint site by StatusChip. See tokens.dart.
  Color get _tone => switch (widget.notice.audience) {
        NoticeAudience.all => NivoraColors.success,
        NoticeAudience.students => NivoraColors.info,
        NoticeAudience.warden => NivoraColors.warning,
        NoticeAudience.manager => NivoraColors.warning,
      };

  String get _audienceLabel => switch (widget.notice.audience) {
        NoticeAudience.all => 'Everyone',
        NoticeAudience.students => 'Residents only',
        NoticeAudience.warden => 'Warden only',
        NoticeAudience.manager => 'Manager only',
      };

  Future<void> _retract() async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Take this notice down?'),
        content: Text(
          'It leaves every noticeboard straight away, including yours.\n\n'
          'The notification has already been delivered and this does not recall it. If people '
          'need to know something has changed, post a new notice saying so.',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Take it down'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      await ref.read(noticeWritesProvider).softDelete(noticeId: widget.notice.id);
      if (!mounted) return;
      // The row is gone from the server's answer, so the list has to be re-asked — this widget
      // is about to be disposed by that invalidation, which is why _busy is never cleared on
      // the success path and why nothing is drawn after it.
      ref.invalidate(noticesProvider(widget.hostelId));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = AppFailure.from(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final notice = widget.notice;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ToneBadge(icon: Icons.campaign_rounded, tone: _tone, tinted: true),
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
              const SizedBox(width: Space.xs),
              // Disabled rather than hidden while a retraction is in flight: a control that
              // vanishes mid-tap is a control the owner will go looking for.
              IconButton(
                tooltip: 'Take this notice down',
                onPressed: _busy ? null : _retract,
                icon: _busy
                    ? const SizedBox(
                        height: IconSize.md,
                        width: IconSize.md,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          SelectionArea(
            child: Text(notice.body.trim(), style: t.textTheme.bodyMedium),
          ),
          const SizedBox(height: Space.sm),
          // Wrap, not Row: two labels of unknown length in one row is a layout that works
          // until someone turns their text up. Same reasoning as the resident's tile.
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(label: _audienceLabel, tone: _tone, dot: true),
              Text(
                '${dayLabel(notice.createdAt.toLocal())} · '
                '${relativeTime(notice.createdAt)}',
                style: t.textTheme.labelSmall,
              ),
            ],
          ),
          if (_failure != null) ...[
            const SizedBox(height: Space.sm),
            ErrorNote(error: _failure!, compact: true, onRetry: _retract),
          ],
        ],
      ),
    );
  }
}
