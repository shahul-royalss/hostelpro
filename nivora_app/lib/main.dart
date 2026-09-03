import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode, SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/boot/startup.dart';
import 'core/auth/auth_controller.dart';
import 'core/config/env.dart';
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
      if (next.value is AuthSignedIn) {
        ref.read(emailVerificationRecheckProvider).runOnceOnStartup();
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
      darkTheme: NivoraTheme.dark(),
      themeMode: ThemeMode.system,
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
