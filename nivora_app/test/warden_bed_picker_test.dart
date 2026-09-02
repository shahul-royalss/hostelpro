// THE BED PICKER OPENS. That is the whole subject of this file.
//
// A warden tapped "Choose a bed" during registration and nothing happened: no sheet, no
// spinner, no message. The cause was not the data and not RLS — both were measured as the
// warden and both were fine (45 free beds, 15 rooms). It was a provider LIFETIME:
//
//   final beds = await ref.read(freeBedOptionsProvider(hostelId).future);
//
// `ref.read` takes no subscription. freeBedOptionsProvider is autoDispose, so with nothing
// listening it is torn down on the next tick — while its own body is still suspended at its
// FIRST await. When that body resumes and reaches its SECOND `ref.watch`, the Ref it is
// holding belongs to a disposed element, and riverpod 3 throws UnmountedRefException out of
// the future. Neither call site had a try/catch, so the exception went to the zone as an
// unhandled async error and the tap produced nothing at all.
//
// (The one-await shape does NOT fail this way — riverpod 3 deliberately lets a disposed
// provider's in-flight future resolve. It is specifically touching `ref` after an await gap,
// in a provider nothing is listening to, that throws. studentsAwaitingBedProvider is the
// one-await shape and could never hang; it could still fail silently, which is why the
// resident picker is in here too.)
//
// EVERY TEST BELOW OVERRIDES THE DEPENDENCIES, NOT freeBedOptionsProvider ITSELF. Overriding
// the provider under test with a synchronous list — which is what the older register-student
// test does, for its own unrelated purposes — removes the await gap and with it the entire
// bug. The fakes here are asynchronous for the same reason a real query is.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/warden/actions/assign_bed_sheet.dart';
import 'package:mobile/features/warden/actions/register_student_sheet.dart';
import 'package:mobile/features/warden/data/warden_providers.dart';
import 'package:mobile/features/warden/widgets/warden_ui.dart';

const _hostelId = 'h1';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // THE CONTRACT THAT MAKES THE WHOLE CLASS OF BUG IMPOSSIBLE.
  //
  // Every test in this group taps and then pumps ONE frame plus a few milliseconds — far less
  // than [_lag]. The sheet must already be there, showing that it is working. Nothing may be
  // awaited between the tap and the sheet, because whatever is awaited there is time in which
  // the warden is looking at a control that did nothing, and it is the exact gap the autoDispose
  // teardown used to fall into.
  //
  // These fail against a call site that reads `await ref.read(provider.future)` before calling
  // showGlassSheet, whether or not that read eventually succeeds.
  group('the tap is answered on the frame it lands', () {
    testWidgets('registration: the sheet is up before the beds are', (tester) async {
      await _openRegisterSheet(tester);

      await tester.tap(find.text('Choose a bed'));
      await _oneFrame(tester);

      expect(find.byType(FreeBedPicker), findsOneWidget,
          reason: 'nothing may be awaited between the tap and the sheet');
      expect(find.byType(CircularProgressIndicator), findsWidgets,
          reason: 'and the sheet must say it is working');
      // Loading is its own state: not the data, not empty, not failed.
      expect(find.text('Room 101 · Bed 2'), findsNothing);
      expect(find.text('Every bed is taken'), findsNothing);
      expect(find.byType(FailureState), findsNothing);

      await tester.pumpAndSettle(); // let the fake request finish; it is not what is asserted
    });

    testWidgets('assign: the sheet is up before the beds are', (tester) async {
      await _openAssignBed(tester);

      await tester.tap(find.text('go'));
      await _oneFrame(tester);

      expect(find.byType(FreeBedPicker), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('Room 101 · Bed 2'), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('place a resident: the sheet is up before the roster is', (tester) async {
      await _openPlaceResident(tester);

      await tester.tap(find.text('go'));
      await _oneFrame(tester);

      expect(find.text('Who needs a bed?'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('Aarav Sharma'), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('and the data lands in the sheet that is already open', (tester) async {
      // The other half of the lifetime fix: the sheet HOLDS the subscription, so the provider
      // and the two it depends on cannot be torn down while their requests are in flight.
      await _openRegisterSheet(tester);
      await tester.tap(find.text('Choose a bed'));
      await _oneFrame(tester);
      expect(find.byType(FreeBedPicker), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byType(FreeBedPicker), findsOneWidget, reason: 'the same sheet, still open');
      expect(find.text('Room 101 · Bed 2'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // REFUSED IS NOT FAILED. A warden whose RLS policy says no cannot be offered a retry button:
  // pressing it again cannot ever work, and a button that cannot help is a lie about the
  // situation. See AppFailure.isRefusal and FailureState.
  group('a refusal is its own state', () {
    testWidgets('names the refusal and offers no retry', (tester) async {
      await _openRegisterSheet(
        tester,
        failWith: const AccessDeniedFailure('You do not have access to that.'),
      );
      await tester.tap(find.text('Choose a bed'));
      await tester.pumpAndSettle();

      expect(find.byType(FreeBedPicker), findsOneWidget);
      // StateBadge upper-cases what it is given.
      expect(find.text('NOT ALLOWED'), findsOneWidget);
      expect(find.text('You do not have access to that.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing,
          reason: 'retrying a refusal cannot work, so the button must not be drawn');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('registration: the bed control opens a picker', () {
    testWidgets('a tap produces the picker, not silence', (tester) async {
      await _openRegisterSheet(tester);

      await tester.tap(find.text('Choose a bed'));
      await tester.pumpAndSettle();

      expect(find.byType(FreeBedPicker), findsOneWidget,
          reason: 'the tap must open the picker — a control that does nothing is a bug');
      expect(find.text('Room 101 · Bed 2'), findsOneWidget);
    });

    testWidgets('the picked bed lands on the form', (tester) async {
      await _openRegisterSheet(tester);
      await tester.tap(find.text('Choose a bed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Room 101 · Bed 2'));
      await tester.pumpAndSettle();

      expect(find.byType(FreeBedPicker), findsNothing);
      expect(find.text('Room 101 · Bed 2'), findsOneWidget, reason: 'now the field value');
    });

    testWidgets('a full building opens the picker and says the building is full',
        (tester) async {
      await _openRegisterSheet(tester, beds: const []);
      await tester.tap(find.text('Choose a bed'));
      await tester.pumpAndSettle();

      expect(find.byType(FreeBedPicker), findsOneWidget);
      expect(find.text('Every bed is taken'), findsOneWidget);
    });

    testWidgets('a failed read names the cause and leaves the control usable', (tester) async {
      await _openRegisterSheet(tester, failWith: const _Unreachable());
      await tester.tap(find.text('Choose a bed'));
      await tester.pumpAndSettle();

      expect(find.byType(FreeBedPicker), findsOneWidget,
          reason: 'a failure must be VISIBLE, and the only place to show it is the sheet');
      expect(_someFailureSentence, findsOneWidget);
      // Retryable, unlike the refusal above: losing signal in a stairwell is worth one more tap.
      expect(find.text('Try again'), findsOneWidget);

      // And the way out is still there: dismiss the sheet, the field is untouched and tappable.
      Navigator.of(tester.element(find.byType(FreeBedPicker))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Choose a bed'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('assign a bed to an existing resident', () {
    testWidgets('a tap produces the picker, not silence', (tester) async {
      await _openAssignBed(tester);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.byType(FreeBedPicker), findsOneWidget);
      expect(find.text('Room 101 · Bed 2'), findsOneWidget);
    });

    testWidgets('a full building opens the picker and says the building is full',
        (tester) async {
      await _openAssignBed(tester, beds: const []);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.byType(FreeBedPicker), findsOneWidget);
      expect(find.text('Every bed is taken'), findsOneWidget);
    });

    testWidgets('a failed read names the cause inside the sheet', (tester) async {
      await _openAssignBed(tester, failWith: const _Unreachable());
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.byType(FreeBedPicker), findsOneWidget);
      expect(_someFailureSentence, findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // The other half of assign_bed_sheet.dart. studentsAwaitingBedProvider is the ONE-await
  // shape, so it never hung — but the read had no try/catch either, so a failed read was the
  // same silence to the warden. Same rule, same fix.
  group('place a resident who has no bed', () {
    testWidgets('a tap produces the picker', (tester) async {
      await _openPlaceResident(tester);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Who needs a bed?'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsOneWidget);
    });

    testWidgets('a failed read names the cause instead of doing nothing', (tester) async {
      await _openPlaceResident(tester, failWith: const _Unreachable());
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Who needs a bed?'), findsOneWidget);
      expect(_someFailureSentence, findsOneWidget);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HARNESS
// ─────────────────────────────────────────────────────────────────────────────

/// The read failed. What matters to this file is not WHICH failure it was — [AppFailure] owns
/// that sentence and repository_states_test.dart owns the mapping — but that SOME sentence
/// reaches the screen instead of nothing at all.
class _Unreachable implements Exception {
  const _Unreachable();
  @override
  String toString() => 'ClientException: Failed host lookup';
}

/// The one thing every failure has in common on screen: [FailureState] draws
/// `AppFailure.message` as the title of a [StateCard], and the message is never empty.
///
/// A SENTENCE, specifically — it must end in a full stop, which every `AppFailure.message`
/// does. That is what separates the message from the other two strings [FailureState] puts on
/// screen: the badge ('OFFLINE', upper-cased by StateBadge) and the retry button ('Try again').
/// Matching any longish Text would accept the button label as if it were an explanation.
final Finder _someFailureSentence = find.descendant(
  of: find.byType(FailureState),
  matching: find.byWidgetPredicate((w) {
    final text = w is Text ? (w.data ?? '').trim() : '';
    return text.length > 8 && text.endsWith('.');
  }),
);

/// The fakes are ASYNCHRONOUS on purpose: a synchronous override closes the await gap that is
/// the entire subject of this file.
const _lag = Duration(milliseconds: 30);

/// The tap, and just enough of the route transition to have something to look at — but well
/// inside [_lag], so the data cannot have arrived. What the warden sees in the first moment.
Future<void> _oneFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 8));
}

/// `Override` is not exported from riverpod's public barrel, so the list is built where it is
/// used rather than returned from a helper that would have to name the type.
Future<void> _host(
  WidgetTester tester, {
  required WidgetBuilder body,
  List<Bed>? beds,
  List<Student>? waiting,
  Object? failWith,
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      freeBedsProvider.overrideWith((ref, hostelId) async {
        await Future<void>.delayed(_lag);
        if (failWith != null) throw failWith;
        return beds ?? _beds();
      }),
      roomOccupancyProvider.overrideWith((ref, hostelId) async {
        await Future<void>.delayed(_lag);
        return _rooms();
      }),
      studentsAwaitingBedProvider.overrideWith((ref, hostelId) async {
        await Future<void>.delayed(_lag);
        if (failWith != null) throw failWith;
        return waiting ?? [_student()];
      }),
    ],
    // Riverpod retries a failed provider on a timer of its own. That is right in the app and
    // only noise here: it would leave a pending Timer at the end of a failure test and says
    // nothing about whether the sheet opened. THE FAILURE ITSELF IS NOT SOFTENED — the read
    // still throws, and the assertions still demand the sentence on screen.
    retry: (_, _) => null,
    child: MaterialApp(home: Scaffold(body: Builder(builder: body))),
  ));
}

Future<void> _openRegisterSheet(
  WidgetTester tester, {
  List<Bed>? beds,
  Object? failWith,
}) async {
  await _host(
    tester,
    beds: beds,
    failWith: failWith,
    body: (context) => Center(
      child: ElevatedButton(
        onPressed: () => showRegisterStudentSheet(context, hostelId: _hostelId),
        child: const Text('open'),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _openAssignBed(
  WidgetTester tester, {
  List<Bed>? beds,
  Object? failWith,
}) async {
  await _host(
    tester,
    beds: beds,
    failWith: failWith,
    body: (context) => Center(
      child: Consumer(
        builder: (context, ref, _) => ElevatedButton(
          onPressed: () => showAssignBedSheet(context, ref, student: _student()),
          child: const Text('go'),
        ),
      ),
    ),
  );
}

Future<void> _openPlaceResident(WidgetTester tester, {Object? failWith}) async {
  await _host(
    tester,
    failWith: failWith,
    body: (context) => Center(
      child: Consumer(
        builder: (context, ref, _) => ElevatedButton(
          onPressed: () => showPlaceResidentSheet(context, ref, hostelId: _hostelId),
          child: const Text('go'),
        ),
      ),
    ),
  );
}

List<Bed> _beds() => [
      Bed(
        id: '7c9e6679-7425-40de-944b-e07fc1f90ae7',
        hostelId: _hostelId,
        roomId: 'r1',
        bedNumber: 2,
        status: BedStatus.free,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ];

List<RoomOccupancy> _rooms() => const [
      RoomOccupancy(
        roomId: 'r1',
        floorId: 'f1',
        floorNumber: 1,
        roomNumber: '101',
        capacity: 3,
        occupied: 2,
      ),
    ];

Student _student() => Student(
      id: 's1',
      hostelId: _hostelId,
      fullName: 'Aarav Sharma',
      phone: '9876500042',
      dateOfJoining: DateTime(2026, 1, 1),
      monthlyFee: 7500,
      status: StudentStatus.active,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
