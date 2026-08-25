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

  /// True when trying the same thing again could plausibly work.
  bool get isRetryable => this is OfflineFailure || this is ServerFailure;

  /// The server said no and meant it. Retrying cannot help and a retry button must not be
  /// drawn; the honest screen is a plain sentence about who to ask.
  bool get isRefusal => this is AccessDeniedFailure || this is ReadOnlyFailure;

  /// The row is not there for this caller — deleted, another tenant's, or hidden by a policy.
  /// NOT the same as a query that legitimately matched nothing, which is not a failure at all.
  bool get isAbsence => this is NotFoundFailure;

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

    if (error is AuthException) {
      return SignedOutFailure(
        'Your session has ended. Sign in again to continue.',
        technical: error.message,
      );
    }

    // A TIMEOUT IS NOT THE SAME AS A DEAD SOCKET, even though both end up offline-shaped. A
    // request that was sent and never answered may well have been applied; one that could not
    // resolve a host or was refused at the socket never reached Postgres at all. The transport
    // classification is identical, the [SideEffect] is not, and for a write that difference is
    // the difference between "tap it again" and "go and look before you tap it again".
    if (error is TimeoutException) {
      return OfflineFailure(
        'Nivora did not answer in time. Check your connection and try again.',
        technical: error.toString(),
        sideEffect: SideEffect.unknown,
      );
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
      case 'PGRST301':
      case '401':
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

/// The server failed on its own account. Worth one retry.
final class ServerFailure extends AppFailure {
  const ServerFailure(super.message, {super.technical, super.sideEffect = SideEffect.none});
}

/// Everything else, including a client/database shape disagreement (see RowShapeError).
final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure(super.message, {super.technical, super.sideEffect = SideEffect.none});
}

/// Runs a database call and converts anything it throws into an [AppFailure].
///
/// Every repository method is wrapped in this, which is what lets the rest of the app catch
/// one sealed type and switch on it exhaustively.
Future<T> guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } catch (error, stack) {
    Error.throwWithStackTrace(AppFailure.from(error), stack);
  }
}
