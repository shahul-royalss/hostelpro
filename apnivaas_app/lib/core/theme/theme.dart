import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'tokens.dart';
import 'typography.dart';

/// Apnivaas's two themes — Forest & Cream, and its dark twin.
///
/// [light] is the product: cream ground, warm white cards, forest for every primary action,
/// Outfit headings over Manrope text. [dark] is designed and measured to the same rules and
/// stays wired, but main.dart pins `ThemeMode.light` at the product owner's request.
///
/// ── FOUR THINGS HERE ARE LOAD-BEARING AND EASY TO UNDO BY ACCIDENT ───────────────────────
///
/// 1. `colorScheme.surface` IS THE CARD, NOT THE GROUND. Call sites across `features/` paint a
///    card with `colorScheme.surface`, and wiring the ground there makes every one of them
///    vanish into the page. The ground is `scaffoldBackgroundColor`.
///
/// 2. [ApnivaasSemantics] and [ApnivaasTextRoles] are registered as ThemeExtensions on BOTH
///    themes. The first is what makes `context.tones.error` legible in whichever theme is
///    current; the second carries the type roles the Material slots have no name for.
///
/// 3. `colorScheme.outline` and `outlineVariant` are TWO DIFFERENT JOBS. `outlineVariant` is a
///    card's decorative edge (1.13:1 on the ground — seen, never read). `outline` is a
///    CONTROL's edge — a text field, a chip, a radio, a drag handle — where WCAG 1.4.11 asks for
///    3:1 and it measures 3.53:1 on the card. Collapse them and either every card looks like a
///    text field or every field loses its edge.
///
/// 4. THE FILLED BUTTON IS FOREST IN LIGHT AND MIST IN DARK. In both it is the single most
///    contrasty object on the screen; a cream button on a cream page, or a forest one on a
///    near-black page, would not be.
abstract final class ApnivaasTheme {
  /// A text field's inner padding — the canvas's 14 across and 15 down, which with a 22dp line
  /// lands the field at 52dp. Off the 4dp grid on purpose, so named rather than written inline.
  static const _fieldInsetX = 14.0;
  static const _fieldInsetY = 15.0;

  static const ColorScheme _lightScheme = ColorScheme.light(
    brightness: Brightness.light,

    primary: ApnivaasColors.forest, //          9.36:1 on the card
    onPrimary: Color(0xFFFFFFFF), //             9.51:1
    primaryContainer: ApnivaasColors.mist,
    onPrimaryContainer: ApnivaasColors.forest, // 7.54:1

    // Leaf is a graphic green: white on it 4.72:1, but 4.23:1 as text on the ground, so it is
    // never a text colour. Supporting text uses `onSurfaceVariant`.
    secondary: ApnivaasColors.leaf,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: ApnivaasColors.well,
    onSecondaryContainer: ApnivaasColors.ink, //  13.23:1

    // Gold, as a fill only.
    tertiary: ApnivaasColors.gold,
    onTertiary: ApnivaasColors.ink, //            7.30:1
    tertiaryContainer: ApnivaasColors.bannerTop,
    onTertiaryContainer: ApnivaasColors.bannerTitle,

    // ONE RED: the semantic ink, so a scheme red and a chip red are not a shade apart.
    error: ApnivaasColors.errorInk,
    onError: Color(0xFFFFFFFF), //               6.54:1
    errorContainer: ApnivaasColors.errorContainerLight,
    onErrorContainer: ApnivaasColors.errorInk, // 5.48:1

    // See note 1: `surface` is the CARD.
    surface: ApnivaasColors.card,
    onSurface: ApnivaasColors.ink, //             14.53:1
    onSurfaceVariant: ApnivaasColors.inkMuted, // 6.06:1
    surfaceDim: ApnivaasColors.cream,
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: ApnivaasColors.card,
    surfaceContainerLow: ApnivaasColors.card,
    surfaceContainer: ApnivaasColors.well,
    surfaceContainerHigh: ApnivaasColors.card,
    surfaceContainerHighest: ApnivaasColors.lightField,
    surfaceTint: Colors.transparent,

    outline: ApnivaasColors.controlBorder, //     3.53:1 — §1.4.11
    outlineVariant: ApnivaasColors.cardBorder,

    inverseSurface: ApnivaasColors.ink,
    onInverseSurface: ApnivaasColors.onSurface, // 12.86:1
    inversePrimary: ApnivaasColors.primary, //      7.69:1 on ink
    shadow: ApnivaasColors.forestDeep,
    scrim: ApnivaasColors.forestDeep,
  );

  static const ColorScheme _darkScheme = ColorScheme.dark(
    brightness: Brightness.dark,

    primary: ApnivaasColors.primary, //           6.43:1 worst
    onPrimary: ApnivaasColors.onPrimary, //       9.59:1
    primaryContainer: ApnivaasColors.primaryContainer, // the Mist filled button
    onPrimaryContainer: ApnivaasColors.onPrimaryContainer, // 7.54:1

    secondary: ApnivaasColors.secondary,
    onSecondary: ApnivaasColors.onSecondary,
    secondaryContainer: ApnivaasColors.secondaryContainer,
    onSecondaryContainer: ApnivaasColors.onSecondaryContainer,

    tertiary: ApnivaasColors.tertiary,
    onTertiary: ApnivaasColors.onTertiary,
    tertiaryContainer: ApnivaasColors.tertiaryContainer,
    onTertiaryContainer: ApnivaasColors.onTertiaryContainer,

    error: ApnivaasColors.errorTone,
    onError: ApnivaasColors.onErrorTone,
    errorContainer: ApnivaasColors.errorContainer,
    onErrorContainer: ApnivaasColors.onErrorContainer,

    surface: ApnivaasColors.surfaceContainerLow,
    onSurface: ApnivaasColors.onSurface,
    onSurfaceVariant: ApnivaasColors.onSurfaceVariant,
    surfaceDim: ApnivaasColors.ground,
    surfaceBright: ApnivaasColors.surfaceBright,
    surfaceContainerLowest: ApnivaasColors.surfaceContainerLowest,
    surfaceContainerLow: ApnivaasColors.surfaceContainerLow,
    surfaceContainer: ApnivaasColors.surfaceContainer,
    surfaceContainerHigh: ApnivaasColors.surfaceContainerHigh,
    surfaceContainerHighest: ApnivaasColors.surfaceContainerHighest,
    surfaceTint: Colors.transparent,

    outline: ApnivaasColors.outline,
    outlineVariant: ApnivaasColors.outlineVariant,
    inverseSurface: ApnivaasColors.onSurface,
    onInverseSurface: ApnivaasColors.ink, //       12.86:1
    inversePrimary: ApnivaasColors.forest,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static ThemeData light() => _base(
        scheme: _lightScheme,
        background: ApnivaasColors.background,
        textPrimary: ApnivaasColors.textPrimary,
        textSecondary: ApnivaasColors.inkMuted,
        labelInk: ApnivaasColors.inkStrong,
        muted: ApnivaasColors.mutedInk,
        placeholder: ApnivaasColors.placeholder,
        controlBorder: ApnivaasColors.controlBorder,
        cardBorder: ApnivaasColors.cardBorder,
        divider: ApnivaasColors.hairline,
        track: ApnivaasColors.track,
        fieldFill: ApnivaasColors.card,
        tonalFill: ApnivaasColors.mist,
        filledButtonBackground: ApnivaasColors.forest,
        filledButtonForeground: const Color(0xFFFFFFFF),
        filledButtonPressed: ApnivaasColors.forestPressed,
        disabledFill: ApnivaasColors.track,
        disabledInk: ApnivaasColors.disabledInk,
        snackBackground: ApnivaasColors.ink,
        snackInk: ApnivaasColors.onSurface,
        snackAction: ApnivaasColors.primary,
        barrier: ApnivaasColors.scrim,
        semantics: ApnivaasSemantics.light,
      );

  static ThemeData dark() => _base(
        scheme: _darkScheme,
        background: ApnivaasColors.ground,
        textPrimary: ApnivaasColors.onSurface,
        textSecondary: ApnivaasColors.onSurfaceVariant,
        labelInk: ApnivaasColors.onSurfaceVariant,
        muted: ApnivaasColors.darkMuted,
        placeholder: ApnivaasColors.darkPlaceholder,
        controlBorder: ApnivaasColors.darkControlBorder,
        cardBorder: ApnivaasColors.darkCardBorder,
        divider: ApnivaasColors.darkHairline,
        track: ApnivaasColors.darkHairline,
        fieldFill: ApnivaasColors.surfaceContainerHigh,
        tonalFill: ApnivaasColors.darkMist,
        filledButtonBackground: ApnivaasColors.primaryContainer,
        filledButtonForeground: ApnivaasColors.onPrimaryContainer,
        filledButtonPressed: ApnivaasColors.primary,
        disabledFill: ApnivaasColors.surfaceBright,
        disabledInk: ApnivaasColors.darkMuted,
        snackBackground: ApnivaasColors.onSurface,
        snackInk: ApnivaasColors.ink,
        snackAction: ApnivaasColors.forest,
        barrier: ApnivaasColors.darkScrim,
        semantics: ApnivaasSemantics.dark,
      );

  /// The Android status and navigation bars, for a theme of this [brightness].
  ///
  /// ── THIS WAS NOT SET ANYWHERE, AND THE RESULT WAS INVISIBLE STATUS-BAR ICONS ─────────────
  ///
  /// Most screens draw their own header rather than an [AppBar], and an AppBar is the only
  /// Material widget that sets the overlay style on its own. With no AppBar on the screen,
  /// Android keeps whatever it had. This is one region at the root that follows the theme:
  /// dark icons over the cream ground. The forest header sets LIGHT icons over itself with its
  /// own region, which wins for the strip it covers.
  ///
  /// EDGE TO EDGE, WHICH TARGET SDK 36 ENFORCES ANYWAY: both bars are transparent so the ground
  /// runs under them, and the three-button bar's contrast scrim is off, because the bar sits on
  /// the app's own opaque surface.
  static SystemUiOverlayStyle systemBars(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      // iOS reads this one instead; it names the BAR's brightness, not the icons'.
      statusBarBrightness: brightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarDividerColor: Colors.transparent,
    );
  }

  /// Light icons, for anything drawn over the forest header in either theme.
  static const SystemUiOverlayStyle onForest = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  static ThemeData _base({
    required ColorScheme scheme,
    required Color background,
    required Color textPrimary,
    required Color textSecondary,
    required Color labelInk,
    required Color muted,
    required Color placeholder,
    required Color controlBorder,
    required Color cardBorder,
    required Color divider,
    required Color track,
    required Color fieldFill,
    required Color tonalFill,
    required Color filledButtonBackground,
    required Color filledButtonForeground,
    required Color filledButtonPressed,
    required Color disabledFill,
    required Color disabledInk,
    required Color snackBackground,
    required Color snackInk,
    required Color snackAction,
    required Color barrier,
    required ApnivaasSemantics semantics,
  }) {
    final text = ApnivaasType.textTheme(textPrimary, textSecondary);
    final roles = ApnivaasTextRoles.of(textPrimary);
    final brand = scheme.primary;
    // A pressed or hovered surface: the brand at 8%, which is a tint you feel rather than see.
    final overlay = brand.withValues(alpha: 0.08);

    OutlineInputBorder field(Color c, double w) => OutlineInputBorder(
          borderRadius: Radii.rControl,
          borderSide: BorderSide(color: c, width: w),
        );

    final inputTheme = InputDecorationTheme(
      filled: true,
      fillColor: fieldFill,
      // 15 + 22 + 15 lands the field at 52dp at 1.0x; no fixed height, so it grows at 2.0x.
      contentPadding: const EdgeInsets.symmetric(horizontal: _fieldInsetX, vertical: _fieldInsetY),
      border: field(controlBorder, Strokes.control),
      enabledBorder: field(controlBorder, Strokes.control),
      focusedBorder: field(brand, Strokes.focus),
      errorBorder: field(semantics.error, Strokes.focus),
      focusedErrorBorder: field(semantics.error, Strokes.focus),
      disabledBorder: field(divider, Strokes.control),
      labelStyle: text.bodyLarge?.copyWith(color: muted),
      floatingLabelStyle: text.labelSmall?.copyWith(color: muted),
      // A placeholder is text, so 4.5:1 applies to it — against the FIELD FILL: 4.77:1.
      hintStyle: roles.fieldValue.copyWith(color: placeholder),
      helperStyle: text.bodySmall?.copyWith(color: muted),
      // An error is never colour alone: the border thickens and the sentence says it.
      errorStyle: text.bodySmall?.copyWith(color: semantics.error, fontWeight: FontWeight.w600),
      prefixIconColor: muted,
      suffixIconColor: muted,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: text,
      // The calmer ripple, and the cheaper one on the budget phones this ships to.
      splashFactory: InkRipple.splashFactory,
      splashColor: overlay,
      highlightColor: overlay,
      hoverColor: overlay,
      focusColor: brand.withValues(alpha: 0.12),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: <ThemeExtension<dynamic>>[semantics, roles],

      iconTheme: IconThemeData(color: textSecondary, size: IconSize.lg),

      // Cream and ink — the bar of a pushed screen that does not draw the forest header.
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: textPrimary, size: IconSize.action),
        systemOverlayStyle: systemBars(scheme.brightness),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return disabledFill;
            if (s.contains(WidgetState.pressed)) return filledButtonPressed;
            return filledButtonBackground;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.disabled) ? disabledInk : filledButtonForeground),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          // 52: the canvas's button, and clear of Material's 48 and Apple's 44.
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.lg)),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Radii.rButton)),
          // Focus is a 2px ring in the brand, never colour alone.
          side: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused)
              ? BorderSide(color: textPrimary, width: Strokes.focus)
              : BorderSide.none),
          textStyle: WidgetStatePropertyAll(roles.cta),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: Radii.rButton),
          side: BorderSide(color: brand, width: Strokes.control),
          foregroundColor: brand,
          disabledForegroundColor: disabledInk,
          overlayColor: brand,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
          foregroundColor: brand,
          overlayColor: brand,
          shape: const RoundedRectangleBorder(borderRadius: Radii.rControl),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          iconSize: IconSize.action,
          overlayColor: brand,
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: filledButtonBackground,
        foregroundColor: filledButtonForeground,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rButtonLarge),
      ),

      // The FALLBACK bar, for any shell not yet on ClayNavBar: the card with a Mist pill under
      // the selected destination, forest for selected and the muted ink for the rest.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: tonalFill,
        indicatorShape: const RoundedRectangleBorder(borderRadius: Radii.rButton),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? text.labelMedium?.copyWith(color: brand)
              : text.labelMedium?.copyWith(color: muted, fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: IconSize.action,
            color: states.contains(WidgetState.selected) ? brand : muted,
          ),
        ),
      ),

      inputDecorationTheme: inputTheme,
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: inputTheme,
        textStyle: roles.fieldValue,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: Radii.rControl)),
        ),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: brand,
        selectionColor: brand.withValues(alpha: 0.2),
        selectionHandleColor: brand,
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rCard,
          side: BorderSide(color: cardBorder, width: Strokes.hairline),
        ),
      ),

      // Choice and filter chips: an outlined pill that fills with the brand when chosen. The
      // border AND the fill change, so the state is never colour alone.
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        color: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return disabledFill;
          if (s.contains(WidgetState.selected)) return filledButtonBackground;
          return scheme.surface;
        }),
        side: WidgetStateBorderSide.resolveWith((s) => BorderSide(
              color: s.contains(WidgetState.selected) ? filledButtonBackground : controlBorder,
              width: Strokes.control,
            )),
        labelStyle: text.labelMedium?.copyWith(
          color: WidgetStateColor.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return disabledInk;
            if (s.contains(WidgetState.selected)) return filledButtonForeground;
            return textPrimary;
          }),
        ),
        checkmarkColor: filledButtonForeground,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: Space.xxs, vertical: Space.xxs),
        labelPadding: const EdgeInsets.symmetric(horizontal: Space.xs),
        iconTheme: IconThemeData(color: textPrimary, size: IconSize.md),
        elevation: 0,
        pressElevation: 0,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: scheme.surface,
          foregroundColor: textPrimary,
          selectedBackgroundColor: tonalFill,
          selectedForegroundColor: brand,
          side: BorderSide(color: controlBorder, width: Strokes.control),
          textStyle: text.labelLarge?.copyWith(fontSize: 13),
          minimumSize: const Size(0, 44),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? brand : Colors.transparent),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(color: controlBorder, width: Strokes.focus),
        shape: const RoundedRectangleBorder(borderRadius: Radii.rCheck),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? brand : controlBorder),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : controlBorder),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? brand : scheme.surface),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? brand : controlBorder),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.md),
        minVerticalPadding: Space.sm,
        iconColor: muted,
        textColor: textPrimary,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall,
        leadingAndTrailingTextStyle: text.titleSmall,
        selectedColor: brand,
        selectedTileColor: tonalFill,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rControl),
      ),

      dividerTheme: DividerThemeData(color: divider, thickness: Strokes.hairline, space: Strokes.hairline),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: track,
        circularTrackColor: track,
        linearMinHeight: 6,
      ),

      // A sheet opened straight through showModalBottomSheet gets the same object
      // showGlassSheet draws: the card, a 28dp top, the brand-ink barrier and a grip.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerHigh,
        modalBarrierColor: barrier,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rSheetTop),
        showDragHandle: true,
        // A drag handle is a control, so 3:1 applies: 3.53:1 on the card.
        dragHandleColor: controlBorder,
        dragHandleSize: const Size(36, 4),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rHero),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyLarge?.copyWith(color: labelInk),
        barrierColor: barrier,
        insetPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xl),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rHero),
        headerBackgroundColor: ApnivaasColors.forest,
        headerForegroundColor: ApnivaasColors.headerTitle,
        headerHeadlineStyle: text.displaySmall,
        todayBorder: BorderSide(color: brand, width: Strokes.control),
        dividerColor: divider,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: scheme.shadow.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rControl,
          side: BorderSide(color: cardBorder, width: Strokes.hairline),
        ),
        textStyle: text.bodyLarge,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: snackBackground, borderRadius: Radii.rTiny),
        textStyle: text.bodySmall?.copyWith(color: snackInk),
      ),

      // Ink on cream — the one surface that reads as in front of the whole app rather than as
      // part of it. Inverted in dark.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: snackBackground,
        contentTextStyle: text.bodyMedium?.copyWith(color: snackInk), // 12.86:1
        actionTextColor: snackAction, //                                   7.69:1
        insetPadding: const EdgeInsets.all(Space.md),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rControl),
      ),

      pageTransitionsTheme:
          const PageTransitionsTheme(builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
