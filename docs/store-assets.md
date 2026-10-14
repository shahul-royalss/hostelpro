# Play Store graphic assets

Google Play will not let you publish a listing without an icon, a feature graphic and at least two
phone screenshots. Everything to upload for `com.nivorasr.app` is in `dist/store-listing/`, which
git ignores. Measured from the PNG headers on 2026-10-14:

| File | Play Console slot | Actual |
|---|---|---|
| `apnivaas-icon-512.png` | Graphics → App icon | 512 × 512, RGBA, alpha 255 on every pixel |
| `apnivaas-feature-graphic.png` | Graphics → Feature graphic | 1024 × 500, RGB, no alpha |
| `apnivaas-phone-{resident,warden,manager,owner}.png` | Graphics → Phone screenshots | 1080 × 1920, RGB |
| `apnivaas-tablet10-{resident,warden,manager,owner}.png` | Graphics → 10-inch tablet screenshots | 1440 × 2560, RGB |

They all go on the **Main store listing** page, under **Store presence** in Play Console's menu.
The screenshot file names carry no order, so set it in Console.

- The feature graphic is written by `apnivaas_app/scripts/make-feature-graphic.py`, which also keeps
  a copy in the repository at `public/store/feature-graphic-1024x500.png`.
- `public/store/icon-512.png` is the repository copy of the icon. `public/icons/icon-512.png` is the
  website's PWA icon, a different file with different padding; do not upload that one.
- The screenshots are rendered from the app's own screens by `apnivaas_app/test/_storeshot.dart`,
  which writes them to `build/store-shots/`.
- The short and full descriptions are tracked in `docs/store-listing/`.

## Alpha on the icon, no alpha anywhere else

[Play's spec](https://support.google.com/googleplay/android-developer/answer/9866151) asks for
different things per slot, and it is easy to apply the wrong one to the wrong slot:

| Slot | What Play asks for | What these files are |
|---|---|---|
| App icon | *32-bit PNG **with** alpha*, ≤ 1024 KB | RGBA, alpha = 255 on every pixel |
| Feature graphic | A JPEG, or a PNG with 24-bit colour and **no** alpha channel | RGB, no alpha channel at all |
| Screenshots | The same format rule as the feature graphic | RGB, no alpha channel at all |

32-bit **means** RGBA — 8 bits × 4 channels — so the icon must carry an alpha channel. But Play
separately rejects icons that are actually transparent, because it composites its own shape and
shadow behind the artwork. Exactly one kind of file satisfies both: RGBA whose alpha channel is 255
everywhere.

The icon also keeps **square corners**. Play applies its own rounded mask; a pre-rounded icon loses
its corners twice.

## What was removed

The generator for the old web-wrapper listing (`scripts/store-assets.mjs`), the six screenshots it
made under `public/store/screenshots/`, and the old logo files it read were removed on 2026-10-14,
together with the wrapper itself.
