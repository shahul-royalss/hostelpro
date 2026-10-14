import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
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
/// ── "Apnivaas", IN TITLE CASE, BECAUSE THAT IS HOW THE LOGO WRITES IT ────────────────────
///
/// The mark this replaced was set in capitals at a wide 4.0 tracking, and that tracking was
/// what made a row of capitals read as a logotype. The logo sets its name in title case with
/// ordinary geometric-sans spacing, and the owner's rule is that the name is written exactly
/// like the logo everywhere — never
/// "APNIVAAS". Lower-case letters spread four points apart stop reading as a word at all, so the
/// tracking comes down to a hair: enough that the line still reads as a signature rather than
/// as a sentence, not so much that "nivaas" falls apart. Bold (700) rather than the old 800:
/// the logo's letters are a firm medium, and 800 at 15 in lower case clogs the counters of
/// "a" and "p". Both weights are bundled (core/theme/typography.dart), so nothing downloads.
///
/// The type mark is narrower than the capitals it replaced (eight mostly lower-case letters at 0.6 against
/// six capitals at 4.0), so no masthead that fitted before can overflow now.
class ApnivaasTypeMark extends StatelessWidget {
  const ApnivaasTypeMark({
    super.key,
    this.color,
    this.fontSize = 15,
    this.letterSpacing = tracking,
  });

  /// The product name, exactly as the logo writes it.
  static const name = 'Apnivaas';

  /// The resting tracking. The masthead's entrance adds [BrowEntrance.eyebrowSpread] to this
  /// and lets it settle back, which is what the eyebrow above it does too.
  static const tracking = 0.6;

  /// Null takes the surrounding ink, which is what a masthead on a brow wants.
  final Color? color;
  final double fontSize;

  /// [tracking], except while the brow's entrance is still settling it.
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Text(
      name,
      style: (t.textTheme.labelLarge ?? const TextStyle()).copyWith(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSpacing,
        height: 1,
      ),
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
    // ink, and in light that drew the greeting near-black on the brand violet — the same leak
    // every header had. BrowText resolves it inside the header, and the signature takes the
    // eyebrow's champagne and settles its tracking with the rest of the entrance.
    if (BrowScope.of(context)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BrowText.title(
            greeting,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.1),
          ),
          const SizedBox(height: Space.xxs / 2),
          BrowReveal(
            line: BrowLine.eyebrow,
            builder: (context, spread) => ApnivaasTypeMark(
              color: BrowInk.eyebrow,
              letterSpacing: ApnivaasTypeMark.tracking + spread,
            ),
          ),
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
