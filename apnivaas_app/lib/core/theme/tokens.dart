library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Apnivaas's design tokens. The single place any visual constant is defined.
///
/// The rule this file exists to enforce: changing the accent colour, the corner radius or the
/// motion curve must be a one-line edit here, never a search across screens. Nothing in
/// `features/` may hardcode a colour, a radius, a duration or a spacing value.
///
// ═════════════════════════════════════════════════════════════════════════════════════════
// FOREST & CREAM — WHERE THESE VALUES COME FROM
// ═════════════════════════════════════════════════════════════════════════════════════════
//
// The design canvas (`apnivaas_canvas/project/*.dc.html`: the look sheet, sign-in, role
// picker, book-a-demo and owner home boards) and the clay icon set in `design-3d/icons-v3`.
// The logo's own greens: Forest #174E43, Leaf #3F7F68, Sage #7A9684, Mist #DCE8DF, on a warm
// Cream #F6F2EA ground with #FFFDF9 cards, Gold #E2AE4A for the one warm accent, and ink
// #1C2B26. THIS REPLACES THE PURPLE BROW AND THE FIGMA DARK PALETTE: violet, teal and saffron
// are gone from the live theme, and the clay icon now says what kind of thing something is.
//
// ── THE THREE DECISIONS WORTH READING BEFORE CHANGING ANYTHING ────────────────────────────
//
//   1. THE CANVAS HAD FIVE VALUES THAT FAIL, AND THEY WERE REPLACED, NOT SHIPPED. The input
//      and chip border #DDD5C8 measures 1.43:1 on the card (a control edge owes 3:1), the
//      placeholder #7B8A83 3.56:1, the inactive tab label #6B7A73 4.44:1, the header search
//      placeholder #CFE0D4 3.94:1 and Leaf as text on the ground 4.23:1. Their replacements
//      ([controlBorder], [placeholder], [inkMuted], [headerPlaceholder], [forest]) are the
//      nearest values that pass. "Restoring the canvas value" reintroduces a failure.
//
//   2. GOLD IS A FILL, NEVER A GRAPHIC ON CREAM. 1.81:1 on the ground, 1.99:1 on a card. It
//      lives on forest and on dark surfaces only: the unread dot, the hero tile's progress, the
//      header stars.
//
//   3. THE UNPREFIXED MATERIAL ROLE NAMES ARE THE DARK SCHEME. [surfaceContainerLow],
//      [onSurface], [primary] and friends predate the light theme and still carry the dark
//      values, because that is the scheme theme.dart builds from them. The light theme reads
//      the light names ([background], [surface], [textPrimary]…) and the brand names at the top
//      of [ApnivaasColors]. A feature painting without a BuildContext should reach for a BRAND
//      name — [forest], [mist], [cream] — not a role name, or it is painting the dark theme.
//
// ── EVERY NUMBER IN A COMMENT IS MEASURED ────────────────────────────────────────────────
//
// The ratios quoted next to the tokens are WCAG 2.1 relative-luminance measurements, and
// `test/theme_contrast_test.dart` recomputes them from the token itself. A colour nudged by eye
// fails `flutter test` with the number it actually measured. The bars are §1.4.3 (text, 4.5:1)
// and §1.4.11 (graphical objects and UI components, 3:1).
//
// ── WHY THERE ARE STILL THREE SEMANTIC SETS ──────────────────────────────────────────────
//
// One flat colour cannot be AA text on both cream and near-black, because luminance is the only
// variable in the ratio. So:
//
//   1. CANONICAL — [ApnivaasColors.success] and friends. The IDENTITY of a meaning, and what a
//      shape is painted with when there is no BuildContext: chart bars, meter fills, rails, a
//      `tone:` plumbed through an enum. Each sits in the luminance window that clears 3:1 on
//      the light ground, card, well and chip AND on the dark ground, card and raised surface.
//      NOT legible enough for small text.
//   2. LIGHT TEXT — the `...Ink` values, AA on every light surface and on a 10% chip of
//      themselves.
//   3. DARK TEXT  — the `...Dark` values, the same contract on the dark surfaces.
//
//   Sets 2 and 3 are reached through [ApnivaasSemantics]: `context.tones.error`, or
//   `context.tones.resolve(tone)` where a canonical colour has been plumbed through.
//
//   THIS IS THE RULE: canonical for shapes, resolved for type.
// ═════════════════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// COLOUR
// ─────────────────────────────────────────────────────────────────────────────

/// The palette. Ratios in comments are measured — see the header.
abstract final class ApnivaasColors {
  // ═══ THE BRAND — raw values. Paint through the roles below where a role exists. ═══════

  /// THE BRAND. The filled button, links, focus, the selected tab, the hero stat tile and the
  /// middle stop of the header. 9.36:1 on the card, 8.52:1 on the ground; white on it 9.51:1.
  static const forest = Color(0xFF174E43);

  /// The header gradient's first (darkest) stop, behind the greeting. White on it 12.74:1.
  static const forestDeep = Color(0xFF10392F);

  /// The header gradient's last (LIGHTEST) stop. Every header ink is measured on this one:
  /// white 7.28:1, [headerGreeting] 5.11:1, [headerSub] 5.29:1.
  static const forestHigh = Color(0xFF1F6150);

  /// A pressed filled button. White on it 12.58:1.
  static const forestPressed = Color(0xFF0F3A31);

  /// The progress track inside the forest hero tile. [gold] on it 3.13:1.
  static const forestTrack = Color(0xFF2D6A5A);

  /// A graphic green. As TEXT only on the card or white (4.65:1); 4.23:1 on the ground, so
  /// never text there. It is also the canonical [brand] tone.
  static const leaf = Color(0xFF3F7F68);

  /// Decorative graphics only — 3.17:1 on the card, 2.52:1 on the chip fill. Never text.
  static const sage = Color(0xFF7A9684);

  /// Tonal tiles, the tab-bar indicator, the persona art panel, the tonal button. Forest on
  /// it 7.54:1, [ink] 11.70:1, [inkMuted] 4.88:1.
  static const mist = Color(0xFFDCE8DF);

  /// THE PAGE GROUND. (= [background])
  static const cream = Color(0xFFF6F2EA);

  /// Cards, sheets, the tab bar and the input fill. (= [surface])
  static const card = Color(0xFFFFFDF9);

  /// The one warm accent, as a FILL: the unread dot (3.60:1 on [forestHigh]), the hero tile's
  /// progress, the header stars. 1.81:1 on cream, so never a graphic there. Ink on it 7.30:1.
  static const gold = Color(0xFFE2AE4A);

  /// A header star's core, and its halo.
  static const goldStar = Color(0xFFF6DFA0);
  static const goldHalo = Color(0xFFFFF6D8);

  /// Primary text. 14.53:1 on the card, 11.57:1 on the chip fill (its worst surface).
  static const ink = Color(0xFF1C2B26);

  /// Labels and notes, one step under [ink]. 9.14:1 on the card, 7.28:1 on the chip fill.
  static const inkStrong = Color(0xFF3D4A44);

  /// Secondary text. 6.06:1 on the card; 4.83:1 on the chip fill, its worst surface. Replaces
  /// the canvas's inactive-tab grey #6B7A73, which measured 4.44:1.
  static const inkMuted = Color(0xFF55655E);

  /// Supporting text on Mist. 5.81:1 there.
  static const mistInk = Color(0xFF3F5C52);

  /// A text field's placeholder: 4.77:1 on the field's own fill ([card]). Replaces the
  /// canvas's #7B8A83 (3.56:1).
  static const placeholder = Color(0xFF66756E);

  /// The quick-action well and the inner surface of a card. 1.09:1 against the card — a
  /// whisper, which is all an inset needs.
  static const well = Color(0xFFEEF4EF);

  /// A selected persona card.
  static const selectedSurface = Color(0xFFF2F8F3);

  /// A skeleton block on the card (1.22:1) and on the ground (1.15:1). Quiet on purpose: a
  /// placeholder that is easy to read is a placeholder people try to read.
  static const skeleton = Color(0xFFECE6DB);
  static const skeletonOnGround = Color(0xFFE9E2D5);

  /// The tab bar's top edge and a light progress track. [forest] on it 7.13:1.
  static const track = Color(0xFFE6DED2);

  /// The rules either side of "or continue with". Decorative.
  static const rule = Color(0xFFE2DACD);

  /// The modal barrier: forest-deep at 48%.
  static const scrim = Color(0x7A10392F);

  /// The dark theme's barrier: black at 60%. Forest-deep is not dark enough to read as a
  /// barrier over a near-black page.
  static const darkScrim = Color(0x99000000);

  /// The light error container, behind an error banner. [errorInk] on it 5.48:1.
  static const errorContainerLight = Color(0xFFF7E8E3);

  /// A disabled control's label and glyph on [track]. Disabled controls owe no contrast; this
  /// is simply the quiet the canvas draws.
  static const disabledInk = Color(0xFF8A958F);

  // ── the header's inks. The same in both themes, because the header is.

  static const headerTitle = Color(0xFFFFFFFF);

  /// The greeting line. 5.11:1 on [forestHigh].
  static const headerGreeting = Color(0xFFBFE0CC);

  /// Meta lines and captions on forest. 5.29:1 on [forestHigh], 6.92:1 on [forest].
  static const headerSub = Color(0xFFCFE0D4);

  /// The search pill's placeholder: 4.65:1 on the pill's composited fill #3A7465. The canvas's
  /// #CFE0D4 measured 3.94:1 there.
  static const headerPlaceholder = Color(0xFFE6F0EA);

  /// White at 12% / 22%: the search pill's fill and its (decorative) border. White text on the
  /// fill 5.42:1.
  static const headerSearchFill = Color(0x1FFFFFFF);
  static const headerSearchBorder = Color(0x38FFFFFF);

  /// White at 8% / 24%: a round header button's fill and border. Its white glyph 6.01:1.
  static const headerButtonFill = Color(0x14FFFFFF);
  static const headerButtonBorder = Color(0x3DFFFFFF);

  /// The 3dp ring around the header's avatar disc: white at 22%.
  static const headerAvatarRing = Color(0x38FFFFFF);

  /// THE HEADER. CSS `linear-gradient(160deg, #10392F 0%, #174E43 55%, #1F6150 100%)`: top to
  /// bottom, turned 20° anticlockwise so the darkest corner sits behind the greeting.
  static const headerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    transform: GradientRotation(-math.pi / 9),
    colors: [forestDeep, forest, forestHigh],
    stops: [0, 0.55, 1],
  );

  /// The dots drawn over [headerGradient]. (= [HeaderStars.dots]) Named here so the header's
  /// paint is found in one place; where a dot may sit, and where a halo may not, is
  /// [HeaderStars].
  static const starDots = HeaderStars.dots;

  // ── the gold task banner ("Meter readings due"). Its own inks, measured on both stops.

  static const bannerTop = Color(0xFFFFF5DF);
  static const bannerBottom = Color(0xFFF8E3B6);

  /// 10.34:1 on [bannerBottom], its darker stop.
  static const bannerTitle = Color(0xFF3D2F0E);

  /// 6.79:1 on [bannerBottom].
  static const bannerBody = Color(0xFF5C4A1E);

  /// CSS 120deg, left to right.
  static const bannerGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    transform: GradientRotation(math.pi / 6),
    colors: [bannerTop, bannerBottom],
  );

  /// The same banner on the dark ground: a low brown-gold, so the one warm surface in the
  /// palette is still warm at night rather than a pale slab glowing on near-black.
  static const bannerTopDark = Color(0xFF2E2614);
  static const bannerBottomDark = Color(0xFF3A2F15);

  /// [goldStar] for the title, 10.00:1 on [bannerBottomDark]; the body 8.99:1 there.
  static const bannerTitleDark = goldStar;
  static const bannerBodyDark = Color(0xFFE6D4AA);

  static const bannerGradientDark = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    transform: GradientRotation(math.pi / 6),
    colors: [bannerTopDark, bannerBottomDark],
  );

  /// The brand's source colour. Nothing is derived from it any more; it names the colour the
  /// whole palette is built around.
  static const seed = forest;

  // ═══ DARK — the dark scheme. Switched off in main.dart, still built and measured. ═════
  //
  // The canvas has no dark mode, so this one was designed against the same rules. The header
  // gradient, the forest hero tile and gold are IDENTICAL in both themes.

  /// The page ground.
  static const ground = Color(0xFF0D1613);

  /// (= [ground]) Nothing sits below the ground.
  static const surfaceContainerLowest = ground;

  /// A card. `colorScheme.surface` in dark. 1.12:1 against the ground, so cards carry a
  /// hairline.
  static const surfaceContainerLow = Color(0xFF15221D);

  /// Raised: fields, sheets, an inner block on a card. 1.24:1 against the ground.
  static const surfaceContainer = Color(0xFF1B2B25);

  /// Sheets. (= [surfaceContainer])
  static const surfaceContainerHigh = surfaceContainer;

  /// The neutral chip.
  static const surfaceContainerHighest = Color(0xFF26342F);

  /// The brightest fill — a skeleton block, a pressed row. 1.26:1 against the card.
  static const surfaceBright = Color(0xFF22352E);

  /// The quick-action well, a dark Mist, and a selected persona, in the dark theme.
  static const darkWell = Color(0xFF1F302A);
  static const darkMist = Color(0xFF1D3A31);
  static const darkSelected = Color(0xFF1A3029);

  /// THE BRAND, dark theme: links, focus, the active tab. 6.43:1 on its worst surface
  /// ([darkMist]), 9.59:1 on the ground.
  static const primary = Color(0xFF86C9A9);

  /// 9.59:1 on [primary].
  static const onPrimary = ground;

  /// THE FULL-BLEED BRAND — the onboarding grounds and the light theme's filled button.
  /// (= [forest]) White on it 9.51:1.
  static const brandDeep = forest;

  /// THE DARK FILLED BUTTON — Mist with a forest label, so the main action is the brightest
  /// object on a dark screen. (= [mist]) It is also the light plate the 2FA QR code sits on in
  /// both themes: a QR is a scanning target before it is interface.
  static const primaryContainer = mist;

  /// 7.54:1 on [primaryContainer].
  static const onPrimaryContainer = forest;

  /// DUE, EXPIRING — the dark theme's warm second voice. (= [warningDark]) Ground on it
  /// 10.08:1.
  static const secondary = Color(0xFFE9B85C);

  static const onSecondary = ground;

  /// [secondary] at 10% over the dark card, flattened. 7.35:1 for [secondary] on it.
  static const secondaryContainer = Color(0xFF2A3123);

  static const onSecondaryContainer = secondary;

  /// POSITIVE — paid, occupied, resolved. (= [successDark]) Ground on it 9.35:1.
  static const tertiary = Color(0xFF6FCB98);

  static const onTertiary = ground;

  /// [tertiary] at 10% over the dark card, flattened. 6.84:1 for [tertiary] on it.
  static const tertiaryContainer = Color(0xFF1E3329);

  static const onTertiaryContainer = tertiary;

  /// NEGATIVE, dark theme. (= [errorDark]) Ground on it 7.69:1. Named `errorTone` because
  /// [error] is the CANONICAL red further down; this one is a dark-theme TEXT colour.
  static const errorTone = Color(0xFFF08C82);

  static const onErrorTone = ground;

  /// [errorTone] at 10% over the dark card, flattened. 5.82:1 for [errorTone] on it.
  static const errorContainer = Color(0xFF2B2D27);

  static const onErrorContainer = errorTone;

  /// The info tint over the dark card, the one container Material has no slot for.
  static const darkInfoContainer = Color(0xFF213131);

  /// Primary text, dark. 10.75:1 on its worst surface ([darkMist]).
  static const onSurface = Color(0xFFF3EFE6);

  /// Secondary text, dark. 6.82:1 worst.
  static const onSurfaceVariant = Color(0xFFB6C4BC);

  /// A control's edge, dark. 3.66:1 on the raised field, 4.06:1 on the card.
  static const outline = Color(0xFF6E837A);

  /// The dark card edge and divider. 1.39:1 on the card — a line you see and never read.
  static const outlineVariant = Color(0xFF2A3B34);

  // ── legacy names, re-pointed. Same meaning, new value; unconverted screens move with us.

  static const darkBackground = ground;

  /// A card. `colorScheme.surface` is wired to the CARD, not the ground, because call sites in
  /// `features/` paint a card with it; the ground is `scaffoldBackgroundColor`.
  static const darkSurface = surfaceContainerLow;

  static const darkElevated = surfaceContainer;

  /// Brand ink for barriers and scrims, in both themes. (= [forestDeep]) A credential dialog's
  /// barrier is this at 48%, which is exactly [scrim].
  static const midnight = forestDeep;

  /// The dark theme's accent. (= [primary]) The name is historical; nothing here is indigo.
  static const darkIndigo = primary;

  /// The dark second voice. (= [secondary]) The name is historical; nothing here is blue.
  static const softBlue = secondary;

  static const darkTextPrimary = onSurface;
  static const darkTextSecondary = onSurfaceVariant;

  /// Muted text, dark. 4.76:1 on its worst surface ([darkMist]), 6.34:1 on the card.
  static const darkMuted = Color(0xFF93A59C);

  /// A placeholder on the dark field. 5.11:1 on the raised fill.
  static const darkPlaceholder = Color(0xFF8A9C93);

  static const darkHairline = outlineVariant;
  static const darkCardBorder = outlineVariant;
  static const darkControlBorder = outline;

  // ═══ LIGHT — the live theme ═══════════════════════════════════════════════════════════

  /// The page ground. `scaffoldBackgroundColor`. (= [cream])
  static const background = cream;

  /// A card — `colorScheme.surface` in light. (= [card]) 1.10:1 against the ground, which is
  /// a fill step only, so a card also takes the [cardBorder] hairline. It casts no shadow.
  static const surface = card;

  /// A sheet. (= [card])
  static const lightSheet = card;

  /// The neutral chip and the info note. `surfaceContainerHighest`. [inkMuted] on it 4.83:1,
  /// the tightest text pair in the light theme.
  static const lightField = Color(0xFFEAE3D6);

  /// (= [lightField]) The design's own name for the same fill.
  static const chipNeutral = lightField;

  /// `onSurface`. (= [ink])
  static const textPrimary = ink;

  /// The stronger supporting ink. (= [inkStrong])
  static const textSecondary = inkStrong;

  /// `primary` in light. (= [forest])
  static const lightPrimary = forest;

  /// (= [lightPrimary]) The name the existing call sites already use.
  static const indigo = lightPrimary;

  /// The quieter accent ink, kept under its old name for the call sites that mean "the other
  /// accent". (= [mistInk]) 5.75:1 on its worst surface.
  static const softBlueInk = mistInk;

  /// THE CONTROL BORDER — inputs, chips, radios, a drag handle. 3.53:1 on the card, 3.21:1 on
  /// the ground. Replaces the canvas's #DDD5C8 (1.43:1) and #BFB6A8 (1.97:1).
  static const controlBorder = Color(0xFF8F8679);

  /// A card's edge. 1.13:1 on the ground — decorative, which is the job.
  static const cardBorder = Color(0xFFECE4D8);

  /// A divider between rows. 1.20:1 on the card.
  static const hairline = Color(0xFFEFE8DC);

  // ═══ SEMANTIC ══════════════════════════════════════════════════════════════

  // ── CANONICAL. Identity + graphics, both themes, never small text. Each sits inside the
  //    dual-theme luminance window; worst cases are measured in theme_contrast_test.dart.

  /// Paid, occupied, resolved. 3.30:1 worst (the light chip fill), 3.51:1 dark.
  static const success = Color(0xFF3C8A5C);

  /// Due, pending, expiring. 3.74:1 / 3.10:1.
  static const warning = Color(0xFF986A10);

  /// Overdue, failed, refused. 3.79:1 / 3.06:1.
  static const error = Color(0xFFC8443B);

  /// Refund, new, "here is something you should know". 3.74:1 / 3.11:1.
  static const info = Color(0xFF3F76AD);

  /// The canonical "muted" identity, for a `tone:` that means nothing in particular. For
  /// muted TEXT use `context.tones.muted`. 3.39:1 / 3.42:1.
  static const textMuted = Color(0xFF6E7D76);

  // ── DARK-THEME TEXT. AA plain on every dark surface and on a 10% chip of itself.

  static const successDark = tertiary; //   6.13:1 worst, on a chip of itself
  static const warningDark = secondary; //  6.58:1
  static const errorDark = errorTone; //    5.16:1 worst, on dark Mist
  static const infoDark = Color(0xFF8DB7E6); // 5.82:1

  // ── LIGHT-THEME TEXT. AA plain on every light surface and on a 10% chip of itself.

  static const successInk = Color(0xFF256B45); // 5.01:1 worst, on a chip over the ground
  static const warningInk = Color(0xFF8A5A00); // 4.64:1 — the tightest status ink
  static const errorInk = Color(0xFFB3261E); //   4.99:1
  static const infoInk = Color(0xFF2C5D8A); //    5.36:1

  /// Muted text, light. (= [inkMuted])
  static const mutedInk = inkMuted;

  // ═══ DOMAIN — retired as colours ═══════════════════════════════════════════════════
  //
  // Rooms, people and food used to be three hues — violet, teal, saffron — so a row's icon
  // said what kind of thing it was. The clay icons do that job now, with far more character
  // than a tinted glyph ever had, and three extra hues on a cream page were the "rainbow"
  // the redesign exists to remove. So all three re-point to THE BRAND: one green family, plus
  // the four status tones that genuinely mean something. The names survive because ~30 call
  // sites pass them as `tone:`; they now resolve to forest in light and mint in dark.

  /// THE BRAND, canonical. (= [leaf]) Context-free paint: chart marks, rails, a meter. Inside
  /// the dual-theme window — 3.70:1 worst light, 3.13:1 worst dark. NOT legible as small text;
  /// resolve it first.
  static const brand = leaf;

  /// THE BRAND as light-theme text. (= [forest])
  static const brandInk = forest;

  /// THE BRAND as dark-theme text. (= [primary])
  static const brandDark = primary;

  static const rooms = brand;
  static const people = brand;
  static const food = brand;
  static const roomsInk = brandInk;
  static const peopleInk = brandInk;
  static const foodInk = brandInk;
  static const roomsDark = brandDark;
  static const peopleDark = brandDark;
  static const foodDark = brandDark;
}

// ─────────────────────────────────────────────────────────────────────────────
// SEMANTIC TONES — the theme-aware half of the palette.
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves a meaning to a colour that is legible *in the current theme*.
///
/// Registered on both themes, so `context.tones.error` is always the right red. See the
/// header of this file for why a single flat colour cannot do that job.
///
/// The chip recipe lives here too: a status chip is its ink on a 10% fill of itself, made
/// opaque over whatever it sits on. That is the tightest contrast case in the app — 12px type on
/// a tint of itself — so the alpha lives in one place, where it is measured.
///
/// WHERE A CHIP MAY SIT: the ground, a card or a well (and their dark twins). NOT on Mist or on
/// the neutral chip fill — both are darker than the ground, and the light warning chip measures
/// 4.13:1 on Mist and 4.09:1 on the chip fill. A tonal tile states its status in a word, the way
/// a tinted surface does (see [surfaceTintAlpha]).
@immutable
class ApnivaasSemantics extends ThemeExtension<ApnivaasSemantics> {
  const ApnivaasSemantics({
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.muted,
    required this.food,
    required this.rooms,
    required this.people,
    required this.chipFillAlpha,
    required this.chipBorderAlpha,
  });

  /// AA as text on every surface of the light theme, and on a chip of itself.
  static const light = ApnivaasSemantics(
    success: ApnivaasColors.successInk,
    warning: ApnivaasColors.warningInk,
    error: ApnivaasColors.errorInk,
    info: ApnivaasColors.infoInk,
    muted: ApnivaasColors.mutedInk,
    food: ApnivaasColors.foodInk,
    rooms: ApnivaasColors.roomsInk,
    people: ApnivaasColors.peopleInk,
    chipFillAlpha: _chipFill,
    chipBorderAlpha: _chipBorder,
  );

  /// AA as text on every surface of the dark theme, and on a chip of itself.
  static const dark = ApnivaasSemantics(
    success: ApnivaasColors.successDark,
    warning: ApnivaasColors.warningDark,
    error: ApnivaasColors.errorDark,
    info: ApnivaasColors.infoDark,
    muted: ApnivaasColors.darkMuted,
    food: ApnivaasColors.foodDark,
    rooms: ApnivaasColors.roomsDark,
    people: ApnivaasColors.peopleDark,
    chipFillAlpha: _chipFill,
    chipBorderAlpha: _chipBorder,
  );

  /// 10%. Measured worst case across both ink sets: 0.10 → 4.64:1 (light warning) · 0.12 →
  /// 4.51:1, the last value that still clears AA · 0.14 → 4.39:1, a fail. A tint of the tone
  /// moves the fill TOWARDS the text, so the ratio falls as the alpha rises; 0.10 keeps a
  /// point of headroom. One number for both themes, so a chip reads at the same weight in
  /// either.
  static const _chipFill = 0.10;

  /// FULL STRENGTH. The new chips are unstroked — the design draws them as a fill and a word —
  /// but the legacy [StateBadge] and [ToneSurface] still draw an edge, and when they do it is
  /// the tone at full strength, which clears 3:1 as a graphic.
  static const _chipBorder = 1.0;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color muted;

  /// The three retired DOMAIN inks. All three are the brand ink now; see the domain block in
  /// [ApnivaasColors].
  final Color food;
  final Color rooms;
  final Color people;

  final double chipFillAlpha;
  final double chipBorderAlpha;

  /// The brand as this theme's text colour: forest in light, mint in dark. (= [rooms])
  Color get brand => rooms;

  /// Maps a CANONICAL colour ([ApnivaasColors.success] and friends) to this theme's legible text
  /// value, and passes anything else through unchanged.
  ///
  /// This exists for the plumbing case: a widget is handed a `tone:` chosen far away, often
  /// inside a context-free `switch` over an enum. The caller keeps naming the meaning; the
  /// paint site fixes the theme.
  ///
  /// EVERY SPELLING OF THE BRAND RESOLVES. The canonical [ApnivaasColors.brand], the light
  /// [ApnivaasColors.lightPrimary] and the dark [ApnivaasColors.primary] all land on this
  /// theme's brand ink. Two call sites pass `ApnivaasColors.primary` as a tone, and that
  /// constant is the DARK scheme's mint — 1.9:1 on cream if it were painted as given.
  Color resolve(Color tone) {
    if (tone == ApnivaasColors.success) return success;
    if (tone == ApnivaasColors.warning) return warning;
    if (tone == ApnivaasColors.error) return error;
    if (tone == ApnivaasColors.info) return info;
    if (tone == ApnivaasColors.textMuted) return muted;
    // rooms, people, food and brand are one value now, so this one branch is all four.
    if (tone == ApnivaasColors.brand) return rooms;
    if (tone == ApnivaasColors.lightPrimary || tone == ApnivaasColors.primary) return rooms;
    return tone;
  }

  /// The fill behind a status chip, given either a canonical or a resolved tone.
  Color chipFill(Color tone) => resolve(tone).withValues(alpha: chipFillAlpha);

  /// The edge of a legacy status chip.
  Color chipBorder(Color tone) => resolve(tone).withValues(alpha: chipBorderAlpha);

  /// The alpha a whole SURFACE takes to carry a meaning, rather than a chip inside it.
  ///
  /// THE SAME NUMBER AS [chipFillAlpha], on purpose: a tinted card and a status chip are the
  /// same gesture at two scales, and one number keeps them the same weight of colour.
  ///
  /// ── THE RULE THAT FALLS OUT OF IT ───────────────────────────────────────────────────────
  ///
  /// **A STATUS CHIP MAY NOT SIT ON A SURFACE TINTED WITH ITS OWN TONE.** The chip's fill is a
  /// tint of the tone, so over a ground that is already one it lands twice as far toward its
  /// own label. Measured, that fails in BOTH themes now: 4.09:1 for the light warning chip on
  /// a warning-tinted well, 4.09:1 for the dark muted chip on a muted-tinted raised surface.
  /// So a tinted surface does not wear a chip: the GROUND is the chip, and the status word
  /// sits on it in the tone at full strength (worst 4.64:1 light, 4.82:1 dark). [ToneSurface]
  /// is the widget that enforces this.
  ///
  /// In the dark theme a tint of the card reproduces the dark container colours byte for byte
  /// ([ApnivaasColors.tertiaryContainer], [ApnivaasColors.secondaryContainer],
  /// [ApnivaasColors.errorContainer]); the contrast test asserts it, so a nudge to a tone has
  /// to answer for its container too.
  static const surfaceTintAlpha = _chipFill;

  /// An OPAQUE fill: this theme's [tone] laid over [base] at [surfaceTintAlpha].
  ///
  /// [base] must be the fill the surface would otherwise have painted — i.e.
  /// `GlassWeight.surfaceOf(scheme)` — because that is the set the ratios were measured on.
  Color tintedSurface(Color tone, Color base) =>
      Color.alphaBlend(resolve(tone).withValues(alpha: surfaceTintAlpha), base);

  @override
  ApnivaasSemantics copyWith({
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? muted,
    Color? food,
    Color? rooms,
    Color? people,
    double? chipFillAlpha,
    double? chipBorderAlpha,
  }) {
    return ApnivaasSemantics(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      muted: muted ?? this.muted,
      food: food ?? this.food,
      rooms: rooms ?? this.rooms,
      people: people ?? this.people,
      chipFillAlpha: chipFillAlpha ?? this.chipFillAlpha,
      chipBorderAlpha: chipBorderAlpha ?? this.chipBorderAlpha,
    );
  }

  @override
  ApnivaasSemantics lerp(ThemeExtension<ApnivaasSemantics>? other, double t) {
    if (other is! ApnivaasSemantics) return this;
    return ApnivaasSemantics(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      food: Color.lerp(food, other.food, t)!,
      rooms: Color.lerp(rooms, other.rooms, t)!,
      people: Color.lerp(people, other.people, t)!,
      chipFillAlpha: lerpDouble(chipFillAlpha, other.chipFillAlpha, t),
      chipBorderAlpha: lerpDouble(chipBorderAlpha, other.chipBorderAlpha, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// `context.tones.error` — the short way to the theme's semantic colours.
///
/// The fallback is the DARK set. It only fires for a widget pumped without an Apnivaas theme —
/// several feature tests do exactly that and assert the dark inks — and production always has
/// the theme.
extension ApnivaasTonesX on BuildContext {
  ApnivaasSemantics get tones =>
      Theme.of(this).extension<ApnivaasSemantics>() ?? ApnivaasSemantics.dark;
}

// ─────────────────────────────────────────────────────────────────────────────
// DOMAIN — what kind of thing this is.
// ─────────────────────────────────────────────────────────────────────────────

/// The areas of the product.
///
/// Each still names a tone and a glyph, because ~50 call sites build rows, buttons and cards
/// from a domain. The TONES have collapsed to the brand plus the status tones that genuinely
/// mean something — money is the paid green, complaints the amber of open work, notices the
/// info blue — and rooms, people, food and security are the brand. What KIND of thing a row is
/// belongs to its clay icon now (`domainClayIcon` in lib/shared/clay/clay_icons.dart).
///
/// The old rule still holds for what is left: domain colour lives on icons, actions and
/// avatars; status colour lives on surfaces and figures, and status wins a whole card.
///
/// Every colour here is a CANONICAL tone; resolve it at the paint site with
/// `context.tones.resolve(domain.tone)`, or let [DomainIcon] and friends do it.
enum ApnivaasDomain {
  /// Rent, fees, payments, expenses, subscriptions. The ledger's natural colour is the paid one.
  money(ApnivaasColors.success, Icons.account_balance_wallet_rounded),

  /// Floors, rooms, beds, the building. The brand.
  rooms(ApnivaasColors.rooms, Icons.meeting_room_rounded),

  /// Residents, staff, roommates, guardians, visitors, leaves. The brand.
  people(ApnivaasColors.people, Icons.people_alt_rounded),

  /// Complaints and tasks — open work. Amber, which is also what an OPEN complaint's own
  /// status chip paints, so an open row and its icon agree rather than argue.
  complaints(ApnivaasColors.warning, Icons.report_problem_rounded),

  /// Notices and announcements — "here is something you should know".
  notices(ApnivaasColors.info, Icons.campaign_rounded),

  /// The weekly menu. The brand.
  food(ApnivaasColors.food, Icons.restaurant_rounded),

  /// Security, the account, the platform itself. The brand.
  security(ApnivaasColors.brand, Icons.shield_rounded);

  const ApnivaasDomain(this.tone, this.icon);

  /// The canonical colour. Resolve it for the theme before painting text with it.
  final Color tone;

  /// The glyph that stands for the whole domain, for a caller with nothing more specific.
  final IconData icon;
}

// ─────────────────────────────────────────────────────────────────────────────
// SPACING — a 4dp rhythm, with two half-steps the canvas uses.
// ─────────────────────────────────────────────────────────────────────────────

/// `hair 2 · xxs 4 · tight 6 · xs 8 · sm 12 · md 16 · lg 20 · xl 24 · xxl 32 · xxxl 40 · huge 48`.
///
/// The screen gutter is [md] on dashboards and tab bodies and [lg] on auth, forms and
/// steppers. Sections sit [md] apart; a header sits [sm] above the content under it.
abstract final class Space {
  /// The gap between a figure and its caption, a dot and its word.
  static const hair = 2.0;
  static const xxs = 4.0;

  /// The gap between a quick-action well and its label.
  static const tight = 6.0;
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
// RADIUS
// ─────────────────────────────────────────────────────────────────────────────

/// The corners, from a badge to the header.
///
/// TWO CARD SIZES, AND WHY. The canvas draws its containers at 24 — a stat tile, the list
/// group, the quick-action panel, the banner. But ~150 call sites in `features/` round every
/// card with [rCard], including 56dp rows where 24 turns a card into a capsule that reads as a
/// button. So [card] is 20, the generic card and row, and [surface] is the canvas's 24 for the
/// large containers the clay widgets draw.
abstract final class Radii {
  /// A legacy badge, a progress track's end.
  static const tiny = 8.0;

  /// Inputs, choice chips, the back button, the search pill, a snackbar.
  static const control = 14.0;

  /// A 52dp button, the tab-bar indicator, an info note.
  static const button = 16.0;

  /// The 56dp call to action.
  static const buttonLarge = 18.0;

  /// The 64dp quick-action well and the Mist info banner.
  static const well = 22.0;

  /// A content card or row. See the class note.
  static const card = 20.0;

  /// The canvas's large containers: stat tiles, list groups, the quick-action panel, banners.
  static const surface = 24.0;

  /// The sign-in hero card.
  static const hero = 28.0;

  /// Bottom sheets and modals.
  static const sheet = 28.0;

  /// The header's bottom corners.
  static const header = 30.0;

  /// Genuinely capsule-shaped: chips, pill buttons, progress tracks, an avatar.
  static const pill = 999.0;

  /// A checkbox's corner.
  static const check = 6.0;

  static const rTiny = BorderRadius.all(Radius.circular(tiny));
  static const rControl = BorderRadius.all(Radius.circular(control));
  static const rButton = BorderRadius.all(Radius.circular(button));
  static const rButtonLarge = BorderRadius.all(Radius.circular(buttonLarge));
  static const rWell = BorderRadius.all(Radius.circular(well));
  static const rCard = BorderRadius.all(Radius.circular(card));
  static const rSurface = BorderRadius.all(Radius.circular(surface));
  static const rHero = BorderRadius.all(Radius.circular(hero));
  static const rSheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
  static const rHeaderBottom = BorderRadius.vertical(bottom: Radius.circular(header));
  static const rPill = BorderRadius.all(Radius.circular(pill));
  static const rCheck = BorderRadius.all(Radius.circular(check));
}

// ─────────────────────────────────────────────────────────────────────────────
// ICONS, ART + STROKES
// ─────────────────────────────────────────────────────────────────────────────

/// Material glyph sizes. A glyph is not a tap target; the 48dp minimum lives on the control.
abstract final class IconSize {
  static const xs = 12.0; // inside a chip, an activity disc
  static const sm = 14.0; // beside a label, a row chevron
  static const md = 16.0; // list rows, section headings
  static const lg = 20.0; // app bar, a row's trailing chevron

  /// The glyph inside a 44dp header or back button.
  static const action = 22.0;

  /// The single glyph over an empty or failed section, where there is no clay art.
  static const xl = 32.0;
}

/// The clay icons' sizes. One table, so a quick action and a stat tile can never drift a few
/// dp apart. The art ships at 192px (role art at 320px), so 64dp is pixel-exact at 3x and
/// anything larger is softly oversampled — which is why nothing below is bigger than it needs
/// to be.
abstract final class ClaySize {
  /// A tab-bar icon, unselected and selected.
  static const navOff = 34.0;
  static const nav = 36.0;

  /// The leading icon of a list row.
  static const list = 46.0;

  /// Inside a 64dp quick-action well.
  static const action = 54.0;

  /// A stat tile's icon.
  static const tile = 56.0;

  /// An info banner.
  static const banner = 72.0;

  /// The forest hero tile.
  static const hero = 78.0;

  /// An empty state, and the gold task banner.
  static const promo = 96.0;

  /// Persona art on the role picker.
  static const persona = 128.0;

  /// The owner on the sign-in hero card.
  static const heroArt = 184.0;
}

/// THE ACCOUNT DISC AT THE TOP-LEFT OF EVERY STAFF SCREEN.
///
/// 44 is the disc the existing mastheads draw, and the size the product owner asked to be "big
/// to access and to view perfectly". The new header draws [headerLarge] — the canvas's 50 —
/// and drops back to [header] below 360dp.
abstract final class AvatarSize {
  static const header = 44.0;
  static const headerLarge = 50.0;

  /// An initials disc at the head of a list row, matching [ClaySize.list].
  static const list = 46.0;
}

/// The generated artwork on a first-run empty state.
abstract final class ArtSize {
  /// The legacy flat illustrations' box.
  static const emptyState = 160.0;

  /// The Mist disc a clay empty-state icon sits on.
  static const emptyDisc = 136.0;
}

/// Border widths. Weight comes from colour first, then width.
abstract final class Strokes {
  /// A card's edge and a divider.
  static const hairline = 1.0;

  /// A control's edge: an input, a chip, an outlined button, a radio ring.
  static const control = 1.5;

  /// A drawn line at glyph weight — a progress ring, a chart's rule.
  static const glyph = 1.5;

  /// A focused or errored control.
  static const focus = 2.0;

  /// The strip down a tinted card's leading edge. A graphic, always the tone at full strength,
  /// and never the only carrier of its meaning — the card still spells the status out.
  static const rail = Space.xxs;
}

// ─────────────────────────────────────────────────────────────────────────────
// OPACITY
// ─────────────────────────────────────────────────────────────────────────────

/// The places the design dims something instead of recolouring it.
abstract final class Dim {
  /// "You can look at this, you cannot use it" — one number over a whole subtree.
  static const readOnly = 0.45;

  /// The floor of a skeleton's pulse. It breathes between here and opaque.
  static const skeletonPulse = 0.55;

  /// A skeleton held still under reduce motion.
  static const skeletonStill = 0.8;

  /// An unselected tab's clay icon, drawn through the greyscale filter.
  static const navOff = 0.85;
}

// ─────────────────────────────────────────────────────────────────────────────
// SURFACE WEIGHT — an elevation ladder, and NOT a blur.
// ─────────────────────────────────────────────────────────────────────────────

/// Three weights of surface. The name is historical: these panes used to blur.
///
/// ── THERE IS NO BLUR IN THIS APP ─────────────────────────────────────────────────────────
///
/// `BackdropFilter` is the most expensive thing this app can draw, the product owner's own
/// phone reported "stuck, lag", and release builds have disabled it unconditionally since the
/// commit "Release builds never blur". Do not reintroduce it — not behind a flag, not "just for
/// the sheet".
///
/// ── WHAT EACH WEIGHT IS ──────────────────────────────────────────────────────────────────
///
/// Light: a card is [ApnivaasColors.card]; `regular` — an inner block, a row inside a card —
/// is the [ApnivaasColors.well] one whisper below it; a sheet is a card lifted out. Dark: card,
/// then the raised fill for both `regular` and `thick`, because a sheet is separated by the
/// scrim and [Shadows.level3], not by another rung of near-black. [surfaceOf] is the only place
/// that decision is made.
enum GlassWeight {
  /// A resting card.
  thin,

  /// A surface that sits on another one: an inner block, a row inside a card.
  regular,

  /// A sheet or modal.
  thick;

  /// The surface this weight paints in the given scheme.
  Color surfaceOf(ColorScheme scheme) {
    if (scheme.brightness == Brightness.light) {
      return switch (this) {
        GlassWeight.thin => scheme.surface, // #FFFDF9, the card
        GlassWeight.regular => scheme.surfaceContainer, // #EEF4EF, the well
        GlassWeight.thick => scheme.surface, // a sheet reads as a card lifted out
      };
    }
    return switch (this) {
      GlassWeight.thin => scheme.surfaceContainerLow,
      GlassWeight.regular => scheme.surfaceContainer,
      GlassWeight.thick => scheme.surfaceContainerHigh,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOTION
// ─────────────────────────────────────────────────────────────────────────────

abstract final class Motion {
  /// The press itself — a scale to 0.97 on a card or button, 0.94 on an icon well.
  static const press = Duration(milliseconds: 100);

  /// The brief's 150–350ms band. Fast enough to feel like a response, slow enough to be read.
  static const fast = Duration(milliseconds: 150); // release, colour, opacity, icon cross-fade
  static const base = Duration(milliseconds: 240); // cards, tabs, chips, the nav indicator
  static const slow = Duration(milliseconds: 340); // sheets, page change, stepper progress

  /// Something leaving: a sheet closing.
  static const exit = Duration(milliseconds: 200);

  /// Decelerating: motion that enters the screen should arrive, not bounce.
  static const enter = Curves.easeOutCubic;

  /// Accelerating, for an exit.
  static const leave = Curves.easeInCubic;

  /// Symmetric, for things that move within the screen.
  static const move = Curves.easeInOutCubic;

  /// About 6% overshoot. ONLY the tab-bar indicator's pop and a persona being chosen — the two
  /// moments a small bounce reads as "yes, that one" rather than as decoration.
  static const emphasis = Cubic(0.34, 1.36, 0.64, 1.0);

  /// The delay between one item of a list entering and the next.
  ///
  /// Small on purpose. At 40ms a six-row list is fully in at 200ms plus the item's own [base],
  /// which reads as one movement with a direction rather than as rows arriving one at a time.
  ///
  /// ── THE RULES A STAGGER HERE MUST KEEP ──────────────────────────────────────────────────
  ///
  ///  * It runs ONCE, on first build, and never again. A list that re-plays its entrance on
  ///    every rebuild is a list that flickers whenever a provider refreshes.
  ///  * It never delays the first frame. The entrance is an opacity and a small offset on
  ///    content that is already laid out and already hit-testable.
  ///  * It is capped — see [staggerCap]. A 200-row list must not compute a ten-second ramp.
  static const stagger = Duration(milliseconds: 40);

  /// How many items still get a stagger step before the delay stops growing.
  static const staggerCap = 8;

  /// One skeleton breath, out and back. The only repeating animation in the app, and it stops
  /// the moment data arrives.
  static const skeletonPulse = Duration(milliseconds: 1200);

  /// How long an inline confirmation stays on the control that produced it — the "Copied" that
  /// replaces a copy button's label.
  static const confirmed = Duration(milliseconds: 1600);

  /// How long a snackbar carrying a FAILURE stays up. A reading budget, not an animation: the
  /// sentences this app shows on a refusal are a full line, read while talking to somebody.
  static const readMessage = Duration(seconds: 5);

  /// VESTIGIAL. Nothing in the app blurs any more — see [GlassWeight] — so setting this
  /// changes nothing that gets drawn. It survives only because `main.dart` writes to it.
  static bool glassFallback = false;
}

// ─────────────────────────────────────────────────────────────────────────────
// ELEVATION
// ─────────────────────────────────────────────────────────────────────────────

/// Soft, low and tinted with the brand — and used sparingly, which is most of the design.
///
/// A RESTING CARD CASTS NOTHING. The canvas separates a card from the cream ground with its fill
/// and a hairline ([ApnivaasColors.cardBorder]); across all six boards the only shadow under a
/// surface is the chosen persona's. So [level1] and [level2] are both empty — and that matters,
/// because ~40 call sites take [level2] as [GlassSurface]'s default, and a page where every card
/// floats has no hierarchy. What still casts is what genuinely sits above the page: a chosen
/// persona or a dragged item ([lift]), the tab bar ([bar]), a sheet or dialog ([level3]) and
/// the one FAB ([glow]).
///
/// The tint is the point of the ones that remain: a black drop shadow on cream reads as a grey
/// smudge, forest at a low alpha as the object sitting a millimetre above the page. These are
/// LIGHT-theme values; on the dark ground a tinted shadow is invisible, and depth there comes
/// from the surface ladder.
abstract final class Shadows {
  /// Flat against the ground: fill and hairline only.
  static const level1 = <BoxShadow>[];

  /// A resting card. EMPTY, like [level1] — see the class note. Kept as its own name because
  /// [GlassSurface] defaults to it and a modal passes [level3] in its place.
  static const level2 = <BoxShadow>[];

  /// A selected persona card, a dragged item: forest at 16%.
  static const lift = <BoxShadow>[
    BoxShadow(color: Color(0x29174E43), blurRadius: 20, offset: Offset(0, 8)),
  ];

  /// The bottom tab bar, casting upward.
  static const bar = <BoxShadow>[
    BoxShadow(color: Color(0x0F174E43), blurRadius: 18, offset: Offset(0, -6)),
  ];

  /// A sheet floating over the scrim. A large soft shadow plus a tight contact one so the edge
  /// does not float free of it, cast UPWARD from the bottom edge the sheet rises from.
  static const level3 = <BoxShadow>[
    BoxShadow(color: Color(0x2E10392F), blurRadius: 32, offset: Offset(0, -8)),
    BoxShadow(color: Color(0x0F10392F), blurRadius: 4, offset: Offset(0, -1)),
  ];

  /// A dialog in the middle of the screen: [level3]'s two shadows cast DOWNWARD, as light from
  /// above falls under a card lifted towards it. On a centred card level3's upward cast sat
  /// above the card, which read as a shadow with nothing to cast it.
  static const dialog = <BoxShadow>[
    BoxShadow(color: Color(0x2E10392F), blurRadius: 32, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0F10392F), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// The FAB's halo — [ApnivaasColors.forest] at 30%. One per screen, on the one control that
  /// is the screen's purpose.
  static const glow = <BoxShadow>[
    BoxShadow(color: Color(0x4D174E43), blurRadius: 20),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// THE HEADER'S STARS
// ─────────────────────────────────────────────────────────────────────────────

/// One dot of the header's star field, in the canvas's 390×170 reference box.
@immutable
class StarDot {
  const StarDot(this.x, this.y, this.radius, this.color, this.alpha,
      {this.haloRadius, this.haloColor, this.haloAlpha});

  final double x;
  final double y;
  final double radius;
  final Color color;
  final double alpha;

  /// A faint disc behind the core, on the three brightest stars only.
  final double? haloRadius;
  final Color? haloColor;
  final double? haloAlpha;
}

/// The procedural "stars" in the forest header, verbatim from the owner-home board.
///
/// Deterministic: the same dots in the same places on every screen and every launch, so the
/// header reads as a printed object rather than as noise. x scales with the header's width
/// against [referenceWidth]; y stays in dp from the top of the content, so the field keeps its
/// relationship to the greeting whatever the status bar's height.
///
/// They stay in the trailing half and along the top and bottom edges, so none lands behind the
/// greeting or the title. The halos are the only part that could lift a ground under type (a
/// halo under the greeting would take it to 3.71:1), so a halo is drawn only from
/// [haloMinFraction] of the width outward; a star further in keeps its core alone.
abstract final class HeaderStars {
  static const referenceWidth = 390.0;
  static const referenceHeight = 170.0;

  /// Halos only at or beyond this fraction of the header's width.
  static const haloMinFraction = 0.78;

  static const dots = <StarDot>[
    StarDot(322, 30, 1.7, ApnivaasColors.goldStar, 1,
        haloRadius: 5, haloColor: ApnivaasColors.goldHalo, haloAlpha: 0.14),
    StarDot(268, 72, 1.3, Color(0xFFFFFFFF), 0.9,
        haloRadius: 4, haloColor: Color(0xFFFFFFFF), haloAlpha: 0.11),
    StarDot(360, 104, 1.2, ApnivaasColors.goldStar, 0.95,
        haloRadius: 3.6, haloColor: ApnivaasColors.goldHalo, haloAlpha: 0.12),
    StarDot(212, 10, 1, Color(0xFFFFFFFF), 0.7),
    StarDot(150, 8, 0.9, ApnivaasColors.goldStar, 0.75),
    StarDot(292, 14, 1, Color(0xFFFFFFFF), 0.6),
    StarDot(380, 34, 1, Color(0xFFFFFFFF), 0.55),
    StarDot(344, 64, 0.8, ApnivaasColors.goldStar, 0.65),
    StarDot(300, 50, 0.8, Color(0xFFFFFFFF), 0.5),
    StarDot(372, 150, 1, Color(0xFFFFFFFF), 0.5),
    StarDot(28, 152, 0.9, Color(0xFFFFFFFF), 0.4),
    StarDot(112, 158, 0.8, Color(0xFFFFFFFF), 0.4),
    StarDot(198, 160, 0.8, ApnivaasColors.goldStar, 0.5),
    StarDot(300, 158, 0.9, Color(0xFFFFFFFF), 0.45),
    StarDot(66, 8, 0.8, Color(0xFFFFFFFF), 0.45),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// BREAKPOINTS — phones are the design target; tablets get more columns, not bigger text.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class Breakpoints {
  static const compact = 360.0; // smallest phone the layouts are drawn for (tests run 320)
  static const medium = 600.0; // large phone / small tablet

  /// Where a phone layout stops being the right one: container padding grows and the bottom
  /// nav is replaced by links in the header.
  static const expanded = 768.0;
}

/// The widest a tab body is allowed to be, from [Breakpoints.expanded] up.
///
/// 720 is the width at which a row of three KPI tiles, a fee ledger row with four figures, or
/// a paragraph of a notice all still read at arm's length on a 10-inch tablet. Applied in
/// shared/motion/tab_swap.dart, the one widget all five shells run their tabs through; the
/// chrome around the body — header, nav bar — stays full-bleed on purpose.
const maxContentWidth = 720.0;
