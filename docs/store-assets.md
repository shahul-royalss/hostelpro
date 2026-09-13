# Play Store graphic assets

Google Play will not let you publish a listing without an icon, a feature graphic and at
least two phone screenshots.

**What to upload for `com.srnivora.app` is in §2.** The icon is `public/store/icon-512.png`. The
feature graphic is `dist/NIVORA-feature-graphic.png` (a byte-identical copy sits in
`dist/store-listing/`), and the phone and 10-inch tablet screenshots and the listing text are in
`dist/store-listing/`. `scripts/store-assets.mjs` neither produces nor checks any of the `dist/`
files; of the upload set it produces and checks only the icon (below). The
feature graphic is written into `dist/` by `nivora_app/scripts/make-feature-graphic.py` (lines
16-17), and `nivora_app/test/_storeshot.dart` defines the phone and `tablet10` canvases the
screenshots are rendered at (lines 77-86). Neither asserts Play's spec, so the dimensions in §1
were read from the PNG headers.

The script below generates the icon, and also the feature graphic and screenshots of the
**retired** web-app (TWA) listing, all into `public/store/`:

```sh
node scripts/store-assets.mjs            # regenerate everything into public/store/
node scripts/store-assets.mjs --svg      # also dump the SVG sources to public/store/svg/
node scripts/store-assets.mjs --check    # verify what is on disk, generate nothing
```

The script exits non-zero if any file in `public/store/` fails its Play spec. For the current
listing that makes it a check of the icon only. It is not a release check for the upload.

---

## 1. What exists

> **Retired for upload on 2026-09-13, except the icon.** The feature graphic and six screenshots in
> this table were made for the retired web-app (TWA) listing, package `app.nivora.twa`. The listing
> for `com.srnivora.app` uploads these instead: `dist/NIVORA-feature-graphic.png` (1024 × 500, a
> different file from the one below; a byte-identical copy is in `dist/store-listing/`), and from
> `dist/store-listing/` four phone screenshots `phone-{resident,warden,manager,owner}.png` at
> 1080 × 1920 and four 10-inch tablet screenshots `tablet10-{resident,warden,manager,owner}.png` at
> 1440 × 2560. All nine are 24-bit RGB with no alpha, according to their PNG headers on 2026-09-13.
> The listing text is in `dist/store-listing/` too, and tracked in git under `docs/store-listing/`.
> `public/store/icon-512.png` is still the icon to upload.
>
> This script neither produces nor checks anything in `dist/`, and `dist/` is ignored by git. The
> table below and §3–§5 document the retired set and how it was built; **§2 is the current upload
> guide**.

| File | Play slot | Actual |
|---|---|---|
| `public/store/icon-512.png` | App icon | 512 × 512, 32-bit RGBA, alpha fully opaque, 103.5 KB |
| `public/store/feature-graphic-1024x500.png` | Feature graphic | 1024 × 500, 24-bit RGB, no alpha, 70.8 KB |
| `public/store/screenshots/01-student-rent-due.png` | Phone screenshot 1 | 1080 × 1920 (9:16), 24-bit, 174.6 KB |
| `public/store/screenshots/02-pay-rent.png` | Phone screenshot 2 | 1080 × 1920, 24-bit, 248.7 KB |
| `public/store/screenshots/03-payment-received.png` | Phone screenshot 3 | 1080 × 1920, 24-bit, 201.8 KB |
| `public/store/screenshots/04-owner-dashboard.png` | Phone screenshot 4 | 1080 × 1920, 24-bit, 146.5 KB |
| `public/store/screenshots/05-warden-fees.png` | Phone screenshot 5 | 1080 × 1920, 24-bit, 181.6 KB |
| `public/store/screenshots/06-manager-expenses.png` | Phone screenshot 6 | 1080 × 1920, 24-bit, 166.0 KB |

Six screenshots — Play accepts between 2 and 8, and wants at least 4 at 1080p to be
eligible for promotional placement. The script refuses to pass if that count ever leaves
the range, and it deletes any PNG in `screenshots/` that is not in its own list, so a
renamed or retired panel cannot linger next to the ones you are about to upload.

**Ordering is deliberate.** Play shows the first two or three inline, so the rent payment
flow leads. Screens 1–3 are one continuous story about one resident and one figure:
Priyanka Singh owes ₹6,500 for Aug 2026, pays it, gets the receipt.

### Alpha on the icon, no alpha anywhere else — the one genuinely confusing line

[Play's spec](https://support.google.com/googleplay/android-developer/answer/9866151) asks
for different things per slot, and it is easy to apply the wrong one to the wrong slot:

| Slot | What Play asks for | What this repo writes |
|---|---|---|
| App icon | *32-bit PNG **with** alpha*, ≤ 1024 KB | RGBA, alpha = 255 on every pixel |
| Feature graphic | A JPEG, or a PNG with 24-bit colour and **no** alpha channel | RGB, no alpha channel at all |
| Screenshots | The same format rule as the feature graphic | RGB, no alpha channel at all |

32-bit **means** RGBA — 8 bits × 4 channels — so the icon must carry an alpha channel.
But Play separately rejects icons that are actually transparent, because it composites its
own shape and shadow behind the artwork. Exactly one file satisfies both: RGBA whose alpha
channel is 255 everywhere. That is what gets written, and the verifier asserts *both*
halves — four channels **and** a measured minimum alpha of 255, read back out of the
encoded pixels with `sharp().stats()`, so a single stray transparent pixel fails the run.

The icon also keeps **square corners**. Play applies its own rounded mask; a pre-rounded
icon loses its corners twice.

`public/icons/icon-512.png` (the PWA icon) is a *different* file with different padding.
Upload `public/store/icon-512.png` to Play, not that one.

---

## 2. Where each one goes in Play Console

All of these go on the **Main store listing** page for the app `com.srnivora.app`, under **Store
presence** in Play Console's menu. Console renames its menu groups from time to time; if the page is
not there, search Console for "Main store listing".

1. **App icon** — *Graphics → App icon*. Upload `public/store/icon-512.png`.
2. **Feature graphic** — *Graphics → Feature graphic*. Upload
   `dist/NIVORA-feature-graphic.png`. This is the banner Play shows at the top
   of the listing and in promotional slots, and some of those placements crop it.
3. **Phone screenshots** — *Graphics → Phone screenshots*. Upload the four
   `dist/store-listing/phone-*.png` files. Their names carry no order, so set it in Console.
4. **10-inch tablet screenshots** — *Graphics → 10-inch tablet screenshots*. Upload the four
   `dist/store-listing/tablet10-*.png` files.

> This section used to name the app `app.nivora.twa`, point at the `public/store/` feature
> graphic and six screenshots, and say that tablet screenshots were not generated and the
> tablet slot should stay empty. All of that described the retired web-app listing. Tablet
> screenshots now exist.

The short description (≤ 80 chars) and full description (≤ 4000 chars) are text fields in
the same form. Paste the short description from `dist/store-listing/short-description.txt`.
For the full description, paste `dist/store-listing/full-description-without-push.txt` until a
push notification has been seen arriving on a real phone. `full-description.txt` is the same
text plus a NOTIFICATIONS section; switch to it only then. Tracked copies of all three files
are in `docs/store-listing/`.

---

## 3. How they are built

> **Historical: the retired TWA listing.** §3, §4 and §5 describe how `scripts/store-assets.mjs`
> builds the `public/store/` set for the retired web-app (TWA) listing, package `app.nivora.twa`.
> Of that set only `public/store/icon-512.png` is uploaded for `com.srnivora.app`. For the current
> upload, see §2 and [`play-submission-pack.md`](./play-submission-pack.md) §1.1.

`scripts/store-assets.mjs` composes SVG and rasterises it with **sharp** (already a Next.js
dependency — sharp 0.35.3 / libvips 8.18.3). Nothing is drawn by hand, so re-running the
script after a brand change re-cuts every asset consistently.

### The brand mark is pixels, not a redraw

This is the part that changed most recently and the part most worth understanding. Earlier
revisions re-drew the logo by extracting paths out of `public/icons/icon.svg`. They no
longer do. The artwork is embedded as a `data:` URI and composited by the same rasteriser
that draws everything else:

| Source | Used for |
|---|---|
| `public/brand/play-icon-512.png` | The store icon, essentially verbatim — resized only if it is not already 512, then flattened and given an opaque alpha channel. |
| `public/brand/logo-square-1024.png` | The small rounded badge on each screenshot's caption band. |
| `public/brand/nivora-logo.png` | The full lockup — mark above the drawn NIVORA wordmark — on the feature graphic. |

Embedding the drawn lockup is why the feature graphic no longer sets "NIVORA" as live
`<text>`. Typed text would render in whatever font the build machine happens to have, and
this repo **cannot** load webfonts to fix that — the CSP has no `font-src` grant. The drawn
letterforms are correct and machine-independent.

If `public/brand/` has not been generated, the script falls back to trimming the
transparent margin off `nivoralogo.png` at the repo root with sharp. That fallback is
never silent: the run log names the file it used for each piece.

Everything else it reads:

| Source | Used for |
|---|---|
| `tailwind.config.ts` | The palette. `C` at the top of the script is a transcription of `theme.extend.colors`; tailwind stays the source of truth. `C.amber` (`#F4A438`) is sampled from the lit window in the logo. |
| `app/manifest.ts` | `#F6F4EF` ivory background / theme colour. |
| `node_modules/lucide-react` | Icon geometry. The script parses `__iconNode` out of the installed icon modules, so the wallet, bell and bed in the screenshots are the same paths React renders. |
| `db/seed.ts` + `db/schema.sql` | Every number in the screenshots. |
| `app/**`, `components/payments/**` | Every string in the screenshots. |

### Determinism

Two consecutive runs produce byte-identical PNGs, verified by comparing SHA-256 across
runs — the verification table prints a short hash per file for exactly this reason. The
reference date is pinned (`TODAY = 2026-08-20`, `PERIOD.iso = 2026-08`) instead of calling
`new Date()`, so regenerating does not create a spurious diff every day. There is no
`Date.now()` anywhere in the script. To move the screenshots to a different month, change
those two constants — every date, month chip and "N entries in \<month\>" label derives
from them.

### `formatPeriodMonth` renders **"Aug 2026"**, not "August 2026"

`lib/utils.ts` formats every period label as `format(d, "MMM yyyy")` — an abbreviated
month. Every period label in the product goes through it: the warden fees subtitle, the
expense table description, the pay sheet, the receipt. Earlier revisions of this script
wrote out "August 2026", which the product renders nowhere. `PERIOD.label` is now the
abbreviated form and carries a comment saying why.

### The payment panels

Screens 1–3 come from `app/student/page.tsx`, `components/payments/pay-rent-sheet.tsx`,
`components/payments/payment-receipt.tsx` and `components/payments/receipt-printer.tsx`.
Every string on them is quoted from those files — "Pay rent", "Amount due",
"`<period>` · paid securely through Razorpay.", "Card details are handled by Razorpay —
never by this app.", "Payment received", "Your fee ledger has been updated.", "TOTAL PAID",
"THANK YOU". The provenance comments in the script name the file each one came from.

Two deliberate choices worth recording:

- **No test-mode chip.** The sheet renders "Test mode — no real money will move." only when
  the server reports `testMode`. A store listing must not advertise a sandbox.
- **The payment ID is pinned and visibly fake** — `pay_S4mNIVORAdemo1`. It has Razorpay's
  shape (`pay_` + 14 characters) so the receipt looks right, but it spells "NIVORAdemo" so
  nobody mistakes it for a traceable reference. A random ID would also break determinism.

The resident on those panels is chosen by **rule, not by name**: the first student in the
seeded ledger who still owes the whole month. Room, floor, fee and amount due are all read
back out of that ledger row, so if `db/seed.ts` changes, the panels change with it. The
warden fees panel (screenshot 5) independently shows the same person as `UNPAID ₹6,500`,
because both are reading the same computed ledger.

### Where the screenshot numbers come from

The app is behind a login and the TWA is portrait-locked, so these are not device captures:
they are the real mobile layouts redrawn to scale (360 CSS px viewport × 2.6). The numbers
are **computed**, not typed, from the seeded Sunrise Residency demo hostel in `db/seed.ts`,
using the same maths the app uses:

- 3 floors × 12 rooms × 3 beds = **36 beds**, 12 seeded students → occupancy **12 / 36 = 33 %**
- fee ledger for the period: 6 paid, 2 partial, 4 unpaid → **collected ₹50.2k**,
  **pending ₹33.8k**, **6 students due**
- complaints where `status <> 'resolved'` → **3 open** (2 open + 1 in progress)
- `₹50.2k` / `₹33.8k` / `₹6,500` are produced by re-implementations of `formatINRCompact`
  and `formatINR` from `lib/utils.ts`, so the rounding matches the app exactly

Nothing in them is a marketing claim: there are no testimonials, no ratings, no awards, and
no feature the app does not have.

**One string is not verbatim.** `db/seed.ts` interpolates the raw `period_month` into the
fee-reminder announcement, so the seeded text literally reads "Fees for 2026-08…".
Announcements are free text written by the hostel in production, so the panel shows the
period the way a person would type it ("Aug 2026"). That deviation is commented in the
script at the point it happens.

### Fonts

The app uses Inter (`app/layout.tsx`, `next/font`). librsvg resolves fonts through the OS,
so the SVG asks for `Inter, 'Segoe UI', 'Noto Sans', Arial, sans-serif`, and the receipt
slip — which is `font-mono` in the product — asks for a monospace stack. On a machine
without Inter installed, including this one, the assets render in Segoe UI. That is a
visual difference from the running app, not a spec failure, but it does mean **the byte
hashes above are only reproducible on a machine with the same fonts**. Install Inter
locally before regenerating if you want an exact match to the app.

---

## 4. Verification

> **Historical, like §3:** this verifies the `public/store/` set only. It does not verify the
> `dist/` files the current listing uploads (§2); their dimensions and colour types were read from
> the PNG headers on 2026-09-13.

Every run re-opens each file with sharp and asserts the real metadata, then prints it:

```
$ node scripts/store-assets.mjs
brand artwork
  icon      public/brand/play-icon-512.png (512x512 → 512x512)
  mark      public/brand/logo-square-1024.png (1024x1024)
  lockup    public/brand/nivora-logo.png (trimmed to 1024x663, aspect 1.544)

wrote public/store/icon-512.png
wrote public/store/feature-graphic-1024x500.png
wrote public/store/screenshots/01-student-rent-due.png
... etc

─────────────────────────── verification ───────────────────────────
  file                                              size       format  depth   alpha   KB     sha256
  ────────────────────────────────────────────────  ─────────  ──────  ──────  ──────  ─────  ────────────
  public/store/icon-512.png                         512x512    png     32-bit  opaque  103.5  1e809950b088
  public/store/feature-graphic-1024x500.png         1024x500   png     24-bit  none    70.8   16f20062581c
  public/store/screenshots/01-student-rent-due.png  1080x1920  png     24-bit  none    174.6  bf14bf368bb6
  public/store/screenshots/02-pay-rent.png          1080x1920  png     24-bit  none    248.7  35374b06114c
  public/store/screenshots/03-payment-received.png  1080x1920  png     24-bit  none    201.8  63ca0bee6d75
  public/store/screenshots/04-owner-dashboard.png   1080x1920  png     24-bit  none    146.5  2237e97208a4
  public/store/screenshots/05-warden-fees.png       1080x1920  png     24-bit  none    181.6  a72f8556e092
  public/store/screenshots/06-manager-expenses.png  1080x1920  png     24-bit  none    166.0  09cc1c9bc0e5

  phone screenshots: 6 (Play accepts 2..8)

  All assets match the Play specs.
```

What is asserted, per file: exact pixel dimensions; PNG format; channel count; for the icon
that it is 4-channel **and** that its measured minimum alpha is 255; for the other two that
there is no alpha channel at all; file size against Play's per-slot limit; and for
screenshots that both sides fall inside 320–3840 px, that the long side is no more than
twice the short side, and that the ratio is 9:16 or 16:9.

This caught a real bug during development. librsvg treats SVG user units as points, so
sharp's default `density: 96` silently rendered every asset 1.333× too large — a 683 × 683
"512 px" icon that Play would have rejected. The script now pins `density: 72` and resizes
explicitly, and the check is what makes that a guarantee rather than a coincidence.

`--check` runs only the verification, which is the useful form for CI or a release
checklist.

---

## 5. Notes and gaps

> **Historical, like §3 and §4:** these notes are about the retired `public/store/` set.

- **These files are served publicly.** Anything in `public/` is served from the site root,
  so the assets are reachable at e.g. `https://hostelpro-three.vercel.app/store/icon-512.png`.
  That is harmless (they are marketing material) and convenient if Console ever wants a
  URL, but the set now costs about **1.26 MB** in the deployment, up from ~750 KB, because
  there are six screenshots instead of four. They are static files in `public/`, so they do
  **not** affect the JS bundle or First Load JS. If you would rather not ship them, add
  `public/store` to `.vercelignore` — the Play upload does not need the site.
- **Nothing here is wired into CI.** `.github/workflows/security.yml` does not run this
  script. `--check` is the hook to add if you want the assets gated on every push.
- **No tablet screenshots in this set**, and no TV/Wear assets or promo video. The current
  listing does have tablet screenshots: four 10-inch ones in `dist/store-listing/` (§2).
- **Not localised.** Play lets you upload a different graphic set per language; there is one
  set, in English.
- **The screenshots are compositions, not captures.** They are honest — real layouts, real
  copy, real seeded numbers — but if you later want true device captures, run the app on a
  phone against the seeded demo hostel and replace the files. Keep the same names and
  `--check` keeps working.
- **The receipt printer is drawn as a still.** `components/payments/receipt-printer.tsx`
  animates the slip feeding out and the cutter firing; screenshot 3 draws its settled
  state. The lower lip is dropped 4 px relative to the stylesheet so the dark slit stays
  visible after downsampling — at the browser's scale the CSS leaves only ~2 px of mouth
  exposed, which resamples into a hairline and makes the machine read as two gold bars.
