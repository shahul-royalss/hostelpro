import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Nivora's type scale — the Figma scale, mapped onto Material's slots.
///
/// ── ONE FAMILY, FIVE STATIC FILES ────────────────────────────────────────────────────────
///
/// **Inter, and nothing else.** Every text node in the nineteen Figma frames is
/// `font-['Inter:...']`. Plus Jakarta Sans, which the Stitch restyle used for everything
/// above `label-caps`, is gone: its file was deleted and its `fonts:` block removed from
/// pubspec.yaml. Do not re-add a second family without a mockup that shows one.
///
/// Inter is bundled as four STATIC files under `assets: google_fonts/`, which the
/// `google_fonts` package resolves from the bundle by filename — `Inter-<Variant>.ttf` maps to
/// a weight by name, so `Inter-ExtraBold.ttf` is w800. `main.dart` sets
/// `GoogleFonts.config.allowRuntimeFetching = false`, so a weight used without shipping its
/// file throws in debug instead of quietly downloading in production. The four shipped are
/// Regular 400, SemiBold 600, Bold 700 and **ExtraBold 800**; this file uses exactly those.
/// Adding a fifth reintroduces the download for that one weight.
///
/// MEDIUM 500 WAS DROPPED, and the reasoning is worth keeping because it is easy to re-add by
/// reflex. No slot below asks for it, and [NivoraType.weight] — the one API that could request
/// an arbitrary weight at runtime — has no callers. The only `FontWeight.w500` in the app is in
/// features/payments/receipt_paper.dart, and that style sets `fontFamily: 'monospace'`, a
/// PLATFORM font: the weight applies to Android's own mono face, never to Inter. So the file was
/// 408 KB that nothing could reach. If a slot ever does want 500, ship the file again — with
/// `allowRuntimeFetching` false a missing weight silently lands on the nearest bundled one
/// rather than downloading, so it fails quietly rather than loudly.
///
/// ── THE HERO IS REALLY 800 ───────────────────────────────────────────────────────────────
///
/// The design's one big figure is `32 / ExtraBold`, and the wordmark on `screen-signin` is
/// `24 / Extra_Bold`. The app previously had no 800 face, and the two ways of faking one both
/// fail silently: `google_fonts` with runtime fetching off throws, and with it on it downloads
/// on first launch. So the file was ADDED rather than the weight downgraded —
/// `google_fonts/Inter-ExtraBold.ttf`, 327KB, `usWeightClass` 800, 2849 codepoints including
/// U+20B9 (₹, which is the glyph the hero exists to draw).
///
/// IT WAS CHECKED FOR BEING A DISTINCT FACE, not assumed. This project has twice shipped
/// byte-identical files under different weight names — four copies of the same 400 registered
/// as four weights, which makes every heading render regular while the pubspec looks correct.
/// The five files now in `google_fonts/` have five different md5s, five different `glyf` table
/// hashes, five different `hmtx` tables and five different `usWeightClass` values.
///
/// ── CHANGING A WEIGHT AT A CALL SITE ─────────────────────────────────────────────────────
///
/// [NivoraType.weight] is now a plain `copyWith(fontWeight:)`. It used to be load-bearing,
/// because a variable font follows its `wght` variation and ignores `fontWeight`; with static
/// faces there is no variation to fight. The helper survives so the ~existing call sites keep
/// compiling and so there is still one obvious place to look.
///
/// ── THE SCALE ────────────────────────────────────────────────────────────────────────────
///
/// `design-figma/DESIGN-SYSTEM.md` records six steps — hero 32/800 · title 16/700 ·
/// body 13/400–600 · label-caps 12/600 UPPERCASE · meta 11/400 · chip 10/600 — and the frames
/// add 24 (the wordmark), 20 ("Welcome back"), 15 (a hostel name), 14 (a button label) and 9
/// (a state badge). Material has more slots than that, so the mapping is written out here
/// rather than left to be guessed. Every size below is a size that appears in the file.
///
///   slot             px/line/wt   design source                            used for
///   ───────────────────────────────────────────────────────────────────────────────────────
///   displayLarge     32/40/800    hero (4:947's ₹ figure)          THE hero figure   tabular
///   headlineLarge    32/40/800    = displayLarge                                     tabular
///   displayMedium    24/32/800    wordmark (4:69)                  a second hero     tabular
///   displaySmall     24/32/700    —                                the screen title
///   headlineMedium   20/28/700    "Welcome back" (4:73) at bold    a stat card value tabular
///   titleLarge       20/28/700    "Welcome back" (4:73)            section heading
///   titleMedium      16/24/700    title 16/700 (4:1543)            row / card title
///   headlineSmall    16/24/700    = titleMedium                    a toned figure    tabular
///   bodyLarge        15/22/400    hostel name size (4:451)         reading text
///   labelLarge       14/20/600    "Continue" (4:84)                button + tab labels
///   titleSmall       13/18/600    body semibold (4:1555)           a stat in a row   tabular
///   bodyMedium       13/18/400    body 13/400 (4:74)               supporting text
///   labelMedium      12/16/600    label-caps                       an uppercase label
///   bodySmall        11/16/400    meta 11/400 (4:1585)             metadata, timestamps
///   labelSmall       10/14/600    chip 10/600 (4:462)              eyebrows, chips   tabular
///
/// Three decisions in there are worth defending:
///
/// * **The screen title dropped 28 → 24.** 28 is not a size in this file. 24 is — it is the
///   wordmark — and it still leaves a clear step down to a 20 section heading.
///
/// * **Body text is 13, not 14.** The design's running text is `text-[13px]` on every screen
///   that has any, and its 14 is reserved for a button label and an input's own value. So
///   [bodyMedium] is 13 and [labelLarge] is 14, which is the opposite of the Material default
///   and is why they are spelled out.
///
/// * **Buttons are 14 semibold, not `label-caps`.** The mockups do set some quiet text buttons
///   in 12px uppercase — that is [labelSmall]/[labelMedium] and screens should use it. But the
///   app's primary CTAs are 48dp filled buttons carrying sentences ("Record payment", "Assign
///   bed"), and the design's own filled button (4:84) is 14 semibold sentence case.
///
/// Hierarchy comes from size, then colour, then weight. The design's headings ARE w700, and
/// its one hero is w800.
///
/// ── NUMBERS ──────────────────────────────────────────────────────────────────────────────
///
/// Money and counts are the point of this product, so every slot that can hold a figure asks
/// for tabular figures. Proportional digits let a column of rupee amounts shuffle sideways by
/// a pixel or two per row, and a refreshing dashboard jitters. Tabular digits are all one
/// width: columns line up, and a value animating ₹9,900 → ₹10,100 does not shove its
/// neighbours. If you add a slot that will hold a number, wrap it with [NivoraType.tabular].
abstract final class NivoraType {
  /// The one family. Every style in this file is Inter; nothing else is bundled.
  static const family = 'Inter';

  static const _tabular = [FontFeature.tabularFigures()];

  /// An Inter style at [size] / [lineHeight] px and weight [w].
  ///
  /// Goes through `GoogleFonts.inter` rather than `fontFamily: 'Inter'` because the faces are
  /// bundled as five separate static files rather than declared as one `family:` in the
  /// pubspec; google_fonts is what maps `Inter-ExtraBold.ttf` onto w800.
  static TextStyle _inter({
    required double size,
    required double lineHeight,
    required FontWeight w,
    required Color color,
    double letterSpacing = 0,
    bool tabular = false,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      height: lineHeight / size,
      fontWeight: w,
      letterSpacing: letterSpacing,
      color: color,
      fontFeatures: tabular ? _tabular : null,
    );
  }

  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      // ── hero 32/800, tracking −0.02em. THE one big figure per screen, and the loudest thing
      //    on it on purpose. This is the only place the ExtraBold face is worth its 327KB.
      displayLarge: _inter(
          size: 32, lineHeight: 40, w: FontWeight.w800, letterSpacing: -0.64, color: primary, tabular: true),
      headlineLarge: _inter(
          size: 32, lineHeight: 40, w: FontWeight.w800, letterSpacing: -0.64, color: primary, tabular: true),

      // ── 24/800 — the wordmark's weight and size. A second-order hero: the figure at the top
      //    of a section that is not the screen's single headline.
      displayMedium: _inter(
          size: 24, lineHeight: 32, w: FontWeight.w800, letterSpacing: -0.36, color: primary, tabular: true),

      // ── 24/700. The screen title. One per screen.
      displaySmall: _inter(size: 24, lineHeight: 32, w: FontWeight.w700, color: primary),

      // ── 20/700 tabular. A stat card's value.
      headlineMedium: _inter(size: 20, lineHeight: 28, w: FontWeight.w700, color: primary, tabular: true),

      // ── 20/700. Section headings.
      titleLarge: _inter(size: 20, lineHeight: 28, w: FontWeight.w700, color: primary),

      // ── 16/700 tabular. A toned figure inside a section heading.
      headlineSmall: _inter(size: 16, lineHeight: 24, w: FontWeight.w700, color: primary, tabular: true),

      // ── title 16/700. Row titles and card titles — the design's own `text-[16px] Bold`.
      titleMedium: _inter(size: 16, lineHeight: 24, w: FontWeight.w700, color: primary),

      // ── 15/400. Reading text, and the size the design gives a hostel name in a header.
      bodyLarge: _inter(size: 15, lineHeight: 22, w: FontWeight.w400, color: primary),

      // ── 14/600. Buttons and tabs. See the note above on why these are not `label-caps`.
      labelLarge: _inter(size: 14, lineHeight: 20, w: FontWeight.w600, color: primary),

      // ── body at semibold. A figure inside a row: same size as bodyMedium, and the weight is
      //    what separates them.
      titleSmall:
          _inter(size: 13, lineHeight: 18, w: FontWeight.w600, color: primary, tabular: true),

      // ── body 13/400. The design's running text; supporting copy.
      bodyMedium: _inter(size: 13, lineHeight: 18, w: FontWeight.w400, color: secondary),

      // ── label-caps 12/600 at +0.05em. Uppercase the STRING at the call site; a TextStyle
      //    cannot.
      labelMedium: _inter(
          size: 12, lineHeight: 16, w: FontWeight.w600, letterSpacing: 0.6, color: secondary),

      // ── meta 11/400. Timestamps, sub-labels, the support line under an empty state.
      bodySmall: _inter(size: 11, lineHeight: 16, w: FontWeight.w400, color: secondary),

      // ── chip 10/600 at +0.05em, tabular: eyebrows and status chips, which are often a count.
      labelSmall: _inter(
          size: 10,
          lineHeight: 14,
          w: FontWeight.w600,
          letterSpacing: 0.5,
          color: secondary,
          tabular: true),
    );
  }

  /// For a figure that must not change width while it animates or refreshes.
  static TextStyle tabular(TextStyle s) => s.copyWith(fontFeatures: _tabular);

  /// Moves a style to another weight.
  ///
  /// USE THIS, not `copyWith(fontWeight: ...)`. With static faces the weight is baked into the
  /// resolved family name — a style from this file carries `fontFamily: 'Inter_<variant>'` —
  /// so a bare `copyWith(fontWeight:)` changes the number and keeps the old face, and nothing
  /// warns you. Re-resolving through google_fonts is what actually swaps the file.
  ///
  /// Only the five bundled weights resolve to their own face. Asking for one that is not
  /// shipped silently lands on the CLOSEST bundled weight rather than downloading, because
  /// `allowRuntimeFetching` is false.
  static TextStyle weight(TextStyle s, FontWeight w) =>
      GoogleFonts.inter(textStyle: s, fontWeight: w);
}
