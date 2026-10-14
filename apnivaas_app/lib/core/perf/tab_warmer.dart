/// Background warm-up for the tabs the user has not tapped yet.
///
/// THE CONTRACT THIS FILE EXISTS TO KEEP. Tapping a tab must never show a skeleton in normal
/// use. The data must already be there — fetched in the background after the home tab has won
/// the network, and held warm for the shell's lifetime (see `holdForSession` and the lifetime
/// policy at the top of lib/data/providers.dart). A [TabWarmer] does the first half of that:
/// it starts every other tab's first-page request, in order, after the first frame, spaced out
/// so warm-up never contends with what the user is looking at.
///
/// HOW A SHELL USES IT.
///
/// ```dart
/// class _WardenShellState extends ConsumerState<WardenShell> {
///   TabWarmer? _warmer;
///
///   @override
///   void initState() {
///     super.initState();
///     // Order = the order the user is most likely to tap. The HOME tab is NOT in this
///     // list: the home screen watches its own providers during build, so its requests
///     // are already on the wire before the first warmer fires.
///     _warmer = TabWarmer([
///       () => ref.read(studentsProvider(StudentQuery(hostelId: id)).future),
///       () => ref.read(feeLedgerProvider(FeeLedgerQuery(hostelId: id, periodMonth: m)).future),
///       () => ref.read(complaintsProvider(ComplaintQuery(hostelId: id)).future),
///       () => ref.read(roomOccupancyProvider(id).future),
///     ])..start();
///   }
///
///   @override
///   void dispose() {
///     _warmer?.cancel();
///     super.dispose();
///   }
/// }
/// ```
///
/// WHY `ref.read(provider.future)` IS THE WHOLE TRICK. Reading a FutureProvider's (or an
/// AsyncNotifierProvider's) `.future` instantiates the provider and starts its fetch exactly
/// as a screen watching it would — same provider, same RLS, same cache entry the tab will
/// later watch. Warming therefore cannot widen a read: it can only start, early, a request
/// the screen was already entitled to make. The returned future is deliberately ignored;
/// a warmer that fails just means that tab cold-loads exactly as it would have today.
///
/// WARM DATA MUST ALSO BE HELD. Warming an autoDispose provider that nothing holds is a
/// wasted request — the value is thrown away the moment the warm read completes. Every
/// provider in a warm list must therefore call `holdForSession(ref)` in its build (the
/// tab-backing providers in lib/data/providers.dart already do). Warm a provider that does
/// not, and the fix is to add the hold to the provider, not to re-warm harder.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';

/// One background warm. Typically `() => ref.read(someProvider(key).future)`.
///
/// May be synchronous or return a future; either way any error it produces is swallowed
/// (see [TabWarmer]).
typedef Warmer = FutureOr<void> Function();

/// Runs an ordered list of [Warmer]s after the first frame, one every [interval].
///
/// The stagger exists so warm-up never contends with what the user is looking at: the home
/// tab's own requests go out during its first build, the first warmer only fires one interval
/// after the frame that painted it, and each subsequent warmer waits another interval. ~150ms
/// is enough to keep requests from queueing behind each other on a phone radio without the
/// last tab still being cold when the user gets around to it.
///
/// ERRORS NEVER ESCAPE. Each warmer runs inside a try/catch and any future it returns has its
/// error swallowed. A failed warm is not an event — the tab it was for simply cold-loads on
/// first tap, exactly as it would have without warm-up, and the screen's own error handling
/// (AsyncSection, retry buttons) remains the one place failures are shown.
///
/// [start] is idempotent; [cancel] stops any warmers that have not fired yet (fire-and-forget
/// requests already started are left to complete — Riverpod discards their results if their
/// provider has been disposed). A cancelled warmer never restarts: create a new [TabWarmer]
/// per shell mount.
class TabWarmer {
  TabWarmer(
    this._warmers, {
    this.interval = const Duration(milliseconds: 150),
    void Function(void Function())? postFrame,
  }) : _postFrame = postFrame ?? _schedulerPostFrame;

  final List<Warmer> _warmers;

  /// Delay before the first warmer and between consecutive warmers.
  final Duration interval;

  /// How "after the first frame" is scheduled. Injectable so unit tests can run the timers
  /// under fakeAsync without a widget binding; production uses [SchedulerBinding].
  final void Function(void Function()) _postFrame;

  Timer? _timer;
  int _next = 0;
  bool _started = false;
  bool _cancelled = false;

  /// True once every warmer has fired (or the list was empty).
  bool get isDone => _next >= _warmers.length;

  /// Schedules the warmers. Calling again is a no-op.
  void start() {
    if (_started || _cancelled) return;
    _started = true;
    _postFrame(() {
      if (_cancelled) return;
      _scheduleNext();
    });
  }

  /// Stops any warmers that have not fired yet. Safe to call more than once.
  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleNext() {
    if (isDone) return;
    _timer = Timer(interval, () {
      if (_cancelled) return;
      _fire(_warmers[_next]);
      _next += 1;
      _scheduleNext();
    });
  }

  /// Runs one warmer, swallowing both synchronous throws and asynchronous errors.
  static void _fire(Warmer warm) {
    try {
      final result = warm();
      if (result is Future) {
        unawaited(_swallow(result));
      }
    } catch (_) {
      // Same rule for a warmer that throws before returning a future.
    }
  }

  /// Awaits a warm read and discards any error. NOT `future.catchError(...)`: the futures
  /// warmers return are typed — `ref.read(provider.future)` is a `Future<PagedResult<…>>` and
  /// friends — and `catchError` demands a handler that produces a value of that type, so a
  /// void handler turns every failed warm into an ArgumentError instead of a swallowed miss.
  static Future<void> _swallow(Future<dynamic> future) async {
    try {
      await future;
    } catch (_) {
      // Swallowed by design: warm-up must never surface an error or crash the shell.
      // The tab this was for cold-loads on first tap instead, which is today's behaviour.
    }
  }

  static void _schedulerPostFrame(void Function() callback) {
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) => callback());
    // A post-frame callback fires only if a frame actually happens. Called from a shell's
    // initState one is already being built, and this is a no-op; called from anywhere else
    // (or a bare test binding, which only pumps frames that were scheduled) it makes sure
    // the frame — and therefore the warm-up — is coming.
    binding.ensureVisualUpdate();
  }
}
