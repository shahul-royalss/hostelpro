library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

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
}

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
Map<String, dynamic> rpcRowOrRefusal(
  Object? data,
  String fn, {
  required String refusal,
}) {
  final row = rpcRow(data, fn);
  if (row != null) return row;
  throw AccessDeniedFailure(
    refusal,
    technical: '$fn returned zero rows — its WHERE clause excluded this caller',
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
Map<String, dynamic> rpcRowOrMissing(
  Object? data,
  String fn, {
  required String missing,
}) {
  final row = rpcRow(data, fn);
  if (row != null) return row;
  throw NotFoundFailure(
    missing,
    technical: '$fn returned zero rows for this caller',
  );
}

/// Rows from a read WHERE AN EMPTY RESULT IS NOT A POSSIBLE ANSWER.
///
/// For most lists, empty means empty and that is a perfectly good thing for a screen to draw.
/// This is for the handful where the schema guarantees at least one row for anything that
/// exists at all — so zero rows says something about the CALLER's reach, not about the data.
/// Passing a query here is a claim about db/schema.sql; [why] is where that claim gets written
/// down, and it travels into the failure's technical text so the next person can check it.
List<Map<String, dynamic>> rowsOrMissing(
  List<Map<String, dynamic>> rows, {
  required String missing,
  required String why,
}) {
  if (rows.isNotEmpty) return rows;
  throw NotFoundFailure(missing, technical: why);
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
