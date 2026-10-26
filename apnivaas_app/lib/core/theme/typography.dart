import 'package:flutter/material.dart';

import 'tokens.dart';

/// Apnivaas's type scale — Outfit for what you glance at, Manrope for what you read.
///
/// ── TWO FAMILIES, SEVEN STATIC FILES, ALL BUNDLED ────────────────────────────────────────
///
/// **Outfit** (500, 600, 700) sets headings, screen titles and display figures: a geometric
/// face with the logo's soft, round build. **Manrope** (400, 500, 600, 700) sets everything a
/// person reads — body, labels, list rows, buttons — and every figure that refreshes, because
/// its tabular digits are built for columns. Both come from the canvas and nothing else.
///
/// They are declared as two ordinary `fonts:` families in pubspec.yaml, pointing at the files
/// in `google_fonts/`. That is a change from the Inter era, when the faces were resolved
/// through `GoogleFonts.inter`: a style then carried `fontFamily: 'Inter_600'`, so a bare
/// `copyWith(fontWeight: …)` at a call site changed the number and kept the old face, silently.
/// With declared families the engine picks the face from the weight, so `copyWith` does what it
/// says, and the theme no longer touches the google_fonts package at all — which is also what
/// lets a widget test build the real theme without reaching for the network.
///
/// EVERY FILE WAS CHECKED, NOT ASSUMED: each has its own `usWeightClass` and its own `glyf`
/// table (this project has twice shipped one face under several weight names), Manrope has
/// U+20B9 ₹ and the `tnum` feature, and Outfit has `tnum` but NO ₹. So every Outfit style
/// falls back to Manrope, and a rupee figure set in Outfit draws its ₹ in Manrope at the same
/// weight. `test/theme_contrast_test.dart` reads all of this off the files.
///
/// ── THE SCALE ────────────────────────────────────────────────────────────────────────────
///
/// Each Material slot keeps the JOB it had, so the ~600 existing call sites keep their meaning
/// and only their look changes.
///
///   slot             family   px/line/wt   job
///   ─────────────────────────────────────────────────────────────────────────────────────
///   displayLarge     Outfit   28/32/700    the one hero figure per screen        tabular
///   headlineLarge    Outfit   28/32/700    = displayLarge                        tabular
///   displayMedium    Outfit   28/32/600    a stepper / onboarding H1
///   displaySmall     Outfit   22/28/600    the screen title
///   headlineMedium   Outfit   22/28/700    a stat tile's value                   tabular
///   titleLarge       Outfit   20/26/600    a page section heading
///   headlineSmall    Outfit   18/24/600    a card heading, a figure in a heading tabular
///   titleMedium      Manrope  14/20/700    a list row's title
///   titleSmall       Manrope  13/18/700    a figure in a row, a field label      tabular
///   bodyLarge        Manrope  15/22/400    reading text
///   bodyMedium       Manrope  13/18/400    supporting text
///   bodySmall        Manrope  12/16/400    meta, timestamps
///   labelLarge       Manrope  15/20/700    outlined and text buttons
///   labelMedium      Manrope  12/16/700    tile and tab labels, chips
///   labelSmall       Manrope  11/14/700    a floating field label, a count       tabular
///
/// Nothing is under 11. Sentence case everywhere: the scale carries no caps tracking, and the
/// few legacy widgets that still uppercase a label do it to keep a test contract, not a style.
///
/// ── NUMBERS ──────────────────────────────────────────────────────────────────────────────
///
/// Money and counts are the point of this product, so every slot that can hold a figure asks
/// for tabular figures. Proportional digits let a column of rupee amounts shuffle sideways by a
/// pixel per row, and a refreshing dashboard jitters. If you add a slot that will hold a
/// number, wrap it with [ApnivaasType.tabular].
abstract final class ApnivaasType {
  /// The reading family: body, labels, buttons, refreshing figures.
  static const family = 'Manrope';

  /// The display family: headings and static display figures.
  static const display = 'Outfit';

  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle _style({
    required String family,
    required double size,
    required double lineHeight,
    required FontWeight w,
    required Color color,
    double letterSpacing = 0,
    bool tabular = false,
  }) {
    final isDisplay = family == display;
    return TextStyle(
      fontFamily: family,
      // Outfit has no ₹; Manrope does, at every weight Outfit is used at.
      fontFamilyFallback: isDisplay ? const [ApnivaasType.family] : null,
      fontSize: size,
      height: lineHeight / size,
      fontWeight: w,
      letterSpacing: letterSpacing,
      color: color,
      fontFeatures: tabular ? _tabular : null,
      // Outfit's tall ascender otherwise sits its text high inside pills and buttons.
      leadingDistribution: isDisplay ? TextLeadingDistribution.even : null,
    );
  }

  static TextStyle outfit(double size, double lineHeight, FontWeight w, Color color,
          {double letterSpacing = 0, bool tabular = false}) =>
      _style(
          family: display,
          size: size,
          lineHeight: lineHeight,
          w: w,
          color: color,
          letterSpacing: letterSpacing,
          tabular: tabular);

  static TextStyle manrope(double size, double lineHeight, FontWeight w, Color color,
          {double letterSpacing = 0, bool tabular = false}) =>
      _style(
          family: family,
          size: size,
          lineHeight: lineHeight,
          w: w,
          color: color,
          letterSpacing: letterSpacing,
          tabular: tabular);

  /// The scale, in [primary] ink for what leads and [secondary] ink for what supports.
  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      // ── 28/700, tracking −0.2. THE one big figure per screen.
      displayLarge: outfit(28, 32, FontWeight.w700, primary, letterSpacing: -0.2, tabular: true),
      headlineLarge: outfit(28, 32, FontWeight.w700, primary, letterSpacing: -0.2, tabular: true),

      // ── 28/600. The role picker and onboarding headline.
      displayMedium: outfit(28, 32, FontWeight.w600, primary),

      // ── 22/600. The screen title. One per screen.
      displaySmall: outfit(22, 28, FontWeight.w600, primary),

      // ── 22/700 tabular. A stat tile's value.
      headlineMedium: outfit(22, 28, FontWeight.w700, primary, tabular: true),

      // ── 20/600. "Overview" — a page section heading.
      titleLarge: outfit(20, 26, FontWeight.w600, primary),

      // ── 18/600 tabular. "Quick actions" — a card's heading, or a figure inside one.
      headlineSmall: outfit(18, 24, FontWeight.w600, primary, tabular: true),

      // ── 14/700. A list row's title: "6 tenants haven't paid".
      titleMedium: manrope(14, 20, FontWeight.w700, primary),

      // ── 13/700 tabular. A figure in a row, a small button, a field label.
      titleSmall: manrope(13, 18, FontWeight.w700, primary, tabular: true),

      // ── 15/400. Reading text.
      bodyLarge: manrope(15, 22, FontWeight.w400, primary),

      // ── 13/400. Supporting text, in the quieter ink.
      bodyMedium: manrope(13, 18, FontWeight.w400, secondary),

      // ── 12/400. Meta: a timestamp, "Raised 2 hours ago".
      bodySmall: manrope(12, 16, FontWeight.w400, secondary),

      // ── 15/700. Outlined and text buttons. Filled buttons take [ApnivaasTextRoles.cta].
      labelLarge: manrope(15, 20, FontWeight.w700, primary),

      // ── 12/700. A quick-action label, a tab label, a chip.
      labelMedium: manrope(12, 16, FontWeight.w700, primary),

      // ── 11/700 tabular, a hair of tracking. A floating field label, a badge count.
      labelSmall: manrope(11, 14, FontWeight.w700, secondary, letterSpacing: 0.2, tabular: true),
    );
  }

  /// For a figure that must not change width while it animates or refreshes.
  static TextStyle tabular(TextStyle s) => s.copyWith(fontFeatures: _tabular);

  /// Moves a style to another weight.
  ///
  /// A plain `copyWith(fontWeight:)` now that the families are declared in the pubspec — the
  /// engine picks the face from the weight. Kept so existing call sites compile and there is
  /// still one obvious place to look. Outfit ships 500/600/700 and Manrope 400–700; a weight
  /// outside those lands on the nearest bundled face rather than downloading anything.
  static TextStyle weight(TextStyle s, FontWeight w) => s.copyWith(fontWeight: w);
}

/// The type roles the Material slots do not cover. Registered on both themes; read it with
/// `context.textRoles`.
@immutable
class ApnivaasTextRoles extends ThemeExtension<ApnivaasTextRoles> {
  const ApnivaasTextRoles({
    required this.cta,
    required this.tileTitle,
    required this.heroHeadline,
    required this.dateNumeral,
    required this.fieldValue,
    required this.formSection,
    required this.statValue,
  });

  /// The roles in [ink], for the theme whose primary text that is.
  factory ApnivaasTextRoles.of(Color ink) => ApnivaasTextRoles(
        cta: ApnivaasType.outfit(17, 22, FontWeight.w600, ink),
        tileTitle: ApnivaasType.outfit(17, 22, FontWeight.w600, ink),
        heroHeadline: ApnivaasType.outfit(24, 28, FontWeight.w600, ink),
        dateNumeral: ApnivaasType.outfit(19, 22, FontWeight.w600, ink, tabular: true),
        fieldValue: ApnivaasType.manrope(15, 22, FontWeight.w500, ink),
        formSection: ApnivaasType.outfit(15, 18, FontWeight.w600, ink),
        statValue: ApnivaasType.outfit(28, 32, FontWeight.w700, ink, tabular: true),
      );

  /// A filled button's label: Outfit 17/600.
  final TextStyle cta;

  /// A banner's or a link tile's title: Outfit 17/600.
  final TextStyle tileTitle;

  /// The sign-in hero card's headline: Outfit 24/600.
  final TextStyle heroHeadline;

  /// The date on a day chip: Outfit 19/600, tabular.
  final TextStyle dateNumeral;

  /// The value typed into a field: Manrope 15/500.
  final TextStyle fieldValue;

  /// A form section heading: Outfit 15/600.
  final TextStyle formSection;

  /// The figure on the forest hero stat tile: Outfit 28/700, tabular.
  final TextStyle statValue;

  @override
  ApnivaasTextRoles copyWith({
    TextStyle? cta,
    TextStyle? tileTitle,
    TextStyle? heroHeadline,
    TextStyle? dateNumeral,
    TextStyle? fieldValue,
    TextStyle? formSection,
    TextStyle? statValue,
  }) =>
      ApnivaasTextRoles(
        cta: cta ?? this.cta,
        tileTitle: tileTitle ?? this.tileTitle,
        heroHeadline: heroHeadline ?? this.heroHeadline,
        dateNumeral: dateNumeral ?? this.dateNumeral,
        fieldValue: fieldValue ?? this.fieldValue,
        formSection: formSection ?? this.formSection,
        statValue: statValue ?? this.statValue,
      );

  @override
  ApnivaasTextRoles lerp(ThemeExtension<ApnivaasTextRoles>? other, double t) {
    if (other is! ApnivaasTextRoles) return this;
    return ApnivaasTextRoles(
      cta: TextStyle.lerp(cta, other.cta, t)!,
      tileTitle: TextStyle.lerp(tileTitle, other.tileTitle, t)!,
      heroHeadline: TextStyle.lerp(heroHeadline, other.heroHeadline, t)!,
      dateNumeral: TextStyle.lerp(dateNumeral, other.dateNumeral, t)!,
      fieldValue: TextStyle.lerp(fieldValue, other.fieldValue, t)!,
      formSection: TextStyle.lerp(formSection, other.formSection, t)!,
      statValue: TextStyle.lerp(statValue, other.statValue, t)!,
    );
  }
}

/// `context.textRoles.cta` — the type roles outside the Material slots. Falls back to the
/// light theme's ink for a widget pumped without an Apnivaas theme.
extension ApnivaasTextRolesX on BuildContext {
  ApnivaasTextRoles get textRoles =>
      Theme.of(this).extension<ApnivaasTextRoles>() ?? _fallback;
}

final _fallback = ApnivaasTextRoles.of(ApnivaasColors.ink);
