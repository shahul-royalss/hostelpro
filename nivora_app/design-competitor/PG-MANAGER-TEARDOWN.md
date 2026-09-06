# What PG Manager actually looks like, and what is worth taking

`com.pgmanager` v9.4.1 (build 106), "a CONCEPTIVE MINDS product", www.pgmanager.in. A native
Kotlin PG-management app — the closest direct competitor to NIVORA that ships on Play today.
Installed on the `nivora_test` AVD from the four supplied splits and driven far enough to see
every pre-login screen. Everything below is measured off the artifact or read off a screenshot,
not recalled.

## The static facts

- **Light theme only.** `Base.Theme.AppCompat.Light.DarkActionBar`, and only three `-night`
  resource entries in the whole APK. There is no dark mode to speak of.
- **Peach primary ramp** `#f1c4a2 → #f8e1d0`, accent brown `#541000`.
- **Eight per-feature accents**, one per module: bills `#0088ff`, bookings `#8e24aa`,
  card `#28a885`, expenses `#8d6e63`, issues `#fbc02d`, notices `#afb42b`,
  paymentApproval `#26a69a`, payments `#f8a824`.
- **Five font families**: Quicksand (bold/book/light), DM Sans, Alata, Roboto. Quicksand — a
  rounded geometric sans — carries almost all the visible type.
- **389 vector drawables vs 75 raster.** Nearly everything is a path, so nothing is soft at
  xxhdpi. ~10 view animations, no Lottie.
- **282 layouts, 46+ activities.** Activity-per-screen, not a single-activity nav graph.

## CORRECTION — the login screen is not representative, and I nearly got this wrong

My first read of this app was the login screen, which has a soft-shadowed white card, and I
started to conclude that the competitor beats NIVORA by being *elevated* where NIVORA is flat.
That conclusion is wrong, and the artifact says so plainly. Dumped with `aapt2` across every
content layout in the APK:

| Layout | cardElevation | cardCornerRadius |
|---|---|---|
| `dashboard` | **0dp** | 20dp outer / 10dp inner |
| `inmate_card` | **0dp** | 20dp |
| `bill_card` | **0dp** | 20dp |
| `expense_card` | **0dp** | 20dp |
| `notice_card` | **0dp** | 20dp |
| `issues_card` | **0dp** | 20dp |
| `payment_approval_card` | **0dp** | 20dp |
| `people_card` | **0dp** | 20dp |
| `wallet_transaction_card` | **0dp** | 20dp |
| `manage_rooms_card` | **0dp** | 20dp |

**Every card in the product is zero-elevation at a 20dp radius.** There is not one shadow
anywhere in the content layer. NIVORA's existing rule — "a resting card casts NO shadow, it
gets a hairline" — is the same instinct, and it should NOT be overturned.

What separates the competitor's cards instead is the thing NIVORA does not do:

- The dashboard ground is a **vertical gradient**, `#d6a37d` → `#f1c4a2` (`colorPrimaryDarker`
  → `colorPrimary`, angle 90).
- The cards on it are **translucent white** — `dashboardCardColor` = `#aaffffff` (67% white),
  and the inner tiles are `gradientBackgroundCardColor` = `#60ffffff` (37% white).
- So a card reads as a card because it is a *lighter wash of the coloured ground*, not because
  it floats above it. Card titles are deep teal `#004d40`, body `#111111`.

That is the whole trick, and it is a good one: **the ground carries the colour, the cards are
translucency over it.** It is why every screen looks tinted and warm rather than white-on-grey.

## The five devices that make it look designed

These are the things worth taking. Only one of them is a colour.

1. **A CURVED COLOURED HERO, AND A CARD RIDING THE SEAM.** The login screen's top third is a
   full-bleed peach block whose bottom edge is a convex curve, and the white form card overlaps
   that curve. That single move is most of why the screen reads as designed rather than
   assembled. Nothing else on the screen is doing any work.
2. **A COLOURED GROUND WITH TRANSLUCENT CARDS ON IT** — see the correction above. This, not
   elevation, is how every content screen gets its warmth.
3. **A BIG, CONSTANT CORNER RADIUS.** 20dp on every card, 10dp on every inner tile, with no
   exceptions anywhere in 282 layouts. The consistency is as important as the size.
4. **BIG ROUNDED OUTLINED INPUTS WITH A LEADING ICON.** ~64dp tall, ~12dp radius, 1dp grey
   outline, no fill, a grey line icon in the leading slot, placeholder as the only label.
   Generous — roughly 1.5x the height of a stock Material field.
5. **A FULL-BLEED SATURATED ONBOARDING CAROUSEL.** Four pages, one flat colour each —
   amber `#f3b313`, teal `~#1ecbb0`, blue `~#3d9bfb`, orchid `~#c07ff0`. Each page is a large
   white thin-stroke line icon, a bold heading, a two-line subtitle, and a bottom bar of
   SKIP - four dots - NEXT (the last page says GOT IT). Copy is plain and benefit-shaped:
   "Manage PGs" / "Create and Manage PGs, Rooms and Beds as required!",
   "Manage Tenants" / "Check In and Check Out tenants with cloud support!",
   "Collect Payments" / "Collect rent payments online or offline, let us do the math!",
   "PG Cloud" / "A free forever app for tenants for you to receive payments online!"

The sixth device, the gradient pill CTA, is real but it is BADLY DONE — see the flaws below.
`rounded_fill_button_gradient_theme` is `#eeb68b` to `#80a4ffff` at 225 degrees: peach into
half-transparent cyan, which greys out through the middle. Take the pill, not the gradient.

Secondary, and also worth having: a **soft vertical background gradient** behind the card
(pale blue → pale cyan), and **line icons everywhere, never filled glyphs**.

## What is actually wrong with it — do not copy these

- **It asks for CALL_PHONE at first launch**, with a system dialog and no rationale, before the
  user has seen a single screen of the product. Denying it then triggers the app's own
  "Need Network Permission" dialog on the login screen. Two permission prompts before login.
- **The gradient CTA is muddy.** Mint on the left, peach on the right, and the middle is the
  grey you get when you interpolate two low-chroma colours through the wrong space. The dark
  brown label on the peach end is marginal against 4.5:1.
- **A bare `0/10` counter dangles under the mobile field**, unlabelled, permanently visible.
- **No dark theme at all.** On a phone set to dark this app is a slab of white at 2am.
- **The bottom fifth of the login screen is branding** — "a CONCEPTIVE MINDS product" and a
  URL — which is space the product is not using.
- **Peach on brown is a weak pairing.** Low chroma, low contrast, and it reads dated rather
  than warm. This is the specific thing NIVORA must beat, not match.

## The brief for NIVORA

Take devices 1–5 and the two secondary ones. Take none of the colours. NIVORA already owns a
better palette than peach-and-brown — a gold accent with violet, teal and coral domain tones —
and it already has a dark theme that this competitor does not have at all. The gap is not
colour identity, it is SHAPE: NIVORA is flat, edged and rectangular where this is curved,
elevated and rounded, and NIVORA has no onboarding at all.

## The animations, in full — because they are smaller than they look

The user singled out the animations. Dumped from `res/anim/` and `res/animator/` with `aapt2`,
here is every one the app defines itself; everything else in those folders is stock AndroidX or
Material and is never referenced by the app's own code.

| Resource | What it does |
|---|---|
| `appear` | scale 0.5 → 1.0 about the centre, **500 ms**, overshoot interpolator, `fillAfter=true` |
| `slide_in` / `slide_out` | translateX 100%p → 0 / 0 → off-screen, `config_shortAnimTime` |
| `slide_up` / `slide_down` | translateY 100% → 0 / 0 → 100%, `config_mediumAnimTime` |
| `fade_in` / `fade_out` | alpha 0 → 1, cycle interpolator |
| `stay_still` | a deliberate no-op, paired with a slide so only ONE side of a transition moves |
| `flip_x` / `flip_y` | `rotationX` / `rotationY` 180° → 360° |
| `chevron_*_checked` | the expander arrow rotating |

**There is no Lottie, no motion layout, no shared-element transition, no choreography.** The
impression of polish comes from exactly two things: a 500 ms scale-from-half "pop" applied to
content as it lands, and the same slide-plus-stay-still pair applied consistently to every
single activity change. Consistency is doing all the work.

Two consequences for NIVORA:

1. This is cheap to beat. Flutter gives shared-axis and container transforms for free, and
   NIVORA already has a `lib/shared/motion/` layer.
2. **Do not copy the 500 ms.** NIVORA's own `theme_contrast_test.dart` holds motion inside a
   150–350 ms band, and that band is the better call — a half-second scale-in on every screen
   reads as sluggish once you have used it more than twice. Match the CONSISTENCY, not the
   duration.
