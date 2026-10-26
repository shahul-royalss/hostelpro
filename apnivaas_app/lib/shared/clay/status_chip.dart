library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';

/// What a status means. Each maps to one canonical tone, and the chip resolves it for the theme.
///
/// The mapping the app uses: paid / resolved / occupied → [success]; due / pending / expiring →
/// [warning]; overdue / failed / refused → [error]; refund / new → [info]; draft / sample /
/// inactive → [neutral]. [brand] is for a chip that marks something as Apnivaas's own rather
/// than as a state ("New feature").
enum StatusTone {
  success,
  warning,
  error,
  info,
  neutral,
  brand;

  /// The canonical colour behind this tone — for a dot, a rail, a chart mark.
  Color get canonical => switch (this) {
        StatusTone.success => ApnivaasColors.success,
        StatusTone.warning => ApnivaasColors.warning,
        StatusTone.error => ApnivaasColors.error,
        StatusTone.info => ApnivaasColors.info,
        StatusTone.neutral => ApnivaasColors.textMuted,
        StatusTone.brand => ApnivaasColors.brand,
      };

  /// The tone a legacy canonical colour stands for — so a screen still plumbing
  /// `ApnivaasColors.warning` through a `tone:` can hand it straight to a [StatusChip].
  static StatusTone fromCanonical(Color? tone) {
    if (tone == null) return StatusTone.neutral;
    if (tone == ApnivaasColors.success) return StatusTone.success;
    if (tone == ApnivaasColors.warning) return StatusTone.warning;
    if (tone == ApnivaasColors.error) return StatusTone.error;
    if (tone == ApnivaasColors.info) return StatusTone.info;
    if (tone == ApnivaasColors.brand) return StatusTone.brand;
    return StatusTone.neutral;
  }
}

/// A status, as a pill with a word in it — "Paid", "Due in 3 days", "Overdue".
///
/// The ink is the theme's text value for the tone; the fill is that ink at 10% over whatever
/// the chip sits on. That is the tightest contrast case in the app and it is measured: worst
/// 4.64:1 (the light warning chip), on the ground, the card and the well. Neutral is the
/// design's grey chip — [ApnivaasColors.inkMuted] on [ApnivaasColors.chipNeutral], 4.83:1.
///
/// ALWAYS A WORD. Hue alone is unreadable to the ~8% of men with a red-green deficiency. And a
/// chip never sits on a surface tinted with its own tone — see
/// [ApnivaasSemantics.surfaceTintAlpha] for the measurement that forbids it.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.dot = false,
    this.icon,
  });

  final String label;
  final StatusTone tone;

  /// A 6dp dot in the canonical colour before the word.
  final bool dot;

  /// A 14dp glyph before the word, in the ink. Use either this or [dot].
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final Color ink;
    final Color fill;
    if (tone == StatusTone.neutral) {
      ink = t.colorScheme.onSurfaceVariant;
      fill = t.colorScheme.surfaceContainerHighest;
    } else {
      ink = tones.resolve(tone.canonical);
      fill = tones.chipFill(ink);
    }
    final style = ApnivaasType.manrope(12, 16, FontWeight.w700, ink);

    return Semantics(
      container: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: Space.sm - Space.hair, vertical: 3),
        decoration: BoxDecoration(color: fill, borderRadius: Radii.rPill),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot) ...[
              ExcludeSemantics(
                child: Container(
                  width: Space.tight,
                  height: Space.tight,
                  decoration: BoxDecoration(color: tone.canonical, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: Space.tight),
            ] else if (icon != null) ...[
              Icon(icon, size: IconSize.sm, color: ink),
              const SizedBox(width: Space.xxs),
            ],
            Flexible(
              child: Text(label, style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// A count on cream: white on the error ink, 6.54:1 (inverted in dark). (On forest, the gold marker in
/// [HeaderIconButton] is the one to use — red on forest is a dark blot.)
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.semanticLabel});

  final int count;

  /// What the number counts — "3 overdue". Defaults to the bare number.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel ?? text,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(color: scheme.error, borderRadius: Radii.rPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xxs + 1),
            child: Align(
              child: MediaQuery.withNoTextScaling(
                child: Text(
                  text,
                  style:
                      ApnivaasType.manrope(11, 14, FontWeight.w700, scheme.onError, tabular: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
