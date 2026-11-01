// A DEV TOOL, not a test (the name does not end in _test): renders the Super Admin console's
// Overview and Hostels tabs to build/shots/ so the layout can be looked at without a device.
// Icons are squares here (the test runner stubs the icon font); check glyphs on a phone.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/features/super_admin/sa_shell.dart';

void main() {
  testWidgets('super admin shots', (tester) async {
    tester.view.physicalSize = const Size(393 * 2, 873 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(ApnivaasSession(
          userId: '00000000-0000-0000-0000-0000000000aa',
          role: UserRole.superAdmin,
          fullName: 'Platform Admin',
          status: 'active',
          mustChangePassword: false,
          email: 'admin@example.com',
        )),
        saStatsProvider.overrideWith((ref) => const SaStats(
              totalHostels: 12,
              totalOwners: 9,
              totalStudents: 418,
              activeSubs: 9,
              expiringSubs: 2,
              expiredSubs: 1,
              monthlySubscriptionRevenue: 184000,
            )),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ApnivaasTheme.light(),
          debugShowCheckedModeBanner: false,
          home: const SaShell(),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    Future<void> shoot(String name) async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/shots').createSync(recursive: true);
        File('build/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await shoot('sa-overview');
  });
}
