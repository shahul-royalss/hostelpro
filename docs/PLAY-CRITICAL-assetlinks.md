# CRITICAL — add the Play App Signing fingerprint before you trust the store build

**Symptom if you skip this:** the app installs from Play, opens, and shows a **browser address
bar across the top**. It stops being a TWA and becomes a Chrome tab with an icon. Reviewers and
users both notice. Nothing else about the app is wrong — only this file.

## Why the current file is not enough

`public/.well-known/assetlinks.json` currently lists **one** fingerprint:

```
24:23:97:46:89:5A:54:63:86:F1:87:4B:1D:B5:F5:31:3D:02:DA:99:DB:E4:72:F5:45:19:23:58:1F:FB:64:65
```

That is the **upload key** — the key `android/` signs with locally, held at
`C:\Users\shahu\.hostelpro-keys\hostelpro-upload.p12`. It is correct for a locally-built APK.

It is **not** the key users get. **Play App Signing is mandatory for all new apps.** Google strips
your signature on upload and re-signs the delivered APKs with a *different* key that Google holds.
Digital Asset Links verification compares the certificate of the **installed** app against this
file. Installed app is signed by Google's key → this file must contain Google's fingerprint too.

## The fix — 5 minutes, after the first upload

You cannot do this before uploading: the app signing key does not exist until Play creates it.

1. Play Console → your app → **Test and release → Setup → App signing**.
2. Copy the SHA-256 under **App signing key certificate** (colon-separated hex, 32 pairs).
3. Add it to the array in `public/.well-known/assetlinks.json` — **keep the upload key too**, so
   locally-built debug installs keep working:

```json
"sha256_cert_fingerprints": [
  "24:23:97:...:64:65",
  "<PASTE THE PLAY APP SIGNING SHA-256 HERE>"
]
```

4. Commit, push, and let Vercel deploy. Confirm it is live:

```bash
curl -s https://hostelpro-three.vercel.app/.well-known/assetlinks.json
```

5. Verify Google agrees, using the *package name* and the *Play* fingerprint:

```bash
curl -s "https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://hostelpro-three.vercel.app&relation=delegate_permission/common.handle_all_urls"
```

6. Reinstall the app from Play (not the local APK) and confirm **no address bar**. That is the only
   test that actually proves it, and it can only be done after a release reaches a track.

## Order of operations

```
build AAB  →  create app in Play Console  →  upload AAB  →  read App signing SHA-256
    →  add it to assetlinks.json  →  deploy the site  →  install from Play  →  verify no URL bar
```

Deploying the site is step 6, not step 1. If you publish to production before adding the
fingerprint, every user who installs during that window sees the address bar until the site
deploys and Android re-checks (which it does not do on a fixed schedule — a reinstall forces it).
