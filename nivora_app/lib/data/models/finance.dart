library;

import 'enums.dart';
import 'parse.dart';

/// public.expenses — money out.
///
/// Readable by the owner and the manager only; the manager is the one who writes them
/// (rls-policies.sql). Wardens and students cannot see this table at all.
class Expense {
  const Expense({
    required this.id,
    required this.hostelId,
    required this.date,
    required this.category,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    this.kind = ExpenseKind.daily,
    this.note,
    this.receiptUrl,
    this.uploadedBy,
    this.deletedAt,
  });

  static const columns =
      'id, hostel_id, date, category, kind, amount, note, receipt_url, uploaded_by, '
      'created_at, updated_at, deleted_at';

  final String id;
  final String hostelId;

  /// Plain `date` — the day the money was spent, not the day it was typed in.
  final DateTime date;
  final ExpenseCategory category;

  /// Monthly or day-to-day. DEFAULTS to daily, matching the column's own default: every row
  /// written before 2026-09-12 has it, and that is a default rather than a classification —
  /// nothing in those rows says which kind they were, and guessing from the category would put
  /// invented numbers into the charts this field exists to draw.
  final ExpenseKind kind;
  final double amount;
  final String? note;

  /// Storage key for the receipt image.
  final String? receiptUrl;
  final String? uploadedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory Expense.fromJson(Map<String, dynamic> row) {
    const src = 'expenses';
    return Expense(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      date: reqDate(row, src, 'date'),
      category: wireOrThrow(ExpenseCategory.values, row['category'], src, 'category'),
      // tryParse, not wireOrThrow: an older client must keep working against a server that has
      // learned a new kind, and the column is NOT NULL so the fallback is only ever reached by
      // a client that predates the value it is reading.
      kind: ExpenseKind.tryParse(row['kind'] as String?) ?? ExpenseKind.daily,
      amount: reqDouble(row, src, 'amount'),
      note: optString(row, 'note'),
      receiptUrl: optString(row, 'receipt_url'),
      uploadedBy: optString(row, 'uploaded_by'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
      deletedAt: optTimestamp(row, src, 'deleted_at'),
    );
  }
}

/// public.revenues — money in, other than through the fee ledger.
///
/// Note this is NOT the same number as fees collected. rpc_hostel_stats reports both
/// separately for exactly that reason; adding them together in a screen would double-count any
/// hostel that also books rent here.
class Revenue {
  const Revenue({
    required this.id,
    required this.hostelId,
    required this.date,
    required this.source,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.uploadedBy,
    this.deletedAt,
  });

  static const columns =
      'id, hostel_id, date, source, amount, note, uploaded_by, '
      'created_at, updated_at, deleted_at';

  final String id;
  final String hostelId;
  final DateTime date;
  final RevenueSource source;
  final double amount;
  final String? note;
  final String? uploadedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory Revenue.fromJson(Map<String, dynamic> row) {
    const src = 'revenues';
    return Revenue(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      date: reqDate(row, src, 'date'),
      source: wireOrThrow(RevenueSource.values, row['source'], src, 'source'),
      amount: reqDouble(row, src, 'amount'),
      note: optString(row, 'note'),
      uploadedBy: optString(row, 'uploaded_by'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
      deletedAt: optTimestamp(row, src, 'deleted_at'),
    );
  }
}

/// One day of public.rpc_daily_finance(hostel, from, to).
///
/// The RPC generates a row for EVERY day in the range, zero-filled — so a chart drawn from it
/// has no gaps to guess at, and a flat stretch is genuinely a flat stretch rather than missing
/// data the client silently interpolated.
class FinanceDay {
  const FinanceDay({
    required this.day,
    required this.revenue,
    required this.expense,
  });

  final DateTime day;
  final double revenue;
  final double expense;

  double get net => revenue - expense;

  factory FinanceDay.fromJson(Map<String, dynamic> row) {
    const src = 'rpc_daily_finance';
    return FinanceDay(
      day: reqDate(row, src, 'day'),
      revenue: reqDouble(row, src, 'revenue'),
      expense: reqDouble(row, src, 'expense'),
    );
  }
}
