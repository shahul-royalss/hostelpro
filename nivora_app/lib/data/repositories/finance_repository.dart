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
    ExpenseKind? kind,
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
        if (kind != null) query = query.eq('kind', kind.wire);
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
    ExpenseKind kind = ExpenseKind.daily,
    DateTime? date,
    String? note,
    String? receiptUrl,
  }) =>
      guardWrite(() async {
        final row = await db
            .from('expenses')
            .insert({
              'hostel_id': hostelId,
              'category': category.wire,
              'kind': kind.wire,
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
      }, unresolved: 'Check the expense list before booking it again — a second entry would '
          'double the amount.');

  /// Book a revenue entry. Manager only.
  Future<Revenue> addRevenue({
    required String hostelId,
    required RevenueSource source,
    required double amount,
    DateTime? date,
    String? note,
  }) =>
      guardWrite(() async {
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
      }, unresolved: 'Check the revenue list before booking it again — a second entry would '
          'double the amount.');

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

  /// Month totals for the last [months] months including this one, split by kind and category.
  ///
  /// public.rpc_expense_months, SECURITY INVOKER — expenses_select is what decides whether the
  /// caller sees anything, exactly as it does for the list above. The server clamps [months] to
  /// 1..24, so a client cannot ask it to scan a decade.
  Future<List<ExpenseMonthSlice>> expenseMonths({
    required String hostelId,
    int months = 6,
  }) =>
      guard(() async {
        final data = await db.rpc('rpc_expense_months', params: {
          'p_hostel_id': hostelId,
          'p_months': months,
        });
        return rpcRows(data, 'rpc_expense_months')
            .map(ExpenseMonthSlice.fromJson)
            .toList(growable: false);
      });

  /// Day totals for one month, split by kind — the day-to-day line.
  ///
  /// [periodMonth] is `YYYY-MM`. The RPC validates the shape with a regex and returns nothing
  /// for anything else, rather than throwing: a malformed month is an empty chart, not a crash.
  Future<List<ExpenseDaySlice>> expenseDays({
    required String hostelId,
    required String periodMonth,
  }) =>
      guard(() async {
        final data = await db.rpc('rpc_expense_days', params: {
          'p_hostel_id': hostelId,
          'p_period_month': periodMonth,
        });
        return rpcRows(data, 'rpc_expense_days')
            .map(ExpenseDaySlice.fromJson)
            .toList(growable: false);
      });
}
