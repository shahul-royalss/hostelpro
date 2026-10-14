import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../shared/aurora.dart';
import '../../shared/brow.dart';

/// Text on the brand band. White in both themes, because the band is the same #4D2896 in both:
/// 10.20:1 for white on it, and it is the one surface a light phone and a dark phone render
/// identically.
const onAuthBand = Color(0xFFFFFFFF);

/// The sign-in family's page: the brand band across the top, a masthead on it, and a card
/// whose top edge is ANCHORED to the band. Used by the sign-in screen and the forced
/// password change, so the first two screens a new account meets are one layout.
///
/// ── WHY ANCHORED, AND NOT CENTRED ────────────────────────────────────────────────────────
///
/// The sign-in group used to be centred in the space ABOVE THE KEYBOARD while the band stayed
/// a fixed 46% of the screen. Measured in the 1.2.0 layout pass (360x640 → 1280x800, text scale
/// 1.0 and 1.4, keyboard open), that produced three defects, all from the one choice:
///
///   · opening the keyboard re-centred the group into the shorter viewport, so the title jumped
///     67–190 dp while the band behind it did not move;
///   · an error line appearing or disappearing changed the group's height, so the whole group
///     re-centred 33–56 dp on every failed sign-in;
///   · the band's edge crossed the first input field at a height that differed per device.
///
/// So the position is now computed from the WINDOW height — [MediaQueryData.size], which the
/// keyboard does not change — and never from the space that is left. The band's flat edge is a
/// fraction of the window; the card's top edge sits a fixed distance above it, so the band's
/// edge is always BEHIND the card and never across a field; the masthead sits directly above
/// the card. Nothing re-centres, so nothing jumps. When the keyboard would cover the focused
/// field the scroll view scrolls just enough to show it (each field passes a `scrollPadding`
/// that also keeps the primary button above the keyboard) — the platform's own behaviour, not
/// a re-layout.
///
/// A masthead too tall for its slot (large text on a short phone) grows the slot downward
/// instead of overlapping the card: the slot is a MINIMUM height, aligned to its bottom edge.
class AuthBandLayout extends StatelessWidget {
  const AuthBandLayout({
    super.key,
    required this.masthead,
    required this.card,
    this.compact = false,
  });

  /// White type on the band, bottom-aligned to sit directly above the card.
  final Widget masthead;

  /// The form. Constrained to 420 dp wide and centred, so a tablet gets a card and not a slab.
  final Widget card;

  /// A shallower band and a card that starts higher, for a form too tall to sit where the
  /// sign-in card does. The forced password change has three fields and a strength meter, and
  /// at the sign-in screen's position its Save and Sign out buttons fell off the bottom of a
  /// 360x640 phone; compact puts both on screen at text scale 1.0.
  final bool compact;

  /// The band's flat bottom edge, in logical pixels from the top of the window.
  static double seamFor(double windowHeight, {bool compact = false}) => compact
      ? (windowHeight * 0.24).clamp(150.0, 260.0)
      : math.max(windowHeight * 0.40, 220.0);

  /// How far the card's top edge reaches UP into the band. The band's edge is always behind
  /// the card by this much (plus the band's centre dip), never across a field.
  static double overlapFor({bool compact = false}) => compact ? 40.0 : 72.0;

  @override
  Widget build(BuildContext context) {
    // Read ABOVE the Scaffold: this is the window as the platform reports it. `size` does not
    // shrink when the keyboard opens — viewInsets does — which is the whole point.
    final media = MediaQuery.of(context);
    final seam = seamFor(media.size.height, compact: compact);
    final cardTop = seam - overlapFor(compact: compact);
    final gap = compact ? Space.xl : Space.xxl;
    final slot = math.max(0.0, cardTop - media.padding.top - gap);

    return Scaffold(
      // TRANSPARENT so the aurora underneath is the ground. Scaffold would otherwise paint its
      // own opaque background over it and the glow would never be seen.
      backgroundColor: Colors.transparent,
      body: AuroraField(
        child: BrandBrow(
          height: seam,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A MINIMUM, bottom-aligned: the masthead sits on the card's top edge at any
                  // size, and pushes the card down rather than under itself when it is taller
                  // than the slot.
                  Container(
                    constraints: BoxConstraints(minHeight: slot),
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(top: Space.md),
                    child: masthead,
                  ),
                  SizedBox(height: gap),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: card,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The room a field should keep clear BELOW itself when the keyboard scrolls it into view, so
/// the button that submits the form stays above the keyboard too.
///
/// [below] is the height of everything between the field's bottom edge and the bottom of that
/// button, at text scale 1.0. It is scaled with the user's text size, because every row it
/// stands for grows with it.
EdgeInsets keepVisibleBelow(BuildContext context, double below) {
  final k = MediaQuery.textScalerOf(context).scale(16) / 16;
  return EdgeInsets.fromLTRB(20, 20, 20, 20 + below * k);
}
