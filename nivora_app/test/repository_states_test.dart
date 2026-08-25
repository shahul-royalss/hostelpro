// LOADING, EMPTY, FAILED and REFUSED are four different facts, and the data layer is where
// they get collapsed into one.
//
// Every test here is a pair. One half shows the good answer still arriving; the other shows
// the bad answer arriving as ITSELF rather than as a blank. That pairing is the point: a test
// that only pins the happy path proves nothing about a defect whose whole nature is that the
// unhappy path looks happy. `flutter analyze` cannot see any of this — a `null` that means
// three things is perfectly well typed — so this file is the only gate it has.
//
// The repository tests run against a stubbed transport rather than a stubbed repository. That
// costs a few lines and buys the thing that matters: the real method, the real PostgREST
// decoding, and the exact bytes Postgres would have sent. A fake repository would only prove
// that the fake was written to agree with the test.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/repositories/dashboard_repository.dart';
import 'package:mobile/data/repositories/hostel_repository.dart';
import 'package:mobile/data/repositories/payment_repository.dart';
import 'package:mobile/data/repositories/repository.dart';
import 'package:mobile/data/repositories/room_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// A SUPABASE CLIENT THAT ANSWERS WITH WHATEVER POSTGREST WOULD HAVE SENT
// ─────────────────────────────────────────────────────────────────────────────

/// A client whose every request is answered with [rows], encoded exactly as PostgREST encodes a
/// `returns table (...)` function or a `select`: a JSON array, empty or not.
SupabaseClient _answering(List<Map<String, Object?>> rows) => SupabaseClient(
      'https://stub.supabase.co',
      'anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(rows),
          200,
          // postgrest reads response.request back off the response; without this it NPEs long
          // before reaching any of our code.
          request: request,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

/// The one row rpc_hostel_stats always produces. Every column of the `returns table`, because
/// HostelStats.fromJson refuses to guess at a missing one.
Map<String, Object?> _statsRow({int totalBeds = 24, String state = 'active'}) => {
      'total_beds': totalBeds,
      'occupied_beds': 19,
      'active_students': 19,
      'open_complaints': 2,
      'fees_collected': 133000,
      'fees_pending': 21000,
      'students_paid': 16,
      'students_unpaid': 3,
      'pending_leaves': 1,
      'visitors_today': 4,
      'pending_tasks': 5,
      'revenue_today': 7000,
      'expenses_today': 1200,
      'revenue_month': 133000,
      'expenses_month': 41000,
      'subscription_days_left': 42,
      'subscription_state': state,
    };

Map<String, Object?> _saRow() => {
      'total_hostels': 12,
      'total_owners': 9,
      'total_students': 418,
      'active_subs': 9,
      'expiring_subs': 2,
      'expired_subs': 1,
      'monthly_subscription_revenue': 184000,
    };

Map<String, Object?> _bedRow(int number) => {
      'id': 'bed-$number',
      'hostel_id': 'h1',
      'room_id': 'r1',
      'bed_number': number,
      'status': 'free',
      'student_id': null,
      'created_at': '2026-08-24T10:00:00+00:00',
      'updated_at': '2026-08-24T10:00:00+00:00',
    };

void main() {
  group('zero rows from a gated RPC is a refusal, not an empty platform', () {
    test('rpc_sa_dashboard answering with no rows refuses instead of returning null', () async {
      // `where app.is_super_admin()` answers everyone else with zero rows rather than a 403.
      // Returned as null, that is a platform with no hostels, no owners and no residents —
      // shown to the one person whose job is to notice when that is true.
      final client = _answering(const []);
      addTearDown(client.dispose);

      await expectLater(
        DashboardRepository(client).superAdminStats(),
        throwsA(
          isA<AccessDeniedFailure>()
              .having((f) => f.isRefusal, 'isRefusal', isTrue)
              .having((f) => f.isRetryable, 'isRetryable', isFalse)
              .having((f) => f.isAbsence, 'isAbsence', isFalse)
              .having((f) => f.technical, 'technical', contains('rpc_sa_dashboard')),
        ),
      );
    });

    test('a super admin still gets the figures', () async {
      // The other half of the pair. Without it, "throws every time" would pass the test above.
      final client = _answering([_saRow()]);
      addTearDown(client.dispose);

      final stats = await DashboardRepository(client).superAdminStats();
      expect(stats.totalHostels, 12);
      expect(stats.totalStudents, 418);
    });

    test('the refusal is not retryable, so no screen can offer a Try again that works', () {
      // A refusal that reports itself retryable is how an unreachable button gets drawn.
      const refusal = AccessDeniedFailure('staff only');
      expect(refusal.isRetryable, isFalse);
      expect(const OfflineFailure('no signal').isRetryable, isTrue);
    });
  });

  group('hostel stats have no empty answer to give', () {
    test('zero rows is a failure, not a dashboard of dashes', () async {
      // rpc_hostel_stats selects scalar subqueries with no FROM clause, so Postgres yields
      // exactly one row for every argument. Zero rows means the deployed function is not the
      // one this client was built against — which is a fault, and has to look like one.
      final client = _answering(const []);
      addTearDown(client.dispose);

      await expectLater(
        DashboardRepository(client).hostelStats(hostelId: 'h1'),
        throwsA(
          isA<AppFailure>()
              .having((f) => f.technical, 'technical', contains('rpc_hostel_stats')),
        ),
      );
    });

    test('one row is read as the figures it is', () async {
      final client = _answering([_statsRow()]);
      addTearDown(client.dispose);

      final stats = await DashboardRepository(client).hostelStats(hostelId: 'h1');
      expect(stats.totalBeds, 24);
      expect(stats.occupiedBeds, 19);
      expect(stats.subscriptionState, SubscriptionState.active);
    });
  });

  group('a contact card that is not there is not a contact card that is blank', () {
    test('st_hostel_contacts with no rows says the account has no hostel', () async {
      // The function's only filter is the caller's own hostel. A hostel that resolves always
      // produces a row, so zero rows is about the caller, never about the hostel.
      final client = _answering(const []);
      addTearDown(client.dispose);

      await expectLater(
        HostelRepository(client).contacts(),
        throwsA(
          isA<NotFoundFailure>()
              .having((f) => f.isAbsence, 'isAbsence', isTrue)
              .having((f) => f.isRefusal, 'isRefusal', isFalse)
              // The screen used to say "pull down to try again". Pulling down cannot conjure a
              // hostel assignment, and an unreachable recovery is worse than none.
              .having((f) => f.isRetryable, 'isRetryable', isFalse)
              .having((f) => f.message, 'message', contains('warden')),
        ),
      );
    });

    test('a resident with a hostel gets the card', () async {
      final client = _answering([
        {
          'hostel_name': 'Sunrise PG',
          'address': '12 Residency Road',
          'rules': null,
          'warden_name': 'Meera Nair',
          'warden_phone': '9000000002',
          'manager_name': null,
          'manager_phone': null,
          'owner_name': 'R Sharma',
        }
      ]);
      addTearDown(client.dispose);

      final card = await HostelRepository(client).contacts();
      expect(card.hostelName, 'Sunrise PG');
      expect(card.wardenPhone, '9000000002');
    });
  });

  group('a room you cannot open is not a room with no beds', () {
    test('no bed rows means the room is out of reach, not unfurnished', () async {
      // rooms.capacity is `check (capacity between 1 and 12)` and app.rooms_capacity_sync
      // creates a bed per unit of it, so a room with no beds cannot exist. An empty list was
      // drawn as "This room has no beds" — a confident sentence about someone else's room.
      final client = _answering(const []);
      addTearDown(client.dispose);

      await expectLater(
        RoomRepository(client).bedsInRoom('someone-elses-room'),
        throwsA(
          isA<NotFoundFailure>()
              .having((f) => f.isAbsence, 'isAbsence', isTrue)
              .having((f) => f.isRetryable, 'isRetryable', isFalse)
              .having((f) => f.technical, 'technical', contains('rooms_capacity_sync')),
        ),
      );
    });

    test('a room the caller can open still lists its beds', () async {
      final client = _answering([_bedRow(1), _bedRow(2)]);
      addTearDown(client.dispose);

      final beds = await RoomRepository(client).bedsInRoom('r1');
      expect(beds.map((b) => b.bedNumber), [1, 2]);
    });

    test('EMPTY is still available where empty is a real answer', () async {
      // The rule is not "no list may ever be empty". A hostel with every bed taken genuinely
      // has no free beds, and that must keep drawing the empty state rather than a failure.
      final client = _answering(const []);
      addTearDown(client.dispose);

      expect(await RoomRepository(client).freeBeds('h1'), isEmpty);
      expect(await RoomRepository(client).rooms('h1'), isEmpty);
    });
  });

  group('the helpers name what zero rows meant', () {
    test('a refusal and an absence are different failures', () {
      expect(
        () => rpcRowOrRefusal(const [], 'rpc_sa_dashboard', refusal: 'staff only'),
        throwsA(isA<AccessDeniedFailure>()),
      );
      expect(
        () => rpcRowOrMissing(const [], 'st_hostel_contacts', missing: 'no hostel'),
        throwsA(isA<NotFoundFailure>()),
      );
      expect(
        () => rowsOrMissing(const [], missing: 'not yours', why: 'schema guarantees a row'),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('a row present is handed straight back', () {
      const Map<String, dynamic> row = {'total_hostels': 1};
      expect(rpcRowOrRefusal(const [row], 'rpc_sa_dashboard', refusal: 'x'), row);
      expect(rpcRowOrMissing(const [row], 'st_hostel_contacts', missing: 'x'), row);
      expect(rowsOrMissing(const [row], missing: 'x', why: 'y'), const [row]);
    });

    test('a shape disagreement is still a shape disagreement, not a refusal', () {
      // A scalar where an array belongs means the function changed under us. That is a bug
      // report, not a permissions conversation.
      expect(
        () => rpcRowOrRefusal(42, 'rpc_sa_dashboard', refusal: 'x'),
        throwsA(isA<RowShapeError>()),
      );
    });
  });

  group('the settlement watch has two endings and they are different signals', () {
    test('a credited payment closes the stream normally', () async {
      final result = await _drain(settlementUpdates(
        poll: _polls([_intent(PaymentIntentStatus.captured, credited: true)]),
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 5),
      ));

      expect(result.error, isNull, reason: 'the server gave a verdict; nothing failed');
      expect(result.events.single.isSettled, isTrue);
    });

    test('a failed payment closes the stream normally too', () async {
      final result = await _drain(settlementUpdates(
        poll: _polls([_intent(PaymentIntentStatus.failed)]),
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 5),
      ));

      expect(result.error, isNull);
      expect(result.events.single.status, PaymentIntentStatus.failed);
    });

    test('giving up ends in an error, and it says the outcome is unknown', () async {
      // THE ONE THIS FILE EXISTS FOR. The webhook has not arrived. The money may well have
      // moved. Ending the same way as "the server told us it failed" is how a resident is told
      // nothing happened when nobody knows that.
      final result = await _drain(settlementUpdates(
        poll: _polls([_intent(PaymentIntentStatus.created)]),
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(milliseconds: 30),
      ));

      expect(result.events.single.status, PaymentIntentStatus.created);
      expect(result.error, isA<AppFailure>());
      final failure = result.error! as AppFailure;
      expect(failure.outcomeIsUnknown, isTrue);
      expect(failure.sideEffect, SideEffect.unknown);
      expect(failure.message, contains('payment history'));
    });

    test('a verdict and a give-up cannot be told apart by luck', () async {
      // Both used to close the stream identically. The listener could only guess from whatever
      // state it happened to be in.
      final verdict = await _drain(settlementUpdates(
        poll: _polls([_intent(PaymentIntentStatus.failed)]),
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 5),
      ));
      final gaveUp = await _drain(settlementUpdates(
        poll: _polls([_intent(PaymentIntentStatus.created)]),
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(milliseconds: 30),
      ));

      expect(verdict.error, isNull);
      expect(gaveUp.error, isNotNull);
      expect(verdict.events.single.status, isNot(gaveUp.events.single.status));
    });

    test('never reaching the server reads differently from reaching it', () async {
      // "We could not ask" and "we asked and it had not heard yet" want different sentences,
      // and only one of them is worth checking your connection over.
      final unreachable = await _drain(settlementUpdates(
        poll: () async {
          throw const OfflineFailure('no signal');
        },
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(milliseconds: 30),
      ));
      final noVerdictYet = await _drain(settlementUpdates(
        poll: _polls([null]),
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(milliseconds: 30),
      ));

      expect(unreachable.events, isEmpty);
      expect(unreachable.error, isA<OfflineFailure>());
      expect((unreachable.error! as AppFailure).outcomeIsUnknown, isTrue);
      expect((unreachable.error! as AppFailure).message, contains('could not reach'));

      expect(noVerdictYet.error, isA<ServerFailure>());
      expect((noVerdictYet.error! as AppFailure).outcomeIsUnknown, isTrue);
      expect(
        (noVerdictYet.error! as AppFailure).message,
        isNot(contains('could not reach')),
      );
    });

    test('money taken but not credited says exactly that', () async {
      // Razorpay has it; rz_credit_fee has not run. Neither "settled" nor "failed" is true and
      // the resident is owed the actual sentence.
      final result = await _drain(settlementUpdates(
        poll: _polls([_intent(PaymentIntentStatus.captured)]),
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(milliseconds: 30),
      ));

      expect(result.events.single.isMoneyTaken, isTrue);
      expect(result.events.single.isSettled, isFalse);
      final failure = result.error! as AppFailure;
      expect(failure.outcomeIsUnknown, isTrue);
      expect(failure.message, contains('Razorpay has your payment'));
    });

    test('a dropped poll is not a verdict — the watch keeps waiting', () async {
      // The money's fate is decided on a server whether or not this phone can reach it. One bad
      // poll must not end the wait, and must not end it as a failure either.
      var call = 0;
      final result = await _drain(settlementUpdates(
        poll: () async {
          call++;
          if (call < 3) throw const OfflineFailure('flaky');
          return _intent(PaymentIntentStatus.captured, credited: true);
        },
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 5),
      ));

      expect(result.error, isNull);
      expect(result.events.single.isSettled, isTrue);
      expect(call, greaterThanOrEqualTo(3));
    });
  });

  group('a timeout is not a dead socket', () {
    test('no answer leaves the outcome unknown; a refused socket does not', () {
      // A request that was sent and never answered may have been applied. One that could not
      // resolve a host never reached Postgres at all.
      expect(AppFailure.from(TimeoutException('no answer')).outcomeIsUnknown, isTrue);
      expect(
        AppFailure.from(Exception('SocketException: Failed host lookup')).outcomeIsUnknown,
        isFalse,
      );
    });

    test('every other failure defaults to "nothing happened"', () {
      // The safe default is only safe because the one case that is not safe is explicit.
      expect(const AccessDeniedFailure('x').sideEffect, SideEffect.none);
      expect(const ConflictFailure('x').outcomeIsUnknown, isFalse);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTLEMENT TEST PLUMBING
// ─────────────────────────────────────────────────────────────────────────────

PaymentIntent _intent(PaymentIntentStatus status, {bool credited = false}) => PaymentIntent(
      id: 'pi_1',
      studentId: 's1',
      periodMonth: '2026-08',
      amountPaise: 900000,
      razorpayOrderId: 'order_1',
      status: status,
      capturedAt: status == PaymentIntentStatus.captured
          ? DateTime.utc(2026, 8, 25, 10, 0, 1)
          : null,
      creditedAt: credited ? DateTime.utc(2026, 8, 25, 10, 0, 3) : null,
      createdAt: DateTime.utc(2026, 8, 25, 10),
    );

/// Answers each poll with the next entry, repeating the last one forever after — which is what
/// a real intent row does while everyone waits on a webhook.
Future<PaymentIntent?> Function() _polls(List<PaymentIntent?> answers) {
  var i = 0;
  return () async {
    final answer = answers[i < answers.length ? i : answers.length - 1];
    if (i < answers.length) i++;
    return answer;
  };
}

/// Collects everything a settlement stream said, INCLUDING how it ended.
Future<({List<PaymentIntent> events, Object? error})> _drain(Stream<PaymentIntent> stream) async {
  final events = <PaymentIntent>[];
  Object? error;
  await for (final event in stream.handleError((Object e) {
    error = e;
  })) {
    events.add(event);
  }
  return (events: events, error: error);
}
