library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import 'warden_models.dart';
import 'warden_repository.dart';

/// Providers for the warden's screens.
///
/// HAND-WRITTEN, matching lib/data/providers.dart — no codegen, nothing to regenerate. Anything
/// the shared file already exposes is used from there and NOT redeclared here: studentsProvider,
/// feeLedgerProvider, complaintsProvider, roomOccupancyProvider, bedsInRoomProvider,
/// freeBedsProvider, hostelStatsProvider, studentFeeHistoryProvider and
/// complaintTimelineProvider are all read straight off lib/data. What follows is the warden's
/// own additions and two joins that only this role needs.

final wardenRepositoryProvider = Provider<WardenRepository>(
  (ref) => WardenRepository(ref.watch(supabaseClientProvider)),
);

/// Registering a resident, TYPED BY THE INTERFACE rather than by the class.
///
/// Everything else the warden does is a read, or a write whose outcome is a row the next read
/// returns. This one mints a credential that exists exactly once, and its interesting states —
/// four fields rejected at once, a phone number already taken, a bed occupied between loading
/// the picker and pressing Register, a rollback that itself failed — are the states worth
/// holding down in `flutter test`, which needs a fake in this slot. See StudentRegistrations,
/// and RentPayments / SaPlatformWrites, which are this shape for the same reason.
final wardenRegistrationsProvider = Provider<StudentRegistrations>(
  (ref) => ref.watch(wardenRepositoryProvider),
);

/// The camera / photo picker the ID proof comes from.
///
/// A PROVIDER SO IT CAN BE REPLACED, exactly as `razorpayCheckoutProvider` is. `image_picker`
/// talks over a MethodChannel and a widget test has no platform on the other end of one — the
/// real plugin in a test makes the registration sheet hang rather than fail, which is the worst
/// of both. Overriding this is what lets the whole flow, up to and including the password
/// dialog, run in `flutter test`.
///
/// Not autoDispose and no teardown: `ImagePicker` registers no listeners and owns nothing that
/// outlives a call, unlike the Razorpay checkout.
final documentCaptureProvider = Provider<DocumentCapture>(
  (ref) => PluginDocumentCapture(),
);

// ─────────────────────────────────────────────────────────────────────────────
// LEAVES AND VISITORS
// ─────────────────────────────────────────────────────────────────────────────

/// Leave requests awaiting a decision. public.leaves.
final pendingLeavesProvider =
    FutureProvider.autoDispose.family<List<LeaveRequest>, String>((ref, hostelId) {
  return ref.watch(wardenRepositoryProvider).leaves(hostelId: hostelId);
});

/// Visitors signed in and not yet signed out. public.visitors.
///
/// Deliberately NOT the same figure as HostelStats.visitorsToday — see
/// WardenRepository.visitorsOnSite. The two are labelled differently everywhere they appear.
final visitorsOnSiteProvider =
    FutureProvider.autoDispose.family<List<VisitorLog>, String>((ref, hostelId) {
  return ref.watch(wardenRepositoryProvider).visitorsOnSite(hostelId: hostelId);
});

// ─────────────────────────────────────────────────────────────────────────────
// FEES
// ─────────────────────────────────────────────────────────────────────────────

/// One resident's fee row for one month, or null if nothing has been paid yet.
///
/// The record-payment sheet has to open on the truth, whichever screen it was opened from: the
/// ledger row a warden tapped may be minutes old, and a second payment may have landed since.
/// A record type is the family key because Dart gives records structural equality for free —
/// the same student and month is the same cache entry, not a second request.
final studentMonthFeeProvider = FutureProvider.autoDispose
    .family<FeePayment?, ({String studentId, String periodMonth})>((ref, key) {
  return ref.watch(feeRepositoryProvider).forMonth(
        studentId: key.studentId,
        periodMonth: key.periodMonth,
      );
});

// ─────────────────────────────────────────────────────────────────────────────
// ROOM AND BED JOINS
// ─────────────────────────────────────────────────────────────────────────────

/// The residents of one room. public.students, filtered server-side by room.
///
/// The room sheet needs a name against each occupied bed, and beds.student_id is only an id.
/// One query per opened room rather than one per bed.
final studentsInRoomProvider =
    FutureProvider.autoDispose.family<List<Student>, String>((ref, roomId) {
  return ref.watch(studentRepositoryProvider).inRoom(roomId);
});

/// Residents with no bed. public.students, filtered server-side on `bed_id is null`.
final studentsAwaitingBedProvider =
    FutureProvider.autoDispose.family<List<Student>, String>((ref, hostelId) {
  return ref.watch(wardenRepositoryProvider).awaitingBed(hostelId: hostelId);
});

/// A free bed with enough context to choose it from a list.
///
/// public.beds carries room_id but no room number, and a warden picks "Room 204, bed 2" — not a
/// UUID. rpc_room_occupancy already returns the room number and storey for every room, so this
/// pairs the two rather than adding a join to the beds query.
class FreeBed {
  const FreeBed({required this.bed, required this.roomNumber, required this.floorNumber});

  final Bed bed;

  /// Null when the bed's room is not in the occupancy result — which should not happen, and is
  /// rendered as the bed number alone rather than as a fabricated room.
  final String? roomNumber;
  final int? floorNumber;

  String get label =>
      roomNumber == null ? 'Bed ${bed.bedNumber}' : 'Room $roomNumber · Bed ${bed.bedNumber}';
}

/// Every unoccupied bed in the hostel, labelled by room and ordered the way a warden walks the
/// building: ground floor first, then by room number, then by bed.
final freeBedOptionsProvider =
    FutureProvider.autoDispose.family<List<FreeBed>, String>((ref, hostelId) async {
  final beds = await ref.watch(freeBedsProvider(hostelId).future);
  final rooms = await ref.watch(roomOccupancyProvider(hostelId).future);
  final byRoom = {for (final r in rooms) r.roomId: r};

  final options = [
    for (final bed in beds)
      FreeBed(
        bed: bed,
        roomNumber: byRoom[bed.roomId]?.roomNumber,
        floorNumber: byRoom[bed.roomId]?.floorNumber,
      ),
  ];

  options.sort((a, b) {
    final floor = (a.floorNumber ?? 0).compareTo(b.floorNumber ?? 0);
    if (floor != 0) return floor;
    // Room numbers are text ("A-101", "12B"), so compareTo is the only ordering that is always
    // defined. It matches the ordering rpc_room_occupancy itself uses.
    final room = (a.roomNumber ?? '').compareTo(b.roomNumber ?? '');
    if (room != 0) return room;
    return a.bed.bedNumber.compareTo(b.bed.bedNumber);
  });
  return options;
});

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN STATE
// ─────────────────────────────────────────────────────────────────────────────

/// Which of the five tabs is showing.
///
/// Lifted out of the shell so the home screen can act on a number rather than only display it:
/// "6 residents unpaid" is a fact, "6 residents unpaid — tap to chase them" is a tool. The
/// filter providers below are set in the same gesture so the list the warden lands on is the
/// list the number was counting.
class WardenTab extends Notifier<int> {
  @override
  int build() => 0;
  void go(int index) => state = index;
}

final wardenTabProvider = NotifierProvider<WardenTab, int>(WardenTab.new);

/// Which slice of the fee ledger the collections screen is showing. Null means everyone.
class FeeFilter extends Notifier<FeeStatus?> {
  @override
  FeeStatus? build() => null;
  void set(FeeStatus? status) => state = status;
}

final feeFilterProvider = NotifierProvider<FeeFilter, FeeStatus?>(FeeFilter.new);

/// Which complaints the queue is showing.
///
/// [needsAction] is `status <> 'resolved'` — open AND in progress. That is exactly what
/// rpc_hostel_stats counts as `open_complaints`, which is what lets the dashboard number and
/// the list it opens agree. A chip that showed only 'open' would land the warden on a shorter
/// list than the number they tapped, and a number you cannot reconcile is a number you stop
/// trusting.
enum ComplaintFilter {
  needsAction('Needs action'),
  open('Open'),
  inProgress('In progress'),
  resolved('Resolved');

  const ComplaintFilter(this.label);
  final String label;

  ComplaintStatus? get status => switch (this) {
        ComplaintFilter.needsAction => null,
        ComplaintFilter.open => ComplaintStatus.open,
        ComplaintFilter.inProgress => ComplaintStatus.inProgress,
        ComplaintFilter.resolved => ComplaintStatus.resolved,
      };

  bool get openOnly => this == ComplaintFilter.needsAction;
}

class ComplaintFilterState extends Notifier<ComplaintFilter> {
  @override
  ComplaintFilter build() => ComplaintFilter.needsAction;
  void set(ComplaintFilter filter) => state = filter;
}

final complaintFilterProvider =
    NotifierProvider<ComplaintFilterState, ComplaintFilter>(ComplaintFilterState.new);

/// Which month the collections screen is showing, as 'YYYY-MM'.
///
/// Shared between the ledger list and the summary above it so the two cannot disagree — a
/// header reading October's totals over November's rows is the kind of bug that is only found
/// by someone chasing the wrong resident for rent.
class SelectedMonth extends Notifier<String> {
  @override
  String build() => ref.watch(currentPeriodMonthProvider);

  /// Back to the month the device thinks it is. Used when an action assumes "this month" —
  /// collecting rent from the home screen must not land on the October ledger a warden was
  /// reading an hour ago.
  void reset() => state = ref.read(currentPeriodMonthProvider);

  /// Steps [months] whole months from the current selection. Negative goes back.
  void step(int months) {
    final parts = state.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    // DateTime normalises month 0 and month 13 into the neighbouring year for us.
    state = toPeriodMonth(DateTime(year, month + months));
  }
}

final selectedMonthProvider =
    NotifierProvider<SelectedMonth, String>(SelectedMonth.new);

// ─────────────────────────────────────────────────────────────────────────────
// REFRESH AFTER A WRITE
//
// A write on one screen changes what another screen is already showing: assigning a bed moves
// a number on the dashboard, empties a slot in the room grid and fills the resident's row. The
// server is the only thing that knows the new truth — every one of these values is computed by
// Postgres, and several by triggers this client never sees — so the response is to re-read,
// never to patch a local copy into agreement.
//
// Invalidating a family without an argument clears every instance of it. The lists are
// deliberately NARROW: the warden shell keeps all five tabs alive, so an over-broad invalidate
// is five refetches on a phone that may be on 3G in a stairwell.
// ─────────────────────────────────────────────────────────────────────────────

/// Beds moved: the grid, the free-bed pickers, and the resident who moved.
void refreshBeds(WidgetRef ref) {
  ref.invalidate(roomOccupancyProvider);
  ref.invalidate(bedsInRoomProvider);
  ref.invalidate(freeBedsProvider);
  ref.invalidate(freeBedOptionsProvider);
  ref.invalidate(studentsInRoomProvider);
  ref.invalidate(studentsAwaitingBedProvider);
  ref.invalidate(studentsProvider);
  ref.invalidate(studentProvider);
  ref.invalidate(hostelStatsProvider);
}

/// The roster changed: a registration, an edit, a check-out.
///
/// The fee ledger is included because it is built FROM students — a new resident appears on it
/// as unpaid the moment they exist, and a checked-out one drops off it.
void refreshResidents(WidgetRef ref) {
  ref.invalidate(studentsProvider);
  ref.invalidate(studentProvider);
  ref.invalidate(studentsAwaitingBedProvider);
  ref.invalidate(feeLedgerProvider);
  ref.invalidate(hostelStatsProvider);
  // A check-out frees a bed, so the grid is stale too.
  ref.invalidate(roomOccupancyProvider);
  ref.invalidate(bedsInRoomProvider);
  ref.invalidate(freeBedsProvider);
  ref.invalidate(freeBedOptionsProvider);
  ref.invalidate(studentsInRoomProvider);
}

/// Money came in.
void refreshFees(WidgetRef ref) {
  ref.invalidate(feeLedgerProvider);
  ref.invalidate(studentFeeHistoryProvider);
  ref.invalidate(studentMonthFeeProvider);
  ref.invalidate(hostelStatsProvider);
}

/// A complaint moved along the workflow.
void refreshComplaints(WidgetRef ref) {
  ref.invalidate(complaintsProvider);
  ref.invalidate(complaintProvider);
  ref.invalidate(complaintTimelineProvider);
  ref.invalidate(hostelStatsProvider);
}

/// A leave was decided. The student's status can change to on_leave by trigger, so the roster
/// is re-read too.
void refreshLeaves(WidgetRef ref) {
  ref.invalidate(pendingLeavesProvider);
  ref.invalidate(studentsProvider);
  ref.invalidate(hostelStatsProvider);
}

/// A visitor was signed out.
void refreshVisitors(WidgetRef ref) {
  ref.invalidate(visitorsOnSiteProvider);
  ref.invalidate(hostelStatsProvider);
}
