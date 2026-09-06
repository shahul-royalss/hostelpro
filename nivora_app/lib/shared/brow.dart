import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/tokens.dart';

/// THE BROW — a full-bleed band of brand across the top of the screen, curved along its
/// bottom edge, with the page's own content riding over the seam.
///
/// ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────
///
/// The owner installed the nearest shipping competitor and said it looked better than NIVORA.
/// Comparing them screen by screen, the single largest difference was not colour and not type:
/// it was that their sign-in screen fills its top third with a coloured block whose bottom edge
/// is convex, and lets the form card overlap that edge, while NIVORA put a card in the middle
/// of an empty field. Roughly 45% of our screen was doing nothing. Theirs is doing the work of
/// saying which product you have opened before you have read a word.
///
/// It is the cheapest device in their whole app and the one worth taking. Everything else they
/// do — 20dp corners, translucent cards — NIVORA either already did or has now taken directly.
///
/// ── WHAT THIS IS NOT ──────────────────────────────────────────────────────────────────────
///
/// It is not a pane, so the rules in `shared/glass/glass.dart` about panes do not apply to it
/// and it does not go through [GlassWeight]. It is not the competitor's shape either: theirs is
/// a shallow arc across a block roughly a third of the screen; this is deliberately lower and
/// flatter, because NIVORA's screens carry more per row than theirs do and a deep bulge eats
/// the first card.
///
/// It is FLAT, not a gradient. `glass.dart` rule 2 bans decorative gradients on a pane, and
/// while a brow is not a pane, the reason behind the rule still holds: one flat fill means the
/// contrast of everything drawn on it is measured once rather than per pixel-row. The
/// competitor's own gradient CTA is the argument for this — it interpolates peach into
/// half-transparent cyan and greys out through the middle.
class BrandBrow extends StatelessWidget {
  const BrandBrow({
    super.key,
    required this.child,
    this.height,
    this.dip = 26,
    this.enabled = true,
  });

  /// The page. Drawn over the brow, so anything it puts near the top rides the seam.
  final Widget child;

  /// How far down the flat part of the band reaches, before the curve. Defaults to 30% of the
  /// screen's height, clamped to a band that is neither a stripe nor half the page.
  final double? height;

  /// How far the centre of the bottom edge bulges below [height]. The whole effect is in this
  /// number, and it is small on purpose: at 26 the curve is legible as a curve and still leaves
  /// a straight-enough edge at the margins for a card to sit against.
  final double dip;

  /// Off for screens that own their whole canvas — a full-bleed onboarding page, a receipt.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    final media = MediaQuery.of(context);
    final band = height ?? (media.size.height * 0.30).clamp(180.0, 320.0);

    return Stack(
      children: [
        // THE STATUS BAR HAS TO FOLLOW THE BROW, NOT THE THEME. The root sets the overlay
        // style from the theme's brightness, which is right for every other screen — but the
        // top of THIS one is a deep indigo block in both themes, and a light-mode phone would
        // draw its clock in dark ink on it and lose it. This is the same class of bug the note
        // on NivoraTheme.systemOverlay records, arriving from the other direction.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: band + dip,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Color(0x00000000),
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
            ),
            child: ClipPath(
              clipper: BrowClipper(dip: dip),
              child: const ColoredBox(color: NivoraColors.brandDeep),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// The convex bottom edge. One quadratic, because one quadratic is what the shape is: a single
/// bulge with no inflection. A cubic would let the edge wobble, and an edge that wobbles by a
/// pixel is the kind of thing that looks wrong without anyone being able to say why.
///
/// Public because a header on a scrolling screen draws its OWN brow rather than sitting on
/// this one — see `GlassHeader.onBrow` for why a full-height brow behind a list cannot work.
class BrowClipper extends CustomClipper<Path> {
  const BrowClipper({required this.dip});

  final double dip;

  @override
  Path getClip(Size size) {
    final h = size.height - dip;
    return Path()
      ..lineTo(0, h)
      // Control point at 2x the dip: a quadratic reaches half its control offset at the
      // midpoint, so this puts the deepest point of the curve exactly `dip` below `h`.
      ..quadraticBezierTo(size.width / 2, h + dip * 2, size.width, h)
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(BrowClipper old) => old.dip != dip;
}

/// "You are being drawn on the brand block." Read it with `BrowScope.of(context)`.
///
/// Most things on a brow need nothing: [GlassHeader] wraps its subtree in an [IconTheme] and a
/// [DefaultTextStyle] set to white, and unstyled text and icons inherit those. This exists for
/// the handful of widgets that name a colour of their own and therefore cannot inherit — a
/// brand dot painted in `colorScheme.primary`, an avatar's identity hash. On #4D2896 those go
/// invisible, and they cannot simply read the default text style because outside a brow that
/// would repaint them the body ink.
class BrowScope extends InheritedWidget {
  const BrowScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BrowScope>() != null;

  @override
  bool updateShouldNotify(BrowScope oldWidget) => false;
}
