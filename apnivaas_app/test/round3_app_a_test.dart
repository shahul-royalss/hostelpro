// Round 3, app workstream A (docs/round3-spec.md R1, R2, R3, R4, R6, R7).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/auth/app_lock.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/auth_endpoint.dart';
import 'package:mobile/core/auth/google_id_token.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/auth/social_sign_in.dart';
import 'package:mobile/core/router/routes.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/stay.dart';
import 'package:mobile/data/providers.dart' show currentHostelIdProvider;
import 'package:mobile/data/repositories/signup_repository.dart' show SignupFailure;
import 'package:mobile/data/repositories/stay_repository.dart';
import 'package:mobile/features/auth/login_screen.dart';
import 'package:mobile/features/owner/widgets/checkouts_notice.dart';
import 'package:mobile/features/signup/create_account_screen.dart';
import 'package:mobile/features/signup/persona_store.dart';
import 'package:mobile/features/signup/signup_gate.dart';
import 'package:mobile/features/student/stay_screens.dart';
import 'package:mobile/features/super_admin/data/sa_round3.dart';
import 'package:mobile/features/auth/app_lock_gate.dart';
import 'package:mobile/features/super_admin/sa_deletions_screen.dart';
import 'package:mobile/features/super_admin/sa_signups_screen.dart';
import 'package:mobile/features/warden/checkout/warden_checkouts_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── fakes ────────────────────────────────────────────────────────────────────────────────────

ApnivaasSession _session(UserRole role, {bool applicant = false, DateTime? verified}) =>
    ApnivaasSession(
      userId: 'u-${role.wire}',
      role: role,
      fullName: 'Test ${role.label}',
      status: 'active',
      mustChangePassword: false,
      email: 'test@example.com',
      emailVerifiedAt: verified ?? DateTime.utc(2026, 1, 1),
      staffApplicant: applicant,
    );

class _Auth extends AuthController {
  _Auth([this.initial = const AuthSignedOut()]);
  final AuthPhase initial;
  final signups = <Map<String, Object?>>[];
  SocialAttempt signupAnswer = const SocialAttempt(null, signedIn: true);

  @override
  Future<AuthPhase> build() async => initial;

  void set(AuthPhase phase) => state = AsyncData(phase);

  @override
  Future<SocialAttempt> continueWithGoogle({bool quietly = false, SignupPersona? persona}) async =>
      const SocialAttempt(null);

  @override
  Future<SocialAttempt> signUpWithPassword({
    required SignupPersona persona,
    required String fullName,
    required String phone,
    required String email,
    required String password,
    String? city,
    String? pincode,
  }) async {
    signups.add({
      'persona': persona,
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'password': password,
      'city': city,
      'pincode': pincode,
    });
    return signupAnswer;
  }

  @override
  Future<void> signOut() async => set(const AuthSignedOut());
}

class _NoGoogle implements GoogleIdTokenSource {
  @override
  bool get isAvailable => false;
  @override
  Future<GoogleTokenOutcome> request() async => const GoogleTokenCancelled();
  @override
  Future<GoogleTokenOutcome> requestQuietly() async => const GoogleTokenCancelled();
  @override
  Future<void> forget() async {}
}

class _Device implements BiometricAuthenticator {
  bool supported = true;
  UnlockResult answer = UnlockResult.unlocked;
  int prompts = 0;
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<UnlockResult> authenticate(String reason) async {
    prompts++;
    return answer;
  }
}

class _Stay implements StayApi {
  CheckoutRequest? mine;
  List<CheckoutRequestRow> rows = const [];
  final decisions = <Map<String, Object?>>[];

  @override
  Future<List<TimelineEntry>> timeline({String? studentId}) async => const [];
  @override
  Future<List<FeeMonth>> feeMonths({String? studentId}) async => const [];
  @override
  Future<CheckoutRequest?> requestCheckout({required DateTime preferredDate, String? reason}) async =>
      mine;
  @override
  Future<CheckoutRequest?> myCheckoutRequest() async => mine;
  @override
  Future<CheckoutRequest?> cancelCheckoutRequest() async => mine;
  @override
  Future<List<CheckoutRequestRow>> checkoutRequests(String hostelId, {String? status}) async =>
      rows;
  @override
  Future<CheckoutRequest?> decideCheckout(String requestId,
      {required bool accept, DateTime? checkoutDate, String? note}) async {
    decisions.add({'id': requestId, 'accept': accept, 'date': checkoutDate, 'note': note});
    return null;
  }

  @override
  Future<CheckoutSummary> checkoutSummary({String? hostelId}) async => CheckoutSummary.empty;
}

class _Sa implements SaRound3Api {
  final purged = <(String, String)>[];
  @override
  Future<SaPage<SaSignup>> signups(SaSignupQuery q) async => const SaPage([], 0);
  @override
  Future<SaPage<SaDeletedAccount>> deletedAccounts(SaDeletionQuery q) async => const SaPage([], 0);
  @override
  Future<void> purgeAccount(String userId, {required String reason}) async =>
      purged.add((userId, reason));
}

class _SaWith extends _Sa {
  _SaWith(this.rows);
  final List<SaSignup> rows;
  @override
  Future<SaPage<SaSignup>> signups(SaSignupQuery q) async => SaPage(rows, rows.length);
}

DateTime get _today {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// 360dp wide at 1.4x text: the size the spec holds every screen to.
Future<void> _pump(WidgetTester tester, Widget home, List<Override> overrides,
    {Map<String, Widget> routes = const {}}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(path: '/', builder: (_, _) => home),
    for (final e in routes.entries) GoRoute(path: e.key, builder: (_, _) => e.value),
  ]);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp.router(
      theme: ApnivaasTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.4)),
        child: child!,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // ═══ R1: signup_password ═════════════════════════════════════════════════════════════════
  group('signup_password wire format (docs/round3-api.md §1.1)', () {
    late List<Map<String, Object?>> sent;
    MobileAuthEndpoint endpoint(Object answer) => MobileAuthEndpoint((name, {body}) async {
          sent.add(Map<String, Object?>.from(body! as Map));
          if (answer is FunctionException) throw answer;
          return answer as FunctionResponse;
        });
    setUp(() => sent = []);

    test('sends exactly the contract fields, address only when given', () async {
      await endpoint(const FunctionsHttpException(status: 400)).signUpWithPassword(
          persona: 'staff', fullName: 'A B', phone: '9876543210', email: 'a@b.in', password: 'P@ss1word');
      expect(sent.single, {
        'action': 'signup_password',
        'persona': 'staff',
        'fullName': 'A B',
        'phone': '9876543210',
        'email': 'a@b.in',
        'password': 'P@ss1word',
      });
    });

    test('field errors come back keyed, unknown keys dropped; email_in_use keeps its code',
        () async {
      final v = await endpoint(const FunctionsHttpException(status: 400, details: {
        'ok': false,
        'error': 'Enter a valid 6-digit pincode.',
        'fieldErrors': {'pincode': 'Enter a valid 6-digit pincode.', 'evil': 'x'},
      })).signUpWithPassword(
          persona: 'owner', fullName: 'A B', phone: '9876543210', email: 'a@b.in', password: 'x');
      expect((v as AuthRejected).fieldErrors, {'pincode': 'Enter a valid 6-digit pincode.'});

      final taken = await endpoint(const FunctionsHttpException(status: 409, details: {
        'ok': false,
        'error': 'An account already uses this email — sign in, or reset your password',
        'code': 'email_in_use',
      })).signUpWithPassword(
          persona: 'owner', fullName: 'A B', phone: '9876543210', email: 'a@b.in', password: 'x');
      expect((taken as AuthRejected).code, 'email_in_use');
      expect(taken.message, startsWith('An account already uses this email'));
    });
  });

  group('Create your account — the manual form', () {
    List<Override> base(_Auth auth, SignupPersona persona) => [
          personaStorageProvider.overrideWithValue(MemoryPersonaStorage()..value = persona),
          authControllerProvider.overrideWith(() => auth),
          googleIdTokenSourceProvider.overrideWithValue(_NoGoogle()),
        ];

    testWidgets('checks every field before sending anything', (tester) async {
      final auth = _Auth();
      await _pump(tester, const CreateAccountScreen(), base(auth, SignupPersona.owner));
      expect(tester.takeException(), isNull);
      await _tap(tester, find.widgetWithText(FilledButton, 'Create account'));
      expect(find.text('Enter a name between 2 and 80 characters.'), findsOneWidget);
      expect(find.text('Enter a valid 10-digit mobile number.'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(find.text('Enter your city.'), findsOneWidget);
      expect(find.text('Enter a valid 6-digit pincode.'), findsOneWidget);
      expect(auth.signups, isEmpty);
    });

    testWidgets('sends the trimmed form; a server field error lands under its field',
        (tester) async {
      final auth = _Auth()
        ..signupAnswer = const SocialAttempt(
          'An account already uses this email — sign in, or reset your password',
          code: 'email_in_use',
          fieldErrors: {'email': 'An account already uses this email — sign in, or reset your password'},
        );
      await _pump(tester, const CreateAccountScreen(), base(auth, SignupPersona.tenant));
      Future<void> type(String key, String text) async {
        final f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.enterText(f, text);
      }

      await type('signup-name', ' Riya Sen ');
      await type('signup-phone', '98765 43210');
      await type('signup-email', 'riya@example.com');
      await type('signup-password', 'Hostel@2026');
      await type('signup-confirm', 'Hostel@2026');
      await type('signup-city', 'Pune');
      await type('signup-pincode', '411001');
      await _tap(tester, find.widgetWithText(FilledButton, 'Create account'));

      expect(auth.signups.single['persona'], SignupPersona.tenant);
      expect(auth.signups.single['city'], 'Pune');
      expect(auth.signups.single['pincode'], '411001');
      expect(find.textContaining('An account already uses this email'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mismatched passwords are caught on the phone', (tester) async {
      final auth = _Auth();
      await _pump(tester, const CreateAccountScreen(), base(auth, SignupPersona.staff));
      await tester.enterText(find.byKey(const ValueKey('signup-password')), 'Hostel@2026');
      await tester.enterText(find.byKey(const ValueKey('signup-confirm')), 'Hostel@2027');
      await _tap(tester, find.widgetWithText(FilledButton, 'Create account'));
      expect(find.text("The two passwords don't match"), findsOneWidget);
      expect(find.byKey(const ValueKey('signup-city')), findsNothing);
    });
  });

  testWidgets('login: logo and wordmark, no hero card, Welcome back kept', (tester) async {
    await _pump(tester, const LoginScreen(), [
      authControllerProvider.overrideWith(() => _Auth()),
      googleIdTokenSourceProvider.overrideWithValue(_NoGoogle()),
    ], routes: {startRoute: const Text('start')});
    expect(find.text('Run your PG from your phone'), findsNothing);
    expect(find.bySemanticsLabel('Apnivaas'), findsWidgets);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('New here? Create an account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ═══ R8 hook: staff applicants ════════════════════════════════════════════════════════════
  test('session reads staff_applicant, and an applicant proves the address like staff', () {
    final s = ApnivaasSession.fromRow({
      'id': 'u1',
      'role': 'student',
      'status': 'active',
      'email': 'a@b.in',
      'staff_applicant': true,
    });
    expect(s.staffApplicant, isTrue);
    expect(s.mustVerifyEmail, isTrue);
    expect(_session(UserRole.student).mustVerifyEmail, isFalse);
  });

  test('the onboarding gate sends a staff applicant to the applicant screen', () {
    final c = ProviderContainer(overrides: [
      sessionProvider.overrideWithValue(_session(UserRole.student, applicant: true)),
    ]);
    addTearDown(c.dispose);
    expect(c.read(signupNeedProvider).value, SignupNeed.staffApplicant);
  });

  // ═══ R3: app lock ═════════════════════════════════════════════════════════════════════════
  group('biometric app lock', () {
    late _Device device;
    late _Auth auth;
    late DateTime clock;

    ProviderContainer make(AuthPhase initial, {Map<String, bool>? prefs}) {
      device = _Device();
      auth = _Auth(initial);
      final c = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(() => auth),
        biometricAuthenticatorProvider.overrideWithValue(device),
        appLockPrefsStorageProvider.overrideWithValue(MemoryAppLockPrefsStorage(prefs)),
      ]);
      addTearDown(c.dispose);
      c.listen(appLockProvider, (_, _) {});
      clock = DateTime(2026, 10, 26, 9);
      c.read(appLockProvider.notifier).now = () => clock;
      return c;
    }

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('an owner reopening the app is asked; unlocking lets them in', () async {
      final c = make(AuthSignedIn(_session(UserRole.owner)));
      await settle();
      expect(c.read(appLockProvider).locked, isTrue);
      await c.read(appLockProvider.notifier).unlock();
      expect(c.read(appLockProvider).locked, isFalse);
      expect(device.prompts, 1);
    });

    test('a failed attempt stays locked and says so', () async {
      final c = make(AuthSignedIn(_session(UserRole.owner)));
      await settle();
      device.answer = UnlockResult.failed;
      await c.read(appLockProvider.notifier).unlock();
      expect(c.read(appLockProvider).locked, isTrue);
      expect(c.read(appLockProvider).message, AppLockController.failedWords);
    });

    test('off by default for a tenant, on when they chose it', () async {
      final off = make(AuthSignedIn(_session(UserRole.student)));
      await settle();
      expect(off.read(appLockProvider).locked, isFalse);
      final on = make(AuthSignedIn(_session(UserRole.student)), prefs: {'u-student': true});
      await settle();
      expect(on.read(appLockProvider).locked, isTrue);
    });

    test('a fresh sign-in is not asked again', () async {
      final c = make(const AuthSignedOut());
      await settle();
      auth.set(AuthSignedIn(_session(UserRole.owner)));
      await settle();
      expect(c.read(appLockProvider).locked, isFalse);
    });

    test('back after more than 60 seconds locks; a quick switch does not', () async {
      final c = make(const AuthSignedOut());
      await settle();
      auth.set(AuthSignedIn(_session(UserRole.owner)));
      await settle();
      final lock = c.read(appLockProvider.notifier);
      lock.onHidden();
      clock = clock.add(const Duration(seconds: 30));
      lock.onShown();
      await settle();
      expect(c.read(appLockProvider).locked, isFalse);
      lock.onHidden();
      clock = clock.add(const Duration(seconds: 61));
      lock.onShown();
      await settle();
      expect(c.read(appLockProvider).locked, isTrue);
    });

    test('a phone with no screen lock never locks anyone out', () async {
      device = _Device()..supported = false;
      final c = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(() => _Auth(AuthSignedIn(_session(UserRole.owner)))),
        biometricAuthenticatorProvider.overrideWithValue(device),
        appLockPrefsStorageProvider.overrideWithValue(MemoryAppLockPrefsStorage()),
      ]);
      addTearDown(c.dispose);
      c.listen(appLockProvider, (_, _) {});
      await settle();
      expect(c.read(appLockProvider).locked, isFalse);
    });

    test('turning it on asks first; a failed check leaves it off', () async {
      final c = make(const AuthSignedOut());
      await settle();
      auth.set(AuthSignedIn(_session(UserRole.manager)));
      await settle();
      device.answer = UnlockResult.failed;
      expect(await c.read(appLockProvider.notifier).setEnabled(true), 'App lock was not turned on.');
      expect(c.read(appLockProvider).enabledFor(_session(UserRole.manager)), isFalse);
      device.answer = UnlockResult.unlocked;
      expect(await c.read(appLockProvider.notifier).setEnabled(true), isNull);
      expect(c.read(appLockProvider).enabledFor(_session(UserRole.manager)), isTrue);
    });

    test('signing out drops the lock', () async {
      final c = make(AuthSignedIn(_session(UserRole.owner)));
      await settle();
      expect(c.read(appLockProvider).locked, isTrue);
      auth.set(const AuthSignedOut());
      await settle();
      expect(c.read(appLockProvider).locked, isFalse);
    });
  });

  test('round 3: an owner with no factor is no longer sent to enrol', () {
    expect(mfaGate(role: UserRole.owner, isAal2: false, hasVerifiedFactor: false),
        MfaGate.satisfied);
    expect(mfaGate(role: UserRole.owner, isAal2: false, hasVerifiedFactor: true),
        MfaGate.codeOwed);
  });

  // ═══ R2 / R6 models ═══════════════════════════════════════════════════════════════════════
  group('stay models', () {
    test('no month before check-in', () {
      final joined = DateTime(2026, 9, 18);
      expect(monthBeforeCheckIn('2026-08', joined), isTrue);
      expect(monthBeforeCheckIn('2026-09', joined), isFalse);
      expect(monthBeforeCheckIn('2026-10', joined), isFalse);
    });

    test('timeline rows parse leniently and keep their order', () {
      final rows = TimelineEntry.listFrom([
        {'at': '2026-10-01T04:30:00Z', 'kind': 'due', 'title': 'Rent due for October 2026', 'amount': 6200, 'status': 'unpaid'},
        {'at': '2026-09-18T04:30:00Z', 'kind': 'checked_in', 'title': 'Checked in'},
        {'kind': 'payment'}, // no time or title: dropped
        {'at': '2026-09-18T04:30:00Z', 'kind': 'new_kind', 'title': 'Something new'},
      ]);
      expect(rows.map((r) => r.kind), [TimelineKind.due, TimelineKind.checkedIn, TimelineKind.other]);
      expect(rows.first.amount, 6200);
    });

    test('check-out request and owner summary', () {
      final r = CheckoutRequest.tryParse({
        'request_id': 'r1',
        'status': 'accepted',
        'preferred_date': '2026-11-12',
        'checkout_date': '2026-11-14',
      })!;
      expect(r.status.isOpen, isTrue);
      expect(r.checkoutDate, DateTime(2026, 11, 14));
      expect(CheckoutRequest.tryParse(null), isNull);

      final s = CheckoutSummary.parse({
        'pending': 2,
        'scheduled': 1,
        'recent': 0,
        'items': [
          {'request_id': 'r1', 'status': 'pending', 'full_name': 'Riya', 'room_number': '101'},
        ],
      });
      expect(CheckoutsNotice.summaryLine(s), '2 waiting · 1 scheduled');
      expect(s.items.single.fullName, 'Riya');
    });
  });

  // ═══ R6 screens ═══════════════════════════════════════════════════════════════════════════
  group('check-out', () {
    testWidgets('tenant: the form asks for a date before sending', (tester) async {
      final stay = _Stay();
      await _pump(tester, const CheckoutScreen(), [stayApiProvider.overrideWithValue(stay)]);
      expect(find.text('Request check-out'), findsWidgets);
      await _tap(tester, find.widgetWithText(FilledButton, 'Request check-out'));
      expect(find.text('Choose a date from today up to 90 days ahead.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tenant: a pending request shows its status and can be cancelled',
        (tester) async {
      final stay = _Stay()
        ..mine = CheckoutRequest(
          requestId: 'r1',
          status: CheckoutStatus.pending,
          preferredDate: _today.add(const Duration(days: 5)),
          reason: 'Moving to a new job',
        );
      await _pump(tester, const CheckoutScreen(), [stayApiProvider.overrideWithValue(stay)]);
      expect(find.text('Waiting for the warden'), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Request check-out'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('warden: accepting today checks the resident out now', (tester) async {
      final stay = _Stay()
        ..rows = [
          CheckoutRequestRow(
            requestId: 'r1',
            studentId: 's1',
            fullName: 'Riya Sen',
            status: CheckoutStatus.pending,
            preferredDate: _today,
            roomNumber: '101',
            bedNumber: 2,
          ),
        ];
      await _pump(tester, const CheckoutRequestsScreen(hostelId: 'h1'), [
        stayApiProvider.overrideWithValue(stay),
        currentHostelIdProvider.overrideWithValue('h1'),
      ]);
      expect(find.text('Riya Sen'), findsOneWidget);
      await _tap(tester, find.widgetWithText(FilledButton, 'Accept'));
      expect(find.text('Check out now'), findsOneWidget);
      await _tap(tester, find.text('Check out now'));
      expect(stay.decisions.single['accept'], isTrue);
      expect(stay.decisions.single['date'], _today);
    });
  });

  // ═══ R7: permanent delete ═════════════════════════════════════════════════════════════════
  testWidgets('permanent delete needs a reason and the typed word, and says payments stay',
      (tester) async {
    final sa = _Sa();
    const account = SaDeletedAccount(
      id: 'd1',
      userId: 'u9',
      fullName: 'Old Warden',
      kind: 'owner_deleted_staff',
      canPurge: true,
    );
    await _pump(
      tester,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => const PurgeAccountDialog(account: account),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      [saRound3ApiProvider.overrideWithValue(sa)],
    );
    await _tap(tester, find.text('open'));
    expect(find.textContaining('Payments, receipts, dues and audit records are kept'), findsOneWidget);
    FilledButton button() => tester.widget<FilledButton>(
        find.ancestor(of: find.text('Delete permanently'), matching: find.byType(FilledButton)));
    expect(button().onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Left the PG in 2025');
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'the word is not typed yet');
    await tester.enterText(find.widgetWithText(TextField, 'Type DELETE to confirm'), 'DELETE');
    await tester.pump();
    await _tap(tester, find.text('Delete permanently'));
    expect(sa.purged.single, ('u9', 'Left the PG in 2025'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('1.4x on 360dp: timeline, sign-ups and the lock screen lay out', (tester) async {
    final entries = TimelineEntry.listFrom([
      {'at': '2026-10-02T04:30:00Z', 'kind': 'payment', 'title': 'Payment recorded', 'detail': 'For October 2026 · UPI', 'amount': 6200, 'status': 'paid'},
      {'at': '2026-10-01T04:30:00Z', 'kind': 'checkout_request', 'title': 'Check-out requested', 'detail': 'Preferred date 12 Nov 2026', 'status': 'pending'},
      {'at': '2026-09-18T04:30:00Z', 'kind': 'checked_in', 'title': 'Checked in', 'detail': 'Room 101, bed 2'},
    ]);
    await _pump(tester, Scaffold(body: ListView(children: [TimelineList(entries: entries)])), []);
    expect(find.text('Check-out requested'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final sa = _SaWith([
      SaSignup.tryParse({
        'user_id': 'u1',
        'full_name': 'Lakshmi Narayanan Iyer',
        'phone': '9876543210',
        'email': 'lakshmi.narayanan@example.com',
        'signup_source': 'self_google',
        'signed_up_at': '2026-10-20T05:00:00Z',
        'hostel_name': 'Green Valley Ladies PG',
        'hostel_city': 'Bengaluru',
        'trial_start': '2026-10-20',
        'trial_end': '2026-11-19',
        'plan_status': 'trial',
        'demo_id': 'd1',
        'demo_slot': '2026-10-28T05:30:00Z',
        'demo_bed_band': '21-50',
        'demo_status': 'requested',
      })!,
    ]);
    await _pump(tester, const SaSignupsScreen(), [saRound3ApiProvider.overrideWithValue(sa)]);
    expect(find.text('Lakshmi Narayanan Iyer'), findsOneWidget);
    expect(find.textContaining('Trial 20 Oct 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pump(tester, const AppLockScreen(), [
      authControllerProvider.overrideWith(() => _Auth()),
      appLockPrefsStorageProvider.overrideWithValue(MemoryAppLockPrefsStorage()),
      biometricAuthenticatorProvider.overrideWithValue(_Device()),
    ]);
    expect(find.text('Apnivaas is locked'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('a refused purge keeps the server sentence', () {
    expect(
      stayErrorText(const SignupFailure('This tenant is still checked in. Check them out of their PG first.')),
      'This tenant is still checked in. Check them out of their PG first.',
    );
  });
}
