import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../auth/session.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/mfa_screen.dart';
import '../../features/shell/role_shell.dart';
import '../../features/splash/splash_screen.dart';

/// Routing, and the role → home mapping.
///
/// Mirrors the web app's lib/roles.ts exactly, because the two clients share one database and a
/// user must land in the same place on either. If that file changes, this must change with it.
const roleHome = <UserRole, String>{
  UserRole.superAdmin: '/super-admin',
  UserRole.owner: '/owner',
  UserRole.manager: '/manager',
  UserRole.warden: '/warden',
  UserRole.student: '/student',
};

/// Reachable without a session. Everything else redirects to /login.
const _publicRoutes = {'/login', '/splash'};

/// Rebuilds the router's redirect logic whenever auth changes, without rebuilding the router.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    debugLogDiagnostics: false,

    /// The ONLY navigation gate. Note what it is and is not: it decides which screens to draw.
    /// It is not authorization — a user who defeated this would still be refused every row by
    /// row-level security, because the server evaluates the JWT, not this function.
    redirect: (context, state) {
      final phase = ref.read(authControllerProvider);
      final here = state.matchedLocation;

      // Still restoring a persisted session. Hold on the splash rather than flashing /login,
      // which is what makes a warm start feel instant instead of like a logout.
      if (phase.isLoading || phase is AsyncLoading) {
        return here == '/splash' ? null : '/splash';
      }

      final value = phase.value;

      if (value is AuthNeedsMfa) {
        return here == '/mfa' ? null : '/mfa';
      }

      if (value is AuthSignedIn) {
        final session = value.session;

        // An owed password change outranks everything, including the role home.
        if (session.needsPasswordChange && here != '/change-password') {
          return '/change-password';
        }

        final home = roleHome[session.role]!;
        // Leaving a public route, or sitting on another role's subtree, sends you to your own.
        if (_publicRoutes.contains(here) || here == '/') return home;
        final ownsHere = roleHome.values.any((h) => here == h || here.startsWith('$h/'));
        final mine = here == home || here.startsWith('$home/');
        if (ownsHere && !mine) return home;
        return null;
      }

      // Signed out.
      return _publicRoutes.contains(here) ? null : '/login';
    },

    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/mfa', builder: (_, _) => const MfaScreen()),
      GoRoute(
        path: '/change-password',
        builder: (_, _) => const _Placeholder(title: 'Set a new password'),
      ),
      // One shell per role. Each owns its own navigation, because forcing five roles through
      // one tab bar is what makes an operational tool feel like an admin template.
      for (final entry in roleHome.entries)
        GoRoute(
          path: entry.value,
          builder: (_, _) => RoleShell(role: entry.key),
        ),
    ],

    errorBuilder: (_, state) => _Placeholder(
      title: 'Not found',
      detail: state.uri.toString(),
    ),
  );
});

/// Temporary destination for routes whose screen is not built yet. Deliberately says so rather
/// than rendering an empty page that looks finished.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, this.detail});
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: t.textTheme.titleLarge, textAlign: TextAlign.center),
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(detail!, style: t.textTheme.bodySmall, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
