/// Lenient readers for round-3 RPC rows: a field this build cannot read becomes null.
library;

String? jStr(Map row, String k) {
  final v = row[k];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? jDate(Map row, String k) => DateTime.tryParse(jStr(row, k) ?? '');

double? jNum(Map row, String k) {
  final v = row[k];
  return v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
}

int? jInt(Map row, String k) {
  final v = row[k];
  return v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
}

bool? jBool(Map row, String k) {
  final v = row[k];
  return v is bool ? v : null;
}

List<String> jStrList(Map row, String k) {
  final v = row[k];
  return v is List ? [for (final x in v) if (x is String && x.isNotEmpty) x] : const [];
}

List<Map<String, dynamic>> jRows(Object? data) =>
    data is List ? [for (final r in data) if (r is Map) r.cast<String, dynamic>()] : const [];

Map<String, dynamic>? jOne(Object? data) {
  final row = data is List ? (data.isEmpty ? null : data.first) : data;
  return row is Map ? row.cast<String, dynamic>() : null;
}
