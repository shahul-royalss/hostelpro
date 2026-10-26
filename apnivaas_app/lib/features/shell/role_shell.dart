import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/version/update_banner.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay_icons.dart';
import '../../shared/clay/nav_bar.dart';
import '../manager/manager_shell.dart';
import '../super_admin/sa_shell.dart';
import '../warden/warden_shell.dart';
import '../owner/owner_tabs.dart';
import '../owner/widgets/owner_header.dart';
import '../student/student_section.dart';
import '../student/widgets/format.dart' show firstName, greetingFor;
import '../../data/people_providers.dart';
import '../../shared/clay/app_header.dart';
import '../../shared/person_avatar.dart';
import 'staff_profile_sheet.dart';

/// Per-role navigation. Each role gets the tabs its job needs — the brief's point that forcing
/// every role through one navigation is what makes an operational tool feel generic.
///
/// This list is the readable index of every role's bar. Only the OWNER and the RESIDENT are drawn
/// from it here; the other three roles own their shells (see [_RoleShellState._shell]) and keep
/// their own copies of these labels.
final _tabs = <UserRole, List<({String label, IconData icon})>>{
  // The owner's labels come from [OwnerTab], so the bar and the bodies behind it are one list.
  // The glyph is unused: both bars this shell draws take clay art from [_artOfTab].
  UserRole.owner: [for (final t in ownerTabs) (label: t.label, icon: Icons.circle_outlined)],
  UserRole.warden: [
    (label: 'Home', icon: Icons.home_rounded),
    (label: 'Students', icon: Icons.people_alt_rounded),
    (label: 'Rooms', icon: Icons.meeting_room_rounded),
    (label: 'Payments', icon: Icons.payments_rounded),
    (label: 'Complaints', icon: Icons.report_problem_rounded),
  ],
  UserRole.student: [
    (label: 'Home', icon: Icons.home_rounded),
    (label: 'Fees', icon: Icons.receipt_long_rounded),
    (label: 'Complaints', icon: Icons.report_problem_rounded),
    (label: 'Notices', icon: Icons.campaign_rounded),
    (label: 'Profile', icon: Icons.person_rounded),
  ],
  UserRole.manager: [
    (label: 'Home', icon: Icons.home_rounded),
    (label: 'Expenses', icon: Icons.trending_down_rounded),
    (label: 'Tasks', icon: Icons.checklist_rounded),
    (label: 'Menu', icon: Icons.restaurant_rounded),
  ],
  // Security is the fourth because the console has a reader now: security_alerts is where
  // app.detect_suspicious_activity() files the patterns it finds in the audit trail, and until
  // this tab existed nothing in either app ever looked at them. See SaShell.
  UserRole.superAdmin: [
    (label: 'Overview', icon: Icons.grid_view_rounded),
    (label: 'Hostels', icon: Icons.apartment_rounded),
    (label: 'Subscriptions', icon: Icons.card_membership_rounded),
    (label: 'Security', icon: Icons.shield_rounded),
  ],
};

/// The clay art for each tab of the two bars this shell draws, in the same order as [_tabs].
///
/// Home and Fees have their own on/off renders (nav-home, nav-money); the other three are clay
/// icons from the main set, which [ClayNavBar] draws through its greyscale filter when they are
/// not selected, so the five still read as one set.
const _clayArt = <UserRole, List<String>>{
  UserRole.student: [
    ClayIcons.navHome, // Home
    ClayIcons.navMoney, // Fees
    ClayIcons.complaint, // Complaints
    ClayIcons.announcement, // Notices
    ClayIcons.roleTenant, // Profile
  ],
};

/// The clay art for one tab, or the generic home render for a slot nothing has mapped.
String _artOfTab(UserRole role, int index) {
  if (role == UserRole.owner && index >= 0 && index < ownerTabs.length) {
    return ownerTabs[index].icon;
  }
  final art = _clayArt[role];
  if (art == null || index < 0 || index >= art.length) return ClayIcons.navHome;
  return art[index];
}

class RoleShell extends ConsumerStatefulWidget {
  const RoleShell({super.key, required this.role});
  final UserRole role;

  @override
  ConsumerState<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends ConsumerState<RoleShell> {
  int _index = 0;

  /// Asks, each time the app comes back to the foreground, whether a warden's or a manager's PG
  /// moved while it was away. See [AuthController.syncActiveHostel] for why: `users.hostel_id`
  /// is shared by every device on the account, so a switch on the website or a second phone
  /// moves this phone's PG too, and nothing else would tell it.
  ///
  /// Here rather than in either shell because this widget outlives them both: the two shells
  /// are rebuilt from scratch when the PG changes (see [_shell]), and a listener inside one
  /// would be torn down by the very event it exists to notice.
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    if (widget.role == UserRole.warden || widget.role == UserRole.manager) {
      _lifecycle = AppLifecycleListener(
        onResume: () => ref.read(authControllerProvider.notifier).syncActiveHostel(),
      );
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// THE ONE MOUNTING POINT FOR THE "A NEW BUILD EXISTS" NOTICE.
  ///
  /// This widget is what the router draws for every one of the five role homes — the three
  /// shells below are reached THROUGH it — so wrapping here reaches every signed-in screen with
  /// a single edit, rather than five that four future roles would have to remember. It draws
  /// nothing at all unless public.app_releases names a build newer than this one; see
  /// core/version/update_banner.dart.
  @override
  Widget build(BuildContext context) =>
      UpdateBannerHost(child: _shell(context));

  Widget _shell(BuildContext context) {
    // A role whose screens are built owns its own shell: its tabs need per-screen headers,
    // badges and a selected index that other screens can move. The placeholder below stays for
    // the roles still to come, and each takes this same one-line exit as it lands. The tab list
    // in [_tabs] remains the readable index of what every role's navigation is.
    //
    // THE TWO STAFF SHELLS ARE KEYED BY THE PG THEY ARE SHOWING. A warden or manager with access
    // to several PGs can switch between them, and a switch has to land as a fresh shell: its
    // TabWarmer warms the NEW PG's tabs (a warmer that has already run would leave every
    // unvisited tab to load cold), and scroll positions, typed searches and expanded rows that
    // belonged to the previous PG's lists do not carry over onto another PG's rows. The tab
    // index and the filters are providers, so where the person was standing survives. A session
    // refresh that leaves the PG alone keeps the same key and rebuilds nothing.
    if (widget.role == UserRole.warden || widget.role == UserRole.manager) {
      final hostelId = ref.watch(currentHostelIdProvider);
      return widget.role == UserRole.warden
          ? WardenShell(key: ValueKey<String?>(hostelId))
          : ManagerShell(key: ValueKey<String?>(hostelId));
    }
    if (widget.role == UserRole.superAdmin) return const SaShell();

    final t = Theme.of(context);
    final tabs = _tabs[widget.role] ?? const [];
    final owner = widget.role == UserRole.owner;
    // The owner's tab is a provider so Home can send the owner to Money or People; the resident's
    // is this widget's own, because nothing on their screens moves it. See [ownerTabProvider].
    final index = owner ? ref.watch(ownerTabProvider) : _index;

    return Scaffold(
      // The theme's cream, drawn once behind both the header and the tab body: the animated wash
      // that used to sit behind the dashboards is gone, so there is nothing left for a second
      // layer to add.
      body: Column(
        children: [
          // THE HEADER IS A FIXED OBJECT THE LIST PASSES UNDER, not the first row of the scroll
          // view: a greeting that scrolls off the forest lands in the theme's ink on whatever is
          // under it. The owner's is one per tab and full-bleed, above the width cap TabSwap puts
          // on the body; the resident keeps the shared masthead.
          if (owner)
            OwnerHeader(tab: ownerTabs[index.clamp(0, ownerTabCount - 1)])
          else
            _StudentHeader(onNotices: () => setState(() => _index = _studentNoticesTab)),
          Expanded(child: _body(t, tabs, index)),
        ],
      ),
      bottomNavigationBar: tabs.isEmpty ? null : _navBar(tabs, index),
    );
  }

  /// The bottom bar: a clay icon per tab on the card the bar is made of.
  ///
  /// [ClayNavBar] sizes itself from its label — 72dp at 1.0x, a little taller with large text and
  /// never past the 88dp every shell's bar is held to — so the old height arithmetic is gone. The
  /// selected tab is the full-colour art on a Mist pill with its label in forest; the others are
  /// their off-renders, or their art drawn grey, with the label in the muted ink. One colour for
  /// every selected tab, rather than each destination's own hue: on a bar of clay art the art is
  /// already the wayfinding, and a second colour per tab would only argue with it.
  Widget _navBar(List<({String label, IconData icon})> tabs, int index) {
    final owner = widget.role == UserRole.owner;
    // Join requests waiting on the owner, as the People tab's badge. Null-safe: a failed or
    // pending count draws no badge rather than a zero.
    final joins = owner ? ref.watch(pendingJoinCountProvider).value ?? 0 : 0;
    return ClayNavBar(
      selectedIndex: index.clamp(0, tabs.length - 1),
      onDestinationSelected: (i) {
        if (owner) {
          ref.read(ownerTabProvider.notifier).select(i);
        } else {
          setState(() => _index = i);
        }
      },
      destinations: [
        for (var i = 0; i < tabs.length; i++)
          ClayNavDestination(
            icon: _artOfTab(widget.role, i),
            label: tabs[i].label,
            badgeCount: owner && i == OwnerTab.people.index && joins > 0 ? joins : null,
            badgeLabel: owner && i == OwnerTab.people.index && joins > 0
                ? '$joins join ${joins == 1 ? 'request' : 'requests'}'
                : null,
          ),
      ],
    );
  }

  /// The screen behind the selected tab.
  ///
  /// Each role's feature directory exposes ONE widget that maps a tab index to a screen, and
  /// this is where those are plugged in. Anything a feature has not built yet falls through to
  /// the placeholder below, which says so rather than rendering an empty page that looks
  /// finished.
  Widget _body(ThemeData t, List<({String label, IconData icon})> tabs, int index) {
    // The owner's section owns its bodies the way the student's does — an IndexedStack over
    // the tabs actually visited — and additionally warms the unvisited tabs' data in the
    // background so a tap lands on drawn numbers, not a skeleton. All five owner tabs are
    // built; the placeholder is still passed because OwnerSection's contract asks for one, and
    // a sixth tab added to the bar before its screen exists should say so rather than render
    // an empty page. See OwnerSection.
    if (widget.role == UserRole.owner) {
      return OwnerSection(tabIndex: index, placeholder: (_) => _placeholder(t, tabs, index));
    }
    // The student app keeps its own widget rather than a per-index function: it holds the tabs
    // already visited in an IndexedStack, so moving between Home and Fees does not refetch the
    // same rent row or lose a scroll position. See StudentSection.
    if (widget.role == UserRole.student) {
      return StudentSection(tabIndex: index);
    }
    return _placeholder(t, tabs, index);
  }

  /// The safety net, for any tab slot no feature has claimed.
  ///
  /// UNREACHABLE TODAY, and deliberately kept. All five roles resolve their own bodies — owner
  /// and student through their sections, warden, manager and super admin through their own
  /// shells — so nothing currently falls here. It stays because a sixth tab added to the bar
  /// before its screen exists should land somewhere honest rather than on a blank Scaffold that
  /// looks finished.
  ///
  /// THE COPY IS WRITTEN FOR WHOEVER SEES IT, which is what changed. It used to end "see the
  /// migration status in the repo" — a sentence addressed to me, on a screen only a customer
  /// can reach. If this ever draws in front of one it should read as a section on its way, not
  /// as a confession.
  Widget _placeholder(ThemeData t, List<({String label, IconData icon})> tabs, int index) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              tabs.isEmpty
                  ? 'No navigation for this role'
                  : tabs[index.clamp(0, tabs.length - 1)].label,
              style: t.textTheme.headlineMedium,
            ),
            const SizedBox(height: Space.xs),
            Text(
              'This section is on its way. Everything else in the app is ready to use — '
              'pick another tab below.',
              style: t.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}


/// The resident's Notices tab, which the header bell opens.
const _studentNoticesTab = 3;

/// THE RESIDENT'S TOP BAR, the owner's shape: their photo (opening the profile sheet, where
/// "Change photo" lives), a greeting over their PG's name, and a bell that opens Notices.
class _StudentHeader extends ConsumerWidget {
  const _StudentHeader({required this.onNotices});

  final VoidCallback onNotices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final hostelId = session?.hostelId;
    final pg = hostelId == null ? null : ref.watch(hostelProvider(hostelId)).value?.name;
    final first = firstName(session?.fullName);
    return AppHeader(
      greeting: first.isEmpty ? greetingFor(DateTime.now()) : '${greetingFor(DateTime.now())}, $first',
      title: pg ?? 'Apnivaas',
      leading: MyHeaderAvatar(onTap: () => showStaffProfile(context)),
      actions: [
        HeaderIconButton(
          icon: Icons.notifications_none_rounded,
          label: 'Notices',
          onPressed: onNotices,
        ),
      ],
    );
  }
}
