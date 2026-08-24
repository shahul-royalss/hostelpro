library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth/auth_controller.dart';
import 'models/models.dart';
import 'repositories/complaint_repository.dart';
import 'repositories/dashboard_repository.dart';
import 'repositories/fee_repository.dart';
import 'repositories/finance_repository.dart';
import 'repositories/hostel_repository.dart';
import 'repositories/notice_repository.dart';
import 'repositories/payment_repository.dart';
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

final complaintRepositoryProvider = Provider<ComplaintRepository>(
  (ref) => ComplaintRepository(ref.watch(supabaseClientProvider)),
);

final noticeRepositoryProvider = Provider<NoticeRepository>(
  (ref) => NoticeRepository(ref.watch(supabaseClientProvider)),
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

/// Rent paid inside the app. public.payment_intents + the razorpay-order Edge Function.
///
/// TYPED BY THE INTERFACE, not by the class, unlike every other repository here. The payment
/// state machine is the one piece of this app whose interesting states are all about money that
/// has moved but has not landed, and those are worth holding down in `flutter test` — which
/// needs a fake in this slot. See RentPayments.
final paymentRepositoryProvider = Provider<RentPayments>(
  (ref) => PaymentRepository(ref.watch(supabaseClientProvider)),
);

/// The native Razorpay checkout.
///
/// A PROVIDER SO IT CAN BE REPLACED. `razorpay_flutter` talks over a MethodChannel, and a
/// widget test has no platform on the other end of one — constructing the real plugin in a test
/// makes the payment flow untestable and the failure looks like a hang rather than a mistake.
/// Overriding this with a fake lets the whole state machine (order, checkout, confirmation,
/// failure, cancellation) run in `flutter test`, which is where it is actually verified.
///
/// autoDispose with an explicit teardown: the plugin's event handlers are registered on an
/// emitter the instance owns, so an instance that is dropped without [RazorpayCheckout.dispose]
/// keeps delivering results to widgets that no longer exist.
final razorpayCheckoutProvider = Provider.autoDispose<RazorpayCheckout>((ref) {
  final checkout = PluginRazorpayCheckout();
  ref.onDispose(checkout.dispose);
  return checkout;
});

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

  @override
  Future<PagedResult<T>> build() => fetchPage(0);

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
  return ref.watch(dashboardRepositoryProvider).hostelStats(
        hostelId: query.hostelId,
        periodMonth: query.periodMonth,
      );
});

/// The hostel row itself. public.hostels.
final hostelProvider = FutureProvider.family<Hostel?, String>((ref, hostelId) {
  return ref.watch(hostelRepositoryProvider).byId(hostelId);
});

/// Storeys. public.floors.
final floorsProvider = FutureProvider.family<List<Floor>, String>((ref, hostelId) {
  return ref.watch(hostelRepositoryProvider).floors(hostelId);
});

/// The room grid with live occupancy. public.rpc_room_occupancy.
final roomOccupancyProvider =
    FutureProvider.autoDispose.family<List<RoomOccupancy>, String>((ref, hostelId) {
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
final myStudentProvider = FutureProvider<Student?>((ref) {
  // Rebuilds on sign-in and sign-out rather than serving the previous person's row.
  ref.watch(sessionProvider);
  return ref.watch(studentRepositoryProvider).me();
});

/// Roommates, names and phones only. public.st_my_roommates.
final roommatesProvider = FutureProvider.autoDispose<List<Roommate>>((ref) {
  return ref.watch(studentRepositoryProvider).roommates();
});

/// Who to call about what. public.st_hostel_contacts.
final hostelContactsProvider = FutureProvider<HostelContacts?>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(hostelRepositoryProvider).contacts();
});

/// One resident's payment history. public.fee_payments.
final studentFeeHistoryProvider =
    FutureProvider.autoDispose.family<PagedResult<FeePayment>, String>((ref, studentId) {
  return ref.watch(feeRepositoryProvider).forStudent(studentId: studentId);
});

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

/// Revenue against expense, day by day. public.rpc_daily_finance.
final dailyFinanceProvider =
    FutureProvider.autoDispose.family<List<FinanceDay>, FinanceRangeQuery>((ref, query) {
  return ref.watch(financeRepositoryProvider).daily(
        hostelId: query.hostelId,
        from: query.from,
        to: query.to,
      );
});

/// The number on the notification bell. public.rpc_unread_count.
final unreadCountProvider = FutureProvider<int>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(dashboardRepositoryProvider).unreadCount();
});

/// Platform totals. Super Admin only — public.rpc_sa_dashboard.
///
/// Null means "not permitted", never "no hostels": the RPC returns zero rows to anyone who is
/// not a Super Admin. See DashboardRepository.superAdminStats.
final saStatsProvider = FutureProvider.autoDispose<SaStats?>((ref) {
  return ref.watch(dashboardRepositoryProvider).superAdminStats();
});
