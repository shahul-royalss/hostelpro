import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// A proportion, drawn as a bar.
///
/// WHY A BAR AND NOT A DONUT. Both encode one number, but a bar shares the width of the card it
/// sits in, so the figure above it and the shape below it are read as one object rather than as
/// a chart with a caption. It also degrades honestly: [value] is null when there is nothing to
/// divide by, and an empty track with an explanation underneath is the truthful drawing of
/// "no beds configured", where a donut at 0% would look like a business with no customers.
class ProportionMeter extends StatelessWidget {
  const ProportionMeter({
    super.key,
    required this.value,
    this.tone,
    this.height = Space.xs,
    this.semanticLabel,
  });

  /// 0.0–1.0, or null when the denominator is zero.
  final double? value;

  /// Defaults to the theme's primary. Pass a semantic colour only when the colour MEANS
  /// something — a bar that is red because the number is low is information; a bar that is
  /// teal because teal is nice is decoration.
  final Color? tone;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A filled bar is a graphical object, so 3:1 against the track applies to it. Resolving
    // keeps that true in the dark theme, where the canonical inks were authored for white.
    final fill = context.tones.resolve(tone ?? theme.colorScheme.primary);
    final track = theme.colorScheme.outlineVariant;
    final target = (value ?? 0).clamp(0.0, 1.0);

    return Semantics(
      label: semanticLabel,
      value: value == null ? 'not applicable' : '${(target * 100).round()} percent',
      child: SizedBox(
        height: height,
        // Radii.rControl is larger than half the bar's height, so the clipper scales it down
        // to a pill. One token, no second constant to keep in step with the height.
        child: ClipRRect(
          borderRadius: Radii.rControl,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: track)),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: target),
                    duration: Motion.base,
                    curve: Motion.enter,
                    builder: (context, t, _) => FractionallySizedBox(
                      widthFactor: t,
                      heightFactor: 1,
                      child: ColoredBox(color: fill),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
