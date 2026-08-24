import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../auth/session.dart';
import '../../features/auth/change_password_screen.dart';
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

/// Reachable without a session.
///
/// [splashRoute] is deliberately NOT in here. It is a transient holding state, never a
/// destination, and treating it as "public" is precisely what made the first release build sit
/// on the splash screen forever: the signed-out branch returned "stay put" for every public
/// route, so an app with no session held the spinner indefinitely. No crash, no error in the
/// log, nothing to diagnose — it simply looked like the app would not open.
const _publicRoutes = {loginRoute};

const splashRoute = '/splash';
const loginRoute = '/login';
const mfaRoute = '/mfa';
const changePasswordRoute = '/change-password';

/// The routing decision, extracted as a pure function so it can be tested without a widget
/// tree, an emulator or a network. The hang above was invisible to `flutter analyze` and to
/// every unit test that existed, because the decision was buried in a closure inside a
/// provider. It is out here now so that "signed out on the splash goes to login" is an
/// assertion rather than an assumption.
///
/// Returns the location to redirect to, or null to stay put.
String? resolveRedirect({
  required AsyncValue<AuthPhase> phase,
  required String here,
}) {
  // Hold on the splash ONLY for the very first session restore, which is the case with no
  // value yet. Later loading states — a token refresh, or the moment between tapping Sign in
  // and the server answering — keep their previous value, so they no longer yank a user who
  // is mid-flow back to a spinner.
  if (phase.isLoading && !phase.hasValue) {
    return here == splashRoute ? null : splashRoute;
  }

  final value = phase.value;

  if (value is AuthNeedsMfa) {
    return here == mfaRoute ? null : mfaRoute;
  }

  if (value is AuthSignedIn) {
    final session = value.session;

    // An owed password change outranks everything, including the role home.
    if (session.needsPasswordChange && here != changePasswordRoute) {
      return changePasswordRoute;
    }

    final home = roleHome[session.role]!;

    // Anything that is not a real destination for a signed-in user sends them home. The
    // splash is listed first because it is the one every cold start passes through.
    if (here == splashRoute ||
        here == mfaRoute ||
        here == '/' ||
        _publicRoutes.contains(here)) {
      return home;
    }

    // Sitting in another role's subtree sends you to your own. This is presentation, not
    // authorization: a user who defeated it would still be refused every row by row-level
    // security, which evaluates the JWT server-side.
    final ownsHere = roleHome.values.any((h) => here == h || here.startsWith('$h/'));
    final mine = here == home || here.startsWith('$home/');
    if (ownsHere && !mine) return home;
    return null;
  }

  // Signed out, or the restore failed. Either way the only place to be is the login screen —
  // including when the user is still on the splash.
  return _publicRoutes.contains(here) ? null : loginRoute;
}

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
    initialLocation: splashRoute,
    refreshListenable: refresh,
    debugLogDiagnostics: false,

    /// The ONLY navigation gate. Note what it is and is not: it decides which screens to draw.
    /// It is not authorization — see resolveRedirect.
    redirect: (context, state) => resolveRedirect(
      phase: ref.read(authControllerProvider),
      here: state.matchedLocation,
    ),

    routes: [
      GoRoute(path: splashRoute, builder: (_, _) => const SplashScreen()),
      GoRoute(path: loginRoute, builder: (_, _) => const LoginScreen()),
      GoRoute(path: mfaRoute, builder: (_, _) => const MfaScreen()),
      GoRoute(
        path: changePasswordRoute,
        builder: (_, _) => const ChangePasswordScreen(),
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
