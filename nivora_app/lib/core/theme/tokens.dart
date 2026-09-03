library;

import 'package:flutter/material.dart';

/// Nivora's design tokens. The single place any visual constant is defined.
///
/// The rule this file exists to enforce: changing the accent colour, the corner radius or the
/// motion curve must be a one-line edit here, never a search across screens. Nothing in
/// `features/` may hardcode a colour, a radius, a duration or a spacing value.
///
// ═════════════════════════════════════════════════════════════════════════════════════════
// WHERE THESE VALUES COME FROM
// ═════════════════════════════════════════════════════════════════════════════════════════
//
// FIGMA, file `8qkhZArLAz9KVOIiWF8ZTG`, the nineteen `screen-*` frames in the `4:*` range.
// The file defines no Figma variables, so the hexes below are the raw literals the designer
// used, read off `get_design_context` for the frames named in each comment. If one of them is
// wrong it is wrong in Figma and the fix belongs there, not here.
//
// THIS REPLACES THE STITCH PALETTE. The app previously shipped `design-stitch/`: navy-black
// #0B1326 with Material 3's stock dark purple #D0BCFF and a mint #4EDEA3. That was the colour
// Flutter generates when nobody picks one. The Figma palette is a deliberate brand — neutral
// near-black, warm cream text, gold accent — and every surface, every accent and the whole
// type stack moves with it. See `design-figma/DESIGN-SYSTEM.md`.
//
// ── THE FOUR DECISIONS WORTH READING BEFORE CHANGING ANYTHING ────────────────────────────
//
//   1. THE PRIMARY BUTTON IS CREAM, NOT GOLD. `screen-signin` (4:83) and the retry button on
//      `screen-empty-error-skeleton` (4:1596) are `bg-[#f5f3ee]` with `text-[#0b0d0f]`. That
//      is the single most distinctive decision in this design and it is not a mistake to be
//      "fixed" to the accent colour. So [primaryContainer] is the cream and theme.dart wires
//      FilledButton to it; [primary] is the gold #C9A96E, which is what a link, an active tab
//      and an emphasis figure use. The gold DOES fill one button — the "Renew Subscription"
//      CTA inside the expired-subscription banner (4:1537) — and that is [primary].
//
//   2. THE DESIGN IS FLAT AND EDGED, NOT SHADOWED. Not one frame in the file carries a
//      `box-shadow`. Every card is a fill plus a 1px #292E33 hairline, and the ground is dark
//      enough that the hairline is the only separator needed (#292E33 measures 1.42:1 on the
//      ground against the card's own 1.05:1). [Shadows.level2] is therefore EMPTY: a resting
//      card gets its edge, not a smear. Only a genuinely floating surface — a modal sheet
//      over a scrim — keeps a shadow. And there is still no blur anywhere; see [GlassWeight].
//
//   3. #6F747A COULD NOT SURVIVE AS TEXT, AND THAT IS ARITHMETIC. The design sets CAPS
//      labels, meta lines, chart axes and input placeholders in `#6f747a`. Measured, that is
//      4.13:1 on the ground, 3.92:1 on the card and 3.70:1 on the raised surface — below AA
//      on every surface in the app, including the one the mockup itself puts it on. It
//      survives untouched as [outline], where WCAG 1.4.11's 3:1 applies and it clears it
//      everywhere. As TEXT it is [darkMuted], the same hue and saturation lifted in lightness
//      until the tightest case in the app passes. The exact delta is recorded there.
//
//   4. THE MOCKUPS' OWN BADGES ARE NOT AA, AND THE FIX IS IN THE COLOUR, NOT THE RECIPE. The
//      state badges on `screen-empty-error-skeleton` are 9px bold text on a 10% tint of
//      themselves — `#5577ad` on `rgba(85,119,173,0.1)`, which measures 4.03:1. The recipe is
//      kept exactly (10% fill, full-strength 1px border; see [NivoraSemantics]) and the two
//      tones that could not carry it were lifted along their own hue by the minimum that
//      works. Four of the six design tones were already fine and are used verbatim.
//
// ── EVERY NUMBER IN A COMMENT IS MEASURED ────────────────────────────────────────────────
//
// The ratios quoted next to the tokens are WCAG 2.1 relative-luminance measurements, not
// estimates, and `test/theme_contrast_test.dart` recomputes every one of them from the token
// itself. A colour nudged by eye fails `flutter test` with the number it actually measured.
// The bars are §1.4.3 (text, 4.5:1) and §1.4.11 (graphical objects and UI components, 3:1).
//
// ── THE LIGHT THEME IS DERIVED, NOT DRAWN ────────────────────────────────────────────────
//
// Figma ships one look and it is dark. (`screen-admin-dashboard` 4:1369 is light; the design
// note treats it as a stale exploration and the admin dashboard is built dark like the rest.)
// A light-mode phone still has to get something legible, so the light scheme is
// `ColorScheme.fromSeed(seedColor: NivoraColors.seed)` with the seed set to the design's own
// gold accent — derived, never hand-picked. The consts below are that function's output,
// pinned so they can be used in `const` expressions; the test asserts each still equals what
// `fromSeed` produces, so they cannot drift into being invented. It measures clean (worst
// text pair 5.01:1) and it is warm rather than the generic grey-violet the old seed produced,
// but nobody designed it. The honest recommendation that goes with it is `ThemeMode.dark`.
//
// ── WHY THERE ARE STILL THREE SEMANTIC SETS ──────────────────────────────────────────────
//
// A single flat colour cannot be AA-legible as text on both a white surface and a near-black
// one. To reach 4.5:1 on the light card #FFFFFF a colour needs relative luminance L ≤ 0.1833;
// to reach 4.5:1 on the dark card #111417 (L = 0.00681) it needs L ≥ 0.2057. The windows do
// not overlap at any hue, because luminance is the only variable in the ratio. So:
//
//   1. CANONICAL — [NivoraColors.success] and friends. The IDENTITY of a meaning, and the
//      value that survives when a colour is painted with no BuildContext: chart bars, meter
//      fills, status icons, tinted borders. Each is the corresponding FIGMA tone taken to the
//      lightness that maximises its worst case across all eight surfaces of both themes;
//      worst measured 3.50:1, so every one clears WCAG 1.4.11 everywhere, including the light
//      input fill and the dark `surface-bright`. (The old palette could not do that — its
//      windows were disjoint. The new ground is darker and the new light surfaces are less
//      extreme, and the window opened. The test proves the overlap rather than asserting it.)
//      NOT legible enough for small text — do not put 11px type in them.
//   2. LIGHT TEXT — the `...Ink` values, AA on every light surface AND on a 10% chip of
//      themselves over any of them. Worst 4.57:1.
//   3. DARK TEXT  — the `...Dark` values, same contract on the dark surfaces. Worst 4.56:1.
//
//   Sets 2 and 3 are reached through [NivoraSemantics], the ThemeExtension registered on both
//   themes. At a paint site with a context write `context.tones.error`; where a canonical
//   colour has already been plumbed through a `tone:` parameter call
//   `context.tones.resolve(tone)`.
//
//   THIS IS THE RULE: canonical for shapes, resolved for type.
// ═════════════════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// COLOUR
// ─────────────────────────────────────────────────────────────────────────────

/// The palette. Ratios in comments are measured — see the header.
///
/// Two vocabularies live here on purpose. The `dark*` / `*Ink` names are the ones ~200 call
/// sites across `features/` already use, so they keep their meaning and simply point at new
/// values: an unconverted screen shifts to the new identity instead of breaking. The
/// Material-3 role names ([surfaceContainerLow] and friends) are the design's own vocabulary
/// and are what a screen being restyled against a mockup should reach for.
abstract final class NivoraColors {
  // ═══ THE SOURCE COLOUR ══════════════════════════════════════════════════════
  /// The design's gold accent, used ONLY as a seed for the light scheme. Paint with
  /// [primary], which is the same hex in the role it actually has.
  static const seed = Color(0xFFC9A96E);

  // ═══ DARK — the Figma palette, verbatim ═════════════════════════════════════
  // Read off `screen-student-dashboard` 4:947, `screen-owner-dashboard` 4:437,
  // `screen-signin` 4:60, `screen-subscription-expired` 4:1520 and
  // `screen-empty-error-skeleton` 4:1562. Do not adjust by eye.

  // ── surfaces. The design ships THREE, plus one brighter fill. Elevation gets LIGHTER as it
  //    rises, which is how depth reads on an emissive panel and how M3 expresses it in dark.

  /// `background` — the page ground. Every `screen-*` frame is `bg-[#0b0d0f]`.
  static const ground = Color(0xFF0B0D0F);

  /// The deepest well — the scrim, the modal barrier, the snackbar.
  ///
  /// (= [ground]) The design has nothing below its background, so this is not a fifth colour;
  /// it is the same one, named for the job. A scrim at 72% of it over the ground still reads
  /// as a barrier because the sheet in front is two rungs lighter.
  static const surfaceContainerLowest = ground;

  /// `surface (card)` #111417 — the rent card, the KPI cards, notice items, and the inner
  /// blocks of the skeleton layout (4:1603, 4:1606).
  static const surfaceContainerLow = Color(0xFF111417);

  /// `surface raised` #171A1E — icon buttons (4:454), inputs (4:77), the room card, the
  /// activity feed's disc, the chart panel, and the empty/error/skeleton cards (4:1575).
  static const surfaceContainer = Color(0xFF171A1E);

  /// Headers and sheets. (= [surfaceContainer]) The design's own bars and panels are the
  /// raised surface and it ships nothing above it for that job; a modal sheet is separated
  /// from the bar behind it by the scrim and [Shadows.level3], not by another rung of colour.
  static const surfaceContainerHigh = surfaceContainer;

  /// Chips and the input fill. (= [surfaceContainer]) 4:77 is the design's own text field:
  /// `bg-[#171a1e] border border-[#292e33]`.
  static const surfaceContainerHighest = surfaceContainer;

  /// `#1D2227` — the brightest fill in the file. It is the shimmer bar of the skeleton layout
  /// (4:1604, 4:1605, 4:1609, 4:1610) and it is what an icon badge sits on.
  ///
  /// A FILL, NEVER A TEXT BACKGROUND in the design — though every text token here is AA on it
  /// anyway (worst 4.56:1), so a label that lands on one is still legible.
  static const surfaceBright = Color(0xFF1D2227);

  // ── key colours

  /// `accent (gold)` #C9A96E — emphasis, links, active state, chart lines, the brand dot, and
  /// the renew CTA's fill (4:1537). 8.70:1 on the ground, 7.16:1 on [surfaceBright].
  static const primary = Color(0xFFC9A96E);

  /// Text on the gold. The design's own `text-[#0b0d0f]` on 4:1537. 8.70:1.
  static const onPrimary = ground;

  /// THE CREAM PRIMARY BUTTON — `bg-[#f5f3ee]` on 4:83 ("Continue") and 4:1596 ("Retry").
  /// Not a container in the M3 tonal sense; it is the design's filled action and this is the
  /// role theme.dart wires FilledButton to. (= [onSurface])
  static const primaryContainer = Color(0xFFF5F3EE);

  /// Text on the cream button. The design's own `text-[#0b0d0f]`. 17.56:1 — the highest
  /// contrast pairing in the app, on the control that matters most.
  static const onPrimaryContainer = ground;

  /// `warning (amber-gold)` #D5A64C — due, expiring, the subscription banner's eyebrow
  /// (4:1535) and the "12 Open" complaints figure (4:485). 8.70:1 on the ground.
  ///
  /// It is the M3 `secondary` role because it is the design's second voice: the same family
  /// as the gold, one step warmer, and never used for anything that is merely decorative.
  static const secondary = Color(0xFFD5A64C);

  /// 8.70:1 on [secondary].
  static const onSecondary = ground;

  /// The design's own `rgba(213,166,76,0.1)` banner fill (4:1531) composited over the card,
  /// pinned flat. Nothing translucent is stored in a ColorScheme, and a container role that
  /// is secretly transparent composites twice the moment somebody stacks it.
  static const secondaryContainer = Color(0xFF25231C);

  /// 7.03:1 on [secondaryContainer].
  static const onSecondaryContainer = secondary;

  /// POSITIVE — paid, occupied, resolved, on-duty. The design's own `#5fae82`, from the rent
  /// collection meter and its "77%" label (4:467, 4:468). 7.29:1 on the ground.
  static const tertiary = Color(0xFF5FAE82);

  /// 7.29:1 on [tertiary].
  static const onTertiary = ground;

  /// [tertiary] at the design's 10%, composited over the card. See [secondaryContainer].
  static const tertiaryContainer = Color(0xFF192322);

  /// 6.03:1 on [tertiaryContainer].
  static const onTertiaryContainer = tertiary;

  /// NEGATIVE — overdue, failed, the error-state badge (4:1590), the notification dot
  /// (4:457), the "Pending Fees" figure (4:481).
  ///
  /// The design's `#C96B6B` lifted by (+3, +7, +7). At 9px on its own 10% tint the mockup's
  /// value measures 4.29:1 — the badge in the file is not AA — and this is the minimum lift
  /// along its own hue that clears 4.5:1 both plain and on that tint. 5.76:1 on the ground.
  ///
  /// Named `errorTone` rather than `error` because [error] is the CANONICAL dual-theme red
  /// further down, and the two are not interchangeable: this one is a dark-theme TEXT colour,
  /// that one is a graphic that has to survive a white background.
  static const errorTone = Color(0xFFCC7272);

  /// 5.76:1 on [errorTone].
  static const onErrorTone = ground;

  /// [errorTone] at the design's 10%, composited over the card. See [secondaryContainer].
  static const errorContainer = Color(0xFF241D20);

  /// 4.89:1 on [errorContainer].
  static const onErrorContainer = errorTone;

  // ── ink and lines

  /// `on-surface` #F5F3EE — primary text. WARM CREAM, NOT PURE WHITE, and the difference is
  /// the whole temperature of the product. 16.67:1 on the card.
  static const onSurface = Color(0xFFF5F3EE);

  /// `on-surface secondary` #A2A6AB — supporting text, roommate names, the sub-lines under a
  /// KPI figure. 7.55:1 on the card.
  static const onSurfaceVariant = Color(0xFFA2A6AB);

  /// `on-surface tertiary` #6F747A — the design's quietest ink, and here it draws SHAPES
  /// rather than type: the 1.5px outline of the empty-state glyph (4:1579), its three bars,
  /// the home-indicator pill, and the border of a text field.
  ///
  /// 3.92:1 on the card and 3.70:1 on the raised surface, so it clears the 3:1 of WCAG
  /// 1.4.11 everywhere a control's edge or an illustrative stroke is drawn. As TEXT it does
  /// not clear 4.5:1 anywhere at all — that is what [darkMuted] is for, and the header
  /// explains why the design's own usage had to be split in two.
  static const outline = Color(0xFF6F747A);

  /// `outline / hairline` #292E33 — every card border, every divider, the avatar disc, the
  /// header's underline, the meter track. 1.35:1 on the card: a line you can see and never
  /// read, which is exactly the job.
  static const outlineVariant = Color(0xFF292E33);

  // ── legacy names, re-pointed. Same meaning, new value; unconverted screens move with us.

  /// The page ground. (= [ground])
  static const darkBackground = ground;

  /// A card. (= [surfaceContainerLow])
  ///
  /// `colorScheme.surface` is wired here, NOT to the design's `background` role, because 17
  /// call sites in `features/` paint a CARD with `colorScheme.surface` and the ground would
  /// make every one of them vanish. The ground is `scaffoldBackgroundColor`. See theme.dart,
  /// which says the same thing where it matters.
  static const darkSurface = surfaceContainerLow;

  /// A raised card. (= [surfaceContainer])
  static const darkElevated = surfaceContainer;

  /// Brand ink: scrims, the modal barrier, the snackbar. (= [surfaceContainerLowest])
  static const midnight = surfaceContainerLowest;

  /// The dark theme's accent. (= [primary]) The name is historical; nothing here is indigo.
  static const darkIndigo = primary;

  /// The second voice. (= [secondary]) The name is historical; nothing in this design is
  /// blue. Never for meaning on its own — a chart's other line, an illustrative fill.
  static const softBlue = secondary;

  /// Body text, dark. (= [onSurface]) 16.67:1 on the card, 14.45:1 on [surfaceBright].
  static const darkTextPrimary = onSurface;

  /// Secondary text, dark. (= [onSurfaceVariant]) 7.55:1 / 6.55:1.
  static const darkTextSecondary = onSurfaceVariant;

  /// Muted text, dark. THE ONE FIGMA VALUE THAT HAD TO MOVE FOR A TEXT ROLE.
  ///
  /// The design's `#6F747A` measures 4.13 / 3.92 / 3.70 / 3.40 on ground / card / raised /
  /// bright — it fails AA on every surface in the app, and the tightest case is tighter still
  /// (12px type on a 10% tint of itself over the raised surface, which is what a muted status
  /// chip and a lapsed-staff avatar are). This is that hue and saturation lifted in lightness
  /// by the minimum that clears 4.5:1 in all eight of those places:
  ///
  ///   #6F747A → #898D93, a delta of (+26, +25, +25) — 5.84 ground · 5.54 card · 5.23 raised ·
  ///   4.80 bright, and 4.57:1 at its worst on a chip of itself.
  ///
  /// #6F747A survives untouched as [outline], where 3:1 applies and it clears it everywhere.
  static const darkMuted = Color(0xFF898D93);

  /// A divider between rows already on the same surface. (= [outlineVariant]) 1.35:1.
  static const darkHairline = outlineVariant;

  /// A card's edge against the ground. (= [outlineVariant]) The design ships ONE hairline
  /// colour and every one of those jobs uses it — card borders, dividers and avatar discs are
  /// all `#292e33`. 1.42:1 on the ground, which is what does the separating now that nothing
  /// casts a shadow.
  static const darkCardBorder = outlineVariant;

  /// The only boundary a text field or an outlined button has, so WCAG 1.4.11 applies.
  /// (= [outline]) 3.70:1 on the design's own field fill.
  static const darkControlBorder = outline;

  // ═══ LIGHT — derived from [seed], never drawn ═══════════════════════════════
  // Every value below is `ColorScheme.fromSeed(seedColor: seed)` output, pinned as a const so
  // it can be used in const expressions. theme.dart calls fromSeed for real; the test asserts
  // these consts still match it, so they cannot quietly become hand-picked.

  /// Derived `surface` — the light canvas. `scaffoldBackgroundColor`.
  static const background = Color(0xFFFFF8F3);

  /// Derived `surfaceContainerLowest` — a card. In the light direction elevation runs TOWARD
  /// white, which is why the card is the lowest container rather than the highest.
  static const surface = Color(0xFFFFFFFF);

  /// Derived `surfaceContainerHigh` — a sheet.
  static const lightSheet = Color(0xFFF1E7D9);

  /// Derived `surfaceContainerHighest` — chips and the input fill.
  static const lightField = Color(0xFFEBE1D4);

  /// Derived `onSurface`. 17.11:1 on the card.
  static const textPrimary = Color(0xFF201B13);

  /// Derived `onSurfaceVariant`. 9.30:1 on the card, 7.19:1 on the field.
  static const textSecondary = Color(0xFF4E4639);

  /// Derived `primary`.
  ///
  /// `fromSeed`'s tonalSpot variant pulls most of the chroma out of #C9A96E and returns a
  /// dark bronze. It is legible (6.47:1 on the card, 5.01:1 on the field, white on it 6.47:1)
  /// and it is derived rather than guessed, which is the most that can be claimed for a
  /// scheme nobody designed. It is at least the right FAMILY now — the previous seed produced
  /// a grey-violet that shared nothing with the product. The recommendation stands:
  /// run the app `ThemeMode.dark`.
  static const lightPrimary = Color(0xFF79590C);

  /// (= [lightPrimary]) The name the existing call sites already use.
  static const indigo = lightPrimary;

  /// Derived `secondary`. 6.48:1 on the card. Kept under its old name for the call sites that
  /// mean "the other accent".
  static const softBlueInk = Color(0xFF6C5C3F);

  /// Derived `outline` — the light control border. 4.48:1 on the card, 3.47:1 on the field.
  static const controlBorder = Color(0xFF7F7667);

  /// Derived `outlineVariant` — a card's edge. 1.70:1 on the card.
  static const cardBorder = Color(0xFFD1C5B4);

  /// A divider. (= [lightField]) 1.29:1 on the card — quieter than [cardBorder], which is the
  /// whole reason the two are separate tokens.
  static const hairline = lightField;

  // ═══ SEMANTIC ══════════════════════════════════════════════════════════════

  // ── CANONICAL. Identity + graphics, both themes, never small text.
  //
  //    Each is the FIGMA tone of that meaning, held at its own hue and saturation and moved
  //    in lightness to the point that maximises its worst case across all eight surfaces of
  //    both themes. Worst measured 3.50:1, so every one clears WCAG 1.4.11 everywhere — the
  //    light input fill and the dark `surface-bright` included. Two of them land essentially
  //    on the design's own hex, which is the clearest evidence the derivation is honest.

  /// From the design's `#5FAE82`. 4.58:1 light card / 4.04:1 dark card, worst 3.50:1.
  static const success = Color(0xFF42825F);

  /// From the design's `#D5A64C`. 4.55:1 / 4.06:1, worst 3.52:1.
  static const warning = Color(0xFF976F23);

  /// From the design's `#C96B6B`. 4.56:1 / 4.05:1, worst 3.51:1.
  static const error = Color(0xFFC05353);

  /// From the design's `#5577AD` — the empty-state badge's blue, which needed a lightness
  /// nudge of one point to be optimal and is otherwise the file's own value. 4.55:1 / 4.07:1,
  /// worst 3.52:1.
  static const info = Color(0xFF5477AD);

  /// The canonical "muted" identity, for the same reason the four above exist: it gets passed
  /// as a `tone:` into widgets that paint it without a context. From the design's `#6F747A`,
  /// two points lighter. For muted TEXT use `context.tones.muted`. 4.53:1 / 4.08:1.
  static const textMuted = Color(0xFF71777D);

  // ── DARK-THEME TEXT. Reached via NivoraSemantics.
  //    Contract: AA plain on ground / card / raised / bright, AND AA as 12px type on a 10%
  //    tint of itself over any of the three content surfaces. Worst across the set: 4.56:1.

  /// The design's positive green, USED VERBATIM. (= [tertiary]) 6.92:1 on the card, 5.60:1 on
  /// a chip of itself.
  static const successDark = tertiary;

  /// The design's amber, USED VERBATIM. (= [secondary]) 8.26:1 on the card, 6.58:1 on a chip.
  static const warningDark = secondary;

  /// The design's red, lifted by (+3, +7, +7). (= [errorTone]) See [errorTone] for why.
  static const errorDark = errorTone;

  /// The design's `#5577AD`, lifted by (+28, +23, +14).
  ///
  /// This is the empty-state badge's blue (4:1577). At its own size and fill in the mockup it
  /// measures 4.03:1; this is the minimum lift along its own hue that clears 4.5:1 plain
  /// (5.83 ground · 5.53 card · 5.23 raised · 4.80 bright) and 4.56:1 on a chip of itself.
  static const infoDark = Color(0xFF718EBB);

  // ── LIGHT-THEME TEXT. Reached via NivoraSemantics.
  //    Same contract against the derived light surfaces. Each is the FIGMA hue darkened
  //    rather than a colour invented for the light theme, so the two themes are recognisably
  //    the same product. Worst across the set: 4.57:1.

  static const successInk = Color(0xFF33654A); // 6.77:1 on the card
  static const warningInk = Color(0xFF75561C); // 6.76:1
  static const errorInk = Color(0xFF9D3939); //   6.82:1
  static const infoInk = Color(0xFF415C88); //    6.75:1

  /// Muted text, light. The design's `#6F747A` darkened until it clears the same chip case.
  /// 6.71:1 on the card, 5.20:1 on the field, 4.57:1 on a chip of itself.
  static const mutedInk = Color(0xFF595C61);

  // ═══ DOMAIN — colour as wayfinding, the way Google's own apps use it ══════════
  //
  // The four semantic tones above say what STATE a thing is in. These three say what KIND of
  // thing it is: food, rooms, people. That is the other job colour does in a well-made app —
  // Gmail is red, Calendar is blue, Keep is yellow — and it is not decoration, because it is
  // consistent: the saffron icon at the head of a row means "this is the menu" on every screen
  // it appears on. See [NivoraDomain] for the mapping and the rule that keeps the two layers
  // apart.
  //
  // DERIVED BY THE SAME METHOD AS THE FOUR ABOVE, NOT PICKED. Each canonical is a hue of the
  // app's own muted register taken to the lightness that maximises its worst 3:1 case across
  // all eight surfaces of both themes (worst 3.50–3.52, the same figures success/warning/error
  // land on). Each ink is that canonical moved in lightness by the MINIMUM that clears 4.5:1
  // plain on every surface of its theme AND on a 10% chip of itself — the exact contract the
  // `...Dark` / `...Ink` sets above meet. The method was checked by re-deriving the shipped
  // inks from their Figma seeds: it lands on #708CBA for info (shipped #718EBB), #CB7171 for
  // error (shipped #CC7272) and #5FAE82 for success (exact). Every figure below is measured in
  // test/theme_contrast_test.dart.
  //
  // Money, complaints and notices did NOT get new tones. Money is `success` (a rent ledger's
  // natural colour is the paid one), complaints are `warning` (open work, which is also what
  // `complaintTone(open)` already paints), and notices are `info`. Three new hues, not seven,
  // because a palette a person can hold in their head is the whole point of wayfinding.

  /// FOOD — the weekly menu. Saffron, at hue 28°. Worst 3:1 case 3.52:1.
  static const food = Color(0xFFAB6528);

  /// ROOMS — floors, rooms, beds. Violet, at hue 262°. Worst 3:1 case 3.52:1.
  static const rooms = Color(0xFF8566BA);

  /// PEOPLE — residents, staff, roommates. Teal, at hue 178°. Worst 3:1 case 3.50:1.
  static const people = Color(0xFF35817E);

  /// [food] lifted for the dark theme. 4.70:1 plain, 4.55:1 on a chip of itself.
  static const foodDark = Color(0xFFC9772F);

  /// [rooms] lifted for the dark theme. 4.73:1 plain, 4.53:1 on a chip.
  static const roomsDark = Color(0xFF997FC5);

  /// [people] lifted for the dark theme. 4.73:1 plain, 4.53:1 on a chip.
  static const peopleDark = Color(0xFF3F9995);

  /// [food] darkened for the light theme. 5.16:1 plain, 4.51:1 on a chip.
  static const foodInk = Color(0xFF864F1F);

  /// [rooms] darkened for the light theme. 5.14:1 plain, 4.50:1 on a chip — at the bar, and
  /// the bar is the contract. The chip alpha is at its ceiling for every tone in this file.
  static const roomsInk = Color(0xFF6C4AA5);

  /// [people] darkened for the light theme. 5.19:1 plain, 4.56:1 on a chip.
  static const peopleInk = Color(0xFF296562);
}

// ─────────────────────────────────────────────────────────────────────────────
// SEMANTIC TONES — the theme-aware half of the palette.
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves a meaning to a colour that is legible *in the current theme*.
///
/// Registered on both themes, so `context.tones.error` is always the right red. See the
/// header of this file for why a single flat colour cannot do that job.
///
/// The chip recipe lives here too, and it is the design's own: the state badges on
/// `screen-empty-error-skeleton` are `bg-[rgba(<tone>,0.1)] border border-[<tone>]` with the
/// label in the tone at full strength. That is the tightest contrast case in the app — 12px
/// type on a 10% tint of itself — so putting the fill and border alphas in one place is what
/// stops a future chip being drawn at a plausible-looking alpha that fails.
@immutable
class NivoraSemantics extends ThemeExtension<NivoraSemantics> {
  const NivoraSemantics({
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
  static const light = NivoraSemantics(
    success: NivoraColors.successInk,
    warning: NivoraColors.warningInk,
    error: NivoraColors.errorInk,
    info: NivoraColors.infoInk,
    muted: NivoraColors.mutedInk,
    food: NivoraColors.foodInk,
    rooms: NivoraColors.roomsInk,
    people: NivoraColors.peopleInk,
    chipFillAlpha: _chipFill,
    chipBorderAlpha: _chipBorder,
  );

  /// AA as text on every surface of the dark theme, and on a chip of itself.
  static const dark = NivoraSemantics(
    success: NivoraColors.successDark,
    warning: NivoraColors.warningDark,
    error: NivoraColors.errorDark,
    info: NivoraColors.infoDark,
    muted: NivoraColors.darkMuted,
    food: NivoraColors.foodDark,
    rooms: NivoraColors.roomsDark,
    people: NivoraColors.peopleDark,
    chipFillAlpha: _chipFill,
    chipBorderAlpha: _chipBorder,
  );

  /// The design's own `rgba(<tone>, 0.1)` — 4:1576, 4:1589, 4:1600, 4:1531 all use it.
  ///
  /// IT IS ALL THE PALETTE CAN TAKE, and that is tighter than intuition says, because a tint of
  /// the tone moves the fill TOWARDS the text rather than away from it. Worst case across both
  /// ink sets, measured: 0.10 → 4.57:1 · 0.11 → 4.50:1, the last value that clears AA at all ·
  /// 0.12 → 4.44:1, a fail. The design's own 0.10 is used rather than the arithmetic ceiling,
  /// so the recipe has a point of headroom instead of sitting on the line. One number serves
  /// both themes, so a chip reads at the same weight whichever one is on.
  static const _chipFill = 0.10;

  /// FULL STRENGTH, which is the design's own badge (`border border-[#5577ad]`, no alpha).
  /// The tones in this palette are muted rather than saturated, so a 1px edge at full strength
  /// reads as a defined chip and not as a warning light.
  static const _chipBorder = 1.0;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color muted;

  /// The three DOMAIN inks — what kind of thing, not what state it is in. Same contract as the
  /// four above; see the domain block in [NivoraColors].
  final Color food;
  final Color rooms;
  final Color people;

  final double chipFillAlpha;
  final double chipBorderAlpha;

  /// Maps a CANONICAL colour ([NivoraColors.success] and friends) to this theme's legible text
  /// value, and passes anything else through unchanged.
  ///
  /// This exists for the plumbing case: a widget is handed a `tone:` chosen far away, often
  /// inside a context-free `switch` over an enum. The caller keeps naming the meaning; the
  /// paint site fixes the theme.
  Color resolve(Color tone) {
    if (tone == NivoraColors.success) return success;
    if (tone == NivoraColors.warning) return warning;
    if (tone == NivoraColors.error) return error;
    if (tone == NivoraColors.info) return info;
    if (tone == NivoraColors.textMuted) return muted;
    if (tone == NivoraColors.food) return food;
    if (tone == NivoraColors.rooms) return rooms;
    if (tone == NivoraColors.people) return people;
    return tone;
  }

  /// The fill behind a status chip, given either a canonical or a resolved tone.
  Color chipFill(Color tone) => resolve(tone).withValues(alpha: chipFillAlpha);

  /// The hairline around a status chip.
  Color chipBorder(Color tone) => resolve(tone).withValues(alpha: chipBorderAlpha);

  /// The alpha a whole SURFACE takes to carry a meaning, rather than a chip inside it.
  ///
  /// IT IS THE SAME NUMBER AS [chipFillAlpha], deliberately and not by coincidence. A tinted
  /// card and a status chip are the same gesture at two scales — "this thing is overdue" — and
  /// giving the card its own alpha would let the two drift until a row and the card it sits in
  /// were different strengths of the same meaning. One number, one weight of colour.
  ///
  /// ── WHAT IT MEASURES, AND THE ONE RULE THAT FALLS OUT OF IT ─────────────────────────────
  ///
  /// Measured over the CONTENT surfaces only — card `#111417` and raised `#171A1E` on dark,
  /// `#FFFFFF` on light — across all five tones. The two themes do NOT behave the same here,
  /// and the difference is the whole reason this comment is long:
  ///
  /// |                              | dark     | light    |
  /// |------------------------------|----------|----------|
  /// | body / secondary text on it  | 6.02:1   | 7.95:1   |
  /// | the tone itself, as text     | 4.56:1   | 5.83:1   |
  /// | a CHIP of the same tone      | **3.98** | 5.03:1   |
  ///
  /// A dark tint moves the ground TOWARD its own light text; a light tint moves it AWAY from
  /// its dark text. So the light theme has room the dark theme does not, and every rule below
  /// is set by the dark column — one widget serves both themes, and it cannot be legible in
  /// only one of them.
  ///
  /// **A STATUS CHIP MAY NOT SIT ON A SURFACE TINTED WITH ITS OWN TONE.** The chip's fill is
  /// itself a tint of the tone, so over a ground that is already one it lands twice as far
  /// toward its own label: **3.98:1 in the dark theme**, and no value of this constant rescues
  /// it — the ratio is already below AA at 0.06. (In the light theme the same stack measures
  /// 5.03:1 and would have been fine. It is still not drawn, because a widget that grew a chip
  /// on one theme and not the other would be two designs.) So a tinted surface does not wear a
  /// chip: the GROUND is the chip, and the status word sits on it in the tone at full strength,
  /// which is the 4.56:1 row above. [ToneSurface] is the widget that enforces this and
  /// [StatusWord] is the label it enforces it with.
  ///
  /// The [Dark.bright] rung is excluded on purpose — that is the input fill, and a tinted text
  /// field is a field that looks like a state.
  ///
  /// ── THIS IS NOT A NEW COLOUR. IT IS THE DESIGN'S OWN CONTAINER RUNG ─────────────────────
  ///
  /// The strongest evidence that this recipe is the right one is that it was already in the
  /// file. Composite each dark tone over the card `#111417` at this alpha and the results are,
  /// byte for byte, the container colours the Figma designer picked by hand:
  ///
  ///   success `#5FAE82` → **#192322** = [NivoraColors.tertiaryContainer]
  ///   warning `#D5A64C` → **#25231C** = [NivoraColors.secondaryContainer]
  ///   error   `#CC7272` → **#241D20** = [NivoraColors.errorContainer]
  ///
  /// Three for three, at the 8-bit precision that reaches a display. So a tinted card is not a
  /// fourth palette and not a new surface: it is the container colour this design system
  /// already shipped, reached by formula instead of by hand — which is what lets it extend to
  /// the two tones (info, muted) that never got a container drawn for them. `theme_contrast_test.dart` asserts the three
  /// identities so a nudge to any tone has to answer for the containers as well.
  static const surfaceTintAlpha = _chipFill;

  /// An OPAQUE fill: this theme's [tone] laid over [base] at [surfaceTintAlpha].
  ///
  /// Opaque rather than translucent so the result does not depend on what happens to be behind
  /// the card. [base] must be the fill the surface would otherwise have painted — i.e.
  /// `GlassWeight.surfaceOf(scheme)` — because that is the set the ratios above were measured
  /// against.
  Color tintedSurface(Color tone, Color base) =>
      Color.alphaBlend(resolve(tone).withValues(alpha: surfaceTintAlpha), base);

  @override
  NivoraSemantics copyWith({
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
    return NivoraSemantics(
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
  NivoraSemantics lerp(ThemeExtension<NivoraSemantics>? other, double t) {
    if (other is! NivoraSemantics) return this;
    return NivoraSemantics(
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
/// The fallback is the DARK set. It only fires for a widget pumped without a Nivora theme,
/// and this is a dark-first app: guessing light there would put a #33654A green on a
/// near-black card at 1.5:1.
extension NivoraTonesX on BuildContext {
  NivoraSemantics get tones =>
      Theme.of(this).extension<NivoraSemantics>() ?? NivoraSemantics.dark;
}

// ─────────────────────────────────────────────────────────────────────────────
// DOMAIN — what kind of thing this is.
// ─────────────────────────────────────────────────────────────────────────────

/// The areas of the product, each with the one colour that identifies it everywhere.
///
/// ── THE RULE THAT KEEPS THIS FROM BECOMING A RAINBOW ─────────────────────────────────────
///
/// **Domain colour lives on icons, actions and avatars. Status colour lives on surfaces and
/// figures.** They occupy different objects, so they never compete on the same pixel:
///
///   * the saffron [DomainIcon] at the head of a menu row says WHAT this is, on every screen,
///     always; the amber [StatusPill] beside a complaint says what STATE it is in, today;
///   * a rent card that is unpaid is a red [ToneSurface], and every coloured thing on it —
///     including the wallet glyph in its corner — takes that same red. STATUS WINS THE WHOLE
///     CARD. The money-domain wallet appears on that card only in the one state that has no
///     status to state: the "No rent record yet" face;
///   * a screen where everything is tinted has said nothing, so a domain tint on a SURFACE
///     ([DomainCard]) is allowed at most once per screen, and never on a card that carries a
///     status. A control is not an exception dressed up: [DomainButton] puts its colour in the
///     glyph and the label and leaves its ground neutral, for exactly this reason.
///
/// This is how Google's own apps use colour — Gmail is red, Calendar is blue, and neither means
/// "error" or "info" — and it is compatible with this design's older rule that colour must
/// mean something. It means "this is the menu".
///
/// Every colour here is a CANONICAL tone from [NivoraColors]; resolve it at the paint site with
/// `context.tones.resolve(domain.tone)` like any other, or let [DomainIcon] and friends do it.
enum NivoraDomain {
  /// Rent, fees, payments, expenses, subscriptions. The ledger's natural colour is the paid one.
  money(NivoraColors.success, Icons.account_balance_wallet_rounded),

  /// Floors, rooms, beds, the building. Also a hostel as an object.
  rooms(NivoraColors.rooms, Icons.meeting_room_rounded),

  /// Residents, staff, roommates, guardians, visitors, leaves.
  people(NivoraColors.people, Icons.people_alt_rounded),

  /// Complaints and tasks — open work. Amber, which is also what an OPEN complaint's own
  /// status pill paints, so an open row and its icon agree rather than argue.
  complaints(NivoraColors.warning, Icons.report_problem_rounded),

  /// Notices and announcements — "here is something you should know".
  notices(NivoraColors.info, Icons.campaign_rounded),

  /// The weekly menu.
  food(NivoraColors.food, Icons.restaurant_rounded),

  /// Security, the account, the platform itself. The brand's own gold — passed through
  /// [NivoraSemantics.resolve] unchanged, because it is a scheme colour and not a semantic one.
  security(NivoraColors.primary, Icons.shield_rounded);

  const NivoraDomain(this.tone, this.icon);

  /// The canonical colour. Resolve it for the theme before painting text with it.
  final Color tone;

  /// The glyph that stands for the whole domain, for a caller with nothing more specific.
  final IconData icon;
}

// ─────────────────────────────────────────────────────────────────────────────
// SPACING — the design's scale, which is already a 4dp rhythm.
// ─────────────────────────────────────────────────────────────────────────────

/// The Figma frames pad screens and cards at 16, gap 20 between sections, and 24 / 16 / 12 /
/// 8 / 6 / 4 / 2 within them. Every one of those is a step this scale already had, so both the
/// names and the values are unchanged:
///
///   [xxs] 4 · [xs] 8 · [sm] 12 · [md] 16 = card and screen padding · [lg] 20 = section gap ·
///   [xl] 24 = the signin form's block gap
///
/// [xxl], [xxxl] and [huge] are off the design's list but on its rhythm; they exist because
/// 32/40/48dp blocks are needed and inventing them at call sites is what this file prevents.
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
// RADIUS — the design's four steps.
// ─────────────────────────────────────────────────────────────────────────────

/// `14 screen · 12 card · 8 small card / button / icon button · 4 badge`, which is what
/// `design-figma/DESIGN-SYSTEM.md` records and what the frames overwhelmingly use.
///
/// The frames also contain 10, 6, 3 and 2 in a handful of places — the KPI cards are
/// `rounded-[10px]`, the retry and renew buttons are `rounded-[6px]`, a meter track is 3 and
/// the home indicator is 2. Those are strays rather than a second vocabulary: the same
/// element is drawn at 8 elsewhere in the same file, and half of them are pill shapes whose
/// radius is just half their height. Do not add steps to match them.
abstract final class Radii {
  /// A badge — `rounded-[4px]` on every state badge (4:1576, 4:1589, 4:1600) and the
  /// notification dot. Something too small to have a corner in the usual sense.
  static const tiny = 4.0;

  /// Buttons, inputs, icon buttons, inner rows, small cards.
  static const control = 8.0;

  /// Cards and list groups — the empty / error / skeleton cards are `rounded-[12px]`.
  static const card = 12.0;

  /// The largest step in the file: the screen shell itself. Large panels.
  static const surface = 14.0;

  /// Bottom sheets and modals. A sheet is a screen-sized surface, so it takes the screen's own
  /// corner rather than a card's.
  static const sheet = 14.0;

  /// Only for things genuinely capsule-shaped that never wrap to a second line: a progress
  /// track, a drag handle, an avatar, the FAB. A status pill uses [control] — a capsule that
  /// wraps looks broken, and status wording is not under our control.
  static const pill = 999.0;

  static const rTiny = BorderRadius.all(Radius.circular(tiny));
  static const rControl = BorderRadius.all(Radius.circular(control));
  static const rCard = BorderRadius.all(Radius.circular(card));
  static const rSheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
  static const rPill = BorderRadius.all(Radius.circular(pill));
}

// ─────────────────────────────────────────────────────────────────────────────
// ICONS + STROKES
// ─────────────────────────────────────────────────────────────────────────────

/// The design draws small. Its glyphs are 8 (status dot), 10 (chevron), 12 (activity icon),
/// 14 (row chevron), 16 (bell, alert triangle, status bar) and 20 at the very largest — a
/// header icon in this file is 16px inside a 32px button, not 24px inside a 40px one.
///
/// These sizes moved DOWN from the previous scale (14/16/18/22/32) to match. A glyph is not a
/// tap target; the 48dp minimum lives on the control, not on the icon inside it.
abstract final class IconSize {
  static const xs = 12.0; // inside a chip, an activity disc
  static const sm = 14.0; // beside a label, a row chevron
  static const md = 16.0; // list rows, section headings, the header's own icons
  static const lg = 20.0; // app bar, bottom nav

  /// The single glyph over an empty or failed section. One size for both: an empty list and a
  /// broken one are the same weight of event.
  static const xl = 32.0;
}

/// The generated artwork that replaces the glyph on a first-run empty state.
///
/// ONE SIZE, AND IT IS THE ONLY ONE. 160 is what the art was drawn to be read at, and the
/// assets ship at 480px so the same file is exact at 3x and oversampled below it. Growing this
/// number does not make the illustration better, it makes it soft.
///
/// It is deliberately much larger than [IconSize.xl]'s 32dp glyph. These states are the FIRST
/// screens a new PG owner sees, before any data exists, and a 56dp outlined square is a
/// placeholder where the product should be introducing itself.
abstract final class ArtSize {
  static const emptyState = 160.0;
}

/// Every border in the app is one physical hairline. Weight comes from colour, not width.
abstract final class Strokes {
  static const hairline = 1.0;

  /// The empty-state glyph's outline — `border-[1.5px]` on 4:1579. An illustration, not a
  /// border: it is the one stroke in the design allowed to be heavier than a hairline without
  /// meaning "focused".
  static const glyph = 1.5;

  static const focus = 1.6; // the only place a CONTROL's border is allowed to thicken

  /// The coloured strip down a card's leading edge — the mockups' `border-l-4`.
  ///
  /// Already the width [OutlineCard] drew its rail at; named here because a second widget
  /// ([ToneSurface]) now draws the same strip, and two call sites reaching for `Space.xxs` and
  /// meaning "rail" is how the two quietly stop matching.
  ///
  /// A rail is always the tone at FULL strength. It is a graphic and not text, and every
  /// canonical tone is already measured at worst 3.50:1 against every surface of both themes,
  /// so the rail clears WCAG 1.4.11 wherever it is drawn. It is also never the only carrier of
  /// its meaning — the row it edges still spells the status out in a word — so a resident who
  /// cannot separate the hues loses nothing.
  static const rail = Space.xxs;
}

// ─────────────────────────────────────────────────────────────────────────────
// OPACITY
// ─────────────────────────────────────────────────────────────────────────────

/// The two places the design dims something instead of recolouring it.
abstract final class Dim {
  /// `screen-subscription-expired` puts the whole body inside a container at `opacity-45`
  /// (4:1539) while the banner above it stays at full strength. That is how the design says
  /// "you can look at this, you cannot use it" — one number over the whole subtree rather than
  /// a disabled variant of every control in it.
  static const readOnly = 0.45;

  /// The floor of a skeleton's pulse. It breathes between here and opaque.
  static const skeletonPulse = 0.45;
}

// ─────────────────────────────────────────────────────────────────────────────
// SURFACE WEIGHT — an elevation ladder, and NOT a blur.
// ─────────────────────────────────────────────────────────────────────────────

/// Three weights of raised surface. The name is historical: these panes used to blur.
///
/// ── THERE IS NO BLUR IN THIS APP ─────────────────────────────────────────────────────────
///
/// `BackdropFilter` is the most expensive thing this app can draw, the product owner's own
/// phone reported "stuck, lag", and release builds have disabled it unconditionally since the
/// commit "Release builds never blur". The Figma design does not ask for any: every surface in
/// every frame is an opaque fill with a 1px `#292e33` hairline. Do not reintroduce it — not
/// behind a flag, not "just for the sheet".
///
/// ── WHAT EACH WEIGHT IS ──────────────────────────────────────────────────────────────────
///
/// The design ships three surfaces and this is those three, in the dark direction where
/// elevation runs LIGHTER as it rises. [thick] and [regular] are the same fill because the
/// design has nothing above its raised surface: a sheet is separated from the bar behind it
/// by the modal scrim and [Shadows.level3], which is a stronger cue than one more rung of
/// near-black would be. In the light theme M3 inverts the whole idea — elevation runs toward
/// white and the card is already white — so all three resolve to the same surface there and
/// the shadow does the separating. [surfaceOf] is the only place that decision is made.
enum GlassWeight {
  /// A resting card. `#111417` — the design's own card.
  thin,

  /// A bar, a header, or a card that sits on top of another surface. `#171A1E` — the design's
  /// raised fill, which is what its icon buttons, inputs and state cards paint.
  regular,

  /// A sheet or modal. (= [regular])
  thick;

  /// The surface this weight paints in the given scheme.
  Color surfaceOf(ColorScheme scheme) {
    // Light elevates by shadow, not by colour: the card is already the lightest surface there,
    // so stepping "up" would mean stepping toward grey.
    if (scheme.brightness == Brightness.light) return scheme.surface;
    return switch (this) {
      GlassWeight.thin => scheme.surfaceContainerLow,
      GlassWeight.regular => scheme.surfaceContainer,
      GlassWeight.thick => scheme.surfaceContainerHigh,
    };
  }

  /// Alpha of the INK hairline that edges a pane in the LIGHT theme, over the pane itself:
  /// 1.39:1, the same visual register as [NivoraColors.cardBorder] (1.70:1). Weight-independent
  /// on purpose — the edge says "this is a pane", and that sentence does not get louder for a
  /// sheet.
  ///
  /// There is no dark counterpart any more. The dark theme's pane edge is the design's own
  /// hairline `#292E33` (1.35:1 on the card), not a white alpha: Figma ships one border colour
  /// and uses it on every card, divider and disc in the file.
  static const lightEdge = 0.16;
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

  /// The delay between one item of a list entering and the next.
  ///
  /// Small on purpose. At 40ms a six-row list is fully in at 200ms plus the item's own [base],
  /// which reads as one movement with a direction rather than as rows arriving one at a time.
  /// Anything longer and the last row of a long list is still animating after the reader has
  /// got there, which is a screen that feels slow rather than alive.
  ///
  /// ── THE RULES A STAGGER HERE MUST KEEP ──────────────────────────────────────────────────
  ///
  ///  * It runs ONCE, on first build, and never again. Nothing in this app animates
  ///    continuously; a list that re-plays its entrance on every rebuild is a list that
  ///    flickers whenever a provider refreshes.
  ///  * It never delays the first frame. The entrance is an opacity and a small offset on
  ///    content that is already laid out and already hit-testable.
  ///  * It is capped — see [staggerCap]. A 200-row list must not compute a ten-second ramp.
  static const stagger = Duration(milliseconds: 40);

  /// How many items still get a stagger step before the delay stops growing.
  ///
  /// Beyond this the entrance is simply [base] with the last delay. Only the first screenful
  /// is ever watched arriving, and an off-screen row that is still waiting its turn is a row
  /// that fades in under the reader's thumb as they scroll to it.
  static const staggerCap = 8;

  /// How long an inline confirmation stays on the control that produced it — the "Copied" that
  /// replaces a copy button's label. Not an animation: long enough to be read, short enough
  /// that a second tap reads as a second confirmation.
  static const confirmed = Duration(milliseconds: 1600);

  /// How long a snackbar carrying a FAILURE stays up. A reading budget, not an animation.
  /// Material's default 4s is sized for "Saved"; the sentences this app shows on a refusal are
  /// a full line ("Bed 3 is already occupied. Choose a free bed.") and a warden reads them
  /// while talking to somebody.
  static const readMessage = Duration(seconds: 5);

  /// VESTIGIAL. Nothing in the app blurs any more — see [GlassWeight] — so setting this
  /// changes nothing that gets drawn. It survives only because `main.dart` writes to it and
  /// that file is outside this change; removing the field would stop the app compiling.
  /// Whoever next touches `main.dart` should delete `_decideGlassBudget` and this together.
  static bool glassFallback = false;
}

// ─────────────────────────────────────────────────────────────────────────────
// ELEVATION
// ─────────────────────────────────────────────────────────────────────────────

/// THE DESIGN HAS NO SHADOWS. Not one of the nineteen Figma frames carries a `box-shadow`;
/// separation is done entirely by the `#292E33` hairline, which is 1.42:1 against the ground
/// where the card itself is only 1.05:1. That is why [level1] and [level2] are both empty: a
/// resting card gets an edge, not a smear, and a drop shadow under a full-bleed bar is the
/// cheapest-looking thing in mobile design.
///
/// The one exception is a surface that is genuinely FLOATING over a scrimmed page. Nothing in
/// the file draws one, so [level3] is the app's own — black rather than tinted, because a
/// coloured shadow over #0B0D0F is invisible.
abstract final class Shadows {
  /// Flat against the ground. The design's default, and now the card's too.
  static const level1 = <BoxShadow>[];

  /// A resting card. (= [level1]) Kept as a separate name because the call sites that pass it
  /// mean "this is a card", and that sentence should survive even though it currently costs
  /// nothing to draw.
  static const level2 = <BoxShadow>[];

  /// Something genuinely floating over a barrier: a sheet, a modal, a menu. A large soft
  /// shadow plus a tight contact shadow so the edge does not float free of it.
  static const level3 = <BoxShadow>[
    BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// The FAB's halo — [NivoraColors.primary] at 30%. The app's one flourish beyond the design,
  /// kept because a floating action button with no lift on a flat near-black page reads as a
  /// sticker. Sparingly: one per screen, on the one control that is the screen's purpose.
  static const glow = <BoxShadow>[
    BoxShadow(color: Color(0x4DC9A96E), blurRadius: 20),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// BREAKPOINTS — phones are the design target; tablets get more columns, not bigger text.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class Breakpoints {
  static const compact = 360.0; // smallest phone still supported
  static const medium = 600.0; // large phone / small tablet

  /// Where a phone layout stops being the right one: container padding grows and the bottom
  /// nav is replaced by links in the header.
  static const expanded = 768.0;
}
