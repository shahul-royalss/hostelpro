import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome, SystemUiMode, SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/boot/retry_policy.dart';
import 'core/boot/startup.dart';
import 'core/auth/auth_controller.dart';
import 'core/config/env.dart';
import 'core/notify/push_service.dart';
import 'core/router/router.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'features/auth/email_verification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw under both system bars. Target SDK 36 enforces this on Android 15+ regardless; asking
  // for it explicitly makes older devices match, and NivoraTheme.systemBars (applied at the
  // app root below) is what keeps the bar icons legible on whichever ground is under them.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // The typeface is bundled (see pubspec.yaml), so nothing should ever be fetched. Turning
  // runtime fetching off makes that a guarantee rather than an intention: if a weight is ever
  // used without shipping its file, google_fonts throws in debug instead of quietly downloading
  // it in production. A first launch on a bad connection then still looks like Nivora.
  GoogleFonts.config.allowRuntimeFetching = false;

  _installErrorHandlers();

  // NOTHING IS AWAITED BEFORE THIS LINE, AND THAT IS THE POINT. Every await here is a frame the
  // app does not draw, and the window Android shows in the meantime is a flat #0B0D0F rectangle
  // with no logo, no text and no spinner — the owner's "completely black screen". See
  // core/boot/startup.dart for the whole argument; the short version is that the splash can
  // draw itself while initialisation runs behind it, and a startup failure is easier to render,
  // not harder, once there is already a frame on screen.
  runApp(const NivoraBoot());
}

/// Owns initialisation, and the two things that can come of it.
///
/// It sits ABOVE [ProviderScope] rather than inside it because the failure arm must depend on
/// nothing — no providers, no theme lookup, no network — since whatever it is reporting may be
/// the reason those are absent. The success arm hands the initialisation future down through
/// [supabaseReadyProvider], which is what stops anything touching `Supabase.instance` early.
class NivoraBoot extends StatefulWidget {
  const NivoraBoot({super.key});

  @override
  State<NivoraBoot> createState() => _NivoraBootState();
}

class _NivoraBootState extends State<NivoraBoot> {
  late Future<void> _ready;

  /// Set when initialisation failed. The raw message, kept for the screenshot somebody sends.
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _error = null;
    _ready = _initialise();
    // The future is handed to a provider and awaited there, but only once something watches it.
    // This keeps a failure in that gap from surfacing as an unhandled zone error; the arm that
    // actually shows the user anything is the setState inside [_initialise].
    _ready.ignore();
  }

  Future<void> _initialise() async {
    try {
      // Only the URL and the ANON key ever reach the client. The anon key is public by design —
      // it grants nothing on its own, because every table is behind row-level security. The
      // service-role key must never appear in this app; it is server-only and would hand any
      // decompiler full database access.
      await Supabase.initialize(
        url: Env.supabaseUrl,
        // Renamed from anonKey in supabase_flutter 2.17; same value, same guarantees.
        publishableKey: Env.supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          // Persisted to the platform keystore by supabase_flutter, which is what lets a warm
          // start reach the home screen without a network round trip.
          authFlowType: AuthFlowType.pkce,
        ),
      ).timeout(startupDeadline);
    } catch (e) {
      // Startup must never die silently. The first release build shipped without the INTERNET
      // permission (Flutter only adds it to the debug/profile manifests), so this call threw and
      // the process ended before drawing a frame — the app simply "did not open", with nothing
      // on screen to say why. It renders an explanation instead, and now a way to try again:
      // the commonest cause is transient, and an app whose only recovery is "kill it from the
      // task switcher" teaches people that it is broken.
      if (mounted) setState(() => _error = e.toString());
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return StartupFailure(error: error, onRetry: () => setState(_start));
    }
    return ProviderScope(
      // The ONE override in the app's real startup. Everything downstream that needs a live
      // Supabase client waits on this rather than assuming one exists.
      overrides: [supabaseReadyProvider.overrideWith((ref) => _ready)],
      // THE THIRTY-EIGHT SECONDS LIVED HERE. Riverpod's default retries a failed provider ten
      // times with backoff that sums to 38.2s, during which the splash, the 2FA screen and
      // every skeleton in the app stayed up for an answer that arrived in the first hundred
      // milliseconds. See core/boot/retry_policy.dart for what is and is not worth a second try.
      retry: nivoraRetry,
      child: const NivoraApp(),
    );
  }
}

class NivoraApp extends ConsumerStatefulWidget {
  const NivoraApp({super.key});
  @override
  ConsumerState<NivoraApp> createState() => _NivoraAppState();
}

class _NivoraAppState extends ConsumerState<NivoraApp> {
  @override
  void initState() {
    super.initState();
    _decideGlassBudget();
  }

  /// PORTRAIT ON PHONES, EITHER WAY ON TABLETS.
  ///
  /// Nothing in this app is designed sideways on a phone: the brow is a third of the screen's
  /// HEIGHT and the sign-in card is centred in what is left, so a landscape phone gives both
  /// about 360dp. Shipping a layout nobody drew is worse than not offering it. A tablet has the
  /// room, so it keeps the choice — and that is also where the width cap in TabSwap starts, so
  /// the two rules agree on what "big enough" means.
  ///
  /// ── THIS USED TO LIVE IN main(), AND IT DID NOTHING ────────────────────────────────────
  ///
  /// The first version read platformDispatcher.implicitView before runApp, guarded with
  /// `physicalSize > 0` because that size is not always populated before the first frame. On
  /// the emulator it was not, the guard skipped, and the app rotated exactly as before. The
  /// guard turned the feature into a silent no-op and the code still read as if it worked —
  /// I only found out by forcing the device to landscape and measuring the screenshot, which
  /// came back 2400x1080.
  ///
  /// didChangeDependencies is where the size is genuinely known, and it re-runs when the
  /// window changes — so a foldable opening flat drops the lock rather than keeping a phone
  /// rule on a tablet-sized screen.
  /// What was last asked of the platform, so the same request is not repeated.
  ///
  /// `MediaQuery.sizeOf` registers a dependency on the SIZE aspect alone, so this does not run
  /// when the keyboard opens or the padding changes — but it does run on every rotation, and on
  /// a foldable it runs on every fold. Each call crosses a platform channel. Remembering the
  /// answer makes the common case free and, more usefully, means the log shows a request only
  /// when the decision actually changed.
  bool? _lockedToPortrait;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    if (shortest <= 0) return;

    final portraitOnly = shortest < Breakpoints.medium;
    if (portraitOnly == _lockedToPortrait) return;
    _lockedToPortrait = portraitOnly;

    SystemChrome.setPreferredOrientations(
      portraitOnly
          // Both ways up: a phone in a car mount upside down is still a phone.
          ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
          : DeviceOrientation.values,
    );
  }

  /// Release builds never blur. Decided by a field report, not a heuristic.
  ///
  /// The first version of this gated BackdropFilter on screen resolution (skip above ~2.5MP),
  /// reasoning that more pixels means a costlier blur pass. A real device proved the heuristic
  /// BACKWARDS: the phones that hurt most are budget handsets with 720p screens and weak GPUs —
  /// which sat under the threshold and kept the most expensive effect in the design system
  /// running on the least capable hardware. The product owner's report from such a phone was
  /// "stuck, lag". No resolution number distinguishes a weak GPU from a strong one, and a
  /// device-model list rots, so release stops guessing: glass always renders as its opaque
  /// fallback, which was designed with IDENTICAL geometry precisely so this switch costs no
  /// layout shift, only the blur.
  ///
  /// Debug keeps real blur so the glass path stays exercised and designable. If blur ever
  /// returns to release, it must be behind a measured frame-time probe, not a spec sheet.
  void _decideGlassBudget() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fallback = !kDebugMode;
      if (fallback != Motion.glassFallback) {
        setState(() => Motion.glassFallback = fallback);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // THE COLD-START ARM OF EMAIL VERIFICATION, AND THE ONLY PLACE IT CAN LIVE.
    //
    // Tapping the emailed link opens this app from cold. By the time a session exists the user
    // is on their role home, NOT on the verify screen — and the verify screen was the only
    // caller of the re-check. So the proof GoTrue had already minted was never read, and the
    // "verify your email" banner sat there after the user had done exactly what it asked.
    // runOnceOnStartup() existed for this case and had zero call sites; this is it.
    //
    // Listening rather than reading in initState because a session is not resolved yet when
    // this widget is first built. The guard inside runOnceOnStartup makes it once per process.
    ref.listen(authControllerProvider, (previous, next) {
      final phase = next.value;
      if (phase is AuthSignedIn) {
        ref.read(emailVerificationRecheckProvider).runOnceOnStartup();
        // PUSH STARTS WITH THE SESSION, NOT WITH THE APP, and that ordering is the point.
        //
        // An FCM token is registered AGAINST A USER (public.push_devices.user_id), so there is
        // nothing to register before somebody has signed in — and asking for the notification
        // permission on a launch that ends at the sign-in screen would be asking a stranger.
        // The dialog therefore appears once the person is inside, where "we will tell you when
        // rent is due" is a sentence that means something.
        //
        // Fire and forget: every step inside start() is wrapped, and a phone that cannot
        // register is a phone that does not buzz — never one that cannot run the PG.
        unawaited(ref.read(pushServiceProvider).start());
      } else if (phase is AuthSignedOut) {
        // The token goes back, so the next person to hold this handset does not receive the
        // last person's rent reminders. One phone genuinely does pass between a warden and
        // their replacement.
        unawaited(ref.read(pushServiceProvider).stop());
      }
    });

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Nivora',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // BOTH SCHEMES, FOLLOWING THE OS. This was pinned to dark for one build, and the reason is
      // worth keeping: the light ColorScheme was a bare ColorScheme.fromSeed derivation and a
      // phone in light mode rendered it as cream-on-white with red boxes — not a Nivora screen.
      // Pinning was the right emergency call and the wrong permanent one; the owner switches
      // their phone between schemes and expects the app to follow.
      //
      // What changed is that light is now a DESIGNED scheme rather than a derivation: warm ivory
      // ground #FFF8F3, white cards, near-black warm ink #201B13, its own field fill, its own
      // semantic reds, and a filled button that is NOT the dark theme's cream — a cream button on
      // a cream page is not a button. Those pairings carry measured WCAG ratios in
      // theme.dart's comments and are asserted in test/theme_contrast_test.dart, which is what
      // makes shipping the light half safe now and unsafe before.
      theme: NivoraTheme.light(),
      // ── LIGHT ONLY, BY DECISION ────────────────────────────────────────────────────────
      //
      // This shipped as ThemeMode.system with a dark theme that is genuinely good — better
      // than the competitor's, which has no dark mode at all. The product owner has asked for
      // one appearance regardless of the phone's setting, and that is his call to make: a
      // product shown to clients on whatever handset is nearest should look the same on all of
      // them, and half the screenshots in a pitch deck coming back dark is a real cost.
      //
      // darkTheme is still WIRED rather than deleted. It costs nothing while themeMode pins
      // light, every one of its colours is still asserted by test/theme_contrast_test.dart, and
      // turning dark back on is then one word here rather than an archaeology exercise.
      darkTheme: NivoraTheme.dark(),
      themeMode: ThemeMode.light,
      builder: (context, child) {
        // Cap text scaling. Respecting the user's font size matters, but past ~1.4x a dense
        // operational screen stops being usable, so it is clamped rather than ignored.
        final mq = MediaQuery.of(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // ONE region at the root, following the theme: light status-bar icons over the dark
          // ground, dark ones over the ivory. Without this, every screen that draws its own
          // header instead of an AppBar — which is most of them — left Android's default dark
          // icons on a near-black ground. See NivoraTheme.systemBars.
          value: NivoraTheme.systemBars(Theme.of(context).brightness),
          child: MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.4),
            ),
            child: child!,
          ),
        );
      },
    );
  }
}

/// THE THREE HANDLERS FLUTTER LEAVES TO YOU, AND WHAT HAPPENED WITHOUT THEM.
///
/// Flutter has three separate error channels and, until this function existed, this app set
/// none of them. StartupFailure below covers exactly one case — initialisation throwing — and
/// every other failure fell through to the framework's defaults:
///
///   1. A throw inside build() painted [ErrorWidget], which in a RELEASE build is a grey
///      rectangle with no text at all. The owner's ask was "no crashes has to occur"; a screen
///      that silently becomes a grey block is worse than a crash, because a crash at least
///      tells you it happened.
///   2. A framework error printed to a console nobody on a phone can read.
///   3. An unhandled async error — a Future with no catch, a stream error — reached the engine
///      and TERMINATED THE PROCESS. The app simply vanishes from the screen.
///
/// None of these is caught by the guard()/AppFailure discipline the repositories use, because
/// that only covers awaited calls the code knew to wrap. This is the floor under everything
/// else.
///
/// ── DEBUG KEEPS THE RED BOX, ON PURPOSE ───────────────────────────────────────────────────
///
/// The red-and-yellow error box is one of the best diagnostics Flutter has, and replacing it in
/// development would trade a stack trace for a polite sentence at exactly the moment a stack
/// trace is what you want. The friendly panel is release-only.
void _installErrorHandlers() {
  // 1 — a throw inside build/layout/paint.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const _BrokenScreen();
  }

  // 2 — every framework error. presentError still runs, so debug behaviour is unchanged and
  // release still writes the detail to the platform log for `adb logcat` / Console.app.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  // 3 — errors that escape the framework entirely: an unawaited Future, a stream with no
  // onError. Returning TRUE is the whole point — it tells the engine the error is handled, so
  // the process is not torn down. Before this, one forgotten `await` anywhere in 183 files
  // could close the app on a warden mid-payment.
  PlatformDispatcher.instance.onError = (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'nivora'),
    );
    return true;
  };
}

/// What a user sees instead of a grey rectangle when one screen's build throws in release.
///
/// It says the app is still running and names the way out, because that is true: only the
/// subtree that threw is replaced, so the shell, the bottom bar and every other tab are intact
/// and one tap away. Hard-coded colours for the same reason [StartupFailure] uses them — this
/// widget can be built in a context where the thing that threw WAS the theme.
class _BrokenScreen extends StatelessWidget {
  const _BrokenScreen();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFF0B0D0F),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'This part did not load',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFF5F3EE)),
                ),
                SizedBox(height: 8),
                Text(
                  'The rest of Nivora is still working. Use the bar at the bottom to go to '
                  'another tab, and come back to this one in a moment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.4, color: Color(0xFFA2A6AB)),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Shown when the app cannot start at all. Deliberately depends on nothing — no theme, no
/// providers, no network — because whatever it is reporting may be the reason those are absent.
///
/// THE GROUND IS THE BRAND'S, hard-coded for the same reason the splash hard-codes it: the
/// window behind this is #0B0D0F (android/app/src/main/res), the app is dark-only, and this
/// screen used to paint a near-white #F6F8FC over it — the same flash the res/ files were
/// changed to remove, kept alive on the one screen nobody rehearses. The values are literals
/// rather than tokens because a theme lookup is a dependency and this widget has none.
class StartupFailure extends StatelessWidget {
  const StartupFailure({super.key, required this.error, this.onRetry});

  final String error;

  /// Runs initialisation again. A blank screen with no way forward is the thing this whole file
  /// is about; a failure with no way forward is the same bug wearing a sentence.
  final VoidCallback? onRetry;

  static const _ground = Color(0xFF0B0D0F);
  static const _ink = Color(0xFFF5F3EE);
  static const _secondary = Color(0xFFA2A6AB);
  static const _tertiary = Color(0xFF6F747A);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _ground,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Nivora could not start',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _ink)),
                const SizedBox(height: 8),
                const Text(
                  'This is usually a connection problem. Check your network and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: _secondary),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: _ink,
                      foregroundColor: _ground,
                    ),
                    child: const Text('Try again'),
                  ),
                ],
                const SizedBox(height: 20),
                // The raw message, small. A user will not read it; the person they send a
                // screenshot to will, and that is the difference between a bug report and a
                // guessing game.
                Text(error,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: _tertiary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
