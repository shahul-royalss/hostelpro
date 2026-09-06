// DOES IT FIT ON THE PHONE SOMEBODY ACTUALLY HAS?
//
// ── WHY THIS FILE ─────────────────────────────────────────────────────────────────────────
//
// Every other test in this suite runs at one size, which is the size the test binding happens
// to default to. That proves the widgets compose; it proves nothing about the device the app
// ships to. The two failures it cannot see are the two that reach a Play Store review:
//
//   A RenderFlex overflow — the yellow-and-black hazard stripe — on a narrow phone.
//   The same overflow at large system text, on a phone of any width.
//
// Both are layout-time errors. Flutter reports them through FlutterError, the test binding
// records them, and `tester.takeException()` hands them over. So a test that pumps a screen at
// a size and then asks for the exception is a real overflow detector, not an approximation.
//
// ── THE SIZES, AND WHY THESE ─────────────────────────────────────────────────────────────
//
// Not a catalogue of phones — a catalogue of EXTREMES, because anything between two passing
// extremes passes too. The narrowest mainstream Android in use, a typical modern Android, the
// smallest current iPhone, the largest iPhone, and a tablet. If the app fits 320 and fits 1024,
// the hundred sizes in between are not the risk.
//
// ── THE TEXT SCALES ──────────────────────────────────────────────────────────────────────
//
// 1.0 is the default nobody has trouble with. 1.3 is Android's "Large". 2.0 is the top of
// Android's accessibility range and roughly iOS's largest accessibility size. An app that holds
// at 2.0 holds everywhere; an app that breaks at 1.3 breaks for a very large number of people
// over forty, which in this product is every PG owner.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/auth/login_screen.dart';
import 'package:mobile/features/onboarding/onboarding_screen.dart';
import 'package:mobile/features/owner/owner_insights.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/shell/role_shell.dart';

typedef Device = ({String name, Size size, double dpr});

const _devices = <Device>[
  // Galaxy A0x and the bottom of the Android market — 320dp logical is the narrowest width
  // Material tells you to support, and the width where fixed-size Rows give up.
  (name: 'small android 320dp', size: Size(960, 1706), dpr: 3.0),
  // The modal modern Android.
  (name: 'typical android 412dp', size: Size(1080, 2400), dpr: 2.625),
  // iPhone 13 mini / SE-class — the smallest current iPhone.
  (name: 'small iphone 375dp', size: Size(1125, 2436), dpr: 3.0),
  // iPhone 15 Pro Max — the tallest phone with the deepest safe areas.
  (name: 'large iphone 430dp', size: Size(1290, 2796), dpr: 3.0),
  // A 10-inch tablet in portrait. The failure here is the opposite one: a form stretched to
  // full width with no max, which reads as a website rather than an app.
  (name: 'tablet 800dp', size: Size(1600, 2560), dpr: 2.0),
];

const _scales = <double>[1.0, 1.3, 2.0];

const _hostelId = 'h-demo';

final _hostel = Hostel(
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

Widget _wrap(Widget home, ThemeData theme, double scale, UserRole role) => ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(NivoraSession(
          // A long name on purpose. "Ananya" fits anywhere; the greeting row is only under
          // pressure when somebody's name is as long as names actually get.
          userId: 'u-1',
          role: role,
          fullName: 'Lakshmi Venkataraman Subramanian',
          status: 'active',
          mustChangePassword: false,
          hostelId: _hostelId,
        )),
        currentHostelIdProvider.overrideWithValue(_hostelId),
        currentPeriodMonthProvider.overrideWithValue('2026-08'),
        myHostelsProvider.overrideWith((ref) => [_hostel]),
        // Left pending on purpose: the skeleton state is the widest the layout ever gets,
        // because a skeleton bar has no text to shrink.
        hostelStatsProvider.overrideWith((ref, q) => Completer<HostelStats?>().future),
        ownerActivityProvider
            .overrideWith((ref, h) => const AsyncValue<List<ActivityItem>>.data([])),
      ],
      child: MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: home,
        ),
      ),
    );

/// Pump, then ask what broke. Returns the overflow/layout error, or null.
Future<Object?> _pumpAndCatch(WidgetTester tester, Widget app, Device d) async {
  tester.view.physicalSize = d.size;
  tester.view.devicePixelRatio = d.dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return tester.takeException();
}

void main() {
  group('nothing overflows on any device, at any text size', () {
    for (final d in _devices) {
      for (final scale in _scales) {
        final at = '${d.name} @ ${scale}x text';

        testWidgets('sign-in — $at', (tester) async {
          final e = await _pumpAndCatch(
            tester,
            _wrap(const LoginScreen(), NivoraTheme.light(), scale, UserRole.owner),
            d,
          );
          expect(e, isNull, reason: 'sign-in overflowed at $at');
        });

        testWidgets('onboarding — $at', (tester) async {
          // The one screen with no scroll view: four fixed pages with a heading, a paragraph
          // and a control bar. If large text breaks anything, it breaks this first.
          final e = await _pumpAndCatch(
            tester,
            _wrap(OnboardingScreen(onDone: () {}), NivoraTheme.light(), scale, UserRole.owner),
            d,
          );
          expect(e, isNull, reason: 'onboarding overflowed at $at');
        });

        for (final role in UserRole.values) {
          testWidgets('${role.name} shell — $at', (tester) async {
            final e = await _pumpAndCatch(
              tester,
              _wrap(RoleShell(role: role), NivoraTheme.light(), scale, role),
              d,
            );
            expect(e, isNull, reason: '${role.name} shell overflowed at $at');
          });
        }
      }
    }
  });

  group('the dark theme has the same geometry', () {
    // Colour cannot cause an overflow, but a theme can: a different font weight or a different
    // component density changes intrinsic widths. Checked at the two extremes only, because
    // repeating the full matrix in dark would double a suite for a risk that is this narrow.
    for (final d in [_devices.first, _devices.last]) {
      testWidgets('owner shell, dark, 2.0x text — ${d.name}', (tester) async {
        final e = await _pumpAndCatch(
          tester,
          _wrap(const RoleShell(role: UserRole.owner), NivoraTheme.dark(), 2.0, UserRole.owner),
          d,
        );
        expect(e, isNull, reason: 'the dark owner shell overflowed on ${d.name} at 2.0x');
      });
    }
  });
}
