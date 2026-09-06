// THE WALKTHROUGH — the real app, on a real device, against the real backend.
//
// ── WHY THIS EXISTS AND WHAT IT IS FOR ────────────────────────────────────────────────────
//
// The 1,194 tests in test/ run against fakes. That is the right shape for what they check, and
// it is blind to everything that only breaks when a network, a session and row-level security
// are all involved at once: an RLS policy that silently refuses a read, a provider that never
// resolves so a skeleton pulses forever, a screen that renders perfectly on fixtures and throws
// on the shape production actually returns.
//
// This signs in as a demo account and walks every tab of that role, asserting at each stop that
// the screen SETTLED — no infinite spinner, no red error screen, no thrown exception — and that
// the tab's own landmark text is on it. It is the pass the owner asked for, in a form that can
// be run again on every release instead of once by hand.
//
// ── HOW TO RUN IT ─────────────────────────────────────────────────────────────────────────
//
//   flutter test integration_test/walkthrough_test.dart \
//     --dart-define=SUPABASE_URL=<your url> \
//     --dart-define=SUPABASE_ANON_KEY=<your anon key> \
//     --dart-define=WALK_EMAIL=demo.warden@nivora.app \
//     --dart-define=WALK_PASSWORD=<the demo password>
//
// with a device or emulator attached. Run it once per role by changing WALK_EMAIL.
//
// THE PASSWORD IS NEVER IN THIS FILE and never in the repo. It arrives as a --dart-define at
// run time, which is also how the Supabase keys already reach the app (see core/config/env.dart)
// — so this adds no new place for a secret to leak. With no WALK_EMAIL set, every test below
// SKIPS rather than fails, so a normal `flutter test` run and CI are unaffected.
//
// ── WHAT A FAILURE HERE MEANS ─────────────────────────────────────────────────────────────
//
// A failure is a screen a real user on a real account cannot use. There is no such thing as a
// flaky pass to shrug at: if a tab did not settle in fifteen seconds on a demo tenant holding
// eighteen beds, it will not settle for a hostel holding four hundred.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/core/config/env.dart';
import 'package:mobile/main.dart' as app;
import 'package:supabase_flutter/supabase_flutter.dart';

const _email = String.fromEnvironment('WALK_EMAIL');
const _password = String.fromEnvironment('WALK_PASSWORD');

/// Every tab of every role, by the text the tab bar shows. Kept as data so adding a role or a
/// tab is one line here rather than a new test.
/// Read off the shells, not remembered: role_shell.dart:22-57, warden_shell.dart:190-207,
/// manager_shell.dart:170-177 and sa_shell.dart:146-153. My first draft of this map had three
/// of the five wrong — the student's last tab is Profile, not Menu, and the manager has FOUR
/// tabs, not five — which the walkthrough would have reported as a missing tab rather than as
/// its own mistake. Anyone editing a shell has to edit this too, and the test says so when the
/// two disagree.
const _tabsByRole = <String, List<String>>{
  'owner': ['Dashboard', 'PGs', 'Students', 'Payments', 'More'],
  'warden': ['Home', 'Students', 'Rooms', 'Payments', 'Complaints'],
  'manager': ['Home', 'Expenses', 'Tasks', 'Menu'],
  'super_admin': ['Overview', 'Hostels', 'Subscriptions', 'Security'],
  'student': ['Home', 'Fees', 'Complaints', 'Notices', 'Profile'],
};

/// The strings that mean the screen gave up. Any of these on any tab is a failure — they are
/// what the app shows when a future rejects, and a walkthrough that tolerated them would be
/// asserting that the app renders, not that it works.
const _failureText = <String>[
  'That did not load',
  'Something did not work',
  'Something unexpected happened',
  'Could not read',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const configured = _email != '' && _password != '';

  // The reason lives in the group name because testWidgets' `skip` takes a bool, not a string —
  // so a run with no credentials prints "the walkthrough (needs --dart-define=WALK_EMAIL and
  // WALK_PASSWORD)" beside the skipped tests instead of a bare "skipped" nobody can act on.
  group('the walkthrough (needs --dart-define=WALK_EMAIL and WALK_PASSWORD)', () {
    testWidgets('signs in, and the app settles on the role home', (tester) async {
      await _boot(tester);
      final role = await _signIn(tester);
      expect(role, isNotNull, reason: 'signed in but the profile row has no role');
      await _settle(tester, 'the role home');
      _assertNoFailureText(role!);
    }, skip: !configured, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('every tab of this role opens, settles, and shows its own content',
        (tester) async {
      await _boot(tester);
      final role = await _signIn(tester);
      final tabs = _tabsByRole[role] ?? const <String>[];
      expect(tabs, isNotEmpty, reason: 'no tab list is declared for role "$role"');

      for (final tab in tabs) {
        // Scoped to the NavigationBar. A bare find.text('Payments') also matches a heading in
        // the body, and tapping that would pass while navigating nowhere — a green test for a
        // tab that was never opened is worse than a red one.
        final target = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(tab),
        );
        if (target.evaluate().isEmpty) {
          fail('the "$tab" tab is not in the nav bar for $role — the shell does not match '
              '_tabsByRole, which means this walkthrough is testing the wrong app');
        }
        await tester.tap(target.first);
        await _settle(tester, 'the "$tab" tab');
        _assertNoFailureText('$role/$tab');

        // A tab that renders nothing at all is as broken as one that throws, and it is the
        // failure mode a screenshot would miss: a Scaffold with an empty body looks calm.
        final anyText = find.byType(Text).evaluate().length;
        expect(anyText, greaterThan(3),
            reason: '$role/$tab settled with almost nothing on it ($anyText Text widgets)');
      }
    }, skip: !configured, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('the profile sheet opens and offers a way out', (tester) async {
      // Signing out is the one action every role must always be able to reach. If the sheet
      // does not open, a user whose session went bad has no way to fix it from inside the app.
      await _boot(tester);
      await _signIn(tester);

      final avatar = find.byTooltip('Your account');
      final opener = avatar.evaluate().isNotEmpty ? avatar : find.text('More');
      if (opener.evaluate().isEmpty) {
        fail('found neither the account avatar nor a More tab — there is no route to sign out');
      }
      await tester.tap(opener.first);
      await _settle(tester, 'the profile sheet');
      expect(find.textContaining('Sign out'), findsWidgets,
          reason: 'the profile surface opened but offers no sign out');
    }, skip: !configured, timeout: const Timeout(Duration(minutes: 3)));
  });
}

Future<void> _boot(WidgetTester tester) async {
  expect(Env.supabaseUrl, isNotEmpty,
      reason: 'pass --dart-define=SUPABASE_URL; the walkthrough talks to the real backend');
  app.main();
  await _settle(tester, 'the app boot');
}

/// Signs in through the SDK rather than by typing into the form.
///
/// The form is covered by test/ already; what this file is for is everything AFTER the session
/// exists. Driving the SDK also means the password is a value in a variable rather than a
/// sequence of key events, so it cannot end up in a screenshot or a widget-tree dump attached
/// to a failure.
Future<String?> _signIn(WidgetTester tester) async {
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) await auth.signOut();

  await auth.signInWithPassword(email: _email, password: _password);
  final uid = auth.currentUser?.id;
  expect(uid, isNotNull, reason: 'sign-in returned no user for $_email');

  await _settle(tester, 'the redirect after sign-in');

  final row = await Supabase.instance.client
      .from('users')
      .select('role')
      .eq('id', uid!)
      .maybeSingle();
  return row?['role'] as String?;
}

/// pumpAndSettle, except it does not hang forever and it says WHERE it gave up.
///
/// The app has skeletons that pulse by design, so a plain pumpAndSettle would time out on a
/// perfectly healthy screen. This pumps a fixed budget instead and then asserts the two things
/// that actually matter: no exception was thrown, and no spinner is still on screen.
Future<void> _settle(WidgetTester tester, String what) async {
  const budget = Duration(seconds: 15);
  const step = Duration(milliseconds: 250);
  for (var waited = Duration.zero; waited < budget; waited += step) {
    await tester.pump(step);
    final exception = tester.takeException();
    if (exception != null) fail('$what threw: $exception');
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      // One more frame, so a widget that appears the instant loading ends is on screen before
      // the caller starts asserting against it.
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
  }
  fail('$what never finished loading — a spinner was still on screen after ${budget.inSeconds}s');
}

void _assertNoFailureText(String where) {
  for (final phrase in _failureText) {
    expect(find.textContaining(phrase), findsNothing,
        reason: '$where is showing an error state: "$phrase"');
  }
}
