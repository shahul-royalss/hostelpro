# Play Store graphic assets

Google Play will not let you publish a listing without an icon, a feature graphic and at
least two phone screenshots. All of them live in `public/store/` and are **generated**, by
one script, from files that are already in this repository:

```sh
node scripts/store-assets.mjs            # regenerate everything into public/store/
node scripts/store-assets.mjs --svg      # also dump the SVG sources to public/store/svg/
node scripts/store-assets.mjs --check    # verify what is on disk, generate nothing
```

The script exits non-zero if any asset fails its Play spec, so it doubles as the release
check. `docs/play-store.md` §5 lists this as a blocker; this file is the answer to it.

---

## 1. What exists

| File | Play slot | Spec | Actual |
|---|---|---|---|
| `public/store/icon-512.png` | App icon | 512 × 512 PNG, ≤ 1 MB | 512 × 512, RGB, **no alpha**, 5.9 KB |
| `public/store/feature-graphic-1024x500.png` | Feature graphic | 1024 × 500 PNG/JPEG, ≤ 15 MB | 1024 × 500, RGB, **no alpha**, 71.6 KB |
| `public/store/screenshots/01-owner-dashboard.png` | Phone screenshot 1 | PNG, 9:16 or 16:9, each side 320–3840 px | 1080 × 1920 (9:16), RGB, 143.6 KB |
| `public/store/screenshots/02-warden-fees.png` | Phone screenshot 2 | ” | 1080 × 1920, RGB, 179.2 KB |
| `public/store/screenshots/03-student-room-fees.png` | Phone screenshot 3 | ” | 1080 × 1920, RGB, 170.3 KB |
| `public/store/screenshots/04-manager-expenses.png` | Phone screenshot 4 | ” | 1080 × 1920, RGB, 163.6 KB |

Four screenshots — Play accepts between 2 and 8. The script refuses to pass if that count
ever leaves the range.

### About "32-bit PNG"

Play's help text still says *32-bit PNG* for the icon, which means 8 bits × RGBA. These
files are **24-bit RGB with no alpha channel**, which Play accepts and which is what you
actually want: Play composites the icon onto its own background and applies its own
rounded mask, so a transparent or pre-rounded icon either loses its corners twice or shows
the store's backdrop through the artwork. Square corners, fully opaque, is the safe answer.
The verifier asserts `channels === 3 && hasAlpha === false` rather than trusting it.

`public/icons/icon-512.png` (the PWA icon) is *not* the same file — it has the `rx="112"`
rounded corners baked in from `public/icons/icon.svg` and an alpha channel. Upload
`public/store/icon-512.png` to Play, not that one.

---

## 2. Where each one goes in Play Console

All of these are under **Grow → Store presence → Main store listing** for the app
`app.nivora.twa`.

1. **App icon** — *Graphics → App icon*. Upload `public/store/icon-512.png`.
2. **Feature graphic** — *Graphics → Feature graphic*. Upload
   `public/store/feature-graphic-1024x500.png`. This is the banner Play shows at the top of
   the listing and in promotional slots; some of those placements crop it, so nothing that
   matters sits outside an 11 % inset (x 112–912, y 130–375 of the 1024 × 500 canvas).
3. **Phone screenshots** — *Graphics → Phone screenshots*. Upload all four in filename
   order; the numeric prefixes are the order they should appear in the listing.

Tablet screenshots are a separate slot and are **not** generated here. Only fill them in if
you declare tablet support — an empty tablet slot is fine, a wrong-sized one is a rejection.

The short description (≤ 80 chars) and full description (≤ 4000 chars) are text fields in
the same form and are not part of this script.

---

## 3. How they are built

`scripts/store-assets.mjs` composes SVG and rasterises it with **sharp** (already a Next.js
dependency — `sharp` 0.35.3 with librsvg 2.62.3). Nothing is drawn by hand, so re-running
the script after a brand change re-cuts every asset consistently.

Sources it reads:

| Source | Used for |
|---|---|
| `public/icons/icon.svg` | The brand mark. The script extracts everything after the background `<rect>` and re-uses that markup verbatim — the house and the teal dot in the store icon are literally the app icon's paths, not a redraw. It throws if the extraction stops matching. |
| `tailwind.config.ts` | The palette. `C` at the top of the script is a transcription of `theme.extend.colors`; tailwind stays the source of truth. |
| `app/manifest.ts` | `#F6F4EF` ivory background / theme colour. |
| `node_modules/lucide-react` | Icon geometry. The script parses `__iconNode` out of the installed icon modules, so the wallet, bell and bed in the screenshots are the same paths React renders. |
| `db/seed.ts` + `db/schema.sql` | Every number in the screenshots (see below). |
| `app/**` | Every string in the screenshots — labels, captions, empty states, nav labels. |

### Determinism

Two consecutive runs produce byte-identical PNGs. That is deliberate: the reference date is
pinned (`TODAY = 2026-08-20`, `PERIOD = August 2026`) instead of using `new Date()`, so
regenerating the assets does not create a spurious diff every day. If you want the
screenshots to show a different month, change those two constants — every date, month chip
and "N entries in <month>" label is derived from them.

### Where the screenshot numbers come from

The app is behind a login and the TWA is portrait-locked, so these are not device captures:
they are the real mobile layouts redrawn to scale (360 CSS px viewport × 2.6). The numbers
are **computed**, not typed, from the seeded Sunrise Residency demo hostel in `db/seed.ts`,
using the same maths the app uses:

- 3 floors × 12 rooms × 3 beds = **36 beds**, 12 seeded students → occupancy **12 / 36 = 33 %**
- fee ledger for the period: 6 paid, 2 partial, 4 unpaid → **collected ₹50.2k**,
  **pending ₹33.8k**, **6 students due** (`students_unpaid` in `rpc_hostel_stats` counts
  `status <> 'paid'`, so partials are included)
- complaints where `status <> 'resolved'` → **3 open** (2 open + 1 in progress)
- expenses whose seeded day-offset lands inside the pinned month → **12 entries, ₹50,400**
- `₹50.2k` / `₹33.8k` / `₹7,000` are produced by re-implementations of `formatINRCompact`
  and `formatINR` from `lib/utils.ts`, so the rounding matches the app exactly

Change the seed and the screenshots change with it. Nothing in them is a marketing claim:
there are no testimonials, no ratings, no awards, and no feature that the app does not have.

### Fonts

The app uses Inter (`app/layout.tsx`, `next/font`). librsvg resolves fonts through the OS,
so the SVG asks for `Inter, 'Segoe UI', 'Noto Sans', Arial, sans-serif`. On a machine
without Inter installed — including this one — the assets render in Segoe UI. That is a
visual difference from the running app, not a spec failure. Install Inter locally before
regenerating if you want an exact match.

---

## 4. Verification

Every run re-opens each file with sharp and asserts the real metadata, then prints it:

```
$ node scripts/store-assets.mjs
brand mark read from public/icons/icon.svg (512x512 grid)
wrote public/store/icon-512.png
wrote public/store/feature-graphic-1024x500.png
wrote public/store/screenshots/01-owner-dashboard.png
wrote public/store/screenshots/02-warden-fees.png
wrote public/store/screenshots/03-student-room-fees.png
wrote public/store/screenshots/04-manager-expenses.png

─────────────────────────── verification ───────────────────────────
  file                                               size       format  channels  alpha  KB
  ─────────────────────────────────────────────────  ─────────  ──────  ────────  ─────  ─────
  public/store/icon-512.png                          512x512    png     3         no     5.9
  public/store/feature-graphic-1024x500.png          1024x500   png     3         no     71.6
  public/store/screenshots/01-owner-dashboard.png    1080x1920  png     3         no     143.6
  public/store/screenshots/02-warden-fees.png        1080x1920  png     3         no     179.2
  public/store/screenshots/03-student-room-fees.png  1080x1920  png     3         no     170.3
  public/store/screenshots/04-manager-expenses.png   1080x1920  png     3         no     163.6

  phone screenshots: 4 (Play accepts 2..8)

  All assets match the Play specs.
```

What is asserted, per file: exact pixel dimensions, PNG format, channel count and absence
of an alpha channel where Play wants opacity, file size against Play's per-slot limit, and
for screenshots that both sides fall inside 320–3840 px and the ratio is 9:16 or 16:9.

This caught a real bug during development. librsvg treats SVG user units as points, so
sharp's default `density: 96` silently rendered every asset 1.333× too large — a 683 × 683
"512 px" icon that Play would have rejected. The script now pins `density: 72` and resizes
explicitly, and the check is what makes that a guarantee rather than a coincidence.

`--check` runs only the verification, which is the useful form for CI or a release
checklist.

---

## 5. Notes and gaps

- **These files are served publicly.** Anything in `public/` is served from the site root,
  so the assets are reachable at e.g.
  `https://hostelpro-three.vercel.app/store/icon-512.png`. That is harmless (they are
  marketing material), it is convenient if Console ever wants a URL, and it costs about
  750 KB in the deployment. `.vercelignore` does not exclude them. If you would rather not
  ship them, add `public/store` to `.vercelignore` — the Play upload does not need the site.
- **Nothing here is wired into CI.** `.github/workflows/security.yml` does not run this
  script. `--check` is the hook to add if you want the assets gated on every push.
- **No tablet screenshots**, no TV/Wear assets, no promo video. Add them only if you list
  those form factors.
- **Not localised.** Play lets you upload a different graphic set per language; there is one
  set, in English.
- **The screenshots are compositions, not captures.** They are honest — real layouts, real
  copy, real seeded numbers — but if you later want true device captures, run the app on a
  phone against the seeded demo hostel and replace the four files. Keep the same names and
  `--check` keeps working.
