import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/config/env.dart';
import 'package:mobile/core/router/router.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/features/auth/email_verification_service.dart';
import 'package:mobile/features/auth/verify_email_screen.dart';

/// EMAIL VERIFICATION BY LINK — the behaviours that make it a requirement rather than a trap,
/// and the one that makes a link usable at all.
///
/// The feature's design turns on one decision, argued at length in
/// supabase/functions/_shared/verification.ts: the account CAN sign in without having proved its
/// address, a banner asks until it does, and the server refuses the one action where an unproved
/// address becomes credentials in a stranger's inbox. The alternative — block sign-in until the
/// address is proved — is a lockout, because the project has "Confirm email" ON and GoTrue
/// refuses a password grant to an unconfirmed user.
///
/// On 2026-09-01 the proof changed from a 6-digit code typed into this app to a LINK opened
/// somewhere else, which adds a problem the code flow never had: NOTHING TELLS THE APP WHEN IT
/// HAPPENED. Section 4 is that problem, and it is the reason this file exists in its current
/// form. The rest is what must survive the change:
///
///   1. ROUTING. An unverified account routes exactly like a verified one — to its role home,
///      and it stays there. If someone ever "tightens" this into a redirect, these fail.
///   2. WHO IS ASKED. By ADDRESS, not by role: a resident whose login is a phone number is
///      never asked for a proof that cannot be produced, and a student with a real email is
///      asked exactly like an owner.
///   3. THE LINK. Sent to the address the banner NAMES, without a second tap. "I have opened
///      it" asks the server rather than believing the user, and a link that has not been opened
///      says so instead of claiming success.
///   4. THE RE-CHECK ON RESUME. Coming back into the app is the completion signal. It must fire
///      for the SCREEN and for the BANNER (a user who taps the link in their inbox and returns
///      to their home screen never opens the screen at all); it must NOT fire for accounts with
///      nothing to prove; and it must stay silent when it fails, because a resume-time error is
///      an accusation aimed at someone who has done nothing wrong.
///   5. THE RESEND COOLDOWN counts down, re-arms, takes the SERVER's number when the server
///      gives one, and never disables the "I have opened it" button — someone whose link is
///      already sitting in their inbox must not be blocked by a throttle on sending another.
///
/// Everything runs through [EmailVerificationService], the seam the real GoTrue/Edge Function
/// client sits behind, so nothing here needs a network, an initialised Supabase client or an
/// inbox.

const _userId = '00000000-0000-0000-0000-000000000042';

/// An owner who has not proved their address. `emailVerifiedAt: null` is where every account in
/// this project has always started — by design and not by backlog.
const _unverified = NivoraSession(
  userId: _userId,
  role: UserRole.owner,
  fullName: 'A Real Owner',
  status: 'active',
  mustChangePassword: false,
  email: 'owner@example.com',
);

final _verified = NivoraSession(
  userId: _userId,
  role: UserRole.owner,
  fullName: 'A Real Owner',
  status: 'active',
  mustChangePassword: false,
  email: 'owner@example.com',
  emailVerifiedAt: DateTime.utc(2026, 9, 1, 10, 30),
);

/// A resident registered with no email at all. The login id is their phone number mapped into
/// the reserved namespace, which no mail server accepts.
const _phoneOnlyStudent = NivoraSession(
  userId: _userId,
  role: UserRole.student,
  fullName: 'A Resident',
  status: 'active',
  mustChangePassword: false,
  hostelId: '00000000-0000-0000-0000-0000000000aa',
  email: '9876543210@student.hostelpro.local',
);

/// A resident whose warden DID collect an email. That address is their login id, so it is
/// reachable and they owe the same proof an owner does.
const _emailStudent = NivoraSession(
  userId: _userId,
  role: UserRole.student,
  fullName: 'A Resident',
  status: 'active',
  mustChangePassword: false,
  hostelId: '00000000-0000-0000-0000-0000000000aa',
  email: 'resident@example.com',
);

/// The real controller reaches for `Supabase.instance` in build(), which throws in a test, so
/// the phase is supplied directly — the same stub change_password_test.dart and
/// mfa_enroll_test.dart use.
///
/// [reload] is overridden rather than left to the real one: the proof is written by the Edge
/// Function with the service role, so the ONLY way this app learns about it is by re-reading the
/// profile row. Modelling that here is what lets the banner-disappears assertion be about the
/// app's behaviour instead of about Supabase being absent.
class _StubAuth extends AuthController {
  _StubAuth(this._phase, {this.afterReload});

  final AuthPhase _phase;
  final AuthPhase? afterReload;
  int reloads = 0;

  @override
  Future<AuthPhase> build() async => _phase;

  @override
  Future<void> reload() async {
    reloads++;
    if (afterReload != null) state = AsyncData(afterReload!);
  }
}

/// A stand-in for GoTrue (the send) and the Edge Function (the check).
class _FakeVerification implements EmailVerificationService {
  _FakeVerification({
    this.resendAfter = const Duration(seconds: 60),
    this.sendFailure,
    this.statusFailure,
  });

  /// Flipped when the "user" opens the link. Everything about this feature is downstream of
  /// this one boolean changing while the app is not looking.
  bool verified = false;

  Duration resendAfter;
  VerificationFailure? sendFailure;
  VerificationFailure? statusFailure;

  int sends = 0;
  int statusCalls = 0;
  final List<String> sentTo = <String>[];

  @override
  Future<VerificationStatus> status() async {
    statusCalls++;
    final failure = statusFailure;
    if (failure != null) throw failure;
    return VerificationStatus(
      email: 'owner@example.com',
      verified: verified,
      required_: !verified,
      verifiedAt: verified ? DateTime.utc(2026, 9, 1, 10, 30) : null,
    );
  }

  @override
  Future<SendOutcome> sendLink(String email) async {
    sends++;
    sentTo.add(email);
    final failure = sendFailure;
    if (failure != null) throw failure;
    return SendOutcome(email: email, resendAfter: resendAfter);
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeVerification fake, {
  _StubAuth? auth,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        emailVerificationServiceProvider.overrideWithValue(fake),
        authControllerProvider.overrideWith(
          () => auth ?? _StubAuth(const AuthSignedIn(_unverified)),
        ),
      ],
      child: MaterialApp(
        theme: NivoraTheme.dark(),
        home: const VerifyEmailScreen(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
  await _settle(tester);
}

/// The banner in isolation, on a throwaway host, so "is it drawn" is not entangled with a role
/// dashboard's own data providers.
Future<void> _pumpBanner(
  WidgetTester tester,
  NivoraSession session, {
  _FakeVerification? fake,
  _StubAuth? auth,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        emailVerificationServiceProvider.overrideWithValue(fake ?? _FakeVerification()),
        authControllerProvider.overrideWith(
          () => auth ?? _StubAuth(AuthSignedIn(session)),
        ),
      ],
      child: MaterialApp(
        theme: NivoraTheme.dark(),
        home: const Scaffold(body: VerifyEmailBanner()),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
  await _settle(tester);
}

/// Frames, not `pumpAndSettle`: a busy button holds a [CircularProgressIndicator] and the
/// cooldown holds a periodic [Timer], both of which schedule frames forever, so settling would
/// time out on exactly the states worth testing.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Leave the app and come back — the only signal this feature gets that a link may have been
/// opened.
///
/// Two hops rather than one because SchedulerBinding short-circuits a transition to the state it
/// is already in (`if (lifecycleState == state) return;`), so pushing `resumed` at a binding that
/// already believes it is resumed would dispatch nothing and quietly pass a test that proves
/// nothing.
Future<void> _leaveAndReturn(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await _settle(tester);
}

Finder _openedButton() => find.widgetWithText(FilledButton, 'I have opened the link');
Finder _resendButton() => find.widgetWithText(TextButton, 'Send it again');

/// The number the countdown is currently showing, or null when the button is live again.
///
/// Read rather than hardcoded because [_settle] pumps real frames before the assertion runs, so
/// a 60s cooldown is legitimately showing 59 by the time it is looked at. Asserting the exact
/// opening number would be pinning the test helper's frame budget, not the feature; what
/// matters is that a countdown exists, that it decreases in real seconds, and that it ends.
int? _countdown(WidgetTester tester) {
  for (final w in tester.widgetList<Text>(find.textContaining('Send again in '))) {
    final match = RegExp(r'Send again in (\d+)s').firstMatch(w.data ?? '');
    if (match != null) return int.parse(match.group(1)!);
  }
  return null;
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════════════════
  // 1. ROUTING — verified and unverified route IDENTICALLY
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('routing does not divert on an unproved address', () {
    test('an unverified account is sent to its role home, exactly like a verified one', () {
      final home = roleHome[UserRole.owner]!;

      expect(
        resolveRedirect(
          phase: const AsyncData(AuthSignedIn(_unverified)),
          here: splashRoute,
        ),
        home,
      );
      expect(
        resolveRedirect(
          phase: AsyncData(AuthSignedIn(_verified)),
          here: splashRoute,
        ),
        home,
        reason: 'proving the address must not change where the user lands',
      );
    });

    test('and it STAYS there — nothing pulls it onto a verification screen', () {
      final home = roleHome[UserRole.owner]!;
      expect(
        resolveRedirect(phase: const AsyncData(AuthSignedIn(_unverified)), here: home),
        isNull,
        reason: 'verification is a requirement, not a trap: the link may be going to a '
            'typo\'d address, and a redirect would be an app with no way back',
      );
    });

    test('a phone-login resident is never diverted either', () {
      final home = roleHome[UserRole.student]!;
      expect(
        resolveRedirect(
          phase: const AsyncData(AuthSignedIn(_phoneOnlyStudent)),
          here: home,
        ),
        isNull,
      );
    });

    test('an owed password change still outranks everything', () {
      // The regression this guards: "verification must come first" being read as a licence to
      // reorder the onboarding steps. The password change is the one that CAN always be
      // completed by the person standing there, so it stays first.
      const owes = NivoraSession(
        userId: _userId,
        role: UserRole.owner,
        fullName: 'A Real Owner',
        status: 'active',
        mustChangePassword: true,
        email: 'owner@example.com',
      );
      expect(
        resolveRedirect(phase: const AsyncData(AuthSignedIn(owes)), here: splashRoute),
        changePasswordRoute,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // 2. WHO IS ASKED — decided by the ADDRESS, never by the role
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('the banner asks exactly the accounts that can answer', () {
    testWidgets('an unverified owner is asked, and the ask names the address', (tester) async {
      await _pumpBanner(tester, _unverified);

      expect(find.text('Verify your email'), findsOneWidget);
      expect(
        find.textContaining('owner@example.com'),
        findsOneWidget,
        reason: 'showing the address is the only way a typo ever gets noticed',
      );
      expect(find.widgetWithText(FilledButton, 'Verify now'), findsOneWidget);
    });

    testWidgets('a verified account is not asked again', (tester) async {
      await _pumpBanner(tester, _verified);

      expect(find.text('Verify your email'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('a phone-login resident is never asked for a proof they cannot produce',
        (tester) async {
      await _pumpBanner(tester, _phoneOnlyStudent);

      // No mail server accepts @student.hostelpro.local. Asking would be a permanent nag for
      // something that can never be done.
      expect(find.text('Verify your email'), findsNothing);
    });

    testWidgets('a resident WITH a real email is asked exactly like an owner', (tester) async {
      await _pumpBanner(tester, _emailStudent);

      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.textContaining('resident@example.com'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // 3. THE LINK — sent once, opened elsewhere, confirmed by the server
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('sending and confirming the link', () {
    testWidgets('the screen sends one link on open, to the address on the account',
        (tester) async {
      final fake = _FakeVerification();
      await _pumpScreen(tester, fake);

      expect(fake.sends, 1, reason: 'the user arrived by tapping "Verify now" — asking them '
          'to tap "Send" for what they just asked for is a step with no decision in it');
      expect(
        fake.sentTo,
        ['owner@example.com'],
        reason: 'the address mailed is the address on public.users — the one the banner shows '
            'and the one the proof is stamped against. Mailing anything else would prove an '
            'address the stamp is not about',
      );
      expect(find.textContaining('owner@example.com'), findsOneWidget);
      expect(find.textContaining('confirmation link'), findsOneWidget);
    });

    testWidgets('nothing on this screen asks for a code any more', (tester) async {
      // The OTP UI is deleted, not hidden. Two ways to prove one thing is how one of them
      // rots — and a stale six-digit field would be an instruction to do something the server
      // no longer accepts.
      final fake = _FakeVerification();
      await _pumpScreen(tester, fake);

      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('6-digit'), findsNothing);
      expect(find.textContaining('code'), findsNothing);
    });

    testWidgets('"I have opened the link" asks the SERVER, and a proof clears the screen',
        (tester) async {
      final fake = _FakeVerification()..verified = true;
      final auth = _StubAuth(
        const AuthSignedIn(_unverified),
        afterReload: AuthSignedIn(_verified),
      );
      await _pumpScreen(tester, fake, auth: auth);

      await tester.tap(_openedButton());
      await _settle(tester);

      expect(fake.statusCalls, greaterThanOrEqualTo(1));
      expect(find.text('Email verified'), findsOneWidget);
      expect(
        auth.reloads,
        1,
        reason: 'the proof is written by the service role, so nothing in this app would ever '
            'notice it without a re-read — the banner would sit there after the link was taken',
      );
    });

    testWidgets('a link that has NOT been opened says so, and never claims success',
        (tester) async {
      // The failure this prevents: believing the button instead of the server. The user tapping
      // "I have opened the link" is a claim, not a proof; only the Edge Function has seen
      // GoTrue's record of the click.
      final fake = _FakeVerification();
      await _pumpScreen(tester, fake);

      await tester.tap(_openedButton());
      await _settle(tester);

      expect(find.textContaining('Not confirmed yet'), findsOneWidget);
      expect(find.text('Email verified'), findsNothing);
    });

    testWidgets('a check the user ASKED for reports its failure', (tester) async {
      // The resume check is silent by design. This one must not be: the user pressed a button
      // and is owed an answer, and "nothing happened" is the one answer that teaches them
      // nothing.
      final fake = _FakeVerification(
        statusFailure: const VerificationFailure(
          'The Nivora server did not answer. Your link still works — open it and come back.',
        ),
      );
      await _pumpScreen(tester, fake);

      await tester.tap(_openedButton());
      await _settle(tester);

      expect(find.textContaining('did not answer'), findsOneWidget);
      expect(find.text('Email verified'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // 4. THE RE-CHECK ON RESUME — the whole reason a link is harder than a code
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('returning to the app is the completion signal', () {
    testWidgets('the screen re-checks on resume and clears itself', (tester) async {
      final fake = _FakeVerification();
      final auth = _StubAuth(
        const AuthSignedIn(_unverified),
        afterReload: AuthSignedIn(_verified),
      );
      await _pumpScreen(tester, fake, auth: auth);
      expect(find.text('Email verified'), findsNothing);

      // The user leaves to their mail app and opens the link. Nothing tells the app.
      fake.verified = true;
      await _leaveAndReturn(tester);

      expect(find.text('Email verified'), findsOneWidget);
      expect(auth.reloads, 1);
    });

    testWidgets('the BANNER re-checks too, and disappears', (tester) async {
      // The case the screen alone would miss, and it is the common one: the user taps the link
      // in their inbox and comes straight back to their home screen. They never open the
      // verification screen at all, so if only that screen listened, the banner would sit there
      // asking for something they had already given.
      final fake = _FakeVerification()..verified = true;
      final auth = _StubAuth(
        const AuthSignedIn(_unverified),
        afterReload: AuthSignedIn(_verified),
      );
      await _pumpBanner(tester, _unverified, fake: fake, auth: auth);
      expect(find.text('Verify your email'), findsOneWidget);

      await _leaveAndReturn(tester);

      expect(fake.statusCalls, 1);
      expect(auth.reloads, 1);
      expect(find.text('Verify your email'), findsNothing);
    });

    testWidgets('a verified account does not ask the server on resume', (tester) async {
      // One call per resume, forever, on every home screen, for every user who has already
      // finished — on a free-tier instance that flips to Unhealthy at ~72% RAM. The cheapest
      // request is the one that is not sent.
      final fake = _FakeVerification();
      await _pumpBanner(tester, _verified, fake: fake);

      await _leaveAndReturn(tester);

      expect(fake.statusCalls, 0);
    });

    testWidgets('a phone-login resident never asks either', (tester) async {
      final fake = _FakeVerification();
      await _pumpBanner(tester, _phoneOnlyStudent, fake: fake);

      await _leaveAndReturn(tester);

      expect(fake.statusCalls, 0);
    });

    testWidgets('a re-check that fails leaves the banner and says nothing', (tester) async {
      // A resume-time error is an accusation aimed at someone who has done nothing wrong, on a
      // screen they did not open, about a request they did not make. The banner simply stays.
      final fake = _FakeVerification(
        statusFailure: const VerificationFailure('Cannot reach Nivora.'),
      );
      await _pumpBanner(tester, _unverified, fake: fake);

      await _leaveAndReturn(tester);

      expect(fake.statusCalls, 1, reason: 'it did try');
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.textContaining('Cannot reach Nivora'), findsNothing);
    });

    testWidgets('resuming does NOT send another link', (tester) async {
      // Resume fires on every task-switch, every notification pull-down, every unlock. If it
      // sent mail, one afternoon of ordinary phone use would spend the project's hourly
      // allowance and every other user's link would bounce off it.
      final fake = _FakeVerification();
      await _pumpScreen(tester, fake);
      expect(fake.sends, 1);

      await _leaveAndReturn(tester);
      await _leaveAndReturn(tester);

      expect(fake.sends, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // 5. THE RESEND COOLDOWN
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('the resend cooldown', () {
    testWidgets('is armed by the first send and counts down in seconds', (tester) async {
      final fake = _FakeVerification(resendAfter: const Duration(seconds: 60));
      await _pumpScreen(tester, fake);

      // Disabled, and it says how long rather than just going grey.
      expect(_resendButton(), findsNothing);

      final opening = _countdown(tester);
      expect(opening, isNotNull);
      expect(opening, greaterThan(50), reason: 'a 60s cooldown was just armed');

      final resend = find.widgetWithText(TextButton, 'Send again in ${opening}s');
      expect(tester.widget<TextButton>(resend).onPressed, isNull);

      // Real seconds, not a spinner that happens to be there: three seconds of frames take
      // exactly three off the number.
      await tester.pump(const Duration(seconds: 3));
      expect(_countdown(tester), opening! - 3);

      // The whole point: a second send is not merely discouraged, it did not happen.
      expect(fake.sends, 1);
    });

    testWidgets('re-arms the button when it elapses, and a resend then works', (tester) async {
      final fake = _FakeVerification(resendAfter: const Duration(seconds: 3));
      await _pumpScreen(tester, fake);

      final opening = _countdown(tester);
      expect(opening, isNotNull, reason: 'the send armed a cooldown');
      expect(
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Send again in ${opening}s'))
            .onPressed,
        isNull,
      );

      await tester.pump(const Duration(seconds: 4));
      expect(_countdown(tester), isNull, reason: 'the countdown finished');
      expect(_resendButton(), findsOneWidget);
      expect(tester.widget<TextButton>(_resendButton()).onPressed, isNotNull);

      await tester.tap(_resendButton());
      await _settle(tester);
      expect(fake.sends, 2);
    });

    testWidgets('the confirm button stays live while resend is throttled', (tester) async {
      // The bug this prevents, restated from the code flow it replaced: a throttled RESEND does
      // not mean the person has nothing to confirm. It usually means a link is sitting in their
      // inbox and they tapped the button before reading it. Disabling the confirm button would
      // be refusing the answer because we would not repeat the question.
      final fake = _FakeVerification(resendAfter: const Duration(seconds: 60))..verified = true;
      await _pumpScreen(tester, fake);

      expect(_resendButton(), findsNothing, reason: 'resend really is throttled');
      expect(tester.widget<FilledButton>(_openedButton()).onPressed, isNotNull);

      await tester.tap(_openedButton());
      await _settle(tester);

      expect(find.text('Email verified'), findsOneWidget);
    });

    testWidgets('a server throttle arms the countdown from the SERVER\'s own wait',
        (tester) async {
      // GoTrue is the thing that will refuse an early resend, and it says how long in the
      // refusal ("you can only request this once every 45 seconds"). That number is the one the
      // button comes back on — not a constant guessed on the phone.
      final fake = _FakeVerification(
        sendFailure: const VerificationFailure(
          'A link was just sent. Check your inbox — and your spam folder — before asking for '
          'another.',
          retryAfter: Duration(seconds: 45),
        ),
      );
      await _pumpScreen(tester, fake);

      expect(find.textContaining('A link was just sent'), findsOneWidget);

      // 45, from the failure — NOT the 60 the client would have guessed on its own.
      final armed = _countdown(tester);
      expect(armed, isNotNull);
      expect(armed, lessThanOrEqualTo(45));
      expect(armed, greaterThan(35));
    });

    testWidgets('an operator fault is not blamed on the person holding the phone',
        (tester) async {
      // CAPTCHA refusing /auth/v1/otp, or a project with no mail sender configured. "Try again"
      // is the wrong advice for both: no amount of retrying fixes a dashboard toggle, and
      // telling a resident to check their connection sends them chasing a fault they cannot
      // reach.
      final fake = _FakeVerification(
        sendFailure: const VerificationFailure(
          'Nivora cannot send verification links yet: CAPTCHA protection is switched on.',
          operatorFault: true,
        ),
      );
      await _pumpScreen(tester, fake);

      expect(find.textContaining('CAPTCHA protection'), findsOneWidget);
      expect(
        find.textContaining('not something you can fix from here'),
        findsOneWidget,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // 6. THE DEAD ESCAPE HATCH, AND THE FACT THAT IT IS GONE
  // ═══════════════════════════════════════════════════════════════════════════════════════
  //
  // This section used to hold five tests for an unfoldable panel — "The link opened a page that
  // would not load" — carrying the Site URL and Redirect URL for an administrator to paste into
  // the Supabase dashboard. It was written for a real fault: the project's Site URL was
  // http://localhost:3000, GoTrue silently substituted it, and a REAL, ACCEPTED link landed the
  // owner's phone on ERR_CONNECTION_REFUSED.
  //
  // The owner fixed the URL configuration on 2026-09-01. Two things follow, and the second is
  // why this is a test rather than a deletion:
  //
  //   · Instructions for a fault that no longer exists are not neutral. The panel told a
  //     resident, unprompted, that something was wrong with a flow that works.
  //   · Its headline — "Nothing is wrong with your link." — was UNCONDITIONAL, and false for an
  //     expired or already-used link, which is exactly the case where a page that will not load
  //     does mean the click failed. Nothing may put that claim back.
  //
  // So what is asserted here is an absence, and the coherence of what is left: four controls
  // that still have to make sense together.

  group('the removed setup panel stays removed', () {
    testWidgets('no control, no panel, and no claim about the landing page', (tester) async {
      await _pumpScreen(tester, _FakeVerification());

      expect(find.text('The link opened a page that would not load'), findsNothing);
      expect(find.text('Hide setup details'), findsNothing);
      expect(find.text('Nothing is wrong with your link.'), findsNothing);
      expect(find.textContaining('URL Configuration'), findsNothing);
      expect(find.textContaining('may show an error or not load'), findsNothing);

      // The instruction that remains says what to DO — including the return trip, which is the
      // step people skip — without predicting how the landing page will behave.
      expect(find.textContaining('come back to Nivora'), findsOneWidget);
    });

    testWidgets('a check that comes back "not yet" opens nothing and points at no panel',
        (tester) async {
      // "Not yet" is what used to unfold the panel, unasked. It must now answer with the next
      // useful action instead — the newest link, or a new email — and nothing else.
      final fake = _FakeVerification();
      await _pumpScreen(tester, fake);

      await tester.tap(_openedButton());
      await _settle(tester);

      expect(find.textContaining('Not confirmed yet'), findsOneWidget);
      expect(find.textContaining('setup note'), findsNothing);
      expect(find.text('Nothing is wrong with your link.'), findsNothing);
      expect(find.textContaining('Only the newest link works'), findsOneWidget);
    });

    testWidgets('an operator fault still says whose fault it is, with no panel behind it',
        (tester) async {
      // The operator-fault sentence is NOT part of what was removed: it is about a send that
      // failed, it is true when it is shown, and "try again" is the wrong advice for it.
      final fake = _FakeVerification(
        sendFailure: const VerificationFailure(
          'Nivora cannot send verification links yet: CAPTCHA protection is switched on.',
          operatorFault: true,
        ),
      );
      await _pumpScreen(tester, fake);

      expect(find.textContaining('not something you can fix from here'), findsOneWidget);
      expect(find.text('Nothing is wrong with your link.'), findsNothing);
      expect(find.text('The link opened a page that would not load'), findsNothing);
    });

    testWidgets('the four things left on the screen still make sense together', (tester) async {
      // Section 4's rule, restated against the screen as it now stands: whatever it is saying,
      // both escapes stay on it. This assertion outlived the panel it was written for.
      final fake = _FakeVerification();
      await _pumpScreen(tester, fake);
      await tester.tap(_openedButton());
      await _settle(tester);

      expect(find.text('Check your email'), findsOneWidget);
      expect(_openedButton(), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'I will do this later'), findsOneWidget);

      // The resend, in whichever of its two forms it is in. The automatic first send has just
      // armed the cooldown, so it reads "Send again in Ns" here — asserting the live label
      // would be asserting the fixture's timing, not the screen's coherence.
      expect(
        _resendButton().evaluate().isNotEmpty || _countdown(tester) != null,
        isTrue,
        reason: 'the resend is on the screen, live or counting down',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // 7. THE SETUP NOTE THAT IS EARNED, AND THE ONE FIELD IT NAMES
  // ═══════════════════════════════════════════════════════════════════════════════════════
  //
  // Section 6 deleted an unfoldable setup panel that was shown UNPROMPTED and claimed "Nothing
  // is wrong with your link" unconditionally. Nothing here restores it, and every assertion
  // there still holds: a screen just opened says nothing about settings, and one "not yet"
  // still answers with the next useful action and no more.
  //
  // What is added is a note that must be EARNED, because there is a real fault it is the only
  // possible report of. Measured against this project on 2026-09-01, by asking /auth/v1/verify
  // to redirect a dead token and reading the Location header back:
  //
  //   app.nivora.mobile://verify-email  ->  https://hostelpro-three.vercel.app   SUBSTITUTED
  //
  // GoTrue does not refuse a redirect that is off the allow-list; it silently swaps in the
  // Site URL. A missing dashboard entry therefore looks exactly like a working link that opens
  // the wrong thing, and NOTHING in the system can detect it — not the app, not the Edge
  // Function, not the database. A run of "the server has never seen your click" is the only
  // evidence that exists, which is why it is what the note is gated on.
  //
  // TWO in a row, not one. One is ordinary. Two is the user telling us twice.

  group('the setup note is earned, and it names one field', () {
    testWidgets('one "not yet" names no setting — slow mail is not evidence', (tester) async {
      final fake = _FakeVerification();
      await _pumpScreen(tester, fake);

      await tester.tap(_openedButton());
      await _settle(tester);

      expect(find.textContaining('Not confirmed yet'), findsOneWidget);
      expect(find.textContaining('URL Configuration'), findsNothing);
      expect(find.textContaining('Redirect URLs'), findsNothing);
    });

    testWidgets('the SECOND in a row names the field and the exact value to paste',
        (tester) async {
      final fake = _FakeVerification();
      await _pumpScreen(tester, fake);

      await tester.tap(_openedButton());
      await _settle(tester);
      await tester.tap(_openedButton());
      await _settle(tester);

      // The literal string an administrator has to paste, not a paraphrase of it. If the
      // scheme ever changes, this fails until the operator instruction changes with it.
      expect(find.textContaining('app.nivora.mobile://verify-email'), findsOneWidget);
      expect(find.textContaining('URL Configuration'), findsOneWidget);

      // Framed as somebody else's job. A resident must never read it as their homework.
      expect(find.textContaining('not something you can fix from here'), findsOneWidget);

      // And it still claims nothing about the link, and closes no exit.
      expect(find.text('Nothing is wrong with your link.'), findsNothing);
      expect(find.textContaining('Only the newest link works'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'I will do this later'), findsOneWidget);
    });

    testWidgets('a new link starts the run again — only the newest link is being asked about',
        (tester) async {
      final fake = _FakeVerification(resendAfter: Duration.zero);
      await _pumpScreen(tester, fake);

      await tester.tap(_openedButton());
      await _settle(tester);
      await tester.tap(_resendButton());
      await _settle(tester);
      await tester.tap(_openedButton());
      await _settle(tester);

      // One "not yet" since the resend, so the note has not been earned again.
      expect(find.textContaining('Not confirmed yet'), findsOneWidget);
      expect(find.textContaining('URL Configuration'), findsNothing);
    });

    testWidgets('a check that FAILED is not an answer and does not count', (tester) async {
      final fake = _FakeVerification();
      await _pumpScreen(tester, fake);

      await tester.tap(_openedButton());
      await _settle(tester);

      // A dropped request in the middle of the run. Two of these must not conjure a note about
      // a setting that may be perfectly correct.
      fake.statusFailure = const VerificationFailure('Cannot reach Nivora.');
      await tester.tap(_openedButton());
      await _settle(tester);

      fake.statusFailure = null;
      await tester.tap(_openedButton());
      await _settle(tester);

      expect(find.textContaining('Not confirmed yet'), findsOneWidget);
      expect(find.textContaining('URL Configuration'), findsNothing);
    });

    testWidgets('a proof clears the run as well as the screen', (tester) async {
      final fake = _FakeVerification();
      await _pumpScreen(tester, fake);

      await tester.tap(_openedButton());
      await _settle(tester);
      fake.verified = true;
      await tester.tap(_openedButton());
      await _settle(tester);

      expect(find.text('Email verified'), findsOneWidget);
      expect(find.textContaining('URL Configuration'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // 8. THE DEEP LINK — two halves that cannot read each other
  // ═══════════════════════════════════════════════════════════════════════════════════════
  //
  // The owner asked for it in as many words: "it has to ask to login through that link, once
  // they login through that link they have to verify". So the link comes back to a custom
  // scheme that opens Nivora, supabase_flutter exchanges the `?code=` GoTrue appends using the
  // PKCE verifier only this app holds, and the sign-in IS the proof. A browser holds no
  // verifier and can never complete that exchange, which is why no web landing page — deployed
  // or not — was ever going to be the fix.
  //
  // It depends on one string being identical in two files that cannot see one another: a Dart
  // constant and an Android manifest. Drift between them is SILENT — the link simply stops
  // opening the app and lands on the web instead, which is the exact failure being fixed here.
  // So the manifest is read and compared.

  group('the deep link the confirmation mail comes back on', () {
    /// The manifest with its XML comments removed.
    ///
    /// The comments in that file DISCUSS the filters that must not exist — an `https` scheme,
    /// an `autoVerify` App Link — by writing them out, which is exactly what makes them worth
    /// keeping and exactly what would make a grep over the raw text lie. What is asserted here
    /// is the MARKUP: what Android will actually register.
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

    test('the redirect the app asks for is the custom scheme, not a web page', () {
      expect(Env.emailConfirmRedirectUrl, 'app.nivora.mobile://verify-email');
      expect(Env.emailConfirmRedirectUrl.startsWith('http'), isFalse,
          reason: 'a browser holds no PKCE verifier and can never complete the exchange');
    });

    test('the manifest declares a VIEW filter for exactly that scheme and host', () {
      expect(manifest, contains('android.intent.action.VIEW'));
      expect(manifest, contains('android.intent.category.BROWSABLE'));
      expect(
        manifest,
        contains('android:scheme="${Env.emailLinkScheme}" '
            'android:host="${Env.emailLinkHost}"'),
        reason: 'the manifest and Env.emailConfirmRedirectUrl must name the same Uri',
      );
    });

    test('and it captures no http/https links belonging to anyone else', () {
      // An https filter without a verified Digital Asset Link would offer Nivora as a handler
      // for ordinary web URLs and put a disambiguation sheet on somebody else's links — and on
      // Android 12+ a failed autoVerify filter is never offered to the app at all. The scheme
      // AND the host are both pinned so this filter cannot widen by accident.
      expect(manifest.contains('android:scheme="https"'), isFalse);
      expect(manifest.contains('android:scheme="http"'), isFalse);
      expect(manifest.contains('android:autoVerify'), isFalse);
    });

    test('a link tapped while Nivora is running reaches the copy that is running', () {
      // Without singleTop, Android starts a SECOND MainActivity for the VIEW intent and the
      // deep-link observer in the first one never sees the code.
      expect(manifest, contains('android:launchMode="singleTop"'));
    });

    test('the operator instruction is built from those constants, not transcribed', () {
      // The one sentence shown on screen and repeated in docs/email-verification.md. It has to
      // carry the value this build actually compiled in, or it sends an administrator off to
      // paste a string that no longer matches the app.
      expect(Env.emailRedirectSetupHint, contains(Env.emailConfirmRedirectUrl));
      expect(Env.emailRedirectSetupHint, contains('Redirect URLs'));
      expect(Env.emailRedirectSetupHint, contains('Site URL does not need to change'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // 9. THE INSTRUCTION, WHICH NOW HAS TWO CASES TO COVER
  // ═══════════════════════════════════════════════════════════════════════════════════════
  //
  // Before the deep link there was one story: it opens a browser, come back. There are now two,
  // and the screen may not tell only the happy one — somebody WILL open the mail on a laptop
  // where Nivora is not installed, and a browser can never complete the exchange. That case has
  // to be named on screen, and it has to be non-fatal.

  group('the instruction covers both places a link can be opened', () {
    testWidgets('it says the phone signs you in, and that a laptop still works',
        (tester) async {
      await _pumpScreen(tester, _FakeVerification());

      expect(find.textContaining('opens Nivora and signs you in'), findsOneWidget);
      expect(find.textContaining('laptop'), findsOneWidget);
      expect(find.textContaining('come back to Nivora'), findsOneWidget);

      // The escape for the other device is the button, and it is on the screen from the start
      // rather than appearing only once something has already gone wrong.
      expect(_openedButton(), findsOneWidget);
    });

    testWidgets('and the way out stays open in every state', (tester) async {
      // Four states, one rule: this screen never dead-ends. Somebody who cannot open their mail
      // must always be able to leave a REQUIREMENT that is not a TRAP.
      final fake = _FakeVerification();
      await _pumpScreen(tester, fake);
      expect(find.widgetWithText(TextButton, 'I will do this later'), findsOneWidget);

      await tester.tap(_openedButton());
      await _settle(tester);
      expect(find.widgetWithText(TextButton, 'I will do this later'), findsOneWidget);

      fake.statusFailure = const VerificationFailure('Cannot reach Nivora.');
      await tester.tap(_openedButton());
      await _settle(tester);
      expect(find.widgetWithText(TextButton, 'I will do this later'), findsOneWidget);
      expect(_openedButton(), findsOneWidget);
    });
  });
}
