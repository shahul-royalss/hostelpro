// Tests for the owner's staff screen — the flow that creates a manager or warden login from
// inside the app.
//
// WHAT THESE ARE FOR. Three things here are worth more than the usual widget coverage:
//
//  1. THE REQUEST SHAPE. `StaffDraft.toJson()` is a contract with a Deno process in another
//     repository directory. A renamed key does not fail to compile — it fails at 9pm with
//     "Please check the highlighted fields" and no highlighted field. The map is asserted
//     literally, against supabase/functions/owner-create-staff/index.ts parseBody().
//
//  2. HARD RULE §4.3. "One active manager and one active warden per hostel" is refused in three
//     places that do not agree on a status code, so the client recognises it by its words. If
//     that match breaks, the owner is told "Something went wrong. Please try again." about a
//     rule the product is working exactly as designed.
//
//  3. THE SHOW-ONCE DIALOG. The password it holds exists nowhere else — not in a table, not in
//     a log, not in the audit row. Every obstacle in the way of dismissing it is load-bearing,
//     so each one is tested: the barrier, the back gesture, and the confirmation checkbox.
//
// No network: the two writes go through `ownerStaffWritesProvider`, which exists as an
// interface for exactly this reason, and every read is an overridden provider.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/owner/staff/add_staff_sheet.dart';
import 'package:mobile/features/owner/staff/owner_staff_screen.dart';
import 'package:mobile/features/owner/staff/staff_credentials_dialog.dart';
import 'package:mobile/features/owner/staff/staff_models.dart';
import 'package:mobile/features/owner/staff/staff_providers.dart';
import 'package:mobile/features/owner/staff/staff_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _hostelId = '3f1c9e2a-0000-4000-8000-00000000abcd';

final _sunrise = Hostel(
  id: _hostelId,
  name: 'Sunrise Residency',
  ownerUserId: 'owner-1',
  totalFloors: 3,
  totalRooms: 12,
  bedsPerRoomDefault: 3,
  status: HostelStatus.active,
  createdAt: DateTime.utc(2026, 3, 1),
  updatedAt: DateTime.utc(2026, 3, 1),
);

StaffMember _member({
  String id = 'u-1',
  StaffRole role = StaffRole.manager,
  String name = 'Ravi Kulkarni',
  StaffStatus status = StaffStatus.active,
  String? email = 'ravi@example.com',
  String? phone = '9876543210',
}) {
  return StaffMember(
    id: id,
    role: role,
    fullName: name,
    status: status,
    createdAt: DateTime.utc(2026, 5, 12),
    email: email,
    phone: phone,
  );
}

/// Stands in for the two writes. Records what it was asked to do, answers what the test set.
class _FakeWrites implements OwnerStaffWrites {
  _FakeWrites({this.outcome, this.throws});

  StaffCreateOutcome? outcome;
  Object? throws;

  int createCalls = 0;
  String? lastHostelId;
  StaffDraft? lastDraft;

  int statusCalls = 0;
  String? lastStatusUserId;
  StaffStatus? lastStatus;

  @override
  Future<StaffCreateOutcome> createStaff({
    required String hostelId,
    required StaffDraft draft,
  }) async {
    createCalls++;
    lastHostelId = hostelId;
    lastDraft = draft;
    if (throws != null) throw throws!;
    return outcome!;
  }

  @override
  Future<StaffMember> setStaffStatus({
    required String hostelId,
    required String userId,
    required StaffStatus status,
  }) async {
    statusCalls++;
    lastStatusUserId = userId;
    lastStatus = status;
    if (throws != null) throw throws!;
    return _member(id: userId, status: status);
  }
}

/// Typed as List<Object> and cast at the call site because Riverpod 3 does not export
/// `Override` from its public barrel, so the real element type cannot be named here.
List<Object> _overrides({
  List<StaffMember> staff = const [],
  Object? staffError,
  OwnerStaffWrites? writes,
  String? hostelId = _hostelId,
}) {
  return [
    activeHostelIdProvider.overrideWithValue(hostelId),
    myHostelsProvider.overrideWith((ref) => [_sunrise]),
    if (staffError != null)
      ownerStaffProvider.overrideWith(
        (ref, id) => Future<List<StaffMember>>.error(staffError),
      )
    else
      ownerStaffProvider.overrideWith((ref, id) => staff),
    if (writes != null) ownerStaffWritesProvider.overrideWithValue(writes),
  ];
}

/// Not pumpAndSettle: the loading skeletons animate forever, so settling would hang.
Future<void> _tick(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, List<Object> overrides) async {
  // Tall enough that both role cards and the sheet fit without scrolling — this is about
  // reaching buttons in a test, not about a real device.
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: NivoraTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const OwnerStaffScreen(),
      ),
    ),
  );
  await _tick(tester);
}

/// Opens the add sheet for one role and fills in a valid person.
Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Full name'), '  Priya Nair ');
  await tester.enterText(find.widgetWithText(TextField, 'Email'), 'Priya@Example.COM');
  await tester.enterText(find.widgetWithText(TextField, 'Phone (optional)'), '98765 43210');
  await tester.pump();
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // THE REQUEST SHAPE — the contract with owner-create-staff/index.ts
  // ───────────────────────────────────────────────────────────────────────────
  group('StaffDraft.toJson', () {
    test('sends exactly the keys parseBody() reads, and nothing else', () {
      const draft = StaffDraft(
        role: StaffRole.warden,
        fullName: '  Priya Nair  ',
        email: '  Priya@Example.COM ',
        phone: ' +91 98765 43210 ',
      );

      expect(draft.toJson(_hostelId), {
        'role': 'warden',
        'fullName': 'Priya Nair',
        'email': 'priya@example.com',
        'phone': '+91 98765 43210',
        'hostelId': _hostelId,
      });
    });

    test('omits phone entirely when it is blank, because it is optional', () {
      const draft = StaffDraft(
        role: StaffRole.manager,
        fullName: 'Ravi',
        email: 'r@example.com',
        phone: '   ',
      );
      final body = draft.toJson(_hostelId);

      // v.optionalPhone() treats a missing key and an empty string the same, but sending the
      // key with whitespace in it would be a value the loose phone regex rejects.
      expect(body.containsKey('phone'), isFalse);
      expect(body.keys.toSet(), {'role', 'fullName', 'email', 'hostelId'});
    });

    test('the role goes over the wire as the Postgres label, never the Dart name', () {
      expect(const StaffDraft(role: StaffRole.manager).toJson(_hostelId)['role'], 'manager');
      expect(const StaffDraft(role: StaffRole.warden).toJson(_hostelId)['role'], 'warden');
    });

    test('the hostel is always named, so a multi-PG owner cannot create against the wrong one',
        () {
      // The function would otherwise fall back to caller.hostelId, which for an owner holding
      // several PGs is whichever they were first attached to — not the one on screen.
      expect(const StaffDraft().toJson(_hostelId)['hostelId'], _hostelId);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // VALIDATION — the same rejections _shared/validate.ts would produce
  // ───────────────────────────────────────────────────────────────────────────
  group('validateStaffDraft', () {
    test('accepts a complete person', () {
      expect(
        validateStaffDraft(const StaffDraft(
          fullName: 'Priya Nair',
          email: 'priya@example.com',
          phone: '9876543210',
        )),
        isEmpty,
      );
    });

    test('accepts a person with no phone at all — the column is nullable', () {
      expect(
        validateStaffDraft(
            const StaffDraft(fullName: 'Priya Nair', email: 'priya@example.com')),
        isEmpty,
      );
    });

    test('rejects a name under two characters, in the function\'s own words', () {
      final errors = validateStaffDraft(
          const StaffDraft(fullName: 'P', email: 'priya@example.com'));
      expect(errors['fullName'], 'Enter the full name.');
    });

    test('rejects a name over the 80-character column budget', () {
      final errors = validateStaffDraft(
        StaffDraft(fullName: 'P' * 81, email: 'priya@example.com'),
      );
      expect(errors['fullName'], 'Keep this under 80 characters.');
    });

    test('rejects an address without an @ or a dot', () {
      for (final bad in ['priya', 'priya@example', 'priya example.com', '']) {
        final errors = validateStaffDraft(StaffDraft(fullName: 'Priya Nair', email: bad));
        expect(errors['email'], 'Enter a valid email address', reason: bad);
      }
    });

    test('rejects a phone the loose server regex would also reject', () {
      // Letters are out; so is anything under 8 or over 16 characters.
      for (final bad in ['98765abcd', '12345', '1' * 17]) {
        final errors = validateStaffDraft(
          StaffDraft(fullName: 'Priya Nair', email: 'p@example.com', phone: bad),
        );
        expect(errors['phone'], 'Enter a valid phone number.', reason: bad);
      }
    });

    test('accepts the punctuation people actually type into a phone box', () {
      for (final good in ['+91 98765 43210', '(022) 555-0100', '9876543210']) {
        final errors = validateStaffDraft(
          StaffDraft(fullName: 'Priya Nair', email: 'p@example.com', phone: good),
        );
        expect(errors, isEmpty, reason: good);
      }
    });

    test('reports every bad field at once, not one per round trip', () {
      final errors = validateStaffDraft(const StaffDraft(fullName: '', email: 'nope'));
      expect(errors.keys.toSet(), {'fullName', 'email'});
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // TRANSLATING THE FUNCTION'S REFUSALS
  // ───────────────────────────────────────────────────────────────────────────
  group('staffRejectionFrom', () {
    test('a validator 400 becomes one message per field', () {
      final rejection = staffRejectionFrom(const FunctionException(
        status: 400,
        details: {
          'error': 'Enter the full name.',
          'fieldErrors': {
            'fullName': ['Enter the full name.'],
            'email': ['Enter a valid email address'],
          },
        },
      ));

      expect(rejection, isNotNull);
      expect(rejection!.fieldErrors['fullName'], 'Enter the full name.');
      expect(rejection.fieldErrors['email'], 'Enter a valid email address');
      expect(rejection.roleLimitReached, isFalse);
    });

    test('§4.3 is recognised from the pre-check, which arrives as a 409', () {
      final rejection = staffRejectionFrom(const FunctionException(
        status: 409,
        details: {
          'error': 'This hostel already has an active manager. '
              'Deactivate the current manager first.',
        },
      ));

      expect(rejection!.roleLimitReached, isTrue);
      expect(rejection.fieldErrors, isEmpty, reason: 'nothing the owner can retype fixes it');
    });

    test('§4.3 is recognised from the trigger too, which arrives as a 400 after rollback', () {
      // rollbackAwareError() hard-codes 400 once the half-created auth user has been removed,
      // so the status alone cannot tell this from a validation failure.
      final rejection = staffRejectionFrom(const FunctionException(
        status: 400,
        details: {
          'error': 'This hostel already has an active warden. '
              'Deactivate the current warden first.',
        },
      ));

      expect(rejection!.roleLimitReached, isTrue);
    });

    test('a duplicate email lands under the email box', () {
      final rejection = staffRejectionFrom(const FunctionException(
        status: 409,
        details: {'error': 'An account with this email already exists.'},
      ));

      expect(rejection!.fieldErrors['email'], 'An account with this email already exists.');
      expect(rejection.roleLimitReached, isFalse);
    });

    test('a 500 is not a rejection — it is not something a field edit fixes', () {
      expect(
        staffRejectionFrom(const FunctionException(
          status: 500,
          details: {'error': 'Something went wrong. Please try again.'},
        )),
        isNull,
      );
    });
  });

  group('staffFailureFrom', () {
    test('no response at all is offline, and offline is retryable', () {
      final failure = staffFailureFrom(const FunctionsFetchException(details: 'SocketException'));
      expect(failure, isA<OfflineFailure>());
      expect(failure.isRetryable, isTrue);
    });

    test('a lapsed subscription is a billing problem, not a permissions one', () {
      final failure = staffFailureFrom(const FunctionException(
        status: 403,
        details: {'error': 'Subscription expired — the hostel is read-only until it is renewed.'},
      ));
      expect(failure, isA<ReadOnlyFailure>());
    });

    test('a suspended hostel is read-only too', () {
      expect(
        staffFailureFrom(const FunctionException(
          status: 403,
          details: {'error': 'This hostel is suspended. Contact NIVORA support.'},
        )),
        isA<ReadOnlyFailure>(),
      );
    });

    test('any other 403 is "not yours", and offers no retry', () {
      final failure = staffFailureFrom(const FunctionException(
        status: 403,
        details: {'error': 'Hostel not found.'},
      ));
      expect(failure, isA<AccessDeniedFailure>());
      expect(failure.isRetryable, isFalse);
    });

    test('401 ends the session rather than blaming the form', () {
      expect(
        staffFailureFrom(const FunctionException(status: 401, details: {'error': 'expired'})),
        isA<SignedOutFailure>(),
      );
    });

    test('the rate limiter, open or fail-closed, both say wait', () {
      expect(staffFailureFrom(const FunctionException(status: 429)), isA<ServerFailure>());
      expect(staffFailureFrom(const FunctionException(status: 503)), isA<ServerFailure>());
    });

    test('a failed rollback keeps the function\'s own message, orphan id and all', () {
      const report = 'Could not create the account. The half-created login could NOT be removed '
          'automatically — delete auth user 1234 in the Supabase dashboard before retrying.';
      final failure = staffFailureFrom(
        const FunctionException(status: 500, details: {'error': report}),
      );
      expect(failure.message, report);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // THE LIST
  // ───────────────────────────────────────────────────────────────────────────
  group('the staff list', () {
    testWidgets('shows both posts, and who holds them', (tester) async {
      await _pump(
        tester,
        _overrides(staff: [
          _member(name: 'Ravi Kulkarni', role: StaffRole.manager),
          _member(
            id: 'u-2',
            name: 'Priya Nair',
            role: StaffRole.warden,
            email: 'priya@example.com',
          ),
        ]),
      );

      expect(find.text('MANAGER'), findsOneWidget);
      expect(find.text('WARDEN'), findsOneWidget);
      expect(find.text('Ravi Kulkarni'), findsOneWidget);
      expect(find.text('Priya Nair'), findsOneWidget);
      // The login id is on screen — it is what the owner has to read out to them.
      expect(find.text('ravi@example.com'), findsOneWidget);
    });

    testWidgets('an empty PG says which posts are unfilled rather than showing nothing',
        (tester) async {
      await _pump(tester, _overrides(staff: const []));

      expect(find.text('No manager yet'), findsOneWidget);
      expect(find.text('No warden yet'), findsOneWidget);
      expect(find.text('Add manager'), findsOneWidget);
      expect(find.text('Add warden'), findsOneWidget);
    });

    testWidgets('§4.3 — Add is disabled while the post is filled, and says why', (tester) async {
      await _pump(
        tester,
        _overrides(staff: [_member(name: 'Ravi Kulkarni', role: StaffRole.manager)]),
      );

      final addManager = tester.widget<FilledButton>(
        find.ancestor(of: find.text('Add manager'), matching: find.byType(FilledButton)),
      );
      final addWarden = tester.widget<FilledButton>(
        find.ancestor(of: find.text('Add warden'), matching: find.byType(FilledButton)),
      );

      expect(addManager.onPressed, isNull, reason: 'the manager post is taken');
      expect(addWarden.onPressed, isNotNull, reason: 'the warden post is free');
      expect(
        find.textContaining('Deactivate Ravi Kulkarni to free the post'),
        findsOneWidget,
      );
    });

    testWidgets('an inactive holder can be reactivated, and the post counts as free',
        (tester) async {
      await _pump(
        tester,
        _overrides(staff: [
          _member(name: 'Ravi Kulkarni', status: StaffStatus.inactive),
        ]),
      );

      expect(find.text('Reactivate'), findsOneWidget);
      expect(find.text('Deactivate'), findsNothing);
      final addManager = tester.widget<FilledButton>(
        find.ancestor(of: find.text('Add manager'), matching: find.byType(FilledButton)),
      );
      expect(addManager.onPressed, isNotNull);
    });

    testWidgets('a failed load says so instead of showing two empty posts', (tester) async {
      // Zero staff and a broken connection are different facts. Reporting the second as the
      // first is how an owner concludes their warden's account vanished.
      await _pump(
        tester,
        _overrides(staffError: const OfflineFailure('offline')),
      );

      expect(find.text('No connection'), findsOneWidget);
      expect(find.text('No manager yet'), findsNothing);
    });

    testWidgets('deactivating asks first, then sends the status the button promised',
        (tester) async {
      final writes = _FakeWrites();
      await _pump(
        tester,
        _overrides(
          staff: [_member(id: 'u-7', name: 'Ravi Kulkarni')],
          writes: writes,
        ),
      );

      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();
      expect(find.text('Deactivate Ravi Kulkarni?'), findsOneWidget);
      expect(writes.statusCalls, 0, reason: 'nothing happens until it is confirmed');

      // Cancel really cancels.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes.statusCalls, 0);

      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
      await _tick(tester);

      expect(writes.statusCalls, 1);
      expect(writes.lastStatusUserId, 'u-7');
      expect(writes.lastStatus, StaffStatus.inactive);
    });

    testWidgets('a refused deactivation is reported, not silently swallowed', (tester) async {
      final writes = _FakeWrites(
        throws: const AccessDeniedFailure('That account is not yours to change.'),
      );
      await _pump(
        tester,
        _overrides(staff: [_member(name: 'Ravi Kulkarni')], writes: writes),
      );

      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
      await _tick(tester);

      expect(find.text('That account is not yours to change.'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // THE ADD FORM
  // ───────────────────────────────────────────────────────────────────────────
  group('the add-staff sheet', () {
    testWidgets('a blank form never reaches the network', (tester) async {
      final writes = _FakeWrites();
      await _pump(tester, _overrides(writes: writes));

      await tester.tap(find.text('Add manager'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create manager account'));
      await _tick(tester);

      // Every create is rate-limited and every one that gets through mints a credential, so a
      // form the server would certainly refuse must not cost an attempt.
      expect(writes.createCalls, 0);
      expect(find.text('Enter the full name.'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    testWidgets('a valid form sends the body index.ts parses', (tester) async {
      final writes = _FakeWrites(
        outcome: const StaffCreated(IssuedStaffCredentials(
          userId: 'u-9',
          name: 'Priya Nair',
          roleLabel: 'Warden',
          loginId: 'priya@example.com',
          password: 'Tx7-quiet-lamp',
        )),
      );
      await _pump(tester, _overrides(writes: writes));

      await tester.tap(find.text('Add warden'));
      await tester.pumpAndSettle();
      await _fillValidForm(tester);
      await tester.tap(find.text('Create warden account'));
      await _tick(tester);

      expect(writes.createCalls, 1);
      expect(writes.lastHostelId, _hostelId);
      expect(writes.lastDraft!.toJson(_hostelId), {
        'role': 'warden',
        'fullName': 'Priya Nair',
        'email': 'priya@example.com',
        'phone': '98765 43210',
        'hostelId': _hostelId,
      });
    });

    testWidgets('§4.3 is shown as a next step, not as a database error', (tester) async {
      final writes = _FakeWrites(
        outcome: const StaffRejected(
          'This hostel already has an active warden. Deactivate the current warden first.',
          roleLimitReached: true,
        ),
      );
      await _pump(tester, _overrides(writes: writes));

      await tester.tap(find.text('Add warden'));
      await tester.pumpAndSettle();
      await _fillValidForm(tester);
      await tester.tap(find.text('Create warden account'));
      await _tick(tester);

      expect(
        find.text('This hostel already has an active warden. '
            'Deactivate the current warden first.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('deactivate the person holding that post'),
        findsOneWidget,
        reason: 'the rule is only useful with the way out of it attached',
      );
      // The sheet stays open — nothing was created, and the typing is still worth something.
      expect(find.text('ADD STAFF'), findsOneWidget);
    });

    testWidgets('a duplicate email is put under the email box', (tester) async {
      final writes = _FakeWrites(
        outcome: const StaffRejected(
          'An account with this email already exists.',
          fieldErrors: {'email': 'An account with this email already exists.'},
        ),
      );
      await _pump(tester, _overrides(writes: writes));

      await tester.tap(find.text('Add manager'));
      await tester.pumpAndSettle();
      await _fillValidForm(tester);
      await tester.tap(find.text('Create manager account'));
      await _tick(tester);

      final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Email'));
      expect(field.decoration!.errorText, 'An account with this email already exists.');
    });

    testWidgets('being offline is a connection card, not a field message', (tester) async {
      final writes = _FakeWrites(
        throws: const OfflineFailure('Cannot reach Nivora. Check your connection and try again.'),
      );
      await _pump(tester, _overrides(writes: writes));

      await tester.tap(find.text('Add manager'));
      await tester.pumpAndSettle();
      await _fillValidForm(tester);
      await tester.tap(find.text('Create manager account'));
      await _tick(tester);

      expect(find.text('No connection'), findsOneWidget);
      expect(writes.createCalls, 1);
    });

    testWidgets('a taken post is drawn as taken in the role picker', (tester) async {
      await _pump(
        tester,
        _overrides(staff: [_member(role: StaffRole.manager)], writes: _FakeWrites()),
      );

      await tester.tap(find.text('Add warden'));
      await tester.pumpAndSettle();

      // The picker is two [StaffRoleCard]s rather than a SegmentedButton — the design draws
      // each role as a card with its own description, so both descriptions are readable while
      // the choice is being made. Same behaviour under test: the post that already has an
      // active holder cannot be chosen, and the free one is what the sheet opened on.
      StaffRoleCard card(StaffRole role) => tester.widget<StaffRoleCard>(
            find.byWidgetPredicate((w) => w is StaffRoleCard && w.role == role),
          );

      expect(card(StaffRole.manager).enabled, isFalse);
      expect(card(StaffRole.manager).taken, isTrue);
      expect(card(StaffRole.warden).enabled, isTrue);
      expect(card(StaffRole.warden).selected, isTrue);
      expect(card(StaffRole.manager).selected, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // THE SHOW-ONCE DIALOG
  // ───────────────────────────────────────────────────────────────────────────
  group('the credentials dialog', () {
    const creds = IssuedStaffCredentials(
      userId: 'u-9',
      name: 'Priya Nair',
      roleLabel: 'Warden',
      loginId: 'priya@example.com',
      password: 'Tx7-quiet-lamp',
    );

    Future<void> show(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: NivoraTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => StaffCredentialsDialog.show(
                  context,
                  credentials: creds,
                  hostelName: 'Sunrise Residency',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the login and the password, and names the PG', (tester) async {
      await show(tester);

      expect(find.text('Warden account created'), findsOneWidget);
      expect(find.text('Sunrise Residency'), findsOneWidget);
      expect(find.text('priya@example.com'), findsOneWidget);
      expect(find.text('Tx7-quiet-lamp'), findsOneWidget);
      expect(find.textContaining('shown once and is stored nowhere'), findsOneWidget);
    });

    testWidgets('Done is dead until the owner says they have saved it', (tester) async {
      await show(tester);

      FilledButton done() => tester.widget<FilledButton>(
            find.ancestor(of: find.text('Done'), matching: find.byType(FilledButton)),
          );

      expect(done().onPressed, isNull);

      await tester.tap(find.text('I have saved these credentials'));
      await tester.pumpAndSettle();
      expect(done().onPressed, isNotNull);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Tx7-quiet-lamp'), findsNothing);
    });

    testWidgets('a tap outside cannot take the password away', (tester) async {
      await show(tester);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(find.text('Tx7-quiet-lamp'), findsOneWidget);
    });

    testWidgets('neither can the back gesture', (tester) async {
      await show(tester);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('Tx7-quiet-lamp'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CREATE → DIALOG → CLOSE, END TO END
  // ───────────────────────────────────────────────────────────────────────────
  testWidgets('a successful create hands over the password before the sheet closes',
      (tester) async {
    final writes = _FakeWrites(
      outcome: const StaffCreated(IssuedStaffCredentials(
        userId: 'u-9',
        name: 'Priya Nair',
        roleLabel: 'Warden',
        loginId: 'priya@example.com',
        password: 'Tx7-quiet-lamp',
      )),
    );
    await _pump(tester, _overrides(writes: writes));

    await tester.tap(find.text('Add warden'));
    await tester.pumpAndSettle();
    await _fillValidForm(tester);
    await tester.tap(find.text('Create warden account'));
    await _tick(tester);

    // The dialog is up and the sheet is still behind it — the password has crossed no route
    // boundary on its way to the screen.
    expect(find.text('Tx7-quiet-lamp'), findsOneWidget);
    expect(find.text('ADD STAFF'), findsOneWidget);

    await tester.tap(find.text('I have saved these credentials'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Tx7-quiet-lamp'), findsNothing);
    expect(find.text('ADD STAFF'), findsNothing, reason: 'the sheet closes on its own after');
  });
}
