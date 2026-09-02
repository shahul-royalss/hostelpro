import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/features/settings/mfa_service.dart';
import 'package:mobile/features/settings/security_screen.dart';

/// Two-factor ENROLMENT — the half of MFA this app did not have.
///
/// Before this feature `grep -rni enroll lib` returned nothing: the app could verify a factor
/// that already existed and could not create one, so 2FA could never be switched on from a
/// phone. Exactly one account on the whole platform had a factor, and it had been enrolled from
/// the web console. These tests hold the three things that make the flow safe rather than
/// merely present:
///
///   1. the happy path actually turns it on,
///   2. a wrong code refuses and leaves 2FA OFF — it must never "succeed" optimistically,
///   3. the setup key is shown ONCE and cannot be recalled, which is what makes it a secret.
///
/// They drive the screen through [MfaService], the same seam the real Supabase implementation
/// sits behind, so nothing here needs a network, an initialised Supabase client or a real TOTP.

/// A stand-in for the real service. Accepts one code and nothing else.
class _FakeMfa implements MfaService {
  _FakeMfa({this.enrolled = false, this.qrSvg});

  /// The only code this fake will take. A real authenticator's code changes every 30 seconds;
  /// a fixed one is the same test with less to go wrong.
  static const goodCode = '123456';

  static const wrongCodeMessage =
      'That code is not right. Use the code your authenticator app is showing NOW.';

  final String? qrSvg;

  /// Flipped by [confirm] and [disable], read back by [load] — so a test asserts on what
  /// the SERVER would say next, not on what the screen hoped.
  bool enrolled;

  /// Every secret this fake has ever issued, in order. The test for "shown once" reads it.
  final List<String> issued = <String>[];
  int beginCalls = 0;
  String? lastFriendlyName;

  @override
  Future<MfaState> load() async => enrolled
      ? MfaState(
          enrolled: true,
          factorId: 'factor-1',
          // A fixed date so this is the same test in September.
          addedOn: DateTime.utc(2026, 8, 23),
        )
      : const MfaState.off();

  @override
  Future<TotpEnrollment> begin({String? friendlyName}) async {
    beginCalls++;
    lastFriendlyName = friendlyName;
    final secret = 'JBSWY3DPEHPK3PX$beginCalls';
    issued.add(secret);
    return TotpEnrollment(
      factorId: 'factor-new-$beginCalls',
      secret: secret,
      uri: 'otpauth://totp/NIVORA:someone?secret=$secret',
      qrSvg: qrSvg,
    );
  }

  @override
  Future<void> confirm({required String factorId, required String code}) async {
    if (code != goodCode) throw const MfaFailure(wrongCodeMessage);
    enrolled = true;
  }

  @override
  Future<void> disable({required String factorId, required String code}) async {
    if (code != goodCode) throw const MfaFailure(wrongCodeMessage);
    enrolled = false;
  }
}

/// The screen reads `sessionProvider` to name the factor the way the web action names it. The
/// real controller reaches for `Supabase.instance` in build(), which throws in a test, so the
/// phase is supplied directly — the same stub change_password_test.dart uses.
///
/// [reload] and [signOut] are overridden rather than left to the real ones because they are the
/// two exits from a REQUIRED arrival, and the real reload() re-resolves through GoTrue. What
/// matters to these tests is that the screen calls it: the phase this screen is drawn for is
/// [AuthNeedsMfaEnrolment], and nothing else in the app republishes it when the factor is
/// verified — gotrue emits only `mfaChallengeVerified`, which AuthController's stream switch
/// does not listen for. A screen that did not make this call would be a screen with no way out,
/// which is the bug the group at the bottom of this file exists for.
class _StubAuth extends AuthController {
  _StubAuth(this._phase, {this.reloadMoves = true});
  AuthPhase _phase;

  /// False models the real [AuthController.reload] failing: it SWALLOWS its errors — everywhere
  /// else in the app it is a background correction — so a screen that treats it as a button has
  /// to look at the outcome rather than assume one.
  final bool reloadMoves;

  int reloads = 0;
  int signOuts = 0;

  @override
  Future<AuthPhase> build() async => _phase;

  @override
  Future<void> reload() async {
    reloads++;
    if (!reloadMoves) return;
    // What the real one would resolve to: the session is aal2 now, so mfaGate is satisfied.
    publish(const AuthSignedIn(_session));
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    publish(const AuthSignedOut());
  }

  void publish(AuthPhase next) {
    _phase = next;
    state = AsyncData(next);
  }
}

const _session = NivoraSession(
  userId: '00000000-0000-0000-0000-000000000009',
  role: UserRole.owner,
  fullName: 'A Real Owner',
  status: 'active',
  mustChangePassword: false,
  email: 'owner@example.com',
);

/// The window every pump in this file uses. Tall, because the setup panel is a QR, a key, a
/// warning, a checkbox and two buttons: on a 600dp window the confirm button is below the fold
/// and "disabled" is indistinguishable from "never built".
void _tallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, _FakeMfa fake) async {
  _tallWindow(tester);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mfaServiceProvider.overrideWithValue(fake),
        authControllerProvider.overrideWith(() => _StubAuth(const AuthSignedIn(_session))),
      ],
      child: MaterialApp(
        theme: NivoraTheme.dark(),
        home: const SecurityScreen(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
  await _settle(tester);
}

/// Frames, not `pumpAndSettle`: a busy button holds a [CircularProgressIndicator], which
/// schedules frames forever, so settling would time out on exactly the states worth testing.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The screen the ROUTER draws: `/mfa-setup`, which is `SecurityScreen(required: true)` and the
/// only page in the navigator. `home:` reproduces that stack shape exactly — one route, and it
/// is `isFirst`, which is the whole reason the back chevron used to do nothing.
Future<_StubAuth> _pumpRequired(
  WidgetTester tester,
  _FakeMfa fake, {
  AuthPhase? phase,
  bool reloadMoves = true,
}) async {
  _tallWindow(tester);
  final auth = _StubAuth(
    phase ?? const AuthNeedsMfaEnrolment(_session),
    reloadMoves: reloadMoves,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mfaServiceProvider.overrideWithValue(fake),
        authControllerProvider.overrideWith(() => auth),
      ],
      child: MaterialApp(
        theme: NivoraTheme.dark(),
        home: const SecurityScreen(required: true),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
  await _settle(tester);
  return auth;
}

/// The ANDROID SYSTEM BACK GESTURE, as the engine actually delivers it — not `Navigator.pop`.
///
/// The two are different events and this whole group exists because they used to have different
/// outcomes: `maybePop` from the chevron returned false and did nothing, while the same refusal
/// reached as a platform message let WidgetsBinding fall through to `SystemNavigator.pop()` and
/// close the app. A test that called Navigator.maybePop would see the first and miss the second.
Future<void> _systemBack(WidgetTester tester) async {
  final message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage('flutter/navigation', message, (_) {});
  await _settle(tester);
}

/// Everything the app asks the ENGINE to do while the test runs.
///
/// `SystemNavigator.pop` in here means Flutter gave up on the back gesture and asked Android to
/// close the app. On a screen the router will put straight back, that is not an exit — it is the
/// app vanishing and reappearing on the same screen, which is what the owner was describing.
List<String> _engineCalls(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call.method);
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

/// Drive the enrolment to the end on whatever screen is up.
Future<void> _enrol(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Set up two-factor authentication'));
  await _settle(tester);
  await tester.enterText(_codeField('Code from your app'), _FakeMfa.goodCode);
  await tester.tap(find.text('I have saved this key'));
  await tester.pump();
  await tester.ensureVisible(_confirmButton());
  await tester.tap(_confirmButton());
  await _settle(tester);
}

Finder _confirmButton() => find.widgetWithText(FilledButton, 'Turn on two-factor');
Finder _codeField(String label) => find.widgetWithText(TextField, label);
Finder _backChevron() => find.byIcon(Icons.arrow_back_rounded);

void main() {
  testWidgets('the happy path: off → key on screen → first code → on', (tester) async {
    final fake = _FakeMfa();
    await _pump(tester, fake);

    // Where every account starts, and it says so rather than saying nothing.
    expect(find.text('OFF'), findsOneWidget);
    expect(find.text('Two-factor authentication'), findsOneWidget);

    final start = find.widgetWithText(FilledButton, 'Set up two-factor authentication');
    expect(start, findsOneWidget);
    await tester.tap(start);
    await _settle(tester);

    // The factor is named exactly as lib/actions/mfa.ts names it, so one account enrolled from
    // either client shows one label in the authenticator app.
    expect(fake.lastFriendlyName, 'NIVORA (owner)');

    // The key, in full, next to the QR rather than behind a "can't scan?" link.
    expect(find.text(fake.issued.single), findsOneWidget);
    expect(find.text('SETUP KEY'), findsOneWidget);
    expect(find.text('I have saved this key'), findsOneWidget);

    // BOTH GATES. A correct code alone must not finish setup — someone who never stored the
    // key is one lost phone away from being locked out of their own hostel.
    expect(tester.widget<FilledButton>(_confirmButton()).onPressed, isNull);

    await tester.enterText(_codeField('Code from your app'), _FakeMfa.goodCode);
    await tester.pump();
    expect(
      tester.widget<FilledButton>(_confirmButton()).onPressed,
      isNull,
      reason: 'the code is entered but the key has not been acknowledged',
    );

    await tester.tap(find.text('I have saved this key'));
    await tester.pump();
    expect(tester.widget<FilledButton>(_confirmButton()).onPressed, isNotNull);

    await tester.ensureVisible(_confirmButton());
    await tester.tap(_confirmButton());
    await _settle(tester);

    // It is on, and the screen says so from the server's own answer, not from optimism.
    expect(find.text('ON'), findsOneWidget);
    expect(find.text('Added 23 Aug 2026'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Turn off two-factor authentication'),
        findsOneWidget);
  });

  testWidgets('a wrong code is refused, says why, and leaves 2FA OFF', (tester) async {
    final fake = _FakeMfa();
    await _pump(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Set up two-factor authentication'));
    await _settle(tester);

    await tester.enterText(_codeField('Code from your app'), '000000');
    await tester.tap(find.text('I have saved this key'));
    await tester.pump();

    await tester.ensureVisible(_confirmButton());
    await tester.tap(_confirmButton());
    await _settle(tester);

    // The failure is shown, in words that name the usual cause.
    expect(find.textContaining('That code is not right'), findsOneWidget);

    // AND NOTHING WAS SWITCHED ON. The panel is still open, the badge has not flipped, and the
    // "turn it off" control — which only exists for an enrolled account — is nowhere.
    expect(find.text('ON'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Turn off two-factor authentication'),
        findsNothing);
    expect(find.text('Setting up'.toUpperCase()), findsOneWidget);

    // The field is cleared so the retry is a fresh code rather than an edit of a rejected one,
    // and the button is disarmed again until six digits are back in it.
    expect(tester.widget<TextField>(_codeField('Code from your app')).controller?.text, '');
    expect(tester.widget<FilledButton>(_confirmButton()).onPressed, isNull);

    // The same panel, the same factor — a rejection must not silently start a second enrolment.
    expect(fake.beginCalls, 1);
  });

  testWidgets('the secret is shown once: gone after setup, and never shown again',
      (tester) async {
    final fake = _FakeMfa();
    await _pump(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Set up two-factor authentication'));
    await _settle(tester);

    final first = fake.issued.single;
    expect(find.text(first), findsOneWidget);

    await tester.enterText(_codeField('Code from your app'), _FakeMfa.goodCode);
    await tester.tap(find.text('I have saved this key'));
    await tester.pump();
    await tester.ensureVisible(_confirmButton());
    await tester.tap(_confirmButton());
    await _settle(tester);

    // It is on, and the key is off the screen — the app keeps no copy to show again.
    expect(find.text('ON'), findsOneWidget);
    expect(find.text(first), findsNothing);
    expect(find.text('SETUP KEY'), findsNothing);
  });

  testWidgets('abandoning setup discards the key; starting again issues a different one',
      (tester) async {
    final fake = _FakeMfa();
    await _pump(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Set up two-factor authentication'));
    await _settle(tester);
    final first = fake.issued.single;
    expect(find.text(first), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(TextButton, 'Cancel setup'));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel setup'));
    await _settle(tester);
    expect(find.text(first), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Set up two-factor authentication'));
    await _settle(tester);

    expect(fake.beginCalls, 2);
    final second = fake.issued.last;
    expect(second, isNot(first));
    expect(find.text(second), findsOneWidget);
    expect(find.text(first), findsNothing,
        reason: 'the abandoned key is dead and must not reappear');

    // The checkbox is un-ticked for the new key: acknowledging one secret cannot vouch for a
    // different one.
    expect(tester.widget<FilledButton>(_confirmButton()).onPressed, isNull);
  });

  testWidgets('a camera that cannot scan is not a dead end', (tester) async {
    // qrSvg null is what the screen gets when the server sent something it cannot draw.
    final fake = _FakeMfa();
    await _pump(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Set up two-factor authentication'));
    await _settle(tester);

    expect(find.byType(SvgPicture), findsNothing);
    // The typed key is still there, in full, and so is the way to finish with it.
    expect(find.text(fake.issued.single), findsOneWidget);
    expect(find.textContaining('Type the key below'), findsOneWidget);
    expect(_codeField('Code from your app'), findsOneWidget);
  });

  testWidgets('the QR is drawn when the server sends one', (tester) async {
    final fake = _FakeMfa(
      qrSvg: '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">'
          '<rect width="8" height="8" fill="#000000"/></svg>',
    );
    await _pump(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Set up two-factor authentication'));
    await _settle(tester);

    expect(find.byType(SvgPicture), findsOneWidget);
    // The key stays on screen NEXT to the QR, not behind a disclosure.
    expect(find.text(fake.issued.single), findsOneWidget);
  });

  testWidgets('turning 2FA off needs a valid code', (tester) async {
    final fake = _FakeMfa(enrolled: true);
    await _pump(tester, fake);

    expect(find.text('ON'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Turn off two-factor authentication'));
    await tester.pump();

    final off = find.widgetWithText(FilledButton, 'Turn off');
    expect(tester.widget<FilledButton>(off).onPressed, isNull,
        reason: 'no code typed yet');

    await tester.enterText(_codeField('Current code'), '999999');
    await tester.pump();
    await tester.ensureVisible(off);
    await tester.tap(off);
    await _settle(tester);

    // Refused, and still on.
    expect(find.textContaining('That code is not right'), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);
    expect(find.text('OFF'), findsNothing);

    await tester.enterText(_codeField('Current code'), _FakeMfa.goodCode);
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Turn off'));
    await tester.tap(find.widgetWithText(FilledButton, 'Turn off'));
    await _settle(tester);

    expect(find.text('OFF'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Set up two-factor authentication'),
        findsOneWidget);
  });

  // ── The one pure function in the flow ────────────────────────────────────────────────────
  //
  // gotrue-dart prepends `data:image/svg+xml;utf-8,` to the QR itself, but the encoding is not
  // part of any contract. Getting this wrong draws a rectangle of garbage where a scannable
  // square should be, which is the kind of failure nobody files a bug about.
  group('svgFromDataUri', () {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>';

    test('unwraps the prefix gotrue-dart actually sends', () {
      expect(svgFromDataUri('data:image/svg+xml;utf-8,$svg'), svg);
    });

    test('decodes a percent-encoded body', () {
      expect(svgFromDataUri('data:image/svg+xml,${Uri.encodeComponent(svg)}'), svg);
    });

    test('decodes a base64 body', () {
      const encoded =
          'PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjwvc3ZnPg==';
      expect(svgFromDataUri('data:image/svg+xml;base64,$encoded'), svg);
    });

    test('passes bare markup through', () {
      expect(svgFromDataUri(svg), svg);
    });

    test('returns null rather than guessing', () {
      // A PNG, a truncated URI, and something that is not a data URI at all. Each falls back to
      // the typed key, which is why the key is never optional.
      expect(svgFromDataUri('data:image/png;base64,iVBORw0KGgo='), isNull);
      expect(svgFromDataUri('data:image/svg+xml;utf-8'), isNull);
      expect(svgFromDataUri('not a uri'), isNull);
      expect(svgFromDataUri('data:image/svg+xml;utf-8,{"not":"svg"}'), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // GETTING OUT — the half of this screen that did not exist
  // ═══════════════════════════════════════════════════════════════════════════════════════
  //
  // Reported verbatim: "when i turn on 2FA i haven't any option / navigation to go back from
  // the screen". Every test below is one of the causes, or one of the exits that replaced it.
  //
  // The shape of the bug: /mfa-setup is `SecurityScreen(required: true)` and it is the FIRST
  // route in go_router's navigator, so `Navigator.maybePop()` took the `bubble` arm and did
  // nothing (navigator.dart:389) — a chevron that was a picture of a control. The same refusal
  // arriving as an Android back GESTURE was worse: `bubble` let WidgetsBinding fall through to
  // `SystemNavigator.pop()` and close the app, which then reopened on the same screen.
  //
  // And nothing released the screen after a successful enrolment, which is the state the
  // owner's screenshot shows: `challengeAndVerify` emits only `mfaChallengeVerified`, and
  // AuthController's stream switch has no arm for it, so the app kept publishing
  // AuthNeedsMfaEnrolment over a session the SERVER had already promoted to aal2.

  group('leaving a required enrolment', () {
    testWidgets('draws no chevron it cannot honour, and says why there is none',
        (tester) async {
      await _pumpRequired(tester, _FakeMfa());

      // The control that used to be here and did nothing. Drawing it was the first half of the
      // bug: it advertised an exit that `maybePop` could not take.
      expect(_backChevron(), findsNothing);

      // What stands in its place, for the whole visit rather than only in reply to a gesture.
      expect(find.text('Required'), findsOneWidget);
      expect(find.textContaining('the only screen it can open'), findsOneWidget);
      expect(find.textContaining('Owner'), findsWidgets,
          reason: 'it names the role the requirement is attached to, from the session');

      // "No way out" is never acceptable, even when going ON is refused.
      expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget);
    });

    testWidgets('the system back gesture is refused OUT LOUD, and never closes the app',
        (tester) async {
      final engine = _engineCalls(tester);
      await _pumpRequired(tester, _FakeMfa());

      await _systemBack(tester);

      // THE ASSERTION THIS GROUP EXISTS FOR. Before the PopScope, the navigator declined the
      // gesture and Flutter asked Android to close the app instead.
      expect(engine, isNot(contains('SystemNavigator.pop')),
          reason: 'backgrounding the app is not an exit from a screen the router redraws');

      // Refused, and answered. A gesture swallowed in silence is indistinguishable from a
      // broken button, which is exactly what got reported.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('or sign out to leave this screen'), findsOneWidget);

      // Still here, still able to do the thing it is asking for.
      expect(find.widgetWithText(FilledButton, 'Set up two-factor authentication'),
          findsOneWidget);
    });

    testWidgets('signing out is a real exit for someone who cannot enrol right now',
        (tester) async {
      // No authenticator app, a borrowed handset, a resident at a desk. The refusal is about
      // walking INTO the app owing a factor, not about holding the phone hostage.
      final auth = await _pumpRequired(tester, _FakeMfa());

      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await _settle(tester);

      expect(auth.signOuts, 1);
    });

    testWidgets('enrolling turns the refusal into a way out, and the way out MOVES THE APP',
        (tester) async {
      final fake = _FakeMfa();
      final auth = await _pumpRequired(tester, fake);

      await _enrol(tester);

      // The factor exists, so the reason for refusing is gone and the screen stops refusing.
      expect(fake.enrolled, isTrue);
      expect(find.text('Required'), findsNothing);
      expect(find.textContaining('the only screen it can open'), findsNothing);

      final continueButton = find.widgetWithText(FilledButton, 'Continue to Nivora');
      expect(continueButton, findsOneWidget);

      await tester.ensureVisible(continueButton);
      await tester.tap(continueButton);
      await _settle(tester);

      // NOT a pop — there is nothing under this route. Leaving means changing the answer the
      // redirect keeps giving, and reload() is the only thing in the app that republishes the
      // phase after `challengeAndVerify`.
      expect(auth.reloads, 1,
          reason: 'without this call the router redraws /mfa-setup for ever');
    });

    testWidgets('once the factor exists the system gesture leaves instead of refusing',
        (tester) async {
      final engine = _engineCalls(tester);
      final auth = await _pumpRequired(tester, _FakeMfa());

      await _enrol(tester);
      await _systemBack(tester);

      expect(auth.reloads, 1);
      expect(find.byType(SnackBar), findsNothing, reason: 'nothing was refused');
      expect(engine, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('an account that is ALREADY enrolled is not held here at all', (tester) async {
      // The offline arm of _applyMfaGate: GoTrue was unreachable when the phase was resolved,
      // so a privileged account with a perfectly good factor was sent here anyway. The screen
      // re-reads the factor list itself, and the moment that read succeeds it must offer the
      // way on rather than demanding a second enrolment.
      final auth = await _pumpRequired(tester, _FakeMfa(enrolled: true));

      expect(find.text('Required'), findsNothing);
      expect(find.text('ON'), findsOneWidget);

      final continueButton = find.widgetWithText(FilledButton, 'Continue to Nivora');
      expect(continueButton, findsOneWidget);
      await tester.ensureVisible(continueButton);
      await tester.tap(continueButton);
      await _settle(tester);

      expect(auth.reloads, 1);
    });

    testWidgets('a Continue that does not move the app SAYS SO instead of spinning',
        (tester) async {
      // reload() swallows its own failures by design. If the phase has not moved when it
      // returns, the router is still drawing this screen — and a button that spins and hands
      // you back the screen you were on, silently, is the same bug in a new costume.
      final fake = _FakeMfa(enrolled: true);
      final auth = await _pumpRequired(tester, fake, reloadMoves: false);

      final continueButton = find.widgetWithText(FilledButton, 'Continue to Nivora');
      await tester.ensureVisible(continueButton);
      await tester.tap(continueButton);
      await _settle(tester);

      expect(auth.reloads, 1);
      expect(find.textContaining('could not confirm that with the server'), findsOneWidget);

      // Still usable: not spinning for ever, and the exits are still there.
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('turning the factor back off restores the refusal, and the reason for it',
        (tester) async {
      // The exit must follow the FACT, not a flag set once. An account that enrols and then
      // disables owes the factor again, and offering Continue would send it to a router that
      // bounces it straight back.
      final fake = _FakeMfa(enrolled: true);
      await _pumpRequired(tester, fake);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Turn off two-factor authentication'));
      await tester.pump();
      await tester.enterText(_codeField('Current code'), _FakeMfa.goodCode);
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Turn off'));
      await tester.tap(find.widgetWithText(FilledButton, 'Turn off'));
      await _settle(tester);

      expect(find.text('OFF'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue to Nivora'), findsNothing);
      expect(find.text('Required'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget);
    });
  });

  // ── AND THE ORDINARY ARRIVAL, WHICH MUST BE EXACTLY AS IT WAS ────────────────────────────
  //
  // Everything above is about the route the redirect draws. The header icon pushes the SAME
  // widget with `required: false`, onto a stack that has something beneath it, and that arrival
  // has always worked. The PopScope must not have taken anything away from it — a `canPop:
  // false` applied to both would have turned a working back button into the bug it was added
  // to fix.

  group('leaving an ordinary visit', () {
    Future<void> pumpPushed(WidgetTester tester, _FakeMfa fake) async {
      _tallWindow(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mfaServiceProvider.overrideWithValue(fake),
            authControllerProvider.overrideWith(() => _StubAuth(const AuthSignedIn(_session))),
          ],
          child: MaterialApp(
            theme: NivoraTheme.dark(),
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    // The production entry point, not a hand-rolled push: every role's header
                    // calls exactly this.
                    onPressed: () => openSecurity(context),
                    child: const Text('Open security'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Open security'));
      await _settle(tester);
      expect(find.text('Security'), findsOneWidget);
    }

    testWidgets('the chevron is there, and it goes back', (tester) async {
      await pumpPushed(tester, _FakeMfa());

      expect(_backChevron(), findsOneWidget);
      await tester.tap(_backChevron());
      // The pop is an ANIMATION: both routes are mounted while it runs, so a fixed number of
      // frames would assert on the transition rather than on the outcome. Nothing on the way
      // out spins, so settling terminates here.
      await tester.pumpAndSettle();

      expect(find.text('Security'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Open security'), findsOneWidget);
    });

    testWidgets('and so does the system back gesture, with nothing refused', (tester) async {
      final engine = _engineCalls(tester);
      await pumpPushed(tester, _FakeMfa());

      await _systemBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('Security'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(engine, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('enrolling from a header visit does not grow a Continue it does not need',
        (tester) async {
      // The ordinary visit already has somewhere to go back to. The required arrival's exit
      // would be a second, differently-behaved way out of a screen that has one.
      final fake = _FakeMfa();
      await pumpPushed(tester, fake);

      await _enrol(tester);

      expect(find.text('ON'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue to Nivora'), findsNothing);
      expect(find.text('Required'), findsNothing);
      expect(_backChevron(), findsOneWidget);
    });
  });
}
