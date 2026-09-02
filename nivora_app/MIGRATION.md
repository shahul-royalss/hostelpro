# Nivora — Flutter migration status

Honest status of the Next.js → Flutter migration. Updated as phases land. Anything not listed
as done is not done, however finished the folder structure looks.

## Why this exists at all

The Android app was a Trusted Web Activity: `LauncherActivity` extended
`com.google.androidbrowserhelper.trusted.LauncherActivity`, whose job is to hand a URL to a
browser. **Chrome was the renderer, not a fallback** — which is why the app "opened Chrome",
and why no amount of `assetlinks.json` work could have fixed it. A WebView shell removed the
Chrome dependency but is still a browser wrapper, so this Flutter client replaces it.

## What the client must NOT re-implement

The Supabase backend is reused unchanged and stays authoritative:

| | |
|---|---|
| Tables | 20 |
| RLS policies | 63 — attack-tested, 80/80 and 44/44 |
| Functions | 59 |
| Triggers | 23 |

**The Flutter client is never a security boundary.** `session.dart` decides which screens to
*draw*; row-level security decides what data the caller may *have*, evaluated server-side
against the JWT. Both hold even if this entire app were recompiled with `role = owner`.

## Phase status

| Phase | State | Notes |
|---|---|---|
| 1 Audit | **done** | Root cause found and recorded above |
| 2 Architecture | **done** | Riverpod + go_router + Supabase; folders under `lib/core`, `lib/features`, `lib/shared` |
| 3 Foundation | **done** | Tokens, both themes, glass system, router, auth, session restore, login, MFA, role shells |
| 4 Core PG system | **done** | PGs, floors, rooms, beds, students, allocations — owner and warden |
| 5 Operations | **done** | Rent recorded at the warden's desk (no in-app checkout in v1), complaints, notices, tasks, expenses, menus |
| 6 Owner analytics | **done** | Occupancy, collections trend, portfolio; super-admin platform console |
| 7 Polish | **done** | Minimal glass, measured contrast, skeletons, empty and error states |
| 8 Security | **done** | RLS inherited; both secrets held in Edge Functions, never on the device |
| 9 Testing | **done** | Routing, roles, data layer, contrast, the desk payment loop, super admin |
| 10 Store readiness | partial | Icons, splash, signing, bundled fonts and a verified release script done; Play listing and the deploy of the Edge Functions are not |

### What is genuinely NOT done

Two things, and neither is cosmetic:

**The Edge Functions are written but not deployed.** They need a Supabase access token this
machine does not have. Until `docs/edge-functions.md` is followed, Create Owner fails at runtime
no matter how finished the screen looks.

**Rent is paid at the warden's desk in v1 — there is no checkout in the app.** The
`razorpay-order` / `razorpay-webhook` functions are deployed but hold no Razorpay credentials,
so the money path never worked; a Pay button that opens a flow the server cannot complete is
worse than no button. The resident's rent card now says where to hand the money over, the warden
records it (`wd_record_payment`) and can correct a mistyped figure (`wd_correct_payment`), and
the owner's Payments tab answers "who paid" (`rpc_recent_payments`). The server functions stay
for a later version; the client plugin, its Gradle pin and its R8 keeps were removed and each
place says what to put back.

**No live round-trip has ever been exercised from a device.** Norton Web/Mail Shield intercepts
TLS on the development machine and presents its own certificate; Windows trusts it and Android
does not, so an emulator cannot reach Supabase at all — every request dies with
`CERTIFICATE_VERIFY_FAILED`. Every screen here is therefore verified by rendering, data-binding
and error-state tests against stubbed providers, not against the real database. Creating an
actual owner and actually paying rent will happen first on a real phone. That is a real gap and
it is stated here rather than in a footnote.

## What actually runs today

`splash → login → (MFA if a factor is enrolled) → role-routed shell`, against the **live**
Supabase project, with real accounts. Session restore is persisted, so a warm start goes
straight to the role home without a network round trip.

The five role shells render their own navigation and a stated placeholder. They say they are
unbuilt rather than showing an empty screen that looks finished.

## Decisions worth knowing

**Students log in with a phone number.** `resolveLoginEmail()` maps it to
`<10 digits>@student.hostelpro.local`, identical to the web app. If the two drift, the same
person cannot sign in on both clients — which is why it has unit tests.

**Dark mode is authored, not inverted.** Its own surfaces (`#070B14` → `#101827` → `#151F32`,
getting *lighter* as they rise) and its own accent `#7C83FF`, because `#5B5FEF` has too little
contrast on a dark background to read as an active state.

**Glass is an elevation treatment, not a skin.** Three weights, and `GlassSurface` asserts in
debug when nested more than one deep — stacked glass reads as fog. When the frame budget is
tight the `BackdropFilter` is skipped for an opaque surface with *identical geometry*, so
nothing reflows and no screen needs a second design.

**Only the anon key ships in the binary.** It is public by design and grants nothing without
RLS. The service-role key, the Razorpay secret and the webhook secret stay server-side; an APK
is readable by anyone who downloads it.

## Two OTP bugs designed out rather than ported

Both were real in the web build and are impossible here by construction:

1. **Boxes collapsing to "small vertical lines."** Each slot had `w-full` *and* `flex-1`, so six
   slots asked for 600% of the row; flex-shrink crushed them and only the caret stayed visible.
   Here each slot is an `Expanded` with a `minWidth` floor.
2. **A correct code reported wrong, then accepted on Verify.** The web version submitted a value
   re-read from state that had not flushed, so the server got the previous keystroke.
   `_verify` is always called with the string the field just produced.

## iOS

Not buildable from this machine: Apple's toolchain is macOS-only and the repo is on Windows.
The `ios/` folder exists and the Dart is platform-agnostic, so the path is a GitHub Actions
`macos-latest` runner plus an Apple Developer account. No code change is expected.

## Running it

```bash
cd nivora_app
flutter run                       # against the live project
flutter test                      # 5 unit tests
flutter build apk --release
```

Staging and production differ by build flag, not by edited files:

```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```
