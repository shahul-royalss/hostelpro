import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../core/theme/typography.dart';
import 'brow.dart';
import 'brow_header.dart';

/// The brand on the masthead: the product name set as type ([ApnivaasTypeMark]), and the block
/// that puts it under the greeting ([MastheadBlock]).
///
/// The traced outline that used to live here spelled the product's earlier name. It was removed
/// with that name, together with the path_parsing dependency it needed.

/// THE BRAND, SET AS TYPE — the masthead's second line under the greeting.
///
/// Asked for by the product owner as "simply elegant typographic which represents our logo /
/// brand", and it is the right call for a masthead — a traced path has to be redrawn on every
/// rebuild, where this is a Text.
///
/// ── "Apnivaas", IN TITLE CASE, IN THE DISPLAY FACE ───────────────────────────────────────
///
/// The owner's rule is that the name is written exactly like the logo everywhere — title case,
/// never "APNIVAAS". It is set in Outfit, the face every heading and the auth top bar's
/// wordmark use, at 600: the logo's letters are a firm medium, and a heavier weight at 15 clogs
/// the counters of "a" and "p". The tracking is a hair, enough that the line reads as a
/// signature rather than as a sentence and not so much that "nivaas" falls apart. Both the face
/// and the weight are bundled (core/theme/typography.dart), so nothing downloads.
class ApnivaasTypeMark extends StatelessWidget {
  const ApnivaasTypeMark({
    super.key,
    this.color,
    this.fontSize = 15,
    this.letterSpacing = tracking,
  });

  /// The product name, exactly as the logo writes it.
  static const name = 'Apnivaas';

  /// The resting tracking.
  static const tracking = 0.6;

  /// Null takes the surrounding ink, which is what a masthead on a brow wants.
  final Color? color;
  final double fontSize;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? DefaultTextStyle.of(context).style.color ?? ApnivaasColors.ink;
    return Text(
      name,
      style: ApnivaasType.outfit(fontSize, fontSize, FontWeight.w600, ink,
          letterSpacing: letterSpacing),
      maxLines: 1,
    );
  }
}

/// The masthead block: who you are, and whose app this is.
///
/// One widget rather than two call sites, because the resident's header and every staff header
/// draw the identical thing and a copy of it would drift the moment one was tuned.
class MastheadBlock extends StatelessWidget {
  const MastheadBlock({super.key, required this.name, this.color});

  /// The signed-in person's full name. Only the FIRST word is greeted — "Hello Lakshmi" is a
  /// greeting, "Hello Lakshmi Venkataraman Subramanian" is a database row read aloud, and on a
  /// 320dp phone it is also two lines where one was intended.
  final String name;

  /// Null takes the surrounding ink. Set only where the block sits on a coloured brow.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final first = name.trim().split(RegExp(r'\s+')).firstWhere((w) => w.isNotEmpty,
        orElse: () => '');
    final greeting = first.isEmpty ? 'Hello' : 'Hello $first';

    // ON THE BROW THE INK IS NOT OURS TO PICK. `titleMedium` with a null colour is the theme's
    // ink, and in light that drew the greeting near-black on the header — the same leak every
    // header had. BrowText resolves it inside the header, and the signature takes the header's
    // greeting ink (5.11:1 on the lightest stop).
    if (BrowScope.of(context)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Outfit 18/24 rather than the header title's 22: a greeting over a signature is two
          // lines where a sub-page header has one, and the header must not eat the tab body.
          BrowText.title(
            greeting,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, height: 24 / 18),
          ),
          const SizedBox(height: Space.xxs / 2),
          const ApnivaasTypeMark(color: BrowInk.eyebrow),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          greeting,
          style: t.textTheme.titleMedium?.copyWith(color: color, height: 1.1),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Space.xxs / 2),
        // 76% of the ink: the brand is a signature under the greeting, not a competing headline.
        ApnivaasTypeMark(
          color: (color ?? t.colorScheme.onSurface).withValues(alpha: 0.76),
        ),
      ],
    );
  }
}
