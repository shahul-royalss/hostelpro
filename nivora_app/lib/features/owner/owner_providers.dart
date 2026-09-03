library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import 'owner_insights.dart';
import 'owner_repository.dart';

/// Owner-scoped wiring on top of lib/data/providers.dart.
///
/// Nothing here re-implements a query that the data layer already owns. What it adds is the
/// two things only the owner needs: WHICH hostel is being looked at (the only role that can
/// hold more than one), and the composition of several data-layer providers into the shapes
/// three owner screens read.

final ownerRepositoryProvider = Provider<OwnerRepository>(
  (ref) => OwnerRepository(ref.watch(supabaseClientProvider)),
);

/// Every PG this owner holds.
///
/// Empty for anybody who is not an owner — not as a permission check (RLS is that), but
/// because asking `hostels` for rows owned by a warden's user id is a pointless round trip.
final myHostelsProvider = FutureProvider<List<Hostel>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null || session.role != UserRole.owner) return const <Hostel>[];
  return ref.watch(ownerRepositoryProvider).hostelsOwnedBy(session.userId);
});

/// The PG the owner has tapped in the switcher, or null for "whatever the default is".
///
/// Deliberately not persisted to disk. A stale selection pointing at a hostel that was
/// transferred away would show an empty dashboard with no explanation, and the default —
/// the session's own hostel — is right on every launch but the second one.
final selectedHostelIdProvider =
    NotifierProvider<SelectedHostelId, String?>(SelectedHostelId.new);

class SelectedHostelId extends Notifier<String?> {
  @override
  String? build() {
    // Keyed on the user id rather than the whole session: a token refresh produces a new
    // NivoraSession object with identical contents, and resetting the switcher every hour
    // because of that would be baffling. A genuine change of user does reset it.
    ref.watch(sessionProvider.select((s) => s?.userId));
    return null;
  }

  void select(String hostelId) => state = hostelId;
}

/// The hostel every owner screen actually reads, or null when there is nothing to show.
final activeHostelIdProvider = Provider<String?>((ref) {
  return resolveActiveHostelId(
    chosen: ref.watch(selectedHostelIdProvider),
    sessionHostelId: ref.watch(currentHostelIdProvider),
    owned: ref.watch(myHostelsProvider).value,
  );
});

/// Picks the hostel to show, given a tapped choice, the session's own hostel, and the list of
/// owned hostels once it has loaded.
///
/// Extracted as a pure function because the interesting cases are all edge cases — the list
/// still loading, a selection that no longer exists, an owner whose `users.hostel_id` points
/// at a hostel they do not own — and none of them are reachable by tapping around a seeded
/// demo. [owned] is null while the query is in flight, which is NOT the same as an owner with
/// no hostels: the first must keep showing what is already on screen, the second must show an
/// empty state.
String? resolveActiveHostelId({
  required String? chosen,
  required String? sessionHostelId,
  required List<Hostel>? owned,
}) {
  if (owned == null) return chosen ?? sessionHostelId;
  if (chosen != null && owned.any((h) => h.id == chosen)) return chosen;
  if (sessionHostelId != null && owned.any((h) => h.id == sessionHostelId)) {
    return sessionHostelId;
  }
  if (owned.isNotEmpty) return owned.first.id;
  // Owns nothing on record. The session's hostel is still the honest answer when it is set:
  // app.can_read_hostel() also admits staff of a hostel, so the rows may well come back.
  return sessionHostelId;
}

/// How far back the cash-flow chart looks. Thirty days is two rent cycles' worth of daily
/// spending — long enough for a shape, short enough that one bad week is still visible.
const int financeWindowDays = 30;

/// The date range behind the dashboard chart, or null when no hostel is selected.
///
/// NORMALISED TO MIDNIGHT, and that is not a detail: [FinanceRangeQuery] takes part in the
/// provider's cache key by value, so a range built from `DateTime.now()` would be a different
/// key on every single rebuild — a fresh network request per frame, forever. Date-only bounds
/// keep the key stable for the whole day, which is also the granularity the RPC works at.
final ownerFinanceWindowProvider = Provider<FinanceRangeQuery?>((ref) {
  final hostelId = ref.watch(activeHostelIdProvider);
  if (hostelId == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  // Constructed rather than subtracted: DateTime normalises day overflow itself, and a
  // Duration subtraction lands an hour off a midnight boundary in any zone with DST.
  final from = DateTime(today.year, today.month, today.day - (financeWindowDays - 1));
  return FinanceRangeQuery(hostelId: hostelId, from: from, to: today);
});

/// Complaints and notices on one timeline — the dashboard's "recent activity".
///
/// Composed from the two data-layer providers rather than a third query, so the feed and the
/// full lists can never disagree about what happened.
final ownerActivityProvider =
    Provider.autoDispose.family<AsyncValue<List<ActivityItem>>, String>((ref, hostelId) {
  final complaints = ref.watch(complaintsProvider(ComplaintQuery(hostelId: hostelId)));
  final notices = ref.watch(noticesProvider(hostelId));
  return combineActivity(complaints, notices);
});

/// Folds two independent loads into one. Either failing fails the section — a feed missing
/// half its sources without saying so is worse than a feed that admits it could not load.
AsyncValue<List<ActivityItem>> combineActivity(
  AsyncValue<PagedResult<Complaint>> complaints,
  AsyncValue<PagedResult<Notice>> notices,
) {
  final error = complaints.error ?? notices.error;
  if (error != null) {
    return AsyncError(
      error,
      complaints.stackTrace ?? notices.stackTrace ?? StackTrace.empty,
    );
  }
  final c = complaints.value;
  final n = notices.value;
  if (c == null || n == null) return const AsyncLoading();
  return AsyncData(buildActivityFeed(complaints: c.items, notices: n.items));
}

/// How long a pull-to-refresh waits before it gives up and lets the body draw the failure.
///
/// Long enough for a slow 3G handshake, short enough that the spinner is not still turning
/// when the warden gives up and puts the phone away. It was written out three times as
/// `Duration(seconds: 12)`; one name means the three screens cannot drift apart.
const ownerRefreshTimeout = Duration(seconds: 12);

/// Pull-to-refresh. Invalidates exactly what the dashboard draws and nothing else — throwing
/// the whole provider container away would also drop the session and the router's opinion of
/// where the user is.
void refreshOwnerDashboard(WidgetRef ref, {required String hostelId, required String period}) {
  ref.invalidate(myHostelsProvider);
  ref.invalidate(hostelStatsProvider(StatsQuery(hostelId: hostelId, periodMonth: period)));
  ref.invalidate(complaintsProvider(ComplaintQuery(hostelId: hostelId)));
  ref.invalidate(noticesProvider(hostelId));
  final window = ref.read(ownerFinanceWindowProvider);
  if (window != null) ref.invalidate(dailyFinanceProvider(window));
}

/// Everything that counts a room or a bed, after THE BUILDING ITSELF has changed.
///
/// Separate from [refreshOwnerDashboard] because they answer different questions.
/// That one re-reads what a DAY changes — money, complaints, notices. This one re-reads what a
/// FLOOR PLAN changes, and a floor plan changes things no dashboard refresh touches: rooms that
/// did not exist a minute ago, beds created under them, and the two denormalised columns on
/// `hostels` that the PG list prints when a PG has no address on file.
///
/// The families are invalidated WHOLE where the key is not a hostel id. [bedsInRoomProvider] is
/// keyed by ROOM, and the rooms this write deleted are precisely the ones whose keys are no
/// longer worth knowing — the same reasoning the room grid already uses when a capacity edit
/// adds or removes bed rows.
/// IT TAKES A CONTAINER, NOT A WidgetRef, AND THAT IS THE WHOLE POINT.
///
/// This is called after an `await` on a write, and by then the screen that started the write may
/// be gone — an owner who taps Save and immediately backs out is the ordinary case, not a
/// contrived one. `WidgetRef.invalidate` on an unmounted element does not no-op: Riverpod's
/// `ConsumerStatefulElement.invalidate` calls `_assertNotDisposed()`, which THROWS a StateError,
/// and not behind an `assert` — it throws in release too.
///
/// So the WidgetRef version of this function threw on its FIRST line, none of the six providers
/// refreshed, and the caller's `catch` swallowed it in silence. The write had landed. Every one
/// of these providers is `holdForSession`-pinned, so the stale building then survived the rest of
/// the session — and because the editor SEEDS ITS PLAN from that grid, the next visit could
/// under-report a deletion by exactly the drift: the dialog says "3 → 2, removing 1 room" while
/// the server, which has four, removes two.
///
/// A [ProviderContainer] outlives any one widget, so it is captured before the await
/// (`ProviderScope.containerOf(context, listen: false)`) and invalidation happens through it.
/// Do not "simplify" this back to a WidgetRef: the path that needs the refresh most is exactly
/// the path on which the WidgetRef is already dead.
void refreshOwnerBuilding(
  ProviderContainer container, {
  required String hostelId,
  required String period,
}) {
  container.invalidate(roomOccupancyProvider(hostelId));
  container.invalidate(floorsProvider(hostelId));
  container.invalidate(bedsInRoomProvider);
  // total_beds / occupied_beds on every staff dashboard for this PG.
  container.invalidate(hostelStatsProvider(StatsQuery(hostelId: hostelId, periodMonth: period)));
  // hostels.total_floors / total_rooms, which the PG list draws under a PG with no address.
  container.invalidate(hostelProvider(hostelId));
  container.invalidate(myHostelsProvider);
}
