// SELF SIGN-UP AND ONBOARDING (1.3.0) — docs/self-signup-api.md, docs/self-signup-onboarding-spec.md.
//
// Every widget here is pumped on a 360 x 640 dp phone at text scale 1.4, so an overflow anywhere
// in the round fails the test that drew it. No network: the server is a fake SignupApi and the
// auth controller is a stub that records what it was asked.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/auth_endpoint.dart';
import 'package:mobile/core/auth/google_id_token.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/auth/social_sign_in.dart';
import 'package:mobile/core/router/routes.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/device/signup_device.dart';
import 'package:mobile/data/media/avatar_image.dart';
import 'package:mobile/data/media/jpeg_encoder.dart';
import 'package:mobile/data/models/models.dart' show Hostel;
import 'package:mobile/data/models/signup.dart';
import 'package:mobile/data/repositories/signup_repository.dart';
import 'package:mobile/features/auth/login_screen.dart';
import 'package:mobile/features/auth/social_buttons.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/signup/create_account_screen.dart';
import 'package:mobile/features/signup/owner/book_demo_screen.dart';
import 'package:mobile/features/signup/persona_store.dart';
import 'package:mobile/features/signup/role_picker_screen.dart';
import 'package:mobile/features/signup/signup_gate.dart';
import 'package:mobile/features/signup/tenant/tenant_details_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── fakes ─────────────────────────────────────────────────────────────────────────────────────

class _StubAuth extends AuthController {
  _StubAuth({this.phase = const AuthSignedOut(), this.googleAttempt = const SocialAttempt(null)});

  final AuthPhase phase;
  SocialAttempt googleAttempt;
  final personas = <SignupPersona?>[];
  int reloads = 0;

  @override
  Future<AuthPhase> build() async => phase;

  @override
  Future<SocialAttempt> continueWithGoogle({bool quietly = false, SignupPersona? persona}) async {
    if (quietly) return const SocialAttempt(null);
    personas.add(persona);
    return googleAttempt;
  }

  @override
  Future<void> reload() async => reloads++;

  @override
  Future<void> signOut() async {}
}

class _Google implements GoogleIdTokenSource {
  @override
  bool get isAvailable => true;
  @override
  Future<GoogleTokenOutcome> request() async => const GoogleTokenCancelled();
  @override
  Future<GoogleTokenOutcome> requestQuietly() async => const GoogleTokenCancelled();
  @override
  Future<void> forget() async {}
}

class _Visible implements SocialCredentialSource {
  @override
  bool get isAvailable => true;
  @override
  Future<SocialCredentialOutcome> request() async => const SocialCredentialCancelled();
}

class _FakeApi implements SignupApi {
  JoinRequest? join;
  List<HostelHit> hits = const [];
  final calls = <String>[];
  Map<String, Object?> lastHostel = const {};
  Object? refuseCreate;

  @override
  Future<MyProfile> myProfile() async => const MyProfile();

  @override
  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? gender,
    DateTime? dateOfBirth,
    String? emergencyName,
    String? emergencyPhone,
  }) async =>
      calls.add('updateProfile:$fullName:$phone');

  @override
  Future<String> uploadAvatar(Uint8List squareJpeg) async {
    calls.add('uploadAvatar:${squareJpeg.length}');
    return 'u/avatar/x.jpg';
  }

  @override
  Future<void> addDocument({required String kind, required Uint8List bytes}) async =>
      calls.add('addDocument:$kind');

  @override
  Future<FirstHostel> createFirstHostel({
    required String name,
    required String propertyType,
    required String genderPolicy,
    required String address,
    required String locality,
    required String city,
    required String pincode,
    required int floors,
    required int rooms,
    required int bedsPerRoom,
    double? latitude,
    double? longitude,
  }) async {
    calls.add('createFirstHostel');
    if (refuseCreate != null) throw refuseCreate!;
    lastHostel = {
      'name': name,
      'type': propertyType,
      'gender': genderPolicy,
      'pincode': pincode,
      'rooms': rooms,
      'lat': latitude,
    };
    return FirstHostel(hostelId: 'h-1', name: name, trialEnd: DateTime(2026, 11, 24));
  }

  @override
  Future<void> bookDemo({
    required String name,
    required String phone,
    required String pgName,
    required String city,
    required String bedBand,
    required DateTime slotKolkata,
  }) async =>
      calls.add('bookDemo');

  @override
  Future<List<HostelHit>> nearbyHostels(double lat, double lng) async {
    calls.add('nearby:$lat,$lng');
    return hits;
  }

  @override
  Future<List<HostelHit>> searchHostels(String query) async {
    calls.add('search:$query');
    return hits;
  }

  @override
  Future<void> requestJoin(String hostelId, {String? message}) async =>
      calls.add('requestJoin:$hostelId');

  @override
  Future<void> cancelJoinRequest() async => calls.add('cancel');

  @override
  Future<JoinRequest?> myJoinRequest() async {
    calls.add('myJoinRequest');
    return join;
  }
}

class _Locator implements CoarseLocator {
  @override
  Future<LocationOutcome> locate({required ExplainFirst explain}) async =>
      const LocationFix(12.97, 77.59);
}

// ── harness ───────────────────────────────────────────────────────────────────────────────────

const _tenant = ApnivaasSession(
  userId: 'u-1',
  role: UserRole.student,
  fullName: 'Test Tenant',
  status: 'active',
  mustChangePassword: false,
  phone: '9876543210',
);

const _owner = ApnivaasSession(
  userId: 'u-2',
  role: UserRole.owner,
  fullName: 'Test Owner',
  status: 'active',
  mustChangePassword: false,
  phone: '9876543210',
);

/// A 360 x 640 dp phone at text scale 1.4.
Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
  required Map<String, Widget> routes,
  String initial = '/',
}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      for (final e in routes.entries) GoRoute(path: e.key, builder: (_, _) => e.value),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: ApnivaasTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// A round provider button, by its screen-reader label.
Finder _social(String label) =>
    find.byWidgetPredicate((w) => w is SocialCircleButton && w.label == label);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  // Centred, not just "visible": a control scrolled flush to the top edge can sit under the
  // page's own padding and miss the tap.
  final context = tester.element(finder);
  if (Scrollable.maybeOf(context) != null) {
    await Scrollable.ensureVisible(context, alignment: 0.5);
  }
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // ═══ wire formats ══════════════════════════════════════════════════════════════════════════
  group('mobile-auth bodies and refusals (docs/self-signup-api.md §1)', () {
    late List<Map<String, Object?>> sent;
    MobileAuthEndpoint endpoint(Object answer) => MobileAuthEndpoint((name, {body}) async {
          sent.add(Map<String, Object?>.from(body! as Map));
          if (answer is FunctionException) throw answer;
          return answer as FunctionResponse;
        });
    setUp(() => sent = []);

    test('Google carries the persona only when one is given', () async {
      await endpoint(const FunctionsHttpException(status: 400))
          .signInWithGoogle(idToken: 't' * 30, nonce: 'n' * 20, persona: 'owner');
      expect(sent.single['persona'], 'owner');
    });

    test('Facebook and Truecaller send exactly the contract fields', () async {
      await endpoint(const FunctionsHttpException(status: 400))
          .signInWithFacebook(accessToken: 'fb-token');
      await endpoint(const FunctionsHttpException(status: 400))
          .signInWithTruecaller(code: 'abc', codeVerifier: 'v' * 43, persona: 'tenant');
      expect(sent[0], {'action': 'facebook', 'accessToken': 'fb-token'});
      expect(sent[1], {
        'action': 'truecaller',
        'code': 'abc',
        'codeVerifier': 'v' * 43,
        'persona': 'tenant',
      });
    });

    test('a refusal keeps its sentence AND its machine code', () async {
      final verdict = await endpoint(const FunctionsHttpException(status: 409, details: {
        'ok': false,
        'error': 'An account already uses this number — sign in with your password',
        'code': 'phone_in_use',
      })).signInWithTruecaller(code: 'abc', codeVerifier: 'v' * 43);
      expect((verdict as AuthRejected).code, 'phone_in_use');
      expect(verdict.message, 'An account already uses this number — sign in with your password');
    });

    test('not configured is an outage with a code, in the contract words', () async {
      final verdict = await endpoint(const FunctionsHttpException(status: 503, details: {
        'ok': false,
        'error': 'Facebook sign-in is not set up yet',
        'code': 'not_configured',
      })).signInWithFacebook(accessToken: 'x');
      expect((verdict as AuthUnavailable).code, MobileAuthEndpoint.codeNotConfigured);
    });
  });

  group('small rules', () {
    test('a synthetic provider address can never receive mail', () {
      expect(isReachableLoginAddress('fb-123@identity.apnivaas.invalid'), isFalse);
      expect(isReachableLoginAddress('tc-9@IDENTITY.apnivaas.invalid'), isFalse);
      expect(isReachableLoginAddress('owner@gmail.com'), isTrue);
    });

    test('storage keys are lowercase UUID v4', () {
      final id = randomUuidV4();
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(randomUuidV4(), isNot(id));
    });

    test('a document is typed by its bytes, never by its name', () {
      expect(documentTypeOf(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]))?.ext, 'jpg');
      expect(documentTypeOf(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0]))?.ext, 'png');
      expect(documentTypeOf(Uint8List.fromList('%PDF-1.7'.codeUnits))?.contentType, 'application/pdf');
      expect(documentTypeOf(Uint8List.fromList('RIFF0000WEBPVP8 '.codeUnits))?.ext, 'webp');
      expect(documentTypeOf(Uint8List.fromList('<html>'.codeUnits)), isNull);
    });

    test('a validation refusal keeps its sentence and names its field', () {
      final f = SignupFailure.from(const PostgrestException(
        message: 'Enter a valid 6-digit pincode.',
        code: 'P0001',
        hint: 'pincode',
      ));
      expect(f.message, 'Enter a valid 6-digit pincode.');
      expect(f.field, 'pincode');
      final limited = SignupFailure.from(const PostgrestException(
        message: 'Too many attempts. Try again tomorrow.',
        code: 'P0001',
        hint: 'Try again in about 30 seconds.',
      ));
      expect(limited.field, isNull, reason: 'a rate-limit hint is not a field');
      expect(
        SignupFailure.from(const PostgrestException(message: 'Not signed in.', code: '42501'))
            .signedOut,
        isTrue,
      );
    });

    test('demo slots are whole Kolkata hours 10–18, at least two hours away', () {
      // 08:00 IST on 1 Nov 2026 is 02:30 UTC.
      final now = kolkataNow(DateTime.utc(2026, 11, 1, 2, 30));
      expect(now.hour, 8);
      final today = demoSlotsFor(DateTime.utc(2026, 11, 1), now);
      expect(today.first.hour, 10);
      expect(today.last.hour, 18);
      // 17:30 IST: nothing left today, so the first bookable day is tomorrow.
      final late = kolkataNow(DateTime.utc(2026, 11, 1, 12, 0));
      expect(demoSlotsFor(DateTime.utc(2026, 11, 1), late), isEmpty);
      final days = demoDaysFrom(late);
      expect(days.first.day, 2);
      expect(days.length, lessThanOrEqualTo(14));
      expect(kolkataIso(DateTime.utc(2026, 11, 2, 15)), '2026-11-02T15:00:00+05:30');
    });

    test('the avatar crop is the centre square, never upscaled, at most 512', () {
      final c = centreSquare(1000, 600);
      expect((c.left, c.top, c.side), (200.0, 0.0, 600.0));
      expect(avatarEdgeFor(600), 512);
      expect(avatarEdgeFor(300), 300);
    });

    test('the JPEG encoder writes a well-formed baseline file at the right size', () {
      const w = 17, h = 9; // not multiples of 8: edge blocks are padded
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        rgba[i * 4] = (i * 7) & 0xff;
        rgba[i * 4 + 1] = (i * 13) & 0xff;
        rgba[i * 4 + 2] = 200;
        rgba[i * 4 + 3] = 255;
      }
      final jpeg = JpegEncoder.encode(rgba, w, h, quality: 80);
      expect(jpeg.sublist(0, 2), [0xFF, 0xD8], reason: 'SOI');
      expect(jpeg.sublist(jpeg.length - 2), [0xFF, 0xD9], reason: 'EOI');
      final sof = _indexOf(jpeg, [0xFF, 0xC0]);
      expect(sof, greaterThan(0));
      expect((jpeg[sof + 5] << 8) | jpeg[sof + 6], h);
      expect((jpeg[sof + 7] << 8) | jpeg[sof + 8], w);
      // Scan data never contains an unstuffed marker before EOI.
      final sos = _indexOf(jpeg, [0xFF, 0xDA]);
      for (var i = sos + 14; i < jpeg.length - 2; i++) {
        if (jpeg[i] == 0xFF) expect(jpeg[i + 1], 0x00, reason: 'byte stuffing at $i');
      }
    });
  });

  // ═══ Flow 1: Who are you? → Create your account ═══════════════════════════════════════════
  group('Who are you? and Create your account', () {
    testWidgets('three cards; Tenant + continue remembers the hint and opens Create your account',
        (tester) async {
      final storage = MemoryPersonaStorage();
      await _pump(tester, initial: startRoute, overrides: [
        personaStorageProvider.overrideWithValue(storage),
        authControllerProvider.overrideWith(() => _StubAuth()),
        googleIdTokenSourceProvider.overrideWithValue(_Google()),
      ], routes: {
        startRoute: const RolePickerScreen(),
        createAccountRoute: const CreateAccountScreen(),
        '/login': const Text('login'),
      });

      expect(find.text('Step 2 of 4'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Tenant'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);

      await _tap(tester, find.text('Tenant'));
      await _tap(tester, find.text('Continue as tenant'));

      expect(storage.value, SignupPersona.tenant);
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('You are signing up as a tenant.'), findsOneWidget);
      expect(_social('Continue with Google'), findsOneWidget);
      // Hidden until their IDs exist.
      expect(_social('Continue with Facebook'), findsNothing);
      expect(_social('Continue with Truecaller'), findsNothing);
    });

    testWidgets('Staff picks the staff persona and goes to Create your account (round 3)',
        (tester) async {
      final storage = MemoryPersonaStorage();
      await _pump(tester, initial: startRoute, overrides: [
        personaStorageProvider.overrideWithValue(storage),
        authControllerProvider.overrideWith(() => _StubAuth()),
      ], routes: {
        startRoute: const RolePickerScreen(),
        createAccountRoute: const CreateAccountScreen(),
        '/login': const Text('login'),
      });
      await _tap(tester, find.text('Staff'));
      await _tap(tester, find.text('Continue as staff'));
      expect(storage.value, SignupPersona.staff);
      expect(find.textContaining('signing up as staff'), findsOneWidget);
      // Staff give no address.
      expect(find.widgetWithText(TextFormField, 'City'), findsNothing);
    });

    testWidgets('Continue with Google sends the persona; success forgets the hint',
        (tester) async {
      final storage = MemoryPersonaStorage()..value = SignupPersona.owner;
      final auth = _StubAuth(googleAttempt: const SocialAttempt(null, signedIn: true));
      await _pump(tester, initial: createAccountRoute, overrides: [
        personaStorageProvider.overrideWithValue(storage),
        authControllerProvider.overrideWith(() => auth),
        googleIdTokenSourceProvider.overrideWithValue(_Google()),
        facebookCredentialSourceProvider.overrideWithValue(_Visible()),
        truecallerCredentialSourceProvider.overrideWithValue(_Visible()),
      ], routes: {
        createAccountRoute: const CreateAccountScreen(),
        startRoute: const Text('start'),
      });

      expect(_social('Continue with Facebook'), findsOneWidget);
      expect(_social('Continue with Truecaller'), findsOneWidget);
      await _tap(tester, _social('Continue with Google'));
      expect(auth.personas, [SignupPersona.owner]);
      expect(storage.value, isNull);
    });

    testWidgets("the server's refusal is shown verbatim", (tester) async {
      final auth = _StubAuth(
        googleAttempt: const SocialAttempt(
          'Staff and administrator accounts sign in with the login they were given, not with Google.',
          code: 'staff_refused',
        ),
      );
      await _pump(tester, initial: createAccountRoute, overrides: [
        personaStorageProvider.overrideWithValue(MemoryPersonaStorage()..value = SignupPersona.tenant),
        authControllerProvider.overrideWith(() => auth),
        googleIdTokenSourceProvider.overrideWithValue(_Google()),
      ], routes: {createAccountRoute: const CreateAccountScreen()});
      await _tap(tester, _social('Continue with Google'));
      expect(find.textContaining('Staff and administrator accounts sign in'), findsOneWidget);
    });

    testWidgets('sign-in: "New here?" opens Who are you?, and so does a no_account refusal',
        (tester) async {
      final auth = _StubAuth(
        googleAttempt: const SocialAttempt('No account yet — create one', code: 'no_account'),
      );
      await _pump(tester, initial: '/login', overrides: [
        authControllerProvider.overrideWith(() => auth),
        googleIdTokenSourceProvider.overrideWithValue(_Google()),
      ], routes: {
        '/login': const LoginScreen(),
        startRoute: const Text('who are you'),
      });
      expect(find.text('New here? Create an account'), findsOneWidget);
      await _tap(tester, _social('Continue with Google'));
      expect(find.text('who are you'), findsOneWidget);
      expect(auth.personas, [null], reason: 'sign-in never sends a persona');
    });
  });

  // ═══ Flow 3: owner onboarding ═════════════════════════════════════════════════════════════
  group('owner with no PG', () {
    testWidgets('PG details → free month → Book a demo → Skip hands back to the home',
        (tester) async {
      final api = _FakeApi();
      final auth = _StubAuth(phase: const AuthSignedIn(_owner));
      await _pump(tester, overrides: [
        sessionProvider.overrideWithValue(_owner),
        authControllerProvider.overrideWith(() => auth),
        myHostelsProvider.overrideWith((ref) async => const <Hostel>[]),
        signupApiProvider.overrideWithValue(api),
        coarseLocatorProvider.overrideWithValue(_Locator()),
      ], routes: {
        '/': const SignupGate(child: Text('owner home')),
      });

      expect(find.text('Tell us about your PG'), findsOneWidget);
      expect(find.text('owner home'), findsNothing);

      await tester.enterText(find.widgetWithText(TextFormField, 'PG name'), 'Green Nest PG');
      await _tap(tester, find.text('Boys'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Full address'), '12, 3rd Cross, HSR');
      await tester.enterText(find.widgetWithText(TextFormField, 'Locality'), 'HSR Layout');
      await tester.enterText(find.widgetWithText(TextFormField, 'City'), 'Bengaluru');
      await tester.enterText(find.widgetWithText(TextFormField, 'Pincode'), '560102');
      await tester.enterText(find.widgetWithText(TextFormField, 'Rooms'), '10');
      await _tap(tester, find.text('Use my current location (optional)'));
      expect(find.text('Map pin added from your location'), findsOneWidget);
      await _tap(tester, find.text('Create my PG'));

      expect(api.lastHostel['name'], 'Green Nest PG');
      expect(api.lastHostel['gender'], 'boys');
      expect(api.lastHostel['lat'], 12.97);
      expect(find.text('Your first month is free'), findsOneWidget);
      expect(find.textContaining('24 November 2026'), findsOneWidget);

      await _tap(tester, find.text('Start my free month'));
      expect(find.text('Book a free demo'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Green Nest PG'), findsOneWidget,
          reason: 'the PG name is prefilled');

      await _tap(tester, find.text('Skip for now'));
      expect(auth.reloads, 1, reason: 'the profile is re-read so the gate can let go');
    });

    testWidgets('a field refusal lands under its field; "already set up" counts as done',
        (tester) async {
      final api = _FakeApi()
        ..refuseCreate = const SignupFailure('Enter a valid 6-digit pincode.', field: 'pincode');
      final auth = _StubAuth(phase: const AuthSignedIn(_owner));
      await _pump(tester, overrides: [
        sessionProvider.overrideWithValue(_owner),
        authControllerProvider.overrideWith(() => auth),
        myHostelsProvider.overrideWith((ref) async => const <Hostel>[]),
        signupApiProvider.overrideWithValue(api),
      ], routes: {
        '/': const SignupGate(child: Text('owner home')),
      });
      await tester.enterText(find.widgetWithText(TextFormField, 'PG name'), 'Green Nest PG');
      await _tap(tester, find.text('Co-ed'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Full address'), '12, 3rd Cross');
      await tester.enterText(find.widgetWithText(TextFormField, 'Locality'), 'HSR');
      await tester.enterText(find.widgetWithText(TextFormField, 'City'), 'Bengaluru');
      await tester.enterText(find.widgetWithText(TextFormField, 'Pincode'), '560102');
      await tester.enterText(find.widgetWithText(TextFormField, 'Rooms'), '4');
      await _tap(tester, find.text('Create my PG'));
      expect(find.text('Enter a valid 6-digit pincode.'), findsOneWidget);

      api.refuseCreate = const SignupFailure('Your PG is already set up.');
      await _tap(tester, find.text('Create my PG'));
      expect(auth.reloads, 1);
    });

    testWidgets('an owner who has a PG goes straight home', (tester) async {
      await _pump(tester, overrides: [
        sessionProvider.overrideWithValue(_owner),
        authControllerProvider.overrideWith(() => _StubAuth()),
        myHostelsProvider.overrideWith((ref) async => [Hostel.fromJson(_hostelRow)]),
      ], routes: {
        '/': const SignupGate(child: Text('owner home')),
      });
      expect(find.text('owner home'), findsOneWidget);
    });
  });

  // ═══ Flow 4: tenant joins a PG ════════════════════════════════════════════════════════════
  group('tenant with no PG', () {
    List<Override> tenantWorld(_FakeApi api, _StubAuth auth) => [
          sessionProvider.overrideWithValue(_tenant),
          authControllerProvider.overrideWith(() => auth),
          signupApiProvider.overrideWithValue(api),
          coarseLocatorProvider.overrideWithValue(_Locator()),
          avatarEncoderProvider.overrideWithValue((b) async => b),
        ];

    testWidgets('details → find → request → waiting → cancel', (tester) async {
      final api = _FakeApi()
        ..hits = const [
          HostelHit(
            hostelId: 'h-9',
            name: 'Kota Stay',
            propertyType: 'hostel',
            genderPolicy: 'girls',
            locality: 'Indiranagar',
            city: 'Bengaluru',
            distanceKm: 2.4,
          ),
        ];
      final auth = _StubAuth(phase: const AuthSignedIn(_tenant));
      await _pump(tester, overrides: tenantWorld(api, auth), routes: {
        '/': const SignupGate(child: Text('tenant home')),
      });
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Your details'), findsOneWidget);
      expect(find.textContaining('masked'), findsWidgets);
      await _tap(tester, find.text('Continue'));
      expect(api.calls, contains('updateProfile:Test Tenant:9876543210'));

      expect(find.text('Find your PG'), findsOneWidget);
      await _tap(tester, find.text('PGs near you'));
      expect(api.calls, contains('nearby:12.97,77.59'));
      expect(find.text('Kota Stay'), findsOneWidget);
      expect(find.text('Hostel · Girls'), findsOneWidget);
      expect(find.text('2.4 km'), findsOneWidget);

      await _tap(tester, find.text('Request to join'));
      await _tap(tester, find.text('Send request'));
      expect(api.calls, contains('requestJoin:h-9'));
      expect(find.text('Waiting for Kota Stay to accept'), findsOneWidget);

      await _tap(tester, find.text('Cancel request'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Cancel request'));
      expect(api.calls, contains('cancel'));
      expect(find.text('Find your PG'), findsOneWidget);
    });

    testWidgets('a pending request opens on the waiting screen', (tester) async {
      final api = _FakeApi()
        ..join = const JoinRequest(
          requestId: 'r-1',
          hostelName: 'Green Nest PG',
          status: JoinStatus.pending,
        );
      await _pump(tester, overrides: tenantWorld(api, _StubAuth()), routes: {
        '/': const SignupGate(child: Text('tenant home')),
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Waiting for Green Nest PG to accept'), findsOneWidget);
    });

    testWidgets('an accepted request re-reads the profile so the home can open', (tester) async {
      final api = _FakeApi()
        ..join = const JoinRequest(
          requestId: 'r-1',
          hostelName: 'Green Nest PG',
          status: JoinStatus.accepted,
        );
      final auth = _StubAuth();
      await _pump(tester, overrides: tenantWorld(api, auth), routes: {
        '/': const SignupGate(child: Text('tenant home')),
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(auth.reloads, 1);
    });

    testWidgets('a resident who belongs to a PG never sees onboarding', (tester) async {
      const housed = ApnivaasSession(
        userId: 'u-3',
        role: UserRole.student,
        fullName: 'Housed',
        status: 'active',
        mustChangePassword: false,
        hostelId: 'h-1',
      );
      await _pump(tester, overrides: [
        sessionProvider.overrideWithValue(housed),
        authControllerProvider.overrideWith(() => _StubAuth()),
      ], routes: {
        '/': const SignupGate(child: Text('tenant home')),
      });
      expect(find.text('tenant home'), findsOneWidget);
    });
  });

  testWidgets('Book a demo stands alone too (the More entry) and fits at 1.4x', (tester) async {
    final api = _FakeApi();
    await _pump(tester, overrides: [
      sessionProvider.overrideWithValue(_owner),
      authControllerProvider.overrideWith(() => _StubAuth()),
      signupApiProvider.overrideWithValue(api),
    ], routes: {
      '/': BookDemoScreen(clock: () => DateTime.utc(2026, 11, 1, 2, 30)),
    });
    expect(find.text('Book a free demo'), findsOneWidget);
    await _tap(tester, find.text('10:00 AM'));
    await _tap(tester, find.text('21–50'));
    await tester.enterText(find.widgetWithText(TextFormField, 'PG name'), 'Green Nest PG');
    await tester.enterText(find.widgetWithText(TextFormField, 'City'), 'Bengaluru');
    await _tap(tester, find.textContaining('Book for'));
    expect(api.calls, contains('bookDemo'));
    expect(find.text('Demo booked'), findsOneWidget);
  });
}

int _indexOf(List<int> bytes, List<int> sig) {
  for (var i = 0; i + sig.length <= bytes.length; i++) {
    var ok = true;
    for (var j = 0; j < sig.length; j++) {
      if (bytes[i + j] != sig[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}

const _hostelRow = <String, dynamic>{
  'id': 'h-1',
  'name': 'Green Nest PG',
  'owner_user_id': 'u-2',
  'total_floors': 1,
  'total_rooms': 4,
  'beds_per_room_default': 2,
  'created_at': '2026-10-01T00:00:00Z',
  'updated_at': '2026-10-01T00:00:00Z',
};
