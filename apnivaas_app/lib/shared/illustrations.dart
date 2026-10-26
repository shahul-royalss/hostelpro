/// The four first-run empty states, by name — and what is drawn for each.
library;

import 'clay/clay_icons.dart';

/// The four first-run empty states, so no screen carries a raw string.
///
/// ── WHAT THESE ARE ────────────────────────────────────────────────────────────────────────
///
/// The four screens a NEW PG owner opens before any data exists: no residents, no complaints,
/// no notices, no payments. Those screens used to show a 32dp glyph inside a 56dp outlined
/// square, which is correct for "this filter matched nothing" and far too quiet for the very
/// first thing a paying customer sees.
///
/// ── WHAT IS DRAWN FOR THEM NOW ────────────────────────────────────────────────────────────
///
/// Each constant names a STATE, and [clayFor] maps it to the clay icon drawn for it — the
/// same art the rest of the app uses for that kind of thing, at 96dp on a Mist disc (see
/// `StateBody` in glass/glass.dart and the clay kit's `EmptyState`). Every call site passes
/// the constant and never the picture, which is why the art could change without touching
/// one of them.
///
/// The PNGs the paths point at are the previous drawings: wordless two-ink line art in the old
/// dark design's gold #c9a96e and cream #f5f3ee. On the cream ground their cream strokes
/// vanish, so nothing draws them any more. They are kept in the bundle only because the paths
/// are the constants' identity and `test/illustration_assets_test.dart` holds them to it; they
/// can go, with that test's bundle check, once every screen has moved to the clay EmptyState.
///
/// THE ART NEVER CARRIES WORDS. The title and the support line stay real `Text`, so they stay
/// translatable, selectable and readable by a screen reader.
abstract final class EmptyArt {
  static const _dir = 'assets/illustrations';

  /// The resident list before anybody has been registered.
  static const residents = '$_dir/no_residents.png';

  /// A resident's complaint history before they have raised one.
  static const complaints = '$_dir/no_complaints.png';

  /// A noticeboard with nothing pinned to it yet.
  static const notices = '$_dir/no_notices.png';

  /// The rent ledger before a single payment has been recorded.
  static const payments = '$_dir/no_payments.png';

  /// The clay icon drawn for [state]. Anything unrecognised gets the welcoming default.
  static String clayFor(String state) => switch (state) {
        residents => ClayIcons.addTenant,
        complaints => ClayIcons.complaint,
        notices => ClayIcons.announcement,
        payments => ClayIcons.collectPayment,
        _ => ClayIcons.success,
      };
}
