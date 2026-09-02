library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A short arrival for content that has just landed — one fade and one small lift, once.
///
/// ── WHAT THIS IS FOR ─────────────────────────────────────────────────────────────────────
///
/// The app's screens are correct and static: a list snaps from a skeleton to its rows with no
/// indication that anything moved, which reads as a page redrawing rather than as data
/// arriving. This gives that moment a direction. It is the only motion in Nivora that is not a
/// response to a touch.
///
/// ── THE FOUR RULES, AND HOW EACH ONE IS ACTUALLY ENFORCED ────────────────────────────────
///
///  1. **It runs once.** The controller is started in `initState` and never restarted. A
///     provider refresh rebuilds this widget; it does not re-play. A list that re-animated
///     whenever its data refreshed would flicker every time the app came back from background.
///
///  2. **It never delays a first frame, and it never blocks a tap.** There is no timer and no
///     scheduled callback: one controller runs for the whole delay-plus-duration and the child
///     is positioned by an [Interval] inside it. The child is built, laid out and hit-testable
///     from frame one — [FadeTransition] and [SlideTransition] change how it is painted, not
///     whether it exists. A resident who taps a row before it has finished arriving gets the
///     row.
///
///  3. **It is capped.** [Motion.staggerCap] steps in and the delay stops growing, so a
///     200-row list does not compute an eight-second ramp for rows nobody has scrolled to.
///
///  4. **It obeys the system.** With "reduce motion" on, this returns the child untouched —
///     not a faster animation, none at all. That switch is set by people for whom movement on
///     screen is a symptom, and the honest reading of it is zero.
///
/// ── AND THE ONE IT DOES NOT DO ───────────────────────────────────────────────────────────
///
/// NOTHING HERE RUNS CONTINUOUSLY. No pulse, no shimmer, no looping highlight. The controller
/// reaches 1.0 and stops, and the widget then costs a rebuild of nothing at all.
class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.child, this.index = 0});

  final Widget child;

  /// Position in the list, which is what buys the delay. 0 for a lone figure or the first row.
  final int index;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    // The stagger is read ONCE, from the index this item was built with. Reading it on every
    // build would let a re-ordered list restart a delay that has already elapsed.
    final steps = widget.index.clamp(0, Motion.staggerCap);
    final delay = Motion.stagger * steps;
    final total = delay + Motion.base;

    _controller = AnimationController(vsync: this, duration: total);
    _curve = CurvedAnimation(
      parent: _controller,
      // The delay is a dead stretch at the head of one controller rather than a Timer: a timer
      // that fires after the widget is gone is a crash, and a timer in a widget test is a
      // pumpAndSettle that never settles.
      curve: Interval(
        total == Duration.zero ? 0.0 : delay.inMicroseconds / total.inMicroseconds,
        1.0,
        curve: Motion.enter,
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rule 4. Checked in build rather than initState because it can change while the app is
    // open — the switch is in the OS, not in this app.
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;

    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        // A fraction of the child's own height, so one row and a whole card travel a
        // proportionate distance rather than the same absolute number of pixels.
        position: Tween<Offset>(
          begin: const Offset(0, _travel),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }

  /// An eighth of the item's height. Small enough to read as settling rather than as flying in
  /// from off-screen, which on a list of twelve rows is a stampede.
  static const _travel = 0.125;
}
