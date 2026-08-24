library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';

/// Composition, not data access.
///
/// Everything here is built out of providers that already exist in lib/data/providers.dart.
/// Nothing in this file — or anywhere under lib/features/student/ — talks to Supabase. A screen
/// that needs a new column needs a change in the data layer, not a query smuggled into a
/// widget, because a query in a widget is a query nobody can override in a test and nobody can
/// find when the column is renamed.

/// This month's rent for the signed-in resident, as the DATABASE computes it.
///
/// WHY rpc_fee_ledger AND NOT fee_payments. A resident who has paid nothing this month has NO
/// ROW in `fee_payments` — that table only gains a row when money is recorded. Reading it alone
/// would show an empty screen to exactly the person who most needs to be told they owe rent.
/// `rpc_fee_ledger` LEFT JOINs from `students`, so it returns a row either way:
///
///     coalesce(fee_payments.amount_due,  students.monthly_fee)  as amount_due
///     coalesce(fee_payments.amount_paid, 0)                     as amount_paid
///     coalesce(fee_payments.status,      'unpaid')              as status
///
/// That coalesce is the definition of "what you owe", and it lives in Postgres. Re-deriving it
/// in Dart would be a second definition, free to drift from the one the warden's collections
/// screen uses — and the two disagreeing about one resident's balance is precisely the bug that
/// ends in an argument at the office door. Verified against the live project: as a student the
/// function returns EXACTLY ONE ROW, their own, because it is SECURITY INVOKER and the
/// `students` policy admits only `user_id = auth.uid()`.
///
/// It also carries `room_number` and `bed_number`, resolved through joins the resident is
/// allowed to make. That is why the home screen can name a room without fetching every room in
/// the building to find one number.
///
/// Null means "no row for me this month" — a resident who has been checked out, or one whose
/// registration is not finished. It never means zero rupees.
///
/// NOT autoDispose, deliberately. Home, Fees and Profile all draw from this one row, and a
/// resident moves between those tabs constantly. Disposing it on the way out would refetch the
/// same figure three times in a minute on mobile data, and would show a skeleton where a number
/// had already been read. It holds only the resident's own rent — the same data as their own
/// `students` row, which `myStudentProvider` already keeps for the session — and it is thrown
/// away by [refreshStudentData] and rebuilt on sign-out, because it watches `myStudentProvider`
/// which watches the session.
final myRentThisMonthProvider = FutureProvider<FeeLedgerRow?>((ref) async {
  final me = await ref.watch(myStudentProvider.future);
  if (me == null) return null;

  final month = ref.watch(currentPeriodMonthProvider);
  final page = await ref.watch(
    feeLedgerProvider(FeeLedgerQuery(hostelId: me.hostelId, periodMonth: month)).future,
  );

  // Row-level security is what limits this to one row; the line below only picks the resident
  // out of the result, it does not narrow it. If the ledger ever came back with more than one
  // row for a student account, that would be an RLS regression rather than something a screen
  // should quietly paper over — so debug builds say so loudly instead.
  assert(
    page.items.length <= 1,
    'rpc_fee_ledger returned ${page.items.length} rows to a resident. The students policy '
    'admits only the caller own row, so this means RLS is not doing what rls-policies.sql says.',
  );

  for (final row in page.items) {
    if (row.studentId == me.id) return row;
  }
  return null;
});

/// The resident's own hostel id, once their record has loaded.
///
/// Taken from `students.hostel_id` rather than from the session. `public.users.hostel_id` is set
/// for residents in this database, but the students row is the column every policy this screen
/// depends on is actually written against, so it is the one to key queries by.
final myHostelIdProvider = Provider.autoDispose<String?>((ref) {
  return ref.watch(myStudentProvider).value?.hostelId;
});

/// Everything the student tabs read, thrown away and fetched again.
///
/// Used by pull-to-refresh. Invalidating a family provider with no argument clears every
/// instance of it, which is what makes this a single call rather than a list of query keys the
/// screens would have to keep in step.
void refreshStudentData(WidgetRef ref) {
  ref.invalidate(myStudentProvider);
  ref.invalidate(myRentThisMonthProvider);
  ref.invalidate(feeLedgerProvider);
  ref.invalidate(studentFeeHistoryProvider);
  ref.invalidate(complaintsProvider);
  ref.invalidate(complaintTimelineProvider);
  ref.invalidate(noticesProvider);
  ref.invalidate(roommatesProvider);
  ref.invalidate(hostelContactsProvider);
  ref.invalidate(unreadCountProvider);
}

/// Waits for the reads a pull-to-refresh actually shows, so the spinner disappears when the
/// screen is ready rather than the instant the gesture ends.
///
/// Failures are swallowed here on purpose: each section renders its own error state, and an
/// exception escaping a RefreshIndicator callback leaves the spinner turning forever.
Future<void> awaitStudentRefresh(WidgetRef ref) async {
  try {
    await ref.read(myStudentProvider.future);
    await ref.read(myRentThisMonthProvider.future);
  } catch (error) {
    debugPrint('student refresh: $error');
  }
}
