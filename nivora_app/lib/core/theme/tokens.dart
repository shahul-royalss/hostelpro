library;

import 'package:flutter/material.dart';

/// Nivora's design tokens. The single place any visual constant is defined.
///
/// The rule this file exists to enforce: changing the accent colour, the corner radius or the
/// motion curve must be a one-line edit here, never a search across screens. Nothing in
/// `features/` may hardcode a colour, a radius, a duration or a spacing value.
///
// ═════════════════════════════════════════════════════════════════════════════════════════
// PALETTE DECISIONS — READ BEFORE CHANGING A COLOUR
// ═════════════════════════════════════════════════════════════════════════════════════════
//
// Every value below was chosen against a measured WCAG 2.1 contrast ratio, not by eye. The
// ratios are quoted next to each token. If you change a value, re-measure; "it looked fine on
// my laptop" is how the previous palette ended up with 25 failing pairs. The audience for this
// app is a warden reading a phone in a corridor or in daylight, and an owner deciding whether
// to buy. Legibility is the product.
//
// WHAT WAS WRONG BEFORE (measured, light theme, against #FFFFFF):
//   success #22C55E  2.28:1     warning #F59E0B  2.15:1
//   error   #EF4444  3.76:1     info    #3B82F6  3.68:1
//   textMuted #98A2B3 2.58:1 — and it was the hint-text colour, which is text, so 4.5:1 applies
//   input border #E4E7EC 1.24:1 — a text field whose only boundary is a line you cannot see
//   the glass "hairline" was white-on-near-white at 1.01:1, i.e. it did not exist
// The one the brief asked about first, primary #5B5FEF on white, measured 4.85:1 — a pass, but
// only just, and 4.56:1 on the #F6F8FC canvas. Too little headroom for a cheap outdoor panel,
// so it was deepened to #5053D2 (5.98:1 / 5.63:1) without leaving the brand hue.
//
// ── THE ONE STRUCTURAL PROBLEM, AND WHY THERE ARE THREE SEMANTIC SETS ────────────────────
//
// A single flat colour CANNOT be AA-legible as text on both a white surface and a dark one.
// The proof is short, and it is arithmetic, not taste. To reach 4.5:1 on #FFFFFF a colour needs
// relative luminance L ≤ 0.18333. To reach 4.5:1 on #070B14 (L = 0.00335) it needs L ≥ 0.19008;
// on #101827 (L = 0.00910), where most text actually sits, L ≥ 0.21595. The windows do not
// overlap, at any hue — luminance is the only variable in the ratio, so hue cannot rescue it.
// Sweeping L in steps of 0.00002 for the value that maximises the WORST of the two ratios:
//
//   best possible single flat colour, white vs #070B14 : 4.44:1 at L = 0.18668
//   best possible single flat colour, white vs #101827 : 4.21:1 at L = 0.19910
//
// Both fail 4.5:1, and only by a hair, which is exactly why this keeps getting "fixed" back to
// one value by someone eyeballing it. It cannot be one value.
//
// So semantic colour comes in three sets and each has one job:
//
//   1. CANONICAL  — [NivoraColors.success] and friends. These are the IDENTITY of a meaning,
//      and the value that survives when a colour is painted without a BuildContext: chart
//      bars, meter fills, 16–18px status icons, tinted borders. Tuned to maximise the
//      worst case across both themes; every one clears the 3:1 that WCAG 1.4.11 asks of a
//      graphical object against ALL SIX surfaces — the three light (#FFFFFF, #F6F8FC,
//      #EEF2F8) and the three dark (#070B14, #101827, #151F32). Measured worst case per
//      colour: success 3.79, warning 3.83, error 3.79, info 3.78, textMuted 3.75.
//      They are NOT legible enough for small text. Do not put 11px type in them.
//
//   2. LIGHT TEXT — the `...Ink` values. AA on white and on the canvas (5.78–5.83:1).
//   3. DARK TEXT  — the `...Dark` values. AA on every dark surface (6.98–8.27:1).
//
//   Sets 2 and 3 are reached through [NivoraSemantics], the ThemeExtension registered on both
//   themes. At a paint site with a context, write `context.tones.error`. Where a canonical
//   colour has already been plumbed through a `tone:` parameter, call
//   `context.tones.resolve(tone)` — it maps a canonical value to the current theme's text
//   value and returns anything else untouched.
//
//   THIS IS THE RULE: canonical for shapes, resolved for type.
//
// ── SEMANTIC HUES ────────────────────────────────────────────────────────────────────────
//
// Green / amber / red / blue, kept because they are the meanings every user already knows, but
// all four pulled down out of the "traffic light" register. Overdue money is #B93434, a brick
// red, not #EF4444 — an owner scanning a list of arrears needs to read it as serious, and a
// screen of fire-alarm red stops anything meaning anything. Amber went to #8D5B06, which is
// the only way an amber reaches 4.5:1 on white at all.
//
// ── NEUTRALS ─────────────────────────────────────────────────────────────────────────────
//
// One cool-grey ramp, slightly blue so it sits under the navy monogram rather than fighting
// it, and three text steps only: primary 17.7:1, secondary 7.7:1, muted 5.7:1. Every step is
// legible; "muted" means quieter, never fainter than AA. Borders are split in two, because
// they have two different jobs and only one of them is regulated:
//   [NivoraColors.hairline]       decorative rules between same-coloured content. 1.2:1.
//   [NivoraColors.cardBorder]     a card's edge, backed up by the card's own fill. 1.5:1.
//   [NivoraColors.controlBorder]  the ONLY boundary a text field or outlined button has, so
//                                 WCAG 1.4.11 applies and it is 3.50:1 light / 3.73:1 dark.
//
// ── FULL MEASURED SET, AND HOW TO RE-MEASURE ─────────────────────────────────────────────
// Every text token was measured against all three of its theme's surfaces; every canonical
// colour as a graphical object against all six; both filled-button directions; all thirty
// status-chip combinations; and every glass pane against the backdrops that weight can sit
// over. All of them pass.
//
// These numbers are NOT decoration. `test/theme_contrast_test.dart` recomputes every one of
// them from these tokens and fails the build if a value drifts, so a colour changed by eye
// gets caught by `flutter test` rather than by a warden squinting at a corridor wall. If you
// change a colour, run the tests and read the failure — it prints the measured ratio.
// ═════════════════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// COLOUR
// ─────────────────────────────────────────────────────────────────────────────

/// The palette. Ratios in comments are measured, not estimated — see the header.
abstract final class NivoraColors {
  // ── brand ──────────────────────────────────────────────────────────────────
  /// Brand ink. The monogram's navy. Snackbars, scrims, shadow tint.
  static const midnight = Color(0xFF0B1220);

  /// The primary. Deepened from #5B5FEF so one value serves both directions:
  /// 5.98:1 as text/icon on white, and the same 5.98:1 for white sitting on it in a filled
  /// button. 5.63:1 on the canvas. Still unmistakably the NIVORA indigo.
  static const indigo = Color(0xFF5053D2);

  /// The primary on dark surfaces. 5.97:1 on #101827; ink on it is 6.29:1.
  static const darkIndigo = Color(0xFF898BF3);

  /// The one accent, used sparingly — never for meaning, only for a second voice on a chart
  /// or an illustrative fill. On dark it is legible as text (6.82:1 on #101827).
  static const softBlue = Color(0xFF7C9CFF);

  /// The same accent where it has to carry text on a light surface. 5.87:1 on white.
  static const softBlueInk = Color(0xFF3A5FC0);

  // ── light surfaces ─────────────────────────────────────────────────────────
  static const background = Color(0xFFF6F8FC); // canvas
  static const surface = Color(0xFFFFFFFF); // cards, sheets

  // ── light text ─────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFF111827); // 17.74:1 on white
  static const textSecondary = Color(0xFF475467); // 7.69:1 on white
  /// The canonical "muted" identity. Like the semantic colours it is a dual-theme compromise
  /// (4.21:1 light / 4.22:1 dark) because it is passed as a `tone:` into widgets that paint it
  /// without a context. For muted TEXT use `context.tones.muted`, which is 5.74:1 / 5.75:1.
  static const textMuted = Color(0xFF747C89);

  /// Muted text, light theme. 5.74:1 on white, 5.39:1 on the canvas.
  static const mutedInk = Color(0xFF5B6779);

  // ── light borders — three jobs, three tokens. See the header. ──────────────
  static const hairline = Color(0xFFE8EDF4); // dividers                      1.16:1
  static const cardBorder = Color(0xFFCBD5E1); // card + tile edges           1.48:1
  static const controlBorder = Color(0xFF7C8AA0); // inputs, outlined buttons 3.50:1

  // ── semantic, CANONICAL. Identity + graphics. Never small text. ────────────
  // Each clears 3:1 as a graphical object in both themes; see the header for why they cannot
  // also be text.
  static const success = Color(0xFF188D43); // 4.26:1 light / 4.17:1 dark
  static const warning = Color(0xFFA96D08); // 4.31:1 light / 4.13:1 dark
  static const error = Color(0xFFDC3F3F); // 4.35:1 light / 4.08:1 dark
  static const info = Color(0xFF3678E2); // 4.25:1 light / 4.18:1 dark

  // ── semantic, LIGHT-THEME TEXT. Reached via NivoraSemantics. ───────────────
  static const successInk = Color(0xFF147538); // 5.78:1 on white
  static const warningInk = Color(0xFF8D5B06); // 5.78:1
  static const errorInk = Color(0xFFB93434); // 5.83:1
  static const infoInk = Color(0xFF2D63BC); // 5.80:1

  // ── semantic, DARK-THEME TEXT. Reached via NivoraSemantics. ────────────────
  static const successDark = Color(0xFF22C55E); // 7.80:1 on #101827
  static const warningDark = Color(0xFFF59E0B); // 8.27:1
  static const errorDark = Color(0xFFF48080); // 6.98:1
  static const infoDark = Color(0xFF6FA3F8); // 7.00:1

  // ── dark surfaces ──────────────────────────────────────────────────────────
  // Authored, not inverted: elevation is expressed by getting LIGHTER, which is how depth
  // reads on an emissive panel. These three were already correct and are unchanged.
  static const darkBackground = Color(0xFF070B14);
  static const darkSurface = Color(0xFF101827);
  static const darkElevated = Color(0xFF151F32);

  // ── dark text ──────────────────────────────────────────────────────────────
  static const darkTextPrimary = Color(0xFFF8FAFC); // 16.98:1 on #101827
  static const darkTextSecondary = Color(0xFF94A3B8); // 6.93:1
  static const darkMuted = Color(0xFF8494AA); // 5.75:1

  // ── dark borders ───────────────────────────────────────────────────────────
  static const darkHairline = Color(0xFF212B3D);
  static const darkCardBorder = Color(0xFF2F3B50);
  static const darkControlBorder = Color(0xFF64748B); // 3.73:1 on #101827
}

// ─────────────────────────────────────────────────────────────────────────────
// SEMANTIC TONES — the theme-aware half of the palette.
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves a meaning to a colour that is legible *in the current theme*.
///
/// Registered on both themes, so `context.tones.error` is always the right red. See the
/// header of this file for why a single flat colour cannot do this job.
///
/// The chip recipe lives here too. A status chip is the one place where a semantic colour is
/// painted as 11px type on a tint of itself, which is the tightest contrast case in the app;
/// putting the fill/border/text alphas in one place is what stops a future chip from being
/// drawn at a plausible-looking alpha that fails.
@immutable
class NivoraSemantics extends ThemeExtension<NivoraSemantics> {
  const NivoraSemantics({
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.muted,
    required this.chipFillAlpha,
    required this.chipBorderAlpha,
  });

  /// AA as text on every surface of the light theme.
  static const light = NivoraSemantics(
    success: NivoraColors.successInk,
    warning: NivoraColors.warningInk,
    error: NivoraColors.errorInk,
    info: NivoraColors.infoInk,
    muted: NivoraColors.mutedInk,
    // 8% of a 5.8:1 ink still leaves 4.61:1 for the 11px text sitting on it, worst case
    // (errorInk on a chip over #EEF2F8). 12% measured 4.2:1 and fails.
    chipFillAlpha: 0.08,
    chipBorderAlpha: 0.28,
  );

  /// AA as text on every surface of the dark theme.
  static const dark = NivoraSemantics(
    success: NivoraColors.successDark,
    warning: NivoraColors.warningDark,
    error: NivoraColors.errorDark,
    info: NivoraColors.infoDark,
    muted: NivoraColors.darkMuted,
    // 10%, and this one is tighter than intuition says. A dark chip LOOKS like it can take
    // more tint than a light one, and the previous 0.14 was chosen on that basis — but the
    // tint lightens the fill toward the text it is sitting behind, so the ratio falls faster.
    // Measured worst case (darkMuted on a chip over #151F32): 0.14 → 4.33:1, a fail.
    // 0.12 → 4.47, still a fail. 0.10 → 4.62, which also lands within 0.01 of the light
    // theme's own worst case, so a chip reads the same weight in both themes.
    chipFillAlpha: 0.10,
    chipBorderAlpha: 0.34,
  );

  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color muted;
  final double chipFillAlpha;
  final double chipBorderAlpha;

  /// Maps a CANONICAL colour ([NivoraColors.success] and friends) to this theme's legible text
  /// value, and passes anything else through unchanged.
  ///
  /// This exists for the plumbing case: a widget is handed a `tone:` that was chosen far away,
  /// often inside a context-free `switch` over an enum. The caller keeps naming the meaning;
  /// the paint site fixes the theme.
  Color resolve(Color tone) {
    if (tone == NivoraColors.success) return success;
    if (tone == NivoraColors.warning) return warning;
    if (tone == NivoraColors.error) return error;
    if (tone == NivoraColors.info) return info;
    if (tone == NivoraColors.textMuted) return muted;
    return tone;
  }

  /// The fill behind a status chip, given either a canonical or a resolved tone.
  Color chipFill(Color tone) => resolve(tone).withValues(alpha: chipFillAlpha);

  /// The hairline around a status chip.
  Color chipBorder(Color tone) => resolve(tone).withValues(alpha: chipBorderAlpha);

  @override
  NivoraSemantics copyWith({
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? muted,
    double? chipFillAlpha,
    double? chipBorderAlpha,
  }) {
    return NivoraSemantics(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      muted: muted ?? this.muted,
      chipFillAlpha: chipFillAlpha ?? this.chipFillAlpha,
      chipBorderAlpha: chipBorderAlpha ?? this.chipBorderAlpha,
    );
  }

  @override
  NivoraSemantics lerp(ThemeExtension<NivoraSemantics>? other, double t) {
    if (other is! NivoraSemantics) return this;
    return NivoraSemantics(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      chipFillAlpha: lerpDouble(chipFillAlpha, other.chipFillAlpha, t),
      chipBorderAlpha: lerpDouble(chipBorderAlpha, other.chipBorderAlpha, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// `context.tones.error` — the short way to the theme's semantic colours.
extension NivoraTonesX on BuildContext {
  NivoraSemantics get tones =>
      Theme.of(this).extension<NivoraSemantics>() ?? NivoraSemantics.light;
}

// ─────────────────────────────────────────────────────────────────────────────
// SPACING — one 4dp rhythm. Anything not on it is a mistake.
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
  /// Something too small to have a corner radius in the usual sense: a 10dp legend swatch, a
  /// bed square on the room grid. Anything larger takes [control] or above.
  static const tiny = 4.0;
  static const control = 12.0; // buttons, inputs, chips
  static const card = 16.0; // cards, list groups
  static const surface = 20.0; // large panels
  static const sheet = 28.0; // bottom sheets, modals

  /// Fully round ends. Only for things that are genuinely capsule-shaped and never contain a
  /// second line of text: a progress track, a drag handle. A status pill uses [control] — a
  /// capsule that wraps looks broken, and status wording is not under our control.
  static const pill = 999.0;

  static const rTiny = BorderRadius.all(Radius.circular(tiny));
  static const rControl = BorderRadius.all(Radius.circular(control));
  static const rCard = BorderRadius.all(Radius.circular(card));
  static const rSurface = BorderRadius.all(Radius.circular(surface));
  static const rSheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
  static const rPill = BorderRadius.all(Radius.circular(pill));
}

// ─────────────────────────────────────────────────────────────────────────────
// ICONS + STROKES — the one-off `size: 13` was the tell that these were missing.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class IconSize {
  static const xs = 14.0; // inside a chip
  static const sm = 16.0; // beside a label
  static const md = 18.0; // list rows, section headings
  static const lg = 22.0; // app bar, nav

  /// The single glyph over an empty or failed section. One size for both: an empty list and a
  /// broken one are the same weight of event, and drawing them at 36 and 32 was two people
  /// guessing rather than a decision.
  static const xl = 32.0;
}

/// Every border in the app is one physical hairline. Weight comes from colour, not width.
abstract final class Strokes {
  static const hairline = 1.0;
  static const focus = 1.6; // the only place a border is allowed to thicken
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS — an elevation treatment, not a skin.
// ─────────────────────────────────────────────────────────────────────────────

/// Three weights only. More than three and "glass" stops meaning anything, and stacking them
/// is what makes an interface look cheap rather than expensive.
///
/// ── THE MODEL: A PANE IS ITS OWN THEME'S SURFACE, HELD BACK ──────────────────────────────
///
/// A glass pane paints `colorScheme.surface` at [opacity], and lets the remaining fraction of
/// whatever is behind show through a blur. That is the whole model, and the important half is
/// the WORD "surface": in the light theme the veil is white, and in the dark theme it is
/// #101827 — it is not white at a smaller number.
///
/// This is the thing the previous pass had backwards, and it is worth spelling out because it
/// looks right on a static mock and fails the moment anything moves. A white veil over a dark
/// theme LIGHTENS the pane. Dark-theme text is near-white. So the brighter the thing sliding
/// under the pane, the lighter the pane gets, and the harder its own text becomes to read —
/// the effect works backwards. Measured, with the old white-veil numbers, a pane over a filled
/// #898BF3 button:
///
///   thin    primary text 2.66:1   muted 1.11:1
///   regular primary text 2.59:1   muted 1.14:1
///   thick   primary text 2.50:1   muted 1.18:1
///
/// and no opacity fixes it, because raising a WHITE veil toward 1.0 walks the pane toward pure
/// white, which is worse. Solving for the veil opacity needed to keep dark-theme muted text at
/// 4.5:1 returns "impossible" for every backdrop brighter than the surface itself. Veiling
/// with the surface colour instead makes the pane converge on the card colour it should have
/// been, and the same solve returns 0.84 for a filled button and 0.915 for pure white behind.
///
/// ── THE NUMBERS, AND WHAT EACH WEIGHT ACTUALLY SITS OVER ─────────────────────────────────
///
/// Opacity per weight is chosen from what can be BEHIND that weight, not by taste. The bar is
/// that the weakest body text in the theme (mutedInk 5.74:1 light, darkMuted 5.75:1 dark)
/// still clears 4.5:1 on the composited pane:
///
///   thin     0.72   only ever over the page canvas. Nothing saturated is behind a resting
///                   card, so this one can stay genuinely translucent.   worst 5.64:1
///   regular  0.88   a header with the page scrolling beneath, so it has to survive a filled
///                   indigo card passing under it.                       worst 4.83:1
///   thick    0.94   a sheet over anything at all, including pure white in the dark theme.
///                   Barely translucent, on purpose — a sheet you cannot read is not a
///                   design, it is a bug.                                worst 4.92:1
///
/// ONE DEPENDENCY WORTH KNOWING ABOUT. `regular` at 0.88 is sized for the brightest thing this
/// app can currently put under a header, which is a filled primary button. It is NOT enough
/// for a large bright area: a dark-theme pane over pure white measures 4.06:1 and fails. That
/// is fine today because the app renders no images at all — `students.photo_url` and
/// `complaints.photo_url` are keys into a private bucket, and the profile screen draws initials
/// rather than a photo, on purpose. The day someone signs those URLs and puts a real picture in
/// a scrolling list, `regular` needs to go to 0.92 and this comment is the reason why.
///
/// Both themes use the same number now, because the veil is each theme's own surface and the
/// requirement is symmetric. One number per weight instead of two is not a simplification for
/// its own sake — it is the model being right.
///
/// Blur came down from sigma 18/24/32. Above ~20 the cost climbs steeply on mid-range Android
/// for no perceptual gain: what reads as glass is the hairline and the movement behind it, not
/// the amount of frosting. See [Motion.glassFallback].
enum GlassWeight {
  /// A resting card. The ONLY thing behind it is the page canvas.
  thin(blur: 8, opacity: 0.72),

  /// A bar or header that the page's own content scrolls beneath.
  regular(blur: 14, opacity: 0.88),

  /// A sheet or modal over arbitrary content.
  thick(blur: 20, opacity: 0.94);

  const GlassWeight({required this.blur, required this.opacity});

  /// Sigma for the backdrop filter. Kept low deliberately.
  final double blur;

  /// How much of the theme's surface colour the pane paints. See the model above.
  final double opacity;

  /// Alpha of the INK hairline that edges a pane in the light theme, over the pane itself:
  /// 1.41:1, the same visual register as [NivoraColors.cardBorder] (1.48:1). The old code drew
  /// a WHITE border on a near-white pane, which measured 1.01:1 — i.e. it did not exist, and a
  /// pane with no edge is just a pale rectangle.
  ///
  /// Weight-independent on purpose: the edge says "this is a pane", and that sentence does not
  /// get louder for a sheet than for a card.
  static const lightEdge = 0.16;

  /// Alpha of the white hairline in the dark theme, where the edge has to be lighter than the
  /// fill to read at all. 1.50:1 over the pane, matching [NivoraColors.darkCardBorder] (1.58:1).
  static const darkEdge = 0.14;
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

  /// How long an inline confirmation stays on the control that produced it — the "Copied" that
  /// replaces a copy button's label, and anything else that swaps a label and swaps it back.
  /// Not an animation either: long enough to be read, short enough that a second tap reads as a
  /// second confirmation rather than as the first one still hanging around.
  static const confirmed = Duration(milliseconds: 1600);

  /// How long a snackbar carrying a FAILURE stays up. Not an animation — a reading budget.
  /// Material's default 4s is sized for "Saved"; the sentences this app shows on a refusal are
  /// a full line ("Bed 3 is already occupied. Choose a free bed.") and a warden reads them
  /// while talking to somebody.
  static const readMessage = Duration(seconds: 5);

  /// Set true when the device cannot afford real backdrop blur. Glass widgets then paint an
  /// opaque tinted surface instead: the layout is identical, only the filter is skipped, so
  /// nothing reflows. Performance beats the effect — a janky premium interface is neither.
  static bool glassFallback = false;
}

// ─────────────────────────────────────────────────────────────────────────────
// ELEVATION — three levels. Shadows stay near-transparent and tinted with the brand navy
// rather than black, which is what keeps depth from looking like dirt.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class Shadows {
  static const level1 = <BoxShadow>[]; // background: no shadow

  /// A resting card. One shadow, barely there — on a minimal surface the hairline does the
  /// work of separating the card and the shadow only stops it looking pasted on.
  static const level2 = <BoxShadow>[
    BoxShadow(color: Color(0x0A0B1220), blurRadius: 10, offset: Offset(0, 1)),
  ];

  /// Something genuinely floating: a sheet, a modal, a menu.
  static const level3 = <BoxShadow>[
    BoxShadow(color: Color(0x1A0B1220), blurRadius: 32, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x0D0B1220), blurRadius: 6, offset: Offset(0, 2)),
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
