// A DEV TOOL, not a test — `flutter test` skips it because the name does not end in _test.
// Run it explicitly: `flutter test test/_shot.dart`, then look in build/shots/.
//
// WHY IT EARNS ITS PLACE. Signed-in screens cannot be reached on a device without credentials,
// so chrome changes to the five shells were going in blind. This renders them to real PNGs from
// a widget test in about five seconds. It has already caught two bugs nothing else would have:
// a greeting drawn in near-black on the indigo brow, and a wordmark that names its own colour
// and so could not inherit the header's white. Icons render as squares here — the test runner
// stubs the icon font — so check glyphs on a device, not in these.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/owner/owner_insights.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/onboarding/onboarding_screen.dart';
import 'package:mobile/features/owner/rooms/floor_plan_screen.dart';
import 'package:mobile/core/boot/splash_gate.dart';
import 'package:mobile/features/shell/role_shell.dart';
import 'package:mobile/features/splash/splash_screen.dart';

const _hostelId = 'h-sunrise';
const _period = '2026-08';

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

Future<void> _shoot(WidgetTester tester, String name, ThemeData theme, [UserRole role = UserRole.owner]) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(NivoraSession(userId: 'u-1', role: role, fullName: 'Ananya Rao', status: 'active', mustChangePassword: false, hostelId: _hostelId)),
        currentHostelIdProvider.overrideWithValue(_hostelId),
        currentPeriodMonthProvider.overrideWithValue(_period),
        myHostelsProvider.overrideWith((ref) => [_sunrise]),
        hostelStatsProvider.overrideWith((ref, q) => Completer<HostelStats?>().future),
        ownerActivityProvider.overrideWith((ref, h) => const AsyncValue<List<ActivityItem>>.data([])),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: theme,
          home: RoleShell(role: role),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // runAsync: PNG encoding is real async work on a real thread, and the fake async zone a
  // widget test runs in never lets it complete. Without this the whole test hangs with no
  // output at all, which is exactly what it did the first time.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/shots').createSync(recursive: true);
    File('build/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('WROTE build/shots/$name.png');
  });
}

Future<void> _shootPlain(WidgetTester tester, String name, Widget home, ThemeData theme,
    {Duration settle = const Duration(milliseconds: 500)}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(theme: theme, home: home),
  ));
  await tester.pump();
  await tester.pump(settle);
  // Images decode on a real thread, which the fake async zone of a widget test never lets
  // finish — so every `Image.asset` in these shots rendered as nothing until this was added.
  // The splash's brand mark was the one that made it obvious: the PNG showed IVORA alone.
  for (final finder in <Finder>[find.byType(Image)]) {
    for (var i = 0; i < finder.evaluate().length; i++) {
      final widget = tester.widget<Image>(finder.at(i));
      await tester.runAsync(() => precacheImage(widget.image, tester.element(finder.at(i))));
    }
  }
  await tester.pump();
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/shots').createSync(recursive: true);
    File('build/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('WROTE build/shots/$name.png');
  });
}

/// The layout editor, on a building whose rooms are deliberately NOT all the same size —
/// which is the whole thing the product owner asked to be able to do.
Future<void> _shootLayout(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  const rooms = [
    RoomOccupancy(roomId: 'r1', floorId: 'f1', floorNumber: 1,
        roomNumber: '101', capacity: 3, occupied: 3),
    RoomOccupancy(roomId: 'r2', floorId: 'f1', floorNumber: 1,
        roomNumber: '102', capacity: 3, occupied: 1),
    RoomOccupancy(roomId: 'r3', floorId: 'f1', floorNumber: 1,
        roomNumber: '103', capacity: 4, occupied: 0),
    RoomOccupancy(roomId: 'r4', floorId: 'f1', floorNumber: 1,
        roomNumber: '104', capacity: 2, occupied: 1),
    RoomOccupancy(roomId: 'r5', floorId: 'f2', floorNumber: 2,
        roomNumber: '201', capacity: 6, occupied: 2),
  ];

  final key = GlobalKey();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sessionProvider.overrideWithValue(NivoraSession(
          userId: 'u-1', role: UserRole.owner, fullName: 'Ananya Rao',
          status: 'active', mustChangePassword: false, hostelId: _hostelId)),
      currentHostelIdProvider.overrideWithValue(_hostelId),
      currentPeriodMonthProvider.overrideWithValue(_period),
      hostelProvider.overrideWith((ref, id) => _sunrise),
      roomOccupancyProvider.overrideWith((ref, id) => rooms),
    ],
    child: RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: NivoraTheme.light(),
        home: const OwnerFloorPlanScreen(hostelId: _hostelId),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/shots').createSync(recursive: true);
    File('build/shots/layout.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('WROTE build/shots/layout.png');
  });
}

void main() {
  testWidgets('layout', _shootLayout);

  // THE OPENING, AT REST. Shot at splashMinimum so this is the frame the wordmark FINISHES on
  // — the one the product owner photographed off his phone and said was not centred. Rendering
  // it here is how that gets looked at without a device and without racing a 1,500ms animation
  // against a one-second adb screencap.
  testWidgets('splash', (t) async => _shootPlain(
      t, 'splash', const ProviderScope(child: SplashScreen()), NivoraTheme.light(),
      settle: splashMinimum));

  testWidgets('onboarding', (t) async => _shootPlain(
      t, 'onboarding', OnboardingScreen(onDone: () {}), NivoraTheme.light()));

  for (final role in [UserRole.owner, UserRole.warden, UserRole.manager, UserRole.superAdmin]) {
    testWidgets('${role.name} light', (t) async => _shoot(t, '${role.name}_light', NivoraTheme.light(), role));
    testWidgets('${role.name} dark', (t) async => _shoot(t, '${role.name}_dark', NivoraTheme.dark(), role));
  }
}
