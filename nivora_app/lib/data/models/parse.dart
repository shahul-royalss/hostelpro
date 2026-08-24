library;

/// Coercion helpers for rows arriving from PostgREST.
///
/// WHY THIS FILE EXISTS. A wrong column name compiles fine and fails at runtime, and so does a
/// wrong *type* assumption. PostgREST is not consistent about the Dart type a number decodes
/// to: `numeric(10,2)` arrives as `5000` (int) for a round value and `5000.5` (double)
/// otherwise, so `row['monthly_fee'] as double` throws on exactly the values a real hostel
/// mostly has. Every read goes through here instead, and every failure names the column that
/// caused it — which turns "type 'int' is not a subtype of type 'double'" into
/// "students.monthly_fee: expected a number, got int".
///
/// The other half of the job is catching a MISSING key. `row['monlthy_fee'] as double?` is a
/// silent null; [req] throws with the table and column, so a typo in a select list fails the
/// first time the screen is opened rather than showing a blank field forever.

/// Thrown when a row does not look the way schema.sql says it should.
///
/// Not an [AppFailure]: this is never the user's fault and never actionable by them. It means
/// the client and the database disagree about the shape of a table, which is a bug in this
/// app. Repositories let it escape as an unexpected failure so it is loud in logs.
class RowShapeError extends StateError {
  RowShapeError(this.source, this.column, String detail)
      : super('$source.$column: $detail');

  /// The table or RPC the row came from, for the message.
  final String source;
  final String column;
}

/// Reads a required value, failing loudly when the key is absent.
Object _req(Map<String, dynamic> row, String source, String column) {
  if (!row.containsKey(column)) {
    throw RowShapeError(source, column,
        'column missing from the response — check the select list against db/schema.sql');
  }
  final value = row[column];
  if (value == null) {
    throw RowShapeError(source, column, 'null, but schema.sql declares it NOT NULL');
  }
  return value;
}

String reqString(Map<String, dynamic> row, String source, String column) {
  final v = _req(row, source, column);
  if (v is String) return v;
  throw RowShapeError(source, column, 'expected text, got ${v.runtimeType}');
}

String? optString(Map<String, dynamic> row, String column) {
  final v = row[column];
  return v == null ? null : v as String;
}

int reqInt(Map<String, dynamic> row, String source, String column) {
  final v = _req(row, source, column);
  if (v is int) return v;
  // A bigint beyond 2^53 arrives as a String; count columns never are, but parsing costs
  // nothing and removes a whole class of "worked in dev" surprise.
  if (v is num) return v.toInt();
  if (v is String) {
    final parsed = int.tryParse(v);
    if (parsed != null) return parsed;
  }
  throw RowShapeError(source, column, 'expected an integer, got ${v.runtimeType}');
}

int? optInt(Map<String, dynamic> row, String source, String column) {
  if (row[column] == null) return null;
  return reqInt(row, source, column);
}

/// Money and any other `numeric`. Always widened to double so arithmetic in the UI is uniform.
double reqDouble(Map<String, dynamic> row, String source, String column) {
  final v = _req(row, source, column);
  if (v is num) return v.toDouble();
  if (v is String) {
    final parsed = double.tryParse(v);
    if (parsed != null) return parsed;
  }
  throw RowShapeError(source, column, 'expected a number, got ${v.runtimeType}');
}

double? optDouble(Map<String, dynamic> row, String source, String column) {
  if (row[column] == null) return null;
  return reqDouble(row, source, column);
}

bool reqBool(Map<String, dynamic> row, String source, String column) {
  final v = _req(row, source, column);
  if (v is bool) return v;
  throw RowShapeError(source, column, 'expected a boolean, got ${v.runtimeType}');
}

/// A `timestamptz`. Kept in the zone Postgres sent (UTC); call `.toLocal()` at the point of
/// display. Converting here would make two identical rows compare unequal after a timezone
/// change, and the hostel day boundary is IST — a decision the UI layer owns, not this one.
DateTime reqTimestamp(Map<String, dynamic> row, String source, String column) {
  final v = _req(row, source, column);
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    if (parsed != null) return parsed;
  }
  throw RowShapeError(source, column, 'expected an ISO-8601 timestamp, got "$v"');
}

DateTime? optTimestamp(Map<String, dynamic> row, String source, String column) {
  if (row[column] == null) return null;
  return reqTimestamp(row, source, column);
}

/// A plain `date` ("2026-08-24"). Parsed to LOCAL midnight, not UTC midnight, because a date
/// column carries no zone and rendering it in UTC shifts it a day backwards for every user
/// east of Greenwich — which is all of them.
DateTime reqDate(Map<String, dynamic> row, String source, String column) {
  final v = _req(row, source, column);
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
  }
  throw RowShapeError(source, column, 'expected a YYYY-MM-DD date, got "$v"');
}

DateTime? optDate(Map<String, dynamic> row, String source, String column) {
  if (row[column] == null) return null;
  return reqDate(row, source, column);
}

/// Formats a `date` for sending back to Postgres. `DateTime.toIso8601String()` would send a
/// time and a zone, which a `date` column silently truncates in the server's zone — off by one
/// for anything after 18:30 IST.
String toDateWire(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The `YYYY-MM` string every fee query is keyed by. Matches the check constraint on
/// fee_payments.period_month exactly.
String toPeriodMonth(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
