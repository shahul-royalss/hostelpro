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
import '../widgets/manager_ui.dart';

/// What the owner has told this hostel — the manager's half of it.
///
/// READS: public.announcements, through `noticesProvider`. `announcements_select` returns a
/// manager the notices addressed to everyone and the ones addressed to managers, and nothing
/// else; measured on the live tenant as 2 of 4 with one notice posted per audience. There is no
/// audience filter in this file. See features/common/staff_notices.dart.
///
/// PUSHED, NOT A TAB. The manager's four slots are declared in features/shell/role_shell.dart
/// and mirrored in manager_shell.dart; those two agreeing is what keeps a tap landing where its
/// label says, and a fifth destination is a change to the manager's navigation rather than to
/// this feature. The home screen's Notices section is the way in.
class ManagerNoticesScreen extends ConsumerWidget {
  const ManagerNoticesScreen({super.key, required this.hostelId});

  static Route<void> route(String hostelId) => MaterialPageRoute<void>(
        builder: (_) => ManagerNoticesScreen(hostelId: hostelId),
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
                          style: t.textTheme.bodySmall
                              ?.copyWith(color: context.tones.muted),
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
              // BOUNDED — see features/common/refresh.dart.
              onRefresh: () {
                ref.invalidate(provider);
                return settleRefresh(context, () => ref.read(provider.future));
              },
              child: AsyncSection<PagedResult<Notice>>(
                value: notices,
                onRetry: () => ref.invalidate(provider),
                builder: (page) => StaffNoticeList(
                  hostelId: hostelId,
                  page: page,
                  viewerRole: UserRole.manager,
                  emptyMessage: 'No notices yet. Anything the owner posts to this hostel — to '
                      'everyone, or to the manager — appears here.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
