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
