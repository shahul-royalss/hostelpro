library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The small capsule action that sits at the end of a row or inside a banner — "Remind",
/// "Assign", "Review", "Start".
///
/// 36dp to the eye and 48dp to the finger: the visual pill is padded out to Material's minimum
/// tap target, so a dense row keeps its rhythm without shrinking the control. Outlined by
/// default (a 1.5px brand edge, the brand label); [filled] for the one primary action inside a
/// banner.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.icon,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  /// A 16dp glyph before the label.
  final IconData? icon;

  /// Spoken instead of [label] when the label alone is ambiguous out of context — "Remind 6
  /// tenants" rather than "Remind".
  final String? semanticLabel;

  /// The visual height of the capsule.
  static const height = 36.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final dark = t.brightness == Brightness.dark;
    final brand = scheme.primary;
    final fill = dark ? ApnivaasColors.primaryContainer : ApnivaasColors.forest;
    final onFill = dark ? ApnivaasColors.onPrimaryContainer : ApnivaasColors.headerTitle;
    final style = (t.textTheme.titleSmall ?? const TextStyle())
        .copyWith(fontFeatures: const [], fontWeight: FontWeight.w700);

    const shape = StadiumBorder();
    // 14 across with a label alone, 12 with a glyph — the canvas's two pills.
    final padding = EdgeInsets.symmetric(horizontal: icon == null ? Space.sm + Space.hair : Space.sm);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: IconSize.md),
          const SizedBox(width: Space.tight),
        ],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );

    final Widget button = filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: fill,
              foregroundColor: onFill,
              minimumSize: const Size(0, height),
              padding: padding,
              shape: shape,
              textStyle: style,
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: brand,
              side: BorderSide(color: brand, width: Strokes.control),
              minimumSize: const Size(0, height),
              padding: padding,
              shape: shape,
              textStyle: style,
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: child,
          );

    final spoken = semanticLabel;
    if (spoken == null) return button;
    // The child's own node is replaced, so the tap is handed to this one.
    return Semantics(
      label: spoken,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      excludeSemantics: true,
      child: button,
    );
  }
}
