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
  /// meaningless — so student screens must not call this.
  ///
  /// NEVER NULL, AND THE OLD NULL BRANCH WAS UNREACHABLE. rpc_hostel_stats is a `select` of
  /// scalar subqueries with no FROM clause (db/schema.sql:1331), so Postgres returns exactly
  /// one row for every possible argument — including a hostel id that does not exist. Zero rows
  /// is therefore not "an empty hostel", it is this client talking to a function it was not
  /// built against, which is a [RowShapeError] and reaches the screen as a failure rather than
  /// as a dashboard of dashes.
  ///
  /// ═══ WHAT THIS METHOD STILL CANNOT TELL YOU — REPORTED, NOT FIXED HERE ═══
  /// Because it is SECURITY INVOKER over tables and the row is produced whatever RLS says, a
  /// hostel the caller cannot see comes back as a full row of ZEROES rather than as nothing at
  /// all: 0 beds, 0 residents, ₹0 collected. That is indistinguishable from a hostel that was
  /// created an hour ago and has not been set up yet, and no amount of client-side reading can
  /// separate them — app.subscription_state is SECURITY DEFINER and answers for hostels the
  /// caller cannot otherwise see, so even the subscription fields look plausible. The fix is a
  /// server one (`where app.can_read_hostel(p_hostel_id)` on the function, which would turn the
  /// case into zero rows and let [rpcRowOrRefusal] name it); it is a schema change and so is out
  /// of scope for this pass. Screens must not treat all-zero stats as proof of an empty hostel.
  Future<HostelStats> hostelStats({
    required String hostelId,
    String? periodMonth,
  }) =>
      guard(() async {
        final data = await db.rpc('rpc_hostel_stats', params: {
          'p_hostel_id': hostelId,
          'p_period_month': ?periodMonth,
        });
        final row = rpcRow(data, 'rpc_hostel_stats');
        if (row == null) {
          throw RowShapeError(
            'rpc_hostel_stats',
            '(result)',
            'zero rows, but the function selects scalar subqueries with no FROM clause and so '
                'always yields exactly one — the deployed function is not the one in '
                'db/schema.sql',
          );
        }
        return HostelStats.fromJson(row);
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
  /// The function ends in `where app.is_super_admin()` (db/schema.sql:1391), so ANY OTHER ROLE
  /// GETS ZERO ROWS rather than a 403. A super admin, by contrast, always gets exactly one row
  /// — the body is scalar subqueries with no FROM — so emptiness has one meaning and one only:
  /// THIS CALLER IS NOT A SUPER ADMIN.
  ///
  /// It used to be returned as null, which every screen is free to read as "the platform has no
  /// hostels, no owners and no residents". That is the same picture a brand-new deployment
  /// draws, and it is drawn for the person whose job is to notice when it is wrong. It is now a
  /// refusal, which is not retryable, so no screen offers a Try again that could never work.
  Future<SaStats> superAdminStats() => guard(() async {
        final data = await db.rpc('rpc_sa_dashboard');
        return SaStats.fromJson(rpcRowOrRefusal(
          data,
          'rpc_sa_dashboard',
          refusal: 'Platform figures are only visible to a Nivora super admin.',
          // THE LINE THAT MAKES THE REFUSAL HONEST. Zero rows here is a refusal only if the
          // question was asked with a credential that was alive when the answer arrived; a
          // dead one is sent as `anon`, which this function refuses in exactly the same shape.
          // See core/auth/session_standing.dart — this is the call that told a super admin he
          // was not the super admin.
          standing: sessionStanding,
        ));
      });

  /// Every hostel on the platform with its owner and subscription. Super Admin only.
  ///
  /// PAGINATED, because this list is the one that grows with the business rather than with any
  /// one customer.
  ///
  /// ═══ STILL AMBIGUOUS, AND DELIBERATELY LEFT SO — REPORTED, NOT FIXED HERE ═══
  /// An empty first page means EITHER "you are not a super admin" (the same `where
  /// app.is_super_admin()` as above) OR "the platform genuinely has no hostels yet", and unlike
  /// [superAdminStats] this function cannot tell them apart from its own result: zero rows is a
  /// legitimate answer for a real super admin on day one. Disambiguating would mean a second
  /// round trip to rpc_sa_dashboard, which is a data-access change rather than a presentation
  /// one. Until then a screen showing this list should take its "not permitted" verdict from
  /// [superAdminStats], which is unambiguous, rather than from this list being short.
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
