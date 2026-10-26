library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import 'clay_icons.dart';
import 'pill_button.dart';

/// THE GOLD TASK BANNER — time-bound work that is waiting on the person: "Meter readings due",
/// "KYC pending for 3 tenants", "Subscription ends in 5 days".
///
/// The palette's one warm surface, so AT MOST ONE PER SCREEN; a second banner makes neither
/// urgent. Its inks are its own and measured on the darker stop: title 10.34:1, body 6.79:1, and
/// the filled forest [PillButton] 7.55:1 against it as a graphic. Dark: a low brown-gold, title
/// 10.00:1, body 8.99:1, the Mist pill 10.42:1.
///
/// The clay icon sits at the trailing edge at 96dp, drops to 72 from 1.5x text, and goes
/// altogether when keeping it would leave the words under 180dp — the words are the banner.
/// The whole banner is one semantics container; the button inside stays its own target.
class ActionBanner extends StatelessWidget {
  const ActionBanner({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.actionSemanticLabel,
  });

  /// One line of what is due — "Meter readings due".
  final String title;

  /// The detail, with the real numbers in it — "Rooms 101–108 · due by 5 Nov".
  final String? message;

  /// A [ClayIcons] path for the trailing art. Decorative.
  final String? icon;

  /// The filled pill under the words — "Start". Both this and [onAction] are needed.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Spoken instead of [actionLabel] when the word alone is ambiguous — "Start meter readings".
  final String? actionSemanticLabel;

  /// The narrowest the words may get before the art gives way.
  static const minTextWidth = 180.0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final titleInk = dark ? ApnivaasColors.bannerTitleDark : ApnivaasColors.bannerTitle;
    final bodyInk = dark ? ApnivaasColors.bannerBodyDark : ApnivaasColors.bannerBody;
    final art = scale >= 1.5 ? ClaySize.banner : ClaySize.promo;

    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.textRoles.tileTitle.copyWith(color: titleInk)),
        if (message != null) ...[
          const SizedBox(height: Space.hair),
          Text(message!, style: ApnivaasType.manrope(13, 18, FontWeight.w400, bodyInk)),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: Space.tight),
          PillButton(
            label: actionLabel!,
            onPressed: onAction,
            filled: true,
            semanticLabel: actionSemanticLabel,
          ),
        ],
      ],
    );

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: dark ? ApnivaasColors.bannerGradientDark : ApnivaasColors.bannerGradient,
          borderRadius: Radii.rSurface,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg - Space.hair, Space.sm + Space.hair,
              Space.sm, Space.sm + Space.hair),
          child: LayoutBuilder(builder: (context, c) {
            final showArt = icon != null && c.maxWidth - art - Space.sm >= minTextWidth;
            return Row(
              children: [
                Expanded(child: words),
                if (showArt) ...[
                  const SizedBox(width: Space.sm - Space.hair),
                  ClayIcon(icon!, size: art),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// THE MIST BANNER — an explanation that belongs to a screen rather than a task: "How a demo
/// works", "Rent is collected on the 5th". Calm, not urgent; any number of screens may carry
/// one, but one per screen.
///
/// Mist, radius 22, at least 96dp tall; the title forest (7.54:1), the body the strong ink
/// (7.36:1), the clay icon 72dp at the trailing edge (dropped below 180dp of words, like
/// [ActionBanner]). An optional [action] goes under the words.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.action,
  });

  final String title;
  final String? message;

  /// A [ClayIcons] path. Decorative.
  final String? icon;

  /// A [PillButton] or a text link under the words.
  final Widget? action;

  static const minHeight = 96.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final titleInk = dark ? ApnivaasColors.onSurface : ApnivaasColors.forest;
    final bodyInk = dark ? ApnivaasColors.onSurfaceVariant : ApnivaasColors.inkStrong;

    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.textRoles.tileTitle.copyWith(color: titleInk)),
        if (message != null) ...[
          const SizedBox(height: Space.hair),
          Text(message!, style: ApnivaasType.manrope(12, 17, FontWeight.w400, bodyInk)),
        ],
        if (action != null) ...[const SizedBox(height: Space.xs), action!],
      ],
    );

    return Semantics(
      container: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.sm, Space.sm),
        decoration: BoxDecoration(
          color: dark ? ApnivaasColors.darkMist : ApnivaasColors.mist,
          borderRadius: Radii.rWell,
        ),
        child: LayoutBuilder(builder: (context, c) {
          final showArt =
              icon != null && c.maxWidth - ClaySize.banner - Space.sm >= ActionBanner.minTextWidth;
          return Row(
            children: [
              Expanded(child: words),
              if (showArt) ...[
                const SizedBox(width: Space.sm),
                ClayIcon(icon!, size: ClaySize.banner),
              ],
            ],
          );
        }),
      ),
    );
  }
}

/// A quiet note — a sentence that qualifies what is around it: "Demo slots are in IST", "Sample
/// data until your first tenant moves in". The neutral chip fill, radius 16, the strong ink
/// (7.28:1; dark 7.19:1). An optional glyph leads it in the same ink.
class InfoNote extends StatelessWidget {
  const InfoNote({super.key, required this.message, this.icon});

  final String message;

  /// A Material glyph at 16dp. Decorative — the sentence says it.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ink =
        t.brightness == Brightness.dark ? ApnivaasColors.onSurfaceVariant : ApnivaasColors.inkStrong;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Space.sm + Space.hair, vertical: Space.sm),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest,
        borderRadius: Radii.rButton,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: Space.hair / 2),
              child: Icon(icon, size: IconSize.md, color: ink),
            ),
            const SizedBox(width: Space.xs),
          ],
          Expanded(
            child: Text(message, style: ApnivaasType.manrope(13, 18, FontWeight.w400, ink)),
          ),
        ],
      ),
    );
  }
}
