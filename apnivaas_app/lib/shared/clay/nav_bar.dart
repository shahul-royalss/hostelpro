library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import 'clay_icons.dart';
import 'status_chip.dart';

/// One tab of a [ClayNavBar]: a clay icon, a word, and anything waiting there.
@immutable
class ClayNavDestination {
  const ClayNavDestination({
    required this.icon,
    required this.label,
    this.offIcon,
    this.badgeCount,
    this.hasBadge = false,
    this.badgeLabel,
  });

  /// The tab's [ClayIcons] path, drawn in full colour while the tab is selected.
  final String icon;

  /// The unselected art. Null takes [ClayIcons.navPairs]' off-render when the icon has one, and
  /// otherwise draws [icon] through [ClayIcon.greyscaleFilter] — the two read as one set.
  final String? offIcon;

  /// One word, sentence case — "Home", "Payments".
  final String label;

  /// A count waiting behind the tab: the error badge, which is the one that reads on the card
  /// the bar is made of (the gold dot belongs to forest). Zero or null draws nothing.
  final int? badgeCount;

  /// Something is waiting but there is no number to show: a small error dot.
  final bool hasBadge;

  /// What the badge means, read after the tab — "3 due". Defaults to the bare count, or
  /// "new" for a dot.
  final String? badgeLabel;

  /// The art for the unselected state.
  String get resolvedOffIcon => offIcon ?? ClayIcons.navPairs[icon] ?? icon;

  /// True when the unselected art is the selected file drawn grey, rather than its own render.
  bool get greysOut => offIcon == null && !ClayIcons.navPairs.containsKey(icon);
}

/// THE BOTTOM TAB BAR — a clay icon per tab on the card the bar is made of.
///
/// Built because Material's NavigationBar cannot draw the design: its indicator is a fixed 64x32
/// pill, and the tab art is a 36dp clay icon in a 58x40 Mist pill. The API is NavigationBar's
/// on purpose — [selectedIndex], [onDestinationSelected], [destinations] — so a shell swaps one
/// for the other without restructuring.
///
/// ── WHAT EACH STATE LOOKS LIKE ───────────────────────────────────────────────────────────
///
/// Selected: the full-colour icon at 36dp, lifted 2dp, on a Mist pill; the label Manrope 12/16
/// w700 in forest (9.36:1 on the card). Unselected: the off-art (or the icon drawn grey) at 34dp
/// and 85%, and the label w600 in the muted ink (6.06:1) — the canvas's #6B7A73 measured 4.44:1
/// and is not used. Dark: the Mist pill is the dark Mist, selected ink the dark primary (6.43:1
/// on it, 8.56:1 on the bar).
///
/// ── MOTION ───────────────────────────────────────────────────────────────────────────────
///
/// On selection the pill grows from 80% with [Motion.emphasis] over [Motion.base], the icon
/// lifts and grows over [Motion.fast], and the two arts cross-fade over [Motion.fast], with a
/// selection click. Implicit animations only: nothing here owns a controller, so nothing ticks
/// once a change has landed. Under reduce motion every duration is zero.
///
/// ── SIZE ─────────────────────────────────────────────────────────────────────────────────
///
/// No fixed height: 72dp at 1.0x text plus the bottom safe inset, growing with the label up to
/// the 1.3x the label is clamped to inside the bar (77dp) — taller at 1.4x than at 1.0x, and
/// under the 88dp cap, which is what `test/responsive_test.dart` holds every shell's bar to. The
/// label scales down to fit its cell rather than clipping; the full words are always in the
/// semantics. At 360dp five tabs get 72dp each, which holds the 58dp pill.
class ClayNavBar extends StatelessWidget {
  const ClayNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  }) : assert(destinations.length >= 2, 'a tab bar needs at least two tabs');

  final List<ClayNavDestination> destinations;
  final int selectedIndex;

  /// Called with the tapped index — including the selected one, as NavigationBar does, so a
  /// shell can scroll that tab back to its top.
  final ValueChanged<int>? onDestinationSelected;

  /// The selected tab's pill.
  static const indicatorWidth = 58.0;
  static const indicatorHeight = 40.0;

  /// The largest text scale the labels take inside the bar.
  static const labelScaleCap = 1.3;

  /// The bar's own vertical padding around the pill and the label.
  static const topInset = Space.tight;
  static const bottomInset = Space.xs;
  static const labelGap = Space.hair;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final selected = selectedIndex.clamp(0, destinations.length - 1);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: dark ? t.colorScheme.outlineVariant : ApnivaasColors.track,
            width: Strokes.hairline,
          ),
        ),
        // Casts upward in light; on the dark ground a tinted shadow is invisible and the edge
        // does the separating.
        boxShadow: dark ? null : Shadows.bar,
      ),
      child: SafeArea(
        top: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: labelScaleCap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _ClayNavItem(
                    destination: destinations[i],
                    selected: i == selected,
                    position: i + 1,
                    count: destinations.length,
                    onTap: onDestinationSelected == null
                        ? null
                        : () {
                            if (i != selected) HapticFeedback.selectionClick();
                            onDestinationSelected!(i);
                          },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClayNavItem extends StatelessWidget {
  const _ClayNavItem({
    required this.destination,
    required this.selected,
    required this.position,
    required this.count,
    required this.onTap,
  });

  final ClayNavDestination destination;
  final bool selected;
  final int position;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final still = MediaQuery.disableAnimationsOf(context);
    Duration d(Duration motion) => still ? Duration.zero : motion;

    final dest = destination;
    final badge = dest.badgeCount ?? 0;
    final badgeWords = dest.badgeLabel ??
        (badge > 0
            ? '$badge'
            : dest.hasBadge
                ? 'new'
                : null);
    final spoken = [
      dest.label,
      'tab $position of $count',
      ?badgeWords,
    ].join(', ');

    final pill = dark ? ApnivaasColors.darkMist : ApnivaasColors.mist;
    final ink = selected ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant;
    final labelStyle = (t.textTheme.labelMedium ?? const TextStyle()).copyWith(
      color: ink,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
    );

    // Both arts stay in the tree, so the first switch to a tab never waits on a decode; only
    // their opacities change.
    final art = AnimatedSlide(
      offset: Offset(0, selected ? -Space.hair / ClaySize.nav : 0),
      duration: d(Motion.fast),
      curve: Motion.enter,
      child: AnimatedScale(
        scale: selected ? 1 : ClaySize.navOff / ClaySize.nav,
        duration: d(Motion.fast),
        curve: Motion.enter,
        child: SizedBox.square(
          dimension: ClaySize.nav,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedOpacity(
                opacity: selected ? 0 : 1,
                duration: d(Motion.fast),
                child: ClayIcon(
                  dest.resolvedOffIcon,
                  size: ClaySize.nav,
                  greyscale: dest.greysOut,
                  opacity: Dim.navOff,
                ),
              ),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: d(Motion.fast),
                child: ClayIcon(dest.icon, size: ClaySize.nav),
              ),
            ],
          ),
        ),
      ),
    );

    final indicator = SizedBox(
      width: ClayNavBar.indicatorWidth,
      height: ClayNavBar.indicatorHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedScale(
              scale: selected ? 1 : 0.8,
              duration: d(Motion.base),
              curve: Motion.emphasis,
              child: AnimatedContainer(
                duration: d(Motion.fast),
                decoration: BoxDecoration(
                  color: selected ? pill : pill.withValues(alpha: 0),
                  borderRadius: Radii.rButton,
                ),
              ),
            ),
          ),
          art,
          if (badge > 0)
            PositionedDirectional(
              top: -Space.hair,
              end: Space.xxs,
              child: CountBadge(count: badge),
            )
          else if (dest.hasBadge)
            PositionedDirectional(
              top: Space.xxs,
              end: Space.sm,
              child: Container(
                width: Space.xs,
                height: Space.xs,
                decoration: BoxDecoration(
                  color: t.colorScheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.colorScheme.surface, width: Strokes.control),
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: onTap != null,
      focusable: onTap != null,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        excludeFromSemantics: true,
        // The pill is the feedback; an ink splash over it would be a second one.
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.hair, ClayNavBar.topInset, Space.hair, ClayNavBar.bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              indicator,
              const SizedBox(height: ClayNavBar.labelGap),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(dest.label, maxLines: 1, softWrap: false, style: labelStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
