library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../glass/glass.dart';

/// Presents a bottom sheet with an optional title and subtitle above its body.
///
/// It IS [showGlassSheet] — the same single pane, grip, scrim, keyboard inset and 28dp top
/// corners — with the heading every new sheet starts with drawn for it, so a title is never a
/// different size on two sheets. Existing call sites of [showGlassSheet] keep working unchanged.
Future<T?> showApnivaasSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
  bool isScrollControlled = true,
}) {
  return showGlassSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    builder: (ctx) {
      if (title == null) return builder(ctx);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(title: title, subtitle: subtitle),
          const SizedBox(height: Space.md),
          Flexible(child: builder(ctx)),
        ],
      );
    },
  );
}

/// A sheet's heading: Outfit 20/26 in the ink, an optional supporting line in the muted ink.
/// A semantics header, so a screen reader lands on it first.
class SheetTitle extends StatelessWidget {
  const SheetTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: t.textTheme.titleLarge)),
        if (subtitle != null) ...[
          const SizedBox(height: Space.xxs),
          Text(subtitle!, style: t.textTheme.bodyMedium),
        ],
      ],
    );
  }
}
