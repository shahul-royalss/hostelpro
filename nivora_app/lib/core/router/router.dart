import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../auth/session.dart';
import '../../features/auth/change_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/mfa_screen.dart';
import '../../features/legal/consent_gate.dart';
import '../../features/settings/security_screen.dart';
import '../../features/shell/role_shell.dart';
import '../../features/auth/verify_email_screen.dart';
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

/// Where a privileged account with NO second factor is held.
///
/// Not a settings page reached from a menu: it is the ONLY destination this app will draw for
/// [AuthNeedsMfaEnrolment], and the redirect below puts it back in front of anyone who navigates
/// away. The server is granting that session grace — see mfaGate() — and this is the screen that
/// ends the grace. It is separate from [mfaRoute] because the two ask for different things:
/// /mfa wants a code from a factor that exists, this wants a factor to exist at all.
const mfaEnrolRoute = '/mfa-setup';
const changePasswordRoute = '/change-password';

/// The gate a brand-new account passes through after setting its own password.
///
/// Only ever reached when [NivoraSession.needsEmailVerification] is true, which is false for
/// every resident whose login is a phone number — their synthetic `<digits>@student.hostelpro.local`
/// address cannot receive mail, and gating them on it would lock them out of a product they can
/// otherwise use perfectly. See isReachableLoginAddress.
const verifyEmailRoute = '/verify-email';

/// EVERY PATH THIS APP REGISTERS, AND THE SCREEN BEHIND IT.
///
/// It is a map rather than a hand-written `routes:` list so a test can ask the question no test
/// could ask before: does every location [resolveRedirect] can return actually have a screen?
/// A redirect to a path with no GoRoute is not an error anyone sees — go_router falls through
/// to [errorBuilder] — and a phase whose destination is missing is a frame that draws nothing.
/// Both are black rectangles on a phone, and both are invisible to `flutter analyze` and to
/// every test that checks one route at a time.
///
/// The router below is BUILT from this map, so the route table and [appRoutes] cannot drift
/// apart: adding a destination means adding it here, and test/router_redirect_test.dart then
/// exercises every AuthPhase against it automatically, without being told it exists.
final appScreens = <String, WidgetBuilder>{
  splashRoute: (_) => const SplashScreen(),
  loginRoute: (_) => const LoginScreen(),
  mfaRoute: (_) => const MfaScreen(),
  // The ONLY destination this app draws for AuthNeedsMfaEnrolment. See [mfaEnrolRoute].
  mfaEnrolRoute: (_) => const SecurityScreen(required: true),
  changePasswordRoute: (_) => const ChangePasswordScreen(),
  verifyEmailRoute: (_) => const VerifyEmailScreen(),
  // One shell per role. Each owns its own navigation, because forcing five roles through one
  // tab bar is what makes an operational tool feel like an admin template.
  //
  // WRAPPED IN [ConsentGate], and this is the whole of the signed-in surface: every role's
  // subtree renders through its role home, so one wrapper here covers all five without a
  // redirect arm. The pre-app obligations above — change password, second-factor enrolment —
  // are deliberately OUTSIDE it: somebody forced to change a temporary password must not have
  // to accept a privacy policy before they are allowed to secure their own account.
  //
  // NOTE WHAT THIS DOES NOT TOUCH. [resolveRedirect] below is unchanged. Consent is fetched
  // rather than carried in the session row, and folding a fetched condition into a pure
  // routing function would have made test/router_redirect_test.dart's every-phase-against-
  // every-route matrix depend on data it cannot see. See features/legal/consent_gate.dart.
  for (final entry in roleHome.entries)
    entry.value: (_) => ConsentGate(child: RoleShell(role: entry.key)),
};

/// Every location the app can legitimately be at. Derived, never restated.
Set<String> get appRoutes => appScreens.keys.toSet();

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
  final to = _decide(phase: phase, here: here);
  // NEVER REDIRECT TO WHERE WE ALREADY ARE, whatever the rule below concluded.
  //
  // go_router counts a redirect to the current location as a redirect and runs the decision
  // again on the result, so any rule that can return its own input is an infinite loop. It does
  // not crash: after five hops go_router gives up with a GoException and draws [errorBuilder],
  // which is a "Not found" card where a screen should be. Every arm below is written to avoid
  // that on its own — this makes it structural rather than a property each new arm has to
  // remember, and it is asserted for every phase against every route in
  // test/router_redirect_test.dart.
  return to == here ? null : to;
}

String? _decide({
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

  // Above the signed-in branch on purpose. This account IS signed in as far as the Auth server
  // and — under the grace arm — as far as Postgres is concerned, so nothing further down would
  // stop it reaching a role home. Enrolment is the whole of what it may do.
  if (value is AuthNeedsMfaEnrolment) {
    return here == mfaEnrolRoute ? null : mfaEnrolRoute;
  }

  if (value is AuthSignedIn) {
    final session = value.session;

    // An owed password change outranks everything, including the role home.
    if (session.needsPasswordChange && here != changePasswordRoute) {
      return changePasswordRoute;
    }

    // TOTAL, not `roleHome[...]!`. The bang could not fire today — NivoraSession.fromRow throws
    // on a role this build cannot name, so an unknown role never becomes an AuthSignedIn — but
    // it is the wrong shape of code to leave in a redirect callback. An exception thrown in here
    // does not surface as a crash the user can report; it surfaces as a frame that never draws.
    // A role with no home is an identity this build cannot route, which is the login screen's
    // case, and the guard in [resolveRedirect] keeps that from looping on /login.
    final home = roleHome[session.role] ?? loginRoute;

    // Anything that is not a real destination for a signed-in user sends them home. The
    // splash is listed first because it is the one every cold start passes through.
    if (here == splashRoute ||
        here == mfaRoute ||
        here == mfaEnrolRoute ||
        here == verifyEmailRoute ||
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

    // Built from [appScreens], so what the redirect can reach and what the router can draw are
    // one list. See the comment there.
    routes: [
      for (final entry in appScreens.entries)
        GoRoute(path: entry.key, builder: (context, _) => entry.value(context)),
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
