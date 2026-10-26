library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/clay/clay.dart' show AppHeader, HeaderBackButton, ListSkeleton;
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
/// THE HEADER IS THE PUSHED-SCREEN ONE: the clay forest [AppHeader] with a back button at its
/// leading edge, not [WardenScreen]. WardenScreen's `actions` slot is on the RIGHT, which is
/// where a screen's verbs go — putting Back there would be the one control on the page that
/// does not do something to the page. OwnerPgDetailScreen sets the same shape for the same
/// reason.
class WardenNoticesScreen extends ConsumerWidget {
  const WardenNoticesScreen({super.key, required this.hostelId, this.viewerRole = UserRole.warden});

  /// Also the manager's noticeboard (their header bell): the rows are the same, only the
  /// audience filter differs — see features/common/staff_notices.dart.
  static Route<void> route(String hostelId, {UserRole viewerRole = UserRole.warden}) =>
      MaterialPageRoute<void>(
        builder: (_) => WardenNoticesScreen(hostelId: hostelId, viewerRole: viewerRole),
      );

  final String hostelId;
  final UserRole viewerRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = noticesProvider(hostelId);
    final notices = ref.watch(provider);
    final hostel = ref.watch(hostelProvider(hostelId));

    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            title: 'Notices',
            // Which PG's board this is, once the hostel row is in; nothing rather than a
            // placeholder until then.
            subtitle: hostel.value?.name,
            leading: const HeaderBackButton(),
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
                  viewerRole: viewerRole,
                  emptyMessage: 'No notices yet. Anything the owner posts to this hostel — to '
                      'everyone, or to the ${viewerRole == UserRole.manager ? 'manager' : 'warden'} '
                      '— appears here.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The board's shape before it lands: rows in one card, under one pulse — a skeleton keeps the
/// layout the reader already knows instead of replacing it with a spinner in a void.
class _NoticesSkeleton extends StatelessWidget {
  const _NoticesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Space.md),
      children: const [ListSkeleton(rows: 4, semanticLabel: 'Loading notices')],
    );
  }
}
