import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/student/widgets/common.dart';
import 'package:mobile/features/warden/widgets/warden_ui.dart';
import 'package:mobile/shared/illustrations.dart';

/// The empty-state artwork, and the two rules that keep it honest.
///
/// This file exists because the failure it catches is SILENT. An asset can be referenced by a
/// constant, pass the analyzer, pass every widget test, and still be absent from the shipped
/// bundle — because `pubspec.yaml` no longer declares the directory, or because the file was
/// renamed. The app would then draw the fallback glyph forever and nobody would notice until a
/// customer did. `rootBundle.load` is the only check that actually reads what was packaged.
void main() {
  const all = <String>[
    EmptyArt.residents,
    EmptyArt.complaints,
    EmptyArt.notices,
    EmptyArt.payments,
  ];

  testWidgets('every EmptyArt path is really in the bundle', (tester) async {
    for (final path in all) {
      final data = await rootBundle.load(path);
      // A declared-but-empty file would still "load". These are 12-36KB each.
      expect(data.lengthInBytes, greaterThan(1000), reason: '$path is missing or truncated');
    }
  });

  testWidgets('artwork replaces the glyph, and the words stay real Text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyNote(
            illustration: EmptyArt.notices,
            icon: Icons.campaign_outlined,
            title: 'No notices yet',
            message: 'Announcements from the hostel owner appear here.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    // The artwork stands INSTEAD of the glyph, not beside it — two drawings of the same idea.
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    // The sentence is never baked into the picture: it stays translatable and selectable.
    expect(find.text('No notices yet'), findsOneWidget);
    expect(find.text('Announcements from the hostel owner appear here.'), findsOneWidget);
  });

  testWidgets('a state with no artwork still draws its glyph', (tester) async {
    // The search miss and the filter miss keep the glyph on purpose: artwork says "nothing
    // here yet", which is not what "no match for that" means.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(icon: Icons.search_off_rounded, title: 'No match for "kumar"'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
