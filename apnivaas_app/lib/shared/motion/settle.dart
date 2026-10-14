import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The crossfade between "we are fetching this" and "here it is".
///
/// ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────
///
/// The owner installed the nearest competitor and said its animations looked better than ours.
/// Auditing what he had actually seen turned up a specific, countable answer: `Entrance` — this
/// app's only arrival vocabulary, and a well-built one — had three call sites, all inside the
/// owner dashboard. Every other screen went through `AsyncSection`, which is a bare `if/else`:
/// the skeleton is present on one frame and the rows are present on the next.
///
/// That switch is not a missing flourish. It is the single most repeated moment in the product —
/// it happens on every tab of every role, every time data lands — and having it be an instant
/// substitution is most of why the app reads as a page redrawing rather than as data arriving.
///
/// Putting the transition HERE rather than at those 31 call sites means the whole app gains it
/// in one edit, and no screen can be forgotten.
///
/// ── WHY IT DOES NOT FIRE ON A REFRESH ─────────────────────────────────────────────────────
///
/// The state key is the point. Riverpod's `AsyncValue` keeps its previous data through a
/// refresh (`skipLoadingOnRefresh`), so the branch stays `data`, the key stays `data`, and
/// `AnimatedSwitcher` correctly does nothing — the rows do not blink every time the app returns
/// from the background. The transition plays when the STATE changes, which is the only time
/// anything actually moved.
///
/// ── WHY THE STACK IS TOP-ALIGNED ──────────────────────────────────────────────────────────
///
/// `AnimatedSwitcher`'s default layout centres the outgoing and incoming children on each other,
/// so a short skeleton crossfading into a tall list makes the parent grow from the middle and
/// the content visibly jumps. Top-aligned, the two share an origin and only the height changes.
class Settle extends StatelessWidget {
  const Settle({super.key, required this.state, required this.child});

  /// What is being shown: `data`, `loading`, `error`. Any stable string works; what matters is
  /// that it changes when, and only when, the thing on screen is a different KIND of thing.
  final String state;

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: Motion.base,
    switchInCurve: Motion.enter,
    // ── THE OUTGOING CHILD LEAVES AT ONCE, AND THAT IS A CONTRACT, NOT A TASTE CALL ──────
    //
    // My first version faded the skeleton out over 150ms beneath the arriving rows. Two tests
    // caught it — warden_shell_warmup_test and manager_warmup_test — and they were right to.
    // Their contract is that ONE FRAME after a tab is tapped, a warm tab has no SkeletonBlock
    // in the tree at all: `_tapTab` pumps exactly one frame, and the comment there says
    // "everything the no-skeleton contract promises must already be true here, without
    // settling". A fading skeleton is still a mounted skeleton, and the entire point of the
    // warm-up machinery is that a warm tab never shows one.
    //
    // Zero removes it on the frame the state changes, leaving the half that was actually
    // missing: the data arriving with a fade and a small lift. It also looks better — a
    // skeleton dissolving under incoming rows is the smear that makes crossfades look cheap.
    switchOutCurve: Motion.enter,
    reverseDuration: Duration.zero,
    layoutBuilder: (current, previous) =>
        Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
    transitionBuilder: (child, anim) => FadeTransition(
      opacity: anim,
      child: SlideTransition(
        // Six pixels at a 16px text size, and it scales with nothing — this is a hint of
        // direction, not a slide. Anything bigger turns a list arriving into a list flying
        // in, which is the kind of motion that is charming twice and tiring afterwards.
        position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
        child: child,
      ),
    ),
    child: KeyedSubtree(key: ValueKey(state), child: child),
  );
}
