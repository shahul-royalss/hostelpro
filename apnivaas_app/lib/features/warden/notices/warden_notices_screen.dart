library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../../common/refresh.dart';
import '../../common/staff_notices.dart';
import '../widgets/warden_ui.dart';

/// What the owner has told this hostel — the warden's half of it.
///
/// READS: public.announcements, through `noticesProvider`. `announcements_select` returns a
/// warden the notices addressed to everyone and the ones addressed to wardens, and nothing
/// else; measured on the live tenant as 2 of 4 with one notice posted per audience. There is no
/// audience filter in this file. See features/common/staff_notices.dart.
///
/// PUSHED, NOT A TAB. The warden's five slots are declared in features/shell/role_shell.dart
/// and mirrored in warden_shell.dart, and those two files agreeing is what keeps a tap landing
/// where its label says. A sixth destination is a change to the warden's navigation, which is
/// not this feature's to make; the home screen's Notices section is the way in.
///
/// THE HEADER IS THE PUSHED-SCREEN ONE (a leading back button in a [GlassHeader]), not
/// [WardenScreen]. WardenScreen's `actions` slot is on the RIGHT, which is where a screen's
/// verbs go — putting Back there would be the one control on the page that does not do
/// something to the page. OwnerPgDetailScreen sets the same shape for the same reason.
class WardenNoticesScreen extends ConsumerWidget {
  const WardenNoticesScreen({super.key, required this.hostelId});

  static Route<void> route(String hostelId) => MaterialPageRoute<void>(
        builder: (_) => WardenNoticesScreen(hostelId: hostelId),
      );

  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final provider = noticesProvider(hostelId);
    final notices = ref.watch(provider);
    final hostel = ref.watch(hostelProvider(hostelId));

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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Notices',
                        style: t.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hostel.value?.name != null)
                        Text(
                          hostel.value!.name,
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
              // BOUNDED. A bare `await ref.read(provider.future)` has no deadline, and
              // riverpod 3 retries a failed provider ten times behind a future it does not
              // complete — which is how a spinner ends up turning for two minutes on a hostel
              // Wi-Fi that has stopped answering. See features/common/refresh.dart.
              onRefresh: () {
                ref.invalidate(provider);
                return settleRefresh(context, () => ref.read(provider.future));
              },
              child: AsyncSection<PagedResult<Notice>>(
                value: notices,
                onRetry: () => ref.invalidate(provider),
                loading: const _NoticesSkeleton(),
                builder: (page) => StaffNoticeList(
                  hostelId: hostelId,
                  page: page,
                  viewerRole: UserRole.warden,
                  emptyMessage: 'No notices yet. Anything the owner posts to this hostel — to '
                      'everyone, or to the warden — appears here.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three notice-shaped blocks. A skeleton keeps the layout the reader already knows instead of
/// replacing it with a spinner in a void.
class _NoticesSkeleton extends StatelessWidget {
  const _NoticesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Space.md),
      children: const [
        SkeletonBlock(lines: 3),
        SizedBox(height: Space.sm),
        SkeletonBlock(lines: 3),
        SizedBox(height: Space.sm),
        SkeletonBlock(lines: 3),
      ],
    );
  }
}
