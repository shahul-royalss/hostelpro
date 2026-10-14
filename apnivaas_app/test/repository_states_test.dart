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
import 'package:mobile/data/repositories/repository.dart';
import 'package:mobile/data/repositories/room_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_session.dart';

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

/// The same client, HOLDING A LIVE SESSION.
///
/// ═══ WHY EVERY REFUSAL TEST BELOW NOW HAS TO ASK FOR THIS ═══
/// A [SupabaseClient] with no session does not fail to make requests — it makes them under the
/// ANON KEY (supabase AuthHttpClient, and see core/auth/session_standing.dart for the incident).
/// So a bare stub client was, all along, the "signed out" case, and these tests were asserting
/// that a gated RPC refuses an anonymous caller. It does. That was never the interesting claim.
///
/// The claim is that a gated RPC returning nothing TO A REAL, LIVE SESSION is a refusal about
/// that caller's role — and it can only be made by a client that is holding one.
Future<SupabaseClient> _answeringSignedIn(List<Map<String, Object?>> rows) async {
  final client = _answering(rows);
  await installLiveSession(client);
  return client;
}

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
      //
      // SIGNED IN, deliberately: this is the arm where blaming the caller's ROLE is the honest
      // reading, and it is honest only because the credential that asked was alive. The two
      // arms where it is not are the next two tests.
      final client = await _answeringSignedIn(const []);
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
      final client = await _answeringSignedIn([_saRow()]);
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
      // produces a row, so zero rows is about the caller, never about the hostel — provided the
      // caller was somebody. Signed in, for the reason on [_answeringSignedIn].
      final client = await _answeringSignedIn(const []);
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
      final client = await _answeringSignedIn([
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
      final client = await _answeringSignedIn(const []);
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
      final client = await _answeringSignedIn([_bedRow(1), _bedRow(2)]);
      addTearDown(client.dispose);

      final beds = await RoomRepository(client).bedsInRoom('r1');
      expect(beds.map((b) => b.bedNumber), [1, 2]);
    });

    test('EMPTY is still available where empty is a real answer', () async {
      // The rule is not "no list may ever be empty". A hostel with every bed taken genuinely
      // has no free beds, and that must keep drawing the empty state rather than a failure.
      final client = await _answeringSignedIn(const []);
      addTearDown(client.dispose);

      expect(await RoomRepository(client).freeBeds('h1'), isEmpty);
      expect(await RoomRepository(client).rooms('h1'), isEmpty);
    });
  });

  group('the helpers name what zero rows meant', () {
    // EVERY CASE BELOW SAYS WHICH CREDENTIAL ASKED. `standing` became required on 2026-09-01,
    // and these assertions are the reason it had to be: each one is a claim about the CALLER,
    // and a claim about the caller may only be made when the token that asked was one this
    // client could still vouch for. SessionStanding.live is what these tests always silently
    // assumed; saying it out loud is what makes the group below possible.
    test('a refusal and an absence are different failures', () {
      expect(
        () => rpcRowOrRefusal(const [], 'rpc_sa_dashboard',
            refusal: 'staff only', standing: SessionStanding.live),
        throwsA(isA<AccessDeniedFailure>()),
      );
      expect(
        () => rpcRowOrMissing(const [], 'st_hostel_contacts',
            missing: 'no hostel', standing: SessionStanding.live),
        throwsA(isA<NotFoundFailure>()),
      );
      expect(
        () => rowsOrMissing(const [],
            missing: 'not yours',
            why: 'schema guarantees a row',
            standing: SessionStanding.live),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('a row present is handed straight back', () {
      const Map<String, dynamic> row = {'total_hostels': 1};
      expect(
        rpcRowOrRefusal(const [row], 'rpc_sa_dashboard',
            refusal: 'x', standing: SessionStanding.live),
        row,
      );
      expect(
        rpcRowOrMissing(const [row], 'st_hostel_contacts',
            missing: 'x', standing: SessionStanding.live),
        row,
      );
      expect(
        rowsOrMissing(const [row], missing: 'x', why: 'y', standing: SessionStanding.live),
        const [row],
      );
    });

    test('a shape disagreement is still a shape disagreement, not a refusal', () {
      // A scalar where an array belongs means the function changed under us. That is a bug
      // report, not a permissions conversation.
      expect(
        () => rpcRowOrRefusal(42, 'rpc_sa_dashboard',
            refusal: 'x', standing: SessionStanding.live),
        throwsA(isA<RowShapeError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // A DEAD TOKEN PRODUCES THE SAME EMPTINESS AS THE WRONG ROLE, AND MUST NOT PRODUCE THE SAME
  // SENTENCE.
  //
  // This is the group the `standing` parameter exists for. When a session dies, supabase's
  // AuthHttpClient fills the Authorization header with the ANON key rather than sending none
  // (auth_http_client.dart:24-32), so `rpc_sa_dashboard()` -- which ends in
  // `where app.is_super_admin()` -- answers zero rows exactly as it would a genuine impostor.
  // The console then told its own super admin to sign in as the super admin. The bytes on the
  // wire cannot tell those two apart; only the credential this client was holding can.
  // ---------------------------------------------------------------------------
  group('zero rows is never a verdict on the person when the token was not live', () {
    test('no session at all: signed out, not access denied', () {
      expect(
        () => rpcRowOrRefusal(const [], 'rpc_sa_dashboard',
            refusal: 'This console is for the Super Admin account.',
            standing: SessionStanding.none),
        throwsA(
          isA<SignedOutFailure>()
              .having((f) => f.needsSignIn, 'needsSignIn', isTrue)
              .having((f) => f.isRefusal, 'isRefusal', isFalse)
              .having((f) => f.technical, 'technical', contains('anon key')),
        ),
      );
    });

    test('expired session: the sign-in expired, not the account', () {
      expect(
        () => rpcRowOrRefusal(const [], 'rpc_sa_dashboard',
            refusal: 'This console is for the Super Admin account.',
            standing: SessionStanding.expired),
        throwsA(
          isA<SessionExpiredFailure>()
              .having((f) => f.needsSignIn, 'needsSignIn', isTrue)
              .having((f) => f.isRefusal, 'isRefusal', isFalse)
              .having((f) => f.isRetryable, 'isRetryable', isFalse),
        ),
      );
    });

    test('an absence is also never blamed on a resident whose token died', () {
      // The student-facing shape of the same bug: "ask your warden to check your registration"
      // is a real errand for a real person, and a dead token must not send anybody on it.
      expect(
        () => rpcRowOrMissing(const [], 'st_hostel_contacts',
            missing: 'Ask your warden to check your registration.',
            standing: SessionStanding.expired),
        throwsA(isA<SessionExpiredFailure>()),
      );
      expect(
        () => rowsOrMissing(const [],
            missing: 'That room is not one this account can open.',
            why: 'rooms_capacity_sync guarantees a bed per unit of capacity',
            standing: SessionStanding.none),
        throwsA(isA<SignedOutFailure>()),
      );
    });

    test('a live token still gets the honest refusal -- the fix did not blunt it', () {
      // The failure mode of a change like this is over-correcting into "never say no". A real
      // impostor on a real session must still be told, or the console has stopped meaning
      // anything.
      expect(
        () => rpcRowOrRefusal(const [], 'rpc_sa_dashboard',
            refusal: 'This console is for the Super Admin account.',
            standing: SessionStanding.live),
        throwsA(
          isA<AccessDeniedFailure>()
              .having((f) => f.isRefusal, 'isRefusal', isTrue)
              .having((f) => f.needsSignIn, 'needsSignIn', isFalse),
        ),
      );
    });
  });

  // WHAT USED TO BE HERE. A group called "the settlement watch has two endings and they are
  // different signals" drove `settlementUpdates()` — the loop that polled `payment_intents`
  // after a Razorpay checkout closed, and whose two endings were "the server reached a verdict"
  // and "we stopped waiting and genuinely do not know whether the money left your account".
  // Online payment is out of v1 (rent is handed over at the warden's desk), that loop went with
  // the checkout, and its tests went with it rather than being kept green against dead code.
  //
  // The property those tests were protecting has NOT gone anywhere: an outcome nobody knows is
  // not a failure, and must never be offered a "try again" that could take money twice. It is
  // held down by [SideEffect] and by `AppFailure.isRetryable`, which the group below covers.

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
