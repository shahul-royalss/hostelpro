// Tests for a warden or manager with access to more than one PG, switching between them.
//
// WHAT THESE ARE FOR. The switch is three steps and each fails differently:
//
//  1. THE CONTROL. Drawn only for somebody with two or more PGs. A warden with one PG (every
//     warden until now) sees the PG's name and nothing else, and a failed access list must not
//     cost them even that.
//
//  2. THE REPUBLISH. `staff_switch_hostel` moves `users.hostel_id` on the server; every screen
//     keys off the SESSION's copy of it. Until the session is republished the app shows one PG
//     while RLS answers for another. So the switch goes through `AuthController.republish`,
//     which throws, and a failure there is reported as what it is: the move landed, the reload
//     did not.
//
//  3. THE UNKEYED READS. `hostelContactsProvider` names no PG in its arguments (the function
//     resolves the PG on the server), and the warden's receipt prints the PG name from it. A
//     held answer would put the previous PG's name on a receipt for money taken in this one.
//
// Plus the other-device path: `AuthController.syncActiveHostel`, run on resume, which must
// republish when the PG moved elsewhere and must NOT republish when it did not.
//
// No network in the widget tests: the two RPCs go through `staffHostelAccessProvider`, which is
// an interface for exactly this reason, and the auth controller is a stand-in that publishes
// what the server would have said. The resume tests use a MockClient under the real
// controller, because what they pin is how many profile reads go over the wire.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/data/repositories/staff_access_repository.dart';
import 'package:mobile/features/common/staff_hostel_switcher.dart';
import 'package:mobile/features/shell/staff_profile_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_session.dart';

const _sunriseId = 'h-sunrise';
const _lakeviewId = 'h-lakeview';

const _names = {_sunriseId: 'Sunrise Residency', _lakeviewId: 'Lakeview PG'};

NivoraSession _warden(String? hostelId) => NivoraSession(
  userId: 'u-warden',
  role: UserRole.warden,
  fullName: 'Anil Warden',
  status: 'active',
  mustChangePassword: false,
  hostelId: hostelId,
  email: 'anil@example.com',
);

Hostel _hostel(String id) => Hostel(
  id: id,
  name: _names[id]!,
  ownerUserId: 'owner-1',
  totalFloors: 2,
  totalRooms: 8,
  bedsPerRoomDefault: 2,
  status: HostelStatus.active,
  createdAt: DateTime.utc(2026, 3, 1),
  updatedAt: DateTime.utc(2026, 3, 1),
);

/// The server, as far as these tests need one: which PGs the warden may work in, and which one
/// `users.hostel_id` points at.
class _FakeAccess implements StaffHostelAccess {
  _FakeAccess({required this.allowed, required this.server});

  final List<String> allowed;

  /// `users.hostel_id` on the server.
  String server;

  Object? switchThrows;
  final switched = <String>[];

  @override
  Future<List<StaffHostel>> myHostels() async => [
    for (final id in allowed) StaffHostel(hostelId: id, name: _names[id]!, isActive: id == server),
  ];

  @override
  Future<String> switchTo(String hostelId) async {
    switched.add(hostelId);
    if (switchThrows != null) throw switchThrows!;
    server = hostelId;
    return hostelId;
  }
}

/// The auth controller, standing in for `_resolve`: republishing reads the fake server's
/// `users.hostel_id`, exactly as the real one reads the profile row.
class _StubAuth extends AuthController {
  _StubAuth(this._access, {this.republishThrows});

  final _FakeAccess _access;

  /// Mutable so a test can let the connection come back after a failure.
  Object? republishThrows;
  int republishCalls = 0;
  int syncCalls = 0;

  @override
  Future<AuthPhase> build() async => AuthSignedIn(_warden(_access.server));

  @override
  Future<AuthPhase> republish() async {
    republishCalls++;
    if (republishThrows != null) throw republishThrows!;
    final next = AuthSignedIn(_warden(_access.server));
    state = AsyncData(next);
    return next;
  }

  /// The resume check's contract, against the fake server: republish only when the PG moved.
  @override
  Future<void> syncActiveHostel() async {
    syncCalls++;
    final held = state.value;
    if (held is AuthSignedIn && held.session.hostelId != _access.server) {
      state = AsyncData(AuthSignedIn(_warden(_access.server)));
    }
  }
}

/// Not pumpAndSettle: a spinner in the sheet animates for as long as it is on screen.
Future<void> _tick(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// How many times the contact card was fetched. A fetch reads the fake SERVER's PG, which is
/// what st_hostel_contacts does, so the text only changes if something threw the held answer
/// away and asked again.
int _contactFetches = 0;

Future<({_FakeAccess access, _StubAuth auth})> _pump(
  WidgetTester tester, {
  List<String> allowed = const [_sunriseId, _lakeviewId],
  Object? republishThrows,
  Object? myHostelsError,
  Size size = const Size(1080, 2200),
  double textScale = 1.0,
}) async {
  _contactFetches = 0;
  final access = _FakeAccess(allowed: allowed, server: _sunriseId);
  late _StubAuth auth;

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() {
          auth = _StubAuth(access, republishThrows: republishThrows);
          return auth;
        }),
        staffHostelAccessProvider.overrideWithValue(access),
        if (myHostelsError != null)
          myStaffHostelsProvider.overrideWith((ref) => Future.error(myHostelsError)),
        hostelProvider.overrideWith((ref, id) => _hostel(id)),
        // No watch on the session here, deliberately: the only way this text can change is an
        // invalidation, which is the thing under test.
        hostelContactsProvider.overrideWith((ref) {
          _contactFetches++;
          return HostelContacts(hostelName: _names[access.server]!);
        }),
      ],
      child: MaterialApp(
        theme: NivoraTheme.light(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final hostelId = ref.watch(currentHostelIdProvider);
              final contacts = ref.watch(hostelContactsProvider).value;
              return Column(
                children: [
                  if (hostelId != null) StaffHostelBar(hostelId: hostelId),
                  // What the warden's receipt prints as the PG name.
                  Text('Receipt PG: ${contacts?.hostelName ?? '-'}'),
                  Text('Session PG: ${hostelId ?? '-'}'),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await _tick(tester);
  return (access: access, auth: auth);
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // THE CONTROL
  // ───────────────────────────────────────────────────────────────────────────
  group('the Switch PG control', () {
    testWidgets('is hidden for a warden with one PG, who still sees the PG name', (tester) async {
      await _pump(tester, allowed: const [_sunriseId]);

      expect(find.text('Sunrise Residency'), findsOneWidget);
      expect(find.text('Switch PG'), findsNothing);
    });

    testWidgets('is shown for a warden with two PGs', (tester) async {
      await _pump(tester);

      expect(find.text('Sunrise Residency'), findsOneWidget);
      expect(find.text('Switch PG'), findsOneWidget);
    });

    testWidgets('the name and the control share a 320dp row at the largest text scale', (
      tester,
    ) async {
      // 1.4x is the root's ceiling. The name gives way (it ellipsises); the control does not.
      await _pump(tester, size: const Size(320, 640), textScale: 1.4);

      expect(tester.takeException(), isNull);
      expect(find.text('Switch PG'), findsOneWidget);
      final button = tester.getSize(find.widgetWithText(TextButton, 'Switch PG'));
      expect(button.height, greaterThanOrEqualTo(44));
    });

    testWidgets('a failed access list draws no switcher, and keeps the PG name', (tester) async {
      // The switcher is a convenience for the few with several PGs. An error card on every
      // warden's home because this one read failed would be a regression for all of them.
      await _pump(tester, myHostelsError: const OfflineFailure('offline'));

      expect(find.text('Sunrise Residency'), findsOneWidget, reason: 'from the hostel row');
      expect(find.text('Switch PG'), findsNothing);
      expect(find.text('No connection'), findsNothing);
    });

    testWidgets('the sheet lists every PG with the current one marked', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Switch PG'));
      await _tick(tester);

      expect(find.byType(StaffHostelSheet), findsOneWidget);
      expect(find.text('Lakeview PG'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
      expect(find.textContaining('Your other devices will switch too.'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // SWITCHING
  // ───────────────────────────────────────────────────────────────────────────
  group('switching', () {
    testWidgets('republishes the session with the new PG and refetches the contact card', (
      tester,
    ) async {
      final fakes = await _pump(tester);
      expect(find.text('Receipt PG: Sunrise Residency'), findsOneWidget);
      final fetchesBefore = _contactFetches;

      await tester.tap(find.text('Switch PG'));
      await _tick(tester);
      await tester.tap(find.text('Lakeview PG'));
      await _tick(tester);

      expect(fakes.access.switched, [_lakeviewId]);
      expect(fakes.auth.republishCalls, 1, reason: 'the session must carry the new PG');
      expect(find.text('Session PG: $_lakeviewId'), findsOneWidget);
      // The unkeyed read was thrown away and asked again, so a receipt now names the PG the
      // money was taken in.
      expect(_contactFetches, greaterThan(fetchesBefore));
      expect(find.text('Receipt PG: Lakeview PG'), findsOneWidget);

      expect(find.byType(StaffHostelSheet), findsNothing, reason: 'the sheet closes itself');
      expect(find.text('Now working in Lakeview PG'), findsOneWidget);
    });

    testWidgets('tapping the PG already in use changes nothing', (tester) async {
      final fakes = await _pump(tester);

      await tester.tap(find.text('Switch PG'));
      await _tick(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(StaffHostelSheet),
          matching: find.text('Sunrise Residency'),
        ),
      );
      await _tick(tester);

      expect(fakes.access.switched, isEmpty);
      expect(fakes.auth.republishCalls, 0);
      expect(find.byType(StaffHostelSheet), findsNothing);
    });

    testWidgets('a refused switch shows the server\'s sentence and changes nothing', (
      tester,
    ) async {
      final fakes = await _pump(tester);
      fakes.access.switchThrows = const InvalidInputFailure('You do not have access to that PG.');

      await tester.tap(find.text('Switch PG'));
      await _tick(tester);
      await tester.tap(find.text('Lakeview PG'));
      await _tick(tester);

      expect(find.text('You do not have access to that PG.'), findsOneWidget);
      expect(fakes.auth.republishCalls, 0);
      expect(find.text('Session PG: $_sunriseId'), findsOneWidget);
      expect(find.byType(StaffHostelSheet), findsOneWidget, reason: 'nothing happened; stay');
    });

    testWidgets('a reload that fails AFTER the move says the move landed, not that it failed', (
      tester,
    ) async {
      // AuthController.reload() swallows this. The switch path must not: the server has moved
      // the warden, and the screens are still keyed to the old PG until the session catches up.
      final fakes = await _pump(tester, republishThrows: Exception('socket closed'));

      await tester.tap(find.text('Switch PG'));
      await _tick(tester);
      await tester.tap(find.text('Lakeview PG'));
      await _tick(tester);

      expect(fakes.access.switched, [_lakeviewId]);
      expect(fakes.auth.republishCalls, 1);
      expect(
        find.text(
          'Your PG was changed, but Nivora could not reload it. Check your connection '
          'and tap the PG again.',
        ),
        findsOneWidget,
      );
      expect(find.byType(StaffHostelSheet), findsOneWidget);
    });

    testWidgets('after a failed reload, tapping the PG on screen moves the server back to it', (
      tester,
    ) async {
      // The list was not refetched after the failure, so it still marks Sunrise active while
      // the server has Lakeview. Closing on that tap would leave the screens on one PG and RLS
      // on the other.
      final fakes = await _pump(tester, republishThrows: Exception('socket closed'));

      await tester.tap(find.text('Switch PG'));
      await _tick(tester);
      await tester.tap(find.text('Lakeview PG'));
      await _tick(tester);
      expect(fakes.access.server, _lakeviewId);
      expect(find.text('Session PG: $_sunriseId'), findsOneWidget);

      fakes.auth.republishThrows = null; // the connection is back
      await tester.tap(
        find.descendant(
          of: find.byType(StaffHostelSheet),
          matching: find.text('Sunrise Residency'),
        ),
      );
      await _tick(tester);

      expect(fakes.access.switched, [_lakeviewId, _sunriseId]);
      expect(fakes.access.server, _sunriseId, reason: 'the server agrees with the screens again');
      expect(find.text('Session PG: $_sunriseId'), findsOneWidget);
      expect(find.byType(StaffHostelSheet), findsNothing);
    });

    testWidgets('closing the sheet after a failed reload re-reads the session', (tester) async {
      // Somebody who dismisses the sheet instead of tapping again must not be left with the
      // screens on the old PG while the server has the new one until the next resume.
      final fakes = await _pump(tester, republishThrows: Exception('socket closed'));

      await tester.tap(find.text('Switch PG'));
      await _tick(tester);
      await tester.tap(find.text('Lakeview PG'));
      await _tick(tester);
      expect(find.text('Session PG: $_sunriseId'), findsOneWidget);
      expect(fakes.auth.syncCalls, 0);

      await tester.tapAt(const Offset(20, 20)); // the barrier above the sheet
      await _tick(tester);

      expect(find.byType(StaffHostelSheet), findsNothing);
      expect(fakes.auth.syncCalls, 1);
      expect(find.text('Session PG: $_lakeviewId'), findsOneWidget);
    });

    testWidgets('closing an untouched sheet asks the server nothing', (tester) async {
      final fakes = await _pump(tester);

      await tester.tap(find.text('Switch PG'));
      await _tick(tester);
      await tester.tapAt(const Offset(20, 20));
      await _tick(tester);

      expect(find.byType(StaffHostelSheet), findsNothing);
      expect(fakes.auth.syncCalls, 0);
    });

    testWidgets('a refetched list that disagrees with the session re-reads the session', (
      tester,
    ) async {
      // An owner took Sunrise away while the app was open: the server moved the warden to
      // Lakeview and nothing told this device. A pull to refresh refetches the list, whose
      // is_active now disagrees with the session, and that is the cue to ask again.
      final fakes = await _pump(tester);
      expect(fakes.auth.syncCalls, 0, reason: 'an agreeing list asks nothing');

      fakes.access.server = _lakeviewId;
      final container = ProviderScope.containerOf(tester.element(find.byType(StaffHostelBar)));
      container.invalidate(myStaffHostelsProvider);
      await _tick(tester);

      expect(fakes.auth.syncCalls, 1);
      expect(find.text('Session PG: $_lakeviewId'), findsOneWidget);

      // The rebuilt list agrees with the new session, so it does not ask a second time.
      await _tick(tester);
      expect(fakes.auth.syncCalls, 1);
    });

    testWidgets('a dead session is its own sentence, not "tap it again"', (tester) async {
      await _pump(
        tester,
        republishThrows: const SessionExpiredFailure('Your sign-in expired. Sign in again.'),
      );

      await tester.tap(find.text('Switch PG'));
      await _tick(tester);
      await tester.tap(find.text('Lakeview PG'));
      await _tick(tester);

      expect(find.text('Your sign-in expired. Sign in again.'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // THE PROFILE SHEET
  // ───────────────────────────────────────────────────────────────────────────
  group('the staff profile sheet', () {
    Future<void> openProfile(WidgetTester tester, List<String> allowed) async {
      final access = _FakeAccess(allowed: allowed, server: _sunriseId);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => _StubAuth(access)),
            staffHostelAccessProvider.overrideWithValue(access),
            hostelProvider.overrideWith((ref, id) => _hostel(id)),
          ],
          child: MaterialApp(
            theme: NivoraTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showStaffProfile(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _tick(tester);
    }

    testWidgets('names the PG and offers Switch PG to a warden with two', (tester) async {
      await openProfile(tester, const [_sunriseId, _lakeviewId]);

      expect(find.text('Working in'), findsOneWidget);
      expect(find.text('Sunrise Residency'), findsOneWidget);
      expect(find.text('Switch PG'), findsOneWidget);
    });

    testWidgets('names the PG but offers no switch to a warden with one', (tester) async {
      await openProfile(tester, const [_sunriseId]);

      expect(find.text('Sunrise Residency'), findsOneWidget);
      expect(find.text('Switch PG'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // OTHER DEVICES: the real controller, on resume
  // ───────────────────────────────────────────────────────────────────────────
  group('a switch made on another device', () {
    late List<String> requests;
    late SupabaseClient client;
    late String serverHostel;
    late String role;
    late String status;
    late bool profileFails;

    /// When set, the next profile read answers with the PG as it was when the read ARRIVED, but
    /// only once this completes: a slow read that something else overtakes.
    Completer<void>? holdNextProfile;

    setUp(() async {
      requests = [];
      serverHostel = _sunriseId;
      role = 'manager';
      status = 'active';
      profileFails = false;
      holdNextProfile = null;
      client = SupabaseClient(
        'https://stub.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          requests.add('${request.method} $path');
          if (path.endsWith('/rest/v1/users')) {
            if (profileFails) {
              return http.Response('{"message":"upstream"}', 503, request: request);
            }
            final hostelAtArrival = serverHostel;
            final gate = holdNextProfile;
            holdNextProfile = null;
            if (gate != null) await gate.future;
            return http.Response(
              jsonEncode([
                {
                  'id': 'user-1',
                  'role': role,
                  'full_name': 'Meera Manager',
                  'email': 'meera@example.com',
                  'phone': null,
                  'hostel_id': hostelAtArrival,
                  'status': status,
                  'must_change_password': false,
                  'email_verified_at': '2026-01-01T00:00:00Z',
                },
              ]),
              200,
              request: request,
              headers: const {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200, request: request);
        }),
      );
      addTearDown(client.dispose);
      await installLiveSession(client);
    });

    int profileReads() => requests.where((r) => r == 'GET /rest/v1/users').length;

    Future<ProviderContainer> signedIn() async {
      final container = ProviderContainer(
        overrides: [authControllerProvider.overrideWith(() => _RealAuth(client))],
      );
      addTearDown(container.dispose);
      container.listen(authControllerProvider, (_, _) {});
      await container.read(authControllerProvider.future);
      return container;
    }

    test('resume republishes when the PG moved elsewhere', () async {
      final container = await signedIn();
      expect(container.read(sessionProvider)!.hostelId, _sunriseId);

      serverHostel = _lakeviewId; // switched on the website
      await container.read(authControllerProvider.notifier).syncActiveHostel();

      expect(container.read(sessionProvider)!.hostelId, _lakeviewId);
    });

    test('resume leaves an unchanged session alone, so nothing downstream rebuilds', () async {
      final container = await signedIn();
      final before = container.read(authControllerProvider).value;
      final reads = profileReads();

      await container.read(authControllerProvider.notifier).syncActiveHostel();

      expect(profileReads(), reads + 1, reason: 'it did ask, once');
      expect(
        identical(container.read(authControllerProvider).value, before),
        isTrue,
        reason: 'the same PG must not publish a new session object',
      );
    });

    test('resume costs an owner nothing: only wardens and managers can switch', () async {
      role = 'owner';
      final container = await signedIn();
      final reads = profileReads();

      await container.read(authControllerProvider.notifier).syncActiveHostel();

      expect(profileReads(), reads);
    });

    test('a failed resume check keeps the session it had', () async {
      final container = await signedIn();
      final before = container.read(authControllerProvider).value;
      profileFails = true;

      await container.read(authControllerProvider.notifier).syncActiveHostel();

      expect(identical(container.read(authControllerProvider).value, before), isTrue);
    });

    test('a resume that finds the account deactivated signs out WITH the reason', () async {
      // _resolve signs the deactivated account out itself, and gotrue's signedOut event reaches
      // the controller first with no sentence. The login screen must still say why.
      final container = await signedIn();
      status = 'inactive'; // deactivated by the owner while the phone was in a pocket

      await container.read(authControllerProvider.notifier).syncActiveHostel();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final phase = container.read(authControllerProvider).value;
      expect(phase, isA<AuthSignedOut>());
      expect((phase as AuthSignedOut).message, 'This account has been deactivated.');
    });

    test('a resume answer read before a switch here does not undo the switch', () async {
      // Resume sends its read; the person switches before it comes back; the switch republishes
      // the new PG; THEN the slow resume answer arrives, carrying the PG from before the switch.
      // Publishing it would put the screens back on the old PG while the server has the new one.
      final container = await signedIn();
      final reads = profileReads();
      final gate = Completer<void>();
      holdNextProfile = gate;

      final resume = container.read(authControllerProvider.notifier).syncActiveHostel();
      while (profileReads() == reads) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      serverHostel = _lakeviewId; // staff_switch_hostel, from this device
      await container.read(authControllerProvider.notifier).republish();
      expect(container.read(sessionProvider)!.hostelId, _lakeviewId);

      gate.complete();
      await resume;

      expect(
        container.read(sessionProvider)!.hostelId,
        _lakeviewId,
        reason: 'the stale answer must not overwrite the switch that overtook it',
      );
    });

    test('republish THROWS on a failed read and leaves the published phase alone', () async {
      final container = await signedIn();
      final before = container.read(authControllerProvider).value;
      profileFails = true;

      await expectLater(
        container.read(authControllerProvider.notifier).republish(),
        throwsA(anything),
      );
      expect(identical(container.read(authControllerProvider).value, before), isTrue);
    });
  });
}

/// The real controller, pointed at the MockClient. See [AuthController.clientOverride].
class _RealAuth extends AuthController {
  _RealAuth(this._client);
  final SupabaseClient _client;

  @override
  Future<AuthPhase> build() {
    clientOverride = _client;
    return super.build();
  }
}
