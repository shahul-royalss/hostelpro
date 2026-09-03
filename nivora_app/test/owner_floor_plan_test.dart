// The owner's building-layout editor: floors, rooms per floor, and beds for the rooms
// ow_set_floor_plan is about to create.
//
// WHAT THESE TESTS ARE HERE TO CATCH. Three of the four are about a screen telling the truth
// before a tap rather than after one:
//
//   * a wire key renamed to match the Dart field, which compiles, round-trips, and quietly
//     sends every floor a plan with no bed count in it;
//   * an editor that opens on a default plan instead of on the building, which turns "save" into
//     "delete everything you have and build what I guessed";
//   * a shrink onto a room somebody sleeps in, discovered from a snackbar after the save
//     instead of from the row before it;
//   * a refusal rewritten into a tidy generic sentence, which loses the room number and sends
//     an owner to walk the whole floor.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/data/repositories/room_repository.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/owner/rooms/floor_plan_screen.dart';

const _hostelId = 'h-sunrise';
const _period = '2026-08';

const _session = NivoraSession(
  userId: 'owner-1',
  role: UserRole.owner,
  fullName: 'Ananya Rao',
  status: 'active',
  mustChangePassword: false,
  hostelId: _hostelId,
);

final _sunrise = Hostel(
  id: _hostelId,
  name: 'Sunrise Residency',
  ownerUserId: 'owner-1',
  totalFloors: 2,
  totalRooms: 3,
  bedsPerRoomDefault: 3,
  address: '12 MG Road, Pune',
  status: HostelStatus.active,
  createdAt: DateTime.utc(2026, 3, 1),
  updatedAt: DateTime.utc(2026, 3, 1),
);

/// The building the editor must open on: floor 1 has two rooms of three beds with four of
/// those six taken, floor 2 has one empty double. Both of floor 1's rooms are occupied, which
/// is what makes any shrink of that floor a refusal waiting to happen.
const _rooms = [
  RoomOccupancy(
    roomId: 'r-101',
    floorId: 'f-1',
    floorNumber: 1,
    roomNumber: '101',
    capacity: 3,
    occupied: 3,
  ),
  RoomOccupancy(
    roomId: 'r-102',
    floorId: 'f-1',
    floorNumber: 1,
    roomNumber: '102',
    capacity: 3,
    occupied: 1,
  ),
  RoomOccupancy(
    roomId: 'r-201',
    floorId: 'f-2',
    floorNumber: 2,
    roomNumber: '201',
    capacity: 2,
    occupied: 0,
  ),
];

/// The same building with an empty room at the top of floor 1, so a shrink there is one the
/// server would actually allow — the only way to reach the confirmation.
const _roomsWithASpareRoom = [
  ..._rooms,
  RoomOccupancy(
    roomId: 'r-103',
    floorId: 'f-1',
    floorNumber: 1,
    roomNumber: '103',
    capacity: 3,
    occupied: 0,
  ),
];

FloorPlanResult _result({int added = 0, int removed = 0}) => FloorPlanResult(
      floors: 2,
      roomsAdded: added,
      roomsRemoved: removed,
      roomsTotal: 3 + added - removed,
      bedsTotal: 8,
    );

/// Pushes the editor onto a real route, because it pops itself after a successful save and a
/// screen that is the only route in the tree cannot.
Future<_FakeLayout> _pump(
  WidgetTester tester, {
  List<RoomOccupancy> rooms = _rooms,
  FloorPlanResult? result,
  Object? failure,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final writes = _FakeLayout(result: result ?? _result(added: 1), failure: failure);
  final navigator = GlobalKey<NavigatorState>();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(_session),
        currentHostelIdProvider.overrideWithValue(_hostelId),
        currentPeriodMonthProvider.overrideWithValue(_period),
        myHostelsProvider.overrideWith((ref) => [_sunrise]),
        hostelProvider.overrideWith((ref, id) => _sunrise),
        roomOccupancyProvider.overrideWith((ref, id) => rooms),
        roomLayoutWritesProvider.overrideWithValue(writes),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  navigator.currentState!.push(OwnerFloorPlanScreen.route(_hostelId));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return writes;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

FilledButton _saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save layout').last);

void main() {
  group('the line one floor puts on the wire', () {
    test('the bed count is sent as "beds", which is the key ow_set_floor_plan reads', () {
      // The Dart field is deliberately the longer bedsPerNewRoom, because that is what it
      // means. The WIRE key is p_plan's own word, and renaming it to match the field would not
      // fail to compile and would not fail the round trip either — every floor would simply
      // arrive at the RPC with no bed count on it.
      const entry = FloorPlanEntry(floor: 2, rooms: 6, bedsPerNewRoom: 3);

      expect(entry.toJson(), {'floor': 2, 'rooms': 6, 'beds': 3});
      expect(entry.toJson().containsKey('bedsPerNewRoom'), isFalse);
    });

    test('copyWith cannot renumber a floor, because a plan must stay 1..N with none missing', () {
      const entry = FloorPlanEntry(floor: 3, rooms: 4, bedsPerNewRoom: 2);
      final wider = entry.copyWith(rooms: 5);

      expect(wider.floor, 3, reason: 'a floor moves only by being added or dropped at the end');
      expect(wider.rooms, 5);
      expect(wider.bedsPerNewRoom, 2);
    });
  });

  group('what the server says it did', () {
    test('the summary names the direction, and says so even when nothing moved', () {
      // "Nothing changed." is a real outcome: an owner who re-saves the plan they already saved
      // has done nothing wrong and must not be shown a success line implying four new rooms.
      expect(_result(added: 4).summary, 'Added 4 rooms.');
      expect(_result(removed: 2).summary, 'Removed 2 rooms.');
      expect(_result().summary, 'Nothing changed.');
    });

    test('a plan that adds on one floor and removes on another says both halves', () {
      // The removal is the half nobody wants to learn about later.
      expect(_result(added: 3, removed: 1).summary, 'Added 3 rooms and removed 1 room.');
    });

    test('every figure is read from the row, never assumed', () {
      final parsed = FloorPlanResult.fromJson(const {
        'floors': 3,
        'rooms_added': 4,
        'rooms_removed': 0,
        'rooms_total': 14,
        'beds_total': 41,
      });

      expect(parsed.floors, 3);
      expect(parsed.roomsAdded, 4);
      expect(parsed.roomsTotal, 14);
      expect(parsed.bedsTotal, 41);
      expect(parsed.summary, 'Added 4 rooms.');
    });

    test('a missing column names itself rather than becoming a zero', () {
      // A plan that silently reports "Nothing changed." after creating fourteen rooms is worse
      // than a crash in a log, so the parse is the strict one every other model uses.
      final row = <String, dynamic>{
        'floors': 3,
        'rooms_added': 4,
        'rooms_removed': 0,
        'rooms_total': 14,
      };
      expect(() => FloorPlanResult.fromJson(row), throwsA(isA<RowShapeError>()));
    });
  });

  group('the layout editor', () {
    testWidgets('opens on the building as it stands, not on a default plan', (tester) async {
      await _pump(tester);

      expect(find.text('Floor 1'), findsOneWidget);
      expect(find.text('Floor 2'), findsOneWidget);
      // Both counted from rpc_room_occupancy: floor 1 is 101 (3 of 3) and 102 (1 of 3).
      expect(find.text('2 rooms now · 4 of 6 beds taken'), findsOneWidget);
      expect(find.text('1 room now · 0 of 2 beds taken'), findsOneWidget);
      // Seeded ON the building means there is nothing to save yet, and the button says so.
      expect(find.text('This is the building as it stands. Nothing will change.'), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNull);
    });

    testWidgets('a stepper moves by one, from the count the floor actually has', (tester) async {
      await _pump(tester);

      await tester.tap(find.byTooltip('One more room on floor 2'));
      await _settle(tester);

      // "(1 → 2)" is the proof the stepper started on floor 2's real room count rather than on
      // a zero or a scaffolding default. The bed count is floor 2's own double, not the PG's
      // beds_per_room_default of three.
      expect(find.text('Floor 2: adding 1 room of 2 beds each (1 → 2).'), findsOneWidget);
      expect(find.text('Adding 1 room.'), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('a shrink onto an occupied room is named before the save, not after it',
        (tester) async {
      await _pump(tester);

      // Floor 1 is 101 and 102 and BOTH have residents. Shrinking it by one takes 102, which
      // ow_set_floor_plan would refuse by name — so the screen refuses first.
      await tester.tap(find.byTooltip('One fewer room on floor 1'));
      await _settle(tester);

      expect(find.text('Floor 1: removing 1 room (2 → 1).'), findsOneWidget);
      expect(
        find.textContaining('Room 102 has residents in it, so this removal is refused'),
        findsWidgets,
        reason: 'said on the floor row and again beside the button',
      );
      expect(
        _saveButton(tester).onPressed,
        isNull,
        reason: 'a button that offers a save the server will refuse is a trap',
      );
    });

    testWidgets('a save that removes anything is confirmed first, and reports the server tally',
        (tester) async {
      // Floor 1 now ends in an EMPTY room, so this shrink is one the server would allow.
      final writes = await _pump(
        tester,
        rooms: _roomsWithASpareRoom,
        result: _result(removed: 1),
      );

      await tester.tap(find.byTooltip('One fewer room on floor 1'));
      await _settle(tester);
      expect(find.text('Floor 1: removing 1 room (3 → 2).'), findsOneWidget);
      expect(writes.plan, isNull, reason: 'nothing is sent until the button is pressed');

      await tester.tap(find.widgetWithText(FilledButton, 'Save layout').last);
      await _settle(tester);

      // Adding is free; taking a room away is agreed to out loud.
      expect(find.text('Remove rooms?'), findsOneWidget);
      expect(find.text('Floor 1: removing 1 room (3 → 2).'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Save layout').last);
      await _settle(tester);

      expect(writes.plan, const [
        FloorPlanEntry(floor: 1, rooms: 2, bedsPerNewRoom: 3),
        FloorPlanEntry(floor: 2, rooms: 1, bedsPerNewRoom: 2),
      ]);
      // The SERVER's count, not the preview's — the preview is a prediction and this is not.
      expect(find.text('Removed 1 room.'), findsOneWidget);
    });

    testWidgets('the server refusal reaches the screen in the server own words', (tester) async {
      // A resident can move in between the read this screen seeded from and the save, so a
      // refusal the client could not have predicted is a real state and not a hypothetical.
      // What must survive it is the ROOM NUMBER: rewritten as "Some of that information is not
      // valid" it sends an owner to walk the floor looking for the one room in the way.
      await _pump(
        tester,
        failure: const InvalidInputFailure(
          'Room 102 still has residents in it. Move them to another bed first.',
        ),
      );

      // An ADD, so the screen itself has nothing to object to and the sentence on screen can
      // only have come from the server.
      await tester.tap(find.byTooltip('One more room on floor 2'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save layout').last);
      await _settle(tester);

      expect(
        find.text('Room 102 still has residents in it. Move them to another bed first.'),
        findsOneWidget,
      );
      expect(find.text('Remove rooms?'), findsNothing, reason: 'adding needs no confirmation');
    });

    testWidgets('a PG with no rooms opens on nothing, and the first floor it offers is one',
        (tester) async {
      // "Seeded from the building" and "opens on an empty plan" are the same thing when the
      // building IS empty — what must not happen is a plan invented to fill the screen. The
      // first floor starts at the RPC's own minimum of one room, and its beds come from
      // hostels.beds_per_room_default because there is no building yet to learn a style from.
      final writes = await _pump(tester, rooms: const []);

      expect(find.text('No floors yet'), findsOneWidget);
      expect(find.text('Floor 1'), findsNothing);
      expect(_saveButton(tester).onPressed, isNull);

      await tester.tap(find.widgetWithText(TextButton, 'Add floor 1'));
      await _settle(tester);

      expect(find.text('Floor 1'), findsOneWidget);
      expect(find.text('Nothing on this floor yet.'), findsOneWidget);
      expect(find.text('Floor 1 is new: 1 room of 3 beds each.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save layout').last);
      await _settle(tester);

      expect(writes.plan, const [FloorPlanEntry(floor: 1, rooms: 1, bedsPerNewRoom: 3)]);
    });

    testWidgets('a PG whose floors are not numbered 1..N is told so instead of renumbered',
        (tester) async {
      // public.floors imposes no such numbering and Floor says so: a ground floor may be 0.
      // ow_set_floor_plan cannot describe that building, and quietly shifting somebody's
      // storeys to fit the editor is not this screen's decision.
      await _pump(tester, rooms: const [
        RoomOccupancy(
          roomId: 'r-g1',
          floorId: 'f-0',
          floorNumber: 0,
          roomNumber: 'G1',
          capacity: 2,
          occupied: 0,
        ),
        RoomOccupancy(
          roomId: 'r-101',
          floorId: 'f-1',
          floorNumber: 1,
          roomNumber: '101',
          capacity: 2,
          occupied: 0,
        ),
      ]);

      expect(find.text('These floors cannot be edited here'), findsOneWidget);
      expect(find.textContaining('floors numbered 0, 1'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save layout'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Four things design review found, each of which shipped once. The fixes are cheap; the
  // reason they are pinned is that every one of them is invisible in ordinary use and only
  // bites on the path somebody takes when they are in a hurry.
  group('the ways this screen went wrong once', () {
    testWidgets('backing out mid-save still refreshes the building', (tester) async {
      // THE ONE WITH TEETH. The refresh used to sit BELOW `if (!mounted) return;`, and moving it
      // above was not enough either: `WidgetRef.invalidate` on an unmounted element THROWS a
      // StateError (not behind an assert, so in release too), the throw was caught by the
      // generic handler, and `if (mounted)` suppressed any report of it. The write had landed.
      // Every one of these providers is holdForSession-pinned, so the stale building then
      // survived the session — and because the editor SEEDS from that grid, the next visit could
      // under-report a deletion: the dialog says "3 → 2, removing 1" while the server, holding
      // four, removes two. Hence the ProviderContainer captured before the await.
      var buildsOfTheGrid = 0;
      final writes = _FakeLayout(result: _result(added: 1), hold: true);
      final navigator = GlobalKey<NavigatorState>();

      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(_session),
            currentHostelIdProvider.overrideWithValue(_hostelId),
            currentPeriodMonthProvider.overrideWithValue(_period),
            myHostelsProvider.overrideWith((ref) => [_sunrise]),
            hostelProvider.overrideWith((ref, id) => _sunrise),
            roomOccupancyProvider.overrideWith((ref, id) {
              buildsOfTheGrid++;
              return _rooms;
            }),
            roomLayoutWritesProvider.overrideWithValue(writes),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            // A listener BELOW the editor, so the grid stays watched after the editor is popped.
            // Without one, an invalidated autoDispose provider has nobody to rebuild it and the
            // count would not move however correct the fix.
            home: Scaffold(
              body: Consumer(
                builder: (_, ref, _) {
                  ref.watch(roomOccupancyProvider(_hostelId));
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      navigator.currentState!.push(OwnerFloorPlanScreen.route(_hostelId));
      await _settle(tester);

      final before = buildsOfTheGrid;

      // Grow floor 2 so there is something to save, then save and leave while it is in flight.
      await tester.tap(find.byTooltip('One more room on floor 2'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save layout').last);
      await tester.pump();

      navigator.currentState!.pop();
      await _settle(tester);

      writes.release();
      await _settle(tester);

      expect(writes.plan, isNotNull, reason: 'the write must still have gone out');
      expect(
        buildsOfTheGrid,
        greaterThan(before),
        reason: 'the building was refetched even though the screen that saved it had gone. If '
            'this fails the owner keeps a stale grid for the session, and the editor seeds its '
            'next plan from it.',
      );
    });

    testWidgets('the last floor cannot be removed, so an empty plan can never be sent',
        (tester) async {
      // Walking down to zero storeys used to be possible: Save stayed enabled, the confirmation
      // listed the whole building, and `[]` went on the wire for ow_set_floor_plan to refuse.
      // A destructive-looking journey that ends in an error message is worse than a control that
      // simply stops.
      await _pump(tester, rooms: const [
        RoomOccupancy(
          roomId: 'r-101',
          floorId: 'f-1',
          floorNumber: 1,
          roomNumber: '101',
          capacity: 2,
          occupied: 0,
        ),
      ]);

      final remove = find.widgetWithText(TextButton, 'Remove floor 1');
      expect(remove, findsOneWidget);
      expect(
        tester.widget<TextButton>(remove).onPressed,
        isNull,
        reason: 'a hostel with one storey has no floor to give up',
      );
    });

    testWidgets('dropping an occupied floor says why the save is dead, beside the save',
        (tester) async {
      // The blocked sentence lives on the floor ROW — and removing a floor removes its row, so
      // the only remaining copy sat in the preview card at the bottom of a scrolling list. On a
      // twelve-storey hostel that is off screen, leaving a dead primary button with no
      // explanation anywhere near it.
      // The TOP floor is the occupied one, because "remove a floor" only ever takes the last —
      // and after the minFloors fix a two-storey building cannot give up its ground floor at all.
      await _pump(tester, rooms: const [
        RoomOccupancy(
          roomId: 'r-101',
          floorId: 'f-1',
          floorNumber: 1,
          roomNumber: '101',
          capacity: 3,
          occupied: 0,
        ),
        RoomOccupancy(
          roomId: 'r-201',
          floorId: 'f-2',
          floorNumber: 2,
          roomNumber: '201',
          capacity: 3,
          occupied: 2,
        ),
      ]);

      // Dropping floor 2 takes room 201, which somebody sleeps in. Its ROW goes with it, so the
      // only place left that can explain the dead button is the save bar.
      await tester.tap(find.widgetWithText(TextButton, 'Remove floor 2'));
      await _settle(tester);

      expect(_saveButton(tester).onPressed, isNull);
      expect(
        find.textContaining('residents in'),
        findsWidgets,
        reason: 'the reason the button is dark must survive the removal of the row that said it',
      );
      // Floor 2's row is gone — it is the floor being dropped — so the sentence about ITS room
      // cannot be coming from a floor row any more. Floor 1 is untouched and still listed, and
      // nothing on it is blocked, so it is not the source either.
      expect(find.text('Floor 2'), findsNothing);
      expect(find.text('Floor 1'), findsOneWidget);
      expect(
        find.textContaining('Room 201'),
        findsWidgets,
        reason: 'the blocked room is named even though the row that used to name it is gone',
      );
    });

    testWidgets('a server refusal is dropped the moment the plan it was about changes',
        (tester) async {
      // "Room 102 still has residents in it." is true of a plan that was actually sent. Left
      // standing after an edit it becomes a lie in a live region — a refusal about a removal the
      // current plan no longer contains, over a headline that now reads "Adding 1 room."
      await _pump(
        tester,
        rooms: _roomsWithASpareRoom,
        failure: const InvalidInputFailure(
          'Room 102 still has residents in it. Move them to another bed first.',
        ),
      );

      await tester.tap(find.byTooltip('One fewer room on floor 1'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save layout').last);
      await _settle(tester);
      // The dialog's confirm carries the same words as the bar's button — it is the same action
      // being agreed to — so this is deliberately the LAST one, which is the dialog's.
      await tester.tap(find.widgetWithText(FilledButton, 'Save layout').last);
      await _settle(tester);

      expect(
        find.textContaining('Room 102 still has residents in it'),
        findsOneWidget,
        reason: 'the server names the room and the screen repeats it verbatim',
      );

      // Now change the plan. The refusal is about something that no longer exists.
      await tester.tap(find.byTooltip('One more room on floor 2'));
      await _settle(tester);

      expect(
        find.textContaining('Room 102 still has residents in it'),
        findsNothing,
        reason: 'a refusal that outlives its plan is a false statement in a live region',
      );
    });
  });
}

/// Stands in for [RoomLayoutWrites] so the interesting states — a refusal, a tally — can be
/// held down without a network or a Supabase client. Records the plan it was handed, because
/// what goes on the wire is half of what these tests are checking.
final class _FakeLayout implements RoomLayoutWrites {
  _FakeLayout({required this.result, this.failure, this.hold = false});

  final FloorPlanResult result;
  final Object? failure;

  /// Hold the write open until [release] is called, so a test can do something — back out of the
  /// screen, say — while it is still in flight. Without this the future resolves inside the same
  /// `tester.tap`, and the interesting window never exists.
  final bool hold;
  final Completer<void> _gate = Completer<void>();
  void release() => _gate.complete();

  /// Null until the button is actually pressed.
  List<FloorPlanEntry>? plan;

  @override
  Future<FloorPlanResult> setFloorPlan({
    required String hostelId,
    required List<FloorPlanEntry> plan,
  }) async {
    this.plan = plan;
    if (hold) await _gate.future;
    final thrown = failure;
    if (thrown != null) throw thrown;
    return result;
  }
}
