library;

import '../models/models.dart';
import 'repository.dart';

/// Day-to-day money: expenses out, revenue in.
///
/// TABLES: public.expenses, public.revenues.
///
/// Owner and manager only, and the MANAGER is the one who writes — an owner can read the books
/// but not add to them (rls-policies.sql). Wardens and students see nothing here at all.
final class FinanceRepository extends Repository {
  const FinanceRepository(super.db);

  /// One page of expenses, most recent day first.
  ///
  /// PAGINATED. A hostel books groceries most days of the year; a year of a single hostel's
  /// expenses is several hundred rows, and the screen shows a dozen.
  Future<PagedResult<Expense>> expenses({
    required String hostelId,
    int page = 0,
    int pageSize = PagedResult.defaultPageSize,
    ExpenseCategory? category,
    DateTime? from,
    DateTime? to,
  }) =>
      guard(() async {
        final bounds = rangeFor(page, pageSize);
        var query = db
            .from('expenses')
            .select(Expense.columns)
            .eq('hostel_id', hostelId)
            .isFilter('deleted_at', null);
        if (category != null) query = query.eq('category', category.wire);
        if (from != null) query = query.gte('date', toDateWire(from));
        if (to != null) query = query.lte('date', toDateWire(to));

        final rows = await query
            .order('date', ascending: false)
            .order('created_at', ascending: false)
            .range(bounds.from, bounds.to);
        return PagedResult.fromOverfetch(
          rows.map(Expense.fromJson).toList(growable: false),
          page: page,
          pageSize: pageSize,
        );
      });

  /// One page of revenue entries, most recent day first.
  Future<PagedResult<Revenue>> revenues({
    required String hostelId,
    int page = 0,
    int pageSize = PagedResult.defaultPageSize,
    RevenueSource? source,
    DateTime? from,
    DateTime? to,
  }) =>
      guard(() async {
        final bounds = rangeFor(page, pageSize);
        var query = db
            .from('revenues')
            .select(Revenue.columns)
            .eq('hostel_id', hostelId)
            .isFilter('deleted_at', null);
        if (source != null) query = query.eq('source', source.wire);
        if (from != null) query = query.gte('date', toDateWire(from));
        if (to != null) query = query.lte('date', toDateWire(to));

        final rows = await query
            .order('date', ascending: false)
            .order('created_at', ascending: false)
            .range(bounds.from, bounds.to);
        return PagedResult.fromOverfetch(
          rows.map(Revenue.fromJson).toList(growable: false),
          page: page,
          pageSize: pageSize,
        );
      });

  /// Book an expense. Manager only.
  Future<Expense> addExpense({
    required String hostelId,
    required ExpenseCategory category,
    required double amount,
    DateTime? date,
    String? note,
    String? receiptUrl,
  }) =>
      guard(() async {
        final row = await db
            .from('expenses')
            .insert({
              'hostel_id': hostelId,
              'category': category.wire,
              'amount': amount,
              // Omitted rather than defaulted in Dart: the column defaults to current_date on
              // the SERVER, which is the clock the rest of the books are kept on.
              if (date != null) 'date': toDateWire(date),
              'note': ?note,
              'receipt_url': ?receiptUrl,
              'uploaded_by': ?db.auth.currentUser?.id,
            })
            .select(Expense.columns)
            .single();
        return Expense.fromJson(row);
      });

  /// Book a revenue entry. Manager only.
  Future<Revenue> addRevenue({
    required String hostelId,
    required RevenueSource source,
    required double amount,
    DateTime? date,
    String? note,
  }) =>
      guard(() async {
        final row = await db
            .from('revenues')
            .insert({
              'hostel_id': hostelId,
              'source': source.wire,
              'amount': amount,
              if (date != null) 'date': toDateWire(date),
              'note': ?note,
              'uploaded_by': ?db.auth.currentUser?.id,
            })
            .select(Revenue.columns)
            .single();
        return Revenue.fromJson(row);
      });

  /// Revenue against expense, one row per day across the range, zero-filled by the RPC.
  ///
  /// The zero-filling is the point: a chart built from the raw tables has gaps on days nothing
  /// was booked, and every charting library draws a straight line across a gap — which reads
  /// as "steady spending" when the truth is "no data". generate_series in the RPC removes the
  /// question.
  Future<List<FinanceDay>> daily({
    required String hostelId,
    required DateTime from,
    required DateTime to,
  }) =>
      guard(() async {
        final data = await db.rpc('rpc_daily_finance', params: {
          'p_hostel_id': hostelId,
          'p_from': toDateWire(from),
          'p_to': toDateWire(to),
        });
        return rpcRows(data, 'rpc_daily_finance')
            .map(FinanceDay.fromJson)
            .toList(growable: false);
      });
}
