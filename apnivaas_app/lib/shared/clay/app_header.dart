library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../brow.dart';
import 'clay_icons.dart';
import 'list_row.dart' show InitialsDisc;
import 'word_fit.dart';

/// THE FOREST HEADER — the top of every dashboard and the brand's one full-bleed object.
///
/// A forest gradient with rounded bottom corners and a quiet field of dot "stars", identical
/// in both themes. It replaces the purple brow with its gold sweep: no dip curve, no entrance
/// animation, nothing ticking — it is drawn once and cached.
///
/// ── THE INK IS NOT THE CALLER'S TO CHOOSE ────────────────────────────────────────────────
///
/// The old brow's worst bug was a call site handing it a `Text` styled with the theme's own
/// ink — near-black on purple. So this takes STRINGS for everything it prints and resolves the
/// inks itself, and anything put into [leading], [actions] or [bottom] sits inside a
/// [ForestInk] scope: unstyled text, icons and icon buttons come out white, and widgets that
/// name a colour of their own (an avatar, a dot) can ask `BrowScope.of(context)`.
///
/// Every ink is measured against the gradient's LIGHTEST stop, [ApnivaasColors.forestHigh]:
/// title white 7.28:1, greeting 5.11:1, subtitle 5.29:1, the gold unread dot 3.60:1.
///
/// ── LAYOUT ───────────────────────────────────────────────────────────────────────────────
///
/// No fixed height. The status-bar inset plus 18 on top, 16 at the sides, 22 underneath and
/// 18 between rows. The title is one line up to 1.3x text and two above it; the greeting and
/// subtitle are one line each and ellipsise. Below 360dp the avatar drops from 50 to 44.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.greeting,
    this.subtitle,
    this.leading,
    this.onTitleTap,
    this.titleSemanticLabel,
    this.actions = const [],
    this.bottom,
    this.stars = true,
  });

  /// The PG name, or the screen's name on a sub-page. Outfit 22/600, white.
  final String title;

  /// The small line above the title — "Good morning, Lakshmi".
  final String? greeting;

  /// A meta line under the title — the PG on a sub-page, a count.
  final String? subtitle;

  /// A [HeaderAvatar] on a dashboard, a [HeaderBackButton] on a sub-page.
  final Widget? leading;

  /// Makes the greeting and title one button with a chevron after the title — the property
  /// switcher. Null draws plain text.
  final VoidCallback? onTitleTap;

  /// What a screen reader says for the title button, e.g. "Green Valley PG, switch property".
  /// Defaults to the title followed by ", switch".
  final String? titleSemanticLabel;

  /// Trailing controls: [HeaderIconButton]s, usually the bell.
  final List<Widget> actions;

  /// An optional second row, usually a [HeaderSearchPill].
  final Widget? bottom;

  /// The star field. On by default; off for a header that must be as plain as possible.
  final bool stars;

  /// The header's own padding, for the few callers that line content up with it.
  static const sideInset = Space.md;
  static const topGap = 18.0;
  static const bottomInset = 22.0;
  static const rowGap = 18.0;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).top;
    final scale = MediaQuery.textScalerOf(context).scale(1);

    final titleBlock = _TitleBlock(
      greeting: greeting,
      title: title,
      subtitle: subtitle,
      titleLines: scale <= 1.3 ? 1 : 2,
      onTap: onTitleTap,
      semanticLabel: titleSemanticLabel,
    );

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: Space.sm)],
            Expanded(child: titleBlock),
            for (final a in actions) ...[const SizedBox(width: Space.xs), a],
          ],
        ),
        if (bottom != null) ...[const SizedBox(height: rowGap), bottom!],
      ],
    );

    content = Padding(
      padding: EdgeInsets.fromLTRB(sideInset, inset + topGap, sideInset, bottomInset),
      child: ForestInk(child: content),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark icons on forest are a clock nobody can read, and the root sets exactly that for
      // the cream ground. This region wins for the strip the header covers.
      value: ApnivaasTheme.onForest,
      child: ClipRRect(
        borderRadius: Radii.rHeaderBottom,
        child: Stack(
          children: [
            // Its own layer, painted once: a badge changing in the content above does not
            // repaint the gradient.
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: HeaderBackdropPainter(topInset: inset, stars: stars)),
              ),
            ),
            content,
          ],
        ),
      ),
    );
  }
}

/// The greeting, the title (and its chevron) and the subtitle, in the header's own inks.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.greeting,
    required this.title,
    required this.subtitle,
    required this.titleLines,
    required this.onTap,
    required this.semanticLabel,
  });

  final String? greeting;
  final String title;
  final String? subtitle;
  final int titleLines;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final styles = HeaderText.of(context);
    final titleRow = LayoutBuilder(builder: (context, box) {
      // A one-word title too long for its line is set a little smaller rather than broken in
      // the middle (see [WordFit]); the chevron's room comes off the line first.
      final line = box.maxWidth - (onTap == null ? 0 : Space.tight + IconSize.lg);
      return Row(
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(title,
                  style: styles.title,
                  maxLines: titleLines,
                  textScaler: WordFit.scalerFor(context, title, styles.title, line),
                  overflow: TextOverflow.ellipsis),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: Space.tight),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: IconSize.lg, color: ApnivaasColors.headerTitle),
          ],
        ],
      );
    });

    final block = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (greeting != null)
          Text(greeting!, style: styles.greeting, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (greeting != null) const SizedBox(height: Space.hair),
        titleRow,
        if (subtitle != null) ...[
          const SizedBox(height: Space.hair),
          Text(subtitle!, style: styles.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ],
    );

    if (onTap == null) return block;
    return Semantics(
      button: true,
      label: semanticLabel ?? '$title, switch',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.rControl,
        splashColor: ApnivaasColors.headerButtonFill,
        highlightColor: ApnivaasColors.headerButtonFill,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(alignment: AlignmentDirectional.centerStart, child: block),
        ),
      ),
    );
  }
}

/// The header's type, resolved for the inks it is measured in. Public so other forest surfaces
/// (the sign-in hero card, a legacy brow) print the same three lines.
@immutable
class HeaderText {
  const HeaderText({required this.greeting, required this.title, required this.subtitle});

  /// Manrope 12/16 w600, [ApnivaasColors.headerGreeting] — 5.11:1 on the lightest stop.
  final TextStyle greeting;

  /// Outfit 22/28 w600, white — 7.28:1.
  final TextStyle title;

  /// Manrope 12/16, [ApnivaasColors.headerSub] — 5.29:1.
  final TextStyle subtitle;

  static HeaderText of(BuildContext context) => HeaderText(
        greeting: ApnivaasType.manrope(12, 16, FontWeight.w600, ApnivaasColors.headerGreeting),
        title: ApnivaasType.outfit(22, 28, FontWeight.w600, ApnivaasColors.headerTitle),
        subtitle: ApnivaasType.manrope(12, 16, FontWeight.w400, ApnivaasColors.headerSub),
      );
}

/// "Everything in here is drawn on forest." White text, white icons, white icon buttons —
/// disabled ones at 38% white rather than the theme's dark ink at 38% — and a [BrowScope] for
/// widgets that pick a colour of their own.
///
/// IconTheme alone is not enough for an IconButton: Material 3 resolves it as a button style,
/// and a DISABLED one never borrows IconTheme's colour; it falls through to onSurface at 38%,
/// which is near-black. So both states are named here, over whatever the app's own
/// IconButtonTheme says about size and shape.
class ForestInk extends StatelessWidget {
  const ForestInk({super.key, required this.child});

  final Widget child;

  /// A disabled control on forest: white at Material's 38%. It owes no contrast; what matters
  /// is that it dims toward the ground rather than going dark.
  static const disabled = Color(0x61FFFFFF);

  @override
  Widget build(BuildContext context) {
    const ink = ApnivaasColors.headerTitle;
    final t = Theme.of(context);
    final iconButtons = IconButton.styleFrom(
      foregroundColor: ink,
      disabledForegroundColor: disabled,
      overlayColor: ink,
    ).merge(IconButtonTheme.of(context).style);
    return BrowScope(
      child: IconTheme.merge(
        data: const IconThemeData(color: ink),
        child: IconButtonTheme(
          data: IconButtonThemeData(style: iconButtons),
          child: DefaultTextStyle.merge(
            style: (t.textTheme.bodyMedium ?? const TextStyle()).copyWith(color: ink),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The gradient and the stars. Static: [shouldRepaint] only answers yes when the inset or the
/// star switch changes, so the layer is painted once per header.
class HeaderBackdropPainter extends CustomPainter {
  const HeaderBackdropPainter({required this.topInset, this.stars = true});

  /// The status-bar inset. The star field is laid out from the top of the CONTENT, so it keeps
  /// its place beside the greeting whatever the phone's status bar height.
  final double topInset;
  final bool stars;

  /// Every star this header draws, resolved for a header of [size]: where it is, and whether it
  /// gets a halo. Public so a test can hold the placement rules to account without pixels.
  static List<({Offset center, StarDot dot, bool halo})> starsFor(Size size, double topInset) {
    final out = <({Offset center, StarDot dot, bool halo})>[];
    final sx = size.width / HeaderStars.referenceWidth;
    for (final dot in HeaderStars.dots) {
      final center = Offset(dot.x * sx, dot.y + topInset);
      // A star that would fall below the header — a short sub-page header — is simply not
      // drawn; the field never squeezes to fit.
      final reach = (dot.haloRadius ?? dot.radius);
      if (center.dy + reach > size.height || center.dx + reach > size.width) continue;
      final halo = dot.haloRadius != null &&
          dot.x / HeaderStars.referenceWidth >= HeaderStars.haloMinFraction;
      out.add((center: center, dot: dot, halo: halo));
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = ApnivaasColors.headerGradient.createShader(rect));
    if (!stars) return;
    for (final s in starsFor(size, topInset)) {
      final d = s.dot;
      if (s.halo) {
        canvas.drawCircle(
          s.center,
          d.haloRadius!,
          Paint()..color = d.haloColor!.withValues(alpha: d.haloAlpha!),
        );
      }
      canvas.drawCircle(s.center, d.radius, Paint()..color = d.color.withValues(alpha: d.alpha));
    }
  }

  @override
  bool shouldRepaint(HeaderBackdropPainter oldDelegate) =>
      oldDelegate.topInset != topInset || oldDelegate.stars != stars;
}

/// The account disc at the head of a dashboard header: the brand mark, or a person's initials,
/// on a warm white disc with a soft white ring.
class HeaderAvatar extends StatelessWidget {
  const HeaderAvatar({super.key, this.name, this.onTap, this.semanticLabel, this.image});

  /// Initials are drawn from this when given; otherwise the Apnivaas mark.
  final String? name;

  /// The person's photo, drawn over the initials when it loads. A photo that fails to load
  /// (an expired or refused signed URL) leaves the initials showing.
  final ImageProvider? image;
  final VoidCallback? onTap;

  /// Required in practice whenever [onTap] is set — "Your account", "Green Valley PG, switch
  /// property".
  final String? semanticLabel;

  /// Up to two initials — [InitialsDisc.initialsFor], so every disc in the app agrees.
  static String initialsFor(String? name) => InitialsDisc.initialsFor(name);

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    final size = narrow ? AvatarSize.header : AvatarSize.headerLarge;
    final person = name?.trim();
    final Widget face = person == null || person.isEmpty
        ? Image.asset(
            ClayIcons.apnivaasMark,
            width: size * 0.64,
            height: size * 0.48,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.home_rounded, color: ApnivaasColors.forest),
          )
        : Text(
            initialsFor(person),
            maxLines: 1,
            style: ApnivaasType.outfit(18, 22, FontWeight.w600, ApnivaasColors.forest),
          );
    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: ApnivaasColors.card,
        boxShadow: [BoxShadow(color: ApnivaasColors.headerAvatarRing, spreadRadius: 3)],
      ),
      // The initials never grow past the disc, whatever the text scale.
      child: image == null
          ? MediaQuery.withNoTextScaling(child: face)
          : ClipOval(
              child: Image(
                image: image!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                gaplessPlayback: true,
                frameBuilder: (_, child, frame, sync) => frame == null && !sync
                    ? Center(child: MediaQuery.withNoTextScaling(child: face))
                    : child,
                errorBuilder: (_, _, _) =>
                    Center(child: MediaQuery.withNoTextScaling(child: face)),
              ),
            ),
    );
    if (onTap == null) {
      return semanticLabel == null
          ? ExcludeSemantics(child: disc)
          : Semantics(label: semanticLabel, image: true, child: ExcludeSemantics(child: disc));
    }
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: size / 2 + Space.xxs,
        child: disc,
      ),
    );
  }
}

/// A round header control: 44 to the eye, 48 to the finger, white glyph on white at 8%.
///
/// [badgeCount] draws a gold pill with the count (ink on gold 7.30:1; gold on forest 3.60:1);
/// [hasUnread] draws the canvas's 9dp gold dot with a forest ring. Either way the count is in
/// the spoken label too, never colour alone.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badgeCount,
    this.hasUnread = false,
  });

  final IconData icon;

  /// Spoken, and shown as the tooltip.
  final String label;
  final VoidCallback? onPressed;
  final int? badgeCount;
  final bool hasUnread;

  static const size = 44.0;

  @override
  Widget build(BuildContext context) {
    final count = badgeCount ?? 0;
    final spoken = count > 0
        ? '$label, $count unread'
        : hasUnread
            ? '$label, unread'
            : label;
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ApnivaasColors.headerButtonFill,
        border: Border.all(color: ApnivaasColors.headerButtonBorder, width: Strokes.hairline),
      ),
      alignment: Alignment.center,
      child: Icon(icon,
          size: 21,
          color: onPressed == null ? ForestInk.disabled : ApnivaasColors.headerTitle),
    );
    Widget marker = const SizedBox.shrink();
    if (count > 0) {
      marker = PositionedDirectional(
        top: 2,
        end: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ApnivaasColors.gold,
              borderRadius: Radii.rPill,
              border: Border.all(color: ApnivaasColors.forest, width: Strokes.focus),
            ),
            child: Padding(
              // The border is painted inside the box, so the text clears it by its width on
              // every side as well as by the horizontal breathing room.
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.xxs + Strokes.focus, vertical: Strokes.focus),
              child: Align(
                child: MediaQuery.withNoTextScaling(
                  child: Text(count > 99 ? '99+' : '$count',
                      style: ApnivaasType.manrope(11, 14, FontWeight.w700, ApnivaasColors.ink,
                          tabular: true)),
                ),
              ),
            ),
          ),
        ),
      );
    } else if (hasUnread) {
      marker = PositionedDirectional(
        top: 9,
        end: 10,
        child: Container(
          width: 9 + Strokes.focus * 2,
          height: 9 + Strokes.focus * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ApnivaasColors.gold,
            border: Border.all(color: ApnivaasColors.forest, width: Strokes.focus),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: spoken,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkResponse(
          onTap: onPressed,
          radius: 26,
          child: SizedBox.square(
            dimension: 48,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [circle, marker],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bell, with the unread count. A [HeaderIconButton] with the label settled.
class HeaderBell extends StatelessWidget {
  const HeaderBell({super.key, required this.onPressed, this.unreadCount, this.hasUnread = false});

  final VoidCallback? onPressed;
  final int? unreadCount;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) => HeaderIconButton(
        icon: Icons.notifications_none_rounded,
        label: 'Notifications',
        onPressed: onPressed,
        badgeCount: unreadCount,
        hasUnread: hasUnread,
      );
}

/// The back control on a forest sub-page header.
class HeaderBackButton extends StatelessWidget {
  const HeaderBackButton({super.key, this.onPressed, this.label = 'Back'});

  /// Defaults to popping the route.
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => HeaderIconButton(
        icon: Icons.arrow_back_rounded,
        label: label,
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      );
}

/// The search pill under a dashboard header. A button, not a field: tapping it opens the full
/// search screen, so the header itself never re-lays out under the keyboard.
class HeaderSearchPill extends StatelessWidget {
  const HeaderSearchPill({
    super.key,
    required this.onTap,
    this.hint = 'Search tenants, rooms, payments',
  });

  final VoidCallback? onTap;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: ApnivaasColors.headerSearchFill,
        shape: const RoundedRectangleBorder(
          borderRadius: Radii.rControl,
          side: BorderSide(color: ApnivaasColors.headerSearchBorder, width: Strokes.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: ApnivaasColors.headerButtonFill,
          highlightColor: ApnivaasColors.headerButtonFill,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm + Space.hair),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 19, color: ApnivaasColors.headerTitle),
                  const SizedBox(width: Space.sm - Space.hair),
                  Expanded(
                    child: Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ApnivaasType.manrope(
                          15, 22, FontWeight.w500, ApnivaasColors.headerPlaceholder),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
