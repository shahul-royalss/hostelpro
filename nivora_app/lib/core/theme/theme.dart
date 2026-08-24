import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Nivora's two themes, both built from [NivoraColors].
///
/// Dark mode is authored, not derived. Inverting a light palette produces grey mud on an OLED
/// panel and loses the elevation cue entirely, so the dark scheme uses its own surfaces
/// (#070B14 → #101827 → #151F32, getting LIGHTER as they rise) and its own accent (#7C83FF,
/// lifted from the light-mode indigo because #5B5FEF has too little contrast against a dark
/// background to read as an active state).
abstract final class NivoraTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: NivoraColors.indigo,
      onPrimary: Colors.white,
      secondary: NivoraColors.softBlue,
      onSecondary: NivoraColors.midnight,
      surface: NivoraColors.surface,
      onSurface: NivoraColors.textPrimary,
      surfaceContainerLowest: NivoraColors.background,
      error: NivoraColors.error,
      onError: Colors.white,
      outline: Color(0xFFE4E7EC),
      outlineVariant: Color(0xFFF0F2F5),
    );
    return _base(scheme, NivoraColors.background,
        NivoraColors.textPrimary, NivoraColors.textSecondary);
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: NivoraColors.darkIndigo,
      onPrimary: NivoraColors.midnight,
      secondary: NivoraColors.softBlue,
      onSecondary: NivoraColors.midnight,
      surface: NivoraColors.darkSurface,
      onSurface: NivoraColors.darkTextPrimary,
      surfaceContainerLowest: NivoraColors.darkBackground,
      surfaceContainerHigh: NivoraColors.darkElevated,
      error: NivoraColors.error,
      onError: Colors.white,
      outline: Color(0xFF243044),
      outlineVariant: Color(0xFF1A2434),
    );
    return _base(scheme, NivoraColors.darkBackground,
        NivoraColors.darkTextPrimary, NivoraColors.darkTextSecondary);
  }

  static ThemeData _base(
    ColorScheme scheme,
    Color background,
    Color textPrimary,
    Color textSecondary,
  ) {
    final text = NivoraType.textTheme(textPrimary, textSecondary);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,

      // Headers are ours to draw (see GlassHeader), so the stock AppBar is stripped rather
      // than styled — a half-configured AppBar peeking through is how wrappers look cheap.
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: textPrimary, size: 22),
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
          side: BorderSide(color: scheme.outline),
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
        fillColor: scheme.brightness == Brightness.light
            ? Colors.white
            : NivoraColors.darkElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
        border: OutlineInputBorder(
          borderRadius: Radii.rControl,
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.rControl,
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.rControl,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.rControl,
          borderSide: const BorderSide(color: NivoraColors.error, width: 1.4),
        ),
        labelStyle: text.bodyMedium,
        hintStyle: text.bodyMedium?.copyWith(color: NivoraColors.textMuted),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rCard),
      ),

      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rSheetTop),
        showDragHandle: true,
        dragHandleColor: NivoraColors.textMuted,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: NivoraColors.midnight,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: const RoundedRectangleBorder(borderRadius: Radii.rControl),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
