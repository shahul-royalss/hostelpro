import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/shared/clay/clay_icons.dart';

/// The clay icons — the registry, the bundle, and the one widget that draws them.
///
/// The failure this file exists for is SILENT, as it is for the illustrations: a path can be a
/// constant, pass the analyzer and every widget test, and still be missing from the shipped
/// bundle, because the folder stopped being declared or a file was renamed. ClayIcon would then
/// draw its fallback glyph forever. `rootBundle.load` reads what was packaged, and the folder
/// listing proves the registry and the disk agree in both directions.
///
/// Images do not decode under `flutter test`, so nothing here asserts pixels. What is asserted
/// is everything a decode would not tell you anyway: that the bytes are a WebP with alpha at the
/// width the registry claims, and that the widget asks for the right decode size and semantics.

/// The VP8X header of a WebP: whether it carries alpha, and its canvas width.
({bool alpha, int width}) _vp8x(Uint8List b) {
  String tag(int at) => String.fromCharCodes(b.sublist(at, at + 4));
  expect(tag(0), 'RIFF');
  expect(tag(8), 'WEBP');
  expect(tag(12), 'VP8X', reason: 'an extended WebP is the only kind that can say it has alpha');
  final flags = b[20];
  final width = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
  return (alpha: flags & 0x10 != 0, width: width);
}

void main() {
  group('the registry and the bundle agree', () {
    test('every constant is a distinct file in assets/clay, and every file has a constant', () {
      expect(ClayIcons.all.toSet(), hasLength(ClayIcons.all.length), reason: 'a duplicate entry');
      final onDisk = Directory('assets/clay')
          .listSync()
          .whereType<File>()
          .map((f) => 'assets/clay/${f.uri.pathSegments.last}')
          .toSet();
      expect(onDisk, ClayIcons.all.toSet(),
          reason: 'a file is in the folder with no constant, or a constant names no file');
    });

    testWidgets('every path is really in the packaged bundle', (tester) async {
      for (final path in ClayIcons.all) {
        final data = await rootBundle.load(path);
        // The smallest icon is a few KB; a declared-but-empty file would still "load".
        expect(data.lengthInBytes, greaterThan(1000), reason: '$path is missing or truncated');
      }
    });

    test('every file is a WebP with alpha, at the width the registry decodes against', () {
      for (final path in ClayIcons.all) {
        final header = _vp8x(File(path).readAsBytesSync());
        expect(header.alpha, isTrue, reason: '$path has no alpha and would sit in a box');
        expect(header.width, ClayIcons.sourceWidthOf(path), reason: '$path width');
      }
    });

    test('the deliberately unconverted art stays out', () {
      for (final name in ['role-seeker', 'role-owner-man', 'role-owner-mascot']) {
        expect(File('assets/clay/$name.webp').existsSync(), isFalse,
            reason: '$name was not chosen; see the header of clay_icons.dart');
      }
    });

    test('the four tabs with their own off-art name real files on both sides', () {
      expect(ClayIcons.navPairs, hasLength(4));
      ClayIcons.navPairs.forEach((on, off) {
        expect(ClayIcons.all, contains(on));
        expect(ClayIcons.all, contains(off));
        expect(off, endsWith('-off.webp'));
      });
    });

    test('every icon has a fallback glyph of its own, and every domain has an icon', () {
      for (final path in ClayIcons.all) {
        expect(ClayIcons.fallbackFor(path), isNot(Icons.circle_outlined),
            reason: '$path would degrade to an anonymous circle');
      }
      for (final d in ApnivaasDomain.values) {
        expect(ClayIcons.all, contains(domainClayIcon(d)), reason: d.name);
      }
    });
  });

  group('ClayIcon', () {
    Widget host(Widget child) => MaterialApp(
          theme: ApnivaasTheme.light(),
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('is decorative unless it is given a label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const ClayIcon(ClayIcons.money)));
      expect(find.bySemanticsLabel(RegExp('.')), findsNothing,
          reason: 'a decorative icon read aloud says its tile twice');

      await tester.pumpWidget(host(const ClayIcon(ClayIcons.money, semanticLabel: 'Money')));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Money')),
        matchesSemantics(label: 'Money', isImage: true),
      );
      handle.dispose();
    });

    testWidgets('decodes at the size it is drawn, never above the file', (tester) async {
      final dpr = tester.view.devicePixelRatio;
      for (final size in [ClaySize.list, ClaySize.action, ClaySize.promo, ClaySize.heroArt]) {
        for (final path in [ClayIcons.money, ClayIcons.roleOwner]) {
          await tester.pumpWidget(host(ClayIcon(path, size: size)));
          final image = tester.widget<Image>(find.byType(Image));
          expect(image.image, isA<ResizeImage>());
          expect((image.image as ResizeImage).width,
              math.min((size * dpr).round(), ClayIcons.sourceWidthOf(path)),
              reason: '$path at $size');
          expect(tester.getSize(find.byType(ClayIcon)), Size.square(size));
        }
      }
    });

    testWidgets('greyscale goes through the one filter, and only when asked', (tester) async {
      await tester.pumpWidget(host(const ClayIcon(ClayIcons.tasks)));
      expect(find.byType(ColorFiltered), findsNothing, reason: 'clay is never tinted');
      await tester.pumpWidget(host(const ClayIcon(ClayIcons.tasks, greyscale: true)));
      final filtered = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
      expect(filtered.colorFilter, ClayIcon.greyscaleFilter);
    });

    testWidgets('a file that cannot load degrades to a brand-tinted glyph, not a broken box',
        (tester) async {
      const missing = 'assets/clay/not-a-clay-icon.webp';
      await tester.pumpWidget(host(const ClayIcon(missing, size: ClaySize.promo)));
      // The load fails on a real future; let it, then rebuild with the error.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      final glyph = tester.widget<Icon>(find.byIcon(ClayIcons.fallbackFor(missing)));
      expect(glyph.color, ApnivaasColors.forest);
      expect(glyph.size, closeTo(ClaySize.promo * 0.55, 0.001));
      expect(tester.getSize(find.byType(ClayIcon)), const Size.square(ClaySize.promo),
          reason: 'the fallback keeps the art\'s footprint, so nothing around it moves');
    });
  });
}
