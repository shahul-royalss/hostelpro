import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/version/update_banner.dart';
import '../../shared/aurora.dart';
import '../../shared/glass/glass.dart';
import '../../shared/wordmark.dart';
import 'staff_profile_sheet.dart';
import '../manager/manager_shell.dart';
import '../super_admin/sa_shell.dart';
import '../warden/warden_shell.dart';
import '../owner/owner_tabs.dart';
import '../settings/security_screen.dart';
import '../student/student_section.dart';

/// Per-role navigation. Each role gets the tabs its job needs — the brief's point that forcing
/// every role through one navigation is what makes an operational tool feel generic.
const _tabs = <UserRole, List<({String label, IconData icon})>>{
  UserRole.owner: [
    (label: 'Dashboard', icon: Icons.grid_view_rounded),
    (label: 'PGs', icon: Icons.apartment_rounded),
    (label: 'Students', icon: Icons.people_alt_rounded),
    (label: 'Payments', icon: Icons.payments_rounded),
    (label: 'More', icon: Icons.more_horiz_rounded),
  ],
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

/// The area each destination leads to, in the same order as [_tabs], so the selected pill can
/// take that area's colour — see [NivoraDomain] for the colours and the rule behind them.
///
/// Only the two roles this shell draws a bar for are listed; the three that own their own shell
/// (warden, manager, super admin) never reach [_RoleShellState._navBar]. Home, Dashboard and
/// More are the platform itself, which is the brand's gold.
const _tabDomains = <UserRole, List<NivoraDomain>>{
  UserRole.owner: [
    NivoraDomain.security, // Dashboard
    NivoraDomain.rooms, // PGs
    NivoraDomain.people, // Students
    NivoraDomain.money, // Payments
    NivoraDomain.security, // More
  ],
  UserRole.student: [
    NivoraDomain.security, // Home
    NivoraDomain.money, // Fees
    NivoraDomain.complaints, // Complaints
    NivoraDomain.notices, // Notices
    NivoraDomain.people, // Profile
  ],
};

/// The domain of one tab, or the brand for a role or an index nothing has mapped.
NivoraDomain _domainOfTab(UserRole role, int index) {
  final domains = _tabDomains[role];
  if (domains == null || index < 0 || index >= domains.length) return NivoraDomain.security;
  return domains[index];
}

class RoleShell extends ConsumerStatefulWidget {
  const RoleShell({super.key, required this.role});
  final UserRole role;

  @override
  ConsumerState<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends ConsumerState<RoleShell> {
  int _index = 0;

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
    if (widget.role == UserRole.warden) return const WardenShell();
    if (widget.role == UserRole.superAdmin) return const SaShell();
    if (widget.role == UserRole.manager) return const ManagerShell();

    final t = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final tabs = _tabs[widget.role] ?? const [];

    return Scaffold(
      // Transparent so the wash below is the ground rather than being painted over.
      backgroundColor: Colors.transparent,
      // THE SAME LIGHT AS THE SIGN-IN SCREEN, TURNED DOWN. The owner asked for the sign-in
      // panel's colour across the dashboards; at full strength behind a screen of figures it
      // competes with the data, so the dashboards get a third of it. The point is that opening
      // the app and signing into it feel like one product, not that every screen glows.
      body: AuroraField(
        intensity: 0.34,
        child: Column(
        children: [
          // THE BROW IS THE HEADER HERE, not a band behind the whole shell.
          //
          // A full-height brow was tried first and rendering this screen to a PNG killed it:
          // the greeting is the first thing in the scroll view, it uses the theme's ink, and on
          // #4D2896 that is near-black on deep indigo. Whitening it only moves the bug, because
          // the greeting scrolls off the band. `onBrow` makes the header itself the brand block
          // with the curved bottom edge — a fixed object the list passes under, so the only
          // thing that ever crosses the colour is a card, which brings its own opaque fill.
          GlassHeader(onBrow: true, child: _header(t, session)),
          Expanded(child: _body(t, tabs)),
        ],
        ),
      ),
      bottomNavigationBar: tabs.isEmpty ? null : _navBar(t, tabs),
    );
  }

  /// The bottom bar, with the selected pill in the colour of the place it leads to.
  ///
  /// THE INDICATOR IS THE DESTINATION'S DOMAIN, not the brand's gold on every tab — the way a
  /// Google app's bottom bar lights the active tab in that section's own hue. Fees glows the
  /// ledger's green, Complaints the amber of open work, Notices the noticeboard's blue; Home and
  /// More keep the brand. The fill and the ink are the chip recipe from [NivoraSemantics], so the
  /// label on the pill measures what every chip in the app measures. The UNSELECTED destinations
  /// are left exactly as theme.dart draws them: only the selected state is re-coloured, and
  /// everything else on the bar still comes from the theme it already had.
  Widget _navBar(ThemeData t, List<({String label, IconData icon})> tabs) {
    final tones = context.tones;
    final selected = _index.clamp(0, tabs.length - 1);
    final ink = tones.resolve(_domainOfTab(widget.role, selected).tone);
    final base = t.navigationBarTheme;

    return NavigationBarTheme(
      data: base.copyWith(
        indicatorColor: tones.chipFill(ink),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final themed = base.iconTheme?.resolve(states);
          if (!states.contains(WidgetState.selected)) return themed;
          return (themed ?? const IconThemeData()).copyWith(color: ink);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final themed = base.labelTextStyle?.resolve(states);
          if (!states.contains(WidgetState.selected)) return themed;
          return (themed ?? const TextStyle()).copyWith(color: ink);
        }),
      ),
      child: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) => setState(() => _index = i),
        // 64dp keeps every destination above the 48dp minimum with room for the label.
        // 64dp keeps every destination above the 48dp minimum with room for the label — at
        // 1.0x. NavigationBar honours `height` LITERALLY: it does not grow for text scale, so
        // at the root's 1.4x ceiling the label was clipped against the icon. Scaling it and
        // capping the growth keeps the bar off the content. Same expression as
        // warden_shell.dart:196, which had this right and was the only one of the four.
        height: MediaQuery.textScalerOf(context).scale(64).clamp(64.0, 88.0),
        backgroundColor: t.colorScheme.surface,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final tab in tabs)
            NavigationDestination(icon: Icon(tab.icon), label: tab.label),
        ],
      ),
    );
  }

  /// The screen behind the selected tab.
  ///
  /// Each role's feature directory exposes ONE function that maps a tab index to a screen, and
  /// this is where those are plugged in. Anything a feature has not built yet returns null and
  /// falls through to the placeholder below, which says so rather than rendering an empty page
  /// that looks finished.
  /// ── TWO HEADERS, AND WHY ──────────────────────────────────────────────────────────────
  ///
  /// A RESIDENT keeps the header they had: their role and name on the left, the shield and the
  /// door on the right. They also have a Profile TAB, and the Account card on it already names
  /// both of those actions and says what each one costs. Moving the icons out of their header
  /// would take away a shortcut they may already have learned and give nothing back.
  ///
  /// EVERY OTHER ROLE gets the arrangement the product owner asked for: the signature centred,
  /// their avatar at the top left, and nothing at the top right. The two icons that used to
  /// live there are inside the sheet the avatar opens — see staff_profile_sheet.dart for why a
  /// sheet and not a fifth tab.
  ///
  /// The mark is drawn at progress: 1, not animated. It is a masthead here; the drawing is the
  /// splash's job and doing it again on every screen would be a logo that fidgets.
  Widget _header(ThemeData t, NivoraSession? session) {
    if (widget.role == UserRole.student) return _residentHeader(t, session);

    final name = session?.fullName.trim() ?? '';
    return Row(
      children: [
        // Leading and trailing are the same width so the mark between them is centred on the
        // SCREEN rather than on the space left over — an avatar on one side and nothing on the
        // other would push it off-centre by exactly one avatar.
        Tooltip(
          message: 'Your account',
          child: InkWell(
            onTap: () => showStaffProfile(context),
            customBorder: const CircleBorder(),
            child: Padding(
              // Space.xs, not Space.xxs. 32dp disc + 4 + 4 was a 40dp target — 8 under
              // Material's 48dp floor and under Apple's 44pt — on the control that opens
              // profile and sign out. `customBorder: CircleBorder()` also clips the hit region
              // to a circle, so the corners were dead and the real target was smaller than the
              // 40 it measured. 8 + 32 + 8 is 48. The visible disc does not change.
              padding: const EdgeInsets.all(Space.xs),
              child: AccountAvatar(
                name: name.isEmpty ? 'Nivora' : name,
                size: IconSize.xl,
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: SizedBox(
              width: 116,
              height: 116 / 3.4,
              // The colour named here is what it paints OFF a brow; on one the wordmark
              // whitens itself from BrowScope, so every masthead gets it without remembering.
              child: NivoraWordmark(progress: 1, color: t.colorScheme.onSurface),
            ),
          ),
        ),
        // The empty twin of the avatar. Sized from the same constants so the two cannot drift.
        const SizedBox(width: IconSize.xl + Space.xxs * 2),
      ],
    );
  }

  Widget _residentHeader(ThemeData t, NivoraSession? session) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.role.label.toUpperCase(), style: t.textTheme.labelSmall),
                Text(
                  session?.fullName.isNotEmpty == true ? session!.fullName : 'Nivora',
                  style: t.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Security',
            onPressed: () => openSecurity(context),
            icon: const Icon(Icons.shield_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      );

  Widget _body(ThemeData t, List<({String label, IconData icon})> tabs) {
    // The owner's section owns its bodies the way the student's does — an IndexedStack over
    // the tabs actually visited — and additionally warms the unvisited tabs' data in the
    // background so a tap lands on drawn numbers, not a skeleton. All five owner tabs are
    // built; the placeholder is still passed because OwnerSection's contract asks for one, and
    // a sixth tab added to the bar before its screen exists should say so rather than render
    // an empty page. See OwnerSection.
    if (widget.role == UserRole.owner) {
      return OwnerSection(tabIndex: _index, placeholder: (_) => _placeholder(t, tabs));
    }
    // The student app keeps its own widget rather than a per-index function: it holds the tabs
    // already visited in an IndexedStack, so moving between Home and Fees does not refetch the
    // same rent row or lose a scroll position. See StudentSection.
    if (widget.role == UserRole.student) {
      return StudentSection(tabIndex: _index);
    }
    return _placeholder(t, tabs);
  }

  /// The "not built yet" page, for any tab slot no feature has claimed.
  Widget _placeholder(ThemeData t, List<({String label, IconData icon})> tabs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              tabs.isEmpty ? 'No navigation for this role' : tabs[_index].label,
              style: t.textTheme.headlineMedium,
            ),
            const SizedBox(height: Space.xs),
            Text(
              'This screen is not built yet. The shell, theme, routing and\n'
              'authentication are — see the migration status in the repo.',
              style: t.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
