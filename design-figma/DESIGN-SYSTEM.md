# NIVORA — the design system, extracted from the owner's Figma

Source: Figma file `8qkhZArLAz9KVOIiWF8ZTG` ("Untitled"), 19 `screen-*` frames, read 2026-08-30.
Values below are copied from `get_design_context` output on `4:947` (screen-student-dashboard) —
the file defines NO Figma variables, so these are the raw literals the designer actually used.

**This supersedes `design-stitch/`.** That folder holds the Stitch project the app was restyled
from earlier today: navy-black `#0b1326` with a VIOLET primary `#d0bcff` and mint `#4edea3`.
The owner has since pointed at Figma as the source. The two are both dark and otherwise share
almost nothing — different black, different accent, different type stack.

## Why the change is worth making

The Stitch primary `#d0bcff` is Material 3's stock dark-theme purple — the colour Flutter
generates when no one picks one. The Figma palette is a deliberate brand: neutral near-black,
warm cream text, gold accent. It reads as designed rather than defaulted.

## Two things in the file that are NOT the design

1. `screen-admin-dashboard` (`4:1369`) is LIGHT — white ground, dark text. Every other Nivora
   screen is dark. Treated as a stale exploration; the admin dashboard is built dark like the rest.
2. The file also contains generic UI-kit frames — `Social feed`, `Ecommerce`, `Booking`,
   `Checkout`, `Chat`, `Dashboard`, `Activities` (node ids `2:*`). Not Nivora. Ignore them.
   The Nivora screens are the `4:*` range, all named `screen-…`.

## Colour

| Role | Hex | Where |
|---|---|---|
| background | `#0b0d0f` | the page ground |
| surface (card) | `#111417` | rent card, notice items |
| surface raised | `#171a1e` | room card, icon buttons |
| outline / hairline | `#292e33` | every card border, dividers, avatar discs |
| on-surface | `#f5f3ee` | primary text — warm cream, NOT pure white |
| on-surface secondary | `#a2a6ab` | supporting text, roommate names |
| on-surface tertiary | `#6f747a` | CAPS labels, meta lines, timestamps |
| accent (gold) | `#c9a96e` | emphasis: "3 Sharing", chart lines, brand dot |
| warning (amber-gold) | `#d5a64c` | due/expiring badges — border at full, fill at 10% |
| filled button | bg `#f5f3ee` / text `#0b0d0f` | the primary CTA is CREAM, not gold |

The primary action being cream-on-black rather than a saturated colour is the single most
distinctive decision in this design. Do not "fix" it to gold.

Status colours (green positive / amber expiring / red expired) appear on the admin and owner
screens; sample them per-screen rather than inventing them here.

### The domain layer — colour as wayfinding

Added 2026-09-03, on the owner's brief that the app should read like a Google app: colourful,
tonal, recognisable. The Figma palette above is untouched — every hex is still pinned by
`test/theme_contrast_test.dart` — and the brand's one loud object is still the cream button.
What was added is the OTHER job colour does in a well-made product: not "what state is this
in" but "what kind of thing is this". Gmail is red, Calendar is blue, Keep is yellow, and none
of those means error, info or warning. In NIVORA the saffron icon at the head of a row means
"this is the menu", on every screen, always.

| Domain | Canonical | Dark ink | Light ink | Covers |
|---|---|---|---|---|
| money | `#42825F` (= success) | `#5FAE82` | `#33654A` | rent, fees, payments, expenses, subscriptions |
| rooms | `#8566BA` | `#997FC5` | `#6C4AA5` | floors, rooms, beds, a PG as an object |
| people | `#35817E` | `#3F9995` | `#296562` | residents, staff, roommates, guardians |
| complaints | `#976F23` (= warning) | `#D5A64C` | `#75561C` | complaints and tasks — open work |
| notices | `#5477AD` (= info) | `#718EBB` | `#415C88` | notices, announcements |
| food | `#AB6528` | `#C9772F` | `#864F1F` | the weekly menu |
| security | `#C9A96E` (= accent) | — | — | home, the account, the platform |

Three hues are new (rooms, people, food). They were DERIVED, not picked, by the same method
that produced the semantic inks: each canonical is a hue of the app's muted register taken to
the lightness that maximises its worst 3:1 case across all eight surfaces of both themes
(worst 3.50–3.52, the figures success/warning/error already land on); each ink is that
canonical moved in lightness by the MINIMUM that clears 4.5:1 plain on every surface of its
theme and on a 10% chip of itself. The method was checked by re-deriving the shipped inks
from their Figma seeds — it lands within one RGB point of every one — and the test pins the
minimality: one step back towards the canonical, and the contract fails.

**The rule that keeps this from becoming a rainbow.** Domain colour lives on ICONS, ACTIONS
and AVATARS. Status colour lives on SURFACES and FIGURES. They occupy different objects, so
they never compete on the same pixel: an unpaid rent card is a red `ToneSurface` — state wins
the surface — and the money-domain green appears only on the wallet glyph in its corner. A
domain tint on a whole surface (`DomainCard`) is allowed at most once per screen, on the card
that is the screen's subject, and never on anything that carries a status.

The furniture, in `lib/shared/glass/glass.dart`: `DomainIcon` (the tinted icon container that
opens a row or a section — the most recognisable piece of a Google app), `DomainButton` (a
neutral control with the glyph and label in the destination's colour), `DomainCard`, and
`avatarToneFor(name)` — a stable colour per person from a hash of their name, the way Google
Contacts does it, so a list of strangers becomes a list of people you can tell apart.
`NivoraDomain` in `tokens.dart` is the enum and carries the rule in its doc comment.

### Where it landed, and the two things review changed

Applied across all five roles: list rows and section headings open with a `DomainIcon`; dashboard
shortcuts are `DomainButton`s in their destination's colour; identity avatars take a colour from
the name; the selected bottom-nav destination and its pill take the tab's domain, with the same
mapping in every shell (Home and Overview gold, residents teal, rooms violet, payments green,
complaints and tasks amber, notices blue, menu saffron). Exactly one tinted `DomainCard` per
screen, and only three screens earn one: the resident's "Today's food" (saffron) and "Your room"
(violet), and the manager's menu editor (saffron). Not one cream `FilledButton` was demoted —
"Pay", "Record payment", "Post a notice" and "Create owner & hostel" all stay the design's one
loud object.

An adversarial design review then changed two decisions, and both are worth recording because
both were the rule catching its own implementation:

**`DomainButton` lost its tonal fill.** It began as Material's `FilledButton.tonal` in the
domain's tint — which put domain colour on a SURFACE, the half of the rule that belongs to
status. On the warden's home that produced four tinted buttons directly beneath four
status-tinted stat tiles: seven hues in one screenful, and two of them collided outright, an
amber "Resolve complaint" sitting under an amber "3 complaints" where the same colour meant "the
complaints area" above and "there is open work" below. The fill is now neutral and the colour
lives in the glyph and the label. That is also the more Google-like shape — a coloured icon on a
neutral row is what Settings, Drive and Gmail draw — and it leaves a tinted surface meaning
exactly one thing again.

**The avatar palette lost its status hues.** `avatarToneFor` first hashed a name across six
tones, three of which (`success`, `warning`, `info`) are states. The same `Avatar` widget carries
a status tone on several screens — the warden's fee ledger passes the fee tone, the roster passes
active/on-leave, the desk sheets pass amber and blue outright — and on the screens that pass
nothing, the hash chose. So a resident whose *name* hashed to amber wore the exact disc that
means "on leave" on the list two taps away. The palette is now the three domain hues that are not
also states, and `test/theme_contrast_test.dart` hashes four thousand names to prove no status
colour can ever come out of it.

## Type — Inter only

One family. Weights used: Regular 400, Semi Bold 600, Bold 700, **Extra Bold 800**.

| Token | Size / weight | Use |
|---|---|---|
| hero | 32 / 800 | the one big figure (₹8,500) |
| title | 16 / 700 | card titles, wordmark |
| body | 13 / 400–600 | list rows, buttons |
| label-caps | 12 / 600 UPPERCASE | section labels |
| meta | 11 / 400 | timestamps, sub-labels |
| chip | 10 / 600 | badges, avatar initials |

**Inter is already bundled** (Regular/Medium/SemiBold/Bold). Extra Bold 800 is NOT — either add
the file to `google_fonts/` and `pubspec.yaml`, or render the hero at 700. Do NOT let
`google_fonts` fetch it at runtime: `allowRuntimeFetching` is false by deliberate decision, and a
missing weight silently renders at 400. Plus Jakarta Sans becomes unused if this lands.

## Shape and spacing

Radius: 14 screen · 12 card · 8 small card / button / icon button · 4 badge · 12 avatar pill.
Padding: 16 card and screen · gaps 20 between sections, 16/12/8/6/2 within.
Header 56 high with a bottom hairline; status bar 36; icon button 32 square.

## Screens in the file

signin · create-password (has a strength indicator) · dashboard · wizard-1 · wizard-2 ·
owner-dashboard · owner-properties-staff · warden-dashboard · warden-students-list ·
warden-room-management · student-dashboard (x2 variants) · payment-history · complaint-form ·
manager-dashboard · meal-editor · admin-dashboard · **subscription-expired** ·
**empty-error-skeleton**

The last two matter: `subscription-expired` is the read-only state the app already models, and
`empty-error-skeleton` specifies the empty / error / skeleton-loading treatments the owner asked
for — a card with a 12px caps tag, a centred glyph, a title, a support line, and one button.

## The rule that has not changed

Every name, figure and date in these frames is invented — "Arjun K.", "₹8,500", "Room 204",
"3 failed login attempts on Owner (ID 892)". None of it may reach a real screen. Every value the
app shows comes from a provider reading the real database.
