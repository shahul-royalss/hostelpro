// A THROWAWAY. Renders signed-in shells to real PNGs so a change to the chrome can be LOOKED
// at without a device and without anybody's password. Not named *_test.dart, so `flutter test`
// never picks it up; run it explicitly. Delete when the redesign is verified.
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
import 'package:mobile/features/shell/role_shell.dart';

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
  totalFloors: 3,
  totalRooms: 12,
  bedsPerRoomDefault: 3,
  status: HostelStatus.active,
  createdAt: DateTime.utc(2026, 3, 1),
  updatedAt: DateTime.utc(2026, 3, 1),
);

Future<void> _shoot(WidgetTester tester, String name, ThemeData theme) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(_session),
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
          home: const RoleShell(role: UserRole.owner),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory(r'C:\shots')..createSync(recursive: true);
  File('${dir.path}\$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote ${dir.path}\$name.png');
}

void main() {
  testWidgets('owner shell, light', (t) async => _shoot(t, 'owner_light', NivoraTheme.light()));
  testWidgets('owner shell, dark', (t) async => _shoot(t, 'owner_dark', NivoraTheme.dark()));
}
