library;

import '../models/models.dart';
import 'repository.dart';

/// The counted numbers every home screen opens with.
///
/// RPCs: public.rpc_hostel_stats(), public.rpc_sa_dashboard(), public.rpc_sa_hostels(),
///       public.rpc_unread_count().
///
/// NOTHING HERE IS ESTIMATED. Every figure is counted by Postgres in a single query. If a
/// screen wants a number this class does not expose, the fix is a column on the RPC — not a
/// calculation over a page of rows the client happens to have, which would be wrong by exactly
/// the amount that did not fit on the page.
final class DashboardRepository extends Repository {
  const DashboardRepository(super.db);

  /// Headline stats for one hostel and one month.
  ///
  /// [periodMonth] is 'YYYY-MM' and defaults, server-side, to the current month. Build it with
  /// [toPeriodMonth] rather than by hand — the same format the fee ledger is keyed on.
  ///
  /// SECURITY INVOKER: the counts run under the caller's RLS. For staff that is the whole
  /// hostel. For a STUDENT it is the single row they can see, which makes every number here
  /// meaningless — so student screens must not call this. Returns null when the function comes
  /// back empty, which should not happen for a hostel that exists.
  Future<HostelStats?> hostelStats({
    required String hostelId,
    String? periodMonth,
  }) =>
      guard(() async {
        final data = await db.rpc('rpc_hostel_stats', params: {
          'p_hostel_id': hostelId,
          'p_period_month': ?periodMonth,
        });
        final row = rpcRow(data, 'rpc_hostel_stats');
        return row == null ? null : HostelStats.fromJson(row);
      });

  /// Unread notifications for the signed-in user — the number on the bell.
  ///
  /// Declared `returns int`, so the response is a bare JSON number, not a row.
  Future<int> unreadCount() => guard(() async {
        final data = await db.rpc('rpc_unread_count');
        if (data is int) return data;
        if (data is num) return data.toInt();
        // Never guess zero: a badge that silently reads zero when the call is misbehaving
        // hides notifications, and hiding them is worse than showing the wrong count loudly.
        throw RowShapeError('rpc_unread_count', '(result)',
            'expected an integer, got ${data.runtimeType}');
      });

  /// Platform-wide totals. Super Admin only.
  ///
  /// The function ends in `where app.is_super_admin()`, so ANY OTHER ROLE GETS ZERO ROWS rather
  /// than a 403. Null therefore means "not permitted", and must never be rendered as a platform
  /// with no hostels on it.
  Future<SaStats?> superAdminStats() => guard(() async {
        final data = await db.rpc('rpc_sa_dashboard');
        final row = rpcRow(data, 'rpc_sa_dashboard');
        return row == null ? null : SaStats.fromJson(row);
      });

  /// Every hostel on the platform with its owner and subscription. Super Admin only.
  ///
  /// PAGINATED, because this list is the one that grows with the business rather than with any
  /// one customer. Same emptiness-means-refusal caveat as [superAdminStats].
  Future<PagedResult<SaHostelRow>> superAdminHostels({
    int page = 0,
    int pageSize = PagedResult.defaultPageSize,
  }) =>
      guard(() async {
        final bounds = rangeFor(page, pageSize);
        final data =
            await db.rpc('rpc_sa_hostels').range(bounds.from, bounds.to);
        return PagedResult.fromOverfetch(
          rpcRows(data, 'rpc_sa_hostels')
              .map(SaHostelRow.fromJson)
              .toList(growable: false),
          page: page,
          pageSize: pageSize,
        );
      });
}
