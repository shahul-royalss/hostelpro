library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
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
    return StudentPagedList<Notice>(
      value: ref.watch(provider),
      onRefresh: () async {
        ref.invalidate(provider);
        try {
          await ref.read(provider.future);
        } catch (_) {
          // The section draws its own failure state. Letting this escape would leave the
          // refresh spinner turning forever.
        }
      },
      onLoadMore: () => ref.read(provider.notifier).loadMore(),
      empty: const EmptyNote(
        icon: Icons.campaign_outlined,
        title: 'No notices yet',
        message: 'Announcements from the hostel owner appear here.',
        tone: NivoraColors.textMuted,
      ),
      itemBuilder: (_, notice) => NoticeTile(notice: notice, expanded: true),
    );
  }
}
