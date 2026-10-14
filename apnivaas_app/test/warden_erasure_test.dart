// CHECKING SOMEBODY OUT NOW SCHEDULES A DELETION, AND THIS FILE HOLDS THE SENTENCES DOWN.
//
// The owner asked for two things that meet on this one screen: "student data deletion request
// has to sent while he is leaving hostel and that student data will be deleted after 1 month",
// and "the fee history of student never has to be deleted". A warden standing at the desk is
// the person who has to tell a departing resident which of their things the hostel keeps — so
// what the check-out sheet SAYS is not decoration, it is the notice.
//
// ═══ WHY THE COPY IS UNDER TEST AND NOT JUST THE BEHAVIOUR ═══
// This sheet used to end with "The record and its history stay — this is not a deletion."
// That sentence was true when it was written and became false the moment the erasure shipped.
// Nothing would have caught it: the button still worked, the RPC still returned, every widget
// test still passed, and the only symptom would have been a resident told the wrong thing and
// finding out a month later. A promise a product makes on screen is behaviour.
//
// The four states are here for the ordinary reason — a screen that cannot tell "still loading"
// from "nothing scheduled" will eventually offer to cancel a deletion that is not there, or
// stay silent about one that is.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/features/warden/actions/assign_bed_sheet.dart';
import 'package:mobile/features/warden/data/warden_models.dart';
import 'package:mobile/features/warden/widgets/warden_ui.dart';

const _hostelId = 'h1';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('the check-out sheet is the notice', () {
    testWidgets('it names the deletion, not just the check-out', (tester) async {
      await _openCheckOut(tester);

      expect(find.textContaining('scheduled for deletion'), findsOneWidget);
      expect(find.textContaining('one month from today'), findsOneWidget);
    });

    testWidgets('it names WHAT is deleted, in the words a resident would use', (tester) async {
      await _openCheckOut(tester);

      final body = _bodyText(tester);
      for (final field in ['phone', 'guardian', 'address', 'ID proof', 'photo']) {
        expect(body, contains(field),
            reason: '"$field" is a thing the resident handed over and can ask about');
      }
    });

    testWidgets('it promises the rent ledger survives — the owner\'s own requirement',
        (tester) async {
      await _openCheckOut(tester);
      expect(find.textContaining('rent ledger is kept permanently'), findsOneWidget);
    });

    testWidgets('it says the deletion can be stopped', (tester) async {
      await _openCheckOut(tester);
      expect(find.textContaining('cancel that any time'), findsOneWidget);
    });

    // The regression this file exists for. If the erasure is ever reverted, this fails and
    // whoever reverts it has to decide what the sheet should say instead.
    testWidgets('it no longer claims the record is not deleted', (tester) async {
      await _openCheckOut(tester);

      final body = _bodyText(tester);
      expect(body, isNot(contains('this is not a deletion')));
      expect(body, isNot(contains('The record and its history stay')));
    });

    testWidgets('and it is still refusable — the sheet closes with nothing written',
        (tester) async {
      await _openCheckOut(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('scheduled for deletion'), findsNothing);
      expect(find.text('go'), findsOneWidget, reason: 'back where they started');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // WHAT A CHECKED-OUT RESIDENT'S SHEET SHOWS. Loading is not "nothing scheduled", and
  // "nothing scheduled" is not "already deleted". Four states, four different things on screen.
  group('the four states of a pending deletion stay four states', () {
    testWidgets('LOADING says nothing about the schedule', (tester) async {
      await _openBlock(tester, schedule: _pending(days: 12), lag: _lag);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 8));

      expect(find.byType(SkeletonBlock), findsOneWidget);
      // None of the other three states may be on screen while the answer is unknown.
      expect(find.text('Deletion scheduled'), findsNothing);
      expect(find.textContaining('No deletion is scheduled'), findsNothing);
      expect(find.text('Details deleted'), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('PENDING names the stored date and offers the way out', (tester) async {
      await _openBlock(tester, schedule: _pending(days: 12));

      expect(find.text('Deletion scheduled'), findsOneWidget);
      expect(find.textContaining('in 12 days'), findsOneWidget);
      expect(find.textContaining('rent ledger is kept'), findsOneWidget);
      expect(find.text('Cancel the deletion'), findsOneWidget);
      expect(find.text('Schedule deletion'), findsNothing);
    });

    testWidgets('a deadline already passed is said so, not rounded up to a day that is left',
        (tester) async {
      await _openBlock(tester, schedule: _pending(days: -2));

      expect(find.textContaining('due since'), findsOneWidget);
      expect(find.textContaining('next nightly sweep'), findsOneWidget);
      // Still cancellable: the job has not run, so the record is still there to save.
      expect(find.text('Cancel the deletion'), findsOneWidget);
    });

    testWidgets('NOTHING SCHEDULED says so plainly and offers to schedule one', (tester) async {
      await _openBlock(tester, schedule: _none());

      expect(find.textContaining('No deletion is scheduled'), findsOneWidget);
      expect(find.text('Schedule deletion'), findsOneWidget);
      expect(find.text('Cancel the deletion'), findsNothing);
    });

    testWidgets('a row this caller cannot read is not reported as "nothing scheduled" data',
        (tester) async {
      // erasure() returns null for a row RLS hid. The screen may offer to schedule one — that
      // is a request, and the server will refuse it if the caller has no business making it —
      // but it must never claim a fact about a row it could not see.
      await _openBlock(tester, schedule: null);

      expect(find.text('Deletion scheduled'), findsNothing);
      expect(find.text('Details deleted'), findsNothing);
    });

    testWidgets('ERASED is a tombstone, with no control to cancel what already happened',
        (tester) async {
      await _openBlock(tester, schedule: _erased());

      expect(find.text('Details deleted'), findsOneWidget);
      expect(find.textContaining('all that remains'), findsOneWidget);
      expect(find.text('Cancel the deletion'), findsNothing);
      expect(find.text('Schedule deletion'), findsNothing);
    });

    testWidgets('FAILED shows the failure and a retry, not an invented schedule',
        (tester) async {
      await _openBlock(tester, failWith: const _Unreachable());

      expect(find.byType(FailureState), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Deletion scheduled'), findsNothing);
      expect(find.textContaining('No deletion is scheduled'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('cancelling is offered as protection, not as another destructive act', () {
    testWidgets('the confirm sheet says what is kept and what re-starts the clock',
        (tester) async {
      await _openBlock(tester, schedule: _pending(days: 12));

      await tester.tap(find.text('Cancel the deletion'));
      await tester.pumpAndSettle();

      expect(find.textContaining('their record stays'), findsOneWidget);
      expect(find.text('Keep the record'), findsOneWidget);
      // The thing a warden would otherwise learn the hard way.
      expect(find.textContaining('fresh one-month countdown'), findsOneWidget);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HARNESS
// ─────────────────────────────────────────────────────────────────────────────

class _Unreachable implements Exception {
  const _Unreachable();
  @override
  String toString() => 'ClientException: Failed host lookup';
}

/// Asynchronous on purpose, so LOADING is a state that actually exists to look at.
const _lag = Duration(milliseconds: 30);

/// Every `Text` on screen, joined. Used for the assertions about what the sheet does NOT say —
/// a `findsNothing` on one phrasing would pass against a paraphrase of the same wrong claim.
String _bodyText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join('\n');

ErasureSchedule _pending({required int days}) => ErasureSchedule(
      studentId: 's1',
      requestedAt: DateTime.now().subtract(const Duration(days: 3)),
      // +1h so `inDays` truncation lands on the whole number the copy claims, rather than one
      // below it — the same rounding the screen is being tested for.
      dueAt: DateTime.now().add(Duration(days: days, hours: 1)),
    );

ErasureSchedule _none() => const ErasureSchedule(studentId: 's1');

ErasureSchedule _erased() => ErasureSchedule(
      studentId: 's1',
      requestedAt: DateTime(2026, 6, 1),
      dueAt: DateTime(2026, 7, 1),
      erasedAt: DateTime(2026, 7, 2),
    );

/// `Override` is not exported from riverpod's public barrel, so the list is built inline.
Future<void> _pumpHost(
  WidgetTester tester, {
  required WidgetBuilder body,
  ErasureSchedule? schedule,
  Object? failWith,
  Duration lag = Duration.zero,
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      studentErasureProvider.overrideWith((ref, studentId) async {
        if (lag > Duration.zero) await Future<void>.delayed(lag);
        if (failWith != null) throw failWith;
        return schedule;
      }),
    ],
    // Riverpod's own retry timer would outlive the failure test and says nothing about what is
    // on screen. THE FAILURE IS NOT SOFTENED — the read still throws and the sentence is still
    // required below.
    retry: (_, _) => null,
    child: MaterialApp(home: Scaffold(body: Builder(builder: body))),
  ));
  // A lagged read is only observable if this does NOT drain it: settling here would step past
  // the loading frame the LOADING test exists to look at.
  if (lag == Duration.zero) await tester.pumpAndSettle();
}

Future<void> _openCheckOut(WidgetTester tester) async {
  await _pumpHost(
    tester,
    body: (context) => Center(
      child: Consumer(
        builder: (context, ref, _) => ElevatedButton(
          onPressed: () => showCheckOutSheet(context, ref, student: _student()),
          child: const Text('go'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

Future<void> _openBlock(
  WidgetTester tester, {
  ErasureSchedule? schedule,
  Object? failWith,
  Duration lag = Duration.zero,
}) async {
  await _pumpHost(
    tester,
    schedule: schedule,
    failWith: failWith,
    lag: lag,
    body: (context) => SingleChildScrollView(child: ErasureBlock(student: _student())),
  );
}

Student _student() => Student(
      id: 's1',
      hostelId: _hostelId,
      fullName: 'Aarav Sharma',
      phone: '9876500042',
      dateOfJoining: DateTime(2026, 1, 1),
      monthlyFee: 7500,
      status: StudentStatus.vacated,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
