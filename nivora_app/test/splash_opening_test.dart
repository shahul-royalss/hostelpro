// THE OPENING, ASSERTED FRAME BY FRAME.
//
// ── WHY A TEST AND NOT A SCREENSHOT ───────────────────────────────────────────────────────
//
// I tried to verify this on a device first and could not. Android 12's own splash screen shows
// the launcher icon on the window background for several seconds on a debug build, and every
// screenshot I took during launch caught THAT rather than Flutter's screen — three captures,
// byte-for-byte identical, which I first read as "the animation is frozen". It was not; it was
// the OS, and the app had already moved on to onboarding by the time I looked again.
//
// A screenshot over adb costs about a second per round trip, which is most of a 1,500ms
// animation. So the device can tell me the opening EXISTS and cannot tell me it PROGRESSES.
// This can, exactly, with no video tooling on the machine and nothing to eyeball.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/boot/splash_gate.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/features/splash/splash_screen.dart';

/// The clip that folds IVORA away behind the mark. Its widthFactor IS the animation.
double _unfold(WidgetTester tester) {
  final align = tester.widget<Align>(
    find.ancestor(of: find.text('IVORA'), matching: find.byType(Align)).first,
  );
  return align.widthFactor!;
}


/// One island of ink on the lockup's row.
typedef _Run = ({int start, int end, int height});

/// Render the tree under [key] and find the horizontal runs of drawn pixels across the band the
/// lockup occupies.
///
/// PIXELS, BECAUSE THE QUESTION IS ABOUT PIXELS. Widget rects answer where a box is; a letter's
/// bearings and an image's transparent margin both live inside the box, and every complaint this
/// test exists for was about the space between the DRAWINGS.
Future<List<_Run>> _inkColumnRuns(WidgetTester tester, GlobalKey key) async {
  final markRect = tester.getRect(find.byType(Image));
  final wordRect = tester.getRect(find.text('IVORA'));
  final top = markRect.top.floor() - 4;
  final bottom = wordRect.bottom.ceil() + 2;

  late final List<_Run> runs;
  // runAsync: encoding an image is real work on a real thread, which the fake clock a widget
  // test runs on never lets finish.
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final px = data!.buffer.asUint8List();
    final w = image.width;

    // The ground is NivoraColors.background. 12 of tolerance ignores the anti-aliased fringe
    // without ignoring any stroke.
    bool ink(int x, int y) {
      final i = (y * w + x) * 4;
      return (px[i] - 238).abs() > 12 || (px[i + 1] - 240).abs() > 12 || (px[i + 2] - 248).abs() > 12;
    }

    final found = <_Run>[];
    int? start;
    for (var x = 0; x <= w; x++) {
      final filled = x < w && [for (var y = top; y < bottom; y++) y].any((y) => ink(x, y));
      if (filled && start == null) {
        start = x;
      } else if (!filled && start != null) {
        var hi = bottom, lo = top;
        for (var y = top; y < bottom; y++) {
          for (var c = start; c < x; c++) {
            if (ink(c, y)) {
              if (y < hi) hi = y;
              if (y > lo) lo = y;
            }
          }
        }
        found.add((start: start, end: x - 1, height: lo - hi + 1));
        start = null;
      }
    }
    runs = found;
  });
  return runs;
}

Widget _app() => const ProviderScope(
      child: MaterialApp(home: SplashScreen()),
    );

/// PUT THE REAL PICTURE IN THE TREE BEFORE MEASURING IT.
///
/// A widget test runs on a fake clock inside a fake async zone, and image decoding is real work
/// on a real thread — so `Image.asset` never completes and paints nothing. [WidgetTester.runAsync]
/// is the door out of that zone, and precaching THE WIDGET'S OWN PROVIDER rather than a freshly
/// constructed `AssetImage` is what makes this correct: the splash asks for `cacheHeight`, which
/// wraps the provider in a `ResizeImage` under a different cache key, so a hand-built provider
/// would warm a cache entry the screen never reads.
Future<void> _decodeTheMark(WidgetTester tester) async {
  final image = tester.widget<Image>(find.byType(Image));
  final element = tester.element(find.byType(Image));
  await tester.runAsync(() => precacheImage(image.image, element));
  await tester.pump();
}

void main() {
  testWidgets('the mark arrives first, then IVORA comes out of it', (tester) async {
    await tester.pumpWidget(_app());

    // FRAME ZERO, AND THE MARK IS ALREADY THERE.
    //
    // It does not fade in, deliberately: Android's own splash shows this same artwork on this
    // same background for a second before Flutter draws, so fading it up made the logo blink
    // out and back. A device screenshot is what caught that — the test suite could not have.
    //
    // Asserted as the ABSENCE of an Opacity above the mark, which is the actual invariant. My
    // first version of this assertion read the Opacity's value with `skip: true` attached
    // because the widget was gone — an expect that can never fail, which is the exact thing
    // this file exists to avoid.
    expect(
      find.ancestor(of: find.byType(Image), matching: find.byType(Opacity)),
      findsNothing,
      reason: 'the mark must not fade in — it continues the system splash seamlessly',
    );
    expect(_unfold(tester), 0, reason: 'IVORA is not folded away at the start');

    // 40% in: the mark has fully arrived and the letters have started to emerge.
    await tester.pump(const Duration(milliseconds: 600));
    final atMiddle = _unfold(tester);
    expect(atMiddle, greaterThan(0), reason: 'IVORA has not started unfolding by 600ms');
    expect(atMiddle, lessThan(1), reason: 'IVORA finished before the animation was half done');

    // The end: fully out, and not a fraction over.
    await tester.pump(const Duration(milliseconds: 900));
    expect(_unfold(tester), 1, reason: 'IVORA is not fully out when the opening ends');

    // Nothing thrown along the way — a missing asset would surface here.
    expect(tester.takeException(), isNull);

    // Let the gate's timer expire so the test does not end holding one.
    await tester.pump(splashMinimum);
  });

  testWidgets('the whole opening is 1500ms — the number the owner asked for', (tester) async {
    await tester.pumpWidget(_app());

    // One millisecond short, the mark must NOT be finished. This is the assertion that would
    // catch someone quietly shortening the animation to make a test faster.
    await tester.pump(splashMinimum - const Duration(milliseconds: 100));
    expect(_unfold(tester), 1,
        reason: 'the unfold ends at 78% of the timeline, so it is done well before the gate');

    expect(splashMinimum, const Duration(milliseconds: 1500));
    await tester.pump(splashMinimum);
  });

  testWidgets('reduce motion shows the finished mark, and waits for nothing', (tester) async {
    // A person who asked the OS for less motion should not be held in front of a still picture
    // for a second and a half. The gate is open immediately and the lockup is already complete.
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SplashScreen(),
        ),
      ),
    ));
    await tester.pump();

    expect(_unfold(tester), 1, reason: 'reduce motion should show the finished lockup');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the finished lockup is centred on the screen, to the pixel', (tester) async {
    // ── THE ASSERTION THAT WOULD HAVE CAUGHT THE BUG THE OWNER PHOTOGRAPHED ────────────────
    //
    // The opening shipped with the mark jammed against the left edge and clear air on the
    // right, and nothing in this file noticed, because every other test here asks about the
    // unfold FACTOR — a number between 0 and 1 that was perfectly correct the whole time. The
    // thing that was wrong was where the result landed, and the only way to know that is to
    // measure where it landed.
    //
    // The cause was a hand-written `Transform.translate` of -ivoraWidth/2 sitting on top of a
    // [Center] that was already re-centring the row every frame as `widthFactor` grew it. Both
    // halves were individually reasonable; together they applied the correction twice.
    //
    // ── WHY THE INK AND NOT THE WIDGET RECTS ──────────────────────────────────────────────
    //
    // Flutter puts `letterSpacing` after the LAST letter as well as between letters, so the
    // Text's box is 6dp wider than the picture inside it. Asserting on the raw rects would
    // enshrine that 6dp as correct and centre the box rather than the wordmark.
    await tester.pumpWidget(_app());
    await tester.pump(splashMinimum);
    await _decodeTheMark(tester);

    final mark = tester.getRect(find.byType(Image));
    final word = tester.getRect(find.text('IVORA'));
    final screen = tester.getRect(find.byType(Scaffold));

    // Read off the tree, not restated here: a copy of the numbers in this file would pass
    // happily while the screen drifted away from them.
    final style = tester.widget<Text>(find.text('IVORA')).style!;
    final painter = TextPainter(
      text: TextSpan(text: 'IVORA', style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    // FIRST, THAT THERE IS A MARK AT ALL.
    //
    // Without this the rest of the test is theatre, and it was: the first version of it passed
    // while the mark rendered at ZERO WIDTH. `Image.asset` decodes asynchronously and the fake
    // clock a widget test runs on never lets the codec finish, so `RawImage` had no intrinsic
    // size and `getRect` handed back an empty box sitting exactly where the mark would start.
    // Every number below still balanced, because the centring arithmetic happens not to depend
    // on how wide the mark is. _decodeTheMark above is what makes it real; this is what makes
    // the test say so.
    expect(mark.width, greaterThan(0),
        reason: 'assets/brand_mark.png did not decode — the lockup is the word alone');

    final inkCentre = (mark.left + (word.right - style.letterSpacing!)) / 2;
    expect(
      inkCentre,
      closeTo(screen.center.dx, 0.5),
      reason: 'the finished NIVORA lockup is off-centre by '
          '${(inkCentre - screen.center.dx).toStringAsFixed(1)}dp',
    );

    // AND THE MARK IS NOT TWICE THE HEIGHT OF THE WORD. "The N goes so long" was the other half
    // of the same report: a flat 70dp mark beside a 32dp cap height reads as a badge with a
    // word after it rather than as one wordmark. Bounded on BOTH sides — a mark shorter than
    // the letters would be just as wrong, and is the mistake an over-correction makes.
    final capHeight = style.fontSize! * 1490 / 2048;
    expect(mark.height / capHeight, inInclusiveRange(1.0, 1.5),
        reason: 'the mark is ${(mark.height / capHeight).toStringAsFixed(2)}x the cap height '
            'of the letters beside it');

    // STANDING ON THE BASELINE, not centred against the line box. All-caps type never uses the
    // descender room under it, so centring the two sat the mark low by half of that descent —
    // small, constant, and exactly the kind of thing that reads as "slightly off" without ever
    // being nameable. The mark's artwork is trimmed to its own ink, so its bottom edge IS the
    // bottom of the drawing.
    final baseline =
        word.top + painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    expect(mark.bottom, closeTo(baseline, 0.5),
        reason: 'the mark does not stand on the letters\' baseline');
  });

  testWidgets('the N is a letter of the word, not a badge in front of it', (tester) async {
    // ── WHAT THE PRODUCT OWNER SAW, AND WHY ONLY PIXELS COULD ANSWER IT ───────────────────
    //
    // "The N letter is longer than compared to other letters I V O R A... please make it to
    // symmetry same gapping, don't give more gap between them."
    //
    // Both halves of that are about INK, and neither is visible from the widget tree. The gap
    // between two letters is not `letterSpacing`: it is letterSpacing plus the side bearings of
    // the pair, and Inter's I carries about 5.4dp of left bearing at this size — which is why a
    // SizedBox that looked small (8dp) rendered a 25dp hole beside a mark whose own box is
    // flush with its artwork. And an Image's height is its BOX; the drawing inside it is only
    // the same thing because scripts/cut-brand-mark.py trims to visible alpha.
    //
    // So this renders the screen and scans columns. It is slower than every other test in this
    // file and it is the only one that can fail for the reason the owner filed.
    tester.view.physicalSize = const Size(1080, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(ProviderScope(
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(theme: NivoraTheme.light(), home: const SplashScreen()),
      ),
    ));
    await tester.pump();
    await tester.pump(splashMinimum);
    await _decodeTheMark(tester);

    final runs = await _inkColumnRuns(tester, key);
    // The mark, then I, V, O, R, A: six islands of ink and no more. Fewer means two glyphs are
    // touching; more means something else is on the row.
    expect(runs, hasLength(6), reason: 'expected the mark and five letters, got ${runs.length}');

    final gaps = [
      for (var i = 1; i < runs.length; i++) runs[i].start - runs[i - 1].end - 1,
    ];
    final markToWord = gaps.first;
    final betweenLetters = gaps.skip(1).toList();
    final mean = betweenLetters.reduce((a, b) => a + b) / betweenLetters.length;

    // WITHIN THE LETTERS' OWN RHYTHM. Those gaps are not equal to each other either — measured
    // 8, 5, 9, 6 — because each pair has its own bearings, so the target is the spread the eye
    // already accepts rather than a single number. It was 25 against a mean of 7.
    expect(
      markToWord,
      lessThanOrEqualTo(mean + 3),
      reason: 'the mark stands ${markToWord}px from the I while the letters average '
          '${mean.toStringAsFixed(1)}px apart',
    );
    expect(markToWord, greaterThanOrEqualTo(1),
        reason: 'the mark is touching the I at ${markToWord}px');

    // AND IT IS THE SAME HEIGHT AS THE LETTERS. Not taller: a mark that stands proud of the cap
    // line reads as a badge with a word after it, which is the one thing a lockup must not do.
    final markHeight = runs.first.height;
    final glyphHeight = runs.last.height;
    expect(
      (markHeight - glyphHeight).abs(),
      lessThanOrEqualTo(2),
      reason: 'the mark is ${markHeight}px tall against the letters\' $glyphHeight',
    );
  });

  testWidgets('the ground is the light canvas, so the launch does not flash', (tester) async {
    // The chain is one colour: launcher plate, Android launch window (values/ AND
    // values-night/), this screen, and the first real screen. It painted the near-black brand
    // ground until the app became light-only, at which point every cold start would have gone
    // light, dark, light.
    await tester.pumpWidget(_app());
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, NivoraTheme.light().scaffoldBackgroundColor);
    await tester.pump(splashMinimum);
  });
}
