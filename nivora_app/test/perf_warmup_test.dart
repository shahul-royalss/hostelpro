import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/perf/session_keep_alive.dart';
import 'package:mobile/core/perf/tab_warmer.dart';

/// The shared warm-up mechanism every shell builds on: TabWarmer (order, stagger, errors
/// swallowed, cancel) and holdForSession (data survives a tab leaving the screen, is refreshed
/// in place rather than blanked, and is DROPPED on sign-out — the one way this caching could
/// have become a privacy bug).
///
/// No network and no screens: TabWarmer runs under the test binding, whose fake clock drives
/// both its post-frame callback and its stagger timers, and holdForSession is probed through a
/// test-local family provider with sessionProvider overridden by a mutable fake.
void main() {
  const tick = Duration(milliseconds: 150);

  group('TabWarmer', () {
    testWidgets('fires warmers in order, one interval apart, none before the frame',
        (tester) async {
      final fired = <int>[];
      TabWarmer([() => fired.add(0), () => fired.add(1), () => fired.add(2)]).start();

      // Nothing runs before a frame has been painted…
      expect(fired, isEmpty);

      // …and nothing runs AT the frame either: the home tab's requests, dispatched during
      // its build, get a full interval's head start on the network.
      await tester.pump();
      expect(fired, isEmpty);

      await tester.pump(const Duration(milliseconds: 149));
      expect(fired, isEmpty, reason: 'first warmer waits the full stagger');
      await tester.pump(const Duration(milliseconds: 1));
      expect(fired, [0]);

      await tester.pump(const Duration(milliseconds: 149));
      expect(fired, [0], reason: 'warmers are staggered, not batched');
      await tester.pump(const Duration(milliseconds: 1));
      expect(fired, [0, 1]);

      await tester.pump(tick);
      expect(fired, [0, 1, 2]);
      await tester.pump(const Duration(minutes: 1));
      expect(fired, [0, 1, 2], reason: 'each warmer fires exactly once');
    });

    testWidgets('a warmer that throws, or whose future fails, does not stop the rest',
        (tester) async {
      final fired = <int>[];
      TabWarmer(
        [
          () => throw StateError('sync boom'),
          () => Future<void>.error(StateError('async boom')),
          // A TYPED future, which is what `ref.read(provider.future)` actually returns. This
          // is the case a bare `.catchError((e, st) {})` cannot swallow: its void handler
          // cannot produce an int, so the swallow itself threw an ArgumentError and took the
          // whole test (or app zone) down with it.
          () => Future<int>.error(StateError('typed async boom')),
          () => fired.add(3),
        ],
        postFrame: (cb) => cb(),
      ).start();

      await tester.pump(tick * 4);
      expect(fired, [3], reason: 'all three failures are swallowed and the sequence continues');
      // Reaching here without the test's zone reporting an unhandled error IS the
      // error-swallowing assertion for the async case.
    });

    testWidgets('cancel stops warmers that have not fired; start is idempotent',
        (tester) async {
      final fired = <int>[];
      final warmer = TabWarmer(
        [() => fired.add(0), () => fired.add(1)],
        postFrame: (cb) => cb(),
      );
      warmer.start();
      warmer.start(); // a second start must not double-schedule

      await tester.pump(tick);
      expect(fired, [0]);

      warmer.cancel();
      await tester.pump(const Duration(minutes: 1));
      expect(fired, [0], reason: 'the un-fired warmer never runs after cancel');
      expect(warmer.isDone, isFalse);
    });
  });

  group('holdForSession', () {
    const warden = NivoraSession(
      userId: 'user-1',
      role: UserRole.warden,
      fullName: 'Warden One',
      status: 'active',
      mustChangePassword: false,
      hostelId: 'hostel-1',
    );
    const nextWarden = NivoraSession(
      userId: 'user-2',
      role: UserRole.warden,
      fullName: 'Warden Two',
      status: 'active',
      mustChangePassword: false,
      hostelId: 'hostel-1',
    );

    late int fetches;
    // The probe stands in for any tab-backing provider in lib/data/providers.dart: a family
    // FutureProvider whose build starts with holdForSession(ref).
    final probe = FutureProvider.autoDispose.family<int, String>((ref, hostelId) {
      holdForSession(ref);
      fetches += 1;
      return Future.value(fetches);
    });

    late _FakeSession auth;
    late ProviderContainer container;

    setUp(() {
      fetches = 0;
      auth = _FakeSession(warden);
      container = ProviderContainer(overrides: [
        sessionProvider.overrideWith((ref) => auth.session(ref)),
      ]);
      addTearDown(container.dispose);
    });

    // Lets the container's dispose scheduler run, the way an event-loop turn does in the app.
    Future<void> pump() => Future<void>.delayed(Duration.zero);

    test('data survives its listeners while signed in — a revisit does not refetch', () async {
      final sub = container.listen(probe('hostel-1'), (_, _) {});
      expect(await container.read(probe('hostel-1').future), 1);

      sub.close(); // the user taps away from the tab
      await pump();

      // Revisit: same value, no new fetch, and it is there synchronously — no skeleton.
      expect(container.read(probe('hostel-1')).value, 1);
      expect(fetches, 1);
    });

    test('a refresh keeps the previous value visible while it is in flight', () async {
      await container.read(probe('hostel-1').future);
      container.invalidate(probe('hostel-1'));

      final refreshing = container.read(probe('hostel-1'));
      expect(refreshing.isLoading, isTrue);
      expect(refreshing.value, 1,
          reason: 'stale-while-revalidate: the screen renders this, never a skeleton');
      expect(await container.read(probe('hostel-1').future), 2);
    });

    test('sign-out drops the held state entirely', () async {
      // The shell is mounted and watching, as it is at the moment a real sign-out happens.
      final sub = container.listen(probe('hostel-1'), (_, _) {});
      expect(await container.read(probe('hostel-1').future), 1);

      auth.set(null); // sign out: the hold is released…
      await pump(); //    …the change propagates (in the app, before the next frame)…
      sub.close(); //     …and the sign-out redirect unmounts the shell
      await pump();

      // Next login must start from blank: nothing of user-1's cache is even briefly visible.
      auth.set(nextWarden);
      final fresh = container.read(probe('hostel-1'));
      expect(fresh.isLoading, isTrue);
      expect(fresh.value, isNull,
          reason: 'cached tenant data must not survive into the next login');
    });

    test('a different user signing in refetches under the new session', () async {
      final sub = container.listen(probe('hostel-1'), (_, _) {});
      addTearDown(sub.close);
      expect(await container.read(probe('hostel-1').future), 1);

      auth.set(nextWarden);
      expect(await container.read(probe('hostel-1').future), 2,
          reason: 'same family key, but a new user means a new fetch under their RLS');
    });
  });
}

/// A sessionProvider the test can flip between users and null, standing in for the
/// AuthController without touching Supabase.
class _FakeSession {
  _FakeSession(this._value);

  NivoraSession? _value;
  final _listeners = <void Function()>[];

  NivoraSession? session(Ref ref) {
    void listener() => ref.invalidateSelf();
    _listeners.add(listener);
    ref.onDispose(() => _listeners.remove(listener));
    return _value;
  }

  void set(NivoraSession? next) {
    _value = next;
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}
