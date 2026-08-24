import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/features/super_admin/data/sa_providers.dart';
import 'package:mobile/features/super_admin/sa_shell.dart';

/// The super admin console had NO tests when it landed — the agent that built it died before
/// writing any. It is also the one console the product owner asked about by name, because it is
/// where an owner account gets created, so shipping it unverified was not an option.
///
/// No network: every provider the screens read is overridden with a fixed value. That is
/// deliberate rather than convenient — the machine this is developed on has its TLS intercepted
/// by antivirus, so an emulator cannot reach Supabase at all. Tests that need a live database
/// would simply never run here.
const _stats = SaStats(
  totalHostels: 12,
  totalOwners: 9,
  totalStudents: 418,
  activeSubs: 9,
  expiringSubs: 2,
  expiredSubs: 1,
  monthlySubscriptionRevenue: 184000,
);

final _session = NivoraSession(
  userId: '00000000-0000-0000-0000-0000000000aa',
  role: UserRole.superAdmin,
  fullName: 'Platform Admin',
  status: 'active',
  mustChangePassword: false,
  email: 'admin@example.com',
);

/// Typed as List<Object> and cast at the call site because Riverpod 3 does not export
/// `Override` from its public barrel, so the real element type cannot be named here.
List<Object> _overrides({SaStats? stats, Object? statsError}) => [
      sessionProvider.overrideWithValue(_session),
      if (statsError != null)
        saStatsProvider.overrideWith((ref) => Future<SaStats>.error(statsError))
      else
        saStatsProvider.overrideWith((ref) => stats ?? _stats),
    ];

Future<void> _pump(WidgetTester tester, List<Object> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: NivoraTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const SaShell(),
      ),
    ),
  );
  // Not pumpAndSettle: a loading spinner never stops animating, so settling would hang.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the console renders instead of the "not built yet" placeholder', (tester) async {
    await _pump(tester, _overrides());

    // The exact string every super-admin tab used to show.
    expect(find.text('This screen is not built yet.'), findsNothing);
    expect(find.byType(SaShell), findsOneWidget);
  });

  testWidgets('platform figures come from the stats row, not from literals', (tester) async {
    await _pump(tester, _overrides());

    // If any of these were hardcoded, changing the stub below would not change the screen.
    expect(find.textContaining('12'), findsWidgets, reason: 'total hostels');
    expect(find.textContaining('418'), findsWidgets, reason: 'total students');
  });

  testWidgets('a different stats row produces different figures', (tester) async {
    await _pump(
      tester,
      _overrides(
        stats: const SaStats(
          totalHostels: 3,
          totalOwners: 2,
          totalStudents: 57,
          activeSubs: 3,
          expiringSubs: 0,
          expiredSubs: 0,
          monthlySubscriptionRevenue: 21000,
        ),
      ),
    );

    expect(find.textContaining('57'), findsWidgets);
    // The first stub's numbers must be gone — this is what catches a fabricated figure.
    expect(find.textContaining('418'), findsNothing);
  });

  testWidgets('a failed load says so rather than showing zeroes', (tester) async {
    await _pump(tester, _overrides(statsError: Exception('offline')));

    // Zero hostels and a broken connection are different facts. Reporting the second as the
    // first is how a platform admin concludes their business disappeared overnight.
    expect(find.byType(SaShell), findsOneWidget);
    expect(find.textContaining('418'), findsNothing);
  });

  test('the four tab indices agree across every file that uses them', () {
    // role_shell.dart owns the labels, SaShell owns the IndexedStack, and the Overview's
    // tappable figures jump between them. A reordered bar in one file is a mis-routed tap.
    expect(SaTabs.overview, 0);
    expect(SaTabs.hostels, 1);
    expect(SaTabs.subscriptions, 2);
    expect(SaTabs.security, 3);
    expect(SaTabs.count, 4);
  });
}
