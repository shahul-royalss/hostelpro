library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/perf/tab_warmer.dart';
import '../../data/providers.dart';
import 'complaints_screen.dart';
import 'fees_screen.dart';
import 'home_screen.dart';
import 'notices_screen.dart';
import 'profile_screen.dart';
import 'student_providers.dart';

/// The student app, as five tab bodies.
///
/// HOW THIS PLUGS INTO THE SHELL. `features/shell/role_shell.dart` owns the header, the
/// sign-out button and the `NavigationBar`, and already lists these five destinations for
/// `UserRole.student`. This file supplies the bodies and nothing else — one widget, driven by
/// the index the shell is already tracking, wired in `_RoleShellState._body`:
///
///     if (widget.role == UserRole.student) return StudentSection(tabIndex: _index);
///
/// [studentTabs] mirrors the shell's own list so the two can be checked against each other, and
/// so a sixth tab cannot be added on one side only.

/// The five destinations, in the order the shell draws them.
const studentTabs = <({String label, IconData icon})>[
  (label: 'Home', icon: Icons.home_rounded),
  (label: 'Fees', icon: Icons.receipt_long_rounded),
  (label: 'Complaints', icon: Icons.report_problem_rounded),
  (label: 'Notices', icon: Icons.campaign_rounded),
  (label: 'Profile', icon: Icons.person_rounded),
];

/// The body for one tab. Exposed separately so a screen can also be pushed on its own.
Widget studentScreenFor(int tabIndex) => switch (tabIndex) {
      0 => const StudentHomeScreen(),
      1 => const StudentFeesScreen(),
      2 => const StudentComplaintsScreen(),
      3 => const StudentNoticesScreen(),
      _ => const StudentProfileScreen(),
    };

/// The background warm-up for every student tab except Home, in tap-likelihood order.
///
/// THE CONTRACT (see TabWarmer): a tab tap must never show a skeleton once the shell has been
/// up for a moment. Home is deliberately absent — its screen watches its own providers during
/// its first build, so those requests are on the wire a full stagger interval before the first
/// warmer fires, and win the network.
///
/// Every warmer starts by joining `myStudentProvider.future` — the read Home has already
/// dispatched — because the family keys (hostel id, student id) live on that row. Joining an
/// in-flight fetch costs nothing; it is not a second request. A null resident (a staff account,
/// an unfinished registration) warms nothing, exactly as the screens would have fetched
/// nothing.
///
/// Each entry reads the SAME provider instance, with the SAME family key, that the tab's screen
/// later watches — so warming cannot widen a read beyond what RLS already grants the session —
/// and every one of these providers holds its value via `holdForSession`, so what is warmed
/// stays warm for the signed-in session instead of being discarded when the warm read
/// completes. (`myRentThisMonthProvider` is the one non-autoDispose provider here; it needs no
/// hold and recomputes to null on sign-out because it watches `myStudentProvider`.)
List<Warmer> studentTabWarmers(WidgetRef ref) {
  return [
    // Fees: this month's rent (shared with Home — usually already in flight) and the payment
    // history, which nothing but this tab reads.
    () async {
      final me = await ref.read(myStudentProvider.future);
      if (me == null) return;
      await Future.wait([
        ref.read(myRentThisMonthProvider.future),
        ref.read(studentFeeHistoryProvider(me.id).future),
      ]);
    },
    // Complaints: the tab's unfiltered list. NOT the same cache entry as Home's open-only
    // summary — the query is the family key — so it needs its own warm.
    () async {
      final me = await ref.read(myStudentProvider.future);
      if (me == null) return;
      await ref.read(complaintsProvider(ComplaintQuery(hostelId: me.hostelId)).future);
    },
    // Notices: one instance serves both the tab and Home's below-the-fold preview.
    () async {
      final me = await ref.read(myStudentProvider.future);
      if (me == null) return;
      await ref.read(noticesProvider(me.hostelId).future);
    },
    // Profile (and Home's greeting/room card): roommates and hostel contacts. Home usually
    // dispatches both during its own build; this joins that fetch, and does the real read only
    // when Home never got that far.
    () async {
      final me = await ref.read(myStudentProvider.future);
      if (me == null) return;
      await Future.wait([
        ref.read(roommatesProvider.future),
        ref.read(hostelContactsProvider.future),
      ]);
    },
    // Home below the fold: the open-complaints summary. Home's ListView mounts children
    // lazily, so on a phone this section may sit under the fold unbuilt — warmed last, it is
    // ready by the time anyone scrolls to it.
    () async {
      final me = await ref.read(myStudentProvider.future);
      if (me == null) return;
      await ref.read(
        complaintsProvider(ComplaintQuery(hostelId: me.hostelId, openOnly: true)).future,
      );
    },
  ];
}

/// Hosts the five bodies, building each one the first time it is opened and keeping it after —
/// while a [TabWarmer] fetches every tab's DATA in the background from the moment the shell
/// mounts.
///
/// WHY THE WIDGETS STAY LAZY WHEN THE DATA DOES NOT. Building all five screens up front would
/// dispatch every query in the student app inside one frame, all contending with the Home tab
/// the resident is actually looking at. Keeping the widgets lazy and warming the data instead
/// gets the ordering right: Home's own requests go out during its first build, and the other
/// tabs' first pages follow staggered behind it (see [studentTabWarmers]). By the time a tab is
/// tapped its provider already holds a value, so the first build renders data, not a skeleton —
/// constructing the widgets themselves costs no network and one frame.
///
/// Once visited, a tab is KEPT: several of these providers are `autoDispose`, and discarding a
/// subtree on the way out used to throw its data away. They now also hold their values for the
/// session (`holdForSession`), so a revisit renders instantly from the held value even across a
/// rebuild — but keeping the subtree is still what preserves scroll positions.
class StudentSection extends ConsumerStatefulWidget {
  const StudentSection({super.key, required this.tabIndex});

  final int tabIndex;

  @override
  ConsumerState<StudentSection> createState() => _StudentSectionState();
}

class _StudentSectionState extends ConsumerState<StudentSection> {
  final _visited = <int>{};
  TabWarmer? _warmer;

  @override
  void initState() {
    super.initState();
    // Post-frame and staggered, so the warm-up never contends with Home's own first fetch.
    // Every error is swallowed by TabWarmer: a failed warm just means that tab cold-loads on
    // first tap, which was yesterday's behaviour for every tap.
    _warmer = TabWarmer(studentTabWarmers(ref))..start();
  }

  @override
  void dispose() {
    _warmer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.tabIndex.clamp(0, studentTabs.length - 1);
    _visited.add(index);
    return IndexedStack(
      index: index,
      children: [
        for (var i = 0; i < studentTabs.length; i++)
          _visited.contains(i) ? studentScreenFor(i) : const SizedBox.shrink(),
      ],
    );
  }
}
