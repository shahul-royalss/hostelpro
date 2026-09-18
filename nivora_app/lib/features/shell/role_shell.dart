import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/version/update_banner.dart';
import '../../shared/aurora.dart';
import '../../shared/brow_header.dart';
import '../../shared/glass/glass.dart';
import '../../shared/wordmark.dart';
import 'staff_profile_sheet.dart';
import '../manager/manager_shell.dart';
import '../super_admin/sa_shell.dart';
import '../warden/warden_shell.dart';
import '../owner/owner_tabs.dart';
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
  /// ── THE MASTHEAD SAYS WHO YOU ARE FIRST, AND WHOSE APP IT IS SECOND ──────────────────
  ///
  /// It used to be the drawn wordmark alone, centred. The product owner's objection was exact:
  /// "the NIVORA name at top middle isn't good and it has to say hello Username. Below of that
  /// it has to show the NIVORA."
  ///
  /// He is right, and the reason is that a masthead is not a logo slot. Every screen in this
  /// app already belongs to Nivora; what the top of the screen can usefully tell a warden at
  /// 8am is that the app knows which warden. The brand goes underneath, quieter, where it reads
  /// as a signature on the greeting rather than as a banner over it.
  ///
  /// ── AND IT IS TYPE, NOT THE DRAWN PATH ────────────────────────────────────────────────
  ///
  /// [NivoraWordmark] traces an outline, which is what the old splash animated. Asked for
  /// "simply elegant typographic which represents our logo / brand", so this is the display
  /// face with the mark's own tracking — the same lockup the new splash resolves into, so
  /// opening the app and using it show one wordmark rather than two that nearly match.
  Widget _header(ThemeData t, NivoraSession? session) {
    if (widget.role == UserRole.student) return _residentHeader(t, session);

    final name = session?.fullName.trim() ?? '';
    // BrowTitleBlock.masthead balances the avatar with an empty twin of the same width, so the
    // greeting is centred on the SCREEN rather than on the space left over beside it, and it
    // draws the greeting and the [MastheadBlock] signature in the brow's own ink.
    return BrowTitleBlock.masthead(
      name: name,
      leading: Tooltip(
        message: 'Your account',
        child: InkWell(
          onTap: () => showStaffProfile(context),
          customBorder: const CircleBorder(),
          child: Padding(
            // 8 + 44 + 8 is a 60dp target on the control that opens profile, two-factor and
            // sign out. `customBorder: CircleBorder()` clips the hit region to a circle, so the
            // corners are dead and the real target is smaller than its box — which is why it is
            // generous. The disc grew from 32 on 2026-09-12; see AvatarSize.header.
            padding: const EdgeInsets.all(Space.xs),
            child: AccountAvatar(
              name: name.isEmpty ? 'Nivora' : name,
              size: AvatarSize.header,
            ),
          ),
        ),
      ),
    );
  }

  /// The resident's masthead, which is now the same one everybody else gets.
  ///
  /// ── WHAT CAME OFF IT, AND WHERE THOSE ACTIONS WENT ───────────────────────────────────
  ///
  /// This used to carry the role in small caps, the name, and two icon buttons at the trailing
  /// edge: a shield for security and a door for sign out. The owner asked for both to go, "at
  /// any cost". They are gone.
  ///
  /// Neither capability is lost, and that mattered more than obeying literally. Sign out was
  /// already on the Profile tab. Security was NOT — it existed only as this icon — so removing
  /// the icon alone would have taken two-factor authentication away from residents entirely,
  /// which is a security downgrade dressed up as a layout change. It is a row on the Profile
  /// tab now, beside sign out, which is where a resident would look for it anyway.
  Widget _residentHeader(ThemeData t, NivoraSession? session) =>
      BrowTitleBlock.masthead(name: session?.fullName.trim() ?? '');

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
