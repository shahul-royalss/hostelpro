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
/// Null is a real answer here, not an error. Several RPCs end in `where app.is_super_admin()`,
/// which returns zero rows to everyone else — a refusal expressed as emptiness. Callers must
/// not read that as "the platform is empty".
Map<String, dynamic>? rpcRow(Object? data, String fn) {
  final rows = rpcRows(data, fn);
  return rows.isEmpty ? null : rows.first;
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
