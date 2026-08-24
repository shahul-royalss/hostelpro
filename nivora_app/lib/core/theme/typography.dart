import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';


/// Nivora's type scale.
///
/// Inter, per the brief. Loaded through google_fonts, which caches to disk after first run —
/// but see [NivoraType.textTheme]: the fallback is the platform face, so a device that cannot
/// reach the font CDN gets Roboto/SF rather than no text.
///
/// The scale is deliberately short. Every extra size is a decision a future contributor has to
/// make correctly, and hierarchy comes from size and colour long before it comes from weight —
/// which is why almost nothing here is bold.
abstract final class NivoraType {
  /// Money and counts. Tabular figures so a column of numbers does not shift width as it
  /// updates — the difference between a dashboard that feels engineered and one that jitters.
  static const _tabular = [FontFeature.tabularFigures()];

  static TextTheme textTheme(Color primary, Color secondary) {
    final base = GoogleFonts.interTextTheme();
    return base.copyWith(
      // PagedResult titles. One per screen.
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 32, height: 1.15, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: primary,
      ),
      // The single hero number on a dashboard.
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 40, height: 1.05, fontWeight: FontWeight.w600, letterSpacing: -1.2,
        color: primary, fontFeatures: _tabular,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 24, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: primary,
      ),
      // Section headings. Medium weight, not bold.
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 19, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: primary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16, height: 1.35, fontWeight: FontWeight.w500, color: primary,
      ),
      // Stat values inside cards.
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 15, height: 1.35, fontWeight: FontWeight.w600, color: primary,
        fontFeatures: _tabular,
      ),
      // Body. 16px because this app is read on a phone in a corridor, not at a desk.
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.5, color: primary),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.5, color: secondary),
      // Metadata, timestamps, captions.
      bodySmall: base.bodySmall?.copyWith(fontSize: 13, height: 1.45, color: secondary),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 15, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0, color: primary,
      ),
      // Eyebrows and status chips.
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: secondary,
      ),
    );
  }

  /// For a figure that must not change width while it animates or refreshes.
  static TextStyle tabular(TextStyle s) => s.copyWith(fontFeatures: _tabular);
}
