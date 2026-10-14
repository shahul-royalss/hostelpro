/// The four pieces of artwork that stand in for a glyph on a first-run empty state.
library;

/// Asset paths for the empty-state illustrations, so no screen carries a raw string.
///
/// ── WHAT THESE ARE ────────────────────────────────────────────────────────────────────────
///
/// Four wordless drawings for the four screens a NEW PG owner opens before any data exists:
/// no residents, no complaints, no notices, no payments. Those screens used to show a 32dp
/// glyph inside a 56dp outlined square, which is correct for "this filter matched nothing" and
/// far too quiet for the very first thing a paying customer sees.
///
/// ── WHY THEY ARE NOT SVG ──────────────────────────────────────────────────────────────────
///
/// `flutter_svg` is already a dependency, so SVG was the obvious choice and was not taken:
/// these came out of an image generator as raster art, and hand-tracing them to vector would
/// be inventing geometry rather than shipping what was approved. They are 480px PNGs — the
/// exact pixel size of a 160dp box on a 3x phone — and total 87KB for all four, which is
/// roughly a tenth of one of the five bundled Inter faces.
///
/// ── WHAT IS TRUE OF EVERY FILE HERE, AND MUST STAY TRUE ───────────────────────────────────
///
///  * **No text inside the image.** Not a word, not a numeral. The title and the support line
///    under the artwork are real `Text` in Inter, so they stay translatable, selectable and
///    readable by a screen reader. Artwork with baked-in English would break all three.
///  * **Transparent background.** The art is keyed off its near-black ground, so the raised
///    card `#171a1e` shows through it. An opaque `#0b0d0f` tile would paint a visibly darker
///    square inside the card it sits in.
///  * **Two inks only, and they are the design's own.** Every non-transparent pixel is exactly
///    the design's gold `#c9a96e` or its cream `#f5f3ee`; the assets were snapped to those two
///    values rather than trusted to arrive at them.
///  * **Dark-only, like the rest of the app.** These read on `#0b0d0f`. If a light path is
///    ever reintroduced — it should not be — this artwork does not come with it.
///
/// Every name is what the state IS, not what the picture SHOWS, so replacing the drawing later
/// does not mean renaming a constant at six call sites.
abstract final class EmptyArt {
  static const _dir = 'assets/illustrations';

  /// The warden's resident list before anybody has been registered. An empty bunk bed.
  static const residents = '$_dir/no_residents.png';

  /// A resident's complaint history before they have raised one. A speech bubble and a spanner.
  static const complaints = '$_dir/no_complaints.png';

  /// A noticeboard with nothing pinned to it yet.
  static const notices = '$_dir/no_notices.png';

  /// The rent ledger before a single payment has been recorded. An open, blank ledger book.
  static const payments = '$_dir/no_payments.png';
}
