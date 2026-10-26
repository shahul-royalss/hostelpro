import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// What is left of the dashboard vocabulary the role home screens were first built from.
///
/// The product owner supplied a reference screenshot (the CampX student app) and asked for its
/// shape: a greeting, a labelled band of tiles carrying the numbers you opened the app for, and
/// a quieter row of tools underneath. Every home is now built from the clay kit instead —
/// StatTile and StatCarousel for the figures, QuickActionGrid for the tools, SectionHeader for
/// the bands (shared/clay/) — and the greeting card, tiles and tool grid that lived here went
/// with their last caller. The band label stays for the super admin's screens, which have not
/// moved over yet.

/// The band label above a group — "ESSENTIALS", "TOOLS".
///
/// Caps, tracked, and quiet: a signpost between bands, not a heading competing with the tiles
/// under it. The new look's headings are sentence case (the clay kit's SectionHeader); this
/// keeps its capitals because the screens still on it, and their tests, read it that way.
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
