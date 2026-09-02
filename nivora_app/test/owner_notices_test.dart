import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/data/repositories/notice_repository.dart';
import 'package:mobile/features/common/staff_notices.dart';
import 'package:mobile/features/owner/notices/compose_notice_sheet.dart';
import 'package:mobile/features/owner/notices/notice_draft.dart';
import 'package:mobile/features/owner/notices/notice_providers.dart';
import 'package:mobile/features/owner/notices/owner_notices_screen.dart';

/// The owner writes a notice; the right people see it.
///
/// WHAT THIS FILE CAN AND CANNOT PROVE. It proves everything this APP decides: that an empty
/// notice never reaches the server, that the audience the owner tapped is the audience that
/// travels, that a posted notice is drawn, and that retracting one calls the retraction and
/// re-reads the list.
///
/// It cannot prove WHO SEES WHAT, and does not pretend to. That is `announcements_select`, and
/// a Dart test asserting a student cannot see a warden notice would only be asserting that the
/// fake handed back what the fake was told to. The real thing was measured against the live
/// database by impersonating each role — owner 4, manager 2, warden 2, resident 2, of four
/// notices posted one per audience — and is recorded in the header of
/// features/common/staff_notices.dart.

const _hostelId = 'c582bbdd-9885-4c44-85cd-c48cf4cedcce';

Notice _notice({
  String id = 'n1',
  String title = 'Water tanker on Sunday',
  String body = 'The tanker arrives at 9am. Please fill your buckets before then.',
  NoticeAudience audience = NoticeAudience.all,
  DateTime? createdAt,
}) {
  final at = createdAt ?? DateTime.now().subtract(const Duration(hours: 2));
  return Notice(
    id: id,
    hostelId: _hostelId,
    authorUserId: 'owner-1',
    title: title,
    body: body,
    audience: audience,
    createdAt: at,
    updatedAt: at,
  );
}

PagedResult<T> _one<T>(List<T> items) =>
    PagedResult<T>(items: items, page: 0, pageSize: 20, hasMore: false);

/// A stand-in for the two writes. Records what it was asked to do and never touches a network.
class _RecordingWrites implements NoticeWrites {
  _RecordingWrites({this.createFailure, this.deleteFailure});

  final Object? createFailure;
  final Object? deleteFailure;

  final List<({String hostelId, String title, String body, NoticeAudience audience})> created =
      [];
  final List<String> deleted = [];

  @override
  Future<Notice> create({
    required String hostelId,
    required String title,
    required String body,
    NoticeAudience audience = NoticeAudience.all,
  }) async {
    if (createFailure != null) throw createFailure!;
    created.add((hostelId: hostelId, title: title, body: body, audience: audience));
    return _notice(title: title, body: body, audience: audience);
  }

  @override
  Future<void> softDelete({required String noticeId}) async {
    if (deleteFailure != null) throw deleteFailure!;
    deleted.add(noticeId);
  }
}

/// The paged notices provider, answering from a list the test controls.
///
/// [pages] is read once per build, so a test can make the SECOND read return something
/// different from the first — which is how "delete hides it" is proved without a database.
class _FakeNotices extends NoticesNotifier {
  _FakeNotices(super.hostelId, this.pages);
  final List<List<Notice>> pages;
  static int builds = 0;

  @override
  Future<PagedResult<Notice>> fetchPage(int page) async {
    final index = builds < pages.length ? builds : pages.length - 1;
    builds++;
    return _one(pages[index]);
  }
}

// `Override` is not exported from the flutter_riverpod public barrel in Riverpod 3, so the
// list is typed as Object and cast at the boundary. Same workaround as the other suites.
/// A phone-shaped surface tall enough for the whole sheet.
///
/// The default test viewport is 800 logical pixels tall. The compose sheet's action row is a
/// PINNED FOOTER outside its SingleChildScrollView, so once the fields carry text the footer
/// sits below the fold and `ensureVisible` cannot move it — it is not in the scrollable. The tap
/// then lands on nothing, flutter_test only WARNS about the miss, and the assertion fails later
/// as an empty writes list. A 360x1200 surface is an ordinary phone and fits the sheet.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Tap something that may be below the fold.
///
/// The compose sheet is taller than the 800px test viewport, so `tester.tap` on "Post notice"
/// landed outside the hit-test area: flutter_test only WARNS about that ("To make this warning
/// fatal, set hitTestWarningShouldBeFatal"), the press never happens, and the assertion then
/// fails somewhere else entirely — as an empty writes list or a missing error message. Scroll
/// it into view first so a tap means a tap.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  // ADVANCE time rather than wait for stillness. A retract puts the list into its loading
  // state, and the shimmer placeholder animates on a shared Ticker for as long as it is
  // painted — so pumpAndSettle never reaches quiescence and times out after ten seconds.
  // Two pumps past the longest transition in the app is enough to see the result.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _wrap(Widget child, {required List<Object> overrides}) => ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(theme: NivoraTheme.dark(), home: child),
    );

void main() {
  setUp(() => _FakeNotices.builds = 0);

  // ───────────────────────────────────────────────────────────────────────────
  group('an empty notice is not a notice', () {
    test('a blank title is refused', () {
      final errors = validateNoticeDraft(
        const NoticeDraft(title: '', body: 'Something real'),
      );
      expect(errors['title'], isNotNull);
      expect(errors['body'], isNull);
    });

    test('a blank body is refused', () {
      final errors = validateNoticeDraft(
        const NoticeDraft(title: 'Something real', body: ''),
      );
      expect(errors['body'], isNotNull);
      expect(errors['title'], isNull);
    });

    // THE CASE POSTGRES CANNOT CATCH. `announcements.title` is `not null` but has no
    // `length(btrim(title)) > 0` check, so a title of three spaces would be stored happily and
    // every phone in the hostel would buzz for a blank line.
    test('whitespace is not content — the database would have accepted this one', () {
      final errors = validateNoticeDraft(
        const NoticeDraft(title: '   ', body: '\n  \t '),
      );
      expect(errors['title'], isNotNull);
      expect(errors['body'], isNotNull);
    });

    test('the length ceilings match the announcements_text_len constraint', () {
      expect(noticeTitleMaxLength, 200);
      expect(noticeBodyMaxLength, 4000);

      final errors = validateNoticeDraft(NoticeDraft(
        title: 'x' * (noticeTitleMaxLength + 1),
        body: 'y' * (noticeBodyMaxLength + 1),
      ));
      expect(errors['title'], isNotNull);
      expect(errors['body'], isNotNull);
    });

    // Validating the UNTRIMMED string would refuse a title that would in fact have stored
    // fine, because what gets sent is the trimmed value.
    test('a full-length title with trailing space is accepted, because trimmed is what is sent',
        () {
      final draft = NoticeDraft(title: '${'x' * noticeTitleMaxLength}   ', body: 'Fine.');
      expect(validateNoticeDraft(draft), isEmpty);
      expect(draft.trimmedTitle.length, noticeTitleMaxLength);
    });

    test('a real notice passes', () {
      expect(
        validateNoticeDraft(
          const NoticeDraft(title: 'Water tanker', body: 'Arrives 9am Sunday.'),
        ),
        isEmpty,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('compose', () {
    Future<_RecordingWrites> openSheet(WidgetTester tester,
        {_RecordingWrites? writes}) async {
      final w = writes ?? _RecordingWrites();
      _useTallSurface(tester);
      await tester.pumpWidget(_wrap(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showComposeNoticeSheet(context, hostelId: _hostelId),
              child: const Text('open'),
            ),
          ),
        ),
        overrides: [
          noticeWritesProvider.overrideWithValue(w),
          noticesProvider.overrideWith2((_) => _FakeNotices(_hostelId, const [[]])),
        ],
      ));
      await _tapVisible(tester, find.text('open'));
      return w;
    }

    testWidgets('nothing is sent when both fields are empty, and the sheet says why',
        (tester) async {
      final writes = await openSheet(tester);

      await _tapVisible(tester, find.text('Post notice'));

      expect(writes.created, isEmpty, reason: 'an empty notice must not reach the server');
      expect(find.text('Give the notice a title.'), findsOneWidget);
      expect(find.text('Write what the notice says.'), findsOneWidget);
    });

    testWidgets('a filled notice reaches the repository as typed, trimmed', (tester) async {
      final writes = await openSheet(tester);

      await tester.enterText(find.byType(TextField).first, '  Water tanker on Sunday  ');
      await tester.enterText(find.byType(TextField).last, '  Arrives at 9am.  ');
      await _tapVisible(tester, find.text('Post notice'));

      expect(writes.created, hasLength(1));
      expect(writes.created.single.title, 'Water tanker on Sunday');
      expect(writes.created.single.body, 'Arrives at 9am.');
      expect(writes.created.single.hostelId, _hostelId);
    });

    // ── AUDIENCE TARGETING ───────────────────────────────────────────────────
    testWidgets('the default audience is everyone', (tester) async {
      final writes = await openSheet(tester);

      await tester.enterText(find.byType(TextField).first, 'Title');
      await tester.enterText(find.byType(TextField).last, 'Body');
      await _tapVisible(tester, find.text('Post notice'));

      expect(writes.created.single.audience, NoticeAudience.all);
    });

    testWidgets('the audience the owner tapped is the audience that travels', (tester) async {
      for (final (label, expected) in <(String, NoticeAudience)>[
        ('Students', NoticeAudience.students),
        ('Wardens', NoticeAudience.warden),
        ('Managers', NoticeAudience.manager),
      ]) {
        final writes = await openSheet(tester);

        await tester.enterText(find.byType(TextField).first, 'Title');
        await tester.enterText(find.byType(TextField).last, 'Body');
        await _tapVisible(tester, find.text(label));
        await _tapVisible(tester, find.text('Post notice'));

        expect(writes.created.single.audience, expected,
            reason: 'tapping "$label" must send ${expected.wire}');
      }
    });

    testWidgets('all four audiences the enum declares are offered', (tester) async {
      await openSheet(tester);
      // Targeting a single role is already possible in the schema; offering only "everyone"
      // would hide a control the database has always had.
      expect(noticeAudienceChoices.toSet(), NoticeAudience.values.toSet());
      for (final audience in NoticeAudience.values) {
        expect(find.text(audience.label), findsOneWidget);
      }
    });

    testWidgets('a refused post is named, and nothing is claimed to have been sent',
        (tester) async {
      final writes = _RecordingWrites(
        createFailure: const ReadOnlyFailure('This hostel is read-only.'),
      );
      await openSheet(tester, writes: writes);

      await tester.enterText(find.byType(TextField).first, 'Title');
      await tester.enterText(find.byType(TextField).last, 'Body');
      await _tapVisible(tester, find.text('Post notice'));

      expect(writes.created, isEmpty);
      // The sheet stays open, carrying the failure, rather than closing on a write that
      // did not happen.
      expect(find.text('Post notice'), findsOneWidget);
      // ErrorNote renders errorGuidance(), not the raw failure message: a ReadOnlyFailure
      // becomes 'Subscription lapsed' / 'Reading still works; recording does not.' That is
      // the sentence the owner actually reads, so it is the one worth asserting.
      expect(find.textContaining('Subscription lapsed'), findsWidgets);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the owner list', () {
    Future<_RecordingWrites> pumpScreen(
      WidgetTester tester, {
      required List<List<Notice>> pages,
      _RecordingWrites? writes,
    }) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final w = writes ?? _RecordingWrites();
      _useTallSurface(tester);
      await tester.pumpWidget(_wrap(
        const OwnerNoticesScreen(hostelId: _hostelId),
        overrides: [
          noticeWritesProvider.overrideWithValue(w),
          hostelProvider.overrideWith((ref, id) async => null),
          noticesProvider.overrideWith2((_) => _FakeNotices(_hostelId, pages)),
        ],
      ));
      await tester.pumpAndSettle();
      return w;
    }

    testWidgets('posted notices are rendered, newest first as the server ordered them',
        (tester) async {
      await pumpScreen(tester, pages: [
        [
          _notice(id: 'n1', title: 'Water tanker on Sunday'),
          _notice(id: 'n2', title: 'Rent due on the 5th', audience: NoticeAudience.students),
        ],
      ]);

      expect(find.text('Water tanker on Sunday'), findsOneWidget);
      expect(find.text('Rent due on the 5th'), findsOneWidget);
    });

    testWidgets('the audience is named on every row, not only on the residents one',
        (tester) async {
      await pumpScreen(tester, pages: [
        [
          _notice(id: 'n1', title: 'To all'),
          _notice(id: 'n2', title: 'To residents', audience: NoticeAudience.students),
          _notice(id: 'n3', title: 'To the warden', audience: NoticeAudience.warden),
        ],
      ]);

      expect(find.text('Everyone'), findsOneWidget);
      expect(find.text('Residents only'), findsOneWidget);
      expect(find.text('Warden only'), findsOneWidget);
    });

    testWidgets('an empty noticeboard says so, and is not a failure', (tester) async {
      await pumpScreen(tester, pages: [const []]);

      expect(find.text('No notices yet'), findsOneWidget);
      // Four distinct states: empty must not borrow the error card's retry.
      expect(find.text('Retry'), findsNothing);
    });

    // ── DELETE ───────────────────────────────────────────────────────────────
    testWidgets('taking a notice down asks first, and a refusal cancels it', (tester) async {
      final writes = await pumpScreen(tester, pages: [
        [_notice(id: 'n1', title: 'Water tanker on Sunday')],
      ]);

      await tester.tap(find.byTooltip('Take this notice down'));
      await tester.pumpAndSettle();
      expect(find.text('Take this notice down?'), findsOneWidget);

      await _tapVisible(tester, find.text('Keep it'));

      expect(writes.deleted, isEmpty, reason: 'declining the dialog must not retract anything');
      expect(find.text('Water tanker on Sunday'), findsOneWidget);
    });

    testWidgets('the confirm dialog does not claim the notification can be recalled',
        (tester) async {
      await pumpScreen(tester, pages: [
        [_notice(id: 'n1')],
      ]);

      await tester.tap(find.byTooltip('Take this notice down'));
      await tester.pumpAndSettle();

      // The fan-out is on INSERT and those rows are not deleted with the notice. An owner who
      // believes retracting un-rings the bell will retract instead of posting a correction.
      expect(find.textContaining('does not recall it'), findsOneWidget);
    });

    testWidgets('confirming retracts that notice, and the list no longer shows it',
        (tester) async {
      final writes = await pumpScreen(tester, pages: [
        // First read: two notices. Second read, after the retraction invalidates the
        // provider: the one that is left — which is what the server would now return, since
        // announcements_select excludes soft-deleted rows for everybody, owner included.
        [
          _notice(id: 'n1', title: 'Water tanker on Sunday'),
          _notice(id: 'n2', title: 'Rent due on the 5th'),
        ],
        [_notice(id: 'n2', title: 'Rent due on the 5th')],
      ]);

      expect(find.text('Water tanker on Sunday'), findsOneWidget);

      await tester.tap(find.byTooltip('Take this notice down').first);
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Take it down'));

      expect(writes.deleted, ['n1'], reason: 'the retraction must name the notice tapped');
      expect(find.text('Water tanker on Sunday'), findsNothing);
      expect(find.text('Rent due on the 5th'), findsOneWidget);
    });

    testWidgets('a refused retraction is named on the row and the notice stays', (tester) async {
      final writes = _RecordingWrites(
        deleteFailure: const AccessDeniedFailure('You do not have access to that.'),
      );
      await pumpScreen(
        tester,
        pages: [
          [_notice(id: 'n1', title: 'Water tanker on Sunday')],
        ],
        writes: writes,
      );

      await tester.tap(find.byTooltip('Take this notice down'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Take it down'));

      // A handler that can return with nothing visible is a bug: the row must say what
      // happened, and the notice must still be there.
      expect(find.text('Water tanker on Sunday'), findsOneWidget);
      // Same reason as the compose refusal above: an AccessDeniedFailure surfaces through
      // errorGuidance as 'Not your PG', not as its raw message.
      expect(find.textContaining('Not your PG'), findsWidgets);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('staff read the same rows', () {
    Future<void> pumpStaffList(
      WidgetTester tester, {
      required List<Notice> notices,
      required UserRole viewer,
    }) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        Scaffold(
          body: StaffNoticeList(
            hostelId: _hostelId,
            page: _one(notices),
            viewerRole: viewer,
          ),
        ),
        overrides: [
          noticesProvider.overrideWith2((_) => _FakeNotices(_hostelId, [notices])),
        ],
      ));
      await tester.pumpAndSettle();
    }

    // The gap this closes: before, an owner notice addressed to `all` reached the resident's
    // Notices tab and nowhere else. The warden and the manager were sent a notifications row
    // pointing at a screen that did not exist.
    testWidgets('a warden sees an owner notice addressed to everyone', (tester) async {
      await pumpStaffList(
        tester,
        viewer: UserRole.warden,
        notices: [_notice(title: 'Water tanker on Sunday')],
      );
      expect(find.text('Water tanker on Sunday'), findsOneWidget);
    });

    testWidgets('a notice addressed to this role alone is marked, an "all" one is not',
        (tester) async {
      await pumpStaffList(
        tester,
        viewer: UserRole.warden,
        notices: [
          _notice(id: 'n1', title: 'To everyone'),
          _notice(id: 'n2', title: 'To the warden', audience: NoticeAudience.warden),
        ],
      );

      // Exactly one "For you": the warden-only row. A warden who cannot tell the two apart
      // re-announces something the whole hostel already has.
      expect(find.text('For you'), findsOneWidget);
      expect(find.text('To everyone'), findsOneWidget);
      expect(find.text('To the warden'), findsOneWidget);
    });

    testWidgets('a manager notice is not marked "for you" in front of a warden',
        (tester) async {
      await pumpStaffList(
        tester,
        viewer: UserRole.warden,
        // Not a visibility claim — announcements_select would never have sent this row to a
        // warden. It pins that the CHIP is keyed to the reader rather than to the row.
        notices: [_notice(audience: NoticeAudience.manager)],
      );
      expect(find.text('For you'), findsNothing);
    });

    testWidgets('an empty staff noticeboard says so without inventing a failure',
        (tester) async {
      await pumpStaffList(tester, viewer: UserRole.manager, notices: const []);
      expect(find.textContaining('No notices yet'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the posted-at label', () {
    test('does not read into the future when the device clock is behind', () {
      final now = DateTime.utc(2026, 9, 2, 12);
      expect(noticePostedLabel(now.add(const Duration(minutes: 3)), now: now), 'just now');
    });

    test('counts up in the unit that is still exact', () {
      final now = DateTime.utc(2026, 9, 2, 12);
      expect(noticePostedLabel(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
      expect(noticePostedLabel(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
      expect(noticePostedLabel(now.subtract(const Duration(days: 2)), now: now), '2d ago');
    });
  });
}
