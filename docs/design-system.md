# Design system

The visual language is Apple's, expressed in Tailwind. Not "some blur classes" — an
actual system: a semantic colour hierarchy, layered translucent materials, an optical
type ramp, spring motion, and a radius/elevation ladder. Everything lives in two files:

| File | Holds |
| --- | --- |
| `app/globals.css` | The token values, as CSS custom properties. Theme, contrast and transparency variants. The material and surface classes. |
| `tailwind.config.ts` | The Tailwind surface over those tokens — which utility name reaches which variable. |

Nothing else needs to change to re-theme the product.

---

## 0. The one rule

**Tokens are additive. No token was renamed or removed.**

Every brand token — `ivory`, `navy`, `teal`, `sage`, `sand`, `red`, `charcoal`, `muted`,
`line`, `glass-*`, `rounded-card`, `rounded-control`, `shadow-glass`, `text-stat`,
`.glass-card`, `.label-caps` — still exists and still resolves to the colour it always
did. The hexes moved *behind* CSS custom properties, which is what buys us the dark
theme and the Increase-Contrast pass without touching a single component.

This was verified mechanically, not by eye. See [§9 Verification](#9-verification).

### How a token flows

```
app/globals.css        --brand-navy: 28 43 69;
tailwind.config.ts     navy: "rgb(var(--brand-navy) / <alpha-value>)"
your component         className="bg-navy/90 text-white"
```

The `<alpha-value>` placeholder is what keeps Tailwind's `/90` opacity modifiers
working through the variable. Two ladders (`label-*`, `fill-*`) bake their alpha into
the token instead, because the alpha *is* the semantic step — so `text-label-secondary`
works, `text-label-secondary/50` does not.

---

## 1. Typography

### The stack

```css
--font-sans:
  -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display",
  var(--font-inter, Inter), Inter, "Segoe UI Variable Text", "Segoe UI", Roboto,
  "Helvetica Neue", Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji";
```

SF Pro cannot be licensed for the web, but `-apple-system` is not a webfont — it is a
handle on the OS font, so Apple devices render genuine SF, including its automatic
optical switch from SF Pro Text to SF Pro Display around 20pt. Everywhere else —
which for this product is most of Android and Windows — Inter renders, already loaded
by `next/font` in `app/layout.tsx`. No new font is downloaded, on any platform.

`var(--font-inter, Inter)` carries a literal fallback on purpose: if a subtree ever
renders without the `next/font` class, an unresolved variable would invalidate the
whole `font-family` declaration and drop the page to a serif. The fallback prevents that.

`html` also sets `font-optical-sizing: auto` (lets SF and Inter v4 use their `opsz`
axis) and `font-synthesis-weight: none` (never fake a bold that the family already has).

### The ramp

Apple's semantic sizes, shipped verbatim, with Apple's leading:

| Utility | Size | Leading | Tracking | Weight | Apple role |
| --- | --- | --- | --- | --- | --- |
| `text-large-title` | 34px | 41px | −0.015em | 700 | largeTitle |
| `text-title-1` | 28px | 34px | −0.013em | 700 | title1 |
| `text-title-2` | 22px | 28px | −0.010em | 600 | title2 |
| `text-title-3` | 20px | 25px | −0.008em | 600 | title3 |
| `text-headline` | 17px | 22px | −0.005em | 600 | headline |
| `text-body-lg` | 17px | 22px | −0.005em | 400 | body |
| `text-callout` | 16px | 21px | −0.004em | 400 | callout |
| `text-subhead` | 15px | 20px | −0.002em | 400 | subhead |
| `text-footnote` | 13px | 18px | 0 | 400 | footnote |
| `text-caption-1` | 12px | 16px | 0 | 400 | caption1 |
| `text-caption-2` | 11px | 13px | +0.006em | 400 | caption2 |

### The ramp the app already speaks

The app is built. Rewriting 200 files to change 14px body copy to 17px would be a
redesign, not a design system — and Apple's own macOS ramp is smaller than its iOS one
(13pt body, not 17pt), so a dense web dashboard sitting between the two is the correct
place to be, not a compromise. The existing utilities therefore keep their **sizes and
line-heights frozen** — those drive every layout in the app — and were moved onto the
same optical tracking curve as the ramp above:

| Utility | Size | Leading | Tracking (was → now) | Sits between |
| --- | --- | --- | --- | --- |
| `text-stat` | 36px | 1.2 | −0.02em → **−0.016em** | above largeTitle |
| `text-stat-sm` | 28px | 34px | −0.02em → **−0.013em** | = title1 |
| `text-title` | 24px | 32px | — → **−0.011em** | title1 / title2 |
| `text-title-sm` | 22px | 30px | — → **−0.010em** | = title2 |
| `text-card-title` | 16px | 24px | — → **−0.004em** | = callout |
| `text-body` | 14px | 20px | — (unchanged) | subhead / footnote |
| `text-caption` | 12px | 16px | +0.05em (unchanged) | uppercase eyebrow |

Only tracking moved. The largest shift is `text-stat-sm`, at 0.007em × 28px ≈ 0.2px per
character — about 2px across a ten-digit currency figure, and in the direction that
makes it read as a number rather than a headline.

`text-caption` deliberately keeps its **+0.05em** and 600 weight. It is the uppercase
eyebrow role (`.label-caps`), and uppercase needs positive tracking. Apple's caption1
tracking of 0 is available as `text-caption-1` for sentence-case captions.

### Why negative tracking at display sizes

Apple's published Dynamic Type tracking values are *corrections layered on top of SF's
own optical metrics* — SF Pro Display is already drawn considerably tighter than SF Pro
Text, and the point-based corrections in the HIG partly compensate for that. They are
not a portable instruction to a web stack.

On the web the stack is mixed. SF tightens itself on Apple devices; **Inter has a single
optical size and does not**. Shipping Apple's raw correction values would leave Inter
users with loose, airy headlines and Apple users with the right thing. The curve above is
therefore the optical curve: roughly −0.015em at display sizes, easing to 0 around 13px
and turning slightly positive at 11px where letterforms need air. On Apple hardware it
composes with SF's own optical sizing; on Inter it does the whole job.

Standalone tracking tokens for one-off cases: `tracking-display` (−0.015em, ≥28px),
`tracking-title` (−0.011em, 20–24px), `tracking-text` (−0.004em, 15–17px),
`tracking-caps` (0.05em).

---

## 2. Colour

### 2.1 Brand (unchanged)

| Token | Value | Role |
| --- | --- | --- |
| `ivory` | `#F6F4EF` | page background |
| `stone` | `#EDEAE3` | secondary surface |
| `navy` / `navy-deep` / `navy-soft` | `#1C2B45` / `#06162F` / `#384762` | primary ink, buttons, active nav, key numbers |
| `teal` / `teal-soft` | `#3E7C74` / `#E4EFED` | paid, positive, healthy |
| `sage` / `sage-soft` | `#8CA687` / `#EAF0E8` | free, available |
| `sand` / `sand-deep` / `sand-soft` | `#D8B98A` / `#A8834B` / `#F7EFE1` | pending, partial, warning |
| `red` / `red-soft` | `#C4574E` / `#F8E7E5` | overdue, unpaid, open, error |
| `charcoal` / `muted` | `#2A2E35` / `#6E7480` | body text / secondary text |
| `line` | `#E5E1D8` | opaque hairline |

### 2.2 The label hierarchy

Four rungs of one ink, the way Apple does it — `label`, `label-secondary`,
`label-tertiary`, `label-quaternary`.

Apple's alphas (1 / 0.60 / 0.30 / 0.18) are calibrated against **pure white**. This app's
page is `#F6F4EF`, whose relative luminance is about 10% below white, and a glass card
over it composites to `#FCFBF9`. Dropped onto those backdrops unchanged, Apple's
secondary label measures **3.75:1 — an AA failure**. So the ladder was re-solved against
the two real backdrops:

| Utility | Alpha | on `ivory` | on a `.glass-card` (`#FCFBF9`) | Use for |
| --- | --- | --- | --- | --- |
| `text-label` | 1.00 | **12.40:1** | **13.19:1** | primary content |
| `text-label-secondary` | 0.68 | **4.70:1** | **4.83:1** | body copy, captions, any real text |
| `text-label-tertiary` | 0.52 | **3.02:1** | **3.08:1** | ≥18.66px bold / ≥24px text, icons, controls |
| `text-label-quaternary` | 0.30 | 1.79:1 | 1.80:1 | **decorative only** — never carries meaning |

`label-quaternary` is below every text threshold by design. It is Apple's rung for
inactive glyph fills and placeholder scaffolding. If a user has to read it, it is the
wrong token.

### 2.3 The fill hierarchy

Translucent greys for control backgrounds, track fills and pressed states — Apple's exact
alphas over `rgb(120 120 128)`. Fills are **backgrounds only**; meaning never lives in a
fill. Text sitting on them keeps enormous headroom:

| Utility | Alpha | Composites over ivory to | `charcoal` on it |
| --- | --- | --- | --- |
| `bg-fill` | 0.20 | `#DDDBD9` | **9.88:1** |
| `bg-fill-secondary` | 0.16 | `#E2E0DD` | **10.36:1** |
| `bg-fill-tertiary` | 0.12 | `#E7E5E2` | **10.85:1** |
| `bg-fill-quaternary` | 0.08 | `#ECEAE6` | **11.35:1** |

`border-separator` is the translucent hairline (ink at 0.10 → `#E2E0DC` over ivory,
1.20:1 — a hairline, correctly). `border-line` remains the opaque `#E5E1D8` equivalent.

### 2.4 Apple's system colours

`sys-blue`, `sys-green`, `sys-indigo`, `sys-orange`, `sys-pink`, `sys-purple`, `sys-red`,
`sys-teal`, `sys-yellow`, `sys-gray`. Light values, dark values, and Apple's own
*accessible* (Increase Contrast) values, all switched automatically.

Measured against this app's real backgrounds:

| Token | Light | on `ivory` | Accessible light | on `ivory` | Dark | on `#0B0F14` | Accessible dark | on `#0B0F14` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| blue | `#007AFF` | 3.65:1 | `#0040DD` | **6.88:1** | `#0A84FF` | **5.27:1** | `#409CFF` | **6.79:1** |
| green | `#34C759` | 2.02:1 | `#248A3D` | 4.00:1 | `#30D158` | **9.51:1** | `#30DB5B` | **10.44:1** |
| indigo | `#5856D6` | **5.14:1** | `#3634A3` | **8.78:1** | `#5E5CE6` | 3.80:1 | `#7D7AFF` | **5.58:1** |
| orange | `#FF9500` | 2.00:1 | `#C93400` | **4.81:1** | `#FF9F0A` | **9.35:1** | `#FFB340` | **10.78:1** |
| pink | `#FF2D55` | 3.32:1 | `#D30F45` | **4.87:1** | `#FF375F` | **5.46:1** | `#FF6482` | **6.77:1** |
| purple | `#AF52DE` | 3.76:1 | `#8944AB` | **5.49:1** | `#BF5AF2` | **5.45:1** | `#DA8FFF` | **8.56:1** |
| red | `#FF3B30` | 3.23:1 | `#D70015` | **4.90:1** | `#FF453A` | **5.64:1** | `#FF6961` | **6.81:1** |
| teal | `#30B0C7` | 2.34:1 | `#0071A4` | **4.90:1** | `#40C8E0` | **9.66:1** | `#5DE6FF` | **13.02:1** |
| yellow | `#FFCC00` | 1.38:1 | `#B25000` | **4.73:1** | `#FFD60A` | **13.61:1** | `#FFD426` | **13.45:1** |

One caveat inside the accessible set itself: `sys-green` at `#248A3D` reaches only
**4.00:1** on ivory. Apple tunes those variants against `#FFFFFF`, and green is the hue
that loses the most on a warm ground. Use `teal` or `ink-teal` for success text on ivory;
`sys-green` accessible is fine for icons and marks (3:1).

**Read that table before using a system colour as text.** In their standard light form
most of them are *fills and control tints*, not text colours — `sys-yellow` on ivory is
1.38:1. Only `sys-indigo` clears AA for body text on ivory unaided. This is not a flaw in
the palette; it is what those colours are for. For coloured text, use §2.5.

### 2.5 Accessible inks — the brand hues at AA strength

The same hues, darkened until they clear **4.5:1 on all three** real backdrops: `ivory`,
a glass card, and their own soft tint.

| Token | Value | on `ivory` | on `.glass-card` | on its soft tint |
| --- | --- | --- | --- | --- |
| `text-ink-navy` | `#1C2B45` | **12.90:1** | **13.72:1** | — |
| `text-ink-teal` | `#376D66` | **5.39:1** | **5.74:1** | **5.05:1** |
| `text-ink-sage` | `#5C6C58` | **5.11:1** | **5.43:1** | **4.85:1** |
| `text-ink-sand` | `#786751` | **4.95:1** | **5.27:1** | **4.77:1** |
| `text-ink-red` | `#A2453D` | **5.53:1** | **5.88:1** | **5.08:1** |
| `text-ink-muted` | `#616772` | **5.18:1** | **5.51:1** | — |

**Any text that carries meaning belongs on these.** Status pills, amounts, inline
warnings, "3 days left".

And for non-text objects — chart series, icon strokes, borders that must be
distinguishable — WCAG asks 3:1, which two brand hues miss on ivory:

| Token | Value | on `ivory` | replaces |
| --- | --- | --- | --- |
| `mark-sage` | `#7B9277` | **3.07:1** | `sage` (2.41:1) |
| `mark-sand` | `#A08966` | **3.05:1** | `sand` (1.70:1) |

`teal` (4.40:1) and `red` (3.96:1) already clear 3:1 as marks and need no substitute.

### 2.6 Audit of the pairs that were already in the app

Measured, not estimated. These are the combinations the app renders today.

| Pair | Ratio | AA target | |
| --- | --- | --- | --- |
| `charcoal` on `ivory` | 12.40:1 | 4.5 | PASS |
| `charcoal` on `.glass-card` | 13.18:1 | 4.5 | PASS |
| `navy` on `ivory` | 12.90:1 | 4.5 | PASS |
| white on `bg-navy` (primary button) | 14.18:1 | 4.5 | PASS |
| white on `bg-teal` (teal button) | 4.84:1 | 4.5 | PASS |
| `muted` on `.glass-card` | 4.54:1 | 4.5 | PASS |
| **`muted` on `ivory`** | **4.27:1** | 4.5 | **FAIL** |
| **white on `bg-red` (destructive button)** | **4.36:1** | 4.5 | **FAIL** |
| **`text-teal` on `bg-teal-soft`** (paid pill) | **4.12:1** | 4.5 | **FAIL** |
| **`text-red` on `bg-red-soft`** (overdue pill) | **3.64:1** | 4.5 | **FAIL** |
| **`text-sand-deep` on `bg-sand-soft`** (pending pill) | **3.06:1** | 4.5 | **FAIL** |
| **`text-sage` on `bg-sage-soft`** (free pill) | **2.29:1** | 4.5 | **FAIL** |
| **`text-teal` on `ivory`** | **4.40:1** | 4.5 | **FAIL** |
| **`text-red` on `ivory`** | **3.96:1** | 4.5 | **FAIL** |
| `sand` as a graphical mark on `ivory` | 1.70:1 | 3.0 | **FAIL** |
| `sage` as a graphical mark on `ivory` | 2.41:1 | 3.0 | **FAIL** |

Three notes on this table:

1. `sand-deep` is commented in the old config as "contrast-safe". It is not — 3.06:1
   on its own tint.
2. The destructive button misses by 0.14. `red: #C0554D` is the nearest value that
   passes (4.50:1) and is visually indistinguishable from `#C4574E`.
3. **None of these were changed here**, because they are brand values that live in
   components outside this system's scope, and a parallel change would collide. What
   *is* shipped: the passing replacements in §2.5, and an automatic swap under
   Increase Contrast (§7.2) that fixes every one of these pairs for the users who ask
   for it. The permanent fix is a five-line change in
   `components/shared/status-pill.tsx` — see [§10 Known gaps](#10-known-gaps).

---

## 3. Materials ("liquid glass")

An Apple material is four things layered, not one:

1. a **blur** of what is behind it,
2. a **saturation boost** on that blur,
3. a translucent **tint**,
4. a **hairline border**, plus a specular top edge.

Point 2 is the one people skip, and it is the one that matters. `blur(20px)` alone
averages the backdrop toward grey — the classic "frosted plastic" look.
`blur(20px) saturate(180%)` pulls the colour back out of the average, so a warm ivory
page stays warm through the glass. That single function is most of the difference
between this reading as Apple and reading as Bootstrap.

Adding it is free: the surface was already running a `backdrop-filter` compositing pass,
and `saturate()` joins the same filter chain rather than adding a second one.

### The five weights

| Class | Tint α | Blur | Saturate | Border | Use for |
| --- | --- | --- | --- | --- | --- |
| `.material-ultra-thin` | 0.45 | 12px | 160% | white/0.6 | overlays that must stay see-through — scrims, hover veils |
| `.material-thin` | 0.65 | 20px | 180% | white/0.6 | **the default card surface** |
| `.material-regular` | 0.85 | 20px | 180% | white/0.8 | content-heavy cards, dense tables |
| `.material-thick` | 0.94 | 30px | 190% | white/0.8 | modals and sheets over a busy page |
| `.material-chrome` | 0.65 | 24px | 200% | white/0.6 | app chrome — sidebars, top bars, bottom nav |

The three legacy classes are now *names for* three of those weights, with identical tint,
blur and border to before:

```
.glass-card        === .material-thin      (+ rounded-card)
.glass-card-strong === .material-regular   (+ rounded-card)
.glass-bar         === .material-chrome
```

What changed on them: the saturation pass, and a `inset 0 1px 0 rgb(255 255 255 / 0.55)`
specular top edge merged into the existing shadow. The ambient shadow is unchanged.

### Rules

- **Never nest a material inside a material.** Two blurs compound into mud and cost two
  compositing passes. Use `bg-fill-tertiary` for a surface inside a card.
- **A material needs something behind it.** Over a flat colour it is just a tinted box
  with a GPU cost. On the ivory page gradient, it works.
- **Chrome uses `chrome`; content uses `thin`/`regular`.** Bars and content should not
  share a weight, or the layering reads flat.

### Fallbacks

- No `backdrop-filter` support → `@supports not (...)` swaps in the pre-flattened opaque
  colour (`#FCFBF9` / `#FEFDFD`). A transparent unreadable panel is never shipped.
- `prefers-reduced-transparency: reduce` → all five alphas go to 1 and the blur is
  dropped entirely.

---

## 4. Motion

### Durations

| Token | Value | Use for |
| --- | --- | --- |
| `duration-quick` | 200ms | hover, tint, opacity, anything under the pointer |
| `duration-standard` | 300ms | most state changes |
| `duration-emphasized` | 500ms | full-screen or hero transitions |

### Curves

| Token | Value | Origin |
| --- | --- | --- |
| `ease-sys` | `cubic-bezier(0.25, 0.1, 0.25, 1)` | `CAMediaTimingFunction` `.default` |
| `ease-sys-in` | `cubic-bezier(0.42, 0, 1, 1)` | `.easeIn` |
| `ease-sys-out` | `cubic-bezier(0, 0, 0.58, 1)` | `.easeOut` |
| `ease-sys-in-out` | `cubic-bezier(0.42, 0, 0.58, 1)` | `.easeInOut` |

### Springs, actually solved

Apple does not use bezier curves for the motion that feels alive — it uses a damped
harmonic oscillator. Four of them are shipped here as CSS `linear()` easings, each one
computed rather than eyeballed:

Given a SwiftUI spring, mass 1, `ω₀ = 2π / duration` and `ζ = 1 − bounce`, the unit-step
response of an underdamped system is

```
x(t) = 1 − e^(−ζω₀t) · [ cos(ω_d t) + (ζω₀ / ω_d) · sin(ω_d t) ],   ω_d = ω₀√(1 − ζ²)
```

Each curve is that function sampled at 29 evenly spaced points across its own settle time
(the last moment it is more than 0.002 from rest), emitted as `linear(…)`:

| Token | SwiftUI equivalent | ζ | Settle | Overshoot | Pair with |
| --- | --- | --- | --- | --- | --- |
| `ease-spring` | `.spring(response: 0.55, dampingFraction: 0.825)` | 0.825 | 0.729s | +1.0% | `duration-spring` (730ms) |
| `ease-smooth` | `.smooth` — `Spring(duration: 0.5, bounce: 0)` | 1.00 | 0.694s | none | `duration-smooth` (700ms) |
| `ease-snappy` | `.snappy` — `Spring(duration: 0.5, bounce: 0.15)` | 0.85 | 0.662s | +0.6% | `duration-snappy` (660ms) |
| `ease-bouncy` | `.bouncy` — `Spring(duration: 0.5, bounce: 0.30)` | 0.70 | 0.749s | +4.6% | `duration-bouncy` (750ms) |

They genuinely overshoot and settle back. **Pair each curve with its own duration token**
or the overshoot lands in the wrong place and the motion reads broken.

Each token is declared twice — a `cubic-bezier` approximation first, then the `linear()`.
Browsers that do not parse `linear()` discard the second declaration and keep the
approximation. No `@supports`, no JS, no feature detection.

```html
<div class="transition-transform duration-snappy ease-snappy" />
```

Animations: `animate-fade-in` (retuned to `ease-sys-out`), `animate-scale-in` (Apple's
popover entrance — 0.96 → 1 with a fade, on `snappy`), `animate-sheet-in` (sheet rise,
on `smooth`).

**With `motion`**: the CSS tokens do not reach `motion/react`. Use the equivalent spring
config directly, so both engines agree:

```ts
const snappy = { type: "spring", duration: 0.5, bounce: 0.15 } as const;
const smooth = { type: "spring", duration: 0.5, bounce: 0 } as const;
```

### Reduced motion

`prefers-reduced-motion: reduce` collapses every animation and transition to 0.01ms
globally. Following Apple's guidance, this removes *movement*, not *feedback* — state
changes still happen visibly, they just stop travelling. Nothing is set to `none`, so no
element gets stuck mid-animation.

---

## 5. Radii

Apple's corner ramp is **6 / 10 / 14 / 20 / 28**, and the size is a function of what the
corner contains, not of taste: a corner should feel like a constant physical radius
regardless of the box it belongs to.

| Utility | Radius | Use for |
| --- | --- | --- |
| `rounded-xs` | 6px | badges, bed dots, chart bars, avatars ≤24px |
| `rounded-md` | 10px | a surface nested inside a card |
| `rounded-control` | 12px | inputs and buttons (the app's established step) |
| `rounded-control-lg` | 14px | 44pt+ controls, segmented controls |
| `rounded-card` | 20px | cards |
| `rounded-sheet` | 28px | sheets, modals, hero surfaces |
| `rounded-full` | — | pills and avatars |

`rounded-sm` (8px) and `rounded-lg` (12px) are retained off-ramp steps that shadcn menu
primitives depend on. New work should use the ramp.

### Squircles

Apple's corners are not circular arcs — they are continuous curvature (a superellipse),
which is why an iOS icon corner has no visible seam where the straight edge meets the
curve. CSS is only now growing a native `corner-shape` property, so this ships as
progressive enhancement:

```css
@supports (corner-shape: squircle) { .squircle { corner-shape: squircle; } }
```

Add `.squircle` alongside any `rounded-*` class. Where the browser supports it the corner
becomes continuous; where it does not, absolutely nothing happens and the normal radius
stands. The alternative — an SVG or `clip-path` superellipse per component — costs
layout, breaks `overflow`, and cannot be applied from a token layer. Not worth it for a
difference most users cannot name.

---

## 6. Elevation

Apple shadows are two shadows: a tight **contact** shadow that anchors the object, and a
wide, very light **ambient** one. A single large blurry shadow always reads as a sticker.

| Utility | Use for |
| --- | --- |
| `shadow-elev-1` | resting chip, inline control |
| `shadow-elev-2` | raised button, hovered row |
| `shadow-elev-3` | a card at rest |
| `shadow-elev-4` | popover, dropdown, sheet |
| `shadow-elev-5` | modal over a dimmed page |
| `shadow-highlight` | the specular top edge alone |
| `shadow-material` | `highlight` + `elev-3` — a complete glass surface |

All of them are keyed to `rgb(6 22 47)` (navy-deep) rather than black, so they stay warm
on ivory instead of going grey. In the dark theme the same tokens re-point to true black
at much higher alpha, because a navy shadow on a navy-black page is invisible.

`shadow-glass`, `shadow-glass-lg` and `shadow-nav` are unchanged.

---

## 7. Accessibility

### 7.1 Contrast

Every pair defined by this system passes WCAG 2.1 AA for its intended use. The complete
measured set is in §2.2, §2.3, §2.5 and §8; the audit of pre-existing pairs, including
six failures this system does not yet fix, is in §2.6.

Targets used: **4.5:1** for text under 18.66px bold / 24px; **3:1** for large text, icons
and graphical objects; hairlines and decorative fills carry no threshold and are labelled
as such.

### 7.2 `prefers-contrast: more`

Honoured, and it does real work rather than adding a border:

- the brand hues re-point to the accessible inks from §2.5 — which fixes **every status
  pill in the app** with no component change;
- the label ladder steps up (secondary 0.68 → 0.82 = **7.18:1**, tertiary 0.52 → 0.68 =
  **4.70:1**);
- separators go from 0.10 to 0.28 alpha;
- materials become nearly opaque (thin 0.65 → 0.92) and their borders switch from white
  to charcoal, so the surface edge is visible rather than implied;
- the system colours swap to Apple's own published accessible variants (§2.4);
- the focus ring goes from 3px to 4px and from 35% to 70% alpha.

### 7.3 `prefers-reduced-transparency: reduce`

All five material weights go fully opaque and drop `backdrop-filter` entirely. This is
Apple's "Reduce Transparency" setting and it is a real accessibility need — translucency
over moving content is a vestibular and low-vision problem, not a taste preference.

### 7.4 `prefers-reduced-motion: reduce`

See §4.

### 7.5 Focus

A system focus ring is applied to every focusable element that does not define its own:

```css
:where(a, button, summary, [role="button"], [role="tab"], input, select, textarea, [tabindex]):focus-visible {
  outline: var(--focus-ring-width) solid var(--focus-ring);
  outline-offset: var(--focus-ring-offset);
}
```

`:where()` contributes zero specificity, so this rule scores `(0,1,0)` — lower than
Tailwind's `focus-visible:outline-none` at `(0,2,0)`. Every component in `components/ui`
that already manages its own ring keeps winning; everything that previously had *no*
visible focus indicator now has one. It cannot regress an existing focus style.

`.focus-ring-sys` applies the same ring explicitly where a component wants it.

---

## 8. Dark theme

The palette is complete and measured. It is **deliberately not wired to
`prefers-color-scheme`.**

Every screen currently hard-codes light surfaces — `bg-white/60`, `bg-ivory`,
`text-charcoal`, `border-white/70`. Flipping tokens on an OS preference alone would put
light text on those still-light surfaces and break the app for every user with a dark
system setting. That would be a worse outcome than no dark mode.

To switch it on: add `class="dark"` (or `data-theme="dark"`) to `<html>` — the token
layer keys off both, as does Tailwind's `dark:` variant — then replace the hard-coded
surface classes with `.material-*` and the `label-*` / `fill-*` ladders. The tokens are
already correct on the other side.

Measured, on the dark material (`#191D22` — the thin material over the `#0B0F14` page):

| Token | Dark value | Ratio | |
| --- | --- | --- | --- |
| `label` | `rgb(235 235 245)` | **14.34:1** | PASS |
| `label-secondary` | α 0.60 | **5.94:1** | PASS |
| `label-tertiary` | α 0.45 | **3.94:1** | PASS (3:1) |
| `charcoal` | `#EBEBF5` | **14.34:1** | PASS |
| `navy` | `#7F8796` | **4.70:1** | PASS |
| `navy-soft` | `#7E8799` | **4.71:1** | PASS |
| `teal` | `#5C9089` | **4.69:1** | PASS |
| `sage` | `#8CA687` | **6.40:1** | PASS |
| `sand` | `#D8B98A` | **9.08:1** | PASS |
| `red` | `#CB6B63` | **4.71:1** | PASS |
| `muted` | `#828791` | **4.71:1** | PASS |

Two things worth knowing about the dark set:

- **`navy` cannot survive.** `#1C2B45` on `#191D22` is **1.20:1** — invisible. Navy is
  the brand's primary ink, so on dark it is lifted to `#7F8796`, keeping the hue and the
  role while becoming readable. This is not optional; it is what a semantic token means.
- **The page is `#0B0F14`, not black.** A navy-tinted near-black keeps the brand's
  temperature. `sage` and `sand` need no adjustment at all — they already clear 6:1
  and 9:1 there.

Dark shadows switch from navy to true black at 0.40–0.65 alpha, because a navy shadow on
a navy page does nothing.

---

## 9. Verification

Nothing above is asserted from reading the CSS. What was actually run:

**Contrast.** Every ratio in this document was computed from the shipped
`app/globals.css` — the script parses the real `:root` and `.dark` blocks, resolves the
custom properties, composites the alpha-based tokens over the *actual* backdrops
(including a `.glass-card` flattened over ivory to `#FCFBF9`), and applies the WCAG 2.1
relative-luminance formula. Result: **0 failures among shipped token pairs.**

**Non-regression.** Both the old and new token sets were compiled with the same Tailwind
CLI against the same 200-odd source files, then diffed *after resolving every custom
property and normalising every colour to `rgba()`*, so `#1C2B45` and
`rgb(var(--brand-navy) / 1)` compare equal:

```
baseline selectors: 935, new selectors: 942
declarations identical after var resolution: 1120
missing selectors: 0, changed/dropped declarations: 19
```

All 19 are intentional and accounted for: 3 × `font-family` (the SF stack, §1),
`.text-stat` / `.text-stat-sm` / `.md:text-stat` letter-spacing (§1), `.animate-fade-in`
easing (§4), `.font-mono` (SF Mono first), and 12 on the three glass classes, which are
the shorthand-to-longhand rewrite in §3. The effective computed style of `.glass-card`,
`.glass-card-strong` and `.glass-bar` was then dumped through PostCSS and compared
declaration by declaration — tint, blur and border are byte-identical to before.

**Every new utility actually generates.** A probe file naming all 29 new class forms was
compiled through the real config. All 29 emit, including the `@supports (corner-shape:
squircle)` block, both `dark:` variant selectors, and the opacity modifier reading through
a variable (`bg-sys-blue/20` → `background-color: rgb(var(--sys-blue) / 0.2)`).

**Toolchain.** `npx tsc --noEmit`, `npm run lint`, `npx next build` and
`node scripts/security-scan.mjs --no-history` all pass — 0 errors, 0 blockers, 0 warnings.

**Cost**, from `next build` before and after:

| | Before | After | Delta |
| --- | --- | --- | --- |
| Route CSS, raw | 58,124 B | 68,786 B | +10,662 B |
| Route CSS, gzipped | 11,562 B | 14,057 B | **+2,495 B** |
| First Load JS shared by all | 102 kB | 102 kB | **0** |
| Shared chunk hashes | `1255-d3668ee…` 46.1 kB, `4bd1b696-100b9d7…` 54.2 kB | identical | **0** |

JavaScript is untouched — the shared chunk filenames are content hashes and they did not
change, so the bundle is byte-identical. No route's First Load JS moved at all. There is
no runtime, no font parsing, no new dependency: the springs are CSS `linear()` functions
and the materials reuse a compositing pass the app was already paying for.

Of that growth, the dark palette accounts for a measured **1,704 bytes minified** — inert
until `.dark` is set. It is one contiguous region of `globals.css` and can be split out if
that ever matters more than having the theme ready.

---

## 10. Known gaps

1. **Status pills still fail AA in the default (non-Increase-Contrast) state.**
   `components/shared/status-pill.tsx` is outside this system's file scope. The fix is
   its `toneClass` map:

   ```ts
   teal: "bg-teal-soft text-ink-teal",     // 4.12:1 -> 5.05:1
   sand: "bg-sand-soft text-ink-sand",     // 3.06:1 -> 4.77:1
   red:  "bg-red-soft  text-ink-red",      // 3.64:1 -> 5.08:1
   sage: "bg-sage-soft text-ink-sage",     // 2.29:1 -> 4.85:1
   muted:"bg-stone     text-ink-muted",    // -> 5.18:1
   ```

2. **The destructive button is 4.36:1**, 0.14 short. `red: #C0554D` reaches 4.50:1 and is
   visually indistinguishable. Not changed here because `red` is a brand value also
   hard-coded in `components/shared/charts.tsx`, and both should move together.

3. **`text-muted` on the bare ivory page is 4.27:1.** On a glass card — where most of it
   sits — it is 4.54:1 and passes. `text-label-secondary` (4.70:1) or `text-ink-muted`
   (5.18:1) is the replacement for page-level secondary text.

4. **Chart colours are hard-coded** in `components/shared/charts.tsx`, so they do not
   follow the theme or Increase Contrast. `CATEGORY_COLORS` also uses `sage` and `sand`
   as series marks at 2.41:1 and 1.70:1 — `mark-sage` / `mark-sand` are the passing
   substitutes.

5. **The dark theme is unreachable from the UI.** No toggle, and the hard-coded surface
   classes described in §8 must be migrated first.

6. **The Recharts overrides in `globals.css` have never shipped.** Pre-existing, found
   while diffing the compiled output: `.recharts-default-tooltip` and
   `.recharts-cartesian-grid-*` sit inside `@layer components`, and Tailwind purges any
   layered rule whose class never appears in the scanned source. Those class names come
   from Recharts at runtime, so they are scanned out of both the old and the new
   stylesheet — `grep -c recharts` on the compiled CSS returns **0 for both**. The charts
   are rendering Recharts' defaults, not the design language. The fix is to move those two
   rules outside `@layer components` (plain top-level CSS is never purged) or to add the
   selectors to a `safelist`. Deliberately not done here: switching them on is a visible
   change to every chart, which belongs in a change that owns the chart components.

7. **Nothing consumes the new tokens yet.** The material, label, fill, ink and spring
   tokens are defined, measured and documented, but every existing component still uses
   the legacy names — which is exactly why the change is safe. Adoption is a separate,
   incremental pass.
