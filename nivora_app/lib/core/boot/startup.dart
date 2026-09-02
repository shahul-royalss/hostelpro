/// STARTUP — WHAT IS ON SCREEN BEFORE THE APP IS READY, AND WHO IS ALLOWED TO WAIT ON IT.
///
/// ── THE BLACK RECTANGLE THIS FILE EXISTS TO REMOVE ───────────────────────────────────────
///
/// `main()` used to `await Supabase.initialize()` BEFORE `runApp()`. Nothing about that call is
/// wrong; what was wrong is that the app drew no frame until it returned. Until Flutter's first
/// frame the screen belongs to Android, and android/app/src/main/res pins that window to a
/// SINGLE FLAT COLOUR — `@color/nivora_ground`, #0B0D0F, deliberately, so the handoff to the
/// splash is invisible. A window with no logo, no text and no spinner is invisible in the other
/// direction too: while it is up, the phone shows a completely black screen with only the
/// status bar on it. That is the owner's screenshot, exactly, and there is nothing in it to
/// diagnose because by construction there is nothing in it at all.
///
/// The awaited work is local — SharedPreferences, the keystore read, and the app_links platform
/// channel `initialize()` opens to catch a launch deep link — so on a healthy device it is
/// milliseconds. It is also UNBOUNDED: a platform channel that never replies holds the launch
/// window forever, and the app "does not open" with no crash and no log line. The same shape as
/// the splash hang that `resolveRedirect` was extracted to kill, one layer lower down.
///
/// ── SO THE ORDER IS INVERTED ─────────────────────────────────────────────────────────────
///
/// `runApp()` goes first and initialisation runs behind the frame it draws. Two things make
/// that safe rather than merely faster:
///
///  1. NOBODY MAY TOUCH `Supabase.instance` UNTIL [supabaseReadyProvider] SAYS SO. It throws
///     when the app is not initialised, so "start the UI early" without a gate would just move
///     the failure. Exactly one provider builds on the first frame — AuthController, through
///     the router's refresh listenable — and it awaits this before its first `_db`. Every other
///     `Supabase.instance` in the app is inside a provider body that no screen watches until a
///     session exists, which is strictly after this future completes.
///
///  2. A STARTUP FAILURE STILL RENDERS AN EXPLANATION. That guarantee was added when the first
///     release build shipped without the INTERNET permission, threw here and died before
///     drawing anything. It is not weakened by starting earlier: the failure now has somewhere
///     to be drawn, which is better than the old arrangement, where it raced the first frame.
///
/// The default below is an already-completed future, so a widget test that never initialises
/// Supabase — which is every widget test in this suite — is untouched by any of it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long the app waits for `Supabase.initialize()` before it stops waiting and says so.
///
/// Generous on purpose: everything behind it is local I/O, so a device slow enough to need
/// twenty seconds has a real problem and the person holding it deserves to be told that rather
/// than left in front of a black window. The point of the number is not its value, it is that
/// one exists — see the header, and test/startup_test.dart.
const startupDeadline = Duration(seconds: 20);

/// Completes when `Supabase.initialize()` has finished; fails when it could not.
///
/// Overridden in [main] with the real initialisation future. The default is "already ready",
/// which is the correct answer for every context that never initialises Supabase at all.
final supabaseReadyProvider = FutureProvider<void>((ref) async {});
