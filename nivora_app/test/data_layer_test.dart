// Unit tests for the parts of lib/data that have no network in them.
//
// These cover the failures that are invisible until a user finds them: an enum parsed by index
// instead of by value, a `numeric` that arrives as an int, a column name that is quietly
// absent, and an error message that says "something went wrong" when Postgres said exactly what
// was wrong. Every one of those compiles cleanly.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/repositories/repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('enums are parsed by value, not by index', () {
    test('each wire string maps to its own case', () {
      expect(BedStatus.tryParse('occupied'), BedStatus.occupied);
      expect(StudentStatus.tryParse('on_leave'), StudentStatus.onLeave);
      expect(FeeStatus.tryParse('partial'), FeeStatus.partial);
      expect(PaymentMode.tryParse('upi'), PaymentMode.upi);
      expect(ComplaintStatus.tryParse('in_progress'), ComplaintStatus.inProgress);
      expect(TaskStatus.tryParse('done'), TaskStatus.done);
      expect(NoticeAudience.tryParse('students'), NoticeAudience.students);
      expect(SubscriptionState.tryParse('expiring'), SubscriptionState.expiring);
    });

    test('the Dart name is never what goes on the wire', () {
      // If anyone ever "simplifies" this to .name, on_leave and in_progress break silently.
      expect(StudentStatus.onLeave.wire, 'on_leave');
      expect(ComplaintStatus.inProgress.wire, 'in_progress');
      expect(TaskStatus.inProgress.wire, 'in_progress');
    });

    test('an unknown value is null, not a neighbouring case', () {
      expect(BedStatus.tryParse('reserved'), isNull);
      expect(FeeStatus.tryParse(null), isNull);
      expect(StudentStatus.tryParse('Vacated'), isNull, reason: 'match is exact, not fuzzy');
    });

    test('a required column with an unknown value throws rather than guessing', () {
      expect(
        () => wireOrThrow(BedStatus.values, 'reserved', 'beds', 'status'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('row shape', () {
    Map<String, dynamic> bed({Object? status = 'free'}) => {
          'id': 'b1',
          'hostel_id': 'h1',
          'room_id': 'r1',
          'bed_number': 1,
          'status': status,
          'student_id': null,
          'created_at': '2026-08-24T10:00:00+00:00',
          'updated_at': '2026-08-24T10:00:00+00:00',
        };

    test('a missing column names itself instead of turning into null', () {
      final row = bed()..remove('bed_number');
      expect(
        () => Bed.fromJson(row),
        throwsA(isA<RowShapeError>()
            .having((e) => e.toString(), 'message', contains('beds.bed_number'))),
      );
    });

    test('null in a NOT NULL column is a shape error, not a silent default', () {
      expect(() => Bed.fromJson(bed(status: null)), throwsA(isA<RowShapeError>()));
    });

    test('numeric arrives as int for round amounts and still parses as double', () {
      // This is the real PostgREST behaviour: 7000.00 comes back as 7000, and `as double`
      // would throw on every hostel whose rent happens to be a round number.
      final student = Student.fromJson({
        'id': 's1',
        'hostel_id': 'h1',
        'user_id': null,
        'full_name': 'Aarav Sharma',
        'phone': '9000000001',
        'email': null,
        'photo_url': null,
        'guardian_name': null,
        'guardian_phone': null,
        'permanent_address': null,
        'id_proof_type': null,
        'id_proof_url': null,
        'date_of_joining': '2026-03-07',
        'room_id': null,
        'bed_id': null,
        'monthly_fee': 7000, // int, not double
        'status': 'active',
        'vacated_at': null,
        'created_at': '2026-03-07T00:00:00+00:00',
        'updated_at': '2026-03-07T00:00:00+00:00',
        'deleted_at': null,
      });
      expect(student.monthlyFee, 7000.0);
      expect(student.monthlyFee, isA<double>());
    });

    test('a date column becomes local midnight, not a UTC instant', () {
      final student = Student.fromJson({
        'id': 's1',
        'hostel_id': 'h1',
        'full_name': 'A',
        'phone': '9',
        'date_of_joining': '2026-03-07',
        'monthly_fee': 0,
        'status': 'active',
        'created_at': '2026-03-07T00:00:00+00:00',
        'updated_at': '2026-03-07T00:00:00+00:00',
      });
      // Parsed as UTC it would render as the 6th for anyone west of Greenwich and stay the 7th
      // in IST purely by luck; as local midnight the calendar day is always the one Postgres
      // stored.
      expect(student.dateOfJoining.year, 2026);
      expect(student.dateOfJoining.month, 3);
      expect(student.dateOfJoining.day, 7);
      expect(student.dateOfJoining.isUtc, isFalse);
    });
  });

  group('wire formatting', () {
    test('dates are zero-padded and carry no time', () {
      expect(toDateWire(DateTime(2026, 1, 5)), '2026-01-05');
      expect(toDateWire(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
    });

    test('period months match the fee_payments check constraint', () {
      expect(toPeriodMonth(DateTime(2026, 8, 24)), '2026-08');
      expect(toPeriodMonth(DateTime(2026, 11, 1)), '2026-11');
      expect(RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(toPeriodMonth(DateTime(2026, 9, 9))),
          isTrue);
    });
  });

  group('pagination', () {
    test('the extra row is what proves there is a next page, and is not shown', () {
      final page = PagedResult.fromOverfetch(List.generate(21, (i) => i), page: 0, pageSize: 20);
      expect(page.items.length, 20);
      expect(page.items.last, 19, reason: 'the 21st row is the probe, not content');
      expect(page.hasMore, isTrue);
      expect(page.nextPage, 1);
    });

    test('a short page is the end of the list', () {
      final page = PagedResult.fromOverfetch(List.generate(7, (i) => i), page: 0, pageSize: 20);
      expect(page.items.length, 7);
      expect(page.hasMore, isFalse);
      expect(page.nextPage, isNull);
    });

    test('an exactly-full page with nothing after it does not offer a next page', () {
      final page = PagedResult.fromOverfetch(List.generate(20, (i) => i), page: 0, pageSize: 20);
      expect(page.hasMore, isFalse);
    });

    test('appending keeps the earlier rows and takes the newer cursor', () {
      final first = PagedResult.fromOverfetch([1, 2, 3], page: 0, pageSize: 2);
      final second = PagedResult.fromOverfetch([3, 4], page: 1, pageSize: 2);
      final joined = first.followedBy(second);
      expect(joined.items, [1, 2, 3, 4]);
      expect(joined.page, 1);
      expect(joined.hasMore, isFalse);
    });
  });

  group('failures say which of the four things happened', () {
    AppFailure map(String? code, String message) =>
        AppFailure.from(PostgrestException(message: message, code: code));

    test('42501 is "you do not have access", never a crash', () {
      final f = map('42501', 'new row violates row-level security policy for table "expenses"');
      expect(f, isA<AccessDeniedFailure>());
      expect(f.message, 'You do not have access to that.');
      expect(f.isRetryable, isFalse);
    });

    test('42501 raised by the read-only gate is a different conversation', () {
      final f = map('42501', 'Subscription expired — hostel is read-only.');
      expect(f, isA<ReadOnlyFailure>());
      expect(f.message, contains('renewed'));
    });

    test('a P0001 message from the database reaches the user unchanged', () {
      // These are written for the person at the desk; rewriting them loses the specifics.
      final f = map('P0001', 'That student has been checked out — no further payments can be recorded.');
      expect(f, isA<InvalidInputFailure>());
      expect(f.message, startsWith('That student has been checked out'));
    });

    test('a unique violation names the rule that was broken', () {
      expect(
        map('23505', 'duplicate key value violates unique constraint "students_one_active_per_bed"').message,
        contains('bed is already taken'),
      );
      expect(
        map('23505', 'duplicate key value violates unique constraint "students_phone_active_key"').message,
        contains('phone number is already registered'),
      );
    });

    test('a missing row, an expired session and a 5xx are each their own type', () {
      expect(map('PGRST116', 'no rows'), isA<NotFoundFailure>());
      expect(map('PGRST301', 'JWT expired'), isA<SignedOutFailure>());
      expect(map('503', 'upstream'), isA<ServerFailure>());
      expect(map('503', 'upstream').isRetryable, isTrue);
    });

    test('no signal is offline, and offline is retryable', () {
      expect(AppFailure.from(TimeoutException('slow')), isA<OfflineFailure>());
      expect(
        AppFailure.from(Exception('SocketException: Failed host lookup: supabase.co')),
        isA<OfflineFailure>(),
      );
      expect(AppFailure.from(Exception('SocketException')).isRetryable, isTrue);
    });

    test('an unrecognised error degrades to a generic message but keeps the detail', () {
      final f = AppFailure.from(FormatException('unexpected token'));
      expect(f, isA<UnexpectedFailure>());
      expect(f.message, 'Something did not work. Please try again.');
      expect(f.technical, contains('unexpected token'));
    });

    test('classifying a failure twice does not re-wrap it', () {
      const original = OfflineFailure('no signal');
      expect(identical(AppFailure.from(original), original), isTrue);
    });
  });

  group('search text cannot break the PostgREST or() grammar', () {
    test('commas, dots and parens are neutralised', () {
      // "Sharma, R." would otherwise be parsed as two conditions and 400 the request.
      expect(sanitizeSearch('Sharma, R.'), 'Sharma R');
      expect(sanitizeSearch('a(b)c'), 'a b c');
      expect(sanitizeSearch('  spaced   out  '), 'spaced out');
    });

    test('wildcards a user typed are not treated as wildcards', () {
      expect(sanitizeSearch('%'), '');
      expect(sanitizeSearch('a*b'), 'a b');
    });
  });

  group('derived values', () {
    test('a balance is never negative, because an overpayment is not a debt', () {
      final over = FeeLedgerRow(
        studentId: 's',
        fullName: 'A',
        phone: '9',
        monthlyFee: 7000,
        amountDue: 7000,
        amountPaid: 8000,
        status: FeeStatus.paid,
      );
      expect(over.balance, 0);
    });

    test('occupancy is null rather than zero when there are no beds at all', () {
      const stats = HostelStats(
        totalBeds: 0,
        occupiedBeds: 0,
        activeStudents: 0,
        openComplaints: 0,
        feesCollected: 0,
        feesPending: 0,
        studentsPaid: 0,
        studentsUnpaid: 0,
        pendingLeaves: 0,
        visitorsToday: 0,
        pendingTasks: 0,
        revenueToday: 0,
        expensesToday: 0,
        revenueMonth: 0,
        expensesMonth: 0,
        subscriptionState: SubscriptionState.active,
      );
      // "No beds configured" and "nobody has moved in" must not draw the same 0% bar.
      expect(stats.occupancyRate, isNull);
    });
  });
}
