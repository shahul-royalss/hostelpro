library;

import 'package:flutter/widgets.dart';

/// Nivora's design tokens. The single place any visual constant is defined.
///
/// The rule this file exists to enforce: changing the accent colour, the corner radius or the
/// motion curve must be a one-line edit here, never a search across screens. Nothing in
/// `features/` may hardcode a colour, a radius, a duration or a spacing value.
///
/// Values come from the product brief verbatim. Where the brief gave a range (glass opacity
/// 10–18%) the choices are pinned to specific numbers and the reasoning recorded, so a later
/// reader can tell a decision from an accident.

// ─────────────────────────────────────────────────────────────────────────────
// COLOUR
// ─────────────────────────────────────────────────────────────────────────────

/// Light mode. The interface should read navy + white + indigo; semantic colours are for
/// meaning, not decoration, which is why they are grouped separately below.
abstract final class NivoraColors {
  // brand
  static const midnight = Color(0xFF0B1220); // primary dark: nav, headers, dark surfaces
  static const indigo = Color(0xFF5B5FEF); // primary accent: buttons, active, links
  static const softBlue = Color(0xFF7C9CFF); // secondary accent — sparingly

  // light surfaces
  static const background = Color(0xFFF6F8FC);
  static const surface = Color(0xFFFFFFFF);

  // text
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF667085);
  static const textMuted = Color(0xFF98A2B3);

  // semantic — use only to carry meaning
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);

  // dark mode. Deliberately designed, not an inversion: the dark background is cooler and
  // darker than the light background is light, and elevation is expressed by getting LIGHTER,
  // which is how depth reads on an emissive display.
  static const darkBackground = Color(0xFF070B14);
  static const darkSurface = Color(0xFF101827);
  static const darkElevated = Color(0xFF151F32);
  static const darkTextPrimary = Color(0xFFF8FAFC);
  static const darkTextSecondary = Color(0xFF94A3B8);

  /// Lifted from #5B5FEF: at the contrast ratios a dark surface demands, the light-mode indigo
  /// sits too close to the background to carry an active state.
  static const darkIndigo = Color(0xFF7C83FF);
}

// ─────────────────────────────────────────────────────────────────────────────
// SPACING — a single scale. Anything not on it is a mistake.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class Space {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;
  static const huge = 48.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// RADIUS — graduated by surface size, so a chip and a sheet are not equally round.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class Radii {
  static const control = 12.0; // buttons, inputs, chips
  static const card = 18.0; // cards, list groups
  static const surface = 24.0; // large panels
  static const sheet = 28.0; // bottom sheets, modals

  static const rControl = BorderRadius.all(Radius.circular(control));
  static const rCard = BorderRadius.all(Radius.circular(card));
  static const rSurface = BorderRadius.all(Radius.circular(surface));
  static const rSheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS — an elevation treatment, not a skin.
// ─────────────────────────────────────────────────────────────────────────────

/// Three weights only. More than three and "glass" stops meaning anything, and stacking them
/// is what makes an interface look cheap rather than expensive.
enum GlassWeight {
  /// Resting cards over the page background.
  thin(tint: 0.10, blur: 18, border: 0.30),

  /// Bars and headers that content scrolls beneath.
  regular(tint: 0.14, blur: 24, border: 0.38),

  /// Sheets and modals, which must stay readable over arbitrary content.
  thick(tint: 0.18, blur: 32, border: 0.45);

  const GlassWeight({required this.tint, required this.blur, required this.border});

  /// White overlay opacity. The brief's 10–18% range, pinned per weight.
  final double tint;

  /// Sigma for the backdrop filter. Above ~32 the cost climbs steeply on mid-range Android
  /// for no perceptual gain — see [Motion.glassFallback].
  final double blur;

  /// Hairline border opacity. The border is what actually reads as "a pane of glass";
  /// without it a translucent box just looks washed out.
  final double border;
}

// ─────────────────────────────────────────────────────────────────────────────
// MOTION
// ─────────────────────────────────────────────────────────────────────────────

abstract final class Motion {
  /// The brief's 150–350ms band. Fast enough to feel like a response, slow enough to be read.
  static const fast = Duration(milliseconds: 150); // press feedback, colour change
  static const base = Duration(milliseconds: 240); // cards, tabs, list items
  static const slow = Duration(milliseconds: 340); // sheets, page transitions

  /// Decelerating: motion that enters the screen should arrive, not bounce.
  static const enter = Curves.easeOutCubic;

  /// Symmetric, for things that move within the screen.
  static const move = Curves.easeInOutCubic;

  /// Set true when the device cannot afford real backdrop blur. Glass widgets then paint an
  /// opaque tinted surface instead: the layout is identical, only the filter is skipped, so
  /// nothing reflows. Performance beats the effect — a janky premium interface is neither.
  static bool glassFallback = false;
}

// ─────────────────────────────────────────────────────────────────────────────
// ELEVATION — three levels, matching the brief. Shadows stay near-transparent and tinted with
// the brand navy rather than black, which is what keeps depth from looking like dirt.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class Shadows {
  static const level1 = <BoxShadow>[]; // background: no shadow

  static const level2 = <BoxShadow>[
    BoxShadow(color: Color(0x0D0B1220), blurRadius: 12, offset: Offset(0, 2)),
  ];

  static const level3 = <BoxShadow>[
    BoxShadow(color: Color(0x140B1220), blurRadius: 28, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A0B1220), blurRadius: 4, offset: Offset(0, 1)),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// BREAKPOINTS — phones are the design target; tablets get more columns, not bigger text.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class Breakpoints {
  static const compact = 360.0; // smallest phone still supported
  static const medium = 600.0; // large phone / small tablet
  static const expanded = 900.0; // tablet
}
