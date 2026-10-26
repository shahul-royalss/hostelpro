import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../boot/splash_gate.dart';
import '../auth/auth_controller.dart';
import '../auth/session.dart';
import 'routes.dart';

export 'routes.dart';
import '../../features/auth/change_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/onboarding/onboarding_gate.dart';
import '../../features/auth/mfa_screen.dart';
import '../../features/legal/consent_gate.dart';
import '../../features/settings/security_screen.dart';
import '../../features/shell/role_shell.dart';
import '../../features/auth/verify_email_screen.dart';
import '../../features/signup/create_account_screen.dart';
import '../../features/signup/role_picker_screen.dart';
import '../../features/signup/signup_gate.dart';
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
///
/// SELF SIGN-UP (1.3.0) adds "Who are you?" and Create your account. Both are public, so a
/// signed-in user who lands on either is sent home by the rule below exactly as from /login —
/// which is also how a successful sign-up leaves Create your account.
const _publicRoutes = {loginRoute, startRoute, createAccountRoute};

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

/// THE EMAIL-VERIFICATION GATE (1.2.0). A real routing rule, not a screen something pushes.
///
/// [resolveRedirect] sends every signed-in route here while [ApnivaasSession.mustVerifyEmail] is
/// true — a staff account (owner, manager, warden, super admin) whose address can receive mail
/// and has never been proved — and sends it home the moment a re-read profile row carries the
/// proof. Existing unverified staff meet it on their next sign-in exactly like new ones.
///
/// Residents are never held here: proving their address changes nothing on the server, so they
/// keep the home-screen banner only. Nor is anyone whose address cannot receive mail — the
/// synthetic `<digits>@student.hostelpro.local` phone logins — because a proof that cannot be
/// produced would be a permanent lockout. See isReachableLoginAddress.
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
  // WRAPPED, so a first-time user is told what this app is before being asked to sign in to
  // it. The gate reads a marker file and shows the child immediately if it exists, so this
  // costs a repeat launch nothing. See features/onboarding/onboarding_gate.dart for why it is
  // a wrapper here rather than a phase in [resolveRedirect].
  // FIRST LAUNCH (1.3.0): the tour is step 1 and "Who are you?" is step 2, so finishing the tour
  // goes there rather than straight to the sign-in form. A returning launch is unchanged.
  loginRoute: (_) => OnboardingGate(
        onFirstRunDone: (context) => GoRouter.of(context).go(startRoute),
        child: const LoginScreen(),
      ),
  startRoute: (_) => const RolePickerScreen(),
  createAccountRoute: (_) => const CreateAccountScreen(),
  mfaRoute: (_) => const MfaScreen(),
  // The ONLY destination this app draws for AuthNeedsMfaEnrolment. See [mfaEnrolRoute].
  mfaEnrolRoute: (_) => const SecurityScreen(required: true),
  // ── CONSENT IS THE FIRST SCREEN AFTER SIGN-IN (1.2.0) ─────────────────────────────────────
  //
  // Every destination a signed-in user can reach from here down is wrapped in [ConsentGate]:
  // the forced password change, the email-verification gate and the five role homes. So the
  // order after authentication is
  //
  //     sign-in → second factor (/mfa or /mfa-setup) → Terms & Privacy → set password
  //             → verify email → home
  //
  // and a brand-new account reads what is kept about it before it is asked for anything else.
  // The product owner asked for exactly that ("at the start, one time"); until 1.2.0 the gate
  // wrapped only the role homes, which made it the LAST step for a new account — after the
  // password change and the verification — and is why it looked as if it never appeared.
  //
  // The second-factor routes stay OUTSIDE it on purpose. Until the second factor is presented
  // the session is not the account's yet (aal1 for an owner who has a factor), and the consent
  // read and write are made AS the account; asking somebody to agree to anything before we
  // know who they are would record an agreement against a session that has not finished
  // signing in. MFA is part of signing in; consent is the first thing after it.
  //
  // Push registration starts on acceptance (see consent_gate.dart), so for a new account it now
  // starts at this point rather than on the dashboard. That is the order the Privacy Policy
  // describes: agree first, then this handset's token is sent.
  //
  // NOTE WHAT THIS DOES NOT TOUCH. [resolveRedirect] below has no consent arm. Consent is
  // fetched rather than carried in the session row, and folding a fetched condition into a pure
  // routing function would have made test/router_redirect_test.dart's every-phase-against-
  // every-route matrix depend on data it cannot see. Wrapping each signed-in builder gives the
  // same order with none of that. See features/legal/consent_gate.dart.
  changePasswordRoute: (_) => const ConsentGate(child: ChangePasswordScreen()),
  // BLOCKING: as the gate route there is nothing behind this screen, so it offers Sign out
  // rather than "later", and the back gesture does not walk through it.
  verifyEmailRoute: (_) => const ConsentGate(child: VerifyEmailScreen(blocking: true)),
  // One shell per role. Each owns its own navigation, because forcing five roles through one
  // tab bar is what makes an operational tool feel like an admin template.
  //
  // Every role's subtree renders through its role home, so one wrapper per home covers all
  // five without a redirect arm.
  //
  // SignupGate sits INSIDE ConsentGate: an owner with no PG or a tenant with no PG meets the
  // onboarding steps only after every gate above has passed (features/signup/signup_gate.dart).
  for (final entry in roleHome.entries)
    entry.value: (_) => ConsentGate(child: SignupGate(child: RoleShell(role: entry.key))),
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
  bool openingFinished = true,
}) {
  // THE OPENING FINISHES BEFORE ANYTHING REPLACES IT.
  //
  // "Whatever the speed our dashboard or login shows, firstly it has to complete its
  // animation." Without this the redirect fired the moment a session resolved — under 200ms on
  // a warm start — and cut the mark off mid-assembly, so the animation played in full only
  // when the network was slow. Precisely backwards.
  //
  // It gates only DEPARTURE from the splash, never arrival: a phase that wants the splash
  // still gets it, and every other rule below is untouched. See core/boot/splash_gate.dart for
  // why the clock lives in a provider rather than in the screen.
  if (!openingFinished && here == splashRoute) return null;

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

    // ── THEN AN UNPROVED STAFF ADDRESS (1.2.0) ───────────────────────────────────────────
    //
    // Every signed-in route goes to /verify-email while [ApnivaasSession.mustVerifyEmail] holds,
    // and nothing but a re-read profile row carrying the proof lets the account out. This rule
    // is the fix for the verification bypass: the verify screen used to be a one-time
    // Navigator.push at the end of the forced password change, and anything that rebuilt the
    // stack threw it away — signing out and back in, killing the app, or (on Android) the
    // emailed link itself arriving as a navigation to '/'. Each of those landed the account on
    // its dashboard with only a banner. A rule evaluated on every navigation cannot be thrown
    // away, so all three now land here.
    //
    // `!needsPasswordChange` IS REQUIRED, not tidiness. The arm above lets an owed password
    // change sit on /change-password and falls through to here; without the guard this arm
    // would answer /verify-email, the arm above would answer /change-password, and go_router
    // would bounce between the two until it gave up and drew the error page — which is exactly
    // what the prototype of this rule did. Password first, then the address: a temporary
    // password read out by somebody else is the weaker secret, so the address is proved by
    // the person who has just chosen their own.
    if (!session.needsPasswordChange && session.mustVerifyEmail) {
      return here == verifyEmailRoute ? null : verifyEmailRoute;
    }

    // TOTAL, not `roleHome[...]!`. The bang could not fire today — ApnivaasSession.fromRow throws
    // on a role this build cannot name, so an unknown role never becomes an AuthSignedIn — but
    // it is the wrong shape of code to leave in a redirect callback. An exception thrown in here
    // does not surface as a crash the user can report; it surfaces as a frame that never draws.
    // A role with no home is an identity this build cannot route, which is the login screen's
    // case, and the guard in [resolveRedirect] keeps that from looping on /login.
    final home = roleHome[session.role] ?? loginRoute;

    // Anything that is not a real destination for a signed-in user sends them home. The
    // splash is listed first because it is the one every cold start passes through.
    //
    // /verify-email is in this list ONLY because nothing is owed by the time control gets
    // here: an account that still owes the proof was answered by the arm above and never
    // reaches this line. This is the release — the re-read that lands a verified session
    // re-runs the redirect with `here == verifyEmailRoute`, and this sends the account home.
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
    // AND the splash gate. Without this second listener the redirect is never re-evaluated
    // after the opening finishes, so an app whose session resolved during the animation would
    // sit on a completed splash until something else happened to poke the router.
    _ref.listen(splashGateProvider, (_, _) => notifyListeners());
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
      openingFinished: ref.read(splashGateProvider),
    ),

    // Built from [appScreens], so what the redirect can reach and what the router can draw are
    // one list. See the comment there.
    routes: [
      for (final entry in appScreens.entries)
        GoRoute(path: entry.key, builder: (context, _) => entry.value(context)),
    ],

    // The raw URI belongs in the log, not on the screen. Somebody who lands here followed a
    // stale link or a deep link into a screen that has moved; showing them "/owner/pg/3f2a…"
    // tells them nothing and reads as a crash. The path still reaches the console.
    errorBuilder: (_, state) {
      debugPrint('no route for ${state.uri}');
      return const _Placeholder(
        title: 'That page has moved',
        detail: 'Use the tabs at the bottom to get back to where you were.',
      );
    },
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
