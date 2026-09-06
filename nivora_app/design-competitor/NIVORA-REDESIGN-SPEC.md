# NIVORA redesign — the decisions

Synthesised from two surviving panel proposals, **NEEL** (colour) and **SEAM** (shape), after
every contrast claim in both was independently recomputed from relative luminance. All 15
spot-checks matched to two decimals; the one knife-edge claim (`foodInk`) was checked twice and
is real. The judges were killed by a session limit, so the verification below is mine.

## 1. The thesis

Gold cannot be NIVORA's brand colour, and that is arithmetic rather than taste. `#C9A96E` on
white measures **2.24:1**. To clear 4.5:1 on white a gold has to be darkened to about L 0.30,
and a gold at L 0.30 is a brown — which is exactly what `ColorScheme.fromSeed(#C9A96E)`
returned (`#79590C`), and exactly the trap the competitor fell into with peach `#f1c4a2` over
brown `#541000`. Blue and violet hold their identity across the whole lightness range a
dual-theme app needs; gold does not.

So the brand becomes **indigo — *neel*** — and NIVORA already owns it: `NivoraColors.rooms`
`#8566BA`, hue 262°, the colour `AuroraField` already paints behind the sign-in screen. Gold
is not discarded; it is **re-scoped to the metal**: the wordmark, the splash, the BeamCard
comet, and the subscription accent.

## 2. Two live defects this fixes

Both were found while verifying, both are in the shipping app, and both are light-mode only —
which is why they were never noticed.

1. **`NivoraDomain.security` paints gold at 2.24:1 on a white card.** `resolve()`
   (`tokens.dart:579-589`) has no branch for it, so it passes through unchanged. It is the
   Home/Dashboard tab domain for three of five roles (`role_shell.dart:68,72,75`) plus the
   manager and super-admin fallbacks. `theme_contrast_test.dart:751-756` explicitly blesses
   this — the test is codifying the bug.
2. **Light mode has no depth at all.** `GlassWeight.surfaceOf` (`tokens.dart:957`) short-circuits
   to `scheme.surface` for light, with the comment *"Light elevates by shadow, not by colour"* —
   but `Shadows.level1` and `level2` are both empty lists. Card, bar and sheet are all
   `#FFFFFF`. It gets neither.

## 3. The palette

Every ratio below was recomputed, not copied.

### Light — redrawn, no longer `fromSeed` output

| token | was | becomes | role | measured |
|---|---|---|---|---|
| `background` | `#FFF8F3` | `#EEF0F8` | canvas | L 0.8727 |
| `surface` | `#FFFFFF` | unchanged | card | — |
| `lightSheet` | `#F1E7D9` | `#F7F8FC` | sheet, header, nav bar | L 0.9394 |
| `lightField` | `#EBE1D4` | `#DFE2EE` | input fill, chips | L 0.7625 vs old 0.7627 |
| `textPrimary` | `#201B13` | `#14161D` | onSurface | 18.07 card · 13.98 field |
| `textSecondary` | `#4E4639` | `#434857` | onSurfaceVariant | 9.12 card · 7.06 field |
| `lightPrimary` | `#79590C` | `#6C4AA5` | light primary (= existing `roomsInk`) | 6.64 card · 5.14 field · white on it 6.64 |
| `softBlueInk` → `slateInk` | `#6C5C3F` | `#464E6B` | light secondary | 8.20 card · 6.34 field |
| `controlBorder` | `#7F7667` | `#767B8C` | control edge (1.4.11) | worst 3.26 |
| `cardBorder` | `#D1C5B4` | `#CDD1E0` | card edge | 1.52 on white |
| `hairline` | `= lightField` | `#E4E7F1` | row divider | 1.24 on white |
| `foodInk` | `#864F1F` | `#854F1F` | food, light text | chip 4.4986 → 4.5221 |

`lightField` was chosen to land within 0.0002 of the old field's luminance so the chip
arithmetic does not move. That is why the other seven semantic inks survive untouched.

**Full light matrix, verified:** worst plain **5.14:1** (`brandInk` on field), worst 10% chip
**4.52:1**, `controlBorder` worst **3.26:1**. Bars are 4.5 and 3.0.

### Both themes

| token | hex | role |
|---|---|---|
| `brandDeep` *(new)* | `#4D2896` | the hero brow, the four onboarding grounds, the light filled button. Identical in both themes. |
| `brand` (= `rooms`) | `#8566BA` | canonical, context-free. L 0.1803, inside the dual-theme window. |
| `brandInk` (= `roomsInk`) | `#6C4AA5` | light text |
| `brandDark` (= `roomsDark`) | `#997FC5` | dark primary |
| `gold` (was `primary`) | `#C9A96E` | **the metal.** Wordmark, splash, beam, subscription. Never light-mode text. |

On `brandDeep`: cream 9.20:1, white 10.20:1, gold 4.56:1 — so even gold *text* passes on it.

### Dark — one substantive change

`scheme.primary` moves `#C9A96E` → `#997FC5`. `onPrimary` stays the ground at 5.74:1 (was
8.70). This repaints the FAB, focus border, text buttons and nav indicator through the 81
`colorScheme.primary` call sites — coherently, in one edit. Everything else in dark stays
Figma-verbatim: all four surfaces, the cream `primaryContainer`, amber, green, error, all inks,
`#292E33`, and all three container tints.

## 4. Shape — from SEAM

The competitor's cards are `cardElevation=0dp` at `cardCornerRadius=20dp` in all 282 layouts.
**NIVORA's no-shadow rule stands.** What changes is the corner and the ground.

- **Radii**: `control` 8→12, `card` 12→16, `surface`/`sheet` 14→20. Three lines in
  `tokens.dart`, reaching 145 call sites. Only 2 hardcoded radius literals exist in `lib/`.
- **The brow**: a full-bleed `brandDeep` block whose bottom edge is a convex curve, with the
  first card riding the seam.

  **BUILT DIFFERENTLY FROM THIS PLAN, and the plan was wrong.** The intent was one mount point
  behind the whole shell at `role_shell.dart:109`. Rendering the owner's dashboard to a PNG
  killed that twice: a transparent header stops being a header (the list scrolled up *through*
  it), and the body's own greeting — theme ink, first thing in the scroll view — landed on the
  indigo as near-black. Whitening the greeting only moves the bug, because it scrolls off the
  band.

  So on a **scrolling** screen the header IS the brow (`GlassHeader(onBrow: true)`): a fixed,
  non-scrolling object exactly as tall as the bar plus its curve, and the only thing that ever
  crosses the colour is a card, which brings its own opaque fill. The full-height `BrandBrow`
  survives for **sign-in**, where nothing scrolls under it.

  Widgets that name their own colour cannot inherit the header's white, so `BrowScope` — an
  InheritedWidget the header provides — is read by `NivoraWordmark`, `AccountAvatar`,
  `SaBrandDot` and warden's `ToneDot`. Reading a scope rather than taking a flag, because four
  mastheads draw these and a flag is three chances to forget.
- **Inputs**: taller, and STILL FILLED — a deliberate half-adoption. The teardown put the whole
  difference down to generosity, but with both rendered side by side the fill is not the
  problem: Figma 4:77 specifies `bg-[#171a1e]`, and a filled field on a dark card is more
  legible than an outline. Padding 16 → 20 lands it near 58dp against their ~64dp.
- **CTA**: a pill. Three things agree and rarely do — Material 3's default button shape is a
  stadium, the competitor's CTA is fully rounded, and `Radii.pill`'s own rule ("only for things
  genuinely capsule-shaped that never wrap") is satisfied by a full-width one-word button.
- **Onboarding**: four full-bleed pages, in `features/onboarding/`. There was none at all —
  `PageView` appeared twice in the whole tree and both were comments saying the shells
  deliberately avoid one.

  Grounds are the deep form of the domain tone that owns each feature, so the sequence is
  NIVORA's own vocabulary rather than the competitor's four unrelated accents: `#4D2896` the
  brand (white 10.20:1), `#0F5F5B` people (7.48), `#1B5E43` money (7.70), `#8A3D12` the daily
  run of the place (7.62).

  Gated by a zero-byte marker in the application support directory via `path_provider`, which
  is already a direct dependency — `shared_preferences` is not, and reaching through
  supabase_flutter's copy of it to store our own state breaks on somebody else's minor bump.
  It wraps the login route rather than becoming a phase in `resolveRedirect`, because that
  function is pure and its every-phase-against-every-route matrix test cannot see a disk read.
  It never shows a spinner: the child renders until the marker resolves.

## 5. What is deliberately NOT changing

- **No shadows.** The competitor proves they are not the differentiator.
- **No blur.** `glass.dart:23-27` bans it on a field report of real-hardware lag.
- **Inter stays.** Quicksand reads consumer-cute; Inter's tabular figures matter for rent.
- **Motion stays 150–350ms.** The competitor's 500ms scale-in is sluggish, not premium.
- **The dark surfaces stay Figma-verbatim.**
