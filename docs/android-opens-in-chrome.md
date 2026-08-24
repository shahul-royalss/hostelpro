# "It opens in Chrome" — what is actually happening, and how to fix it

## First, the part that is not a bug

**A TWA always runs on Chrome's engine.** That is what a Trusted Web Activity *is* — your web app
running inside Chrome, with Chrome's UI removed. There is no version of this where Chrome is not
involved. Wrapping a website is the whole approach.

So the question is never "is Chrome involved" — it is **"is the address bar showing?"**

| What you see | Meaning |
|---|---|
| Fullscreen, no address bar, your icon in the task switcher | Working correctly |
| A white/grey bar at the top showing `hostelpro-three.vercel.app` | Verification failed — fix below |
| Chrome opens with tabs, your other tabs visible | You opened a **link**, not the app icon |

## What I verified from here

The configuration is correct — this is not a code problem:

```
Google's own verification API (the one Android calls):
  https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://hostelpro-three.vercel.app
  -> package_name  app.nivora.twa
  -> sha256        24:23:97:46:89:5A:54:63:86:F1:87:4B:1D:B5:F5:31:3D:02:DA:99:DB:E4:72:F5:45:19:23:58:1F:FB:64:65

The installed APK's signing certificate:
  apksigner verify --print-certs -> 24239746895a546386f1874b1db5f5313d02da99dbe472f5451923581ffb6465

AndroidManifest in the built APK:
  autoVerify=true, host="hostelpro-three.vercel.app", DEFAULT_URL present, asset_statements present
```

Those match. So the failure is **on the device**, and it is almost always one of three things.

## The three causes, most likely first

### 1. An older build is still installed (most likely)

Earlier builds used the package `app.hostelpro.twa`. Android caches domain-verification results
**per package**, and a stale or failed result sticks. If the old app is still there — or if you
installed a NIVORA build before `assetlinks.json` was updated — the verification never re-ran.

```
Settings → Apps → look for BOTH "HostelPro" and "NIVORA" → uninstall every one you find
Then install NIVORA-1.0.0.apk again, with mobile data or Wi-Fi ON.
```

Network at install time matters: Android fetches `assetlinks.json` during verification. Installing
offline fails it silently.

### 2. Chrome is disabled, outdated, or not the default browser

The TWA needs a browser that supports it (Chrome 72+). If none is available,
`androidbrowserhelper` falls back to a Custom Tab — which is Chrome **with a toolbar**. That is
exactly the symptom.

```
Play Store → Chrome → Update (if offered)
Settings → Apps → Chrome → make sure it is Enabled
Settings → Apps → Default apps → Browser app → Chrome
```

### 3. Verification genuinely failed and Android is caching it

Check the real state. On a computer with the phone connected and USB debugging on:

```bash
adb shell pm get-app-links app.nivora.twa
```

You want `verified` next to the domain. If it says `unverified` or `1024`, force a re-check:

```bash
adb shell pm verify-app-links --re-verify app.nivora.twa
adb shell pm get-app-links app.nivora.twa
```

## The fastest way to a clean demo, if you are short on time

Skip the APK entirely and **install the PWA**:

1. Open `https://hostelpro-three.vercel.app` in Chrome on the phone
2. Menu (⋮) → **Add to Home screen** / **Install app**
3. Launch it from the home screen

This runs standalone — no address bar, own icon, own task-switcher entry — and it does **not**
depend on Digital Asset Links at all, so none of the above can break it. The manifest already
declares `display: standalone`, which is what makes this work.

It is not a substitute for the Play listing, but it is a reliable way to show the app.

## Worth knowing

The Android app is a **shell**. It loads `https://hostelpro-three.vercel.app` live. Every web
change — dashboards, payments, styling — reaches the phone the moment it deploys, with no new
APK and no Play review. You only need a new build for Android-side changes: the package id, the
launcher icon, the splash screen, or the target SDK.
