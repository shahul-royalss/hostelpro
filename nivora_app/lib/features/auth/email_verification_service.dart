library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart';
import '../../core/config/env.dart';

// ═══════════════════════════════════════════════════════════════════════════════════════════
// PROVING AN EMAIL ADDRESS, FROM THE PHONE
// ═══════════════════════════════════════════════════════════════════════════════════════════
//
// ── THE SHAPE OF THE FEATURE (the long form is in the Edge Function) ─────────────────────
//
// The owner asked that "everyone has to verify their email first and then they have to
// continue furtherly". Taken literally — block sign-in until the address is proved — that
// breaks the product, and not hypothetically. Measured against the live project again on
// 2026-09-01:
//
//     GET https://nimxvgzscbanhtvgnjll.supabase.co/auth/v1/settings
//       -> {"mailer_autoconfirm": false, ...}
//
// "Confirm email" is ON, so GoTrue refuses a password grant to any user whose
// email_confirmed_at is null. An account created unconfirmed cannot sign in AT ALL, so a
// literal reading would break the hostel desk, make a typo'd address an unrecoverable lockout,
// and demand a proof from residents whose login is <digits>@student.hostelpro.local, which no
// mail server accepts.
//
// So: the account CAN sign in, a persistent banner asks for the proof, and the proof gates the
// one action where an unproved address turns into credentials in a stranger's inbox — CREATING
// ANOTHER ACCOUNT. The server is where that gate lives (requireVerifiedEmail in
// supabase/functions/_shared/verification.ts). Nothing in this file is a security boundary.
//
// ── 2026-09-01: A LINK, NOT A CODE ───────────────────────────────────────────────────────
//
// The owner asked for this directly ("don't go with otp… go with link verification"), and
// there is a measurable reason to agree. The old path was
//
//     app -> email-verification Edge Function -> GoTrue -> mail
//
// and the owner's failure screenshot said "The Nivora server did not answer" — which is the
// string 30 lines below this one, produced by the 15s deadline expiring on that Edge Function
// while this free-tier NANO instance had PostgREST and Auth flipping to Unhealthy at ~72% RAM.
// The feature that proves an address was failing in the hop we had added to it.
//
// A confirmation LINK is composed and sent by GoTrue. [sendLink] calls /auth/v1/otp directly,
// so the path is app -> GoTrue -> mail: one hop fewer, and the hop removed is the one that kept
// failing. The Edge Function is still here, but only for [status] — which is off the critical
// path entirely, because a status call that fails loses nothing: the click is already recorded
// in GoTrue's own tables and the next resume picks it up.
//
// ── WHAT THAT COST, SAID PLAINLY ─────────────────────────────────────────────────────────
//
// The old design refused to let the phone call signInWithOtp itself, for a stated reason: a
// cooldown enforced in the process being asked to obey it is a suggestion, and the durable
// per-user counter (app.rate_limits) is granted to service_role only. That reason was sound and
// this change gives it up. What replaces it:
//
//   · GoTrue's own SMTP_MAX_FREQUENCY — 60s minimum between mails to one user, server-side, and
//     [_throttleFrom] reads the wait out of GoTrue's refusal so the button comes back exactly
//     when the server would start saying yes;
//   · GOTRUE_RATE_LIMIT_EMAIL_SENT — 30/hour, project-wide.
//
// And the thing that counter was never actually protecting: /auth/v1/otp is a public endpoint
// and the anon key is printed inside the APK. Anyone who wanted to make this project send mail
// could always call it directly. The Edge Function constrained THIS APP, not an attacker.
//
// ── 2026-09-01: THE LINK OPENS NIVORA, AND THE SIGN-IN IS THE PROOF ──────────────────────
//
// The owner asked for exactly this: "it has to ask to login through that link, once they login
// through that link they have to verify". The previous build sent people to a web page instead,
// and the page they landed on said "Page not found — That link doesn't exist, or you don't have
// access to it" (measured 2026-09-01: the route is untracked in git and was never deployed).
//
// The redirect is now a custom scheme — [Env.emailConfirmRedirectUrl], `app.nivora.mobile://
// verify-email` — matched by a VIEW intent-filter in AndroidManifest.xml. That is not a
// cosmetic swap. `main.dart` pins AuthFlowType.pkce, so the code verifier for a link THIS APP
// asked for is in THIS APP'S keystore. When the link lands on the phone:
//
//   1. GoTrue has already matched the single-use token at /auth/v1/verify — this is where the
//      proof is minted, before any redirect happens;
//   2. Android hands app.nivora.mobile://verify-email?code=… to Nivora;
//   3. supabase_flutter's deep-link observer recognises the `code` parameter, calls
//      getSessionFromUrl -> exchangeCodeForSession, and a session exists;
//   4. that emits AuthChangeEvent.signedIn with a NEW access token, which AuthController's
//      existing listener answers by re-resolving the profile (actionForAuthEvent -> reresolve).
//
// A BROWSER CAN NEVER DO STEP 3. It holds no verifier, so any web landing page is a page that
// watched something happen elsewhere. That is the structural reason this shape is right and the
// old one was not, and it is why the fix is not "deploy the missing page".
//
// ── THE ONE COST, NAMED SO NOBODY FILES IT AS A BUG ──────────────────────────────────────
//
// Step 3 mints a session authenticated by `magiclink` ALONE, which is aal1.
// `app.is_super_admin()` is (role = super_admin AND mfa_satisfied) and is false at aal1. So a
// super admin who taps their own verification link on the phone is dropped back to the TOTP
// prompt and re-enters six digits.
//
// That is a RE-PROMPT, not a lockout, and the boundary is unweakened — aal2 is still required
// for everything that required it, which is the point. It is the honest price of "the link
// signs you in", it affects one account on this project, and that account is already verified.
// Anything that avoided it would have to stop the link creating a session, which is the feature.
//
// NOTHING IN THIS FILE HAS TO CATCH THAT DEEP LINK. The proof is written by GoTrue at step 1,
// before the app is even involved, so [status] finds it whenever it is next asked — on resume,
// on the one startup check ([EmailVerificationRecheck.runOnceOnStartup], which is what covers a
// COLD start from the link, where there is no resume transition to listen for), or on the
// button. No new auth-event listener is added here, deliberately: onAuthStateChange is backed by
// an unbounded ReplaySubject, and a fresh subscriber replaying the whole history is precisely
// how this app once issued 825 profile reads a second.
//
// ── WHY THE ADDRESS COMES FROM public.users AND NOT FROM GoTrue ──────────────────────────
//
// [sendLink] is given the address the banner is displaying — `NivoraSession.email`, i.e.
// public.users.email. Supabase's own `currentUser.email` (auth.users.email) would be the more
// forgiving choice, because that is the column GoTrue looks the user up by. It is deliberately
// not used. The proof is stamped onto public.users.email, guarded on that exact value; if the
// two columns ever diverged, mailing the auth one would prove an address the stamp is not
// about. Mailing the public one means a divergence produces NO mail and NO proof — visible,
// and fail-closed, instead of quietly wrong.

/// What the server says about this account's address right now.
@immutable
class VerificationStatus {
  const VerificationStatus({
    required this.email,
    required this.verified,
    required this.required_,
    this.verifiedAt,
  });

  /// The address on the caller's own profile row, as the server reads it.
  final String? email;

  final bool verified;

  /// True when the account has a reachable address it has not proved. Named with the trailing
  /// underscore because `required` is a Dart keyword.
  final bool required_;

  final DateTime? verifiedAt;

  /// The local mirror of the server's own rule, for a screen that has a session but has not
  /// asked the server anything yet. Mirrors `isReachableAddress()` in the Edge Function and
  /// `app.email_is_reachable()` in Postgres.
  static bool isOwedBy(NivoraSession session) => session.needsEmailVerification;
}

/// The outcome of asking for a link.
@immutable
class SendOutcome {
  const SendOutcome({required this.email, required this.resendAfter});

  final String email;

  /// How long before "Send it again" may be offered. GoTrue enforces its own minimum between
  /// mails (SMTP_MAX_FREQUENCY, 60s by default) and this mirrors it, so the button comes back
  /// when the server would start accepting rather than when the client guessed.
  final Duration resendAfter;
}

/// A failure carrying a sentence the user can act on.
///
/// [retryAfter] is non-null only for a throttle. It is GoTrue's own number, dug out of its
/// refusal ("you can only request this once every 60 seconds") rather than invented here.
///
/// [operatorFault] marks failures that are NOT the user's problem and that no amount of
/// retrying fixes — CAPTCHA refusing /auth/v1/otp, an email template with nothing to click in
/// it, SMTP not configured. They get a different presentation, because telling a resident to
/// "check their connection" when an administrator has to change a project setting sends them
/// chasing a fault they cannot reach.
@immutable
class VerificationFailure implements Exception {
  const VerificationFailure(
    this.message, {
    this.retryAfter,
    this.operatorFault = false,
    this.noAddress = false,
  });

  final String message;
  final Duration? retryAfter;
  final bool operatorFault;

  /// The account signs in with a phone number, so there is nothing to verify.
  final bool noAddress;

  bool get throttled => retryAfter != null;

  @override
  String toString() => 'VerificationFailure($message)';
}

/// The seam the screen talks to, so a widget test can drive the whole flow without a network,
/// an initialised Supabase client, or a real inbox.
abstract class EmailVerificationService {
  /// Ask the server whether the link has been opened yet.
  ///
  /// Cheap, and — for an account that has already proved its address — free of side effects.
  /// For one that has not, this is also the call that RECORDS the proof: only the service role
  /// may write `users.email_verified_at`, so the Edge Function reads GoTrue's own record of the
  /// click and stamps the column. That is why the app asks again on every resume.
  Future<VerificationStatus> status();

  /// Email the account a confirmation link. [email] is the address to send to and the address
  /// the proof will be stamped against — see the note at the top of this file.
  Future<SendOutcome> sendLink(String email);
}

/// The real one: GoTrue for the send, the `email-verification` Edge Function for the check.
class SupabaseEmailVerificationService implements EmailVerificationService {
  const SupabaseEmailVerificationService(this._db);

  final SupabaseClient _db;

  static const _function = 'email-verification';

  /// The same fifteen seconds every other network step in this app gets, for the reason
  /// AuthController's comment gives: Dart's HTTP client waits minutes on a connection that was
  /// accepted and never answered, and a spinner over a wedged backend is indistinguishable
  /// from a slow one.
  static const _networkTimeout = Duration(seconds: 15);

  /// GoTrue's SMTP_MAX_FREQUENCY default. Used only when GoTrue has not told us a number.
  static const _defaultCooldown = Duration(seconds: 60);

  // ── SEND ──────────────────────────────────────────────────────────────────────────────

  @override
  Future<SendOutcome> sendLink(String email) async {
    final address = email.trim().toLowerCase();
    if (!isReachableLoginAddress(address)) {
      throw const VerificationFailure(
        'This account signs in with a phone number, so there is no email address to verify. '
        'Ask your warden to add your email if you would like one on the account.',
        noAddress: true,
      );
    }

    // THE REDIRECT IS A REQUEST, NOT AN INSTRUCTION, AND GoTrue NEVER SAYS NO OUT LOUD.
    //
    // There used to be a retry here: catch a "redirect not allowed" refusal and send again with
    // no redirect. It was deleted because it cannot fire. GoTrue validates redirect_to by
    // silently SUBSTITUTING the Site URL when it is not on the allow-list; it does not refuse
    // the request, so there is no refusal to catch and no branch this app can take.
    //
    // Measured on this project 2026-09-01, by asking /auth/v1/verify to redirect a dead token
    // and reading the Location header — the one probe that shows the decision without spending
    // a real link:
    //
    //   app.nivora.mobile://verify-email                  -> https://hostelpro-three.vercel.app
    //   https://hostelpro-three.vercel.app/verify-email/…  -> honoured (same host as Site URL)
    //   https://definitely-not-allowed.example.org/x       -> https://hostelpro-three.vercel.app
    //
    // So until someone pastes the deep link into Supabase → Authentication → URL Configuration →
    // Redirect URLs, the link lands on the web app's home page instead of opening Nivora. That
    // costs the sign-in-by-link, NOT the verification: GoTrue matched the token at
    // /auth/v1/verify BEFORE redirecting anywhere, and public.email_link_proof() reads that back
    // from GoTrue's own tables. "I have opened the link" still finishes the job, which is why
    // this substitution is survivable rather than fatal. The screen names the exact fix when the
    // evidence says the link is not coming back to the app; docs/email-verification.md §0 is the
    // value to paste and §4 is every fallback, and [Env.emailRedirectSetupHint] is the single
    // string the screen and the document both use.
    final redirect = Env.emailConfirmRedirectUrl.trim();
    await _otp(address, redirect.isEmpty ? null : redirect);

    return SendOutcome(email: address, resendAfter: _defaultCooldown);
  }

  Future<void> _otp(String address, String? redirectTo) async {
    try {
      await _db.auth
          .signInWithOtp(
            email: address,
            emailRedirectTo: redirectTo,
            // Stops a typo minting an account, and means this can never be the reason a new
            // user exists. An address with no account simply gets no mail.
            shouldCreateUser: false,
          )
          .timeout(_networkTimeout);
    } on AuthException catch (e) {
      throw _sendFailureFrom(e);
    } on TimeoutException {
      throw const VerificationFailure(
        'Nivora could not reach the mail service. Check your connection and try again.',
      );
    } catch (e) {
      debugPrint('signInWithOtp failed (transport): ${e.runtimeType} $e');
      throw VerificationFailure(_transportMessage(e));
    }
  }

  // ── CHECK ─────────────────────────────────────────────────────────────────────────────

  @override
  Future<VerificationStatus> status() async {
    final d = await _invoke({'action': 'status'});
    return VerificationStatus(
      email: d['email'] as String?,
      verified: d['verified'] == true,
      required_: d['required'] == true,
      verifiedAt: DateTime.tryParse((d['verifiedAt'] as String?) ?? ''),
    );
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _db.functions.invoke(_function, body: body).timeout(_networkTimeout);
      final data = res.data;
      if (data is Map && data['data'] is Map) {
        return Map<String, dynamic>.from(data['data'] as Map);
      }
      // A 200 whose envelope this build cannot read. Treating it as success would claim a
      // proof nobody earned, so it is a failure.
      return <String, dynamic>{};
    } on FunctionException catch (e) {
      throw _statusFailureFrom(e);
    } on TimeoutException {
      throw const VerificationFailure(
        'The Nivora server did not answer. Your link still works — open it and come back.',
      );
    } catch (e) {
      debugPrint('email-verification failed (transport): ${e.runtimeType} $e');
      throw VerificationFailure(_transportMessage(e));
    }
  }
}

String _transportMessage(Object e) {
  final m = e.toString().toLowerCase();
  if (m.contains('failed host lookup') ||
      m.contains('no address associated') ||
      m.contains('network is unreachable')) {
    return 'Cannot reach Nivora. Check your connection and try again.';
  }
  return 'The Nivora server is not responding right now. Please try again in a few minutes.';
}

/// GoTrue's refusal, turned into one sentence.
///
/// The two operator-caused outages stay loud. A `captcha_failed` or a mail template with no
/// `{{ .ConfirmationURL }}` in it is not the user's problem and must never be reported as one:
/// the cost of a vague "could not send" here is somebody rebuilding the app looking for a bug
/// that is a dashboard toggle.
VerificationFailure _sendFailureFrom(AuthException e) {
  final raw = e.message;
  final m = raw.toLowerCase();
  final code = (e.code ?? '').toLowerCase();

  if (code.contains('captcha') || m.contains('captcha')) {
    debugPrint('verification link BLOCKED BY CAPTCHA: $raw');
    return const VerificationFailure(
      'Nivora cannot send verification links yet: CAPTCHA protection is switched on for this '
      'project and it refuses the link-sending endpoint. Ask your administrator to turn it off '
      'in Supabase → Authentication → Attack Protection.',
      operatorFault: true,
    );
  }

  // DOES NOT FIRE ON THIS PROJECT, and is kept anyway — with a sentence naming the setting and
  // the exact value, rather than the silent retry it used to trigger. Measured 2026-09-01:
  // /auth/v1/otp accepts any redirect_to and substitutes the Site URL for one it does not like,
  // so this branch is unreachable against today's GoTrue. If a future version starts validating
  // out loud, the right answer is a dashboard field, and a generic "try again in a few minutes"
  // would send an operator hunting a fault that no retry can reach.
  if (m.contains('redirect') && (m.contains('not allowed') || m.contains('invalid'))) {
    debugPrint('verification link REFUSED over redirect_to: $raw');
    return VerificationFailure(
      'Nivora cannot send verification links yet: the address the link comes back to is not on '
      'this project\'s allow-list. ${Env.emailRedirectSetupHint}',
      operatorFault: true,
    );
  }

  if (code == 'over_email_send_rate_limit' ||
      e.statusCode == '429' ||
      m.contains('only request this once') ||
      m.contains('rate limit') ||
      m.contains('too many')) {
    return VerificationFailure(
      'A link was just sent. Check your inbox — and your spam folder — before asking for '
      'another.',
      retryAfter: _throttleFrom(raw),
    );
  }

  // `create_user: false` and the address had no account. Verified live on 2026-09-01: this
  // project answers 422 `otp_disabled` / "Signups not allowed for otp". The address came from
  // the caller's own profile row, so this means public.users and auth.users disagree about it —
  // a half-created account, not something the user typed wrong.
  if (code == 'otp_disabled' || m.contains('signups not allowed') || m.contains('user not found')) {
    debugPrint('verification link: no auth user for the profile address: $raw');
    return const VerificationFailure(
      'Nivora could not find a mailbox for this account. The address on your profile does not '
      'match the one you sign in with — ask your administrator to correct it.',
    );
  }

  if (m.contains('error sending') || m.contains('smtp') || m.contains('mail')) {
    debugPrint('SMTP refused the verification email: $raw');
    return const VerificationFailure(
      'Nivora could not send the email just now. If this keeps happening, the project has no '
      'working mail sender configured — ask your administrator to check Supabase → '
      'Authentication → Emails.',
      operatorFault: true,
    );
  }

  debugPrint('verification link send failed: $raw');
  return const VerificationFailure(
    'Nivora could not send the link. Please try again in a few minutes.',
  );
}

/// The number of seconds out of GoTrue's own refusal.
///
/// "For security purposes, you can only request this once every 60 seconds" — reading the 60
/// from the sentence means the button comes back exactly when the server starts saying yes,
/// rather than when the client guessed. No match falls back to the documented default.
Duration _throttleFrom(String message) {
  final match = RegExp(r'(\d+)\s*second').firstMatch(message);
  final seconds = int.tryParse(match?.group(1) ?? '');
  if (seconds != null && seconds > 0 && seconds <= 3600) return Duration(seconds: seconds);
  return SupabaseEmailVerificationService._defaultCooldown;
}

/// Turns the Edge Function's `{ ok: false, error: "..." }` envelope into one sentence.
VerificationFailure _statusFailureFrom(FunctionException e) {
  final message = _messageFrom(e.details);

  if (e is FunctionsFetchException || e.status == 0) {
    return const VerificationFailure(
      'Cannot reach Nivora. Check your connection and try again.',
    );
  }

  return switch (e.status) {
    401 => VerificationFailure(
        message ?? 'Your session has ended. Sign in again to continue.',
      ),
    // 404 means the email-verification Edge Function is not deployed on this project — the
    // app is asking for a server feature that was never installed. It cost a live debugging
    // session to work that out from "could not do that", because a missing deployment and a
    // transient server error read identically to whoever is holding the phone. They are not
    // the same: one is fixed by waiting, the other never resolves on its own.
    404 => VerificationFailure(
        message ?? 'Email verification is not available on this server yet. '
            'Ask your administrator to enable it.',
        operatorFault: true,
      ),
    _ => VerificationFailure(
        message ?? 'Nivora could not check your address just now. Please try again.',
      ),
  };
}

String? _messageFrom(Object? details) {
  if (details is Map) {
    final error = details['error'];
    if (error is String && error.trim().isNotEmpty) return error.trim();
  }
  return null;
}

/// The live service. Lazy, so a widget test that overrides it never touches
/// [Supabase.instance] — which throws when the app has not been initialised, i.e. in every test.
final emailVerificationServiceProvider = Provider<EmailVerificationService>(
  (ref) => SupabaseEmailVerificationService(Supabase.instance.client),
);

/// THE RE-CHECK THE WHOLE LINK FLOW TURNS ON.
///
/// The user leaves Nivora to open a link in a browser or a mail app. Nothing tells the app when
/// they are done, and there is nothing to poll for cheaply — the proof is written by the server
/// the first time it is asked. So the app asks when it comes back to the foreground, which is
/// exactly the moment the answer is most likely to have changed. Both the banner and the
/// verification screen call this on [AppLifecycleState.resumed]; both are mounted at once while
/// the screen is open, which is why the in-flight future is shared rather than fired twice.
///
/// NOT A TIMER. A poll would spend requests on an instance that is already short of RAM, on the
/// overwhelmingly common case where the user has not opened their mail yet.
///
/// FAILURES ARE SILENT, and that is the right direction: a resume-time check that turned a
/// dropped request into an error would put a red message on the home screen of someone who has
/// done nothing wrong. The banner simply stays, and the next resume tries again. The explicit
/// "I have opened the link" button on the verification screen calls [status] directly, so a
/// check the user ASKED for still reports what went wrong.
class EmailVerificationRecheck {
  EmailVerificationRecheck(this._ref);

  final Ref _ref;
  Future<bool>? _inFlight;
  bool _startupChecked = false;

  /// True when the address is now proved. Never throws.
  Future<bool> run() => _inFlight ??= _run().whenComplete(() => _inFlight = null);

  /// THE ONE CHECK THAT IS NOT TRIGGERED BY A RESUME, AND THE CASE IT EXISTS FOR.
  ///
  /// Tapping the link on the phone can COLD-START Nivora: Android launches the app with the
  /// VIEW intent, so there is no background-to-foreground transition and
  /// `didChangeAppLifecycleState` never fires. The banner would then sit on a freshly launched
  /// home screen asking for a proof the user gave thirty seconds ago — the exact dead end this
  /// rebuild is meant to remove.
  ///
  /// So the banner also asks once when it first mounts. ONCE PER APP RUN, not once per mount:
  /// this provider lives for the life of the [ProviderScope], the flag is set before the request
  /// starts, and [run] returns immediately for any account that does not owe a proof. The worst
  /// case is therefore a single extra `status` call per launch, for the accounts that are
  /// actually waiting on one — which is the cheapest thing that can close a cold start, and far
  /// cheaper than the poll it replaces the need for.
  ///
  /// It does not matter that this can run BEFORE supabase_flutter has finished exchanging the
  /// deep link's code: the proof was minted by GoTrue when it matched the emailed token, one
  /// redirect earlier and before this process existed. Nothing the app does afterwards creates
  /// it, so nothing the app does afterwards has to be waited for.
  Future<bool> runOnceOnStartup() {
    if (_startupChecked) return Future.value(false);
    _startupChecked = true;
    return run();
  }

  Future<bool> _run() async {
    final session = _ref.read(sessionProvider);
    if (session == null) return false;
    // Nothing to ask about: already proved, or an address that can never be proved.
    if (!session.needsEmailVerification) return session.emailVerifiedAt != null;

    try {
      final status = await _ref.read(emailVerificationServiceProvider).status();
      if (!status.verified) return false;
      // The proof is written by the Edge Function with the service role, so nothing in this app
      // would ever notice it otherwise and the banner would sit there after the link was
      // opened. See AuthController.reload().
      await _ref.read(authControllerProvider.notifier).reload();
      return true;
    } catch (e) {
      debugPrint('email verification re-check skipped: ${e.runtimeType} $e');
      return false;
    }
  }
}

final emailVerificationRecheckProvider = Provider<EmailVerificationRecheck>(
  EmailVerificationRecheck.new,
);
