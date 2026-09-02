import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Nivora's two themes.
///
/// ── THE DARK ONE IS THE PRODUCT ──────────────────────────────────────────────────────────
///
/// [dark] is the Figma design, written out role by role from `design-figma/DESIGN-SYSTEM.md`
/// and the frames themselves, with nothing inferred. All nineteen `screen-*` frames are dark;
/// this is the app.
///
/// [light] is `ColorScheme.fromSeed(seedColor: NivoraColors.seed)` — derived from the design's
/// own gold accent, not drawn — and it is included because the app currently runs
/// `ThemeMode.system` and a light-mode phone has to get something legible. It measures clean
/// (worst text pair 5.01:1) but it is a generic Material page in the right family, because
/// `fromSeed` pulls most of the chroma out of #C9A96E and nobody designed a light Nivora. See
/// [NivoraColors.lightPrimary]. The honest recommendation is `themeMode: ThemeMode.dark` in
/// main.dart; that file is outside this change, so both themes are here and both are correct.
///
/// ── FIVE THINGS HERE ARE LOAD-BEARING AND EASY TO UNDO BY ACCIDENT ───────────────────────
///
/// 1. `colorScheme.surface` IS THE CARD, NOT THE GROUND. The design's `background` role is
///    #0B0D0F, the page ground — but 17 call sites across `features/` paint a card with
///    `colorScheme.surface`, and wiring the ground there makes every one of them vanish into
///    the background. So `surface` is the design's card #111417 and the ground is
///    `scaffoldBackgroundColor`. Screens being restyled against a mockup should name the
///    surface they mean — `surfaceContainerLow`, `surfaceContainer`, `surfaceBright` — all of
///    which carry the design's exact values.
///
/// 2. THE FILLED BUTTON IS CREAM, AND IT IS WIRED TO `primaryContainer`. This is the reverse
///    of the previous theme and of Material's default, and it is the design's most
///    distinctive decision: 4:83 ("Continue") and 4:1596 ("Retry") are `bg-[#f5f3ee]` with
///    `text-[#0b0d0f]`, 17.56:1. `primary` is the GOLD, which is what links, active tabs,
///    focus rings and emphasis figures use, and which fills exactly one button in the file —
///    the renew CTA on `screen-subscription-expired` (4:1537). A screen that wants that button
///    asks for `colorScheme.primary` explicitly; the default is cream.
///
/// 3. [NivoraSemantics] is registered as a ThemeExtension on BOTH themes. It is what makes
///    `context.tones.error` legible in whichever theme is current. See the proof in tokens.dart
///    for why a single flat colour cannot do that job.
///
/// 4. `colorScheme.outline` and `outlineVariant` are TWO DIFFERENT JOBS. `outlineVariant`
///    #292E33 is the design's hairline — every card edge and divider in the file, 1.35:1, a
///    line you see and never read. `outline` #6F747A is the design's quietest INK, used here
///    for the boundary of a control (a text field, an outlined button, a drag handle), where
///    WCAG 1.4.11 pushes it to 3:1 and it measures 3.70:1 on the field fill. Do not collapse
///    them: either every card grows a heavy outline, or every input loses its edge.
///
/// 5. NOTHING CASTS A SHADOW EXCEPT A MODAL. Every `elevation:` here is 0 and every surface is
///    separated by the hairline, because that is what the design does — see [Shadows].
abstract final class NivoraTheme {
  /// The Figma dark scheme, role by role. Every hex is [NivoraColors]; nothing is literal.
  static const ColorScheme _darkScheme = ColorScheme.dark(
    brightness: Brightness.dark,

    // GOLD is `primary`: links, active state, emphasis, focus, the renew CTA.
    primary: NivoraColors.primary,
    onPrimary: NivoraColors.onPrimary, // 8.70:1
    // CREAM is the filled button. See note 2.
    primaryContainer: NivoraColors.primaryContainer,
    onPrimaryContainer: NivoraColors.onPrimaryContainer, // 17.56:1

    // AMBER is `secondary`: due, expiring, the subscription banner.
    secondary: NivoraColors.secondary,
    onSecondary: NivoraColors.onSecondary, // 8.70:1
    secondaryContainer: NivoraColors.secondaryContainer,
    onSecondaryContainer: NivoraColors.onSecondaryContainer, // 7.03:1

    // POSITIVE lives on `tertiary`: paid, occupied, resolved.
    tertiary: NivoraColors.tertiary,
    onTertiary: NivoraColors.onTertiary, // 7.29:1
    tertiaryContainer: NivoraColors.tertiaryContainer,
    onTertiaryContainer: NivoraColors.onTertiaryContainer, // 6.03:1

    error: NivoraColors.errorTone,
    onError: NivoraColors.onErrorTone, // 5.76:1
    errorContainer: NivoraColors.errorContainer,
    onErrorContainer: NivoraColors.onErrorContainer, // 4.89:1

    // See note 1: `surface` is the CARD. The ground is scaffoldBackgroundColor.
    surface: NivoraColors.surfaceContainerLow,
    onSurface: NivoraColors.onSurface, // 16.67:1
    onSurfaceVariant: NivoraColors.onSurfaceVariant, // 7.55:1
    surfaceDim: NivoraColors.ground,
    surfaceBright: NivoraColors.surfaceBright,
    surfaceContainerLowest: NivoraColors.surfaceContainerLowest,
    surfaceContainerLow: NivoraColors.surfaceContainerLow,
    surfaceContainer: NivoraColors.surfaceContainer,
    surfaceContainerHigh: NivoraColors.surfaceContainerHigh,
    surfaceContainerHighest: NivoraColors.surfaceContainerHighest,

    outline: NivoraColors.outline,
    outlineVariant: NivoraColors.outlineVariant,
    surfaceTint: NivoraColors.primary,
    inversePrimary: NivoraColors.seed,
    inverseSurface: NivoraColors.onSurface,
    onInverseSurface: NivoraColors.ground, // 17.56:1
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  /// Derived once. `fromSeed` runs a quantiser and this is read on every theme rebuild, so it
  /// is a `static final` rather than a call inside [light].
  ///
  /// Two overrides: `surface` becomes the derived `surfaceContainerLowest` (white), for the
  /// same reason as note 1 — `surface` is the card here too, and the derived `surface`
  /// #FFF8F3 is the ground. `error` becomes the semantic ink so the light theme has one red
  /// rather than a scheme red and a chip red a shade apart.
  static final ColorScheme _lightScheme = ColorScheme.fromSeed(
    seedColor: NivoraColors.seed,
  ).copyWith(
    surface: NivoraColors.surface, // white; the derived surfaceContainerLowest
    error: NivoraColors.errorInk, // 6.82:1 for white on it
    onError: const Color(0xFFFFFFFF),
  );

  static ThemeData dark() => _base(
        scheme: _darkScheme,
        background: NivoraColors.ground,
        textPrimary: NivoraColors.onSurface,
        textSecondary: NivoraColors.onSurfaceVariant,
        muted: NivoraColors.darkMuted,
        controlBorder: NivoraColors.darkControlBorder,
        // 4:77 — the design's own text field is the raised surface, not a step above it.
        fieldFill: NivoraColors.surfaceContainerHighest,
        // The design's filled action: cream with near-black text.
        filledButtonBackground: NivoraColors.primaryContainer,
        filledButtonForeground: NivoraColors.onPrimaryContainer,
        semantics: NivoraSemantics.dark,
      );

  static ThemeData light() => _base(
        scheme: _lightScheme,
        background: NivoraColors.background,
        textPrimary: NivoraColors.textPrimary,
        textSecondary: NivoraColors.textSecondary,
        muted: NivoraColors.mutedInk,
        controlBorder: NivoraColors.controlBorder,
        fieldFill: NivoraColors.lightField,
        // A cream button on a cream page is not a button. The light theme keeps M3's own
        // primary/onPrimary pairing, which is derived and measures 6.47:1.
        filledButtonBackground: _lightScheme.primary,
        filledButtonForeground: _lightScheme.onPrimary,
        semantics: NivoraSemantics.light,
      );

  static ThemeData _base({
    required ColorScheme scheme,
    required Color background,
    required Color textPrimary,
    required Color textSecondary,
    required Color muted,
    required Color controlBorder,
    required Color fieldFill,
    required Color filledButtonBackground,
    required Color filledButtonForeground,
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
        titleTextStyle: text.titleMedium,
        iconTheme: IconThemeData(color: textPrimary, size: IconSize.lg),
      ),

      // The design's filled action. See note 2 — this is the cream one in the dark theme.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: filledButtonBackground,
          foregroundColor: filledButtonForeground,
          // 48dp: Material's minimum, and above Apple's 44pt, so one number satisfies both.
          // The design's own button is 44 high, which is under Material's floor.
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
          // The design's own secondary button ("Learn More", 4:1587) is cream on a hairline
          // box, not a coloured label: the outline is what says "button", so the text stays
          // ordinary.
          foregroundColor: textPrimary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          textStyle: text.labelLarge,
          // "Contact Support" (4:1598) and "Contact your hostel admin" (4:86) are both gold.
          foregroundColor: scheme.primary,
        ),
      ),

      // The FAB is the gold — the design's one coloured fill — with [Shadows.glow] for the
      // screen that draws one. Near-black on gold measures 8.70:1.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
      ),

      // A bar is the raised surface with a hairline; the active destination is the gold on a
      // 10% wash of itself, which is the design's own chip recipe applied to a nav pill.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: GlassWeight.regular.surfaceOf(scheme),
        surfaceTintColor: Colors.transparent,
        indicatorColor: semantics.chipFill(scheme.primary),
        indicatorShape: const RoundedRectangleBorder(borderRadius: Radii.rControl),
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? text.labelSmall?.copyWith(color: scheme.primary)
              : text.labelSmall?.copyWith(color: muted),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: IconSize.lg,
            color: states.contains(WidgetState.selected) ? scheme.primary : muted,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // 4:77: `bg-[#171a1e] border border-[#292e33] rounded-[10px] h-[44px] px-[14px]`.
        // The fill and the hairline are the design's; the radius rounds to the vocabulary's 8
        // and the height goes to the 48dp tap floor.
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
        // A placeholder is text, so 4.5:1 applies to it — against the FIELD FILL. The design
        // sets its own placeholder in #6F747A, which measures 3.70:1 there and fails; this is
        // the lifted value. See NivoraColors.darkMuted.
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
        // 4:466 — the meter track is the hairline colour as a filled channel, 6px high with a
        // fully rounded end.
        linearTrackColor: scheme.outlineVariant,
        linearMinHeight: 6,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rSheetTop),
        showDragHandle: true,
        // A drag handle is a control, so 3:1 applies.
        dragHandleColor: controlBorder,
      ),

      // The deepest well in the design, in both themes — a snackbar is the one surface that
      // should read as being in front of the whole app rather than part of it. In the dark
      // theme that is the ground itself, so it carries the hairline the design gives every
      // other surface, drawn by the shape's side.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: NivoraColors.midnight,
        contentTextStyle: text.bodyMedium?.copyWith(color: NivoraColors.onSurface), // 17.56:1
        shape: const RoundedRectangleBorder(
          borderRadius: Radii.rControl,
          // The DARK hairline in both themes, because the snackbar is the dark ground in both.
          side: BorderSide(color: NivoraColors.outlineVariant, width: Strokes.hairline),
        ),
      ),

      pageTransitionsTheme:
          const PageTransitionsTheme(builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
