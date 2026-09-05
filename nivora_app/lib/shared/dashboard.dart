import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'glass/glass.dart';

/// The dashboard vocabulary every role's home screen is built from.
///
/// ── WHAT THIS IS COPYING, AND WHAT IT IS NOT ──────────────────────────────────────────────
///
/// The product owner supplied a reference screenshot (the CampX student app) and asked for the
/// same shape: a greeting that names you and the day, a caps-labelled band of coloured tiles
/// carrying the numbers you opened the app for, and a quieter row of tools underneath. That
/// STRUCTURE is what is reproduced here, because it is the part that was actually being asked
/// for — a home screen that leads with figures instead of a stack of undifferentiated cards.
///
/// The reference's PALETTE is not reproduced, and that is deliberate rather than a shortcut.
/// CampX is a light interface with pastel tiles — mint, rose, lilac — on white. NIVORA is
/// dark-first on #0b0d0f, its colours are fixed by [NivoraDomain], and theme_contrast_test.dart
/// enforces WCAG 1.4.3 and 1.4.11 against those grounds on every build. Pouring pastels onto a
/// near-black ground would fail that suite immediately, and the right response to "make it
/// colourful like this" in a dark app is to use the colours the app already owns rather than to
/// weaken the contrast rules protecting them. Every tile below is tinted by its domain, so a
/// money tile is the money colour on every screen it appears on, in every role.
///
/// ── ONE VOCABULARY, FIVE DASHBOARDS ───────────────────────────────────────────────────────
///
/// These widgets live in shared/ rather than in features/student/ because the same request
/// covers the super admin, owner, manager, warden and resident. Five hand-rolled copies of a
/// tile is exactly how the interface got uneven enough to be called messy in the first place.

/// The band label above a group — "ESSENTIALS", "TOOLS".
///
/// Caps, tracked, and quiet: it is a signpost between bands, not a heading competing with the
/// tiles under it. Deliberately not [SectionHeading], which carries a glyph and a caption and
/// belongs above a list of real content.
class DashboardBand extends StatelessWidget {
  const DashboardBand({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Text(
        label.toUpperCase(),
        style: t.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: t.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The card at the top: who you are, what day it is, and one thing worth saying today.
///
/// The reference puts the weather here. NIVORA has no weather and inventing a reason to ask for
/// a location permission would be a poor trade for a decoration — so [trailing] carries whatever
/// that role actually cares about at a glance, and nothing when there is nothing.
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({
    super.key,
    required this.name,
    required this.subtitle,
    this.trailing,
    this.actionLabel,
    this.onAction,
  });

  /// Shown as "Hi <name}," — first name only is the caller's choice, not this widget's.
  final String name;

  /// The line under the greeting: the day, the hostel, whatever situates the reader.
  final String subtitle;

  /// A figure or chip at the trailing edge. Null draws nothing and the greeting takes the width.
  final Widget? trailing;

  /// The row beneath the divider. Both must be set for it to appear.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hasAction = actionLabel != null && onAction != null;

    // GlassCard, not the student screens' OutlineCard: this file is shared by five roles and a
    // shared widget reaching into features/student/ would invert the dependency.
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hi $name,',
                        style: t.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Space.xxs),
                      Text(subtitle, style: t.textTheme.bodyMedium),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: Space.sm),
                  trailing!,
                ],
              ],
            ),
          ),
          if (hasAction) ...[
            Divider(height: 1, color: t.colorScheme.outlineVariant),
            InkWell(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(actionLabel!, style: t.textTheme.titleSmall),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: IconSize.md,
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One tile in the essentials band: a domain-tinted card carrying at most one number.
///
/// AT MOST ONE NUMBER is the rule that keeps the band readable. The reference tiles show a single
/// figure with a label above it and a timestamp under it, and the moment a tile carries two
/// figures the eye has to work out which one it is for. A tile with no [value] is the small
/// variant — an icon and a destination, nothing more.
class EssentialTile extends StatelessWidget {
  const EssentialTile({
    super.key,
    required this.domain,
    required this.icon,
    required this.title,
    this.label,
    this.value,
    this.footnote,
    this.onTap,
    this.flagged = false,
  });

  final NivoraDomain domain;
  final IconData icon;
  final String title;

  /// The word above the figure — "Dues", "Occupied", "Open". Ignored without a [value].
  final String? label;

  /// The figure itself, already formatted. Null makes this the compact variant.
  final String? value;

  /// The line under the figure, usually a date. Ignored without a [value].
  final String? footnote;

  final VoidCallback? onTap;

  /// Draws the reference's small dot in the corner: something here wants attention. Used for an
  /// overdue payment or an unread count, never as decoration — a dot that is always on is a dot
  /// nobody looks at.
  final bool flagged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = context.tones.resolve(domain.tone);

    return DomainCard(
      domain: domain,
      onTap: onTap,
      padding: const EdgeInsets.all(Space.sm),
      // The whole tile is one target and one announcement. Without this a screen reader reads
      // "Fees", "Dues", "1,02,860", "As on 18 Aug" as four unrelated strings.
      semanticLabel: [
        title,
        if (label != null && value != null) '$label $value',
        if (footnote != null && value != null) footnote,
      ].whereType<String>().join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DomainIcon(domain: domain, icon: icon, size: DomainIconSize.sm),
              const Spacer(),
              if (flagged)
                Container(
                  width: Space.xs,
                  height: Space.xs,
                  decoration: BoxDecoration(
                    color: t.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            title,
            style: t.textTheme.titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (value != null) ...[
            const SizedBox(height: Space.xs),
            Divider(height: 1, color: t.colorScheme.outlineVariant),
            const SizedBox(height: Space.xs),
            if (label != null)
              Text(label!, style: t.textTheme.labelSmall),
            const SizedBox(height: Space.xxs),
            Text(
              value!,
              style: t.textTheme.titleMedium?.copyWith(color: tone),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (footnote != null) ...[
              const SizedBox(height: Space.xxs),
              Text(
                footnote!,
                style: t.textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The essentials band: tiles two to a row, each row as tall as its taller tile.
///
/// A GridView would need a childAspectRatio, and one ratio cannot fit both a tile carrying a
/// figure and a tile carrying only a label — at a large text scale the tall one clips and the
/// short one floats in space. Rows of [IntrinsicHeight] instead: each pair is exactly as tall as
/// it needs to be, and a resident who has turned their text up gets a taller tile rather than a
/// truncated one.
class EssentialsGrid extends StatelessWidget {
  const EssentialsGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final left = tiles[i];
      final right = i + 1 < tiles.length ? tiles[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: Space.xs),
              // An odd tile keeps its half rather than stretching across the width: a lone
              // full-bleed tile reads as a different kind of object from the ones above it.
              Expanded(child: right ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
      if (i + 2 < tiles.length) rows.add(const SizedBox(height: Space.xs));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// A tool: a destination with no number attached.
///
/// Untinted on purpose. The essentials band is where the colour is, and if the tools were
/// coloured too there would be no band — just a screen of coloured boxes, which is the
/// "messy" this rework exists to answer.
class ToolTile extends StatelessWidget {
  const ToolTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The glyph may carry its domain's colour even though the card does not — it is a small
  /// enough area to stay quiet, and it keeps a tool recognisable as belonging somewhere.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: Space.md, horizontal: Space.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: IconSize.lg,
            color: tone == null ? t.colorScheme.onSurfaceVariant : context.tones.resolve(tone!),
          ),
          const SizedBox(height: Space.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            style: t.textTheme.labelLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The tools band, laid out on the same two-up grid as the essentials so the columns line up.
class ToolsGrid extends StatelessWidget {
  const ToolsGrid({super.key, required this.tools});

  final List<Widget> tools;

  @override
  Widget build(BuildContext context) => EssentialsGrid(tiles: tools);
}
