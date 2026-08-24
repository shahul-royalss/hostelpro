library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../widgets/warden_ui.dart';

/// The inside of every warden bottom sheet.
///
/// showGlassSheet already owns the geometry, the barrier and the keyboard inset. This owns the
/// two things it cannot: a HEIGHT CAP, and scrolling.
///
/// Without the cap a sheet with a long form grows past the top of the screen and its submit
/// button becomes unreachable — an isScrollControlled sheet is allowed to be taller than the
/// display, and Flutter will happily let it. 88% leaves the page underneath visible, which is
/// what tells a warden they are looking at something they can dismiss rather than a new screen.
class SheetBody extends StatelessWidget {
  const SheetBody({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  /// False for a sheet whose child scrolls itself (a list), so there are not two scroll views.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.88 - media.padding.top;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: title, subtitle: subtitle, trailing: trailing),
          const SizedBox(height: Space.md),
          Flexible(
            child: scrollable
                ? SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: child,
                  )
                : child,
          ),
        ],
      ),
    );
  }
}
