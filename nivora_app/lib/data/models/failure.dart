library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether the operation a failure interrupted is known NOT to have taken effect.
///
/// WHY THIS IS NOT A DETAIL. "We confirmed nothing happened" and "we stopped waiting and do not
/// know" are opposite messages. The first lets a resident tap Pay again; the second must not,
/// because the first attempt may be settling on a server this phone cannot currently see. There
/// is no third option and there is no defaulting to the comfortable one — a request that was
/// refused, or that never left the handset, is [none]; a request whose answer never arrived is
/// [unknown], and every screen downstream has to say so out loud.
enum SideEffect {
  /// Nothing changed on the server. The request was refused, rejected, or never landed.
  none,

  /// The request may or may not have taken effect. Never render this as "nothing happened",
  /// never offer a plain "try again" that would repeat a side effect, and never show a figure
  /// derived from the assumption that it failed.
  unknown,
}

/// What went wrong, in terms a screen can act on.
///
/// THE POINT OF THIS FILE. "Something went wrong" is the worst sentence in software. The four
/// things that actually happen here are genuinely different and want genuinely different
/// screens: the phone has no signal (retry), the server refused (nothing to retry — say who to
/// ask), the subscription lapsed (renew), or the input was rejected (fix the field). Postgres
/// already tells us which, in the SQLSTATE. Collapsing that into one string throws away the
/// only information the user could have used.
///
/// In particular 42501 is `insufficient_privilege`. It means "you do not have access to that",
/// and every write RPC in db/schema.sql raises it deliberately. Rendering it as a crash trains
/// staff to file bugs about permissions working correctly.
///
/// ═══ THE FOUR STATES A SCREEN HAS TO TELL APART ═══
/// LOADING, EMPTY, FAILED and REFUSED are four different facts and must not draw the same
/// picture. Three of them live here: a failure that is [isRetryable] is FAILED, one that is
/// [isRefusal] is REFUSED, one that [isAbsence] is the thing genuinely not being there. EMPTY
/// is the fourth and is NOT a failure at all — it is a successful read with no rows, and the
/// only way a repository is allowed to say it. Which is why a repository must never hand back
/// an empty list or a bare null for a row the server refused: doing so spends the one signal
/// that means "there are none of these" on a fact that is nothing like it.
sealed class AppFailure implements Exception {
  const AppFailure(
    this.message, {
    this.technical,
    this.sideEffect = SideEffect.none,
  });

  /// Safe and useful to put in front of a user, verbatim.
  final String message;

  /// The underlying driver text. For logs and bug reports; never for the UI.
  final String? technical;

  /// Whether the thing being attempted is known not to have happened. See [SideEffect].
  final SideEffect sideEffect;

  /// True when trying the same thing again could plausibly work AND could not do harm.
  ///
  /// BOTH HALVES ARE LOAD-BEARING, and the second one is new. Every screen in this app draws
  /// its Try again button from this getter, so a failure that reports itself retryable is a
  /// failure that gets a button pressed. That is right for a read — asking the same question
  /// twice costs nothing — and wrong for anything whose outcome is [SideEffect.unknown], where
  /// the button would repeat a write that may already have landed. "Retryable" therefore means
  /// SAFE TO REPEAT, never merely "worth checking on": the settlement watch's three verdicts
  /// (see settlementUpdates) are worth checking on and are deliberately not repeatable, because
  /// the only repeat available there is paying again.
  bool get isRetryable =>
      !outcomeIsUnknown && (this is OfflineFailure || this is ServerFailure);

  /// The server said no and meant it. Retrying cannot help and a retry button must not be
  /// drawn; the honest screen is a plain sentence about who to ask.
  bool get isRefusal => this is AccessDeniedFailure || this is ReadOnlyFailure;

  /// The row is not there for this caller — deleted, another tenant's, or hidden by a policy.
  /// NOT the same as a query that legitimately matched nothing, which is not a failure at all.
  bool get isAbsence => this is NotFoundFailure;

  /// THE CREDENTIAL IS THE PROBLEM, NOT THE PERSON. Nothing on the screen can fix this and no
  /// retry can either; the one action that helps is signing in again, and a screen that reports
  /// one of these owes the reader that button.
  ///
  /// It is deliberately NOT folded into [isRefusal]. A refusal is a verdict about who somebody
  /// is and is answered by asking someone else for access; this is a statement about a token
  /// and is answered by getting a new one. Rendering the second as the first is the exact
  /// mistake that sent a super admin chasing an account problem that did not exist — see
  /// core/auth/session_standing.dart for the mechanism.
  bool get needsSignIn => this is SignedOutFailure || this is SessionExpiredFailure;

  /// WE DO NOT KNOW WHETHER IT HAPPENED. The loudest thing this class can say, and the one a
  /// screen is most tempted to round down to "nothing happened". See [SideEffect.unknown].
  bool get outcomeIsUnknown => sideEffect == SideEffect.unknown;

  @override
  String toString() => '$runtimeType: $message${technical == null ? '' : ' ($technical)'}';

  /// Classifies anything a repository can throw.
  ///
  /// Deliberately total: the final branch is [UnexpectedFailure], so a new error type from a
  /// dependency degrades to a generic message instead of escaping as a raw exception.
  static AppFailure from(Object error) {
    if (error is AppFailure) return error;

    if (error is PostgrestException) return _fromPostgrest(error);

    if (error is AuthException) return _fromAuth(error);

    // A TIMEOUT IS NOT THE SAME AS A DEAD SOCKET, even though both end up offline-shaped. A
    // request that was sent and never answered may well have been applied; one that could not
    // resolve a host or was refused at the socket never reached Postgres at all. The transport
    // classification is NOT identical (see [timedOut]), the [SideEffect] is not either, and for
    // a write that second difference is the difference between "tap it again" and "go and look
    // before you tap it again".
    //
    // [SideEffect.unknown] is the default here because this entry point does not know what it
    // is classifying. [guard] and [guardWrite] do know, and each says so.
    if (error is TimeoutException) {
      return timedOut(error, sideEffect: SideEffect.unknown);
    }

    if (_looksOffline(error)) {
      return OfflineFailure(
        'Cannot reach Nivora. Check your connection and try again.',
        technical: error.toString(),
      );
    }

    return UnexpectedFailure(
      'Something did not work. Please try again.',
      technical: error.toString(),
    );
  }

  /// The failure a request that WAS SENT AND NEVER ANSWERED becomes.
  ///
  /// ═══ WHY THIS IS A ServerFailure AND NOT AN OfflineFailure ═══
  /// It used to be the latter, worded "check your connection and try again", and that sentence
  /// is false in the exact situation it was written for. Reaching a deadline means the DNS
  /// lookup resolved, the TCP connection was accepted, the TLS handshake completed and the
  /// request went out — every one of which needs a working connection. What did not happen is
  /// an answer. Telling that person to check their Wi-Fi sends them to reboot a router while
  /// the backend is the thing that is down, which is precisely what happened here for the 24
  /// hours the server was wedged. [OfflineFailure]'s own doc says "the request never reached
  /// the server"; for a timeout that is not true, so it is not the type.
  ///
  /// The classification is also what the four role UIs already read: their exhaustive switches
  /// word [OfflineFailure] as "No connection — check your Wi-Fi" and [ServerFailure] as "the
  /// server did not answer in time", and the second is the one that is true.
  ///
  /// [sideEffect] is the caller's to state and cannot be guessed from the exception: a read
  /// that timed out changed nothing (there was nothing to change), a write that timed out may
  /// have committed on a server this phone can no longer hear. [unresolved] is the sentence
  /// that says what to do about that second case, and belongs to whoever knows what was being
  /// written — a fee row and a task row deserve different advice.
  static ServerFailure timedOut(
    Object error, {
    required SideEffect sideEffect,
    String? unresolved,
  }) {
    final message = sideEffect == SideEffect.unknown
        ? 'The Nivora server stopped responding before it confirmed this, so nobody can say '
            'yet whether it went through. ${unresolved ?? 'Check before doing it again.'}'
        : 'The Nivora server is not responding right now. Your connection is fine — this '
            'usually clears in a few minutes.';
    return ServerFailure(
      message,
      technical: 'no answer within the client deadline: $error',
      sideEffect: sideEffect,
    );
  }

  /// ═══ NOT EVERY AuthException MEANS "YOUR SESSION HAS ENDED" ═══
  /// Until this method existed, every one of them did: the branch above said so in one line,
  /// and the line was wrong for the most common case on this instance.
  ///
  /// The exception this app actually sees most is [AuthRetryableFetchException], which gotrue
  /// throws when a token refresh could not REACH the Auth server — a dropped socket, a gateway
  /// 5xx, or one of the Unhealthy windows the free-tier NANO produces several times a day. It
  /// arrives here because `SupabaseClient._getAccessToken()` refreshes an expired token inline
  /// before a PostgREST call and rethrows what the refresh threw (supabase_client.dart:282-291).
  /// Nothing about it says the session is over — gotrue deliberately KEEPS the session on this
  /// branch and retries — so reporting it as a sign-out threw people out of a working account
  /// because a packet went missing.
  ///
  /// Three outcomes, and the difference between them is what the reader is supposed to do:
  ///   · could not ask         → [OfflineFailure] / [ServerFailure], and it is worth retrying
  ///   · the session is over   → [SessionExpiredFailure], and only signing in again helps
  ///   · anything else         → [SignedOutFailure], the conservative old answer
  static AppFailure _fromAuth(AuthException e) {
    if (e is AuthRetryableFetchException) {
      // gotrue wraps the transport error's own text, so the offline sniffer still works on it.
      if (_looksOffline(e.message)) {
        return OfflineFailure(
          'Cannot reach Nivora. Check your connection and try again.',
          technical: 'auth refresh could not reach the server: ${e.message}',
        );
      }
      return ServerFailure(
        'Nivora is having trouble right now. Try again in a moment.',
        technical: 'auth refresh failed and is retryable: ${e.message} (${e.statusCode})',
      );
    }

    // The codes GoTrue uses when the REFRESH TOKEN itself is finished — spent, rotated away,
    // revoked, or belonging to a session the server has forgotten. There is nothing left to
    // refresh, and the person is not signed in any more even though this app is still holding
    // bytes that look like a session.
    const finished = {
      'session_expired',
      'session_not_found',
      'refresh_token_not_found',
      'refresh_token_already_used',
      'session_missing',
    };
    if (e is AuthSessionMissingException || finished.contains(e.code)) {
      return SessionExpiredFailure(
        _signInAgain,
        technical: '${e.code ?? e.runtimeType}: ${e.message}',
      );
    }

    return SignedOutFailure(
      'Your session has ended. Sign in again to continue.',
      technical: e.message,
    );
  }

  /// What an expired credential says, in every role's words, because it is the same sentence
  /// for all five: nothing is wrong with the account and nothing is wrong with the phone.
  static const _signInAgain =
      'Your sign-in expired, so Nivora could not ask the server on your behalf. Nothing is '
      'wrong with your account — sign in again to carry on.';

  static AppFailure _fromPostgrest(PostgrestException e) {
    final code = e.code;
    final text = e.message.toLowerCase();

    switch (code) {
      // insufficient_privilege — RLS refused the row, or one of our RPCs raised it on purpose.
      case '42501':
        // §4.4: an expired subscription blocks writes with this same code. It is a completely
        // different conversation from "you are not allowed", so it gets its own type. The
        // server writes the message; matching on it is how we tell the two apart.
        if (text.contains('read-only') ||
            text.contains('read only') ||
            text.contains('subscription expired')) {
          return ReadOnlyFailure(
            'This hostel is read-only until the subscription is renewed.',
            technical: e.message,
          );
        }
        // "permission denied for FUNCTION/TABLE x" names the database ROLE, not the person, and
        // that distinction is the whole diagnosis. A signed-in caller is `authenticated`, which
        // holds EXECUTE on every RPC this app calls. `anon` does not — EXECUTE was revoked from
        // it deliberately. And a dead session does not make a request fail: supabase-2.16.1
        // auth_http_client.dart:24-32 falls back to the anon key when there is no access token,
        // so an unrefreshable token turns every call into an ANONYMOUS one. The 42501 that comes
        // back is therefore evidence about the TOKEN, never about the account's role.
        //
        // Reported as a role refusal, it produced the sentence that cost a live debugging
        // session: a super admin with a genuinely aal2 session, told to "sign in with the Super
        // Admin account" while already signed in as exactly that.
        // FUNCTION only, deliberately. "permission denied for TABLE x" can legitimately reach a
        // signed-in user — a table `authenticated` holds no grant on — and calling that an
        // expired session would just be a new lie in place of the old one. Every RPC this app
        // calls is granted to `authenticated`, so a refused FUNCTION can only mean the caller
        // was `anon`. test/refusal_honesty_test.dart pins the table case as a real refusal.
        if (text.contains('permission denied for function')) {
          return SessionExpiredFailure(
            'Your session has expired. Sign in again to continue.',
            technical: e.message,
          );
        }
        return AccessDeniedFailure(
          'You do not have access to that.',
          technical: e.message,
        );

      // PostgREST could not return exactly one row for .single().
      case 'PGRST116':
        return NotFoundFailure(
          'That record no longer exists.',
          technical: e.message,
        );

      // The JWT is missing, malformed or expired.
      //
      // EXPIRED IS ITS OWN ANSWER. PostgREST says "JWT expired" in as many words, and that is
      // the single most likely 401 this app produces: the access token lives one hour and the
      // background refresh that should renew it fails whenever this instance flips Unhealthy.
      // "Your session has ended" is true but reads as a revocation; the expired sentence says
      // the account is fine, which is the part the reader needs before they start changing
      // things that were never broken.
      case 'PGRST301':
      case '401':
        if (text.contains('expired')) {
          return SessionExpiredFailure(_signInAgain, technical: '${e.code}: ${e.message}');
        }
        return SignedOutFailure(
          'Your session has ended. Sign in again to continue.',
          technical: e.message,
        );

      case '403':
        return AccessDeniedFailure(
          'You do not have access to that.',
          technical: e.message,
        );

      // unique_violation — the row already exists. The unique indexes this hits are all
      // meaningful: one active student per bed, one phone per resident, one fee row per month.
      case '23505':
        return ConflictFailure(
          _conflictMessage(text),
          technical: e.message,
        );

      // foreign_key_violation — pointing at something that is gone.
      case '23503':
        return InvalidInputFailure(
          'That refers to something that no longer exists. Reload and try again.',
          technical: e.message,
        );

      // not_null_violation / check_violation / invalid_text_representation.
      case '23502':
      case '23514':
      case '22P02':
        return InvalidInputFailure(
          'Some of that information is not valid. Check the fields and try again.',
          technical: e.message,
        );

      // raise_exception — every one of these in db/schema.sql carries a message written FOR a
      // user ("That student has been checked out", "Amount must be greater than zero"). Pass
      // it through unchanged; rewriting it here would lose the specificity.
      case 'P0001':
        return InvalidInputFailure(e.message, technical: e.message);

      // statement_timeout / query_canceled.
      case '57014':
        return ServerFailure(
          'That took too long. Try again in a moment.',
          technical: e.message,
        );

      default:
        // PostgREST reports transport-level trouble here too; a 5xx is worth retrying.
        if (code != null && code.startsWith('5')) {
          return ServerFailure(
            'Nivora is having trouble right now. Try again in a moment.',
            technical: '${e.code}: ${e.message}',
          );
        }
        return UnexpectedFailure(
          'Something did not work. Please try again.',
          technical: '${e.code}: ${e.message}',
        );
    }
  }

  static String _conflictMessage(String lowercaseMessage) {
    if (lowercaseMessage.contains('students_one_active_per_bed')) {
      return 'That bed is already taken by another resident.';
    }
    if (lowercaseMessage.contains('students_phone_active_key')) {
      return 'A resident with that phone number is already registered.';
    }
    if (lowercaseMessage.contains('fee_payments') || lowercaseMessage.contains('period_month')) {
      return 'A payment for that month is already recorded.';
    }
    if (lowercaseMessage.contains('beds_student_key')) {
      return 'That resident is already assigned to a bed.';
    }
    if (lowercaseMessage.contains('rooms_hostel_id_room_number')) {
      return 'A room with that number already exists.';
    }
    return 'That already exists.';
  }

  /// dart:io's SocketException and package:http's ClientException are the two shapes a dead
  /// connection arrives in. Neither package is a direct dependency of this app, and importing
  /// one to `is`-check it would both trip depend_on_referenced_packages and break a web build,
  /// so this matches on the type name instead. Ugly, contained, and documented.
  static bool _looksOffline(Object error) {
    final text = '${error.runtimeType} $error'.toLowerCase();
    return text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('handshakeexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection closed') ||
        text.contains('connection reset') ||
        text.contains('network is unreachable') ||
        text.contains('software caused connection abort');
  }
}

/// No usable network. The request never reached the server, so nothing changed.
final class OfflineFailure extends AppFailure {
  const OfflineFailure(super.message, {super.technical, super.sideEffect = SideEffect.none});
}

/// RLS said no. Retrying will not help; the user needs a different account or a role change.
final class AccessDeniedFailure extends AppFailure {
  const AccessDeniedFailure(super.message, {super.technical, super.sideEffect = SideEffect.none});
}

/// Hard rule §4.4 — the hostel's subscription lapsed, so reads still work and writes do not.
final class ReadOnlyFailure extends AppFailure {
  const ReadOnlyFailure(super.message, {super.technical, super.sideEffect = SideEffect.none});
}

/// The row is gone, or RLS hides it so completely it may as well be.
final class NotFoundFailure extends AppFailure {
  const NotFoundFailure(super.message, {super.technical, super.sideEffect = SideEffect.none});
}

/// A uniqueness rule was hit — usually someone else got there first.
final class ConflictFailure extends AppFailure {
  const ConflictFailure(super.message, {super.technical, super.sideEffect = SideEffect.none});
}

/// The server rejected the values. The message comes from the database and is user-facing.
final class InvalidInputFailure extends AppFailure {
  const InvalidInputFailure(super.message, {super.technical, super.sideEffect = SideEffect.none});
}

/// The session is no longer valid. The router signs the user out on this.
final class SignedOutFailure extends AppFailure {
  const SignedOutFailure(super.message, {super.technical, super.sideEffect = SideEffect.none});
}

/// THE APP IS HOLDING A CREDENTIAL THE SERVER WILL NOT ACCEPT ANY MORE — or is holding none at
/// all while still behaving as though it were signed in.
///
/// ═══ WHY THIS IS NOT SignedOutFailure, AND EMPHATICALLY NOT AccessDeniedFailure ═══
/// It is separate from [SignedOutFailure] because the two are different events with different
/// sentences. Signed out is a verdict — the identity was rejected, or deliberately ended. This
/// is an accident of time and network: the access token lives one hour, the background refresh
/// that renews it failed, and the app went on asking questions with a token nobody will honour.
/// The account is untouched; the person did nothing; there is no administrator to call.
///
/// It is separate from [AccessDeniedFailure] because that one is the sentence that cost this
/// project two live debugging sessions. When the session dies, `SupabaseClient` falls back to
/// the ANON key rather than sending nothing (see core/auth/session_standing.dart), every RPC
/// that ends in `where app.is_super_admin()` answers zero rows exactly as it would for a real
/// impostor, and the console told its own super admin to go and find the right account. The
/// server never said that. This type is what the app says instead once it has checked which
/// credential actually asked the question.
///
/// NOT RETRYABLE — the same request with the same dead token fails the same way — and NOT a
/// refusal. [AppFailure.needsSignIn] is true, and every role's error surface reads that and
/// offers the one action that works.
final class SessionExpiredFailure extends AppFailure {
  const SessionExpiredFailure(super.message,
      {super.technical, super.sideEffect = SideEffect.none});
}

/// The server failed on its own account. Worth one retry.
final class ServerFailure extends AppFailure {
  const ServerFailure(super.message, {super.technical, super.sideEffect = SideEffect.none});
}

/// Everything else, including a client/database shape disagreement (see RowShapeError).
final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure(super.message, {super.technical, super.sideEffect = SideEffect.none});
}

/// ─────────────────────────────────────────────────────────────────────────────
/// THE DEADLINE
/// ─────────────────────────────────────────────────────────────────────────────

/// How long ONE call into the data layer may take before this app stops waiting for it.
///
/// ═══ WHY A NUMBER HAS TO BE WRITTEN DOWN HERE AT ALL ═══
/// Dart's HTTP client has no default request timeout. A socket that was accepted and is then
/// never answered — which is exactly the shape of a wedged Postgres or a gateway with nothing
/// behind it — leaves the future pending for minutes, and the screen above it renders a
/// skeleton for every one of them. Every "the app hung" report from the 24-hour outage last
/// week is this: not a crash, not an error, an unbounded LOADING state. The four states this
/// data layer is built around collapse to one whenever a read is allowed to take forever,
/// because FAILED can only be reached by a call that agrees to stop.
///
/// ═══ WHY TWELVE SECONDS ═══
/// Measured against the live project (nimxvgzscbanhtvgnjll) from this machine today: 0.77s for
/// the first request including DNS, TCP and TLS, then 0.30–0.36s on a warm connection. Twelve
/// seconds is therefore between 15× and 40× a healthy round trip — so far outside normal that
/// reaching it is evidence rather than noise, with room to spare for a slow mobile handover, a
/// cold Postgres connection and a query that is merely unlucky. It is also short enough that a
/// person still has the screen in front of them when the answer arrives, which is what makes
/// the Retry button on the error state a real offer rather than an apology.
///
/// It is deliberately SHORTER than the 15s the sign-in path allows (core/auth/auth_controller
/// .dart). Signing in is a one-shot the user cannot route around and is worth waiting longer
/// for; a list read is repeatable, its screen has a Retry, and the sooner it admits defeat the
/// sooner that Retry appears.
///
/// ONE CONSTANT, NOT A FAMILY OF THEM. Both guards take it as an overridable default so a call
/// site with a genuinely different shape can say so in a sentence — no call site needs to yet,
/// and tests use it to reach the timeout without waiting twelve real seconds.
const dataDeadline = Duration(seconds: 12);

/// Runs a READ and converts anything it throws — including running out of time — into an
/// [AppFailure].
///
/// Every repository method is wrapped in this or in [guardWrite], which is what lets the rest
/// of the app catch one sealed type and switch on it exhaustively, and is now also what puts a
/// deadline on every single call without a `.timeout()` appearing in any repository.
///
/// ═══ USE [guardWrite] IF THE CALL CHANGES ANYTHING WHOSE REPEAT WOULD DOUBLE IT ═══
/// A timeout classified by this function says the outcome is [SideEffect.none] — nothing
/// happened — which is free for a read and a lie for an INSERT. Reads, and writes that the
/// server makes idempotent (setting a column to a value it will hold anyway, an upsert on a
/// unique key, an RPC that no-ops the second time), belong here; each such write says so in a
/// comment at its own call site. Everything else belongs in [guardWrite].
///
/// THE DEADLINE COVERS THE WHOLE BODY, not each await inside it. A method that makes two round
/// trips (DashboardRepository, ManagerRepository.taskCounts) gets [deadline] for both together,
/// because what the screen is waiting for is the method, not its halves.
Future<T> guard<T>(Future<T> Function() body, {Duration deadline = dataDeadline}) =>
    _deadlined(body, deadline, SideEffect.none, null);

/// Runs a WRITE whose repetition would double something, and says so honestly if it times out.
///
/// ═══ THE ONLY HONEST THING TO SAY ABOUT A WRITE THAT RAN OUT OF TIME ═══
/// Giving up on the answer does not cancel the request. `Future.timeout` stops this app
/// waiting; it does not reach across the network and un-send anything, and the transaction may
/// be committing at the instant the deadline passes. So a timed-out write is [SideEffect
/// .unknown], it is not [AppFailure.isRetryable] (no screen may offer a plain Try again that
/// would send it a second time), and it is NEVER reported as a failure — "that did not work"
/// is a statement of fact this app does not have.
///
/// [unresolved] is what the person should do instead, written for the specific thing being
/// written: where to look to find out whether it landed. It is required because a generic
/// "check before doing it again" is useless to someone holding ₹8,000 in cash.
Future<T> guardWrite<T>(
  Future<T> Function() body, {
  required String unresolved,
  Duration deadline = dataDeadline,
}) =>
    _deadlined(body, deadline, SideEffect.unknown, unresolved);

Future<T> _deadlined<T>(
  Future<T> Function() body,
  Duration deadline,
  SideEffect onTimeout,
  String? unresolved,
) async {
  try {
    return await body().timeout(deadline);
  } on TimeoutException catch (error, stack) {
    // Classified here rather than in [AppFailure.from], which cannot know whether it is looking
    // at a read or a write and so has to assume the cautious one.
    Error.throwWithStackTrace(
      AppFailure.timedOut(error, sideEffect: onTimeout, unresolved: unresolved),
      stack,
    );
  } catch (error, stack) {
    Error.throwWithStackTrace(AppFailure.from(error), stack);
  }
}
