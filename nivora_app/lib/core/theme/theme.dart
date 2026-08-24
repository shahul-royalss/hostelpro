import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Nivora's two themes, both built from [NivoraColors].
///
/// Dark mode is authored, not derived. Inverting a light palette produces grey mud on an OLED
/// panel and loses the elevation cue entirely, so the dark scheme uses its own surfaces
/// (#070B14 → #101827 → #151F32, getting LIGHTER as they rise) and its own accent (#898BF3,
/// lifted from the light-mode indigo because a dark surface needs a lighter accent to read an
/// active state).
///
/// Two things here are load-bearing and easy to undo by accident:
///
/// 1. [NivoraSemantics] is registered as a ThemeExtension on BOTH themes. It is what makes
///    `context.tones.error` legible in whichever theme is current. See the proof in tokens.dart
///    for why a single flat colour cannot do that job.
///
/// 2. `colorScheme.outline` and `colorScheme.outlineVariant` are DECORATIVE borders — a card's
///    edge and a divider. The border of a text field or an outlined button is not decorative,
///    it is the control's only boundary, so those are wired to [NivoraColors.controlBorder]
///    (3.50:1 light / 3.73:1 dark) rather than to the scheme. Do not "simplify" that back into
///    one value: either every card grows a heavy 3:1 outline, or every input loses its edge.
abstract final class NivoraTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: NivoraColors.indigo,
      onPrimary: Colors.white, // 5.98:1
      secondary: NivoraColors.softBlueInk,
      onSecondary: Colors.white, // 5.87:1
      surface: NivoraColors.surface,
      onSurface: NivoraColors.textPrimary, // 17.74:1
      surfaceContainerLowest: NivoraColors.background,
      surfaceContainerHighest: Color(0xFFEEF2F8),
      error: NivoraColors.errorInk, // text-grade: Material paints this as type
      onError: Colors.white, // 5.83:1
      outline: NivoraColors.cardBorder,
      outlineVariant: NivoraColors.hairline,
    );
    return _base(
      scheme: scheme,
      background: NivoraColors.background,
      textPrimary: NivoraColors.textPrimary,
      textSecondary: NivoraColors.textSecondary,
      muted: NivoraColors.mutedInk,
      controlBorder: NivoraColors.controlBorder,
      fieldFill: NivoraColors.surface,
      semantics: NivoraSemantics.light,
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: NivoraColors.darkIndigo,
      onPrimary: NivoraColors.midnight, // 6.29:1
      secondary: NivoraColors.softBlue,
      onSecondary: NivoraColors.midnight, // 7.18:1
      surface: NivoraColors.darkSurface,
      onSurface: NivoraColors.darkTextPrimary, // 16.98:1
      surfaceContainerLowest: NivoraColors.darkBackground,
      surfaceContainerHigh: NivoraColors.darkElevated,
      surfaceContainerHighest: NivoraColors.darkElevated,
      error: NivoraColors.errorDark,
      onError: NivoraColors.midnight, // 7.35:1
      outline: NivoraColors.darkCardBorder,
      outlineVariant: NivoraColors.darkHairline,
    );
    return _base(
      scheme: scheme,
      background: NivoraColors.darkBackground,
      textPrimary: NivoraColors.darkTextPrimary,
      textSecondary: NivoraColors.darkTextSecondary,
      muted: NivoraColors.darkMuted,
      controlBorder: NivoraColors.darkControlBorder,
      fieldFill: NivoraColors.darkElevated,
      semantics: NivoraSemantics.dark,
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color background,
    required Color textPrimary,
    required Color textSecondary,
    required Color muted,
    required Color controlBorder,
    required Color fieldFill,
    required NivoraSemantics semantics,
  }) {
    final text = NivoraType.textTheme(textPrimary, textSecondary);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[semantics],

      iconTheme: IconThemeData(color: textSecondary, size: IconSize.md),

      // Headers are ours to draw (see GlassHeader), so the stock AppBar is stripped rather
      // than styled — a half-configured AppBar peeking through is how wrappers look cheap.
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: textPrimary, size: IconSize.lg),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 48dp: Material's minimum, and above Apple's 44pt, so one number satisfies both.
          minimumSize: const Size.fromHeight(48),
          shape: const RoundedRectangleBorder(borderRadius: Radii.rControl),
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const RoundedRectangleBorder(borderRadius: Radii.rControl),
          // The control's only boundary. 3:1, not the decorative card hairline.
          side: BorderSide(color: controlBorder, width: Strokes.hairline),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          textStyle: text.labelLarge,
          foregroundColor: scheme.primary,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
        border: OutlineInputBorder(
          borderRadius: Radii.rControl,
          borderSide: BorderSide(color: controlBorder, width: Strokes.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.rControl,
          borderSide: BorderSide(color: controlBorder, width: Strokes.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.rControl,
          borderSide: BorderSide(color: scheme.primary, width: Strokes.focus),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.rControl,
          borderSide: BorderSide(color: semantics.error, width: Strokes.hairline),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.rControl,
          borderSide: BorderSide(color: semantics.error, width: Strokes.focus),
        ),
        labelStyle: text.bodyMedium,
        // A placeholder is text, so 4.5:1 applies to it. The old #98A2B3 measured 2.58:1.
        hintStyle: text.bodyMedium?.copyWith(color: muted),
        errorStyle: text.bodySmall?.copyWith(color: semantics.error),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rCard),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: Strokes.hairline,
        space: Strokes.hairline,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.outlineVariant,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rSheetTop),
        showDragHandle: true,
        // A drag handle is a control, so 3:1 applies. The old #98A2B3 measured 2.58:1.
        dragHandleColor: controlBorder,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: NivoraColors.midnight,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white), // 18.4:1
        shape: const RoundedRectangleBorder(borderRadius: Radii.rControl),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
