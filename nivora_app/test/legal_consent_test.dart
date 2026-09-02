// ═══════════════════════════════════════════════════════════════════════════════════════════
// THE CONSENT GATE
// ═══════════════════════════════════════════════════════════════════════════════════════════
//
// WHAT THIS FEATURE IS FOR, so that a future edit knows what it is allowed to break. NIVORA
// holds residents' names, phone numbers, permanent addresses, guardian contacts, government-ID
// scans and a payment ledger. Google Play will not list an app that handles personal data
// without a publicly reachable privacy policy, and the DPDP Act 2023 requires notice and
// consent before that processing begins. The gate is the second half of that, and the tests
// below are the claims it makes:
//
//   1. It BLOCKS. Nobody reaches the product without agreeing — proven per role in
//      role_routing_test.dart, through the real router.
//   2. It RECORDS what can be evidenced: who, WHICH VERSION, and when.
//   3. It ASKS AGAIN when the documents change, which is what the version is for.
//   4. Declining is a REAL option that neither strands the person nor pretends to be one.
//   5. Its four states stay four states: checking, not agreed, failed, refused.
//
// WHAT IS NOT TESTED HERE AND CANNOT BE: that public.legal_versions actually holds the version
// this build ships. `accept_legal_terms()` refuses a version it has never heard of, so the
// migration must land before a build carrying that string does. That is a deployment order, not
// an assertion — see legal_documents.dart and db/migrations/2026-09-02-legal-consent.sql §4.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/features/legal/consent_gate.dart';
import 'package:mobile/features/legal/legal_documents.dart';
import 'package:mobile/features/legal/legal_providers.dart';
import 'package:mobile/features/legal/legal_screen.dart';

import 'fake_consent.dart';

class _StubAuth extends AuthController {
  _StubAuth(this._phase);
  final AuthPhase _phase;
  @override
  Future<AuthPhase> build() async => _phase;
}

const _session = NivoraSession(
  userId: 'user-1',
  role: UserRole.student,
  fullName: 'Meera Nair',
  status: 'active',
  mustChangePassword: false,
  hostelId: 'hostel-1',
);

/// The thing behind the gate. A distinct string so "did they get in" is unambiguous.
const _behindTheGate = 'THE PRODUCT';

void main() {
  Future<void> pumpGate(WidgetTester tester, FakeConsentStore store) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _StubAuth(const AuthSignedIn(_session))),
          legalConsentStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: NivoraTheme.light(),
          debugShowCheckedModeBanner: false,
          home: const ConsentGate(child: Scaffold(body: Text(_behindTheGate))),
        ),
      ),
    );
    // Let the auth notifier and the consent future resolve. pumpAndSettle would hang on the
    // gate's own CircularProgressIndicator, which never stops animating.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> agree(WidgetTester tester) async {
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Agree and continue'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('it blocks, and only agreement unblocks it', () {
    testWidgets('an agreed user never sees the gate at all', (tester) async {
      final store = FakeConsentStore.accepted();
      await pumpGate(tester, store);

      expect(find.text(_behindTheGate), findsOneWidget);
      expect(find.text('Please read and agree'), findsNothing);
      expect(store.writes, 0, reason: 'agreeing again for somebody who already had is a write '
          'nobody asked for');
    });

    testWidgets('a first-run user is stopped, and the product is not behind them',
        (tester) async {
      await pumpGate(tester, FakeConsentStore.notAccepted());

      expect(find.text(_behindTheGate), findsNothing);
      expect(find.text('Please read and agree'), findsOneWidget);
    });

    testWidgets('the button is inert until the box is ticked', (tester) async {
      await pumpGate(tester, FakeConsentStore.notAccepted());

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Agree and continue'),
      );
      expect(button.onPressed, isNull,
          reason: 'a consent that can be given by a thumb on the way past is not a consent');
    });

    testWidgets('the box starts unticked — a pre-ticked consent is not consent',
        (tester) async {
      await pumpGate(tester, FakeConsentStore.notAccepted());

      final box = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(box.value, isFalse);
    });

    testWidgets('ticking and agreeing lets them through', (tester) async {
      final store = FakeConsentStore.notAccepted();
      await pumpGate(tester, store);
      await agree(tester);

      expect(store.writes, 1);
      expect(find.text(_behindTheGate), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('what gets recorded is what can be evidenced', () {
    testWidgets('the version agreed to is the version this build showed', (tester) async {
      final store = FakeConsentStore.notAccepted();
      await pumpGate(tester, store);
      await agree(tester);

      expect(store.lastVersionWritten, kLegalVersion,
          reason: 'an acceptance recorded against the wrong version evidences nothing');
      expect(store.lastSurface, 'android');
    });

    testWidgets('the question asked is about this build version, not any version',
        (tester) async {
      final store = FakeConsentStore.accepted();
      await pumpGate(tester, store);

      expect(store.versionsRead, isNotEmpty);
      expect(store.versionsRead.every((v) => v == kLegalVersion), isTrue);
    });

    testWidgets('the documents on screen are the ones being agreed to', (tester) async {
      await pumpGate(tester, FakeConsentStore.notAccepted());

      // Both documents are reachable from the gate, and the one on screen carries the version
      // that is about to be recorded.
      expect(find.text('Privacy Policy'), findsWidgets);
      expect(find.text('Terms of Use'), findsWidgets);
      expect(find.textContaining(kLegalVersion), findsWidgets);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('when the documents change, consent is asked again', () {
    testWidgets('an acceptance of an earlier version does not carry over', (tester) async {
      // A real user of a real earlier build. This is the whole reason acceptance is stored per
      // version rather than as a boolean: bumping kLegalVersion has to put the new text in
      // front of everybody, and a `has_accepted` flag would silently move them onto a policy
      // they never saw.
      final store = FakeConsentStore.acceptedOnly('2020-01-01');
      await pumpGate(tester, store);

      expect(find.text(_behindTheGate), findsNothing);
      expect(find.text('Please read and agree'), findsOneWidget);
    });

    testWidgets('agreeing again records the NEW version, leaving the old one alone',
        (tester) async {
      final store = FakeConsentStore.acceptedOnly('2020-01-01');
      await pumpGate(tester, store);
      await agree(tester);

      expect(store.lastVersionWritten, kLegalVersion);
      expect(find.text(_behindTheGate), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('declining is a real option and does not strand anybody', () {
    testWidgets('it explains rather than silently doing nothing', (tester) async {
      final store = FakeConsentStore.notAccepted();
      await pumpGate(tester, store);

      await tester.tap(find.text('I do not agree'));
      await tester.pump();

      expect(find.text('NIVORA cannot be used without agreeing'), findsOneWidget);
      expect(store.writes, 0, reason: 'declining must never write an acceptance');
      expect(find.text(_behindTheGate), findsNothing);
    });

    testWidgets('it offers the door — and the way back', (tester) async {
      await pumpGate(tester, FakeConsentStore.notAccepted());
      await tester.tap(find.text('I do not agree'));
      await tester.pump();

      // Both, and both matter. Without Sign out the screen is a trap; without the way back a
      // mis-tap costs somebody their session.
      expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Back to the documents'), findsOneWidget);
    });

    testWidgets('changing their mind returns them to the documents, and clears the tick',
        (tester) async {
      await pumpGate(tester, FakeConsentStore.notAccepted());

      // Tick it FIRST, so this proves the tick is cleared rather than merely never set.
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      await tester.tap(find.text('I do not agree'));
      await tester.pump();
      await tester.tap(find.text('Back to the documents'));
      await tester.pump();

      expect(find.text('Please read and agree'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse,
          reason: 'somebody who declined and came back is deciding again, and should not find '
              'the decision already made and one stray tap from being final');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  //
  // LOADING, EMPTY, FAILED and REFUSED are four distinct states everywhere in this app (see
  // data/models/failure.dart). The gate is the one screen every user meets, so collapsing two
  // of them here would be the rule broken in the most visible place there is.
  group('the four states stay four states', () {
    testWidgets('CHECKING is a spinner, not a silently-open door', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => _StubAuth(const AuthSignedIn(_session))),
            legalConsentStoreProvider.overrideWithValue(FakeConsentStore.notAccepted()),
          ],
          child: MaterialApp(
            theme: NivoraTheme.light(),
            home: const ConsentGate(child: Scaffold(body: Text(_behindTheGate))),
          ),
        ),
      );
      // One frame: the future has not resolved.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_behindTheGate), findsNothing,
          reason: 'the product must not be readable while the check is still in flight');
    });

    testWidgets('FAILED offers a retry, and does not let them in', (tester) async {
      await pumpGate(
        tester,
        FakeConsentStore.failing(const OfflineFailure('Cannot reach Nivora.')),
      );

      expect(find.text('Cannot check your agreement'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget);
      expect(find.text(_behindTheGate), findsNothing);
    });

    testWidgets('a retry that succeeds gets them to the gate', (tester) async {
      // The ordinary "my train went into a tunnel" case: it must be recoverable without
      // signing out and back in.
      //
      // THE STORE IS SICK UNTIL THE TEST SAYS OTHERWISE, rather than failing a fixed number of
      // times, and that is the point. Riverpod 3 retries a failed provider on its own with a
      // backoff, so a store that failed once and then healed would be rescued by that schedule
      // and this test would pass while proving nothing about the button. Holding it failed
      // until the moment of the tap — with no pump between healing it and tapping, so no timer
      // can fire in between — makes the Try again button the only thing that can have caused
      // the recovery.
      final flaky = _SickStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => _StubAuth(const AuthSignedIn(_session))),
            legalConsentStoreProvider.overrideWithValue(flaky),
          ],
          child: MaterialApp(
            theme: NivoraTheme.light(),
            home: const ConsentGate(child: Scaffold(body: Text(_behindTheGate))),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Cannot check your agreement'), findsOneWidget);

      flaky.healthy = true;
      await tester.tap(find.text('Try again'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Please read and agree'), findsOneWidget);
    });

    testWidgets('REFUSED is told apart from FAILED — no retry, sign in again', (tester) async {
      // A dead credential. Retrying the same dead token cannot help, so no Try again button is
      // drawn; the one action that helps is getting a new session. This is why the repository
      // calls requireLiveSession() before the read: without it an anonymous request would come
      // back empty and be mistaken for "has never agreed", and the app would ask somebody to
      // agree and then refuse to accept it.
      await pumpGate(
        tester,
        FakeConsentStore.failing(
          const SignedOutFailure('You are not signed in any more.'),
        ),
      );

      expect(find.text('Your session has ended'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget);
      expect(find.text(_behindTheGate), findsNothing);
    });

    testWidgets('a write that fails keeps them at the gate and says why', (tester) async {
      final store = FakeConsentStore(
        writeError: const OfflineFailure('Cannot reach Nivora. Check your connection.'),
      );
      await pumpGate(tester, store);
      await agree(tester);

      expect(find.text(_behindTheGate), findsNothing,
          reason: 'a failed write must not be reported as an acceptance');
      expect(find.textContaining('Cannot reach Nivora'), findsWidgets);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('the documents are readable outside the gate', () {
    testWidgets('both open, and carry real text rather than a promise of it', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: NivoraTheme.light(),
        home: const LegalScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Terms & Privacy'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsWidgets);

      await tester.tap(find.text('Terms of Use').last);
      await tester.pumpAndSettle();
      expect(find.text('Who these terms bind'), findsOneWidget);
    });

    testWidgets('the privacy policy names what is actually collected', (tester) async {
      // Not a wording test — a "this is a real document" test. A policy that does not mention
      // the ID scan is not describing THIS app, and an ID scan is the highest-consequence
      // thing NIVORA holds.
      await tester.pumpWidget(MaterialApp(
        theme: NivoraTheme.light(),
        home: const LegalScreen(initial: 'privacy'),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('identity document', findRichText: true), findsWidgets);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  //
  // THE ONE COUPLING DART CAN CHECK.
  //
  // The same version string lives in three places (see legal_documents.dart): the Next.js pages
  // that publish the documents, this app, and a row in public.legal_versions. Nothing can check
  // the third from here. The first two are both files in this repository, so they can be — and
  // a version bumped on the web while the app still records the old one means every acceptance
  // taken by the app points at text nobody published.
  group('the app and the published pages agree on the version', () {
    test('kLegalVersion matches LEGAL_VERSION in lib/legal-config.ts', () {
      final config = File('../lib/legal-config.ts');
      expect(
        config.existsSync(),
        isTrue,
        reason: 'lib/legal-config.ts is not where this test expects it. The app version and the '
            'published version can no longer be cross-checked — find it and fix this path '
            'rather than deleting the check.',
      );

      final match = RegExp(r'''LEGAL_VERSION\s*=\s*["']([^"']+)["']''')
          .firstMatch(config.readAsStringSync());
      expect(match, isNotNull,
          reason: 'lib/legal-config.ts no longer exports a LEGAL_VERSION this test can read');
      expect(match!.group(1), kLegalVersion,
          reason: 'the app records acceptances against $kLegalVersion but the web pages publish '
              '${match.group(1)} — one of them is showing text the other never agreed to');
    });
  });
}

/// Fails every read until [healthy] is set. Written here rather than in fake_consent.dart
/// because only the retry test wants it.
class _SickStore extends FakeConsentStore {
  _SickStore();
  bool healthy = false;

  @override
  Future<DateTime?> acceptedAt({
    required String userId,
    String version = kLegalVersion,
  }) async {
    if (!healthy) throw const OfflineFailure('Cannot reach Nivora.');
    return null;
  }
}
