# NIVORA UI/UX — the design system, extracted from the real Stitch project

Source: Stitch project `2206751849911882558` ("NIVORA UI/UX"), 24 screens, fetched 2026-08-30.
Ground truth is `owner-dashboard.html`'s `tailwind.config` block — every value below is copied
from it verbatim, not inferred from a screenshot.

**This supersedes `design-exports/` entirely.** That folder holds an OLDER Stitch project
(`15365392661227774313`) with a completely different look — warm ivory canvas, navy ink, teal.
A previous automated pass restyled the app from it by mistake and was reverted. If you are
picking up this work: `design-exports/` is not the design. This folder is.

## The headline: it is a DARK-FIRST app

The design ships one scheme and it is dark. Near-black navy ground, violet primary, mint for
positive, coral for error. The app it replaces was light-first with an indigo primary, so this
is a change of product identity, not a re-tint.

## Colour — Material 3 dark scheme, verbatim

| Role | Hex | Where it shows |
|---|---|---|
| `background` / `surface` / `surface-dim` | `#0b1326` | the page ground |
| `surface-container-lowest` | `#060e20` | the deepest wells |
| `surface-container-low` | `#131b2e` | cards (see the glass note) |
| `surface-container` | `#171f33` | raised cards |
| `surface-container-high` | `#222a3d` | headers, sheets |
| `surface-container-highest` / `surface-variant` | `#2d3449` | chips, inputs |
| `surface-bright` | `#31394d` | the brightest surface |
| `primary` | `#d0bcff` | active nav, links, emphasis |
| `primary-container` | `#a078ff` | filled buttons, FAB |
| `on-primary` | `#3c0091` | text on a filled button |
| `on-primary-container` | `#340080` | |
| `secondary` | `#dbb8ff` | |
| `secondary-container` | `#573878` | |
| `tertiary` | `#4edea3` | POSITIVE: paid, occupied, resolved |
| `tertiary-container` | `#00a572` | |
| `error` | `#ffb4ab` | overdue, maintenance, failures |
| `error-container` | `#93000a` | |
| `on-background` / `on-surface` / `inverse-surface` | `#dae2fd` | body text |
| `on-surface-variant` | `#cbc3d7` | secondary text |
| `outline` | `#958ea0` | borders |
| `outline-variant` | `#494454` | hairlines |
| `inverse-primary` | `#6d3bd7` | **the light-theme primary** — see below |

### Deriving a light theme

The design has no light scheme. `inverse-primary` `#6d3bd7` is, by Material 3 convention, the
light theme's primary generated from the same source colour — so a coherent light scheme can be
built with `ColorScheme.fromSeed(seedColor: Color(0xFF6D3BD7), brightness: light)` rather than
invented. Do NOT hand-pick light colours; derive them, then verify contrast by measurement.

## Type

Two families:

- **Plus Jakarta Sans** — display, headline, title, body
- **Inter** — `label-caps` only (the small uppercase labels)

| Token | Size / line / weight | Notes |
|---|---|---|
| `display-lg` | 48 / 56 / 700, tracking −0.02em | the single hero figure |
| `headline-lg` | 32 / 40 / 700, tracking −0.01em | |
| `headline-lg-mobile` | 28 / 36 / 700 | use this on phones |
| `title-md` | 20 / 28 / 600 | section titles |
| `body-lg` | 16 / 24 / 400 | |
| `body-sm` | 14 / 20 / 400 | the body default |
| `label-caps` | 12 / 16 / 600, tracking +0.05em | **Inter**, uppercase |

Inter is already bundled. **Plus Jakarta Sans must be bundled too** — this app sets
`GoogleFonts.config.allowRuntimeFetching = false` deliberately, so a font that is not in
`google_fonts/` will throw in debug rather than silently download in production.

## Shape and spacing

Radius: `DEFAULT` 4px · `lg` 8px · `xl` 12px · `full` pill.
Spacing: base 8 · stack-sm 12 · gutter 16 · stack-md 24 · stack-lg 40 · container padding 20 (mobile).

## The glass card, and why it must not use blur

The design defines:

```css
.glass-card {
  background-color: rgba(23, 31, 51, 0.6);   /* surface-container at 60% */
  backdrop-filter: blur(16px);
  border: 1px solid rgba(255,255,255,0.05);
  box-shadow: 0 8px 32px rgba(0,0,0,0.3);
}
```

**Do not implement the blur.** A field report from the product owner's phone was "stuck, lag",
and `BackdropFilter` is the most expensive thing this app can draw; release builds now disable
it unconditionally (see `main.dart`, commit "Release builds never blur").

The look survives without it. Compositing `rgba(23,31,51,0.6)` over the `#0b1326` ground gives
**`#121a2e`** — which is, to within one point per channel, the design's own
`surface-container-low` `#131b2e`. So: paint the card as a FLAT `surface-container-low`, keep
the hairline border and the shadow, and the result is visually the same card at zero GPU cost.
That is not a compromise; it is the same pixel.

`glow-text` (a soft primary text-shadow) and `gradient-text` (primary→secondary) are cheap and
may be used sparingly for the hero figure.

## What the screenshots are and are not

All 24 PNGs are layout references. **Every name, figure and date in them is invented** — "Rahul
Sharma", "Nivora Heights PG", "₹8,500", "150 beds", "5th Oct 2024". None of it may reach a real
screen. Every value the app displays comes from a provider reading the real database. If a
mockup shows a widget whose data does not exist in the schema, skip the widget and say so.
