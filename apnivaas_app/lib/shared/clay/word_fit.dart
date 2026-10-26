library;

import 'package:flutter/widgets.dart';

/// Measuring words, for the kit pieces that must never break one in the middle.
///
/// Flutter wraps between words, but a single word wider than its line is split wherever the
/// line ends: "Collections" in a header beside two buttons at 2.0x came out as "Collection" over
/// "s", and a quick-action label as "Monthl y". Each piece that can meet a long word at large
/// text decides what to do about it from these two measurements — a grid drops a column, a
/// title or a tile's caption is set a little smaller — rather than letting the word break.
abstract final class WordFit {
  /// The widest single word in [texts], set in [style] at this context's text scale.
  static double widestWord(BuildContext context, Iterable<String> texts, TextStyle? style) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var widest = 0.0;
    for (final text in texts) {
      for (final word in text.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        painter
          ..text = TextSpan(text: word, style: style)
          ..layout();
        if (painter.width > widest) widest = painter.width;
      }
    }
    painter.dispose();
    return widest;
  }

  /// The text scale that keeps the longest word of [text] on one line of [width]: the reader's
  /// own scale whenever it fits, a little less when one word would otherwise break in the
  /// middle. A null [width] — a line whose width is not known — keeps the reader's scale.
  static TextScaler scalerFor(BuildContext context, String text, TextStyle? style, double? width) {
    final scaler = MediaQuery.textScalerOf(context);
    if (width == null || width <= 0) return scaler;
    final widest = widestWord(context, [text], style);
    if (widest <= width) return scaler;
    final size = style?.fontSize ?? 14;
    // A hair under the exact ratio, so rounding in the glyph advances cannot tip the word over.
    return TextScaler.linear(scaler.scale(size) / size * width / widest * 0.98);
  }
}
