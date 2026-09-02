/// The receipt's own constants: thermal paper, printer metal, and the motion of a feed.
///
/// ═══ WHY THESE ARE NOT IN core/theme/tokens.dart ═══
/// Everything in `NivoraColors` answers the question "what colour is this app in the current
/// theme". Nothing below answers that question, because none of it is theme-dependent, and it
/// must not become so:
///
///   1. A RECEIPT IS A PIECE OF PAPER. Paper is off-white and toner is near-black whether the
///      phone is in light mode or dark mode. A receipt that inverted itself at dusk would look
///      like a rendering bug, not like a preference being honoured.
///   2. IT LEAVES THE APP AS A PNG. The exported image is opened in a gallery, forwarded on
///      WhatsApp, and printed. It has to carry its own background and its own contrast into
///      places where this app's theme does not exist.
///
/// So this is a feature-local token file, held to the same rule as the global one: nothing
/// under `features/payments/` may write a raw colour, radius or duration — it comes from here.
///
/// ── MEASURED CONTRAST, ink against [ReceiptPaper.stock] (#FAFAF8) ───────────────────────
///   [ReceiptPaper.ink]      #222222   15.22:1   body, figures, everything that is read
///   [ReceiptPaper.inkSoft]  #5C5C5C    6.40:1   labels and captions. AA at any size.
///   [ReceiptPaper.inkFaint] #8A8A8A    3.30:1   GRAPHICS ONLY. Clears WCAG 1.4.11's 3:1 for
///                                               a non-text object; it is NOT legible enough
///                                               for type, so the barcode's caption uses
///                                               inkSoft and only the bars themselves are
///                                               faint.
library;

import 'package:flutter/widgets.dart';

/// The paper, and what is printed on it.
abstract final class ReceiptPaper {
  /// Thermal stock: warm, very slightly off-white. Pure #FFFFFF reads as a screen, not paper.
  static const stock = Color(0xFFFAFAF8);

  /// Toner. 15.22:1 on [stock].
  static const ink = Color(0xFF222222);

  /// Labels, captions, the barcode number. 6.40:1.
  static const inkSoft = Color(0xFF5C5C5C);

  /// The barcode bars, and nothing else. 3.30:1 — a graphical object, never text.
  static const inkFaint = Color(0xFF8A8A8A);

  /// The dotted rules between sections.
  static const rule = Color(0xFFCFCCC5);

  /// A hair of shading down the left and right edges, so the paper reads as a sheet with a
  /// thickness rather than a rectangle of colour.
  static const edgeShade = Color(0x0F000000);

  /// Printed width. The same 330 logical pixels the supplied animation uses, which is close to
  /// the 80mm of real POS stock at typical phone density.
  static const width = 330.0;

  /// Depth of the cutter's teeth, and how wide one tooth is.
  static const toothDepth = 10.0;
  static const toothWidth = 11.0;

  static const padding = EdgeInsets.symmetric(horizontal: 22, vertical: 24);

  /// The mono stack. NOT a Google font: the receipt is exported as an image and is opened
  /// offline, so it cannot depend on a face that is fetched over the network the first time it
  /// is drawn. Every platform this ships to resolves 'monospace' to a real monospaced face,
  /// which is exactly what a thermal printer would have used.
  static const monoFamily = 'monospace';
  static const monoFallback = <String>['monospace', 'Roboto Mono', 'Courier New', 'Courier'];
}

/// The dispenser the paper comes out of.
///
/// Brushed gold, as supplied: a warm metal against the app's cool indigo, which is what makes
/// the machine read as an object sitting on the screen rather than as another panel of UI.
abstract final class ReceiptPrinter {
  static const hoodWidth = 400.0;
  static const hoodTopHeight = 34.0;
  static const hoodLipHeight = 14.0;

  /// The dark mouth the paper feeds through.
  static const slitWidth = 350.0;
  static const slitHeight = 12.0;

  static const metalDark = Color(0xFF8A5D22);
  static const metalMid = Color(0xFFD8B478);
  static const metalLight = Color(0xFFFFF7EA);
  static const metalShadow = Color(0xFF6B4715);

  /// Inside the slot. Nearly black, so the paper appears to come from somewhere.
  static const slit = Color(0xFF0F0A03);

  /// The specular streak along the top of the hood.
  static const highlight = Color(0xF2FFFFFF);

  /// The cutter blade catching the light as it crosses.
  static const blade = Color(0xFFFFFFFF);

  static const radius = 14.0;
}

/// The motion, matched to the animation the product owner supplied.
///
/// The curve is that file's `cubic-bezier(0.16, 1, 0.3, 1)` — a very fast start that decays to
/// almost nothing, which is what makes a paper feed read as mechanical rather than as a slide
/// transition. It is deliberately NOT `Motion.enter` from the app's tokens: this is a machine,
/// and it should not move like a card.
abstract final class ReceiptMotion {
  /// The feed. 2.5s, as supplied — long, and the point of the whole screen.
  static const feed = Duration(milliseconds: 2500);
  static const feedCurve = Cubic(0.16, 1, 0.3, 1);

  /// How much of the paper is already showing when the feed begins, so the first frame is a
  /// sliver of emerging paper rather than nothing at all.
  static const feedStart = 0.04;

  /// The cutter's flash across the slit, at the end of the feed.
  static const cut = Duration(milliseconds: 350);

  /// The tear: a tug sideways, then free of the machine.
  static const tear = Duration(milliseconds: 550);
  static const tearCurve = Cubic(0.2, 0.8, 0.2, 1);

  /// The paper flexes towards the reader as it emerges and flattens as it settles. Radians.
  static const flex = -0.30;

  /// Perspective for that flex. Small — a receipt is close to the eye.
  static const perspective = 0.0011;

  /// The feed judder, in logical pixels of horizontal travel. Sub-pixel by design: it should
  /// be felt and not seen.
  static const judder = 0.6;
}
