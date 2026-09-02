// Registering a resident, and the one property that changed: THE WARDEN NOW HANDS OVER A LOGIN.
//
// This flow used to be a plain INSERT with user_id null — the resident appeared on the roster
// and could not sign in until somebody finished the job in the web console. It now posts to
// supabase/functions/warden-register-student, which mints the auth user with the service-role
// key it holds SERVER-SIDE, uploads the documents, calls wd_register_student as the warden, and
// returns a temporary password exactly once.
//
// Every test below guards a way that flow can quietly stop being true:
//   • the request body drifting from the contract in docs/edge-functions.md §7
//   • four megabytes of ID scan being pushed up a stairwell connection before anyone notices
//     the guardian's name is blank
//   • "A student with this phone number already has an account" arriving as a generic
//     "something went wrong" instead of a message under the phone box
//   • the one-and-only copy of the password being dismissible with a stray tap
//
// Nothing here touches a network, a database or a device. `wardenRegistrationsProvider` is typed
// by [StudentRegistrations] and `documentCaptureProvider` by [DocumentCapture] precisely so both
// can be replaced — image_picker is a MethodChannel plugin and a widget test has no platform on
// the other end of one.
//
// The stock Material theme is used rather than NivoraTheme, as in warden_test.dart: NivoraTheme
// is built on google_fonts, which reaches for the network from inside the test binary.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/features/warden/actions/register_student_sheet.dart';
import 'package:mobile/features/warden/actions/student_credentials_dialog.dart';
import 'package:mobile/features/warden/data/warden_providers.dart';
import 'package:mobile/features/warden/data/warden_repository.dart';

const _hostelId = 'h1';
const _bedId = '7c9e6679-7425-40de-944b-e07fc1f90ae7';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('the request body is the contract in docs/edge-functions.md §7', () {
    test('every key index.ts parses is sent, under the name it parses', () {
      final json = _draft().toJson();

      // parseBody() in warden-register-student/index.ts, field for field.
      expect(json.keys.toSet(), {
        'fullName',
        'phone',
        'dateOfJoining',
        'guardianName',
        'guardianPhone',
        'permanentAddress',
        'idProofType',
        'bedId',
        'monthlyFee',
        'idProofBase64',
      });
    });

    test('there is no hostelId, and there must not be', () {
      // The function accepts none. A warden belongs to one hostel and users.hostel_id is the
      // tenant for the login, the uploads and the rows — sending one would be a value the
      // server would have to decide whether to trust.
      expect(_draft().toJson().containsKey('hostelId'), isFalse);
    });

    test('the joining date is a plain YYYY-MM-DD, not an ISO instant', () {
      // v.isoDate() rejects anything else, and `date` in Postgres would truncate a timestamp in
      // the server's zone — off by one for every registration after 18:30 IST.
      final json = _draft(joining: DateTime(2026, 8, 25, 23, 45)).toJson();
      expect(json['dateOfJoining'], '2026-08-25');
    });

    test('the ID proof travels as base64 and the optional halves are omitted, not null', () {
      final json = _draft().toJson();
      // 'AAAA' is base64 for three 0x00 bytes; _doc() fills its bytes with zeroes.
      expect(json['idProofBase64'], isA<String>());
      expect((json['idProofBase64']! as String).isNotEmpty, isTrue);
      expect(json.containsKey('photoBase64'), isFalse, reason: 'no photo was attached');
      expect(json.containsKey('email'), isFalse, reason: 'no email was entered');
    });

    test('a photo and an email are sent when there are any', () {
      final json = _draft(email: 'aarav@example.com', photo: _doc(12)).toJson();
      expect(json['email'], 'aarav@example.com');
      expect(json['photoBase64'], isA<String>());
    });

    test('the ID proof type is the wire value the web app stores', () {
      // ID_PROOF_TYPES in index.ts is exactly these six strings, and students.id_proof_type is
      // free text — 'aadhaar' from a phone would file the same document under a second spelling.
      expect(IdProofType.values.map((t) => t.wire).toList(), [
        'Aadhaar',
        'PAN',
        'Passport',
        'Driving licence',
        'Voter ID',
        'Other',
      ]);
    });

    test('the 3 MB ceiling storage.ts enforces is known before the upload', () {
      expect(_doc(3 * 1024 * 1024).isTooLarge, isFalse);
      expect(_doc(3 * 1024 * 1024 + 1).isTooLarge, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the response is read the way the function writes it', () {
    test('a successful registration carries the credentials', () {
      final result = RegisteredStudent.fromJson({
        'studentId': 's1',
        'roomId': 'r1',
        'credentials': {
          'name': 'Aarav Sharma',
          'loginId': '9876500042',
          'password': 'Sage-7413-Kite',
        },
      });
      expect(result.studentId, 's1');
      expect(result.roomId, 'r1');
      // With no email collected the login id is the PHONE NUMBER, not the synthetic address
      // the auth user actually carries.
      expect(result.credentials.loginId, '9876500042');
    });

    test('a registration with an email carries the email as the login id', () {
      // createStudentAuthUser sends `loginId: input.email ?? input.phone`. The client reads it
      // rather than deriving it — the server is the only party that knows which of the two
      // boxes the login was minted from.
      final result = RegisteredStudent.fromJson({
        'studentId': 's1',
        'roomId': 'r1',
        'credentials': {
          'name': 'Aarav Sharma',
          'loginId': 'aarav@example.com',
          'password': 'Sage-7413-Kite',
        },
      });
      expect(result.credentials.loginId, 'aarav@example.com');
    });

    test('a null roomId is "could not look it up", not a crash', () {
      // The function reads the room AFTER the resident exists and swallows a failure to,
      // because failing to read it is not a failure to register.
      final result = RegisteredStudent.fromJson({
        'studentId': 's1',
        'roomId': null,
        'credentials': {'name': 'A', 'loginId': '9876500042', 'password': 'p'},
      });
      expect(result.roomId, isNull);
    });

    test('a response with no credentials is a shape error, not a silent success', () {
      // A login was created and its password was not returned: the resident cannot sign in and
      // nobody can tell them why. Better to fail loudly than to show a success screen.
      expect(
        () => RegisteredStudent.fromJson({'studentId': 's1', 'roomId': null}),
        throwsA(isA<RowShapeError>()),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the sheet asks for everything the function requires', () {
    testWidgets('every mandatory field is on the form', (tester) async {
      final registrations = _FakeRegistrations();
      await _open(tester, registrations: registrations);

      for (final label in [
        'Full name',
        'Phone number',
        'Monthly rent',
        'Joined on',
        'Bed',
        'Guardian name',
        'Guardian phone',
        'Permanent address',
        'ID proof type',
        'ID proof file',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('the email box is on the form and says what it does', (tester) async {
      // The owner asked for students to be able to sign in with an email address. The box has
      // to be visible at the desk — it used to sit under "Optional" below the photo, which is
      // where a warden stops reading.
      await _open(tester, registrations: _FakeRegistrations());

      expect(find.text('Email'), findsOneWidget);
      // Blank: the phone number is the login and the form says so, under the phone.
      expect(find.text('This is the login id they sign in with'), findsOneWidget);
      expect(
        find.text('Optional — without one they sign in with their phone number'),
        findsOneWidget,
      );
    });

    testWidgets('typing an email moves the "this is the login" line onto it', (tester) async {
      // The two boxes trade the sentence between them. If it did not move, a warden would read
      // "this is the login id" under the phone number and hand over the half that does not
      // work — an account created thirty seconds ago that the resident cannot open.
      await _open(tester, registrations: _FakeRegistrations());
      await tester.enterText(_field('Email'), 'aarav@example.com');
      await tester.pump();

      expect(find.text('For contact and the fee ledger'), findsOneWidget);
      expect(find.text('This is the login id they sign in with'), findsOneWidget);
      expect(
        find.text('Optional — without one they sign in with their phone number'),
        findsNothing,
      );
    });

    testWidgets('the notice no longer sends the warden to the web console', (tester) async {
      await _open(tester, registrations: _FakeRegistrations());

      // The exact promise the old sheet made. It was true when it was written and is not now;
      // a stale notice asserting the opposite of what the code does is worse than none.
      expect(find.textContaining('web console'), findsNothing);
      expect(find.textContaining('not allowed to create'), findsNothing);
      expect(find.textContaining('also creates their app login'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('validation runs before anything is sent', () {
    testWidgets('an empty form does not reach the server', (tester) async {
      final registrations = _FakeRegistrations();
      await _open(tester, registrations: registrations);

      await tester.tap(_registerButton);
      await tester.pump();

      // The point of the whole exercise: an ID scan is the largest request this app makes, and
      // it must not travel before the free checks have run.
      expect(registrations.calls, isEmpty);
      expect(find.text("Enter the student's full name"), findsOneWidget);
      expect(find.text("Enter the guardian's name"), findsOneWidget);
      expect(find.text('Enter the permanent address'), findsOneWidget);
      expect(find.text('Pick a free bed'), findsOneWidget);
      expect(find.text('Choose an ID proof type'), findsOneWidget);
      expect(find.text('ID proof file is required'), findsOneWidget);
    });

    testWidgets('a filled form with no ID proof still does not reach the server',
        (tester) async {
      final registrations = _FakeRegistrations();
      // The picker hands back nothing — the warden opened it and backed out.
      await _open(tester, registrations: registrations, capture: _FakeCapture(document: null));
      await _fill(tester, attachIdProof: true);

      await tester.tap(_registerButton);
      await tester.pump();

      expect(registrations.calls, isEmpty);
      expect(find.text('ID proof file is required'), findsOneWidget);
    });

    testWidgets('a complete form does reach the server, with what was typed', (tester) async {
      final registrations = _FakeRegistrations();
      await _open(tester, registrations: registrations);
      await _fill(tester);

      await tester.tap(_registerButton);
      await tester.pump();
      await tester.pump();

      expect(registrations.calls, hasLength(1));
      final sent = registrations.calls.single;
      expect(sent.fullName, 'Aarav Sharma');
      // Normalised, not as typed: this string becomes the login id, and the web app derives the
      // same synthetic address from it.
      expect(sent.phone, '9876500042');
      expect(sent.guardianPhone, '9876500043');
      expect(sent.bedId, _bedId);
      expect(sent.idProofType, IdProofType.aadhaar);
      expect(sent.monthlyFee, 7500);
      // Nothing was typed in the email box, so nothing is claimed. The server then mints the
      // phone-mapped login, exactly as before this feature existed.
      expect(sent.email, isNull);
    });

    testWidgets('an email that was typed is what travels', (tester) async {
      final registrations = _FakeRegistrations();
      await _open(tester, registrations: registrations);
      await _fill(tester, email: 'Aarav@Example.com');

      await tester.tap(_registerButton);
      await tester.pump();
      await tester.pump();

      expect(registrations.calls, hasLength(1));
      // Trimmed, not otherwise touched. The Edge Function lowercases it — one place, so the
      // address stored and the address GoTrue registers cannot disagree.
      expect(registrations.calls.single.email, 'Aarav@Example.com');
    });

    testWidgets('an address in the phone-mapping domain never leaves the form', (tester) async {
      // "@student.hostelpro.local" is not a real mail domain. An address inside it would mint
      // the login id belonging to whoever actually holds 9000000001 — and, because GoTrue
      // never releases a registered address, would block that resident from being registered
      // at all, with nothing on any screen explaining why.
      final registrations = _FakeRegistrations();
      await _open(tester, registrations: registrations);
      await _fill(tester, email: '9000000001@student.hostelpro.local');

      await tester.tap(_registerButton);
      await tester.pump();

      expect(registrations.calls, isEmpty);
      expect(find.text('Enter a real email address'), findsOneWidget);
    });

    testWidgets('a malformed email is caught before the ID scan is uploaded', (tester) async {
      final registrations = _FakeRegistrations();
      await _open(tester, registrations: registrations);
      await _fill(tester, email: 'aarav@example');

      await tester.tap(_registerButton);
      await tester.pump();

      expect(registrations.calls, isEmpty);
      expect(find.text('Enter a valid email'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('a refusal lands on the field it is about', () {
    testWidgets('a duplicate phone is a field error, not a generic failure', (tester) async {
      // createStudentAuthUser() raises this with HTTP 409 and NO fieldErrors, so the repository
      // infers the field from the sentence. If that inference broke, this message would appear
      // as a snackbar over a form with nothing highlighted — and the warden would retry the
      // same number.
      const message = 'A student with this phone number already has an account.';
      final registrations = _FakeRegistrations(
        outcome: const RegistrationRejected(message, fieldErrors: {'phone': message}),
      );
      await _open(tester, registrations: registrations);
      await _fill(tester);

      await tester.tap(_registerButton);
      await tester.pump();
      await tester.pump();

      expect(registrations.calls, hasLength(1));
      // Under the phone box, inside the form — not in a snackbar.
      expect(find.text(message), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(StudentCredentialsDialog), findsNothing);
      // Still open, still holding what was typed, so the number can be corrected in place.
      expect(_registerButton, findsOneWidget);
    });

    testWidgets('editing the phone clears the message that described the old one',
        (tester) async {
      const message = 'A student with this phone number already has an account.';
      final registrations = _FakeRegistrations(
        outcome: const RegistrationRejected(message, fieldErrors: {'phone': message}),
      );
      await _open(tester, registrations: registrations);
      await _fill(tester);
      await tester.tap(_registerButton);
      await tester.pump();
      await tester.pump();
      expect(find.text(message), findsOneWidget);

      await tester.enterText(_field('Phone number'), '9876500099');
      await tester.pump();

      expect(find.text(message), findsNothing);
    });

    testWidgets('a bed taken since the list loaded drops the stale choice', (tester) async {
      // students_one_active_per_bed settles the race between two wardens on two phones. The
      // loser must not be left staring at a bed label that is already wrong.
      const message = 'That bed is already occupied. Choose a free bed.';
      final registrations = _FakeRegistrations(
        outcome: const RegistrationRejected(message, fieldErrors: {'bedId': message}),
      );
      await _open(tester, registrations: registrations);
      await _fill(tester);
      expect(find.text('Room 101 · Bed 2'), findsOneWidget);

      await tester.tap(_registerButton);
      await tester.pump();
      await tester.pump();

      expect(find.text(message), findsOneWidget);
      expect(find.text('Room 101 · Bed 2'), findsNothing, reason: 'the stale bed is cleared');
      expect(find.text('Choose a bed'), findsOneWidget);
    });

    testWidgets('a lapsed subscription is a failure, not a field message', (tester) async {
      // assertWritable() and wd_register_student both refuse with 403. Nothing on this form can
      // be edited to fix it, so it must not be pinned under a field — it is the owner's
      // conversation with billing.
      final registrations = _FakeRegistrations(
        error: const ReadOnlyFailure(
          'Subscription expired — the hostel is read-only until it is renewed.',
        ),
      );
      await _open(tester, registrations: registrations);
      await _fill(tester);

      await tester.tap(_registerButton);
      await tester.pump();
      await tester.pump();

      expect(registrations.calls, hasLength(1));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('read-only until it is renewed'),
        findsOneWidget,
      );
      expect(find.byType(StudentCredentialsDialog), findsNothing);
    });

    testWidgets('offline says the resident was NOT registered', (tester) async {
      // The one sentence a warden needs when the spinner stops: whether to do it again.
      final registrations = _FakeRegistrations(
        error: const OfflineFailure(
          'Cannot reach Nivora. The resident was NOT registered — check your connection and '
          'try again.',
        ),
      );
      await _open(tester, registrations: registrations);
      await _fill(tester);

      await tester.tap(_registerButton);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('was NOT registered'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the password is shown once and is hard to lose', () {
    testWidgets('a successful registration opens the credentials dialog', (tester) async {
      await _open(tester, registrations: _FakeRegistrations());
      await _fill(tester);

      await tester.tap(_registerButton);
      await tester.pump();
      await tester.pump();

      expect(find.byType(StudentCredentialsDialog), findsOneWidget);
      // BOTH halves. A student signs in by phone; the password alone is half a credential.
      // Scoped to the dialog: the sheet behind it still holds the same number in its phone box.
      expect(_inDialog('9876500042'), findsOneWidget);
      expect(_inDialog('Sage-7413-Kite'), findsOneWidget);
    });

    testWidgets('the dialog names the half that actually signs them in', (tester) async {
      // The dialog is the ONLY place anyone is told which of the two boxes became the login,
      // and it is shown once. A hard-coded "Phone (login)" over an email address would send
      // the resident to the sign-in screen with the string that does not work.
      await _pumpDialog(tester, loginId: '9876500042');
      // _CredentialRow upper-cases the label it draws.
      expect(find.text('PHONE (LOGIN)'), findsOneWidget);
      expect(find.text('EMAIL (LOGIN)'), findsNothing);
      expect(find.textContaining('sign in with their phone number'), findsOneWidget);
    });

    testWidgets('an email login is labelled as an email, not as a phone number',
        (tester) async {
      await _pumpDialog(tester, loginId: 'aarav@example.com');
      expect(find.text('EMAIL (LOGIN)'), findsOneWidget);
      expect(find.text('PHONE (LOGIN)'), findsNothing);
      expect(find.text('aarav@example.com'), findsOneWidget);
      expect(find.textContaining('sign in with this email address'), findsOneWidget);
    });

    testWidgets('the dialog cannot be dismissed until the warden confirms', (tester) async {
      await _pumpDialog(tester);

      expect(find.byType(StudentCredentialsDialog), findsOneWidget);

      // 1. A tap outside. barrierDismissible is false.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(find.byType(StudentCredentialsDialog), findsOneWidget);

      // 2. The Android back gesture. PopScope(canPop: false).
      final popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(StudentCredentialsDialog), findsOneWidget,
          reason: 'back must not be a way past the confirmation (handled: $popped)');

      // 3. Done, before ticking the box.
      final done = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Done'),
      );
      expect(done.onPressed, isNull, reason: 'Done is disabled until the box is ticked');
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(find.byType(StudentCredentialsDialog), findsOneWidget);
    });

    testWidgets('ticking the box is the only way out', (tester) async {
      await _pumpDialog(tester);

      await tester.tap(find.text('I have saved these credentials'));
      await tester.pump();

      final done = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Done'),
      );
      expect(done.onPressed, isNotNull);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(StudentCredentialsDialog), findsNothing);
    });

    testWidgets('the sheet stays open behind the dialog until it is confirmed',
        (tester) async {
      // Popping the sheet first would take the dialog's context with it, and the resident would
      // have an account nobody can sign in to.
      await _open(tester, registrations: _FakeRegistrations());
      await _fill(tester);
      await tester.tap(_registerButton);
      await tester.pump();
      await tester.pump();

      expect(find.byType(StudentCredentialsDialog), findsOneWidget);

      await tester.tap(find.text('I have saved these credentials'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(StudentCredentialsDialog), findsNothing);
      // Now — and only now — the sheet closes and the roster is told.
      expect(_registerButton, findsNothing);
      expect(find.text('Aarav Sharma registered'), findsOneWidget);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FAKES
// ─────────────────────────────────────────────────────────────────────────────

final class _FakeRegistrations implements StudentRegistrations {
  _FakeRegistrations({this.outcome, this.error});

  /// What the server decided. Defaults to a successful registration with credentials.
  final RegistrationOutcome? outcome;

  /// Something that is not about the input — offline, 403, a failed rollback.
  final Object? error;

  /// Every draft that actually left the form. Empty is the assertion that matters most.
  final List<StudentRegistration> calls = [];

  @override
  Future<RegistrationOutcome> registerStudent(StudentRegistration draft) async {
    calls.add(draft);
    final failure = error;
    if (failure != null) throw failure;
    return outcome ??
        const RegistrationSucceeded(
          RegisteredStudent(
            studentId: 's1',
            roomId: 'r1',
            credentials: StudentCredentials(
              name: 'Aarav Sharma',
              loginId: '9876500042',
              password: 'Sage-7413-Kite',
            ),
          ),
        );
  }
}

final class _FakeCapture implements DocumentCapture {
  _FakeCapture({this.document});

  /// Null is a cancelled pick, which is not an error and must not be reported as one.
  final CapturedDocument? document;
  final List<CaptureSource> picks = [];

  @override
  Future<CapturedDocument?> pick(CaptureSource source) async {
    picks.add(source);
    return document;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FIXTURES
// ─────────────────────────────────────────────────────────────────────────────

CapturedDocument _doc([int bytes = 2048]) => CapturedDocument(
      bytes: Uint8List(bytes),
      name: 'aadhaar.jpg',
    );

StudentRegistration _draft({
  DateTime? joining,
  String? email,
  CapturedDocument? photo,
}) =>
    StudentRegistration(
      fullName: 'Aarav Sharma',
      phone: '9876500042',
      email: email,
      dateOfJoining: joining ?? DateTime(2026, 8, 25),
      guardianName: 'Ramesh Sharma',
      guardianPhone: '9876500043',
      permanentAddress: '14 Nehru Road, Pune',
      idProofType: IdProofType.aadhaar,
      idProof: _doc(),
      photo: photo,
      bedId: _bedId,
      monthlyFee: 7500,
    );

List<FreeBed> _freeBeds() => [
      FreeBed(
        bed: Bed(
          id: _bedId,
          hostelId: _hostelId,
          roomId: 'r1',
          bedNumber: 2,
          status: BedStatus.free,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
        roomNumber: '101',
        floorNumber: 1,
      ),
    ];

// ─────────────────────────────────────────────────────────────────────────────
// HARNESS
//
// A TALL VIEWPORT, deliberately. SheetBody caps a sheet at 88% of the display and the form is
// long; on the default 800x600 test surface half the fields sit outside the hit-test area and
// every tap below would need its own ensureVisible. Making the surface tall enough for the whole
// form is the same test with less ceremony — nothing under test depends on the height.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _open(
  WidgetTester tester, {
  required _FakeRegistrations registrations,
  _FakeCapture? capture,
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        wardenRegistrationsProvider.overrideWithValue(registrations),
        documentCaptureProvider.overrideWithValue(capture ?? _FakeCapture(document: _doc())),
        freeBedOptionsProvider.overrideWith((ref, hostelId) => _freeBeds()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showRegisterStudentSheet(context, hostelId: _hostelId),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Fills the form the way a warden would, through the widgets rather than around them.
///
/// [attachIdProof] false skips the ID proof entirely; true still taps the camera button, which
/// is how the "picker returned nothing" case is exercised.
Future<void> _fill(
  WidgetTester tester, {
  bool attachIdProof = true,
  /// Null leaves the box empty, which is the common case — the resident has no email and the
  /// phone mapping is what mints their login.
  String? email,
}) async {
  await tester.enterText(_field('Full name'), 'Aarav Sharma');
  // Typed the way people type it. normalisePhone() is what makes this the same string the web
  // app writes, and the assertion on `sent.phone` is what proves it ran.
  await tester.enterText(_field('Phone number'), '9876500042');
  if (email != null) await tester.enterText(_field('Email'), email);
  await tester.enterText(_field('Monthly rent'), '7500');
  await tester.enterText(_field('Guardian name'), 'Ramesh Sharma');
  await tester.enterText(_field('Guardian phone'), '9876500043');
  await tester.enterText(_field('Permanent address'), '14 Nehru Road, Pune');
  await tester.pump();

  // The bed picker is a second sheet on top of this one.
  await tester.tap(find.text('Choose a bed'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Room 101 · Bed 2'));
  await tester.pumpAndSettle();

  await tester.tap(find.byType(DropdownButtonFormField<IdProofType>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Aadhaar').last);
  await tester.pumpAndSettle();

  if (attachIdProof) {
    // The ID proof's camera button, not the optional photo's — both carry this tooltip and the
    // ID proof is the first of the two on the form.
    await tester.tap(find.byTooltip('Take a photo').first);
    await tester.pumpAndSettle();
  }
}

/// Text inside the credentials dialog, and not the identical text on the sheet behind it.
Finder _inDialog(String text) => find.descendant(
      of: find.byType(StudentCredentialsDialog),
      matching: find.text(text),
    );

/// The submit button. NOT `find.text('Register resident')` — the sheet's own title says the
/// same words, and a finder that matches both is a finder that matches neither.
final Finder _registerButton =
    find.widgetWithText(FilledButton, 'Register resident');

/// A TextFormField, found by the label its InputDecoration draws.
Finder _field(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextFormField),
    );

Future<void> _pumpDialog(WidgetTester tester, {String loginId = '9876500042'}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => StudentCredentialsDialog.show(
                context,
                credentials: StudentCredentials(
                  name: 'Aarav Sharma',
                  loginId: loginId,
                  password: 'Sage-7413-Kite',
                ),
                bedLabel: 'Room 101 · Bed 2',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
