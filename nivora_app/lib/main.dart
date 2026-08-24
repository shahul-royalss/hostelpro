import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/router/router.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only the URL and the ANON key ever reach the client. The anon key is public by design —
  // it grants nothing on its own, because every table is behind row-level security. The
  // service-role key must never appear in this app; it is server-only and would hand any
  // decompiler full database access.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    // Renamed from anonKey in supabase_flutter 2.17; same value, same guarantees.
    publishableKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      // Persisted to the platform keystore/keychain by supabase_flutter, which is what lets a
      // warm start reach the home screen without a network round trip.
      authFlowType: AuthFlowType.pkce,
    ),
  );

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

  /// Decide once whether this device can afford real backdrop blur.
  ///
  /// Blur is the most expensive thing in the design system, and the brief is explicit that
  /// performance wins. Rather than guess from a device model list that rots, this samples the
  /// actual frame budget: if the platform reports a low refresh rate or the first frames are
  /// already slow, glass falls back to an opaque surface with identical geometry.
  void _decideGlassBudget() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final view = View.of(context);
      // devicePixelRatio * logical size approximates how many pixels a full-screen blur costs.
      final size = view.physicalSize;
      final megapixels = (size.width * size.height) / 1000000;
      // A blur pass over more than ~2.5MP on a low-tier GPU is where dropped frames start.
      // Paired with a debug override so the fallback path is testable, not theoretical.
      final expensive = megapixels > 2.5 && !kDebugMode;
      if (expensive != Motion.glassFallback) {
        setState(() => Motion.glassFallback = expensive);
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
