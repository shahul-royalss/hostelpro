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
| 4 Core PG system | **not started** | PGs, buildings, floors, rooms, beds, students, allocations |
| 5 Operations | **not started** | Payments, complaints, maintenance, notices, notifications |
| 6 Owner analytics | **not started** | Occupancy, revenue, collections, portfolio |
| 7 Polish | partial | Glass, motion and dark mode exist; skeletons and empty states pending |
| 8 Security | inherited | RLS carries over; client-side privilege tests still to write |
| 9 Testing | partial | 5 unit tests pass; widget and integration tests pending |
| 10 Store readiness | **not started** | Icons, splash, signing, listings |

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
