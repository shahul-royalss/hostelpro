// EVERY DATA READ HAS A DEADLINE, AND A READ THAT REACHES IT BECOMES A FAILED STATE.
//
// The defect these tests were written against did not look like a bug from the outside. When
// the backend wedged for a day, nothing crashed and nothing reported an error: Dart's HTTP
// client waits indefinitely on a socket that was accepted and never answered, so every screen
// sat on its skeleton for minutes and the app kept rendering it, frame after frame, with no way
// out. LOADING, EMPTY, FAILED and REFUSED collapse to one whenever a read is allowed to take
// forever, because FAILED can only be reached by a call that agrees to stop.
//
// So each test below is a pair, the same way the rest of this suite is: the deadline fires AND
// the thing it produces is the right kind of failure, with the right sentence, offering the
// right button. A deadline that fired and then said "no connection" under a working connection
// would pass a weaker test and still send the user to reboot their router.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/repositories/room_repository.dart';
import 'package:mobile/features/student/widgets/common.dart';
import 'package:mobile/features/warden/widgets/warden_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A body that behaves exactly like the wedged server did: it accepts the call and never
/// answers. Not a delay — a delay would eventually finish and prove nothing.
Future<T> _neverAnswers<T>() => Completer<T>().future;

/// A transport with the same manners, for the tests that go through the real PostgREST client.
SupabaseClient _silentServer() => SupabaseClient(
      'https://stub.supabase.co',
      'anon-key',
      httpClient: MockClient((_) => _neverAnswers<http.Response>()),
    );

void main() {
  group('a read that is never answered gives up', () {
    test('the deadline fires instead of loading forever', () async {
      // Overriding the deadline is how this runs in milliseconds instead of twelve seconds.
      // What is under test is that the deadline EXISTS and is honoured, not its exact size.
      await expectLater(
        guard(_neverAnswers<int>, deadline: const Duration(milliseconds: 40)),
        throwsA(isA<AppFailure>()),
      );
    });

    test('and the same call answered in time still returns its value', () async {
      // The other half of the pair. Without it, "throws every time" would pass the test above,
      // and a deadline that fires on healthy traffic is a worse bug than no deadline at all.
      expect(await guard(() async => 7), 7);
    });

    test('the failure is a silent SERVER, not a dead connection', () async {
      // The distinction the outage turned on. Both of these are "we have no data", and the two
      // remedies do not overlap: one is "reconnect", the other is "wait, the fault is ours".
      final silent = await guard(
        _neverAnswers<int>,
        deadline: const Duration(milliseconds: 40),
      ).then<AppFailure?>((_) => null, onError: (Object e) => e as AppFailure);
      final offline = AppFailure.from(
        Exception('SocketException: Failed host lookup: stub.supabase.co'),
      );

      expect(silent, isA<ServerFailure>());
      expect(offline, isA<OfflineFailure>());
      expect(silent!.message, isNot(offline.message));

      // The wording each one is allowed to use, stated as the thing a reader would act on.
      expect(silent.message.toLowerCase(), contains('not responding'));
      expect(silent.message.toLowerCase(), contains('connection is fine'));
      expect(offline.message.toLowerCase(), contains('check your connection'));
    });

    test('a read that timed out is retryable, because asking twice costs nothing', () async {
      final failure = await guard(
        _neverAnswers<int>,
        deadline: const Duration(milliseconds: 40),
      ).then<AppFailure?>((_) => null, onError: (Object e) => e as AppFailure);

      expect(failure!.isRetryable, isTrue);
      expect(failure.outcomeIsUnknown, isFalse, reason: 'a read changes nothing');
      expect(failure.isRefusal, isFalse, reason: 'nobody said no; nobody said anything');
    });
  });

  group('a WRITE that is never answered is not reported as a failure', () {
    Future<AppFailure> timedOutWrite() => guardWrite(
          _neverAnswers<int>,
          unresolved: 'Open this resident\'s payments before entering it again.',
          deadline: const Duration(milliseconds: 40),
        ).then<AppFailure>(
          (_) => throw StateError('the deadline did not fire'),
          onError: (Object e) => e as AppFailure,
        );

    test('the outcome is unknown, and the sentence says so out loud', () async {
      final failure = await timedOutWrite();

      // Giving up on the answer does not cancel the request. The row may be committing at the
      // instant the deadline passes, so "that did not work" is a claim this app cannot make.
      expect(failure.outcomeIsUnknown, isTrue);
      expect(failure.message, contains('nobody can say yet whether it went through'));
      expect(failure.message.toLowerCase(), isNot(contains('did not work')));
      expect(failure.message.toLowerCase(), isNot(contains('failed')));
    });

    test('no screen may offer a plain retry, because the retry is the harm', () async {
      final failure = await timedOutWrite();

      // Every error card in this app draws its Try again from isRetryable. Under a write whose
      // outcome nobody knows, that button is a second payment.
      expect(failure.isRetryable, isFalse);
    });

    test('it carries the advice of whoever knew what was being written', () async {
      final failure = await timedOutWrite();

      // A generic "check before doing it again" is useless to someone holding cash. The
      // repository that made the call is the only place that knows where to look.
      expect(failure.message, contains('Open this resident\'s payments'));
    });

    test('a read and a write that time out identically are told apart', () async {
      final read = await guard(
        _neverAnswers<int>,
        deadline: const Duration(milliseconds: 40),
      ).then<AppFailure?>((_) => null, onError: (Object e) => e as AppFailure);
      final write = await timedOutWrite();

      // Same exception, same transport, same twelve seconds of silence — opposite messages,
      // because only the call site knows whether anything could have changed.
      expect(read!.outcomeIsUnknown, isFalse);
      expect(write.outcomeIsUnknown, isTrue);
      expect(read.isRetryable, isTrue);
      expect(write.isRetryable, isFalse);
    });
  });

  group('the deadline is wired into the repositories, not just available to them', () {
    test('a real read through the real client stops at dataDeadline', () {
      // Through SupabaseClient and the real PostgREST request builder, so this proves the
      // wiring rather than proving that guard() was called in the test.
      //
      // FakeAsync, because the honest deadline is twelve seconds and a suite that waits them
      // out is a suite nobody runs.
      FakeAsync().run((async) {
        final client = _silentServer();
        Object? caught;
        var settled = false;
        unawaited(() async {
          try {
            await RoomRepository(client).rooms('h1');
          } catch (error) {
            caught = error;
          }
          settled = true;
        }());

        async.elapse(dataDeadline - const Duration(seconds: 1));
        expect(settled, isFalse, reason: 'it must wait the whole deadline out first');

        async.elapse(const Duration(seconds: 2));
        expect(caught, isA<ServerFailure>());
        expect((caught! as AppFailure).technical, contains('client deadline'));

        client.dispose();
      });
    });

    test('dataDeadline is far enough outside a healthy round trip to mean something', () {
      // Measured against the live project from the build machine on 2026-08-31: 0.77s cold
      // (DNS + TCP + TLS + request) and 0.30-0.36s warm. A deadline inside an order of
      // magnitude of that fires on ordinary bad luck and trains everyone to ignore it.
      expect(dataDeadline.inMilliseconds, greaterThanOrEqualTo(10 * 770));
      // And short enough that the person is still looking at the screen when it gives up.
      expect(dataDeadline, lessThanOrEqualTo(const Duration(seconds: 20)));
    });
  });

  group('a timed-out read renders as FAILED, never as empty', () {
    // The point of the whole exercise: the failure has to reach a screen as an error card with
    // a way forward. An empty list would say "you have no rooms", which is a different and
    // completely false sentence.

    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: child))),
        );

    /// What a read hitting the deadline actually produces, built the same way guard builds it.
    final readTimeout = AppFailure.timedOut(
      TimeoutException('no answer', dataDeadline),
      sideEffect: SideEffect.none,
    );

    testWidgets('the resident is told the server is quiet, not that their wifi is', (
      tester,
    ) async {
      await pump(tester, ErrorNote(error: readTimeout, onRetry: () {}));

      // The retry is real here: asking again is free and may well work.
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);

      // And the copy must not send them to their router. This is the exact confusion the
      // OfflineFailure classification used to cause, so it is asserted rather than trusted.
      final words = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ')
          .toLowerCase();
      expect(words, isNot(contains('wi-fi')));
      expect(words, isNot(contains('mobile data')));
      expect(words, contains('did not answer'));
    });

    testWidgets('a dead connection still says so — the pair that keeps the test honest', (
      tester,
    ) async {
      await pump(
        tester,
        ErrorNote(error: const OfflineFailure('no route to host'), onRetry: () {}),
      );

      final words = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ')
          .toLowerCase();
      expect(words, contains('wi-fi'));
    });

    testWidgets('a warden sees the timed-out payment in the data layer own words', (
      tester,
    ) async {
      // FailureState prints failure.message verbatim, so this is the sentence the person at the
      // desk actually reads when wd_record_payment stopped answering.
      final writeTimeout = AppFailure.timedOut(
        TimeoutException('no answer', dataDeadline),
        sideEffect: SideEffect.unknown,
        unresolved: 'Open this resident\'s payments for that month before entering it again.',
      );

      await pump(tester, FailureState(error: writeTimeout, onRetry: () {}));

      expect(find.textContaining('nobody can say yet'), findsOneWidget);
      expect(find.textContaining('before entering it again'), findsOneWidget);
      // The retry would be a second credit against the same month.
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
    });
  });
}
