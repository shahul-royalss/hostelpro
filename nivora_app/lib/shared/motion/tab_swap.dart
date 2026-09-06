import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The arrival of a tab's content when you tap the bottom bar.
///
/// ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────
///
/// Switching tabs is the most repeated interaction in the product, and it had no motion at all
/// on the content. The `NavigationBar` animates its own indicator, so the bar slid and the page
/// it controls did not — which reads as the bar being disconnected from the thing it commands.
/// Same construction in all five shells.
///
/// ── WHY NOT AnimatedSwitcher, WHICH IS THE OBVIOUS ANSWER ─────────────────────────────────
///
/// Because it would silently undo the reason `IndexedStack` is there. Every shell in this app
/// uses IndexedStack so each tab keeps its scroll position and its loaded state — warden_shell
/// says so in a comment at the top of the file. `AnimatedSwitcher` swaps between DIFFERENT
/// widgets: to make it fire you have to give the IndexedStack a key that changes with the
/// index, and a changed key means Flutter builds a NEW IndexedStack and throws away every
/// child's State. The tabs would animate beautifully and forget where you were in each of them.
///
/// So this keeps ONE IndexedStack, identical across rebuilds, and animates around it. The child
/// tree is untouched; only a FadeTransition and a SlideTransition wrap it, driven by a
/// controller that replays whenever [index] changes.
///
/// ── WHAT IT DOES NOT DO ───────────────────────────────────────────────────────────────────
///
/// It does not cross-fade the outgoing tab with the incoming one. IndexedStack paints exactly
/// one child, so there is nothing to cross-fade WITH — the old tab is gone the moment the index
/// changes. What you get is the new content arriving: a fade up from nothing with a small lift.
/// That is the honest effect available here, and paying for a true cross-fade would mean giving
/// up the state preservation, which is a bad trade for a 240ms flourish.
class TabSwap extends StatefulWidget {
  const TabSwap({super.key, required this.index, required this.child});

  /// The selected tab. A change here is what replays the arrival.
  final int index;

  /// The [IndexedStack], or whatever else the shell puts in its body. Kept identical across
  /// rebuilds on purpose — see the class doc.
  final Widget child;

  @override
  State<TabSwap> createState() => _TabSwapState();
}

class _TabSwapState extends State<TabSwap> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.base,
    value: 1,
  );

  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Motion.enter);

  late final Animation<Offset> _lift = Tween<Offset>(
    // A hint of direction rather than a slide. Bigger than this and switching tabs becomes a
    // performance, which is charming twice and tiring afterwards.
    begin: const Offset(0, 0.015),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void didUpdateWidget(TabSwap old) {
    super.didUpdateWidget(old);
    // Only on an actual tab change. A rebuild from a provider landing new data must not replay
    // this, or every refresh would flash the whole page.
    if (old.index != widget.index) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A user who asked the OS to reduce motion gets the page, with no arrival. Checked on every
    // build rather than cached, because the setting can change while the app is open.
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;

    return FadeTransition(
      opacity: _fade,
      // `child:` on both, so the subtree is built once and only the transitions rebuild per
      // frame. Passing it positionally instead would rebuild all five tabs on every frame of
      // every tab change.
      child: SlideTransition(position: _lift, child: widget.child),
    );
  }
}
