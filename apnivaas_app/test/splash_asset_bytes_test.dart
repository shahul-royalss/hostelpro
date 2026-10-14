// THE LAUNCH ANIMATION, CHECKED FROM ITS OWN BYTES.
//
// Image decoding silently does nothing under `flutter test`, so a test that "looks at" the WebP
// would pass on an empty picture. These read the file instead: the RIFF container states its loop
// count and every frame's duration in plain integers (WebP container spec: ANIM loop count at
// body offset 4, two bytes little-endian; ANMF frame duration at body offset 12, three bytes
// little-endian). They also hold every copy of the launch ground to one value, because a seam
// between the native window and the first Flutter frame is a flash on every cold start.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/boot/splash_gate.dart';

class _Webp {
  _Webp(this.loopCount, this.frameDurationsMs);
  final int? loopCount;
  final List<int> frameDurationsMs;
}

_Webp _parse(Uint8List b) {
  String tag(int at) => String.fromCharCodes(b.sublist(at, at + 4));
  int u16(int at) => b[at] | b[at + 1] << 8;
  int u24(int at) => b[at] | b[at + 1] << 8 | b[at + 2] << 16;
  int u32(int at) => u24(at) | b[at + 3] << 24;

  if (tag(0) != 'RIFF' || tag(8) != 'WEBP') {
    throw StateError('$kSplashAnimationAsset is not a WebP RIFF container');
  }
  int? loop;
  final durations = <int>[];
  var i = 12;
  while (i + 8 <= b.length) {
    final t = tag(i);
    final size = u32(i + 4);
    final body = i + 8;
    if (t == 'ANIM') loop = u16(body + 4);
    if (t == 'ANMF') durations.add(u24(body + 12));
    i = body + size + (size & 1);
  }
  return _Webp(loop, durations);
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  late _Webp anim;
  setUpAll(() => anim = _parse(File(kSplashAnimationAsset).readAsBytesSync()));

  test('the animation plays exactly once (a loop count of 0 would replay forever)', () {
    expect(anim.loopCount, 1);
  });

  test('kSplashFrameCount matches the file, so the splash ends on the real last frame', () {
    expect(anim.frameDurationsMs.length, kSplashFrameCount);
  });

  test('splashAnimationLength matches the file, and fits inside the cap', () {
    final total = anim.frameDurationsMs.fold<int>(0, (a, b) => a + b);
    expect(Duration(milliseconds: total), splashAnimationLength);
    expect(splashAnimationLength < splashCap, isTrue);
  });

  test('the animation is small enough to ship', () {
    // About 430 KB today. A re-export at full size or full length would quietly add megabytes.
    expect(File(kSplashAnimationAsset).lengthSync(), lessThan(600 * 1024));
  });

  test('the reduce-motion still is a real WebP', () {
    final still = File(kSplashStillAsset).readAsBytesSync();
    expect(String.fromCharCodes(still.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(still.sublist(8, 12)), 'WEBP');
  });

  group('every copy of the launch ground is the same colour', () {
    final hex = kSplashGround.toARGB32().toRadixString(16).substring(2).toUpperCase();

    test('Android colors.xml splash_ground', () {
      final xml = _read('android/app/src/main/res/values/colors.xml');
      final m = RegExp(r'<color name="splash_ground">#([0-9A-Fa-f]{6})</color>').firstMatch(xml);
      expect(m, isNotNull);
      expect(m!.group(1)!.toUpperCase(), hex);
    });

    test('iOS LaunchScreen.storyboard background', () {
      final sb = _read('ios/Runner/Base.lproj/LaunchScreen.storyboard');
      final m = RegExp(r'<color key="backgroundColor" red="([\d.]+)" green="([\d.]+)" blue="([\d.]+)"')
          .firstMatch(sb);
      expect(m, isNotNull);
      final rgb = [1, 2, 3]
          .map((g) => (double.parse(m!.group(g)!) * 255).round().toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      expect(rgb, hex);
    });

    test('Android 12+ system splash: values-v31 and values-night-v31 are identical and blank', () {
      final day = _read('android/app/src/main/res/values-v31/styles.xml');
      final night = _read('android/app/src/main/res/values-night-v31/styles.xml');
      // The night copy must exist and match: Android ranks the night qualifier above the API
      // level one, so without it a dark-mode phone falls back to values-night/ and shows the
      // launcher icon on the system splash again.
      expect(night, day);
      expect(day, contains('android:windowSplashScreenBackground">@color/splash_ground'));
      expect(day, contains('android:windowSplashScreenAnimatedIcon">@drawable/splash_icon_none'));
    });

    test('every launch window and theme points at splash_ground', () {
      for (final f in [
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-night/launch_background.xml',
        'android/app/src/main/res/values/styles.xml',
        'android/app/src/main/res/values-night/styles.xml',
      ]) {
        expect(_read(f), contains('@color/splash_ground'), reason: f);
      }
    });
  });

  test('pubspec ships the two WebPs and NOT the 3 MB masters beside them', () {
    final pubspec = _read('pubspec.yaml');
    expect(pubspec, contains('- $kSplashAnimationAsset'));
    expect(pubspec, contains('- $kSplashStillAsset'));
    expect(pubspec, isNot(contains(RegExp(r'^\s*- assets/brand/\s*$', multiLine: true))));
    // No asset ENTRY for the masters (a comment explaining why they are left out is fine).
    expect(pubspec,
        isNot(contains(RegExp(r'^\s*- assets/brand/apnivaas_(mark|lockup)\.png', multiLine: true))));
  });
}
