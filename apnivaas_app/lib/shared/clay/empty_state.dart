library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'clay_icons.dart';

/// The state a list is in when it has nothing to show — or could not load.
///
/// A clay icon on a soft Mist disc, a short title, one helpful sentence, and at most one
/// action. Centred in a 300dp column, so it reads as a considered moment rather than as a gap.
///
/// ── WHAT IT IS FOR, AND WHAT IT IS NOT ───────────────────────────────────────────────────
///
/// The art means "nothing here YET". A list emptied by a search or a filter is a different
/// fact — "no match for that" — and should say so in words with a plain glyph, not borrow the
/// first-run illustration. [EmptyState.error] is for a section that failed: the sentence must
/// be the honest one (`errorGuidance` and the screen's own words), and the action retries.
///
/// All the wording stays real Text: translatable, selectable, and read in order by a screen
/// reader; the art is excluded from semantics.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.body,
    this.icon = ClayIcons.success,
    this.actionLabel,
    this.onAction,
    this.action,
    this.compact = false,
  });

  /// A section that could not load. [message] is the honest sentence; [onRetry] the way on.
  const EmptyState.error({
    super.key,
    required String message,
    VoidCallback? onRetry,
    this.title = "This didn't load",
    String retryLabel = 'Try again',
    this.icon = ClayIcons.complaint,
    this.compact = false,
  })  : body = message,
        actionLabel = onRetry == null ? null : retryLabel,
        onAction = onRetry,
        action = null;

  final String title;
  final String? body;

  /// A [ClayIcons] path.
  final String icon;

  /// A filled button with this label. Ignored when [action] is given.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Any single action, for a caller that needs an outlined or custom button.
  final Widget? action;

  /// The in-card variant: a 72dp icon, a smaller title, tighter spacing.
  final bool compact;

  /// The widest the column grows, so the sentence keeps a readable measure.
  static const maxWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final disc = compact ? ClaySize.promo : ArtSize.emptyDisc;
    final art = compact ? ClaySize.banner : ClaySize.promo;

    Widget? cta = action;
    if (cta == null && actionLabel != null && onAction != null) {
      cta = FilledButton(onPressed: onAction, child: Text(actionLabel!));
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.all(compact ? Space.md : Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: disc,
                  height: disc,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dark ? ApnivaasColors.darkMist : ApnivaasColors.mist,
                    shape: BoxShape.circle,
                  ),
                  child: ClayIcon(icon, size: art),
                ),
              ),
              SizedBox(height: compact ? Space.sm : Space.md),
              Text(
                title,
                textAlign: TextAlign.center,
                // Proportional figures in both: a title is words, not a column of numbers.
                style: (compact ? t.textTheme.labelLarge : t.textTheme.headlineSmall)
                    ?.copyWith(fontFeatures: const []),
              ),
              if (body != null) ...[
                const SizedBox(height: Space.tight),
                Text(body!, textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
              ],
              if (cta != null) ...[
                SizedBox(height: compact ? Space.md : Space.lg),
                cta,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
