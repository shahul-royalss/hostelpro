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
import 'package:mobile/features/shell/role_shell.dart';

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

Future<void> _shootPlain(WidgetTester tester, String name, Widget home, ThemeData theme) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(theme: theme, home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
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

void main() {
  testWidgets('onboarding', (t) async => _shootPlain(
      t, 'onboarding', OnboardingScreen(onDone: () {}), NivoraTheme.light()));

  for (final role in [UserRole.owner, UserRole.warden, UserRole.manager, UserRole.superAdmin]) {
    testWidgets('${role.name} light', (t) async => _shoot(t, '${role.name}_light', NivoraTheme.light(), role));
    testWidgets('${role.name} dark', (t) async => _shoot(t, '${role.name}_dark', NivoraTheme.dark(), role));
  }
}
