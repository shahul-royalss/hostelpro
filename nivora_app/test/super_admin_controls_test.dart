// The Super Admin's controls on one hostel: reset the owner's password, change the owner's
// email, suspend or reactivate the PG, cancel its plan, and rename it.
//
// WHAT THESE ARE FOR. Every one of these changes something an owner, their staff or their
// residents will notice, and two of them are hard to undo from a phone: a password that is
// minted and then never shown locks an owner out, and a plan cancelled by a stray tap makes a
// running PG read-only. So the things held down here are:
//
//  1. THE CONTRACT. Function and RPC names, parameter names, and that the owner is addressed by
//     HOSTEL — never by a user id the client picked. Asserted on the wire, against a stub HTTP
//     client, because a renamed key does not fail to compile.
//  2. CONFIRMATION. Nothing is sent until the admin has read what will happen and said yes.
//  3. THE SHOW-ONCE PASSWORD. It appears once, through the create wizard's dialog.
//  4. VALIDATION and REFUSALS. Short names and reasons never leave the phone; a P0001 is shown
//     in the server's own words, a 42501 as "no access".
//  5. ONE CHANGE AT A TIME. Nothing is tappable twice while a request is out.
//  6. NOTHING ENDS WITHOUT A WORD. A sheet dragged shut mid-request still reports how it went,
//     and an owner-login call that is never answered gives up and says what to do.
//
// No network: the writes go through saHostelControlsProvider, and every read is overridden.
//
// package:http is a transitive dependency, used here only to stub the wire — the same
// arrangement as repository_states_test.dart.
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
import 'package:mobile/features/super_admin/create/credentials_dialog.dart';
import 'package:mobile/features/super_admin/data/sa_models.dart';
import 'package:mobile/features/super_admin/data/sa_providers.dart';
import 'package:mobile/features/super_admin/data/sa_repository.dart';
import 'package:mobile/features/super_admin/sa_hostel_controls.dart';
import 'package:mobile/features/super_admin/sa_hostel_detail_screen.dart';
import 'package:mobile/features/super_admin/widgets/sa_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _hostelId = '3f1c9e2a-0000-4000-8000-00000000abcd';
const _password = 'Tq7-mangrove-41';

const _stats = SaStats(
  totalHostels: 12,
  totalOwners: 9,
  totalStudents: 418,
  activeSubs: 9,
  expiringSubs: 2,
  expiredSubs: 1,
  monthlySubscriptionRevenue: 184000,
);

const _session = NivoraSession(
  userId: '00000000-0000-0000-0000-0000000000aa',
  role: UserRole.superAdmin,
  fullName: 'Platform Admin',
  status: 'active',
  mustChangePassword: false,
  email: 'admin@example.com',
);

/// [noPlan] is what rpc_sa_hostels returns for a hostel with no period it counts — never
/// recorded, or every current one cancelled: no plan dates, and expired.
SaHostelRow _row({
  String name = 'Sunrise Residency',
  HostelStatus status = HostelStatus.active,
  int? daysLeft = 40,
  bool noPlan = false,
}) {
  final lapsed = noPlan || (daysLeft != null && daysLeft < 0);
  return SaHostelRow(
    hostelId: _hostelId,
    hostelName: name,
    hostelStatus: status,
    ownerId: 'owner-1',
    ownerName: 'Ramesh Krishnamurthy',
    ownerEmail: 'ramesh@example.com',
    ownerPhone: '9876543210',
    subState: lapsed ? SubscriptionState.expired : SubscriptionState.active,
    subStart: noPlan ? null : DateTime(2026, 1, 1),
    subEnd: noPlan || daysLeft == null ? null : DateTime(2026, 10, 26),
    subAmount: noPlan ? null : 12000,
    daysLeft: noPlan ? null : daysLeft,
    totalBeds: 30,
    occupiedBeds: 20,
    activeStudents: 20,
    openComplaints: 0,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

/// One period of the hostel's history, cancelled when [cancelledAt] is given.
SubscriptionRecord _period({String id = 'sub-1', DateTime? end, DateTime? cancelledAt}) {
  return SubscriptionRecord(
    id: id,
    hostelId: _hostelId,
    ownerUserId: 'owner-1',
    startDate: DateTime(2026, 1, 1),
    endDate: end ?? DateTime(2026, 12, 31),
    amount: 12000,
    status: cancelledAt == null ? SubscriptionState.active : SubscriptionState.expired,
    createdAt: DateTime.utc(2026, 1, 1),
    cancelledAt: cancelledAt,
    cancelReason: cancelledAt == null ? null : 'Owner closed the PG',
  );
}

// ═════════════════════════════════════════════════════════════════════════════════════════
// FAKES
// ═════════════════════════════════════════════════════════════════════════════════════════

/// Records every call as one readable string and answers what the test set.
class _FakeControls implements SaHostelControls {
  final calls = <String>[];

  /// Thrown by the next call, after it has been recorded.
  Object? throws;

  /// When set, every call waits for it — the "request still on the wire" state.
  Completer<void>? gate;

  OwnerEmailOutcome emailOutcome =
      const OwnerEmailChanged(ownerName: 'Ramesh Krishnamurthy', loginId: 'new@example.com');
  HostelStatus statusResult = HostelStatus.suspended;
  void Function(String name)? onRename;

  Future<void> _enter(String call) async {
    calls.add(call);
    if (gate != null) await gate!.future;
    if (throws != null) throw throws!;
  }

  @override
  Future<IssuedCredentials> resetOwnerPassword(String hostelId) async {
    await _enter('reset:$hostelId');
    return const IssuedCredentials(
      name: 'Ramesh Krishnamurthy',
      loginId: 'ramesh@example.com',
      password: _password,
    );
  }

  @override
  Future<OwnerEmailOutcome> setOwnerEmail(String hostelId, String email) async {
    await _enter('email:$hostelId:$email');
    return emailOutcome;
  }

  @override
  Future<HostelStatus> setHostelStatus(String hostelId, HostelStatus status) async {
    await _enter('status:$hostelId:${status.wire}');
    return statusResult;
  }

  @override
  Future<int> cancelSubscription(String hostelId, String reason) async {
    await _enter('cancel:$hostelId:$reason');
    return 1;
  }

  @override
  Future<String> renameHostel(String hostelId, String name) async {
    await _enter('rename:$hostelId:$name');
    onRename?.call(name);
    return name;
  }
}

/// A hostel list that counts how often it is fetched, so a refresh can be seen.
class _CountingHostels extends SaHostelListNotifier {
  _CountingHostels(super.query, this.onFetch);
  final void Function() onFetch;

  @override
  Future<PagedResult<SaHostelRow>> fetchPage(int page) async {
    onFetch();
    return PagedResult<SaHostelRow>(items: [_row()], page: 0, pageSize: 20, hasMore: false);
  }
}

/// The detail screen's world, with counters on the reads a change must refresh.
class _Harness {
  _Harness(this.row, this.history, this.historyGate);
  SaHostelRow row;
  List<SubscriptionRecord> history;

  /// When set, the history read waits for it instead of answering [history].
  Completer<List<SubscriptionRecord>>? historyGate;
  final controls = _FakeControls();
  int rowReads = 0;
  int historyReads = 0;
  int statsReads = 0;
}

/// Not pumpAndSettle: a busy spinner never stops animating, so settling would hang.
Future<void> _frames(WidgetTester tester, {int count = 8}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [pushed] opens the screen on top of another page, the way the hostels list does, so a pop
/// that closes the wrong route has somewhere to go.
Future<_Harness> _pumpDetail(
  WidgetTester tester, {
  SaHostelRow? row,
  List<SubscriptionRecord> history = const [],
  Completer<List<SubscriptionRecord>>? historyGate,
  bool pushed = false,
}) async {
  // Tall enough that every card and its buttons are on screen without scrolling.
  tester.view.physicalSize = const Size(1000, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final h = _Harness(row ?? _row(), history, historyGate);
  FutureOr<List<SubscriptionRecord>> readHistory() {
    h.historyReads++;
    final gate = h.historyGate;
    if (gate != null) return gate.future;
    return h.history;
  }

  // Typed as List<Object> and cast at the call site because Riverpod 3 does not export
  // `Override` from its public barrel.
  final overrides = <Object>[
    sessionProvider.overrideWithValue(_session),
    saStatsProvider.overrideWith((ref) {
      h.statsReads++;
      return _stats;
    }),
    saHostelProvider.overrideWith((ref, id) {
      h.rowReads++;
      return h.row;
    }),
    saSubscriptionHistoryProvider.overrideWith((ref, id) => readHistory()),
    hostelProvider.overrideWith((ref, id) => null),
    hostelStatsProvider.overrideWith((ref, query) => null),
    saPayoutProvider.overrideWith((ref, id) => const SaPayout()),
    saHostelControlsProvider.overrideWithValue(h.controls),
  ];

  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        navigatorKey: navigator,
        theme: NivoraTheme.light(),
        debugShowCheckedModeBanner: false,
        home: pushed
            ? const Scaffold(body: Center(child: Text('Hostels')))
            : const SaHostelDetailScreen(hostelId: _hostelId),
      ),
    ),
  );
  if (pushed) unawaited(navigator.currentState!.push(SaHostelDetailScreen.route(_hostelId)));
  await _frames(tester);
  return h;
}

/// The button a label sits in, whatever flavour of button it is.
ButtonStyleButton _button(WidgetTester tester, String label) => tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()).first,
    );

void main() {
  // ═══════════════════════════════════════════════════════════════════════════════════════
  // OWNER — RESET PASSWORD
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('Reset password', () {
    testWidgets('asks first, says what happens, and backing out sends nothing', (tester) async {
      final h = await _pumpDetail(tester);

      await tester.tap(find.text('Reset password'));
      await _frames(tester);

      expect(find.text('Reset and show password'), findsOneWidget);
      expect(find.textContaining('shown to you once'), findsOneWidget);
      expect(find.textContaining('must choose their own password'), findsOneWidget);
      expect(find.textContaining('signed out on every device'), findsOneWidget);
      expect(h.controls.calls, isEmpty, reason: 'opening the dialog is not a reset');

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _frames(tester);

      expect(find.text('Reset and show password'), findsNothing);
      expect(h.controls.calls, isEmpty);
    });

    testWidgets('resets the hostel\'s owner and shows the password exactly once',
        (tester) async {
      final h = await _pumpDetail(tester);

      await tester.tap(find.text('Reset password'));
      await _frames(tester);
      await tester.tap(find.text('Reset and show password'));
      await _frames(tester);

      // Addressed by HOSTEL. The owner is the server's to resolve.
      expect(h.controls.calls, ['reset:$_hostelId']);
      expect(find.text('Reset and show password'), findsNothing,
          reason: 'the confirmation closes before the password opens');
      expect(find.byType(CredentialsDialog), findsOneWidget);
      expect(find.text('New temporary password'), findsOneWidget);
      expect(find.text('Owner account created'), findsNothing,
          reason: 'a reset is not an account being created');
      expect(find.text(_password), findsOneWidget);

      await tester.tap(find.text('I have saved these credentials'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await _frames(tester);

      expect(find.byType(CredentialsDialog), findsNothing);
      expect(find.text(_password), findsNothing, reason: 'and nothing brings it back');
      expect(h.controls.calls, hasLength(1));
    });

    testWidgets('a refusal stays in the dialog, in the server\'s words, with no password',
        (tester) async {
      final h = await _pumpDetail(tester);
      h.controls.throws = const AccessDeniedFailure(
        'Confirm your second factor before changing an owner\'s login.',
      );

      await tester.tap(find.text('Reset password'));
      await _frames(tester);
      await tester.tap(find.text('Reset and show password'));
      await _frames(tester);

      expect(find.text('Confirm your second factor before changing an owner\'s login.'),
          findsOneWidget);
      expect(find.byType(CredentialsDialog), findsNothing);
      expect(find.text('Reset and show password'), findsOneWidget, reason: 'still open');
    });

    testWidgets('cannot be sent twice while the first request is out', (tester) async {
      final h = await _pumpDetail(tester);
      final gate = Completer<void>();
      h.controls.gate = gate;

      await tester.tap(find.text('Reset password'));
      await _frames(tester);
      await tester.tap(find.text('Reset and show password'));
      await _frames(tester, count: 2);

      // Busy: the confirm button shows progress and takes no taps, and neither does Cancel.
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.bySubtype<ButtonStyleButton>(),
      );
      for (final element in confirm.evaluate()) {
        expect((element.widget as ButtonStyleButton).onPressed, isNull);
      }
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );
      await tester.tap(confirm.last, warnIfMissed: false);
      await tester.pump();

      // Every other control on the hostel is off too.
      expect(_button(tester, 'Change email').onPressed, isNull);
      expect(_button(tester, 'Suspend hostel').onPressed, isNull);
      expect(_button(tester, 'Edit name').onPressed, isNull);

      // And the guard holds below the buttons as well.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SaHostelDetailScreen)),
      );
      await expectLater(
        container.read(saHostelActionProvider(_hostelId).notifier).rename('Another name'),
        throwsA(isA<ConflictFailure>()),
      );
      expect(h.controls.calls, ['reset:$_hostelId']);

      gate.complete();
      await _frames(tester);
      expect(find.byType(CredentialsDialog), findsOneWidget);
      expect(h.controls.calls, hasLength(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // OWNER — CHANGE EMAIL
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('Change email', () {
    testWidgets('validates, then moves the login and says what the owner now types',
        (tester) async {
      final h = await _pumpDetail(tester);
      final rowReadsBefore = h.rowReads;

      await tester.tap(find.text('Change email'));
      await _frames(tester);

      expect(find.textContaining('will sign in with the new address'), findsOneWidget);
      expect(find.textContaining('signed out on every device'), findsOneWidget);
      expect(find.textContaining('must verify the new address'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'not-an-email');
      await tester.tap(find.text('Save email'));
      await _frames(tester);
      expect(find.text('That does not look like an email address.'), findsOneWidget);
      expect(h.controls.calls, isEmpty);

      await tester.enterText(find.byType(TextFormField), '  new@example.com ');
      await tester.tap(find.text('Save email'));
      await _frames(tester);

      expect(h.controls.calls, ['email:$_hostelId:new@example.com']);
      expect(find.text('Save email'), findsNothing, reason: 'the sheet closes on success');
      expect(find.textContaining('now signs in with new@example.com'), findsOneWidget);
      expect(h.rowReads, greaterThan(rowReadsBefore), reason: 'the Login row is re-read');
    });

    testWidgets('an address the server refuses is shown under the field', (tester) async {
      final h = await _pumpDetail(tester);
      h.controls.emailOutcome = const OwnerEmailRejected(
        'An account with this email already exists.',
        emailError: 'An account with this email already exists.',
      );

      await tester.tap(find.text('Change email'));
      await _frames(tester);
      await tester.enterText(find.byType(TextFormField), 'taken@example.com');
      await tester.tap(find.text('Save email'));
      await _frames(tester);

      expect(h.controls.calls, ['email:$_hostelId:taken@example.com']);
      expect(find.text('An account with this email already exists.'), findsOneWidget);
      expect(find.text('Save email'), findsOneWidget, reason: 'still open, to fix it');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // SUBSCRIPTION — SUSPEND, REACTIVATE, CANCEL
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('Suspend and reactivate', () {
    testWidgets('suspending says every write is blocked, and only then suspends',
        (tester) async {
      final h = await _pumpDetail(tester);

      expect(find.text('Reactivate hostel'), findsNothing);
      await tester.tap(find.text('Suspend hostel'));
      await _frames(tester);

      expect(
        find.textContaining('every write in this PG is blocked until you reactivate it'),
        findsOneWidget,
      );
      expect(h.controls.calls, isEmpty);

      await tester.tap(find.text('Suspend'));
      await _frames(tester);

      expect(h.controls.calls, ['status:$_hostelId:suspended']);
      expect(find.textContaining('is suspended'), findsOneWidget);
      // The platform figures are refreshed too; see "after a change", where they are watched.
    });

    testWidgets('a suspended hostel offers reactivation, and a lapsed plan is reported',
        (tester) async {
      final h = await _pumpDetail(tester, row: _row(status: HostelStatus.suspended));
      h.controls.statusResult = HostelStatus.readonly;

      expect(find.text('Suspend hostel'), findsNothing);
      await tester.tap(find.text('Reactivate hostel'));
      await _frames(tester);
      expect(find.textContaining('stays read-only until it is renewed'), findsOneWidget);
      expect(h.controls.calls, isEmpty);

      await tester.tap(find.text('Reactivate'));
      await _frames(tester);

      expect(h.controls.calls, ['status:$_hostelId:active']);
      expect(find.textContaining('stays read-only until renewed'), findsOneWidget);
    });
  });

  group('Cancel plan', () {
    testWidgets('needs a real reason, says what happens, and cancels with it trimmed',
        (tester) async {
      final h = await _pumpDetail(tester);
      final historyBefore = h.historyReads;

      await tester.tap(find.text('Cancel plan'));
      await _frames(tester);

      expect(find.textContaining('becomes read-only immediately'), findsOneWidget);
      expect(find.textContaining('A renewal starts a new period'), findsOneWidget);

      await tester.tap(find.text('Cancel the plan'));
      await _frames(tester);
      expect(find.text('Give a reason of at least 3 characters. The owner is shown it.'),
          findsOneWidget);

      await tester.enterText(find.byType(TextFormField), ' ab ');
      await tester.tap(find.text('Cancel the plan'));
      await _frames(tester);
      expect(find.text('Give a reason of at least 3 characters. The owner is shown it.'),
          findsOneWidget);
      expect(h.controls.calls, isEmpty, reason: 'a short reason never leaves the phone');

      await tester.enterText(find.byType(TextFormField), '  Owner closed the PG  ');
      await tester.tap(find.text('Cancel the plan'));
      await _frames(tester);

      expect(h.controls.calls, ['cancel:$_hostelId:Owner closed the PG']);
      expect(find.text('Cancel the plan'), findsNothing);
      expect(find.textContaining('Plan cancelled'), findsOneWidget);
      expect(h.historyReads, greaterThan(historyBefore), reason: 'the history is re-read');
    });

    testWidgets('"Keep the plan" backs out without cancelling anything', (tester) async {
      final h = await _pumpDetail(tester);

      await tester.tap(find.text('Cancel plan'));
      await _frames(tester);
      await tester.enterText(find.byType(TextFormField), 'Owner closed the PG');
      await tester.tap(find.text('Keep the plan'));
      await _frames(tester);

      expect(find.text('Cancel the plan'), findsNothing);
      expect(h.controls.calls, isEmpty);
    });

    testWidgets('a P0001 is shown verbatim and a 42501 as no access', (tester) async {
      final h = await _pumpDetail(tester);

      await tester.tap(find.text('Cancel plan'));
      await _frames(tester);
      await tester.enterText(find.byType(TextFormField), 'Owner closed the PG');

      h.controls.throws =
          const PostgrestException(message: 'There is no current plan to cancel.', code: 'P0001');
      await tester.tap(find.text('Cancel the plan'));
      await _frames(tester);
      expect(find.text('There is no current plan to cancel.'), findsOneWidget);
      expect(find.text('Cancel the plan'), findsOneWidget, reason: 'the sheet stays open');

      h.controls.throws = const PostgrestException(
        message: 'Only the Super Admin can cancel a plan.',
        code: '42501',
      );
      await tester.tap(find.text('Cancel the plan'));
      await _frames(tester);
      expect(find.text('You do not have access to that.'), findsOneWidget);
      expect(find.text('Only the Super Admin can cancel a plan.'), findsNothing);
    });

    testWidgets('is not offered when there is no current plan', (tester) async {
      await _pumpDetail(tester, row: _row(daysLeft: -3));
      expect(find.text('Cancel plan'), findsNothing);
      expect(find.text('Suspend hostel'), findsOneWidget);
    });

    testWidgets('a cancelled period in the history says so, with its date and reason',
        (tester) async {
      final cancelledAt = DateTime.utc(2026, 9, 16, 6);
      await _pumpDetail(tester, history: [
        SubscriptionRecord(
          id: 'sub-1',
          hostelId: _hostelId,
          ownerUserId: 'owner-1',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
          amount: 12000,
          status: SubscriptionState.active,
          createdAt: DateTime.utc(2026, 1, 1),
          cancelledAt: cancelledAt,
          cancelReason: 'Owner closed the PG',
        ),
      ]);

      expect(find.text('Cancelled'), findsOneWidget);
      expect(
        find.text('On ${dateLabel(cancelledAt.toLocal())}: Owner closed the PG'),
        findsOneWidget,
      );
    });

    testWidgets('the page then says the plan was cancelled, not that there never was one',
        (tester) async {
      final cancelledAt = DateTime.utc(2026, 9, 16, 6);
      await _pumpDetail(
        tester,
        // What rpc_sa_hostels returns once the only current period is cancelled, with the status
        // sa_cancel_subscription moves an active hostel to.
        row: _row(noPlan: true, status: HostelStatus.readonly),
        history: [_period(cancelledAt: cancelledAt)],
      );

      final on = dateLabel(cancelledAt.toLocal());
      expect(
        find.text('The plan was cancelled on $on. Staff can read but cannot record anything '
            'until a new period is recorded.'),
        findsOneWidget,
        reason: 'the band at the top',
      );
      expect(
        find.text('The plan was cancelled on $on, so every write is refused until a new period '
            'is recorded.'),
        findsOneWidget,
        reason: 'the subscription card',
      );
      expect(find.textContaining('No subscription has ever been recorded'), findsNothing);
      expect(find.textContaining('Marked read-only'), findsNothing);
      expect(find.textContaining('web console'), findsNothing);
    });

    testWidgets('an older period that ran out is not passed off as the plan', (tester) async {
      await _pumpDetail(
        tester,
        // After a cancel the row falls back to the newest period that was NOT cancelled.
        row: _row(daysLeft: -200, status: HostelStatus.readonly),
        history: [
          _period(id: 'sub-2', cancelledAt: DateTime.utc(2026, 9, 16, 6)),
          _period(end: DateTime(2026, 3, 1)),
        ],
      );

      expect(find.text('CURRENT PERIOD'), findsNothing);
      expect(find.textContaining('The plan was cancelled on'), findsNWidgets(2));
    });

    testWidgets('straight after a cancel, the old history does not make it "never recorded"',
        (tester) async {
      final h = await _pumpDetail(tester, history: [_period()]);
      // How the two reads answer once the cancel has landed: the row at once, the history not
      // yet — so for a moment the page holds the new row beside the list from before the cancel.
      h.row = _row(noPlan: true, status: HostelStatus.readonly);
      final historyGate = h.historyGate = Completer<List<SubscriptionRecord>>();

      await tester.tap(find.text('Cancel plan'));
      await _frames(tester);
      await tester.enterText(find.byType(TextFormField), 'Owner closed the PG');
      await tester.tap(find.text('Cancel the plan'));
      await _frames(tester);

      expect(find.textContaining('Plan cancelled'), findsOneWidget);
      expect(
        find.text('There is no current plan, so every write is refused until one is recorded.'),
        findsOneWidget,
      );
      expect(find.textContaining('No subscription has ever been recorded'), findsNothing);
      expect(find.textContaining('web console'), findsNothing);

      historyGate.complete([_period(cancelledAt: DateTime.utc(2026, 9, 16, 6))]);
      await _frames(tester);
      expect(find.textContaining('The plan was cancelled on'), findsNWidgets(2));
    });

    testWidgets('"never recorded" waits for a settled history to agree', (tester) async {
      final historyGate = Completer<List<SubscriptionRecord>>();
      await _pumpDetail(tester, row: _row(noPlan: true), historyGate: historyGate);

      // Straight after a cancel the history is reloading, and until it lands a cancelled plan and
      // one that never existed look the same.
      expect(
        find.text('There is no current plan. Staff can read but cannot record anything until '
            'one is recorded.'),
        findsOneWidget,
      );
      expect(
        find.text('There is no current plan, so every write is refused until one is recorded.'),
        findsOneWidget,
      );
      expect(find.textContaining('No subscription has ever been recorded'), findsNothing);

      historyGate.complete(const []);
      await _frames(tester);
      expect(find.textContaining('No subscription has ever been recorded'), findsNWidgets(2));
      expect(find.textContaining('web console'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // HOSTEL NAME
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('Edit name', () {
    testWidgets('blocks a short name, and a saved name reaches the header', (tester) async {
      final h = await _pumpDetail(tester);
      h.controls.onRename = (name) => h.row = _row(name: name);

      await tester.tap(find.text('Edit name'));
      await _frames(tester);

      final field = find.byType(TextFormField);
      expect(tester.widget<TextFormField>(field).controller?.text, 'Sunrise Residency');

      await tester.enterText(field, ' A ');
      await tester.tap(find.text('Save name'));
      await _frames(tester);
      expect(find.text('A hostel name needs at least 2 characters.'), findsOneWidget);
      expect(h.controls.calls, isEmpty);

      await tester.enterText(field, '  Sunrise Heights  ');
      await tester.tap(find.text('Save name'));
      await _frames(tester);

      expect(h.controls.calls, ['rename:$_hostelId:Sunrise Heights']);
      expect(find.text('Save name'), findsNothing);
      // The page header and the hostel card both carry it now.
      expect(find.text('Sunrise Heights'), findsNWidgets(2));
      expect(find.text('Sunrise Residency'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // A SHEET DRAGGED SHUT MID-REQUEST
  // ═══════════════════════════════════════════════════════════════════════════════════════

  // PopScope refuses the back gesture and the barrier, not the drag, so a sheet can be gone by the
  // time its answer arrives. The answer must still reach the admin, and nothing else may close.
  group('a sheet dragged shut mid-request', () {
    testWidgets('a refusal is still told on the page, naming the change', (tester) async {
      final h = await _pumpDetail(tester);
      final gate = Completer<void>();
      h.controls.gate = gate;

      await tester.tap(find.text('Cancel plan'));
      await _frames(tester);
      await tester.enterText(find.byType(TextFormField), 'Owner closed the PG');
      await tester.tap(find.text('Cancel the plan'));
      await _frames(tester, count: 2);
      expect(h.controls.calls, ['cancel:$_hostelId:Owner closed the PG']);

      await tester.fling(find.text('Cancel the current plan'), const Offset(0, 400), 3000);
      await _frames(tester);
      expect(find.text('Cancel the current plan'), findsNothing, reason: 'the drag closed it');

      h.controls.throws =
          const PostgrestException(message: 'There is no current plan to cancel.', code: 'P0001');
      gate.complete();
      await _frames(tester);

      expect(find.text('Cancel plan: There is no current plan to cancel.'), findsOneWidget);
    });

    testWidgets('an address the server refuses is still told on the page', (tester) async {
      final h = await _pumpDetail(tester);
      final gate = Completer<void>();
      h.controls
        ..gate = gate
        ..emailOutcome = const OwnerEmailRejected(
          'That email address already belongs to another account.',
          emailError: 'That email address already belongs to another account.',
        );

      await tester.tap(find.text('Change email'));
      await _frames(tester);
      await tester.enterText(find.byType(TextFormField), 'taken@example.com');
      await tester.tap(find.text('Save email'));
      await _frames(tester, count: 2);

      await tester.fling(find.text('Change the owner\'s email'), const Offset(0, 400), 3000);
      await _frames(tester);
      expect(find.text('Save email'), findsNothing, reason: 'the drag closed it');

      gate.complete();
      await _frames(tester);

      expect(
        find.text('Change email: That email address already belongs to another account.'),
        findsOneWidget,
      );
    });

    testWidgets('a change landing while the sheet is still leaving closes nothing else',
        (tester) async {
      final h = await _pumpDetail(tester, pushed: true);
      final gate = Completer<void>();
      h.controls
        ..gate = gate
        ..onRename = (name) => h.row = _row(name: name);

      await tester.tap(find.text('Edit name'));
      await _frames(tester);
      await tester.enterText(find.byType(TextFormField), 'Sunrise Heights');
      await tester.tap(find.text('Save name'));
      await _frames(tester, count: 2);

      // A short, fast flick: the sheet is on its way out, and not yet gone, when the answer lands.
      await tester.fling(find.text('Edit hostel name'), const Offset(0, 60), 3000);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Edit hostel name'), findsOneWidget, reason: 'still leaving');

      gate.complete();
      await _frames(tester);

      expect(find.byType(SaHostelDetailScreen), findsOneWidget, reason: 'the page is still open');
      expect(find.text('Renamed to Sunrise Heights.'), findsOneWidget);
      expect(find.text('Edit hostel name'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // WHAT A SUCCESS REFRESHES
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('after a change', () {
    late ProviderContainer container;
    late _FakeControls controls;
    late Map<String, int> reads;

    setUp(() {
      controls = _FakeControls();
      reads = {'row': 0, 'list': 0, 'stats': 0, 'history': 0};
      container = ProviderContainer(
        overrides: <Object>[
          sessionProvider.overrideWithValue(_session),
          saHostelControlsProvider.overrideWithValue(controls),
          saHostelProvider.overrideWith((ref, id) {
            reads['row'] = reads['row']! + 1;
            return _row();
          }),
          saStatsProvider.overrideWith((ref) {
            reads['stats'] = reads['stats']! + 1;
            return _stats;
          }),
          saSubscriptionHistoryProvider.overrideWith((ref, id) {
            reads['history'] = reads['history']! + 1;
            return const <SubscriptionRecord>[];
          }),
          saHostelListProvider.overrideWith2(
            (_) => _CountingHostels(const SaHostelQuery(), () => reads['list'] = reads['list']! + 1),
          ),
          hostelProvider.overrideWith((ref, id) => null),
        ].cast(),
      );
      // Held open the way the screens hold them.
      container.listen(saHostelProvider(_hostelId), (_, _) {});
      container.listen(saStatsProvider, (_, _) {});
      container.listen(saSubscriptionHistoryProvider(_hostelId), (_, _) {});
      container.listen(saHostelListProvider(const SaHostelQuery()), (_, _) {});
      container.listen(saHostelActionProvider(_hostelId), (_, _) {});
    });

    tearDown(() => container.dispose());

    Future<Map<String, int>> settle() async {
      await container.read(saHostelProvider(_hostelId).future);
      await container.read(saStatsProvider.future);
      await container.read(saSubscriptionHistoryProvider(_hostelId).future);
      await container.read(saHostelListProvider(const SaHostelQuery()).future);
      return Map.of(reads);
    }

    test('a cancelled plan re-reads the hostel, the lists, the figures and the history',
        () async {
      final before = await settle();
      await container.read(saHostelActionProvider(_hostelId).notifier).cancelPlan('Closed');
      final after = await settle();

      expect(controls.calls, ['cancel:$_hostelId:Closed']);
      for (final key in before.keys) {
        expect(after[key], before[key]! + 1, reason: key);
      }
      expect(container.read(saHostelActionProvider(_hostelId)), isNull, reason: 'idle again');
    });

    test('a rename re-reads the hostel and the lists, and leaves the figures alone', () async {
      final before = await settle();
      await container.read(saHostelActionProvider(_hostelId).notifier).rename('Sunrise Heights');
      final after = await settle();

      expect(after['row'], before['row']! + 1);
      expect(after['list'], before['list']! + 1);
      expect(after['stats'], before['stats']);
    });

    test('a failed change refreshes nothing and leaves the hostel idle', () async {
      controls.throws = const InvalidInputFailure('There is no current plan to cancel.');
      final before = await settle();
      await expectLater(
        container.read(saHostelActionProvider(_hostelId).notifier).cancelPlan('Closed'),
        throwsA(isA<InvalidInputFailure>()),
      );
      final after = await settle();

      expect(after, before);
      expect(container.read(saHostelActionProvider(_hostelId)), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // THE WIRE — the contract with sa-owner-account and the three RPCs
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('on the wire', () {
    late List<http.Request> sent;

    SaRepository answering(int status, Object? body) {
      sent = [];
      return SaRepository(SupabaseClient(
        'https://stub.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          sent.add(request);
          return http.Response(
            jsonEncode(body),
            status,
            request: request,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ));
    }

    Map<String, dynamic> sentBody() => jsonDecode(sent.single.body) as Map<String, dynamic>;

    test('suspend calls sa_set_hostel_status with the contract\'s parameters', () async {
      final repo = answering(200, 'suspended');
      final result = await repo.setHostelStatus(_hostelId, HostelStatus.suspended);

      expect(sent.single.url.path, '/rest/v1/rpc/sa_set_hostel_status');
      expect(sentBody(), {'p_hostel_id': _hostelId, 'p_status': 'suspended'});
      expect(result, HostelStatus.suspended);
    });

    test('reactivation reports the status the server settled on', () async {
      final repo = answering(200, 'readonly');
      expect(await repo.setHostelStatus(_hostelId, HostelStatus.active), HostelStatus.readonly);
      expect(sentBody()['p_status'], 'active');
    });

    test('read-only is never sent as a choice', () async {
      final repo = answering(200, 'readonly');
      await expectLater(
        repo.setHostelStatus(_hostelId, HostelStatus.readonly),
        throwsA(isA<InvalidInputFailure>()),
      );
      expect(sent, isEmpty);
    });

    test('cancel calls sa_cancel_subscription with the reason trimmed', () async {
      final repo = answering(200, 1);
      expect(await repo.cancelSubscription(_hostelId, '  Owner closed the PG '), 1);
      expect(sent.single.url.path, '/rest/v1/rpc/sa_cancel_subscription');
      expect(sentBody(), {'p_hostel_id': _hostelId, 'p_reason': 'Owner closed the PG'});
    });

    test('rename calls sa_rename_hostel and returns the stored name', () async {
      final repo = answering(200, 'Sunrise Heights');
      expect(await repo.renameHostel(_hostelId, ' Sunrise Heights '), 'Sunrise Heights');
      expect(sent.single.url.path, '/rest/v1/rpc/sa_rename_hostel');
      expect(sentBody(), {'p_hostel_id': _hostelId, 'p_name': 'Sunrise Heights'});
    });

    test('a P0001 keeps its sentence; a 42501 becomes no access', () async {
      await expectLater(
        answering(400, {'code': 'P0001', 'message': 'There is no current plan to cancel.'})
            .cancelSubscription(_hostelId, 'Closed'),
        throwsA(isA<InvalidInputFailure>()
            .having((f) => f.message, 'message', 'There is no current plan to cancel.')),
      );
      await expectLater(
        answering(403, {'code': '42501', 'message': 'not the super admin'})
            .renameHostel(_hostelId, 'Sunrise Heights'),
        throwsA(isA<AccessDeniedFailure>()
            .having((f) => f.message, 'message', 'You do not have access to that.')),
      );
    });

    test('reset-password names the hostel and no user, and returns the password', () async {
      final repo = answering(200, {
        'ok': true,
        'data': {'ownerName': 'Ramesh Krishnamurthy', 'loginId': 'ramesh@example.com', 'password': _password},
      });
      final creds = await repo.resetOwnerPassword(_hostelId);

      expect(sent.single.url.path, '/functions/v1/sa-owner-account');
      expect(sentBody(), {'action': 'reset-password', 'hostelId': _hostelId});
      expect(creds.name, 'Ramesh Krishnamurthy');
      expect(creds.loginId, 'ramesh@example.com');
      expect(creds.password, _password);
    });

    test('set-email sends the trimmed address and returns the new login', () async {
      final repo = answering(200, {
        'ok': true,
        'data': {'ownerName': 'Ramesh Krishnamurthy', 'loginId': 'new@example.com'},
      });
      final outcome = await repo.setOwnerEmail(_hostelId, ' new@example.com ');

      expect(sentBody(), {'action': 'set-email', 'hostelId': _hostelId, 'email': 'new@example.com'});
      expect(outcome, isA<OwnerEmailChanged>().having((o) => o.loginId, 'loginId', 'new@example.com'));
    });

    test('a 409 on the email comes back as a rejection for the field, not a throw', () async {
      final repo = answering(409, {
        'ok': false,
        'error': 'An account with this email already exists.',
        'fieldErrors': {
          'email': ['An account with this email already exists.'],
        },
      });
      final outcome = await repo.setOwnerEmail(_hostelId, 'taken@example.com');

      expect(
        outcome,
        isA<OwnerEmailRejected>()
            .having((o) => o.emailError, 'emailError', 'An account with this email already exists.'),
      );
    });

    test('a hostel with no owner is a failure in the function\'s words', () async {
      await expectLater(
        answering(404, {'ok': false, 'error': 'That hostel has no owner.'})
            .resetOwnerPassword(_hostelId),
        throwsA(isA<NotFoundFailure>().having((f) => f.message, 'message', 'That hostel has no owner.')),
      );
    });

    // functions.invoke has no deadline of its own, and the reset dialog cannot be closed while
    // its request is out. A request that is accepted and never answered must still end.
    SaRepository stalled() => SaRepository(
          SupabaseClient(
            'https://stub.supabase.co',
            'anon-key',
            httpClient: MockClient((_) => Completer<http.Response>().future),
          ),
          ownerAccountDeadline: const Duration(milliseconds: 200),
        );

    test('a stalled reset stops waiting, and says the password may have been reset', () async {
      await expectLater(
        stalled().resetOwnerPassword(_hostelId),
        throwsA(isA<ServerFailure>()
            .having((f) => f.outcomeIsUnknown, 'outcomeIsUnknown', isTrue)
            .having((f) => f.isRetryable, 'isRetryable', isFalse)
            .having((f) => f.message, 'message', contains('The password may have been reset'))
            .having((f) => f.message, 'message', contains('Reset it again'))),
      );
    });

    test('a stalled email change stops waiting, and says how to find out', () async {
      await expectLater(
        stalled().setOwnerEmail(_hostelId, 'new@example.com'),
        throwsA(isA<ServerFailure>()
            .having((f) => f.outcomeIsUnknown, 'outcomeIsUnknown', isTrue)
            .having((f) => f.message, 'message', contains('Save the same address again'))),
      );
    });
  });

  group('the owner-login failure mapping', () {
    test('a 404 with no body is a missing deployment, not a missing hostel', () {
      final failure = SaRepository.ownerAccountFailureFrom(const FunctionException(status: 404));
      expect(failure, isA<NotFoundFailure>());
      expect(failure.message, contains('not available on this server'));
      expect(failure.message, contains('Nothing was changed'));
    });

    test('a 403 keeps the function\'s sentence, and a 401 needs sign-in', () {
      const secondFactor = FunctionException(
        status: 403,
        details: {'ok': false, 'error': 'Confirm your second factor first.'},
      );
      final refused = SaRepository.ownerAccountFailureFrom(secondFactor);
      expect(refused, isA<AccessDeniedFailure>());
      expect(refused.message, 'Confirm your second factor first.');
      expect(
        SaRepository.ownerAccountFailureFrom(const FunctionException(status: 401)).needsSignIn,
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // VALIDATION AND PARSING
  // ═══════════════════════════════════════════════════════════════════════════════════════

  group('validation', () {
    test('a hostel name is 2 to 120 characters after trimming', () {
      expect(validateHostelName(' A '), isNotNull);
      expect(validateHostelName('AB'), isNull);
      expect(validateHostelName('x' * 120), isNull);
      expect(validateHostelName('x' * 121), isNotNull);
      expect(validateHostelName('Sunrise', current: 'Sunrise'), isNotNull);
    });

    test('a cancel reason is 3 to 300 characters after trimming', () {
      expect(validateCancelReason('  ab  '), isNotNull);
      expect(validateCancelReason(' abc '), isNull);
      expect(validateCancelReason('x' * 300), isNull);
      expect(validateCancelReason('x' * 301), isNotNull);
    });

    test('an owner email is a real, different address', () {
      expect(validateOwnerEmail('owner@example.com'), isNull);
      expect(validateOwnerEmail(''), isNotNull);
      expect(validateOwnerEmail('owner@example'), isNotNull);
      expect(validateOwnerEmail('9876543210@student.hostelpro.local'), isNotNull,
          reason: 'the residents\' phone-login namespace is not a mailbox');
      expect(validateOwnerEmail('Owner@Example.com', current: 'owner@example.com'), isNotNull);
    });
  });

  test('a subscription row carries its cancellation', () {
    final row = SubscriptionRecord.fromJson({
      'id': 'sub-1',
      'hostel_id': _hostelId,
      'owner_user_id': 'owner-1',
      'start_date': '2026-01-01',
      'end_date': '2026-12-31',
      'amount': 12000,
      'status': 'active',
      'notes': null,
      'created_at': '2026-01-01T00:00:00Z',
      'cancelled_at': '2026-09-16T06:00:00Z',
      'cancel_reason': 'Owner closed the PG',
    });
    expect(row.isCancelled, isTrue);
    expect(row.cancelReason, 'Owner closed the PG');
    expect(SubscriptionRecord.columns, contains('cancelled_at'));
    expect(SubscriptionRecord.columns, contains('cancel_reason'));

    final live = SubscriptionRecord.fromJson({
      'id': 'sub-2',
      'hostel_id': _hostelId,
      'owner_user_id': 'owner-1',
      'start_date': '2026-01-01',
      'end_date': '2026-12-31',
      'amount': 12000,
      'status': 'active',
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(live.isCancelled, isFalse);
  });
}
