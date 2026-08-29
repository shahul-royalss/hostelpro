import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/router/router.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The typeface is bundled (see pubspec.yaml), so nothing should ever be fetched. Turning
  // runtime fetching off makes that a guarantee rather than an intention: if a weight is ever
  // used without shipping its file, google_fonts throws in debug instead of quietly downloading
  // it in production. A first launch on a bad connection then still looks like Nivora.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Only the URL and the ANON key ever reach the client. The anon key is public by design —
  // it grants nothing on its own, because every table is behind row-level security. The
  // service-role key must never appear in this app; it is server-only and would hand any
  // decompiler full database access.
  // Startup must never die silently. The first release build shipped without the INTERNET
  // permission (Flutter only adds it to the debug/profile manifests), so this call threw and the
  // process ended before drawing a frame — the app simply "did not open", with nothing on screen
  // to say why. Now any startup failure renders an explanation instead of a black rectangle.
  try {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      // Renamed from anonKey in supabase_flutter 2.17; same value, same guarantees.
      publishableKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        // Persisted to the platform keystore by supabase_flutter, which is what lets a warm
        // start reach the home screen without a network round trip.
        authFlowType: AuthFlowType.pkce,
      ),
    );
  } catch (e) {
    runApp(_StartupFailure(error: e.toString()));
    return;
  }

  runApp(const ProviderScope(child: NivoraApp()));
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
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Nivora',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: NivoraTheme.light(),
      darkTheme: NivoraTheme.dark(),
      // Follows the OS. Dark mode is authored, not inverted — see NivoraTheme.
      themeMode: ThemeMode.system,
      builder: (context, child) {
        // Cap text scaling. Respecting the user's font size matters, but past ~1.4x a dense
        // operational screen stops being usable, so it is clamped rather than ignored.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.4),
          ),
          child: child!,
        );
      },
    );
  }
}


/// Shown when the app cannot start at all. Deliberately depends on nothing — no theme, no
/// providers, no network — because whatever it is reporting may be the reason those are absent.
class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Nivora could not start',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                const SizedBox(height: 8),
                const Text(
                  'This is usually a connection problem. Check your network and reopen the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF667085)),
                ),
                const SizedBox(height: 20),
                // The raw message, small. A user will not read it; the person they send a
                // screenshot to will, and that is the difference between a bug report and a
                // guessing game.
                Text(error,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF98A2B3))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
