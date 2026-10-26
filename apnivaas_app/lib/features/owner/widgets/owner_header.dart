library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/person_avatar.dart';
import '../../shell/staff_profile_sheet.dart';
import '../notices/owner_notices_screen.dart';
import '../owner_complaints_screen.dart';
import '../owner_format.dart';
import '../owner_insights.dart';
import '../owner_providers.dart';
import '../owner_tabs.dart';
import 'states.dart' show ErrorNote, whenAsync;

/// The name of the PG every owner screen is reading, or null while the owned list is in flight.
///
/// An owner whose users.hostel_id points at a PG they do not own can still read it
/// (app.can_read_hostel admits staff of a hostel), so the name comes from the hostel row itself
/// in that case rather than from the ownership list — and ONLY in that case, so an owner with
/// their own PGs never pays for a second read.
String? watchActiveHostelName(WidgetRef ref) {
  final activeId = ref.watch(activeHostelIdProvider);
  final list = ref.watch(myHostelsProvider).value;
  if (activeId == null || list == null) return null;
  for (final h in list) {
    if (h.id == activeId) return h.name;
  }
  return ref.watch(hostelProvider(activeId)).value?.name;
}

/// THE OWNER'S FOREST HEADER, one per tab, drawn by the shell above the tab body.
///
/// In the shell rather than inside each screen so it runs the full width of a tablet while the
/// body under it is held to [maxContentWidth], and so a tab switch changes the words in it rather
/// than sliding a second header in with the page.
///
/// Every tab leads with the owner's own initials, which open the account sheet — profile,
/// two-factor, password, deletion and sign out — exactly as the old masthead's avatar did, so
/// none of those moved further away. Home adds the greeting, the PG switcher, the activity bell
/// and the resident search; the other tabs name themselves and the PG they are reading.
class OwnerHeader extends ConsumerWidget {
  const OwnerHeader({super.key, required this.tab});

  final OwnerTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = MyHeaderAvatar(onTap: () => showStaffProfile(context));

    if (tab == OwnerTab.home) return _HomeHeader(avatar: avatar);

    final pg = watchActiveHostelName(ref);
    return switch (tab) {
      OwnerTab.money => AppHeader(title: 'Payments', subtitle: pg, leading: avatar),
      OwnerTab.people => AppHeader(title: 'Residents', subtitle: pg, leading: avatar),
      OwnerTab.property => AppHeader(
          title: 'Your PGs',
          subtitle: switch (ref.watch(myHostelsProvider).value?.length) {
            null || 0 => null,
            final n => '${countLabel(n, 'PG')} on your account',
          },
          leading: avatar,
        ),
      _ => AppHeader(title: 'More', subtitle: 'Team, money and your account', leading: avatar),
    };
  }
}

/// Home's header: who is reading, which PG the figures below belong to, and the two ways out
/// of the page that are not a section of it — the activity bell and the resident search.
class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({required this.avatar});

  final Widget avatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final activeId = ref.watch(activeHostelIdProvider);
    final list = ref.watch(myHostelsProvider).value;
    final pg = watchActiveHostelName(ref) ?? 'Your PG';
    // A single-PG owner gets a line of text, not a menu with one item in it.
    final several = list != null && list.length >= 2;

    return AppHeader(
      greeting: '${greetingFor(DateTime.now())}, ${firstName(session?.fullName)}',
      title: pg,
      leading: avatar,
      onTitleTap: several ? () => pickOwnerHostel(context, ref, list, activeId) : null,
      titleSemanticLabel: 'Current property: $pg. Tap to switch.',
      actions: [
        // NO BADGE, deliberately. The bell opens what happened lately; nothing in the schema
        // records what this owner has already looked at, so a count of "unread" would be a
        // number this app made up.
        HeaderIconButton(
          icon: Icons.notifications_none_rounded,
          label: 'Recent activity',
          onPressed: activeId == null ? null : () => showOwnerActivity(context, activeId),
        ),
      ],
      bottom: HeaderSearchPill(
        hint: 'Search residents by name or phone',
        onTap: () {
          ref.read(ownerSearchRequestProvider.notifier).request();
          ref.read(ownerTabProvider.notifier).go(OwnerTab.people);
        },
      ),
    );
  }
}

/// The forest header on a screen pushed over the shell: its name, the PG it is about, and the
/// way back.
class OwnerSubpageHeader extends StatelessWidget {
  const OwnerSubpageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;

  /// [HeaderIconButton]s at the trailing edge — "Assign a task".
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AppHeader(
        title: title,
        subtitle: subtitle,
        leading: const HeaderBackButton(),
        actions: actions,
      );
}

/// Which PG the owner screens read — for an owner with more than one.
Future<void> pickOwnerHostel(
  BuildContext context,
  WidgetRef ref,
  List<Hostel> hostels,
  String? activeId,
) async {
  final chosen = await showApnivaasSheet<String>(
    context: context,
    title: 'Your PGs',
    subtitle: 'Every screen shows the PG you pick here.',
    builder: (ctx) => SingleChildScrollView(
      child: ListGroup(
        children: [
          for (final h in hostels)
            ListRow(
              icon: ClayIcons.rooms,
              title: h.name,
              subtitle: h.address ?? '${h.totalRooms} rooms · ${h.totalFloors} floors',
              trailing: h.id == activeId
                  ? const StatusChip(label: 'Showing', tone: StatusTone.brand)
                  : null,
              showChevron: false,
              onTap: () => Navigator.of(ctx).pop(h.id),
            ),
        ],
      ),
    ),
  );
  if (chosen != null) {
    ref.read(selectedHostelIdProvider.notifier).select(chosen);
  }
}

/// What happened lately in this PG: complaints raised and notices posted, newest first.
///
/// Read from [ownerActivityProvider], which composes the two lists the complaints screen and the
/// noticeboard already read — so the bell cannot disagree with either of them, and opening it
/// costs nothing the dashboard's pull-to-refresh has not already accounted for.
Future<void> showOwnerActivity(BuildContext context, String hostelId) => showApnivaasSheet<void>(
      context: context,
      title: 'Recent activity',
      subtitle: 'Complaints and notices in this PG, newest first.',
      builder: (_) => _ActivitySheet(hostelId: hostelId),
    );

class _ActivitySheet extends ConsumerWidget {
  const _ActivitySheet({required this.hostelId});

  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(ownerActivityProvider(hostelId));
    return SingleChildScrollView(
      child: whenAsync(
        activity,
        loading: () => const ListSkeleton(rows: 3, semanticLabel: 'Loading recent activity'),
        error: (error) => ErrorNote(error: error, compact: true),
        data: (items) => items.isEmpty
            ? const EmptyState(
                compact: true,
                icon: ClayIcons.bell,
                title: 'Nothing has happened yet',
                body: 'Complaints residents raise and notices you post will show up here.',
              )
            : ListGroup(
                children: [
                  for (final item in items) _ActivityRow(item: item, hostelId: hostelId),
                ],
              ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.hostelId});

  final ActivityItem item;
  final String hostelId;

  @override
  Widget build(BuildContext context) {
    final complaint = item.kind == ActivityKind.complaint;
    final status = item.complaintStatus;
    return ListRow(
      icon: complaint ? ClayIcons.complaint : ClayIcons.announcement,
      title: item.title,
      subtitle: [?item.detail, relativeTime(item.at)].join(' · '),
      trailing: status == null
          ? null
          : StatusChip(
              label: status.label,
              tone: switch (status) {
                ComplaintStatus.open => StatusTone.warning,
                ComplaintStatus.inProgress => StatusTone.info,
                ComplaintStatus.resolved => StatusTone.success,
              },
            ),
      onTap: () {
        final navigator = Navigator.of(context);
        navigator.pop();
        navigator.push(
          complaint ? OwnerComplaintsScreen.route() : OwnerNoticesScreen.route(hostelId),
        );
      },
    );
  }
}

/// Space between a section's heading and what it heads, and between two sections, on every
/// owner page — one rhythm, so the pages read as one product.
abstract final class OwnerRhythm {
  static const headingGap = Space.sm;
  static const sectionGap = Space.xl;
  static const pagePadding = EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md, Space.huge);
}
