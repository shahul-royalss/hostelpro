library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/perf/session_keep_alive.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import 'sa_models.dart';
import 'sa_repository.dart';

/// Providers for the platform console.
///
/// HAND-WRITTEN, matching lib/data/providers.dart — no codegen, nothing to regenerate. Two
/// things the shared file already exposes are used from there and NOT redeclared:
/// `saStatsProvider` (public.rpc_sa_dashboard) and `hostelStatsProvider`
/// (public.rpc_hostel_stats, which is `security invoker` and therefore returns any hostel to a
/// Super Admin because `hostels_select` admits them). `saHostelsProvider` in that file is the
/// unfiltered list; the console needs a searchable one, so [saHostelListProvider] supersedes it
/// here rather than the shared one growing a query object only one role uses.

final saRepositoryProvider = Provider<SaRepository>(
  (ref) => SaRepository(ref.watch(supabaseClientProvider)),
);

/// The two calls that change something, TYPED BY THE INTERFACE rather than by the class.
///
/// Everything else here is a read, and a screen that reads is tested by overriding the provider
/// holding the answer. These two are not: one mints a credential that exists exactly once, the
/// other is the only mutation the database permits on an evidence table. Their interesting
/// states are worth holding down in `flutter test`, which needs a fake in this slot. See
/// SaPlatformWrites — and RentDesk, which is in this shape for the same reason.
final saPlatformWritesProvider = Provider<SaPlatformWrites>(
  (ref) => ref.watch(saRepositoryProvider),
);

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGATION
// ─────────────────────────────────────────────────────────────────────────────

/// The four tabs, by index.
///
/// NAMED CONSTANTS RATHER THAN LITERALS, because three files agree about this order —
/// features/shell/role_shell.dart (which owns the label and icon for every role's navigation),
/// SaShell (which owns the IndexedStack), and the Overview (whose figures jump to the tab that
/// lists them). `go(2)` in one of them and a reordered bar in another is a mis-routed tap that
/// nothing catches.
abstract final class SaTabs {
  static const overview = 0;
  static const hostels = 1;
  static const subscriptions = 2;
  static const security = 3;
  static const count = 4;
}

/// Which of the four tabs the console is on.
///
/// A PROVIDER, NOT LOCAL STATE, for the same reason the warden's is: the Overview's figures are
/// tappable. "3 expired" is a fact; "3 expired — tap to see which" is a tool, and landing on the
/// Subscriptions tab already filtered to `expired` is what makes the number and the list agree.
class SaTab extends Notifier<int> {
  @override
  int build() {
    // Rebuilt to Overview when the signed-in user changes. UI state is small, but "which tab
    // was open" is still the previous admin's context and has no business greeting the next.
    ref.watch(sessionProvider.select((s) => s?.userId));
    return 0;
  }
  void go(int index) => state = index;
}

final saTabProvider = NotifierProvider<SaTab, int>(SaTab.new);

// ─────────────────────────────────────────────────────────────────────────────
// HOSTELS
// ─────────────────────────────────────────────────────────────────────────────

/// Which hostels to list. Value equality so two identical searches share one cache entry and
/// one request — without it every keystroke that produced the same text would refetch.
final class SaHostelQuery {
  const SaHostelQuery({this.search, this.subState, this.hostelStatus});

  /// Matched by Postgres against hostel name, owner name, owner email and address. Debouncing
  /// keystrokes is the screen's job; each distinct value here is a distinct request.
  final String? search;
  final SubscriptionState? subState;
  final HostelStatus? hostelStatus;

  bool get isFiltered =>
      (search ?? '').trim().isNotEmpty || subState != null || hostelStatus != null;

  SaHostelQuery copyWith({
    String? search,
    bool clearSearch = false,
    SubscriptionState? subState,
    bool clearSubState = false,
    HostelStatus? hostelStatus,
    bool clearHostelStatus = false,
  }) {
    return SaHostelQuery(
      search: clearSearch ? null : (search ?? this.search),
      subState: clearSubState ? null : (subState ?? this.subState),
      hostelStatus: clearHostelStatus ? null : (hostelStatus ?? this.hostelStatus),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SaHostelQuery &&
      other.search == search &&
      other.subState == subState &&
      other.hostelStatus == hostelStatus;

  @override
  int get hashCode => Object.hash(search, subState, hostelStatus);
}

/// The Hostels tab's live query. Held apart from the list so changing a filter does not have to
/// rebuild the list widget to be noticed.
class SaHostelFilter extends Notifier<SaHostelQuery> {
  @override
  SaHostelQuery build() {
    // Reset on user change. The fetched DATA is already session-scoped (holdForSession), but a
    // filter is UI state and used to survive sign-out — including the typed search string,
    // which can contain an owner's name or email the previous admin was looking up. A filter
    // outliving the person who typed it is a small leak; small leaks are still leaks.
    ref.watch(sessionProvider.select((s) => s?.userId));
    return const SaHostelQuery();
  }

  void search(String? text) {
    final trimmed = (text ?? '').trim();
    state = state.copyWith(search: trimmed.isEmpty ? null : trimmed, clearSearch: trimmed.isEmpty);
  }

  void subscription(SubscriptionState? value) =>
      state = state.copyWith(subState: value, clearSubState: value == null);

  void hostel(HostelStatus? value) =>
      state = state.copyWith(hostelStatus: value, clearHostelStatus: value == null);

  void clear() => state = const SaHostelQuery();
}

final saHostelFilterProvider =
    NotifierProvider<SaHostelFilter, SaHostelQuery>(SaHostelFilter.new);

/// Hostels across the platform, paginated and filtered server-side. public.rpc_sa_hostels.
///
/// EMPTY DOES NOT MEAN "NO HOSTELS". The function ends in `where app.is_super_admin()`, so any
/// other role gets zero rows instead of a refusal — see SaRepository. The screen distinguishes
/// the two by whether [saStatsProvider] also came back null.
final saHostelListProvider = AsyncNotifierProvider.autoDispose
    .family<SaHostelListNotifier, PagedResult<SaHostelRow>, SaHostelQuery>(
  SaHostelListNotifier.new,
);

class SaHostelListNotifier extends PagedNotifier<SaHostelRow> {
  SaHostelListNotifier(this.query);
  final SaHostelQuery query;

  /// The lifetime policy at the top of lib/data/providers.dart, applied to this family.
  ///
  /// The DEFAULT query backs two tabs at once (Hostels unfiltered, and Subscriptions with no
  /// state picked narrows to the same value-equal key), and the enum-filtered variants are the
  /// Overview's "3 expired — tap to see which" landing pages; all of those are bounded in
  /// number and are held for the session so a revisit renders instantly. A LIVE SEARCH is not:
  /// every distinct string is its own family member, and holding each one would pin a cache
  /// entry per settled keystroke until sign-out. Search results therefore keep plain
  /// autoDispose and die with their screen.
  @override
  bool get holdWhileSignedIn => (query.search ?? '').trim().isEmpty;

  @override
  Future<PagedResult<SaHostelRow>> fetchPage(int page) =>
      ref.read(saRepositoryProvider).hostels(
            page: page,
            search: query.search,
            subState: query.subState,
            hostelStatus: query.hostelStatus,
          );
}

/// One hostel's summary row, for the detail screen. public.rpc_sa_hostels.
final saHostelProvider =
    FutureProvider.autoDispose.family<SaHostelRow?, String>((ref, hostelId) {
  return ref.watch(saRepositoryProvider).hostel(hostelId);
});

/// Hostels onboarded per month, last twelve. public.rpc_sa_onboarding_series.
///
/// Backs the Overview — session-held per the lifetime policy, so a pull-to-refresh redraws the
/// chart in place rather than blanking it, and the series is dropped the moment the admin
/// signs out.
final saOnboardingProvider = FutureProvider.autoDispose<List<OnboardingPoint>>((ref) {
  holdForSession(ref);
  return ref.watch(saRepositoryProvider).onboardingSeries();
});

// ─────────────────────────────────────────────────────────────────────────────
// SUBSCRIPTIONS
// ─────────────────────────────────────────────────────────────────────────────

/// Which subscription states the Subscriptions tab is showing. Null is all of them.
///
/// SEPARATE FROM [saHostelFilterProvider] because the two tabs are two questions. The Hostels
/// tab is "find me this hostel"; this one is "show me the ones about to lapse", and an admin who
/// filtered one should not find the other silently narrowed underneath them.
class SaSubscriptionFilter extends Notifier<SubscriptionState?> {
  @override
  SubscriptionState? build() {
    // Reset on user change — same reasoning as SaHostelFilter.
    ref.watch(sessionProvider.select((s) => s?.userId));
    return null;
  }
  void set(SubscriptionState? value) => state = value;
}

final saSubscriptionFilterProvider =
    NotifierProvider<SaSubscriptionFilter, SubscriptionState?>(SaSubscriptionFilter.new);

/// Every paid period for one hostel, newest first. public.subscriptions.
final saSubscriptionHistoryProvider =
    FutureProvider.autoDispose.family<List<SubscriptionRecord>, String>((ref, hostelId) {
  return ref.watch(saRepositoryProvider).subscriptionHistory(hostelId);
});

// ─────────────────────────────────────────────────────────────────────────────
// OWNERS
// ─────────────────────────────────────────────────────────────────────────────

/// Owner accounts and how many hostels each holds. public.users + public.hostels.
///
/// SESSION-HELD, NOT PLAIN: the wizard reads it on step one and the review step reads the
/// picked row again three steps later, and refetching between them would let the summary panel
/// disagree with what was chosen — holdForSession keeps that guarantee for as long as the
/// admin is signed in. It used to be a never-disposed FutureProvider, which kept the same
/// promise but also kept every owner's name and email cached PAST sign-out; the hold gives the
/// wizard the identical in-session behaviour and drops the list with the session. Invalidated
/// after a successful create, which is the only thing that changes it from inside this app.
final saOwnersProvider = FutureProvider.autoDispose<List<SaOwnerOption>>((ref) {
  holdForSession(ref);
  return ref.watch(saRepositoryProvider).owners();
});

// ─────────────────────────────────────────────────────────────────────────────
// SECURITY CONSOLE
// ─────────────────────────────────────────────────────────────────────────────

/// Which alerts the console is showing.
enum AlertFilter {
  open('Unacknowledged'),
  all('All');

  const AlertFilter(this.label);
  final String label;

  bool get openOnly => this == AlertFilter.open;
}

class SaAlertFilter extends Notifier<AlertFilter> {
  @override
  AlertFilter build() {
    // Reset on user change — same reasoning as SaHostelFilter.
    ref.watch(sessionProvider.select((s) => s?.userId));
    return AlertFilter.open;
  }
  void set(AlertFilter value) => state = value;
}

final saAlertFilterProvider =
    NotifierProvider<SaAlertFilter, AlertFilter>(SaAlertFilter.new);

/// Alerts raised by app.detect_suspicious_activity(), newest first. public.security_alerts.
///
/// A NOTIFIER RATHER THAN A FutureProvider, because acknowledging one has to change the row in
/// place. Re-fetching the whole console after each tap would reorder nothing but would flash the
/// list, lose the scroll position, and — with the filter on "Unacknowledged" — make the row the
/// admin just read vanish before they had finished reading it. See [SaAlertsNotifier.acknowledge].
final saAlertsProvider = AsyncNotifierProvider.autoDispose
    .family<SaAlertsNotifier, List<SecurityAlert>, bool>(SaAlertsNotifier.new);

class SaAlertsNotifier extends AsyncNotifier<List<SecurityAlert>> {
  SaAlertsNotifier(this.openOnly);

  /// True for the "Unacknowledged" filter — the server does the filtering, so the two tabs are
  /// two queries rather than one query and a client-side hide.
  final bool openOnly;

  @override
  Future<List<SecurityAlert>> build() {
    // Session-held (two family members at most — openOnly is a bool), so the console the
    // TabWarmer warmed at sign-in is still warm when the Security tab is finally tapped, and
    // an acknowledge-then-revisit renders the stamped list instantly instead of refetching
    // from blank. Dropped outright on sign-out.
    holdForSession(ref);
    return fetch();
  }

  /// The one read, apart from [build] so a test can substitute rows while the lifetime logic
  /// above still runs for real.
  Future<List<SecurityAlert>> fetch() =>
      ref.read(saRepositoryProvider).securityAlerts(openOnly: openOnly);

  /// Marks one alert as seen and stamps the row locally.
  ///
  /// THE ROW IS UPDATED, NOT REMOVED, even under the "Unacknowledged" filter. The alert stays on
  /// screen wearing its new "Acknowledged" state until the console is refreshed — an entry that
  /// disappears the instant it is touched is how a Super Admin loses the one detail they were
  /// about to write down, and the acknowledgement is already durable on the server by then.
  ///
  /// Returns null on success, or the failure to show without disturbing the list. A refusal here
  /// is not hypothetical: ack_security_alert() raises 42501 for anyone who is neither the Super
  /// Admin nor the owner of the alert's hostel.
  Future<AppFailure?> acknowledge(int alertId, String byUserId) async {
    final current = state.value;
    // NOT `return null`. Null is this method's word for "it worked", and returning it without
    // having written anything is how a tap on Acknowledge came back silent and unchanged: the
    // card cleared its spinner, showed no message, and the alert stayed open. There are no rows
    // to stamp because the list is not loaded, which is a state worth saying out loud.
    if (current == null) {
      return const UnexpectedFailure(
        'The alert list is not loaded, so nothing was acknowledged. Pull to refresh and try '
        'again.',
      );
    }
    try {
      await ref.read(saPlatformWritesProvider).acknowledgeAlert(alertId);
      state = AsyncData([
        for (final alert in current)
          if (alert.id == alertId && alert.isOpen) alert.acknowledgedNow(byUserId) else alert,
      ]);
      // The Overview's badge counts open alerts and has just gone stale by one.
      ref.invalidate(saOpenAlertCountProvider);
      return null;
    } catch (error) {
      return AppFailure.from(error);
    }
  }

  void refresh() => ref.invalidateSelf();
}

/// How many alerts are still unacknowledged — the number on the Overview.
///
/// Counted from the rows the console itself would show, capped the same way, so the badge and
/// the list can never disagree. Zero is drawn as "nothing outstanding", never as an empty badge.
///
/// WAS A PLAIN, NEVER-DISPOSED FutureProvider, which meant the previous admin's count could
/// survive a sign-out into the next login. Session-held instead: identical behaviour while
/// signed in (the shell's badge watches it continuously anyway), dropped the moment the
/// session ends.
final saOpenAlertCountProvider = FutureProvider.autoDispose<int>((ref) async {
  holdForSession(ref);
  final alerts = await ref.watch(saRepositoryProvider).securityAlerts(openOnly: true);
  return alerts.length;
});
