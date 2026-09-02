library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Supabase exports a type named AuthState too. Ours is AuthPhase precisely so the two
// can coexist without an alias that future readers have to decode.

import '../../data/models/failure.dart';
import '../boot/startup.dart';
import 'auth_endpoint.dart';
import '../config/env.dart';
import 'session.dart';
import 'session_standing.dart';

// [studentLoginDomain] and [isReachableLoginAddress] moved to session.dart, because
// NivoraSession is what has to answer "does this account have an address worth verifying" and
// core/auth/session cannot import the controller that imports it. Re-exported here so
// `import auth_controller.dart show studentLoginDomain` — which several screens and tests do —
// keeps resolving to the same single definition.
export 'session.dart' show isReachableLoginAddress, studentLoginDomain;

/// Auth state for the whole app. One source of truth that the router listens to.
///
/// A student signs in with EITHER a real email address — the one the warden collected when
/// they registered — OR, when they have none, their phone number, which is mapped to a
/// synthetic address (`<digits>@student.hostelpro.local`). The web app resolves the same two
/// forms with the same rules and this client must match it byte for byte, or the same person
/// cannot sign in on mobile. That mapping lives in [resolveLoginEmail] and nowhere else.

/// Strips an Indian mobile number down to its ten digits.
///
/// Byte-identical to `normalizePhone` in the web app's lib/utils.ts and to `normalisePhone` in
/// features/warden/data/warden_repository.dart — the same string has to come out of all three,
/// because one of them writes the login id and another one resolves it. Deliberately NOT
/// imported from the warden repository: core/ must not depend on features/.
String _normalisePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) return digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) return digits.substring(1);
  return digits;
}

/// The web's `isPhoneLike`: it must LOOK like a typed phone number — digits and the separators
/// people actually use — and still have at least ten digits once they are stripped.
bool _isPhoneLike(String input) =>
    RegExp(r'^[\d\s+\-()]{8,16}$').hasMatch(input) && _normalisePhone(input).length >= 10;

/// Turns whatever the user typed into the address Supabase Auth expects.
///
/// Pure and side-effect free on purpose: it reads no table, so it can never become an
/// account-enumeration oracle. That is also why there is no third case where a student may use
/// either their email or their phone — answering "which login does this number belong to?"
/// needs a lookup on an unauthenticated endpoint, over a population of young residents whose
/// address is exactly the thing worth protecting. Each account has ONE login id, and the
/// warden hands it over on the credentials screen.
///
/// Three cases, in this order, matching resolveLoginEmail() in the web app's lib/utils.ts:
///   1. anything containing '@' is an email and passes through, lowercased;
///   2. anything that looks like a typed phone number becomes the synthetic student address;
///   3. anything else is passed through lowercased and left for the server to refuse.
///
/// Case 3 used to build `<nothing>@student.hostelpro.local` out of a typo — a login that could
/// not exist, sent as if it might, and a divergence from the web client for the same input.
String resolveLoginEmail(String input) {
  final trimmed = input.trim();
  if (trimmed.contains('@')) return trimmed.toLowerCase();
  if (_isPhoneLike(trimmed)) return '${_normalisePhone(trimmed)}@$studentLoginDomain';
  return trimmed.toLowerCase();
}

sealed class AuthPhase {
  const AuthPhase();
}

/// Before the first session restore completes. The splash holds here.
class AuthLoading extends AuthPhase {
  const AuthLoading();
}

class AuthSignedOut extends AuthPhase {
  const AuthSignedOut({this.message});

  /// Set when the user was signed out FOR a reason worth showing (deactivated, revoked).
  final String? message;
}

/// Authenticated at the Auth server, but a second factor is still owed for this session.
class AuthNeedsMfa extends AuthPhase {
  const AuthNeedsMfa(this.factorId);
  final String factorId;
}

/// Privileged, signed in, and holding NO factor to present.
///
/// The server's grace arm made visible: the session genuinely works — Postgres is letting this
/// account through on purpose — and the only screen this app will draw for it is enrolment.
/// See [mfaGate] for why that is a routing decision and not a refusal.
class AuthNeedsMfaEnrolment extends AuthPhase {
  const AuthNeedsMfaEnrolment(this.session);

  /// Carried so the enrolment screen can name the account it is about to change, and so it can
  /// label the factor the way the web action labels it. Staff phones get handed around, and 2FA
  /// is the one setting where changing it on the wrong account is discovered much later.
  final NivoraSession session;
}

/// Roles the server will not serve at aal1.
///
/// A FOURTH COPY of a list that must agree with three others, and the only one nothing checks:
///   · `app.mfa_required_roles()`                — Postgres, the authority for row-level security
///   · `MFA_REQUIRED_ROLES` in .env.local        — read by lib/supabase/middleware.ts (the web app)
///   · `DEFAULT_MFA_REQUIRED_ROLES` in caller.ts — read by the Edge Functions
///   · here                                      — routing, and nothing else
///
/// Getting THIS copy wrong cannot open a hole, which is why a mirrored constant is acceptable
/// where it would not be on the server. Too narrow and a privileged user is sent to their role
/// home and then refused every row by row-level security — visibly broken, never quietly
/// permitted. Too wide and somebody is asked to enrol who did not have to.
const mfaRequiredRoles = <UserRole>{UserRole.superAdmin, UserRole.owner};

/// What a session still owes before this app may treat it as signed in.
enum MfaGate {
  /// Nothing. Either a code was already presented this session, or none is required.
  satisfied,

  /// A factor exists and has not been used yet — go and enter the code.
  codeOwed,

  /// Privileged, and there is no factor to enter. Go and create one.
  enrolmentOwed,
}

/// The client half of the server's rule, kept pure so both arms are testable without a network,
/// a Supabase client or a real TOTP.
///
/// It mirrors `app.mfa_satisfied()` (db/migrations/2026-08-31-mfa-enforcement.sql) arm for arm,
/// with one deliberate difference: ANY role holding a verified factor is asked for its code, not
/// only the privileged ones. That is the behaviour this app already had, it is what a manager who
/// switched 2FA on for himself expects, and asking for more than the server demands can only
/// refuse a session the server would have allowed — never the other way round.
///
///   aal2 already            → satisfied      server: `aal = 'aal2'` → true
///   has a verified factor   → codeOwed       server: REFUSES a privileged aal1 session
///   privileged, no factor   → enrolmentOwed  server: GRACE — the session works
///   anyone else             → satisfied      server: role not on the list → true
///
/// THE THIRD ARM IS THE ONE THAT MATTERS, and it is why this returns three values rather than a
/// bool. On the day enforcement shipped the platform held exactly ONE enrolled factor — an
/// owner's, from 2026-08-23 — while the super admin and two of the three owners had none.
/// Refusing every privileged aal1 session outright would have locked the platform's
/// administrators out of their own platform, and enrolling a factor itself needs a working
/// session, so there would have been no way back in. The server therefore lets those accounts
/// through and audits every use of the exemption; this routes them to the one screen that closes
/// it. The hole shuts per account, by itself, the moment that account enrols.
MfaGate mfaGate({
  required UserRole role,
  required bool isAal2,
  required bool hasVerifiedFactor,
}) {
  if (isAal2) return MfaGate.satisfied;
  if (hasVerifiedFactor) return MfaGate.codeOwed;
  return mfaRequiredRoles.contains(role) ? MfaGate.enrolmentOwed : MfaGate.satisfied;
}

class AuthSignedIn extends AuthPhase {
  const AuthSignedIn(this.session);
  final NivoraSession session;
}

class AuthController extends AsyncNotifier<AuthPhase> {
  StreamSubscription<AuthState>? _sub;

  /// How many auth events this notifier has already handled.
  ///
  /// ═══ THE COUNTER THAT STOPS THE APP READING ITS OWN HISTORY BACK ═══
  /// `onAuthStateChange` is not a plain broadcast stream. gotrue backs it with a
  /// `ReplaySubject` with an UNBOUNDED buffer (gotrue_client.dart:94, 2.27.2), so EVERY new
  /// subscriber is handed the entire history of auth events this process has ever emitted,
  /// oldest first, before it sees anything new.
  ///
  /// This notifier resubscribes on every rebuild — `ref.onDispose` cancels the subscription and
  /// nulls it between builds, and the `_sub ??=` below then makes a fresh one — so each rebuild
  /// replayed the whole history, including the `signedIn` whose handler calls
  /// `ref.invalidateSelf()`. That is a closed loop: replay → invalidateSelf → rebuild →
  /// resubscribe → replay. See [actionForAuthEvent] for the measurement.
  ///
  /// Skipping the events already handled is the narrow fix for the replay; the idempotence
  /// rules in [actionForAuthEvent] are the wide one, and both are here because either alone
  /// would leave the other's failure mode standing.
  int _eventsHandled = 0;

  /// The access token the phase this notifier last published was resolved from.
  ///
  /// The one fact that tells a genuine sign-in apart from the same sign-in being read back out
  /// of the replay buffer: a new session carries a new access token, a replay carries the one
  /// we already answered.
  String? _resolvedFor;

  /// True while [signIn] or [verifyMfa] is installing a session it will resolve itself.
  ///
  /// `setSession` emits `signedIn` before it returns, and the stream delivers that to the
  /// listener BEFORE the awaiting caller resumes — so without this flag the `signedIn` arm
  /// fires a second, concurrent [_resolve] for a session the caller is already resolving. Two
  /// profile reads for one fact, racing each other to publish it.
  bool _installingSelf = false;

  /// The Supabase client this controller talks to.
  ///
  /// [clientOverride] exists for exactly one reason: the sign-in and second-factor paths could
  /// not be tested at all. Everything else in this file that could be extracted into a pure
  /// function has been — [mfaGate], [restoreWithin], [phaseAfterFailedRefresh],
  /// [actionForAuthEvent] — but the round trips those paths make, and the ORDER they make them
  /// in, are the thing that broke in the field and are not expressible as a pure function. A
  /// test can now point this at a MockClient and count what actually goes over the wire.
  @visibleForTesting
  SupabaseClient? clientOverride;

  SupabaseClient get _db => clientOverride ?? Supabase.instance.client;

  @override
  Future<AuthPhase> build() async {
    // THE FIRST LINE, BEFORE ANY `_db`. `Supabase.instance` throws until initialisation has
    // finished, and since main() stopped awaiting that before runApp() — so the splash draws
    // immediately instead of leaving Android's flat black launch window up — this notifier is
    // the one thing that builds while it may still be in flight. See core/boot/startup.dart.
    // Outside the real app this is an already-completed future and costs a microtask.
    await ref.watch(supabaseReadyProvider.future);

    // supabase_flutter restores a persisted session from secure storage before this runs, so
    // by the time we get here currentUser is already populated on a warm start. That is what
    // makes "open app → straight to home" possible without a network round trip first.
    // `.skip(_eventsHandled)` IS NOT A TIDY-UP. See [_eventsHandled]: this stream replays its
    // whole history to every new subscriber, and this notifier gets a new subscriber on every
    // rebuild. Without the skip, each rebuild re-delivers the `signedIn` whose handler asks for
    // a rebuild.
    _sub ??= _db.auth.onAuthStateChange.skip(_eventsHandled).listen(
      (event) {
        _eventsHandled++;
        // The decision is [actionForAuthEvent], which takes no client and no network so the
        // loop it exists to prevent can be asserted in a unit test rather than discovered in a
        // server log. Everything left here is the work.
        final action = actionForAuthEvent(
          event: event.event,
          eventToken: event.session?.accessToken,
          resolvedToken: _resolvedFor,
          holdsSession: _db.auth.currentSession != null,
          installingSelf: _installingSelf,
          signedOutByDeadToken: _signedOutByDeadToken,
        );
        switch (action) {
          case AuthEventAction.ignore:
            break;
          case AuthEventAction.republishSignedOut:
            _signedOutByDeadToken = false;
            _resolvedFor = null;
            // WHY THIS ARM CARRIES A SENTENCE. gotrue emits `signedOut` for three quite
            // different things and used to be answered here with one wordless phase: the user
            // tapped Sign out, the refresh token was rejected, or a stored session could not be
            // read back. `signOutReason` (gotrue 2.27, sign_out_reason.dart) says which, and
            // the login screen has shown [AuthSignedOut.message] since the arrival-message
            // change. Landing on an empty form is how "the app forgot me" happens.
            state = AsyncData(AuthSignedOut(message: signOutMessage(event.signOutReason)));
          case AuthEventAction.reresolve:
            _signedOutByDeadToken = false;
            ref.invalidateSelf();
        }
      },
      // ═══ THE HANDLER THAT WAS NOT THERE ═══
      // `onAuthStateChange` is a stream that carries ERRORS as well as events, and a failed
      // token refresh is the main thing it puts on that channel: gotrue's `_doRefresh` calls
      // `notifyException` — which is `_onAuthStateChangeController.addError` — for every
      // retryable failure, i.e. for every one of the Unhealthy windows this NANO instance
      // produces (gotrue_client.dart:1608-1645, 2.27.2).
      //
      // With no onError, that error had nowhere to go but the zone's uncaught handler. The app
      // never learned that its token was no longer being renewed; it went on holding a
      // credential that expires an hour after it was minted, and then started asking the server
      // questions that could only be answered "no". Which is where the misleading refusals came
      // from.
      onError: _refreshFailed,
    );
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });

    // THE ONE CALL SITE OF [_resolve] THAT HAD NO DEADLINE. signIn, verifyMfa and
    // changePassword each wrapped theirs; the cold-start restore did not, and it is the call
    // that holds the splash. The rule and the whole argument for it live in [restoreWithin],
    // which is a free function precisely so it can be tested without a Supabase client.
    //
    // The deadline covers the whole restore rather than each round trip inside it, because what
    // the user is owed is an answer within a human span, not a budget per request. Same rule
    // failure.dart states for every data read — "EVERY DATA READ HAS A DEADLINE, AND A READ
    // THAT REACHES IT BECOMES A FAILED STATE" — which auth was simply never covered by.
    return restoreWithin(_resolve);
  }

  /// True while this notifier is the reason the app is sitting on the login screen — i.e. it
  /// published [AuthSignedOut] because the token stopped being renewable, NOT because anybody
  /// signed out and NOT because the server rejected the identity.
  ///
  /// It exists so the app can take that back. gotrue keeps retrying a failed refresh on its own
  /// ticker, and on a NANO instance the thing that failed at 14:02 frequently succeeds at
  /// 14:03. Stranding somebody on a login form because of a bad minute — while the client
  /// quietly holds a session that now works — would be a second, quieter version of exactly the
  /// dishonesty this change is about.
  bool _signedOutByDeadToken = false;

  /// A refresh failure arrived on the auth stream. Decide whether it is this app's business.
  ///
  /// The decision itself is [phaseAfterFailedRefresh], which takes no client and no network so
  /// it can be asserted in a unit test. What is left here is the plumbing and the log line.
  ///
  /// ═══ WHY THE ANSWER IS USUALLY "DO NOTHING" ═══
  /// gotrue retries, with the session intact, for as long as the failure is retryable. A
  /// dropped packet at minute 40 of a 60-minute token is not an event a user should ever hear
  /// about — the next tick fixes it, and yanking a working screen away would be far worse than
  /// the fault. It becomes this app's business only once the token in hand is one the server
  /// will not accept, because from that moment every screen is drawing answers to questions
  /// asked by nobody.
  void _refreshFailed(Object error, StackTrace stack) {
    // The rule from the top of the file: name the cause the person can act on, and put the
    // detail here. debugPrint is stripped in release, so this cannot reach a production log.
    debugPrint('auth stream error (token refresh): ${error.runtimeType} $error');

    final next = phaseAfterFailedRefresh(sessionStandingOf(_db));
    if (next == null) return;
    // Already signed out for some other, better-known reason — a deactivation, a revocation,
    // the user's own tap. Do not overwrite that sentence with this weaker one.
    if (state.value is AuthSignedOut) return;

    debugPrint('token is no longer usable; routing to sign-in');
    _signedOutByDeadToken = true;
    state = AsyncData(next);
  }

  Future<AuthPhase> _resolve() async {
    final user = _db.auth.currentUser;
    if (user == null) {
      _resolvedFor = null;
      return const AuthSignedOut();
    }

    // CLAIMED BEFORE THE FIRST AWAIT, not after the last one. This is what lets
    // [actionForAuthEvent] tell a genuine sign-in from the same one being replayed, and a replay
    // can be delivered at any await point below. Recording it on the way out would leave a
    // window in which the loop this ends could still start.
    _resolvedFor = _db.auth.currentSession?.accessToken;

    // public.users is the authority for role/status, NOT the JWT's app_metadata, which lags a
    // refresh behind. RLS lets a user read their own row, so no elevated key is involved.
    //
    // THIS READ COMES FIRST NOW, and it has to. The second-factor decision below is made per
    // ROLE — a warden owes nothing, an owner owes everything — and the role is in this row.
    // The read survives the gate it is about to inform: `users_select`'s self branch is a bare
    // `id = auth.uid()` carrying no assurance conjunct, so a refused owner at aal1 still reads
    // their own row and nothing else. Checked against the live database on 2026-08-31 by
    // impersonating the one owner who holds a factor: at aal1, users 1 — hostels 0, students 0,
    // rooms 0. Were that ever to change, this would return null and sign a legitimate owner out
    // with "your account is not set up", so it is a fact worth re-checking rather than assuming.
    final row = await _db
        .from('users')
        .select('id, role, full_name, email, phone, hostel_id, status, '
            'must_change_password, email_verified_at')
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) {
      // Authenticated but no profile: the account is half-created. Refusing beats guessing.
      await _db.auth.signOut();
      return const AuthSignedOut(message: 'Your account is not set up yet. Contact your administrator.');
    }

    final session = NivoraSession.fromRow(row);
    if (!session.isActive) {
      await _db.auth.signOut();
      return const AuthSignedOut(message: 'This account has been deactivated.');
    }

    // Before AuthSignedIn, never after: a session that still owes a factor must not be published
    // as signed in even briefly, or the router flashes the role home on the way past. The owed
    // factor also outranks an owed password change, because the phase returned here is not
    // AuthSignedIn at all and the router never gets as far as `needsPasswordChange` — the same
    // order the web app routes (/mfa before /change-password) and the same order
    // requireSession() in supabase/functions/_shared/caller.ts is built around.
    return _applyMfaGate(session);
  }

  /// The verified TOTP factor carried by the session's OWN user object, or null.
  ///
  /// Local: no network, and nothing here can throw. `getAuthenticatorAssuranceLevel()` derives
  /// its `nextLevel` from this very list (gotrue-2.27.2, gotrue_mfa_api.dart:230), so reading it
  /// directly rather than going to the wire for the same answer keeps the two from disagreeing.
  String? _localFactorId() {
    final factors = _db.auth.currentSession?.user.factors;
    if (factors == null) return null;
    for (final f in factors) {
      if (f.factorType == FactorType.totp && f.status == FactorStatus.verified) return f.id;
    }
    return null;
  }

  /// Work out what [session] still owes and turn it into a phase. See [mfaGate] for the rule.
  Future<AuthPhase> _applyMfaGate(NivoraSession session) async {
    // The `aal` claim out of the access token this app is already holding — the SAME claim
    // Postgres reads in app.mfa_satisfied() and requireAssurance() reads in caller.ts. Decoded
    // locally, so this costs no round trip and has no failure mode.
    final isAal2 = _db.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
        AuthenticatorAssuranceLevels.aal2;

    var factorId = _localFactorId();

    // ONE conditional round trip, on the single branch where a stale local answer would send a
    // person to the wrong screen: privileged, not stepped up, and this token's user object lists
    // no factor. If that is right they must enrol. If it is stale — enrolled from the web since
    // this token was minted — they must enter a code instead, and only the server knows which.
    // Every other branch is decided from the token alone and never reaches the network.
    if (!isAal2 && factorId == null && mfaRequiredRoles.contains(session.role)) {
      try {
        // `getUser()`, NOT `mfa.listFactors()`, and the difference is not cosmetic.
        //
        // gotrue's `listFactors()` opens with an unconditional `await _client.refreshSession()`
        // (gotrue_mfa_api.dart:176, 2.27.2) and only then reads `currentUser.factors`. That is a
        // POST to /auth/v1/token?grant_type=refresh_token — a heavier round trip than the one we
        // need, on the cold-start path, and it SPENDS AND ROTATES THE REFRESH TOKEN to answer a
        // question about factors. Two consequences, both of which this app has seen:
        //   · latency, on the one path where the user is staring at a splash screen;
        //   · a 400 `Invalid Refresh Token: Refresh Token Not Found` whenever the stored token
        //     has already been retired — which is exactly what enrolling a factor does, since
        //     verifying one logs out every other session (gotrue_mfa_api.dart:37) — and gotrue
        //     answers a non-retryable refresh failure by dropping the session outright
        //     (`_removeSession()`, gotrue_client.dart:1626). Asking "do you have a factor?" must
        //     not be able to end the session it is asking about.
        // `getUser()` is a GET /auth/v1/user with the token already in hand: same answer, one
        // cheaper round trip, no rotation, no side effect on the session.
        final refreshed = await _db.auth.getUser();
        for (final f in refreshed.user?.factors ?? const []) {
          if (f.factorType == FactorType.totp && f.status == FactorStatus.verified) {
            factorId = f.id;
            break;
          }
        }
      } catch (e) {
        // WHAT GIVING UP HERE COSTS, NOW THAT THE SERVER ENFORCES.
        //
        // The comment that stood here until 2026-08-31 justified swallowing this with "the
        // server still refuses aal1 requests for anything gated — the client is not the
        // boundary". That was FALSE when it was written: 0 of the 65 live policies mentioned
        // `aal`, requireCaller() never read an assurance level, and an audit on 2026-08-30
        // signed in as SUPER_ADMIN with a password alone and was issued a working token at aal1.
        // Swallowing it meant walking into the app with no second factor and nothing downstream
        // to stop you. On mobile that check WAS the boundary, and it was fail-open.
        //
        // It is true now. Here is exactly where, so the next person can check rather than trust:
        //   · app.mfa_satisfied() — db/migrations/2026-08-31-mfa-enforcement.sql, live as
        //     mfa_enforcement_predicate, _wire_rls_helpers and _gate_live_owner_paths. It is a
        //     conjunct of app.owned_hostel_ids(), app.user_hostel_id() and app.is_super_admin(),
        //     which between them back every one of the 65 live policies, so PostgREST hands an
        //     owner who holds a factor ZERO rows at aal1. Verified by impersonating that owner
        //     against the live database — never against db/rls-policies.sql, which is stale.
        //   · requireAssurance() in supabase/functions/_shared/caller.ts, reached from every
        //     requireCaller(), which is every privileged Edge Function write.
        //
        // So this catch no longer decides whether anything is protected. It decides which screen
        // a privileged user is shown while GoTrue is unreachable, and it picks enrolment: the
        // account whose factors we could not read is EITHER factor-less, in which case enrolment
        // is the right screen and the server is granting grace, OR enrolled, in which case the
        // server is refusing every row and the enrolment screen re-reads the factor list itself
        // and offers Continue the moment that read succeeds. Sending them to their role home
        // instead would draw five empty tabs over a session the server has already refused.
        debugPrint('mfa factor lookup failed: ${e.runtimeType} $e');
      }
    }

    switch (mfaGate(role: session.role, isAal2: isAal2, hasVerifiedFactor: factorId != null)) {
      case MfaGate.satisfied:
        return AuthSignedIn(session);
      case MfaGate.codeOwed:
        // Non-null by construction: codeOwed is returned only for hasVerifiedFactor, which is
        // `factorId != null` one line above.
        return AuthNeedsMfa(factorId!);
      case MfaGate.enrolmentOwed:
        return AuthNeedsMfaEnrolment(session);
    }
  }

  /// Sign in with an email OR a phone number (see [resolveLoginEmail]).
  /// Returns null on success, or a message to show the user.
  ///
  /// This deliberately does NOT push the in-flight attempt into the shared auth state. The
  /// router listens to that state, and a value-less loading value there means "the first
  /// session restore is still running" — so routing it through here yanked the user off the
  /// login form and onto the splash screen the moment they tapped Sign in. Submission
  /// progress belongs to the form; auth phase belongs to the app.
  /// How long any single sign-in network step may take before the app gives up on it.
  ///
  /// There is no default. Dart's HTTP client will wait for minutes on a connection that was
  /// accepted but is never answered, which is exactly what a wedged backend does: the TCP and
  /// TLS handshakes complete in under a second, then nothing. Without this the sign-in button
  /// spins indefinitely and the person holding the phone has no way to tell a dead server from
  /// a slow one. Fifteen seconds is well past a genuine sign-in on a poor mobile connection
  /// (the observed healthy figure is around two) and well short of a person's patience.
  static const _networkTimeout = Duration(seconds: 15);

  /// Installs a session the Edge Function minted.
  ///
  /// `setSession(refresh, accessToken: access)` uses THOSE tokens rather than exchanging the
  /// refresh token for new ones, which matters on the second-factor path: the access token the
  /// function returns is the one carrying `aal2`, and swapping it out would throw the step-up
  /// away and bounce the user straight back to the code screen.
  ///
  /// It is one round trip (gotrue validates the token with `getUser`) and it persists the
  /// session to the keystore and emits `signedIn`, exactly as `signInWithPassword` used to.
  Future<void> _install(AuthGranted grant) async {
    await _db.auth
        .setSession(grant.refreshToken, accessToken: grant.accessToken)
        .timeout(_networkTimeout);
  }

  /// Sign in through `supabase/functions/mobile-auth`, NOT through GoTrue directly.
  ///
  /// ═══ WHY THE CALL MOVED ═══
  /// `signInWithPassword` posts straight to `/auth/v1/token?grant_type=password`, which this
  /// project measured as completely unthrottled: twelve consecutive wrong passwords for a real
  /// account, twelve 400s, no 429, no lockout, back-off DECREASING, and not one row in
  /// `public.audit_log` — so the attack was invisible to `app.detect_suspicious_activity()` as
  /// well. The Edge Function spends a durable Postgres counter keyed by identifier AND by IP
  /// before a password is checked, and audits the failure either way.
  ///
  /// The three outcomes below are three different sentences on purpose. A 429 is not a verdict
  /// on the password (it was never checked), and neither is a 503 — which is not hypothetical
  /// here: with CAPTCHA protection on, EVERY password grant fails without any credential being
  /// examined, and wording that as "wrong password" would send every user in the product to
  /// reset a password that was fine.
  /// Send a password-reset mail. Returns null when the request was accepted, or a message.
  ///
  /// ── IT ALWAYS SUCCEEDS, AND THAT IS THE POINT ────────────────────────────────────────
  ///
  /// The caller shows the same sentence whether or not an account exists, because the
  /// difference is an account-enumeration oracle: a stranger typing addresses at this endpoint
  /// must not be able to learn which ones are residents of a PG. GoTrue's own recover endpoint
  /// answers 200 for an unknown address for exactly this reason, and this method does not
  /// undo that by reporting the distinction.
  ///
  /// ── A STUDENT ON A PHONE LOGIN CANNOT BE REACHED THIS WAY ───────────────────────────
  ///
  /// A resident registered without an email signs in as `<digits>@student.hostelpro.local`,
  /// which no mail server will ever accept. Sending there would look like success and deliver
  /// nothing. Refused here, with the one instruction that actually helps: ask the warden, who
  /// can mint a new temporary password from the student list.
  ///
  /// ── THE LIMIT IS THE SERVER'S ─────────────────────────────────────────────────────────
  ///
  /// public.password_reset_gate hashes the identifier, spends a global bucket before a
  /// per-address one, and is granted to anon. A client-side cooldown would be a suggestion;
  /// this is the enforcement, and it holds for an attacker who never opens the app.
  Future<String?> sendPasswordReset(String identifier) async {
    final email = resolveLoginEmail(identifier);
    if (email.endsWith('@$studentLoginDomain')) {
      return 'That login has no email address. Ask your warden to set you a new password.';
    }

    try {
      final gate = await _db
          .rpc('password_reset_gate', params: {'p_identifier': email})
          .timeout(_networkTimeout);
      final row = gate is List && gate.isNotEmpty ? gate.first : gate;
      if (row is Map && row['allowed'] == false) {
        final wait = row['retry_after_seconds'];
        final mins = wait is int ? ((wait + 59) ~/ 60) : 1;
        return 'A reset link was sent recently. Try again in '
            '${mins <= 1 ? 'a minute' : '$mins minutes'}.';
      }

      await _db.auth
          .resetPasswordForEmail(email, redirectTo: Env.emailConfirmRedirectUrl)
          .timeout(_networkTimeout);
      return null;
    } on AuthException catch (e) {
      debugPrint('sendPasswordReset failed: ${e.runtimeType} ${e.message}');
      return _friendly(e);
    } catch (e) {
      debugPrint('sendPasswordReset failed (transport): ${e.runtimeType} $e');
      return _unreachable(e);
    }
  }

  Future<String?> signIn({required String identifier, required String password}) async {
    // ═══ THE DEAD SESSION THAT WAS BLOCKING EVERY ATTEMPT ═══
    //
    // `functions.invoke` does not send the request first and ask questions later. Every call
    // goes through `AuthHttpClient.send`, whose FIRST line is `await _getAccessToken()`
    // (supabase auth_http_client.dart:24) — and that resolves to `GoTrueClient.getSession()`,
    // which REFRESHES an expired session before returning it. A refresh that comes back
    // 400 `refresh_token_not_found` throws, and the throw happens before a single byte of the
    // sign-in leaves the handset.
    //
    // That is not a rare state. The login screen is reached holding a stale session on two
    // ordinary paths this file already documents: [restoreWithin] times out and returns
    // AuthSignedOut WITHOUT clearing the persisted token ("a timed-out restore is not a
    // sign-out"), and [phaseAfterFailedRefresh] does the same for a token gotrue is still
    // retrying. In both, the person is looking at a login form while the client quietly holds a
    // credential the server has finished with — so every tap on Sign in spent itself refreshing
    // a dead token, was refused before the password was read, and reported as a failure of the
    // sign-in. The `400 Invalid Refresh Token: Refresh Token Not Found` pairs in the auth log
    // are those taps. The Edge Function was never invoked; there is no `mobile-auth` invocation
    // beside them.
    //
    // A sign-in is a fresh start, possibly as a different person. Nothing about the old session
    // is worth carrying into it, so drop it. LOCAL AND UNAWAITED, deliberately: `_signOut`
    // removes the session synchronously before its first await (gotrue_client.dart:1086), so the
    // invoke below is already clean, while the /logout round trip that retires the old token
    // server-side is best effort and must never sit on the critical path of a sign-in.
    unawaited(_dropStaleSession());

    try {
      final verdict = await ref.read(mobileAuthEndpointProvider).signIn(
            loginEmail: resolveLoginEmail(identifier),
            password: password,
          );
      final AuthGranted granted;
      switch (verdict) {
        case AuthGranted():
          granted = verdict;
        case AuthThrottled(:final message):
          return message;
        case AuthRejected(:final message):
          return message;
        case AuthUnavailable(:final message):
          return message;
      }
      _installingSelf = true;
      try {
        await _install(granted);
        // The profile read is a SECOND network call, to PostgREST rather than to Auth, and it
        // gets its own deadline. This step is why sign-in could previously appear to succeed and
        // then strand the user: the password was accepted, this read hung or failed, and the
        // PostgrestException it threw is not an AuthException, so the catch below never saw it.
        // The button kept spinning and no message was ever shown.
        //
        // ONE read, not two. `_installingSelf` is what keeps the `signedIn` this install emits
        // from starting a second, concurrent resolve of the same session — see
        // [actionForAuthEvent], and the 825-reads-per-second it measures.
        state = AsyncData(await _resolve().timeout(_networkTimeout));
      } finally {
        _installingSelf = false;
      }
      return null;
    } on AuthException catch (e) {
      // The user sees a deliberately vague message; whoever is debugging needs the real one.
      // debugPrint is stripped in release, so this cannot leak to a device log in production.
      debugPrint('signIn failed: ${e.runtimeType} status=${e.statusCode} '
          'code=${e.code} ${e.message}');
      // Deliberately not distinguishing "no such user" from "wrong password": that difference
      // is an account-enumeration oracle, and this app's population is young residents whose
      // phone number is the login.
      return _authFailure(e);
    } catch (e) {
      // Everything that is not an auth verdict: timeouts, dropped sockets, DNS failures, and
      // the 5xx pages a gateway serves when the backend behind it is not answering. These are
      // all "we could not ask the question", never "the answer was no", so none of them may be
      // reported as a bad password.
      debugPrint('signIn failed (transport): ${e.runtimeType} $e');
      return _unreachable(e);
    }
  }

  /// Clear whatever session this handset is still holding, locally and now.
  ///
  /// Called only from [signIn]. The local half is what matters and it is synchronous; the
  /// /logout round trip is a courtesy to the server and its failure is not the user's problem —
  /// the token being retired is one the server has very often already forgotten, which is how
  /// this app got into the state that needed clearing.
  Future<void> _dropStaleSession() async {
    if (_db.auth.currentSession == null) return;
    try {
      await _db.auth.signOut(scope: SignOutScope.local).timeout(_networkTimeout);
    } catch (e) {
      debugPrint('clearing the stale session before sign-in: ${e.runtimeType} $e');
    }
  }

  /// Returns null on success, or a message to show. Same reasoning as [signIn].
  ///
  /// Routed through the same Edge Function, and for a sharper reason than sign-in. A TOTP is
  /// six digits on a thirty-second rotation — a 10^6 space that an unthrottled endpoint gives
  /// away in minutes — and the `mfa.challenge`/`mfa.verify` pair this used to call is exactly
  /// that endpoint. Whoever is guessing codes has already passed the first factor for this
  /// account, so the server audits the failures against a REAL actor and
  /// `app.detect_suspicious_activity()` alerts at three in ten minutes.
  /// ═══ WHERE THE SECONDS ACTUALLY GO, AND HOW TO SEE IT AGAIN ═══
  ///
  /// The owner's report was "it taking lot of time to authenticate my request". Measured against
  /// this project rather than guessed at, on 2026-08-31 (UTC), the three legs are:
  ///
  ///   · the `mobile-auth` invocation   1394 / 2620 / 2663 / 3522 / **9252** ms
  ///     (`function_edge_logs.execution_time_ms`, five real invocations that evening). Inside it:
  ///     two rate-limit RPCs in parallel, then /factors/{id}/challenge, then /factors/{id}/verify,
  ///     then an audit INSERT — every one of them serial, and the audit write is on the critical
  ///     path before the tokens are handed back. GoTrue's own halves are usually tiny: the
  ///     challenge+verify pair at 23:13:19 measured 32.7 ms + 39.7 ms.
  ///   · `_install` — one GET /auth/v1/user, 3–42 ms typically (4785 ms once, at 23:06:17).
  ///   · `_resolve` — one GET /rest/v1/users, ~250 ms.
  ///
  /// So the client's own share was two round trips and the function's was seconds — EXCEPT that
  /// `_resolve` was not running once. See [actionForAuthEvent]: it was running hundreds of times
  /// a second, until PostgREST stopped keeping up and the fifteen-second deadline below turned
  /// into "the server is not responding". That was the real "lot of time", and it was ours.
  ///
  /// The timing line at the end is how the next person checks this on a real handset instead of
  /// re-deriving it from server logs.
  Future<String?> verifyMfa({required String factorId, required String code}) async {
    final clock = Stopwatch()..start();
    var endpointMs = 0;
    var installMs = 0;
    try {
      final verdict = await ref.read(mobileAuthEndpointProvider).verifyMfa(
            factorId: factorId,
            code: code,
          );
      endpointMs = clock.elapsedMilliseconds;
      final AuthGranted granted;
      switch (verdict) {
        case AuthGranted():
          granted = verdict;
        case AuthThrottled(:final message):
          return message;
        case AuthRejected(:final message):
          return message;
        case AuthUnavailable(:final message):
          return message;
      }
      _installingSelf = true;
      try {
        await _install(granted);
        installMs = clock.elapsedMilliseconds - endpointMs;
        state = AsyncData(await _resolve().timeout(_networkTimeout));
      } finally {
        _installingSelf = false;
      }
      debugPrint('mfa verify ok in ${clock.elapsedMilliseconds}ms '
          '(endpoint ${endpointMs}ms, install ${installMs}ms, '
          'resolve ${clock.elapsedMilliseconds - endpointMs - installMs}ms)');
      return null;
    } on AuthException catch (e) {
      debugPrint('verifyMfa failed after ${clock.elapsedMilliseconds}ms: '
          '${e.runtimeType} status=${e.statusCode} code=${e.code} ${e.message}');
      final failure = AppFailure.from(e);
      // THE SESSION THAT WAS CARRYING THIS CODE HAS ENDED. Not an outage, and there is nothing
      // to retype on this screen: the FIRST factor is what expired, so the honest move is to say
      // so and put the person back on the form that can fix it. Publishing the phase is what
      // moves them; the message is returned as well so that a frame in which the router has not
      // yet acted is never a cleared field with nothing on it.
      if (failure is SessionExpiredFailure) {
        state = AsyncData(AuthSignedOut(message: failure.message));
        return failure.message;
      }
      return _authFailure(e);
    } catch (e) {
      debugPrint('verifyMfa failed (transport) after ${clock.elapsedMilliseconds}ms: '
          '${e.runtimeType} $e');
      return _unreachable(e);
    }
  }

  /// Set a new password. Returns null on success, or a message to show.
  ///
  /// ═══ 2026-09-01: THE CURRENT PASSWORD IS NOW REQUIRED ON BOTH PATHS ═══
  ///
  /// This method used to take `String? currentPassword` and pass null for a FORCED change, on
  /// the reasoning that the user had just authenticated with the temporary password and asking
  /// for it again reads as a bug. That reasoning was ours; the server's is different, and the
  /// server is the one that decides. Measured against the live project on 2026-09-01:
  ///
  ///     PUT /auth/v1/user  {"password":"…"}
  ///     -> 400 {"error_code":"current_password_required",
  ///             "msg":"Current password required when setting new password."}
  ///
  ///     PUT /auth/v1/user  {"password":"…","current_password":"…"}
  ///     -> 200
  ///
  /// `GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD` is ON for this project. Every
  /// account this platform creates — every owner, manager, warden and student — arrives with
  /// `must_change_password = true` and is routed straight here, so with the old signature NO
  /// ACCOUNT COULD EVER COMPLETE ITS FIRST LOGIN. The screen accepted the form, the request was
  /// refused, and the flag stayed set: a locked door for the whole product.
  ///
  /// So [currentPassword] is required, it travels to GoTrue on both paths, and the
  /// change-password screen asks for it on both paths (labelled "Temporary password" for a
  /// forced change, because that is the thing the person is holding).
  ///
  /// The FORCED/VOLUNTARY asymmetry survives where it actually mattered. A voluntary change
  /// still spends a throttled reauthentication through the mobile-auth endpoint before the
  /// write — same per-identifier and per-IP budget as sign-in, same audit trail — because an
  /// unlimited "is this the current password?" oracle on a borrowed handset is how a session
  /// becomes an account. A forced change does not: GoTrue is about to check the very same
  /// password itself, one line below, and a second unthrottled grant to verify what the next
  /// call verifies anyway would only widen that oracle. Which case applies is still read from
  /// the profile row by the caller, never from anything the form can say.
  Future<String?> changePassword({
    required String newPassword,
    required String currentPassword,
    /// True when the server still holds `must_change_password` for this account. Read from the
    /// profile row by the screen; it selects the reauthentication policy above, and nothing
    /// else. A client that lied here would gain nothing: GoTrue checks [currentPassword]
    /// regardless, and the flag it is trying to clear is cleared by the row's own RLS.
    required bool forced,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) return 'Your session has expired. Sign in again.';

    try {
      if (!forced) {
        // Reauthenticate. A failure here must not be reported as a password-strength problem.
        //
        // This went through the Edge Function too, because it was the THIRD unthrottled
        // password grant in this file and the same guessing attack fits it: a stolen or
        // borrowed handset already holds a session, and an unlimited "is this the current
        // password?" oracle is how that becomes the account. It spends the same per-identifier
        // and per-IP budget as sign-in — deliberately, since it is the same question — and the
        // failures land in the same audit trail.
        final verdict = await ref.read(mobileAuthEndpointProvider).signIn(
              loginEmail: user.email ?? '',
              password: currentPassword,
            );
        switch (verdict) {
          case AuthGranted():
            // The grant is for this same person, so installing it is what
            // signInWithPassword did here anyway — and leaving it uninstalled would strand a
            // live token nobody holds.
            await _install(verdict);
          case AuthRejected():
            return 'Your current password is incorrect.';
          case AuthThrottled(:final message) || AuthUnavailable(:final message):
            // Neither of these checked the password, so neither may claim it was wrong.
            return message;
        }
      }

      // EVERY step here gets the same deadline as the rest of this class. This tail was the
      // last unbounded await in the auth path: against a backend that accepts the connection
      // and never answers — which this free-tier instance does intermittently — the user was
      // stranded having just set a new password, with the old one already invalid on the
      // server and the spinner running forever.
      // `currentPassword` is what turns this from a 400 into a 200 — see the header. It is also
      // the last verification in the chain, and the only one on the forced path: GoTrue checks
      // it against the stored hash before it writes anything.
      await _db.auth
          .updateUser(UserAttributes(
            password: newPassword,
            currentPassword: currentPassword,
          ))
          .timeout(_networkTimeout);

      // Clear the flag the router gates on. RLS permits a user to update their own row; no
      // elevated key is involved. app_metadata is not touched here — it lags a token refresh
      // and public.users is the authority, exactly as on the web.
      await _db
          .from('users')
          .update({'must_change_password': false})
          .eq('id', user.id)
          .timeout(_networkTimeout);

      // ═══ FROM HERE THE PASSWORD IS ALREADY CHANGED. NOTHING BELOW MAY REPORT FAILURE. ═══
      //
      // Both writes have landed: GoTrue holds the new password and `must_change_password` is
      // false. Everything after this point is only this app catching up with a fact the server
      // already has, so a fault in it is a REFRESH problem. Reporting it as "could not save your
      // password" would send somebody back to type a temporary password that no longer exists.
      //
      // ═══ WHY THIS IS invalidateSelf() AND NOT `state = AsyncData(await _resolve())` ═══
      //
      // It was that assignment, and the assignment lost a race it could not see.
      //
      // `updateUser` two statements above makes gotrue emit `userUpdated`, and this notifier's
      // own onAuthStateChange listener answers that event with `ref.invalidateSelf()`. So a
      // rebuild starts THERE — one statement before the flag is cleared — and its `_resolve()`
      // reads public.users while `must_change_password` is still true. Riverpod publishes the
      // result of a rebuild that is already in flight when it finishes, on top of whatever was
      // assigned in the meantime: measured on riverpod 3.4.2, a manual `state =` is overwritten
      // by the stale build that completes after it. The app therefore finished a SUCCESSFUL
      // password change still believing the change was owed, and the router — which gates on
      // exactly that flag — had every reason to keep the user on the change-password screen.
      // That is half of the owner's "it stays at there"; the other half is that resolveRedirect
      // returns null for a signed-in user sitting on /change-password even once the flag IS
      // clear, which is why the screen now leaves under its own power as well.
      //
      // Invalidating again here supersedes the stale build (its result is discarded) and the
      // rebuild this one starts reads the row AFTER both writes. `await future` then waits for
      // the phase this method is supposed to have published, rather than for whichever build
      // happened to finish last.
      ref.invalidateSelf();
      try {
        await future.timeout(_networkTimeout);
      } catch (e) {
        // Swallowed deliberately, for the reason stated at the top of this block and the same
        // one [reload] gives: the operation succeeded, the caller is about to say so, and the
        // next resolve — a reopen, a token refresh, the dashboard's own reads — corrects the
        // phase. A read that failed after the write must not be dressed up as a write that
        // failed.
        debugPrint('post-change re-resolve failed: ${e.runtimeType} $e');

        // AND PUBLISH THE FLAG WE KNOW IS CLEARED. Swallowing the failed READ is right; leaving
        // the phase saying the change is still owed is not. Both writes landed above, so
        // `must_change_password` is false on the server whatever this re-read did. If the phase
        // still carries the old value, resolveRedirect's first arm sends the user straight back
        // to /change-password — an empty form, no message, immediately after they successfully
        // changed their password. That IS the symptom this whole job exists to fix, and the
        // re-read failing is exactly when it would bite.
        final held = state.value;
        if (held is AuthSignedIn && held.session.mustChangePassword) {
          final s = held.session;
          state = AsyncData(AuthSignedIn(NivoraSession(
            userId: s.userId,
            role: s.role,
            fullName: s.fullName,
            status: s.status,
            mustChangePassword: false,
            hostelId: s.hostelId,
            email: s.email,
            phone: s.phone,
            emailVerifiedAt: s.emailVerifiedAt,
          )));
        }
      }
      return null;
    } on AuthException catch (e) {
      debugPrint('changePassword failed: ${e.runtimeType} ${e.message}');
      final m = e.message.toLowerCase();
      // ── THE CURRENT PASSWORD ITSELF WAS REFUSED ──
      // Matched on `code`, not on `message`, because GoTrue's message is WRONG for one of the
      // two codes. Measured on 2026-09-01: a *wrong* current password answers
      //     400 {"error_code":"current_password_invalid",
      //          "msg":"Current password required when setting new password."}
      // — the same sentence it sends when the field is missing entirely. Passing that through
      // tells somebody who typed their temporary password that they did not type one, and they
      // will type the same wrong thing again. Both codes get a sentence about the field the
      // person can actually see.
      if (e.code == 'current_password_invalid' || e.code == 'current_password_required') {
        return forced
            ? 'That temporary password is not right. Use the one you were given, exactly as '
                'it was written.'
            : 'Your current password is incorrect.';
      }
      if (m.contains('different from the old') || m.contains('same password')) {
        return 'Choose a password different from your temporary one.';
      }
      if (m.contains('weak') ||
          m.contains('pwned') ||
          m.contains('leaked') ||
          m.contains('compromised')) {
        return 'That password is too weak or has appeared in a data breach — choose another.';
      }
      return _friendly(e);
    } catch (e) {
      debugPrint('changePassword failed: $e');
      return 'Could not save your password. Check your connection and try again.';
    }
  }

  Future<void> signOut() async {
    await _db.auth.signOut();
    state = const AsyncData(AuthSignedOut());
  }

  /// Re-read the profile row and republish the phase.
  ///
  /// Used after something changed a column the session carries but this app did not write
  /// itself — `email_verified_at` is set by the email-verification Edge Function with the
  /// service role, so nothing here would ever notice it otherwise and the banner would sit on
  /// the screen after the code was accepted.
  ///
  /// `state = AsyncData(...)` rather than `ref.invalidateSelf()`, for the reason the sign-in
  /// path gives: invalidating publishes a value-less loading state on some paths, and the
  /// router reads that as "the first session restore is still running" and shows the splash.
  /// A refresh must never take a working screen away from someone.
  Future<void> reload() async {
    try {
      state = AsyncData(await _resolve().timeout(_networkTimeout));
    } catch (e) {
      // Deliberately swallowed. This is a background correction, never the thing the user
      // asked for: the caller has already told them the outcome of the operation that
      // prompted it, and replacing a good session with an error here would sign them out
      // over a dropped packet.
      debugPrint('session reload failed: ${e.runtimeType} $e');
    }
  }

  /// The sentence for an [AuthException] that escaped [signIn] or [verifyMfa].
  ///
  /// ═══ A 400 IS NOT AN OUTAGE ═══
  /// Everything the Edge Function decides about a credential comes back as an [AuthVerdict], so
  /// an AuthException on these two paths is almost never about what the person just typed. It is
  /// about the session this handset was ALREADY holding — `functions.invoke` refreshing an
  /// expired token before it sends, or `setSession` being handed one the server has forgotten.
  /// The auth log for the reported window is exactly that shape: two
  /// `400 Invalid Refresh Token: Refresh Token Not Found` on /token, and no 5xx anywhere.
  ///
  /// [AppFailure] is where this app already keeps that distinction — [SessionExpiredFailure] for
  /// the codes that mean the refresh token is finished, [OfflineFailure] and [ServerFailure] for
  /// a refresh that could not reach the server at all. Deferring to it rather than restating it
  /// is the whole point: the same event classified two different ways in two files is how "the
  /// server is not responding" ended up in front of a person whose server was answering in
  /// 250 ms.
  ///
  /// Anything OUTSIDE those three keeps [_friendly]'s credential-aware wording, because
  /// `_fromAuth`'s catch-all is [SignedOutFailure] and rendering a mistyped password as "your
  /// session has ended" would just be a new lie in place of the old one.
  String _authFailure(AuthException e) {
    final failure = AppFailure.from(e);
    if (failure is SessionExpiredFailure) return failure.message;
    if (failure is OfflineFailure || failure is ServerFailure) return failure.message;
    return _friendly(e);
  }

  /// Errors a user can act on. Anything unrecognised becomes a generic line rather than
  /// leaking a driver message into the UI.
  String _friendly(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'That login or password is not right.';
    }
    // What GoTrue says when the identifier is not a syntactically valid address at all — the
    // third case in [resolveLoginEmail], i.e. neither an email nor a phone number. It is a
    // verdict on what the person typed and not on whether any account exists, so saying the
    // login is wrong leaks nothing and is the only useful thing to say.
    if (m.contains('unable to validate email address') || m.contains('invalid format')) {
      return 'That login or password is not right.';
    }
    if (m.contains('invalid totp') || m.contains('invalid code')) {
      return 'That code is not right. Codes change every 30 seconds — try the current one.';
    }
    if (m.contains('rate') || e.statusCode == '429') {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (m.contains('network') || m.contains('failed host lookup')) {
      return 'Cannot reach Nivora. Check your connection and try again.';
    }
    // A gateway 5xx means the request reached Supabase's edge and the service behind it did
    // not answer. That is an outage, not a credential problem, and saying so saves the user
    // from retyping a password that was never actually wrong.
    if (const {'502', '503', '504', '522'}.contains(e.statusCode)) {
      return _serverDown;
    }
    return 'Sign-in could not be completed. Please try again.';
  }

  /// Shown when the request never got an answer. Deliberately distinguishes "the server is
  /// down" from "your connection is down", because the two have different remedies and telling
  /// someone to check their wifi when the backend is dead sends them chasing the wrong fault.
  ///
  /// ═══ [_serverDown] IS NOW RESERVED FOR WHAT IT DESCRIBES ═══
  /// This used to answer EVERYTHING that was not an [AuthException] with "the Nivora server is
  /// not responding right now" — a PostgREST refusal, a Riverpod state error, anything at all.
  /// It is the sentence the owner photographed, and for his account it was false: the backend
  /// was answering /rest/v1/users in ~250 ms while the app said it was not. A sentence that
  /// broad cannot be evidence of anything, and a person who reads it goes and waits for an
  /// outage that is not happening.
  ///
  /// It now belongs to exactly two facts: a deadline this client set and reached, and a
  /// transport failure that is not a local connection problem. Everything else is classified by
  /// [AppFailure] — the same classifier every repository in this app already uses — so an
  /// expired session says it expired and an unexpected error says it was unexpected.
  String _unreachable(Object e) {
    // A deadline we set and reached. The request went out and nothing came back, which is
    // literally what the sentence says.
    if (e is TimeoutException) return _serverDown;

    final failure = AppFailure.from(e);

    // The credential is finished. Nothing on this screen can be retried into working, and
    // saying "the server is down" would send the person to wait instead of to sign in.
    if (failure.needsSignIn) return failure.message;

    // "Check your connection" is only honest when the request never left the handset.
    if (failure is OfflineFailure) return failure.message;

    // Reached the server, got nothing usable back.
    if (failure is ServerFailure) return _serverDown;

    return failure.message;
  }

  static const _serverDown = serverNotResponding;
}

/// What the app says when the server accepted the connection and then said nothing.
///
/// Top-level because two things now need it: [AuthController]'s sign-in failure mapping, which
/// has always used it, and [restoreWithin], which is a free function so the deadline it applies
/// can be tested without a Supabase client. The sentence is unchanged — it separates "the fault
/// is ours, wait" from "your password is wrong", which is the distinction a person needs before
/// they start changing things that were never broken.
const serverNotResponding =
    'The Nivora server is not responding right now. This is not a problem with your '
    'password. Please try again in a few minutes.';

/// THE SENTENCE THE LOGIN SCREEN SHOWS WHEN THE ROUTER PUT SOMEBODY THERE.
///
/// gotrue emits `signedOut` for three different things and this app used to answer all three
/// with one wordless phase, so an involuntary sign-out arrived as an empty login form. That
/// reads as "the app forgot me", and it is answered by typing the same correct password again
/// — which is what the owner did. `signOutReason` (gotrue 2.27, sign_out_reason.dart) says
/// which of the three it was, and [AuthSignedOut.message] is already rendered by the login
/// screen's arrival banner.
///
/// NULL FOR [SignOutReason.userInitiated], deliberately. Somebody who just tapped Sign out does
/// not need to be told why they are looking at a login form; a banner explaining a person's own
/// action to them reads as an error report.
///
/// A free function so the mapping can be asserted without an initialised Supabase client — the
/// same reason [phaseAfterFailedRefresh], [resolveRedirect] and [mfaGate] are free functions.
String? signOutMessage(SignOutReason? reason) => switch (reason) {
      SignOutReason.sessionExpired => sessionCouldNotBeRenewed,
      SignOutReason.sessionMissing =>
        'Nivora could not read the sign-in saved on this phone, so it has been cleared. Sign in '
            'again — nothing is wrong with your account.',
      SignOutReason.userInitiated || null => null,
    };

/// What the login screen says when a token stopped being renewable.
///
/// Top-level and shared with [SessionExpiredFailure]'s wording in spirit, because the two are
/// the same event seen from two places — the router got there first, or a screen's read did.
/// Both say the same three things: your sign-in ran out, your account is fine, sign in again.
const sessionCouldNotBeRenewed =
    'Your sign-in expired and Nivora could not renew it. Nothing is wrong with your account or '
    'your password — sign in again to carry on.';

/// WHAT A FAILED TOKEN REFRESH SHOULD DO TO THE APP. Null means "nothing".
///
/// Extracted for the same reason [resolveRedirect], [mfaGate] and [restoreWithin] are: the rule
/// was going to live inside a stream callback on a notifier that cannot be built without an
/// initialised Supabase client, which is to say nothing could ever assert it. It needs no
/// network, no client and no widget tree.
///
/// The three arms, and why each is the only honest one:
///   · [SessionStanding.live] — the token in hand still works. gotrue will try again on its own
///     ticker and will very probably succeed; a person mid-task must not be thrown out over a
///     minute of bad network. NOTHING HAPPENS, and that is a decision rather than an oversight.
///   · [SessionStanding.expired] — the token is past its lifetime and the renewal that should
///     have replaced it did not. Every request from here goes out with a credential the server
///     will refuse, or (worse — see core/auth/session_standing.dart) with the anon key. The app
///     must say so and offer the one thing that fixes it.
///   · [SessionStanding.none] — gotrue has already dropped the session. There is nothing left to
///     refresh and nothing left to hold.
///
/// It never returns a phase that would LOSE work: by the time either of the second two arms is
/// reached the app cannot successfully write anything anyway.
AuthPhase? phaseAfterFailedRefresh(SessionStanding standing) => switch (standing) {
      SessionStanding.live => null,
      SessionStanding.expired => const AuthSignedOut(message: sessionCouldNotBeRenewed),
      SessionStanding.none => const AuthSignedOut(
          message: 'Your sign-in has ended on this phone. Sign in again to carry on.',
        ),
    };

/// What an event on gotrue's auth stream should do to [AuthController].
enum AuthEventAction {
  /// Nothing. Either the fact has already been published, or the event is history being read
  /// back out of the replay buffer.
  ignore,

  /// Publish [AuthSignedOut], carrying whatever [signOutMessage] makes of the reason.
  republishSignedOut,

  /// Re-run the profile read and republish the phase.
  reresolve,
}

/// ═══ THE RULE THAT ENDED 825 PROFILE READS A SECOND ═══
///
/// MEASURED, not reasoned about. On 2026-08-31 the live project's `edge_logs` show the mobile
/// app issuing `_resolve`'s own query —
///
///     GET /rest/v1/users?select=id,role,full_name,email,phone,hostel_id,status,
///                               must_change_password,email_verified_at&id=eq.<uid>
///
/// — 80, 107, 279 and 170 times in four consecutive seconds after ONE sign-in at 23:14:47 UTC,
/// and 825 times in the single second 23:17:05. Six separate sign-ins that evening did the same
/// thing. That is not a slow backend; that is this client asking one question several hundred
/// times a second, and it is the whole of "it takes a long time and then says the server is
/// down": the app saturates its own free-tier PostgREST, `_resolve` reaches its fifteen-second
/// deadline, and the deadline is rendered as an outage.
///
/// THE MECHANISM, in three facts that are each individually reasonable:
///   1. `GoTrueClient.onAuthStateChange` is backed by a `ReplaySubject` with an unbounded buffer
///      (gotrue_client.dart:94, 2.27.2). Every NEW subscriber receives the entire history first.
///   2. [AuthController] resubscribes on every rebuild: `ref.onDispose` cancels the subscription
///      and nulls it between builds, and `_sub ??=` then creates another.
///   3. The `signedIn` arm called `ref.invalidateSelf()`.
///
/// So: sign in → `signedIn` → invalidateSelf → rebuild → resubscribe → the buffer replays
/// `signedIn` → invalidateSelf → … bounded only by how fast the network answers. The same replay
/// also re-delivered every OLD `signedOut`, which republished [AuthSignedOut] over a session that
/// was alive — the router throwing a signed-in user back to the login form, over and over, which
/// is what "when i try to login it blocking me all the time" looks like from the outside.
///
/// The rule below is what makes each arm idempotent, so that a replayed event is a no-op no
/// matter how the replay happens:
///
///   · `signedOut` while a session is HELD is history. gotrue calls `_removeSession()` before it
///     emits (gotrue_client.dart:1086, and again at :1626 for a dead refresh token), so a
///     genuine sign-out always arrives with no session left. One that arrives while the client
///     holds a live session is the buffer talking about a session that has since been replaced.
///   · `signedIn`/`userUpdated` carrying the access token we already resolved is the same
///     session being announced twice. A real new session carries a new token.
///   · `signedIn` while [installingSelf] is [signIn] or [verifyMfa] announcing a session it is
///     already resolving on its own. `setSession` emits before it returns and the stream delivers
///     to this listener BEFORE the awaiting caller resumes, so without this the app made two
///     concurrent profile reads for one sign-in and let them race to publish.
///   · `tokenRefreshed` is nothing, except as the apology described in [AuthController].
AuthEventAction actionForAuthEvent({
  required AuthChangeEvent event,
  required String? eventToken,
  required String? resolvedToken,
  required bool holdsSession,
  required bool installingSelf,
  required bool signedOutByDeadToken,
}) {
  switch (event) {
    case AuthChangeEvent.signedOut:
      return holdsSession ? AuthEventAction.ignore : AuthEventAction.republishSignedOut;
    case AuthChangeEvent.signedIn:
    case AuthChangeEvent.userUpdated:
      if (installingSelf) return AuthEventAction.ignore;
      if (eventToken != null && eventToken == resolvedToken) return AuthEventAction.ignore;
      return AuthEventAction.reresolve;
    case AuthChangeEvent.tokenRefreshed:
      // NORMALLY NOTHING. A SUCCESSFUL refresh changes no fact this notifier publishes — same
      // user, same role, same assurance level — and re-resolving on each one would put a profile
      // read and a router rebuild on a timer for the whole life of the session. The interesting
      // event is a refresh that FAILS, and that does not arrive here at all: it arrives as a
      // stream error. See [AuthController._refreshFailed].
      //
      // THE ONE EXCEPTION IS THE APOLOGY. If a previous failure was what put this app on the
      // login screen, the refresh that just succeeded is the evidence that it was wrong, and
      // holding the person there would be the sulk after the mistake.
      return signedOutByDeadToken ? AuthEventAction.reresolve : AuthEventAction.ignore;
    default:
      return AuthEventAction.ignore;
  }
}

/// THE COLD-START RESTORE'S DEADLINE, AND WHAT RUNNING OUT OF TIME MAKES A SESSION.
///
/// Extracted for exactly the reason `resolveRedirect` and `mfaGate` are: the rule was buried in
/// a method that cannot run without an initialised Supabase client, so nothing could assert it
/// and the absence of an assertion is how it went missing in the first place. [restore] is the
/// work; this function is the whole of the policy about it, and it needs no network to test.
///
/// signIn, verifyMfa and changePassword each already wrapped their resolve in a deadline. The
/// COLD-START restore did not, and it is the one that matters most: while it is in flight the
/// auth notifier is AsyncLoading with no value, which `resolveRedirect` reads as "the first
/// session restore is still running" and answers by holding the splash. This project is a
/// free-tier NANO whose PostgREST and Auth flip to Unhealthy under memory pressure, and a
/// wedged server is not a server that refuses: it completes the TCP and TLS handshakes in under
/// a second and then answers nothing, which Dart's HTTP client waits on indefinitely. So the
/// profile read never returned, the phase never left AsyncLoading, and the splash spun forever
/// with no crash and no log line — the same failure resolveRedirect was written to kill, one
/// layer further in.
///
/// A TIMED-OUT RESTORE IS NOT A SIGN-OUT. Nothing is revoked and the persisted token is
/// untouched; the next resolve — a reopen, a token refresh, or the user signing in again on the
/// screen this sends them to — restores normally. It is the signed-out phase CARRYING A
/// SENTENCE, because the login screen is the only place with anything to do about it and a form
/// a person can act on beats a spinner they cannot. Deliberately not rethrown: an AsyncError
/// routes to the very same screen but arrives there mute.
Future<AuthPhase> restoreWithin(
  Future<AuthPhase> Function() restore, {
  Duration deadline = restoreDeadline,
}) async {
  try {
    return await restore().timeout(deadline);
  } on TimeoutException {
    debugPrint('session restore timed out after $deadline');
    return const AuthSignedOut(message: serverNotResponding);
  }
}

/// The same fifteen seconds every other network step in this file gets, for the reason stated
/// at [AuthController._networkTimeout]: well past a genuine restore on a poor mobile connection,
/// well short of a person's patience.
const restoreDeadline = Duration(seconds: 15);

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthPhase>(AuthController.new);

/// The current session, or null. Convenience for screens that already know they are signed in.
///
/// [AuthNeedsMfaEnrolment] counts. That phase is a real, server-accepted session — the account
/// simply has one screen it is allowed to reach — and the enrolment screen needs the row to name
/// the account it is about to change and to label the factor `NIVORA (<role>)` the way the web
/// action labels it. It grants nothing: which screens exist is settled by the router, and what
/// data they may hold is settled by row-level security.
final sessionProvider = Provider<NivoraSession?>((ref) {
  final s = ref.watch(authControllerProvider).value;
  return switch (s) {
    AuthSignedIn(:final session) => session,
    AuthNeedsMfaEnrolment(:final session) => session,
    _ => null,
  };
});
