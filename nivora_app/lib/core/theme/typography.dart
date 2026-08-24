import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Nivora's type scale.
///
/// Inter, per the brief. Loaded through google_fonts, which caches to disk after first run —
/// but see [NivoraType.textTheme]: the fallback is the platform face, so a device that cannot
/// reach the font CDN gets Roboto/SF rather than no text.
///
/// ── THE SCALE ────────────────────────────────────────────────────────────────────────────
/// Eight steps, and each one has a job that no other step does:
///
///   40  headlineLarge   the single hero figure on a dashboard          tabular
///   30  displaySmall    the screen title. One per screen.
///   24  headlineMedium  a stat card's value                            tabular
///   19  titleLarge      section heading
///   16  titleMedium     row title  ·  bodyLarge  reading text
///   15  labelLarge      button and tab labels
///   14  bodyMedium      supporting text  ·  titleSmall  a stat inside a row (w600, tabular)
///   13  bodySmall       metadata, timestamps, captions
///   11  labelSmall      eyebrows and status chips                      tabular
///
/// 16/14 and 15/14 each carry two roles apart by WEIGHT, not size. That is deliberate: a
/// fifteenth-of-a-step size difference is invisible on a phone and only gives a future
/// contributor a decision to get wrong. Hierarchy here comes from size, then colour, then
/// weight — which is why almost nothing is bold and nothing is w700.
///
/// ── NUMBERS ──────────────────────────────────────────────────────────────────────────────
/// Money and counts are the point of this product, so every slot that can hold a figure asks
/// for tabular figures. Proportional digits let a column of rupee amounts shuffle sideways by
/// a pixel or two per row, and a refreshing dashboard jitters. Tabular digits are all one
/// width: columns line up, and a value animating from ₹9,900 to ₹10,100 does not shove its
/// neighbours. If you add a slot that will hold a number, wrap it with [NivoraType.tabular].
abstract final class NivoraType {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextTheme textTheme(Color primary, Color secondary) {
    final base = GoogleFonts.interTextTheme();
    return base.copyWith(
      // The single hero number on a dashboard. The loudest thing on the screen, on purpose.
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 40,
        height: 1.05,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.2,
        color: primary,
        fontFeatures: _tabular,
      ),
      // Screen titles. One per screen.
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: primary,
      ),
      // A stat card's value.
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: primary,
        fontFeatures: _tabular,
      ),
      // Section headings. Medium weight, not bold.
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 19,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: primary,
      ),
      // Row titles.
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: primary,
      ),
      // A figure inside a row. Same size as bodyMedium; the weight is what separates them.
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: primary,
        fontFeatures: _tabular,
      ),
      // Body. 16px because this app is read on a phone in a corridor, not at a desk.
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.5, color: primary),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.5, color: secondary),
      // Metadata, timestamps, captions.
      bodySmall: base.bodySmall?.copyWith(fontSize: 13, height: 1.45, color: secondary),
      // Buttons and tabs.
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: primary,
      ),
      // Eyebrows and status chips. Often a count, so tabular.
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: secondary,
        fontFeatures: _tabular,
      ),
    );
  }

  /// For a figure that must not change width while it animates or refreshes.
  static TextStyle tabular(TextStyle s) => s.copyWith(fontFeatures: _tabular);
}
