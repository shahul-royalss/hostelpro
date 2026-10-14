library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../common/refresh.dart';
import '../../shared/illustrations.dart';
import 'widgets/common.dart';
import 'widgets/notice.dart';
import 'widgets/paged_list.dart';

/// The noticeboard, as a resident sees it.
///
/// READS: public.announcements, through `noticesProvider` → `NoticeRepository.page`.
///
/// There is no audience filter in this file and there must not be one. The select policy
/// already returns a student the notices addressed to everyone and the ones addressed to
/// students, and nothing else. A second filter here would be a copy of a control that has
/// already run — and the day the policy changes, the copy is what would silently hide rows.
class StudentNoticesScreen extends StatelessWidget {
  const StudentNoticesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResidentBuilder(
      builder: (context, ref, me) => _Notices(hostelId: me.hostelId),
    );
  }
}

class _Notices extends ConsumerWidget {
  const _Notices({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = noticesProvider(hostelId);
    // The names arrive separately from the rows and are allowed to be late: `.value` rather
    // than a watch that could hold the list behind a second request. A notice renders without
    // a byline for the moment before the map lands, and gains one when it does.
    final authors = ref.watch(noticeAuthorsProvider(hostelId)).value;
    return StudentPagedList<Notice>(
      value: ref.watch(provider),
      // BOUNDED. The bare `await ref.read(provider.future)` had no deadline, and riverpod 3
      // retries a failed provider ten times behind a future it does not complete — so a
      // resident on a hostel Wi-Fi that had stopped answering held this spinner for over two
      // minutes. See features/common/refresh.dart.
      onRefresh: () {
        ref.invalidate(provider);
        return settleRefresh(context, () => ref.read(provider.future));
      },
      onLoadMore: () => ref.read(provider.notifier).loadMore(),
      // No tone: an empty noticeboard is neither good news nor bad, and [EmptyNote]'s
      // untinted glyph is the design's own neutral outline for exactly that case.
      empty: const EmptyNote(
        illustration: EmptyArt.notices,
        icon: Icons.campaign_outlined,
        title: 'No notices yet',
        message: 'Announcements from the hostel owner appear here.',
      ),
      itemBuilder: (_, notice) => NoticeTile(
        notice: notice,
        author: authors?[notice.authorUserId],
        expanded: true,
      ),
    );
  }
}
