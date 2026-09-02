library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/session_standing.dart';
import '../models/models.dart';

export '../../core/auth/session_standing.dart' show SessionStanding;

/// Shared plumbing for every repository.
///
/// THE RULE THESE CLASSES ENFORCE BY SHAPE. A repository returns models, never raw maps. A
/// `Map<String, dynamic>` leaking into a widget puts `row['montly_fee']` one typo away from a
/// blank field that nobody notices for a month; a model puts the same typo in front of the
/// analyzer. Every method here therefore ends in a `fromJson` and a wrap in [guard].
///
/// AND THE RULE THEY DO NOT ENFORCE. None of this is a security boundary. The `.eq('hostel_id',
/// …)` filters below are there so the server does less work and the screen gets the rows it
/// asked for — they are NOT what stops one hostel reading another's residents. That is
/// row-level security, evaluated against the JWT, and it would still hold if every filter in
/// this directory were deleted.
abstract base class Repository {
  const Repository(this.db);

  /// The anon-key client. There is no other client in this app, by design.
  final SupabaseClient db;

  /// WHAT CREDENTIAL THE QUESTION WAS ASKED WITH, sampled at the moment an answer is being
  /// interpreted rather than at the moment it was sent.
  ///
  /// Read it ONLY to decide what a SILENCE meant. It is not a permission check and it does not
  /// gate anything: row-level security decides what may be read, and it does so against the
  /// token the server received, not against this. What it is for is the three helpers below,
  /// each of which is about to make a claim concerning WHO THE CALLER IS, and none of which may
  /// make that claim while this app cannot vouch for the token it sent.
  ///
  /// The full mechanism, and the live incident that produced it, are in
  /// core/auth/session_standing.dart. The short version: a dead session does not make requests
  /// fail, it makes them go out as `anon`, and `anon` is refused in exactly the same shape as a
  /// person in the wrong role.
  SessionStanding get sessionStanding => sessionStandingOf(db);

  /// REFUSE TO ASK A QUESTION THIS CLIENT CANNOT SIGN, when a null answer to it would be read
  /// as a fact about the caller.
  ///
  /// The `.maybeSingle()` reads in this layer all document their null the same way — "null when
  /// the row is not visible to this caller" — and every screen above them turns that into a
  /// sentence about the reader: "no resident record for this account", "it belongs to another
  /// hostel". Those are true when the server looked at a real credential and declined. They are
  /// invented when the request went out under the anon key because the session had died, which
  /// is what supabase does rather than failing (core/auth/session_standing.dart).
  ///
  /// So this is a PRE-FLIGHT, not a post-hoc reinterpretation: called before the request, it
  /// keeps the anonymous read from happening at all. It is emphatically NOT an authorization
  /// check — row-level security is, on the server, against the token it actually received. All
  /// this decides is whether asking could produce an answer worth believing.
  ///
  /// [what] names the read, for the technical text only.
  void requireLiveSession(String what) {
    final failure = credentialFailure(sessionStanding, what);
    if (failure != null) throw failure;
  }
}

/// WHAT THE CREDENTIAL ITSELF MAKES OF THIS, or null when the credential was good and any
/// emptiness is therefore genuinely about the caller.
///
/// The one rule, in one place, used two ways: [Repository.requireLiveSession] asks it BEFORE a
/// read whose null would be read as a fact about the reader, and the three helpers below ask it
/// AFTER an empty answer they were about to attribute to somebody. Both need the same sentence,
/// and the one thing worse than a misleading refusal is two of the three sites being fixed.
///
/// [context] names the read and appears only in [AppFailure.technical], which debugPrint carries
/// and release builds strip.
AppFailure? credentialFailure(SessionStanding standing, String context) => switch (standing) {
      SessionStanding.live => null,
      SessionStanding.none => SignedOutFailure(
          'You are not signed in any more, so Nivora asked the server as nobody. Sign in again '
          'to see this.',
          technical: '$context: this client held NO session, so the request either went out '
              'under the anon key (supabase AuthHttpClient fills the Authorization header with '
              'it) or was not worth sending — either way nothing that came back is about this '
              'account',
        ),
      SessionStanding.expired => SessionExpiredFailure(
          'Your sign-in expired before this loaded. Nothing is wrong with your account — sign '
          'in again to carry on.',
          technical: '$context: the held access token was past its expiry, so a refusal by role '
              'cannot be told apart from a refusal by dead token here and neither is claimed',
        ),
    };

/// The rows a set-returning RPC came back with.
///
/// A `returns table (...)` function always yields a JSON array, even for one row. Anything else
/// means the function was changed to return a scalar and this call site was not updated.
List<Map<String, dynamic>> rpcRows(Object? data, String fn) {
  if (data is List) {
    return data
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }
  throw RowShapeError(fn, '(result)', 'expected an array of rows, got ${data.runtimeType}');
}

/// The single row a one-row RPC came back with, or null.
///
/// PREFER [rpcRowOrRefusal] OR [rpcRowOrMissing]. This function hands back the bare null that
/// this whole file exists to get rid of: at the call site it means "refused", "not there" and
/// "the function changed shape" all at once, and every screen that has ever branched on it has
/// picked one of the three and drawn that. Use it only where a caller genuinely has all three
/// answers already — there is one such place left, in the Super Admin feature.
Map<String, dynamic>? rpcRow(Object? data, String fn) {
  final rows = rpcRows(data, fn);
  return rows.isEmpty ? null : rows.first;
}

/// The row from an RPC WHOSE EMPTINESS IS A REFUSAL, never an absence of data.
///
/// Several functions in db/schema.sql end in `where app.is_super_admin()` (rpc_sa_dashboard,
/// rpc_sa_onboarding_series). Postgres answers a caller who fails that predicate with zero
/// rows, not with 42501 — the refusal arrives dressed as emptiness, and PostgREST has no way to
/// tell us otherwise. So the meaning has to be restored here, at the only place that knows the
/// function's own WHERE clause. A platform admin console that renders this as "0 hostels, 0
/// owners, ₹0" is telling its reader their business evaporated.
///
/// [refusal] is shown to the user, so write it as the plain sentence it is: nobody is at fault,
/// and there is nothing to retry.
///
/// ═══ [standing] IS REQUIRED, AND IT IS THE WHOLE POINT OF THE 2026-09-01 CHANGE ═══
/// "The RPC's WHERE clause excluded this caller" is a claim about a PERSON, and this function
/// used to make it from the one fact that cannot support it on its own. A super admin whose
/// token had quietly died was told to go and sign in as the super admin — the account he was
/// already using. The emptiness was real; the attribution was invented.
///
/// So the refusal is now only ever named when [standing] is [SessionStanding.live]: a token
/// that existed, and had not expired, at the moment this answer was read. Anything else is a
/// statement about the credential and says so instead. Pass `sessionStanding` from [Repository]
/// — never a literal — so the value is sampled here rather than assumed.
Map<String, dynamic> rpcRowOrRefusal(
  Object? data,
  String fn, {
  required String refusal,
  required SessionStanding standing,
}) {
  final row = rpcRow(data, fn);
  if (row != null) return row;
  throw credentialFailure(standing, fn) ??
      AccessDeniedFailure(
        refusal,
        technical: '$fn returned zero rows to a live session — its WHERE clause excluded '
            'this caller',
      );
}

/// The row from an RPC WHOSE EMPTINESS MEANS THE CALLER HAS NO SUCH THING, not that the thing
/// is empty.
///
/// The distinction from [rpcRowOrRefusal] is who the answer is about: a refusal is about the
/// caller's role, an absence is about the record. Both are dead ends — [NotFoundFailure] is not
/// retryable either — but they are different sentences, and a screen that says "ask your warden
/// to check your registration" when the honest answer is "this console is staff-only" sends
/// someone to bother the wrong person.
///
/// [standing] carries the same obligation it carries on [rpcRowOrRefusal], for the same reason.
/// "Ask your warden to check your registration" is a real errand for a real person, and sending
/// a resident on it because their token expired on the bus is the student-facing shape of the
/// bug that started this.
Map<String, dynamic> rpcRowOrMissing(
  Object? data,
  String fn, {
  required String missing,
  required SessionStanding standing,
}) {
  final row = rpcRow(data, fn);
  if (row != null) return row;
  throw credentialFailure(standing, fn) ??
      NotFoundFailure(
        missing,
        technical: '$fn returned zero rows to a live session',
      );
}

/// Rows from a read WHERE AN EMPTY RESULT IS NOT A POSSIBLE ANSWER.
///
/// For most lists, empty means empty and that is a perfectly good thing for a screen to draw.
/// This is for the handful where the schema guarantees at least one row for anything that
/// exists at all — so zero rows says something about the CALLER's reach, not about the data.
/// Passing a query here is a claim about db/schema.sql; [why] is where that claim gets written
/// down, and it travels into the failure's technical text so the next person can check it.
///
/// [standing] again: "that room is not one this account can open" is a sentence about an
/// account, and a dead token produces the identical empty list.
List<Map<String, dynamic>> rowsOrMissing(
  List<Map<String, dynamic>> rows, {
  required String missing,
  required String why,
  required SessionStanding standing,
}) {
  if (rows.isNotEmpty) return rows;
  throw credentialFailure(standing, why) ?? NotFoundFailure(missing, technical: why);
}

/// The row returned by an RPC declared `returns <composite>` — for example wd_record_payment,
/// which returns one `public.fee_payments`.
///
/// Accepts a bare object OR a one-element array. Both mean the same single row, and which one
/// PostgREST sends for a composite return has not been stable across its versions — so pinning
/// this to `Map` would turn a server upgrade into a crash at the moment a cashier takes money.
/// Anything with more than one row is a genuine disagreement and still throws.
Map<String, dynamic> rpcObject(Object? data, String fn) {
  if (data is Map<String, dynamic>) return data;
  if (data is List && data.length == 1 && data.first is Map<String, dynamic>) {
    return data.first as Map<String, dynamic>;
  }
  throw RowShapeError(fn, '(result)', 'expected a single row, got ${data.runtimeType}');
}

/// Makes a user's search text safe to embed in a PostgREST `or=(...)` expression.
///
/// PostgREST parses that parameter itself: a comma starts a new condition, a dot separates
/// column from operator, and parentheses nest. Typing "Sharma, R." into a search box would
/// otherwise produce a malformed filter and a 400 — not a security hole (the request is still
/// evaluated under the caller's RLS) but a confusing failure on a completely ordinary name.
/// Wildcards are stripped for the same reason: `%` in the middle of a name is not what the
/// person typing meant.
String sanitizeSearch(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[,().*%\\"]'), ' ').trim();
  // Collapse the gaps left behind so "R.  Sharma" still matches "R Sharma".
  return cleaned.replaceAll(RegExp(r'\s+'), ' ');
}

/// Turns a zero-based page into the inclusive `.range()` bounds that fetch one extra row.
///
/// The extra row is how [PagedResult.hasMore] is known without asking Postgres for an exact count —
/// see the note on [PagedResult].
({int from, int to}) rangeFor(int page, int pageSize) {
  final from = page * pageSize;
  return (from: from, to: from + pageSize);
}
