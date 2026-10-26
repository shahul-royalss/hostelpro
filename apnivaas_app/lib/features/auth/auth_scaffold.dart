library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../shared/clay/clay_icons.dart';
import '../../shared/wordmark.dart';
import '../common/form_parts.dart';

/// THE SIGN-IN FAMILY'S PAGE — sign-in, the second factor, the forced password change and the
/// email gate. The screens a new account meets before it reaches a home share one frame, so the
/// first four steps read as one walk rather than four different apps.
///
/// Cream ground, the brand bar at the top, a 20dp gutter, and a column no wider than 420dp — a
/// tablet gets a phone-width form in the middle, not a slab. An optional [footer] sits at the
/// bottom of a screen tall enough to have room for it and simply follows the content on one
/// that is not.
///
/// ── WHY IT IS ANCHORED TO THE TOP, AND NEVER CENTRED ────────────────────────────────────────
///
/// The sign-in group used to be centred in whatever space the keyboard left, and measured in the
/// 1.2.0 layout pass that made the title jump 67–190dp when the keyboard opened and re-centre the
/// whole group 33–56dp every time an error line appeared or went. A column that starts at the
/// top cannot do either: opening the keyboard shortens the viewport UNDER the content, and an
/// error that grows the form grows it downward. When the keyboard would cover the focused field,
/// the field's own `scrollPadding` ([keepVisibleBelow]) scrolls just far enough to keep it and the
/// button under it in view — the platform's behaviour, not a re-layout.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.children,
    this.footer,
    this.topBar = const AuthTopBar(),
  });

  /// The page under the brand bar, top to bottom, each at the column's full width.
  final List<Widget> children;

  /// Pinned to the bottom when there is room. It must be able to report its own height — text
  /// and buttons, never a LayoutBuilder — because that is how the room left over is measured.
  final Widget? footer;

  /// The brand bar. A screen that needs a back arrow passes its own [AuthTopBar].
  final Widget topBar;

  /// The widest the column grows.
  static const maxWidth = 420.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final side = math.max(Space.lg, (box.maxWidth - maxWidth) / 2);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, Space.md, side, Space.lg),
                // One box rather than a lazy list: the form's fields must never be built and
                // thrown away as they scroll, or a half-typed form loses its validation state.
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [topBar, ...children],
                  ),
                ),
              ),
              if (footer != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(side, 0, side, Space.lg),
                    child: Align(alignment: Alignment.bottomCenter, child: footer),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// The brand bar: the A-house mark and the wordmark, in forest, with room for one control at
/// either end.
///
/// 44dp tall at 1.0x and growing with the text, never fixed. The wordmark is held to 1.3x text
/// at most: it is the logo set in type, and a logo that doubles with the reading size pushes
/// the page down without making anything easier to read. The words on the page scale in full.
class AuthTopBar extends StatelessWidget {
  const AuthTopBar({super.key, this.leading, this.trailing});

  /// A back control, on a screen that was pushed rather than routed to.
  final Widget? leading;

  /// One control at the trailing edge.
  final Widget? trailing;

  static const height = 44.0;

  /// The canvas's 34×25 — the mark's own 256×186 proportions.
  static const markWidth = 34.0;
  static const markHeight = 25.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          ClayIcons.apnivaasMark,
          width: markWidth,
          height: markHeight,
          fit: BoxFit.contain,
          cacheWidth: math.min((markWidth * dpr).round(), ClayIcons.sourceWidthOf(ClayIcons.apnivaasMark)),
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) =>
              Icon(Icons.home_rounded, size: IconSize.lg, color: t.colorScheme.primary),
        ),
        const SizedBox(width: Space.xs),
        Flexible(
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: ApnivaasTypeMark(
                color: t.colorScheme.primary,
                fontSize: 22,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: Space.xxs)],
          Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: brand)),
          if (trailing != null) ...[const SizedBox(width: Space.xs), trailing!],
        ],
      ),
    );
  }
}

/// A step's heading: the title, one line saying what to do, and the step's clay icon in a Mist
/// well at the trailing edge.
///
/// Left-aligned, like the sign-in screen's own heading, so the steps after it line up on the same
/// edge. The title is Outfit 22/28 — the screen title, one per screen — and a semantics header.
///
/// The well sits BESIDE the words rather than above them. Stacked, it cost these screens 80dp of
/// height, and the forced password change is the one screen a brand-new account meets with three
/// fields, a meter and two buttons on it: on a 600dp-tall window Save and Sign out have to stay on
/// screen. Beside, the words wrap around a fixed 56dp and the heading costs nothing extra.
///
/// UNTIL THAT WOULD BREAK A WORD. The longest word a heading here carries — "authentication" —
/// needs about 168dp per 1x of text. Where the column beside the well is narrower than that at
/// the reader's text size, the well moves above the title and the title takes the full width,
/// because "aut-henticatio-n" down a narrow column is not a heading anybody can read.
class AuthHeading extends StatelessWidget {
  const AuthHeading({super.key, required this.title, this.message, this.icon});

  final String title;
  final String? message;

  /// A [ClayIcons] path for the well beside the title. Decorative.
  final String? icon;

  /// The width one unit of text scale needs for the longest heading word.
  static const _longestWord = 168.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: t.textTheme.displaySmall)),
        if (message != null) ...[
          const SizedBox(height: Space.xxs),
          Text(
            message!,
            style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
    if (icon == null) return words;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(builder: (context, box) {
      final beside = box.maxWidth - ClayWell.compactSize - Space.sm;
      if (beside < _longestWord * scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [ClayWell(icon!, compact: true), const SizedBox(height: Space.sm), words],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: words),
          const SizedBox(width: Space.sm),
          ClayWell(icon!, compact: true),
        ],
      );
    });
  }
}

/// The room a field should keep clear BELOW itself when the keyboard scrolls it into view, so
/// the button that submits the form stays above the keyboard too.
///
/// [below] is the height of everything between the field's bottom edge and the bottom of that
/// button, at text scale 1.0. It is scaled with the user's text size, because every row it
/// stands for grows with it.
EdgeInsets keepVisibleBelow(BuildContext context, double below) {
  final k = MediaQuery.textScalerOf(context).scale(16) / 16;
  return EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.lg + below * k);
}
