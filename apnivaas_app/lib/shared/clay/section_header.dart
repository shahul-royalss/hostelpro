library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';

/// How loud a [SectionHeader] is.
enum SectionHeaderSize {
  /// A section of the page — "Overview". Outfit 20/600.
  page,

  /// A heading inside a card — "Quick actions". Outfit 18/600.
  card,

  /// A group of fields in a form. Outfit 15/600.
  form,
}

/// A heading over a group, with an optional action at the trailing edge.
///
/// Sentence case, always — the tracked capitals of [DashboardBand] are retired for new work.
/// The heading is a semantics header, so a screen-reader user can jump between sections.
///
/// [actionLabel] + [onAction] draws a quiet brand text link ("View all") with a 48dp target;
/// [trailing] takes any widget instead — a neutral [StatusChip] reading "Sample data", say.
///
/// THE TRAILING CONTROL GIVES WAY TO THE WORDS. It sits at the end of the heading's line while
/// both fit, and moves under the heading when they do not: at 2.0x a month chip beside
/// "Overview" left "Overvi" on one line and "ew" on the next.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.size = SectionHeaderSize.page,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final SectionHeaderSize size;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final style = switch (size) {
      SectionHeaderSize.page => t.textTheme.titleLarge,
      SectionHeaderSize.card => t.textTheme.headlineSmall?.copyWith(fontFeatures: const []),
      SectionHeaderSize.form => context.textRoles.formSection,
    };

    Widget? end = trailing;
    if (end == null && actionLabel != null && onAction != null) {
      end = TextButton(
        onPressed: onAction,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
          textStyle: t.textTheme.titleSmall?.copyWith(fontFeatures: const []),
        ),
        child: Text(actionLabel!),
      );
    }

    final heading = Semantics(
      header: true,
      child: Text(title, style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
    );

    // Full width either way, like the Row this used to be: spaceBetween needs the whole line
    // to put the control at its end.
    return Padding(
      padding: padding,
      child: SizedBox(
        width: double.infinity,
        child: end == null
            ? heading
            : Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Space.xs,
                runSpacing: Space.xxs,
                children: [heading, end],
              ),
      ),
    );
  }
}
