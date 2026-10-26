import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'clay/app_header.dart' show HeaderBackdropPainter;

/// THE BROW — a full-bleed band of forest across the top of the screen, with the page's own
/// content riding over its bottom edge.
///
/// ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────
///
/// The owner installed the nearest shipping competitor and said it looked better than Apnivaas.
/// The single largest difference was that their sign-in screen fills its top third with a
/// coloured block and lets the form card overlap its edge, while Apnivaas put a card in the
/// middle of an empty field. A band that says which product you have opened before you have
/// read a word is the cheapest device in their app and the one worth taking.
///
/// ── WHAT IT PAINTS ────────────────────────────────────────────────────────────────────────
///
/// The forest header's own backdrop — [ApnivaasColors.headerGradient] and the dot stars, via
/// [HeaderBackdropPainter] — with the header's 30dp bottom corners, so the auth band and every
/// dashboard header are one object rather than two greens that nearly match. It used to be a
/// flat violet block with a convex dip; the dip went with the violet, because the design's
/// headers are rounded rectangles and a curve under one of them would be a second shape
/// language. Static: painted once into its own layer, nothing moves.
///
/// It is not a pane, so the rules in `shared/glass/glass.dart` about panes do not apply to it.
/// Nothing reads text off it except a masthead written for it in white (7.28:1 on the
/// gradient's lightest stop): the card that rides its edge brings its own opaque fill.
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

  /// How far down the band reaches before its rounded bottom edge starts. Defaults to 30% of
  /// the screen's height, clamped to a band that is neither a stripe nor half the page.
  final double? height;

  /// Extra band below [height]. It was the depth of the old convex curve; the band now simply
  /// reaches this much further, so a card positioned against [height] still overlaps the
  /// colour by the same amount it always did.
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
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: band + dip,
          // THE STATUS BAR HAS TO FOLLOW THE BROW, NOT THE THEME. The root sets dark icons for
          // the cream ground; on forest that is a clock nobody can read.
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: ApnivaasTheme.onForest,
            child: ClipRRect(
              borderRadius: Radii.rHeaderBottom,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: HeaderBackdropPainter(topInset: media.padding.top),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// "You are being drawn on the forest." Read it with `BrowScope.of(context)`.
///
/// Most things on a brow need nothing: the header frames wrap their subtree in an [IconTheme]
/// and a [DefaultTextStyle] set to white, and unstyled text and icons inherit those. This exists
/// for the handful of widgets that name a colour of their own and therefore cannot inherit — a
/// brand dot painted in `colorScheme.primary`, an avatar's identity colour. On forest those go
/// invisible, and they cannot simply read the default text style because outside a brow that
/// would repaint them the body ink.
class BrowScope extends InheritedWidget {
  const BrowScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BrowScope>() != null;

  @override
  bool updateShouldNotify(BrowScope oldWidget) => false;
}
