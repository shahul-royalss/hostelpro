// ═══════════════════════════════════════════════════════════════════════════════════════════
// ACCOUNT DELETION, FROM INSIDE THE APP
// ═══════════════════════════════════════════════════════════════════════════════════════════
//
// Google Play requires an in-app path to request account deletion wherever accounts are created
// inside the app, and rejects apps that lack one. These are the claims the screen makes:
//
//   1. It will not send until the person has confirmed.
//   2. Sending files a request carrying what they typed, and the hostel they are looking at.
//   3. A request already on file is SHOWN, not offered again — the server de-duplicates for 30
//      days, and a button that looks like it did something new would be a lie.
//   4. A refusal reaches the person in the server's own words.
//   5. Who actions the request is said truthfully per role.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/legal/account_deletion.dart';

class _FakeStore implements AccountDeletionStore {
  _FakeStore({this.pending, this.failWith});

  DateTime? pending;
  final AppFailure? failWith;
  final requests = <({String? reason, String? hostelId})>[];

  @override
  Future<DateTime?> pendingRequest() async => pending;

  @override
  Future<DeletionRequestReceipt> request({String? reason, String? hostelId}) async {
    requests.add((reason: reason, hostelId: hostelId));
    final failure = failWith;
    if (failure != null) throw failure;
    final at = DateTime(2026, 9, 13, 10);
    pending = at;
    return DeletionRequestReceipt(requestedAt: at, alreadyPending: false, notified: 2);
  }
}

NivoraSession _session(UserRole role) => NivoraSession(
      userId: 'u-1',
      role: role,
      fullName: 'Meera Nair',
      status: 'active',
      mustChangePassword: false,
      hostelId: 'h-1',
    );

Future<void> _pump(WidgetTester tester, _FakeStore store, {UserRole role = UserRole.student}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(_session(role)),
        currentHostelIdProvider.overrideWithValue('h-1'),
        accountDeletionStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(theme: NivoraTheme.light(), home: const AccountDeletionScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

final _sendButton = find.byWidgetPredicate((w) => w is FilledButton);

FilledButton _button(WidgetTester tester) => tester.widget<FilledButton>(_sendButton);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('it will not send until the person has confirmed', (tester) async {
    await _pump(tester, _FakeStore());

    expect(find.text('Send deletion request'), findsOneWidget);
    expect(_button(tester).onPressed, isNull);

    await _tapVisible(tester, find.byType(Checkbox));
    expect(_button(tester).onPressed, isNotNull);
  });

  testWidgets('sending files the request with the reason and the hostel, then says when', (tester) async {
    final store = _FakeStore();
    await _pump(tester, store);

    await tester.enterText(find.byType(TextField), '  Moving to another city  ');
    await _tapVisible(tester, find.byType(Checkbox));
    await _tapVisible(tester, _sendButton);

    expect(store.requests, hasLength(1));
    expect(store.requests.single.reason, '  Moving to another city  ');
    expect(store.requests.single.hostelId, 'h-1');
    expect(find.textContaining('Request sent on 13 Sep 2026'), findsOneWidget);
    expect(find.text('Send deletion request'), findsNothing);
  });

  testWidgets('a request already on file is shown, not offered again', (tester) async {
    await _pump(tester, _FakeStore(pending: DateTime(2026, 9, 10, 9)));

    expect(find.textContaining('Request sent on 10 Sep 2026'), findsOneWidget);
    expect(find.text('Send deletion request'), findsNothing);
  });

  testWidgets('a refusal reaches the person in the server\'s own words', (tester) async {
    const refusal = 'You have already sent this request. Your warden and hostel owner can see it.';
    await _pump(tester, _FakeStore(failWith: const InvalidInputFailure(refusal, technical: refusal)));

    await _tapVisible(tester, find.byType(Checkbox));
    await _tapVisible(tester, _sendButton);

    expect(find.text(refusal), findsOneWidget);
    expect(_button(tester).onPressed, isNotNull, reason: 'a refused send must be retryable');
  });

  testWidgets('who actions the request is said truthfully for each role', (tester) async {
    await _pump(tester, _FakeStore(pending: DateTime(2026, 9, 10)), role: UserRole.warden);
    expect(find.textContaining('Your hostel owner has it'), findsOneWidget);

    await _pump(tester, _FakeStore(pending: DateTime(2026, 9, 10)), role: UserRole.owner);
    expect(find.textContaining('The platform administrator has it'), findsOneWidget);

    await _pump(tester, _FakeStore(pending: DateTime(2026, 9, 10)), role: UserRole.student);
    expect(find.textContaining('Your warden and hostel owner have it'), findsOneWidget);
  });

  test('the date is written the way a person reads it', () {
    expect(deletionDayLabel(DateTime(2026, 1, 5)), '5 Jan 2026');
    expect(deletionDayLabel(DateTime(2026, 12, 31)), '31 Dec 2026');
  });
}
