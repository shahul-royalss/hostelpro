# What NIVORA actually looks like today — measured, not remembered

Built from HEAD (`6ce31c8`) as a debug APK, installed on the `nivora_test` AVD, screenshotted in
both themes. Files: `before-nivora-light.png`, `before-nivora-dark.png`. The competitor's
equivalent is `competitor-login.png`.

**A trap worth recording:** the build already on the emulator was from 29 August, versionCode 1,
eight days and many commits stale. It showed a clean grey screen with an indigo button and I
almost drew conclusions from it. It is not what HEAD renders. Everything below is HEAD.

## Light theme — this is the problem, and it is worse than the competitor

The sign-in screen renders as **a beige card on a beige ground with a dark mustard button**.

- Ground `#FFF8F3` with a barely-visible lilac wash at the top — the `AuroraField` from commit
  1f05275, which claims "a purple gradient with two pulsing radial glows". At the intensity it
  is set to, on a light ground, it is not visible as purple at all.
- The card is cream `#F1E7D9`-ish on that ground. Card and ground are the same family and only
  the shadow separates them.
- The "Sign in" button is `#79590C` — dark bronze. That is `NivoraColors.lightPrimary`, which is
  `ColorScheme.fromSeed(seedColor: #C9A96E)` output. Nobody chose it; a quantiser did.
- "Forgot your password?" is the same bronze.

Every colour on the screen is one warm brown. This is the **same failure the user identified in
the competitor** — peach and brown, low chroma, dated — except NIVORA's is less deliberate,
because the competitor at least picked its browns and NIVORA derived them from a seed.

`tokens.dart` is honest about this in its own comments: *"nobody designed it… The honest
recommendation that goes with it is `ThemeMode.dark`."* But `main.dart:188-190` ships
`themeMode: ThemeMode.system`, so on any phone set to light — which is most phones — this is
the product.

**This is the single thing to fix.** It is not a matter of taste; it is a screen where the
brand colour is an accident.

## Dark theme — competent, austere, and unfinished

Near-black ground, dark card, cream filled button, gold link. It reads as deliberate and it is
better than anything in the competitor, which has no dark theme at all. Three real gaps:

1. **The aurora and the beam are nearly invisible.** The beam shows as a faint gold trace on the
   card's right edge; the two pulsing glows do not read. Effort is being spent on effects that
   do not survive contact with the screen.
2. **The card is dark-on-dark.** Ground `#0B0D0F` against card `#111417` is a 1.05:1 separation
   carried entirely by a `#292E33` hairline.
3. **55% of the screen is empty.** Both themes put a card in the middle of a void. The
   competitor fills its top third with a curved coloured hero and a logo, and that is most of
   why its screen looks finished and NIVORA's looks like a form.

## The scoreboard, honestly

| | NIVORA light | NIVORA dark | PG Manager |
|---|---|---|---|
| Has a designed palette | **no** | yes | yes, a weak one |
| Brand visible before login | no | barely | yes, immediately |
| Uses the top third of the screen | no | no | yes |
| Corner radius on cards | small | small | 20dp everywhere |
| Coloured ground | no | no | yes, a gradient |
| Dark theme exists | — | yes | **no** |
| Onboarding | **none** | **none** | four pages |
| Contrast enforced in CI | yes | yes | no |

NIVORA wins on rigour and loses on presence. The redesign has to keep the first and buy the
second.

---

# After

Same device, same emulator, HEAD at the end of the redesign. Files: `after-signin-light.png`,
`after-signin-dark.png`, `after-onboarding-1.png`, `after-onboarding-3.png`,
`after-owner-light.png`, `after-owner-dark.png`, `after-warden-light.png`,
`after-superadmin-light.png`.

The signed-in shots are rendered by `test/_shot.dart` rather than photographed, because those
screens are behind a login. Icons show as squares in those two — the test runner stubs the icon
font — so glyphs were checked on the device instead, where they render normally.

| | before | after |
|---|---|---|
| Light-theme brand | `#79590C`, a quantiser's bronze | `#6C4AA5`, chosen and measured |
| Light-theme depth | card, bar and sheet all `#FFFFFF` | a real three-rung ramp |
| `NivoraDomain.security` in light | gold at **2.24:1** on a white card | the brand, 6.64:1 |
| Card corner | 12dp | 16dp (screen 20dp) |
| Primary CTA | 12dp rectangle | pill |
| Field height | ~50dp | ~58dp |
| Top third of sign-in | empty | the brow, with the card riding its seam |
| Signed-in header | flat bar, 3 of 5 roles undecorated | the brow, all five |
| Onboarding | none | four pages |
| Contrast enforced in CI | 86 tests | 89, and the light group now asserts the opposite of what it did |
