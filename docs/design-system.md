# Design system: Forest & Cream

This is the design system of the Apnivaas app (`apnivaas_app/`). It replaces the "liquid
glass" document that described the violet and indigo look. The full measured spec it was
built from is Appendix A of [`apnivaas-1.3-build-plan.md`](apnivaas-1.3-build-plan.md). This
page describes what is actually in the code: where each piece lives, the rules it keeps, and
the API that screens are built from.

The website keeps its own token system in `app/globals.css` and `tailwind.config.ts`. The old
document that described it is in git history, at commit `40731c8`.

| File | Holds |
| --- | --- |
| `lib/core/theme/tokens.dart` | Every colour, space, radius, size, stroke, motion and shadow constant. Also the semantic inks (`context.tones`) and the domain enum. |
| `lib/core/theme/typography.dart` | The two typefaces, the TextTheme slots, and the extra text roles (`context.textRoles`). |
| `lib/core/theme/theme.dart` | `ApnivaasTheme.light()` (the live theme), `.dark()`, and the status-bar styles. |
| `lib/shared/clay/` | The clay icon registry and the new-look widget kit. Import it all with `package:mobile/shared/clay/clay.dart`. |
| `lib/shared/glass/`, `brow*.dart`, `aurora.dart`, `beam_card.dart`, `dashboard.dart`, `meter.dart` | The older shared widgets, restyled with their APIs unchanged so screens not yet reskinned already look right. |

---

## 1. Principles

- **Every visual constant is a token.** Features never write a colour, radius, duration or
  size literal. When a legacy token name was kept, its value changed but its meaning did not.
  That is how screens nobody has touched moved to the new look on their own.
- **Shapes take canonical colours; text takes resolved ones.** `ApnivaasColors.success` and
  the other canonical tones are for dots, rails and chart marks. Text uses
  `context.tones.resolve(tone)`, which returns the ink measured for the current theme.
- **The unprefixed Material role names on `ApnivaasColors` are the dark values.** These are
  names like `primary`, `onSurface` and `outline`. Light painting that has no context uses the
  brand names (`forest`, `cream`, `card`, `ink`, `inkMuted`). Widgets should read
  `Theme.of(context).colorScheme` or `context.tones`.
- **Resting cards are flat.** A card is its fill plus a hairline. Shadows are kept for things
  that really sit above the page: the tab bar, a sheet or dialog, a selected or dragged item,
  and the one FAB. Nothing blurs.
- **No decorative motion.** Nothing loops and nothing ticks after a change has landed. Under
  reduce motion every transition is instant.
- **Sentence case, minimum 11sp, tabular figures for numbers that refresh.** The only
  capitals left are the small state tags (`StateBadge`, `ToneSurface`'s status word,
  `DashboardBand`, `GlassStatCard`'s label). Screens and their tests read those in capitals.
- **Every ratio quoted in a comment is asserted** by `test/theme_contrast_test.dart` or
  `test/brow_header_test.dart`.

## 2. Colour

### Brand

| Token | Hex | Use |
| --- | --- | --- |
| `forest` | `#174E43` | Primary: the filled button, links, focus, selection, the hero tile. 9.36:1 on the card. |
| `forestDeep` / `forestHigh` | `#10392F` / `#1F6150` | The header gradient's darkest and lightest stops. Header inks are measured on `forestHigh`. |
| `leaf` | `#3F7F68` | Graphic green. It may be used as text only on the card, because it fails on cream. |
| `sage` | `#7A9684` | Decoration only. |
| `mist` | `#DCE8DF` | Tonal tiles, the nav pill, avatar discs, the Mist banner. |
| `cream` | `#F6F2EA` | The page ground (`scaffoldBackgroundColor`). |
| `card` | `#FFFDF9` | Cards, sheets, the tab bar, input fill. This is `colorScheme.surface`. |
| `gold` | `#E2AE4A` | A fill on forest only: the unread dot, the hero progress bar, the stars. It is never used on cream (1.99:1 there). |
| `ink` / `inkStrong` / `inkMuted` | `#1C2B26` / `#3D4A44` / `#55655E` | Primary text, labels, secondary text (6.06:1 on the card). |
| `well` | `#EEF4EF` | The quick-action well and inner blocks (`colorScheme.surfaceContainer`). |
| `cardBorder` / `hairline` / `controlBorder` | `#ECE4D8` / `#EFE8DC` / `#8F8679` | Card edge (decorative), divider, control border (3.53:1, for WCAG 1.4.11). |

### Status

The canonical values (`success #3C8A5C`, `warning #986A10`, `error #C8443B`, `info #3F76AD`,
`textMuted #6E7D76`) are for shapes. The light text inks are `successInk #256B45`,
`warningInk #8A5A00`, `errorInk #B3261E` and `infoInk #2C5D8A`. Each one clears 4.5:1 on a
10% chip of itself over the ground, the card and the well. The tightest is warning, at
4.64:1.

Status mapping:
- paid, resolved, occupied: success
- due, pending, expiring: warning
- overdue, failed, refused: error
- refund, new: info
- draft, sample, inactive: neutral

A status is always a word, never colour alone. A chip never sits on a surface tinted with
its own tone.

### Domains

`ApnivaasDomain` (money, rooms, people, complaints, notices, food, security) keeps `.tone`
and `.icon`. The violet, teal and saffron domain hues are gone: rooms, people and food fold
into the brand. What kind of thing something is now comes from its clay icon
(`domainClayIcon(domain)`), so colour can stay reserved for status.

### Header and banner inks

On the header gradient, measured on its lightest stop:
- title: white, 7.28:1
- greeting: `headerGreeting #BFE0CC`, 5.11:1
- captions: `headerSub #CFE0D4`, 5.29:1
- search placeholder: `headerPlaceholder`, 4.65:1 on the pill

The gold task banner has its own inks (`bannerTitle` 10.34:1, `bannerBody` 6.79:1) and a
dark set (`bannerGradientDark`, `bannerTitleDark`, `bannerBodyDark`).

### Dark

The dark scheme is built and tested but switched off. `main.dart` pins `ThemeMode.light`.
Its values are a ground of `#0D1613`, a card of `#15221D`, a raised surface of `#1B2B25` and
a primary of `#86C9A9`. The header gradient and the hero tile look the same in both themes.

## 3. Type

The fonts are bundled and declared as families in `pubspec.yaml` `fonts:`. There are seven
static files in `google_fonts/`, each the exact file google_fonts 8.2.1 would fetch, checked
by sha256. Nothing is fetched at runtime.

- **Outfit** (500, 600, 700) is used for headings and figures. It has no ₹ glyph, so every
  Outfit style falls back to Manrope.
- **Manrope** (400, 500, 600, 700) is used for everything a person reads.

| Slot | Style | Job |
| --- | --- | --- |
| `displayLarge` / `headlineLarge` | Outfit 28/32 700, tabular | Hero figure |
| `displaySmall` | Outfit 22/28 600 | Screen title |
| `headlineMedium` | Outfit 22/28 700, tabular | Stat value |
| `titleLarge` | Outfit 20/26 600 | Section heading |
| `headlineSmall` | Outfit 18/24 600, tabular | Card heading |
| `titleMedium` | Manrope 14/20 700 | List row title |
| `titleSmall` | Manrope 13/18 700, tabular | Figure in a row, field label |
| `bodyLarge` / `bodyMedium` / `bodySmall` | Manrope 15/22, 13/18, 12/16 | Body, supporting text, meta |
| `labelLarge` / `labelMedium` / `labelSmall` | Manrope 15/20, 12/16, 11/14, all 700 | Buttons, tile and tab labels, counts |

`context.textRoles` adds:
- `cta`: Outfit 17/22 600
- `tileTitle`: Outfit 17/22 600
- `heroHeadline`: Outfit 24/28 600
- `dateNumeral`: Outfit 19/22 600, tabular
- `fieldValue`: Manrope 15/22 500
- `formSection`: Outfit 15/18 600
- `statValue`: Outfit 28/32 700, tabular

Build one-off styles with `ApnivaasType.outfit(size, lineHeight, weight, color)` or
`ApnivaasType.manrope(...)`.

## 4. Space, shape, size and motion

- **Space**: `hair 2`, `xxs 4`, `tight 6`, `xs 8`, `sm 12`, `md 16` (dashboard gutter),
  `lg 20` (form gutter), `xl 24`, `xxl 32`, `xxxl 40`, `huge 48`.
- **Radii**: `control 14` (inputs, chips, the search pill), `button 16`, `buttonLarge 18`,
  `card 20`, `well 22`, `surface 24` (stat tiles, list groups, banners), `hero 28`,
  `sheet 28` (top corners), `header 30` (bottom corners), `pill 999`. Each has a
  `BorderRadius` constant (`rControl`, `rSurface`, `rHeaderBottom`, and so on).
- **ClaySize**:

  | Size | Use |
  | --- | --- |
  | 34 / 36 | Nav icon, off / on |
  | 46 | List leading icon |
  | 54 | Quick action |
  | 56 | Stat tile |
  | 72 | Banner, compact empty state |
  | 78 | Hero tile |
  | 96 | Empty state |
  | 128 | Persona art |
  | 184 | Sign-in hero art |

- **Other sizes**: `IconSize` covers Material glyphs from 12 to 32. `AvatarSize` is 44 or 50
  for the header and 46 in a list. `Strokes` gives hairline 1, control 1.5 and focus 2.
- **Motion**: `press 100ms`, `fast 150ms`, `base 240ms`, `slow 340ms`, `exit 200ms`. The
  curves are `enter` (easeOutCubic), `leave`, `move`, and `emphasis` (a slight overshoot, used
  only for the nav pill and the persona card). `skeletonPulse` is 1200ms.
- **Shadows**: `level1` and `level2` are empty. `lift`, `bar`, `level3` and `glow` are
  forest-tinted and apply to the light theme only.
- **Breakpoints**: `compact 360`, `medium 600`, `expanded 768`, `maxContentWidth 720`.

## 5. Clay icons

There are 54 glossy 3D clay renders in `assets/clay/`. They total 585 KB as WebP with alpha
(the source PNGs are 4.1 MB). Feature and nav icons are 192px, role art is 320px, and the
brand mark is 256×186. `ClayIcons` names every file, and `ClayIcons.all` is checked against
the folder by `test/clay_icons_test.dart`.

`ClayIcon(asset, {size, semanticLabel, greyscale, opacity})`:
- It is decorative unless it is given a label.
- It decodes at the size it is drawn.
- If the file cannot load, it falls back to a Material glyph in the brand ink.

The rules:
- Never tint clay. The one exception is `greyscale`, for an unselected tab with no off-art.
- Always seat clay on a surface: a well, a tile, a card or a Mist disc. It never sits bare on
  cream or on the forest header. Role art is the exception.
- No words in any image.

## 6. The widget kit (`lib/shared/clay/`)

| Widget | What it is for |
| --- | --- |
| `AppHeader` | The forest header. It has a gradient, static dot stars, 30dp corners, and light status icons through `ApnivaasTheme.onForest`. It takes strings and resolves its own inks. Its slots are `leading` (`HeaderAvatar`, `HeaderBackButton`), `title` / `greeting` / `subtitle`, `onTitleTap` (the PG switcher), `actions` (`HeaderBell`, `HeaderIconButton`) and `bottom` (`HeaderSearchPill`). Anything in a slot inherits white through `ForestInk`. |
| `ClayNavBar` + `ClayNavDestination` | The bottom tab bar. It has the same API as NavigationBar (`destinations`, `selectedIndex`, `onDestinationSelected`). A selected tab shows its clay icon on a Mist pill with a forest label. An unselected tab shows its off-art, or the icon in grey, with a muted label. It supports count and dot badges. It is 72dp at 1.0x plus the safe inset, and grows to at most 77dp. |
| `StatTile`, `StatCarousel` | A figure, its label, and a clay icon. Styles are `plain`, `hero` (forest, at most one per screen) and `tonal` (a Mist link tile). The carousel becomes a two-column wrap from 1.6x text on phones narrower than 400dp. |
| `QuickActionGrid`, `QuickActionTile` | A clay icon in a 64dp well with a label of up to two lines. Columns follow width and text size: 4, then 3, then 2 side by side. |
| `ListGroup`, `ListRow`, `ListRowCard`, `ListRowAmount`, `InitialsDisc` | Rows of at least 70dp. The leading slot is a clay icon or initials. The words form one semantics node, and the trailing control is its own target. On narrow or large-text screens the trailing control wraps below the words. |
| `SectionHeader` | A sentence-case heading at page, card or form size. It can carry a "View all" link or any trailing widget. |
| `StatusChip`, `CountBadge` | A status word in a 10% tint pill. The count badge is error-red. |
| `PillButton` | A 36dp capsule with a 48dp target. It is outlined, or filled for the one action in a banner. |
| `EmptyState` | A clay icon on a Mist disc, a title, one sentence and one action. `.error(message, onRetry)` is the failure variant, and `compact` is the in-card size. |
| `Skeleton`, `SkeletonPulse`, `ListSkeleton`, `TileSkeleton`, `QuickActionsSkeleton` | A single 1.2s pulse per group. It stops when hidden, holds still under reduce motion, and forms one live region per group. |
| `ActionBanner` | The gold task banner, at most one per screen. It drops its art before the words fall under 180dp. |
| `InfoBanner`, `InfoNote` | A calm explanation on Mist, and a one-sentence note on the neutral fill. |
| `showApnivaasSheet`, `SheetTitle` | `showGlassSheet` with a heading: card fill, 28dp corners, the grip, and the forest scrim. |
| `PressScale` | The shared press-down scale. |

## 7. The older shared widgets

These keep their APIs and paint the new look:
- **`GlassSurface`, `FlatSurface`, `GlassCard`**: a card with a hairline.
- **`ToneSurface`, `DomainCard`**: an opaque 10% tint.
- **`StateCard`, `StateBody`, `StateBadge`**: an in-card empty state. The `EmptyArt`
  constants now draw their clay icon.
- **`NoticeBanner`, `DomainIcon`, `DomainButton`, `AccountAvatar`**: restyled in place.
- **`GlassHeader`**: plain, it is a cream bar with a hairline. With `onBrow`, it is the
  forest header, through `BrowHeaderFrame`.
- **`BrowTitleBlock`, `BrowText`**: use the forest header's inks and type.
- **`BrandBrow`**: paints the header backdrop behind the auth screens.
- **`AuroraField`**: now a flat ground.
- **`BeamCard`**: a static card with no loop.
- **`ProportionMeter`**: draws on the warm track.

## 8. Accessibility checklist for a screen

- Contrast is AA: 4.5:1 for body text, 3:1 for large text and UI. Use the inks above and do
  not mix new ones.
- Every tap target is at least 48dp. Every icon-only button has a semantics label.
- Test at 360dp and 320dp, at 1.0x, 1.3x and 2.0x text. Heights are minimums, not fixed.
  Only single figures and nav labels may scale down to fit.
- Loading shows a skeleton. Empty shows an `EmptyState` with a clay icon and one helpful
  sentence. An error gives an honest sentence and a retry only where retrying can help.

## 9. Tests

| Test | Covers |
| --- | --- |
| `theme_contrast_test.dart` | Every token pairing, the component themes, and the font files. |
| `brow_header_test.dart`, `brow_test.dart` | The header inks, the static header, and the legacy brow. |
| `clay_icons_test.dart` | The registry against the bundle and the WebP headers. Images are never decoded. |
| `clay_widgets_test.dart` | The tab bar, empty state, stat tile, header, list row, banners and skeletons, for semantics and fit. |
| `responsive_test.dart` | Every shell and the auth screens across 320 to 800dp and 1.0x to 2.0x. The bottom bar must be taller at 1.4x than at 1.0x and at most 88dp, whether it is NavigationBar or ClayNavBar. |
| `colour_and_motion_test.dart`, `illustration_assets_test.dart` | The tinted surfaces, the first-run art, and the entrance. |
