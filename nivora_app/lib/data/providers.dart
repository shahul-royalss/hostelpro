library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth/auth_controller.dart';
import '../core/auth/session.dart';
import '../core/perf/session_keep_alive.dart';
import 'capture.dart';
import 'models/models.dart';
import 'repositories/checkout_repository.dart';
import 'repositories/complaint_repository.dart';
import 'repositories/dashboard_repository.dart';
import 'repositories/fee_repository.dart';
import 'repositories/finance_repository.dart';
import 'repositories/hostel_repository.dart';
import 'repositories/menu_repository.dart';
import 'repositories/notice_repository.dart';
import 'repositories/room_repository.dart';
import 'repositories/student_repository.dart';
import 'repositories/task_repository.dart';

/// Every provider the feature screens read from.
///
/// HAND-WRITTEN, NO CODEGEN. riverpod_generator is deliberately not a dependency of this
/// project, so there is no `.g.dart` to regenerate, nothing to be stale after a rebase, and no
/// build_runner step between editing a provider and running the app.
///
/// WHAT LIVES WHERE. Repositories know how to talk to Postgres and nothing else. Providers know
/// how to cache, key and refresh those calls, and nothing else. Screens know neither. That is
/// what lets a screen be tested by overriding one provider, and what stops a query string
/// ending up inside a widget build method.
///
/// LIFETIME POLICY — read this before adding or changing `autoDispose` below (the feature
/// provider files follow the same rule). A provider that BACKS A TAB — a list, a dashboard, a
/// ledger: anything an IndexedStack child watches — stays `autoDispose` but calls
/// `holdForSession(ref)` (core/perf/session_keep_alive.dart) first thing in its build. That
/// holds the data for the shell's lifetime, so a tab revisit renders instantly from the held
/// value and a background refresh updates it in place, never blanking back to a skeleton. The
/// hold cannot leak across a boundary: family keys carry the hostelId, so a hostel switch is a
/// different cache entry, and holdForSession drops everything on sign-out or a change of user.
/// A provider scoped to a SHEET OR DETAIL — one resident, one room's beds, one complaint —
/// keeps plain `autoDispose` with no hold, so browsing twenty residents does not pin twenty
/// rows of PII for the whole session.

// ─────────────────────────────────────────────────────────────────────────────
// CLIENT + REPOSITORIES
// ─────────────────────────────────────────────────────────────────────────────

/// The one Supabase client, holding the ANON key and nothing else.
///
/// Exposed as a provider purely so tests can override it. There is no service-role client in
/// this app and there must never be one: it bypasses row-level security, and anything compiled
/// into an APK is readable by whoever downloads it.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final hostelRepositoryProvider = Provider<HostelRepository>(
  (ref) => HostelRepository(ref.watch(supabaseClientProvider)),
);

final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => RoomRepository(ref.watch(supabaseClientProvider)),
);

final studentRepositoryProvider = Provider<StudentRepository>(
  (ref) => StudentRepository(ref.watch(supabaseClientProvider)),
);

final feeRepositoryProvider = Provider<FeeRepository>(
  (ref) => FeeRepository(ref.watch(supabaseClientProvider)),
);

/// Opens a Razorpay order for the signed-in resident's own rent. Takes no arguments
/// anywhere in its chain — see CheckoutRepository on why that is the security property.
final checkoutRepositoryProvider = Provider<CheckoutRepository>(
  (ref) => CheckoutRepository(ref.watch(supabaseClientProvider)),
);

final complaintRepositoryProvider = Provider<ComplaintRepository>(
  (ref) => ComplaintRepository(ref.watch(supabaseClientProvider)),
);

/// The camera / photo picker every attachment in the app comes from.
///
/// A PROVIDER SO IT CAN BE REPLACED, exactly as `receiptExporterProvider` is. `image_picker`
/// talks over a MethodChannel and a widget test has no platform on the other end of one — the
/// real plugin in a test makes the sheet hang rather than fail, which is the worst of both.
/// Overriding this is what lets the registration flow AND the raise-a-complaint flow run end to
/// end in `flutter test`.
///
/// IT LIVES HERE, not in the warden's provider file, because two features now capture images
/// and a test that overrode only one of them would silently drive the real picker in the other.
/// warden_providers.dart re-exports it so nothing that already read it from there had to move.
///
/// Not autoDispose and no teardown: `ImagePicker` registers no listeners and owns nothing that
/// outlives a call, unlike a plugin that registers event handlers of its own.
final documentCaptureProvider = Provider<DocumentCapture>(
  (ref) => PluginDocumentCapture(),
);

final noticeRepositoryProvider = Provider<NoticeRepository>(
  (ref) => NoticeRepository(ref.watch(supabaseClientProvider)),
);

final menuRepositoryProvider = Provider<MenuRepository>(
  (ref) => MenuRepository(ref.watch(supabaseClientProvider)),
);

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(supabaseClientProvider)),
);

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(supabaseClientProvider)),
);

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(supabaseClientProvider)),
);

/// Taking money at the desk. public.wd_record_payment + public.wd_correct_payment.
///
/// TYPED BY THE INTERFACE, not by the class, unlike every other repository here — and pointed
/// at the same [FeeRepository] instance the reads use, so there is one object and one client.
/// CASH AT THE DESK IS NOW ONE OF TWO WAYS MONEY REACHES THE LEDGER. The other is
/// `razorpay-webhook`, which credits the resident server-to-server after an in-app checkout and
/// never passes through this app at all. These two writes remain the only ones a PERSON makes,
/// and their interesting states are all refusals from Postgres (a resident who has checked out,
/// a month with nothing to correct, a figure above the schema's ceiling). Holding those down in
/// `flutter test` needs a fake in this slot. See RentDesk.
final feeDeskProvider = Provider<RentDesk>((ref) => ref.watch(feeRepositoryProvider));

// ─────────────────────────────────────────────────────────────────────────────
// SESSION-DERIVED KEYS
// ─────────────────────────────────────────────────────────────────────────────

/// The tenant the signed-in user belongs to, or null.
///
/// Null for a Super Admin, who sits outside every tenant, and null while signed out. A screen
/// that needs it should render its empty state rather than passing an empty string down — a
/// query keyed on '' returns nothing and looks exactly like a hostel with no data in it.
///
/// This is a CONVENIENCE, NOT A CONTROL. Passing a different hostel id to a repository does not
/// grant access to that hostel; RLS refuses it at the server.
final currentHostelIdProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider)?.hostelId;
});

/// The current month as 'YYYY-MM' — the key every fee query is written against.
///
/// Computed from the device clock, which is close enough for choosing a default month and is
/// never used for anything that must agree with the server: the RPCs default to Postgres's own
/// `to_char(current_date, 'YYYY-MM')` when no month is passed.
final currentPeriodMonthProvider = Provider<String>((ref) {
  return toPeriodMonth(DateTime.now());
});

// ─────────────────────────────────────────────────────────────────────────────
// FAMILY KEYS
//
// Riverpod caches one provider instance per argument, so every argument type below defines
// value equality. Without it, two identical queries would be two different caches and every
// rebuild would refetch.
// ─────────────────────────────────────────────────────────────────────────────

/// Which residents to list.
final class StudentQuery {
  const StudentQuery({
    required this.hostelId,
    this.search,
    this.status,
    this.includeVacated = false,
  });

  final String hostelId;

  /// Matched against name and phone by Postgres. Debouncing keystrokes is the screen's job:
  /// each distinct value here is a distinct cache entry and a distinct request.
  final String? search;
  final StudentStatus? status;
  final bool includeVacated;

  @override
  bool operator ==(Object other) =>
      other is StudentQuery &&
      other.hostelId == hostelId &&
      other.search == search &&
      other.status == status &&
      other.includeVacated == includeVacated;

  @override
  int get hashCode => Object.hash(hostelId, search, status, includeVacated);
}

/// Which complaints to list.
final class ComplaintQuery {
  const ComplaintQuery({
    required this.hostelId,
    this.status,
    this.category,
    this.openOnly = false,
  });

  final String hostelId;
  final ComplaintStatus? status;
  final ComplaintCategory? category;
  final bool openOnly;

  @override
  bool operator ==(Object other) =>
      other is ComplaintQuery &&
      other.hostelId == hostelId &&
      other.status == status &&
      other.category == category &&
      other.openOnly == openOnly;

  @override
  int get hashCode => Object.hash(hostelId, status, category, openOnly);
}

/// Which month of the fee ledger to list.
final class FeeLedgerQuery {
  const FeeLedgerQuery({
    required this.hostelId,
    required this.periodMonth,
    this.status,
  });

  final String hostelId;

  /// 'YYYY-MM'.
  final String periodMonth;

  /// Narrow to just the defaulters, for the chase-up list.
  final FeeStatus? status;

  @override
  bool operator ==(Object other) =>
      other is FeeLedgerQuery &&
      other.hostelId == hostelId &&
      other.periodMonth == periodMonth &&
      other.status == status;

  @override
  int get hashCode => Object.hash(hostelId, periodMonth, status);
}

/// Which tasks to list.
final class TaskQuery {
  const TaskQuery({
    required this.hostelId,
    this.status,
    this.assignedTo,
    this.openOnly = false,
  });

  final String hostelId;
  final TaskStatus? status;
  final String? assignedTo;
  final bool openOnly;

  @override
  bool operator ==(Object other) =>
      other is TaskQuery &&
      other.hostelId == hostelId &&
      other.status == status &&
      other.assignedTo == assignedTo &&
      other.openOnly == openOnly;

  @override
  int get hashCode => Object.hash(hostelId, status, assignedTo, openOnly);
}

/// A hostel and the month to report on. Null month means "let Postgres pick today's".
final class StatsQuery {
  const StatsQuery({required this.hostelId, this.periodMonth});

  final String hostelId;
  final String? periodMonth;

  @override
  bool operator ==(Object other) =>
      other is StatsQuery &&
      other.hostelId == hostelId &&
      other.periodMonth == periodMonth;

  @override
  int get hashCode => Object.hash(hostelId, periodMonth);
}

/// A hostel and an inclusive date range, for the finance chart.
final class FinanceRangeQuery {
  const FinanceRangeQuery({
    required this.hostelId,
    required this.from,
    required this.to,
  });

  final String hostelId;
  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is FinanceRangeQuery &&
      other.hostelId == hostelId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(hostelId, from, to);
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGINATED LISTS
// ─────────────────────────────────────────────────────────────────────────────

/// Shared behaviour for a list that loads a page at a time.
///
/// [build] fetches page zero; [loadMore] appends the next one.
///
/// A FAILURE PART-WAY DOWN A LIST DOES NOT EMPTY THE SCREEN. `state` stays on the rows already
/// loaded and the failure is RETURNED to whoever asked for more, because that is who can act on
/// it — a scroll listener or a "load more" button, which can show a retry line under the last
/// row. Publishing it as `AsyncError` instead would replace a resident's place in a 200-row
/// list with an error page because the lift lost signal for one second.
abstract class PagedNotifier<T> extends AsyncNotifier<PagedResult<T>> {
  /// Fetches exactly one page. Implemented per list.
  Future<PagedResult<T>> fetchPage(int page);

  /// Guards against a scroll listener firing twice before the first request lands.
  bool _loadingMore = false;

  /// Whether this instance's pages are held for the signed-in session (the lifetime policy at
  /// the top of this file). True for every tab-backing list; overridden false for transient
  /// variants — a live search, say — that would otherwise pin one cache entry per keystroke.
  bool get holdWhileSignedIn => true;

  @override
  Future<PagedResult<T>> build() {
    if (holdWhileSignedIn) holdForSession(ref);
    return fetchPage(0);
  }

  /// Appends the next page. Safe to call on every scroll event: it is a no-op while a request
  /// is in flight and at the end of the list.
  ///
  /// Returns null on success, or the failure to show without disturbing the list.
  Future<AppFailure?> loadMore() async {
    final current = state.value;
    final next = current?.nextPage;
    if (current == null || next == null || _loadingMore) return null;

    _loadingMore = true;
    try {
      final more = await fetchPage(next);
      state = AsyncData(current.followedBy(more));
      return null;
    } catch (error) {
      // Repositories already convert; this is belt and braces for anything that slips past.
      return AppFailure.from(error);
    } finally {
      _loadingMore = false;
    }
  }

  /// Throws the pages away and reloads from the top — pull-to-refresh.
  void refresh() => ref.invalidateSelf();
}

/// Residents, paginated. Reads public.students.
final studentsProvider =
    AsyncNotifierProvider.autoDispose.family<StudentsNotifier, PagedResult<Student>, StudentQuery>(
  StudentsNotifier.new,
);

class StudentsNotifier extends PagedNotifier<Student> {
  StudentsNotifier(this.query);
  final StudentQuery query;

  /// The unfiltered list is the tab; a typed search is a keystroke-keyed variant that must
  /// still die with its listeners, or every string the warden half-types stays cached (and is
  /// a page of resident PII) until sign-out.
  @override
  bool get holdWhileSignedIn => query.search == null || query.search!.isEmpty;

  @override
  Future<PagedResult<Student>> fetchPage(int page) =>
      ref.read(studentRepositoryProvider).page(
            hostelId: query.hostelId,
            page: page,
            search: query.search,
            status: query.status,
            includeVacated: query.includeVacated,
          );
}

/// Complaints, paginated. Reads public.complaints.
///
/// Serves both the staff queue and a resident's own list — RLS decides which rows come back,
/// so the two are the same query. See ComplaintRepository.page.
final complaintsProvider = AsyncNotifierProvider.autoDispose
    .family<ComplaintsNotifier, PagedResult<Complaint>, ComplaintQuery>(
  ComplaintsNotifier.new,
);

class ComplaintsNotifier extends PagedNotifier<Complaint> {
  ComplaintsNotifier(this.query);
  final ComplaintQuery query;

  @override
  Future<PagedResult<Complaint>> fetchPage(int page) =>
      ref.read(complaintRepositoryProvider).page(
            hostelId: query.hostelId,
            page: page,
            status: query.status,
            category: query.category,
            openOnly: query.openOnly,
          );
}

/// The month's fee ledger, paginated. Reads public.rpc_fee_ledger.
final feeLedgerProvider = AsyncNotifierProvider.autoDispose
    .family<FeeLedgerNotifier, PagedResult<FeeLedgerRow>, FeeLedgerQuery>(
  FeeLedgerNotifier.new,
);

class FeeLedgerNotifier extends PagedNotifier<FeeLedgerRow> {
  FeeLedgerNotifier(this.query);
  final FeeLedgerQuery query;

  @override
  Future<PagedResult<FeeLedgerRow>> fetchPage(int page) => ref.read(feeRepositoryProvider).ledger(
        hostelId: query.hostelId,
        periodMonth: query.periodMonth,
        page: page,
        status: query.status,
      );
}

/// Refunds against ONE RESIDENT, indexed by the month they belong to.
/// Reads public.payment_refunds.
///
/// ═══ WHY A SECOND READ AT ALL ═══
/// A refund is a child row of `payment_intents`, not a column on `fee_payments`, because a
/// month can be refunded more than once and a running-total column cannot be made idempotent
/// against a webhook Razorpay may deliver twice. So the fee rows and the refunds arrive
/// separately and a [RefundIndex] puts them back together — see models/refund.dart.
///
/// ═══ IT MAY FAIL, AND NOTHING BREAKS WHEN IT DOES ═══
/// Every screen reads this as `.value ?? RefundIndex.empty`. A refund panel is a QUALIFIER on a
/// figure that is already on screen from its own read; it must never be able to blank, block or
/// error the rent itself. The cost of that choice is stated plainly: if this read fails, a
/// refunded month reads exactly as it did before this feature existed. That is the same
/// position, not a worse one — and it is strictly better than a fees screen that will not draw
/// because a secondary query timed out.
///
/// Held for the session on the resident's own shell, where it backs the Fees tab, exactly as
/// [studentFeeHistoryProvider] is.
final studentRefundsProvider =
    FutureProvider.autoDispose.family<RefundIndex, String>((ref, studentId) async {
  if (ref.watch(sessionProvider.select((s) => s?.role)) == UserRole.student) {
    holdForSession(ref);
  }
  return RefundIndex.of(await ref.watch(feeRepositoryProvider).refundsForStudent(studentId));
});

/// Refunds against ONE HOSTEL, indexed by (resident, month). Reads public.payment_refunds.
///
/// [StatsQuery.periodMonth] narrows it: the warden's collections list is a month at a time and
/// passes one, the owner's "who paid" walks backwards through months as it pages and passes
/// null. Same failure contract as [studentRefundsProvider] — a screen reads it as
/// `.value ?? RefundIndex.empty` and the ledger draws regardless.
final hostelRefundsProvider =
    FutureProvider.autoDispose.family<RefundIndex, StatsQuery>((ref, query) async {
  holdForSession(ref);
  return RefundIndex.of(
    await ref.watch(feeRepositoryProvider).refundsForHostel(
          hostelId: query.hostelId,
          periodMonth: query.periodMonth,
        ),
  );
});

/// Who paid, most recently recorded first. Reads public.rpc_recent_payments.
///
/// THE OWNER'S "WHO PAID" LIST, and the warden's own record of what they have taken. Keyed by
/// hostel because that is the whole scope of the question; the RPC refuses a caller who may not
/// see a hostel's money, so an empty page here means nobody has paid yet and nothing else.
///
/// Held for the session like the other tab-backing lists: the owner's Payments tab watches this
/// directly and must redraw from the held value rather than blanking on every visit.
final recentPaymentsProvider = AsyncNotifierProvider.autoDispose
    .family<RecentPaymentsNotifier, PagedResult<RecentPayment>, String>(
  RecentPaymentsNotifier.new,
);

class RecentPaymentsNotifier extends PagedNotifier<RecentPayment> {
  RecentPaymentsNotifier(this.hostelId);
  final String hostelId;

  @override
  Future<PagedResult<RecentPayment>> fetchPage(int page) =>
      ref.read(feeRepositoryProvider).recentPayments(hostelId: hostelId, page: page);
}

/// The noticeboard, paginated. Reads public.announcements.
final noticesProvider =
    AsyncNotifierProvider.autoDispose.family<NoticesNotifier, PagedResult<Notice>, String>(
  NoticesNotifier.new,
);

class NoticesNotifier extends PagedNotifier<Notice> {
  NoticesNotifier(this.hostelId);
  final String hostelId;

  @override
  Future<PagedResult<Notice>> fetchPage(int page) =>
      ref.read(noticeRepositoryProvider).page(hostelId: hostelId, page: page);
}

/// Tasks, paginated. Reads public.tasks.
final tasksProvider =
    AsyncNotifierProvider.autoDispose.family<TasksNotifier, PagedResult<Task>, TaskQuery>(
  TasksNotifier.new,
);

class TasksNotifier extends PagedNotifier<Task> {
  TasksNotifier(this.query);
  final TaskQuery query;

  @override
  Future<PagedResult<Task>> fetchPage(int page) => ref.read(taskRepositoryProvider).page(
        hostelId: query.hostelId,
        page: page,
        status: query.status,
        assignedTo: query.assignedTo,
        openOnly: query.openOnly,
      );
}

/// Expenses, paginated. Reads public.expenses.
final expensesProvider =
    AsyncNotifierProvider.autoDispose.family<ExpensesNotifier, PagedResult<Expense>, String>(
  ExpensesNotifier.new,
);

class ExpensesNotifier extends PagedNotifier<Expense> {
  ExpensesNotifier(this.hostelId);
  final String hostelId;

  @override
  Future<PagedResult<Expense>> fetchPage(int page) =>
      ref.read(financeRepositoryProvider).expenses(hostelId: hostelId, page: page);
}

/// Revenue entries, paginated. Reads public.revenues.
final revenuesProvider =
    AsyncNotifierProvider.autoDispose.family<RevenuesNotifier, PagedResult<Revenue>, String>(
  RevenuesNotifier.new,
);

class RevenuesNotifier extends PagedNotifier<Revenue> {
  RevenuesNotifier(this.hostelId);
  final String hostelId;

  @override
  Future<PagedResult<Revenue>> fetchPage(int page) =>
      ref.read(financeRepositoryProvider).revenues(hostelId: hostelId, page: page);
}

/// Hostels across the platform, paginated. Super Admin only — reads public.rpc_sa_hostels.
final saHostelsProvider =
    AsyncNotifierProvider.autoDispose<SaHostelsNotifier, PagedResult<SaHostelRow>>(
  SaHostelsNotifier.new,
);

class SaHostelsNotifier extends PagedNotifier<SaHostelRow> {
  @override
  Future<PagedResult<SaHostelRow>> fetchPage(int page) =>
      ref.read(dashboardRepositoryProvider).superAdminHostels(page: page);
}

// ─────────────────────────────────────────────────────────────────────────────
// SINGLE READS
//
// FutureProvider for anything a screen only reads. autoDispose on the ones keyed by an id, so
// browsing twenty residents does not leave twenty cached rows of PII in memory.
// ─────────────────────────────────────────────────────────────────────────────

/// Headline numbers for a staff dashboard. public.rpc_hostel_stats.
final hostelStatsProvider =
    FutureProvider.autoDispose.family<HostelStats?, StatsQuery>((ref, query) {
  holdForSession(ref);
  return ref.watch(dashboardRepositoryProvider).hostelStats(
        hostelId: query.hostelId,
        periodMonth: query.periodMonth,
      );
});

/// The hostel row itself. public.hostels.
///
/// Was a plain (never-disposed) provider; now held per session instead, so the cached row
/// cannot survive a sign-out into the next login.
final hostelProvider = FutureProvider.autoDispose.family<Hostel?, String>((ref, hostelId) {
  holdForSession(ref);
  return ref.watch(hostelRepositoryProvider).byId(hostelId);
});

/// Storeys. public.floors. Session-held, same reasoning as [hostelProvider].
final floorsProvider =
    FutureProvider.autoDispose.family<List<Floor>, String>((ref, hostelId) {
  holdForSession(ref);
  return ref.watch(hostelRepositoryProvider).floors(hostelId);
});

/// The room grid with live occupancy. public.rpc_room_occupancy.
final roomOccupancyProvider =
    FutureProvider.autoDispose.family<List<RoomOccupancy>, String>((ref, hostelId) {
  holdForSession(ref);
  return ref.watch(roomRepositoryProvider).occupancy(hostelId);
});

/// Beds in one room. public.beds.
final bedsInRoomProvider =
    FutureProvider.autoDispose.family<List<Bed>, String>((ref, roomId) {
  return ref.watch(roomRepositoryProvider).bedsInRoom(roomId);
});

/// Every free bed, for the registration form. public.beds.
final freeBedsProvider =
    FutureProvider.autoDispose.family<List<Bed>, String>((ref, hostelId) {
  return ref.watch(roomRepositoryProvider).freeBeds(hostelId);
});

/// One resident. public.students.
final studentProvider =
    FutureProvider.autoDispose.family<Student?, String>((ref, studentId) {
  return ref.watch(studentRepositoryProvider).byId(studentId);
});

/// The signed-in resident's own record. public.students.
///
/// Session-held: rebuilds on sign-in and a change of user, and is dropped on sign-out, rather
/// than serving the previous person's row — holdForSession watches the signed-in user id.
final myStudentProvider = FutureProvider.autoDispose<Student?>((ref) {
  holdForSession(ref);
  return ref.watch(studentRepositoryProvider).me();
});

/// The mess menu for the week. public.menus.
///
/// ONE PROVIDER FOR BOTH ROLES, and it is the same 28 rows either way — the manager's Menu tab
/// watches it to edit the week, the resident's home screen and week view watch it to read it.
/// Two providers over one table would have been two caches, two lifetimes and two chances for
/// the screen the kitchen types into to disagree with the screen the residents read. They are
/// never the same session (a manager login and a resident login are different people), so this
/// is about there being one definition, not about sharing a cache between them.
///
/// ONE REQUEST, NEVER SEVEN. The whole week arrives in a single select — see
/// [MenuRepository.weeklyMenu] for why 28 rows are not paginated — and nothing polls it. The
/// menu changes when a manager changes it; a resident sees the new week on their next refresh
/// or their next sign-in, which is what a mess menu has always been.
///
/// Session-held: it backs the manager's Menu tab and the resident's home screen, both of which
/// must redraw from the held value on a revisit rather than blanking back to a skeleton.
final weeklyMenuProvider =
    FutureProvider.autoDispose.family<WeeklyMenu, String>((ref, hostelId) {
  holdForSession(ref);
  return ref.watch(menuRepositoryProvider).weeklyMenu(hostelId);
});

/// Roommates, names and phones only. public.st_my_roommates.
final roommatesProvider = FutureProvider.autoDispose<List<Roommate>>((ref) {
  holdForSession(ref);
  return ref.watch(studentRepositoryProvider).roommates();
});

/// Who to call about what. public.st_hostel_contacts.
final hostelContactsProvider = FutureProvider.autoDispose<HostelContacts?>((ref) {
  holdForSession(ref);
  return ref.watch(hostelRepositoryProvider).contacts();
});

/// One resident's payment history. public.fee_payments.
///
/// PAGINATED, AND THAT IS NOT A DETAIL — IT IS THE POINT. This list is the resident's own
/// financial record, it grows by one row a month and NOTHING EVER REMOVES A ROW: the retention
/// job (app.apply_retention, daily at 03:15) touches audit_log, security_alerts, rate_limits
/// and read notifications, and does not name fee_payments at all. A resident of two years has
/// twenty-four months, which is more than one page, so a provider that could only ever hold
/// page 0 made the client the one place where a permanent record got shortened. It used to be a
/// plain FutureProvider and the Fees screen apologised for it in a sentence
/// ("ask your warden for anything older"); now the screen can ask for the rest.
///
/// The type this exposes is unchanged — `AsyncValue<PagedResult<FeePayment>>` — so the staff
/// sheets that watch one resident's last few months (warden/students/student_sheet.dart,
/// owner_students_screen.dart) read exactly as they did. What they gain is a `.notifier` they
/// may call `loadMore()` on if they ever want the rest.
///
/// Held ONLY for a resident's own shell, where it backs the Fees tab and RLS means the one id
/// they can read is their own. For staff this is a per-resident detail behind a sheet, and
/// stays plain autoDispose so browsing residents does not pin every history until sign-out.
final studentFeeHistoryProvider = AsyncNotifierProvider.autoDispose
    .family<StudentFeeHistoryNotifier, PagedResult<FeePayment>, String>(
  StudentFeeHistoryNotifier.new,
);

class StudentFeeHistoryNotifier extends PagedNotifier<FeePayment> {
  StudentFeeHistoryNotifier(this.studentId);
  final String studentId;

  /// The resident's own tab holds; a staff sheet does not. Same rule as before, moved from the
  /// old provider body into the hook [PagedNotifier.build] already consults.
  @override
  bool get holdWhileSignedIn =>
      ref.watch(sessionProvider.select((s) => s?.role)) == UserRole.student;

  @override
  Future<PagedResult<FeePayment>> fetchPage(int page) =>
      ref.read(feeRepositoryProvider).forStudent(studentId: studentId, page: page);
}

/// One complaint. public.complaints.
final complaintProvider =
    FutureProvider.autoDispose.family<Complaint?, String>((ref, complaintId) {
  return ref.watch(complaintRepositoryProvider).byId(complaintId);
});

/// A complaint's status history. public.complaint_events.
final complaintTimelineProvider =
    FutureProvider.autoDispose.family<List<ComplaintEvent>, String>((ref, complaintId) {
  return ref.watch(complaintRepositoryProvider).timeline(complaintId);
});

/// A short-lived URL for one complaint's photo, or null when it has none.
///
/// AUTO-DISPOSE WITH NO HOLD, and that is not the usual lifetime argument — it is the URL's.
/// A signed URL is a bearer capability with a 30-minute life (SIGNED_URL_TTL in
/// supabase/functions/_shared/storage.ts). Holding one for the session would keep handing a
/// stale link to a sheet reopened forty minutes later, which renders a broken image and looks
/// like a missing photo. Scoped to the sheet that is looking, re-minted on the next look.
///
/// ONE PROVIDER FOR THREE ROLES. The resident's sheet, the warden's sheet and the owner's sheet
/// all watch this, because who may see the photo is decided on the server by the same
/// `complaints_select` policy that decided who may see the complaint. A per-role provider would
/// be three copies of a rule that lives in one place.
final complaintPhotoProvider =
    FutureProvider.autoDispose.family<Uri?, String>((ref, complaintId) {
  return ref.watch(complaintRepositoryProvider).photoUrl(complaintId);
});

/// Revenue against expense, day by day. public.rpc_daily_finance.
final dailyFinanceProvider =
    FutureProvider.autoDispose.family<List<FinanceDay>, FinanceRangeQuery>((ref, query) {
  holdForSession(ref);
  return ref.watch(financeRepositoryProvider).daily(
        hostelId: query.hostelId,
        from: query.from,
        to: query.to,
      );
});

/// The number on the notification bell. public.rpc_unread_count.
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) {
  holdForSession(ref);
  return ref.watch(dashboardRepositoryProvider).unreadCount();
});

/// Platform totals. Super Admin only — public.rpc_sa_dashboard.
///
/// Null means "not permitted", never "no hostels": the RPC returns zero rows to anyone who is
/// not a Super Admin. See DashboardRepository.superAdminStats.
final saStatsProvider = FutureProvider.autoDispose<SaStats?>((ref) {
  holdForSession(ref);
  return ref.watch(dashboardRepositoryProvider).superAdminStats();
});
