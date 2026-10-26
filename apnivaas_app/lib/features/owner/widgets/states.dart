import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';
import '../../../shared/sign_in_again.dart';
import '../owner_insights.dart';

/// The three things a screen is doing when it is not showing data: loading, empty, or broken.
///
/// ALL THREE ARE DESIGNED, because all three are what a user actually sees on a bad morning.
/// A full-screen spinner throws away the layout the user already knows and replaces it with a
/// grey void; a skeleton keeps the shape and fills it in. An empty list that says nothing looks
/// identical to a list that failed. And an error that says "something went wrong" is a dead end
/// — every error here says what to do next, and only offers a retry when retrying could work
/// (see [errorGuidance]).
///
/// The card primitives — [StateCard], [StateBadge], [StateBody] — live in
/// `shared/glass/glass.dart`; this file is where they meet the app's real failures and empties.
///
/// ── WHAT MOVED TO THE CLAY KIT ───────────────────────────────────────────────────────────
///
/// The owner screens now draw their loading states with the clay skeletons (`ListSkeleton`,
/// `SkeletonPulse` in shared/clay/skeleton.dart), first-run empties with `EmptyState`, chips with
/// the clay `StatusChip`, and headings with `SectionHeader`. The owner-only KPI tile, section
/// label, heading, eyebrow, badge, avatar and chip that lived here had no caller left and are
/// gone, and so are the old dark-theme skeleton bar, its card and their shared ticker: the
/// clay skeleton's pulse stops off-screen and under reduce motion in the same way, and
/// test/theme_contrast_test.dart now holds it to that.

/// Draws one async section: skeleton, error, or content.
///
/// GO THROUGH THIS RATHER THAN CALLING `.when` DIRECTLY, because of a Riverpod 3 behaviour that
/// silently deletes every error state in the app. Riverpod 3 RETRIES a failed provider on its
/// own, with backoff. While a retry is pending the state is `AsyncLoading` carrying the previous
/// error — `hasError` is true but `isLoading` is also true — and `.when()` with its default
/// flags takes the loading branch. The result: a query that fails shows a skeleton that pulses
/// forever, and the error state that was carefully written for it is never once rendered.
/// Verified against riverpod 3.4.2: a provider whose future completes with an error sits at
/// `AsyncLoading<T> isLoading=true hasError=true` indefinitely.
///
/// `skipLoadingOnReload: true` is what fixes it: a state that is loading only because it is
/// retrying after a failure falls through to the error branch. A first load, which has no
/// previous state at all, still shows the skeleton — which is the one time a skeleton is right.
Widget whenAsync<T>(
  AsyncValue<T> value, {
  required Widget Function(T value) data,
  required Widget Function(Object error) error,
  required Widget Function() loading,
}) {
  return value.when(
    skipLoadingOnRefresh: true,
    skipLoadingOnReload: true,
    data: data,
    error: (e, _) => error(e),
    loading: loading,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY AND FAILED
// ─────────────────────────────────────────────────────────────────────────────

/// Nothing to show, and that is fine. Says what would appear here rather than sitting blank.
///
/// THE OWNER SCREENS NOW REACH FOR THE CLAY `EmptyState` for a first run — the clay icon on a
/// Mist disc. This stays for the two cases that are not a first run: a SEARCH that matched
/// nothing (a plain glyph, because the art would claim "nothing here yet") and a compact line
/// inside a card or sheet that already has its own heading. The standalone form is a card with
/// a glyph (or, given [illustration], the clay art) over a title and one support line.
class EmptyNote extends StatelessWidget {
  const EmptyNote({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.compact = false,
    this.tone,
    this.badge,
    this.action,
    this.illustration,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Inside a card that already has its own heading.
  final bool compact;

  /// Green only where empty is genuinely GOOD news ("nothing is waiting on you"). An empty
  /// list that is merely empty gets the neutral outline colour, because a reassuring tick over
  /// "no data yet" is the interface congratulating itself.
  final Color? tone;

  /// The design's caps tag. Null by default — see the note in [ErrorNote] on why the mockup's
  /// own "EMPTY STATE" is not copied.
  final String? badge;

  /// The design's one button ("Learn More", 4:1586 — a hairline outlined box, not a filled
  /// one). Most empty states in this app have nothing useful to offer, and an empty state with
  /// a button that does nothing is worse than one without.
  final Widget? action;

  /// An [EmptyArt] path drawn at 160dp INSTEAD of the outlined glyph square.
  ///
  /// THE OWNER IS THE READER THIS MATTERS MOST TO. A new PG owner signs in to four screens
  /// that are empty by definition — no residents, no payments, no notices, no complaints — and
  /// a 56dp outlined glyph on every one of them is what an unfinished app looks like. The
  /// resident and warden shells have drawn artwork on their own first-run states for a while;
  /// this is the same four pictures on the shell that sees them first.
  ///
  /// ONLY FIRST-RUN STATES GET ONE, which is the rule [StateBody.illustration] already sets: a
  /// list emptied by a SEARCH or a FILTER keeps the glyph, because the artwork says "there is
  /// nothing here yet" and that would be a lie over "no match for that". Call sites pass null
  /// when a filter is active.
  ///
  /// IGNORED WHEN [compact] IS SET — a compact note is a section inside a card that already
  /// has a heading, and 160dp of artwork there is larger than the thing it is explaining.
  /// [icon] stays required either way: it is the compact drawing, and it is what the artwork
  /// falls back to if the asset will not load.
  final String? illustration;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: IconSize.md,
                color: tone == null ? t.colorScheme.outline : context.tones.resolve(tone!)),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.textTheme.labelLarge),
                  if (message != null) ...[
                    const SizedBox(height: Space.xxs),
                    Text(message!, style: t.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    return StateCard(
      badge: badge,
      tone: tone,
      child: StateBody(
        icon: icon,
        illustration: illustration,
        title: title,
        message: message,
        tone: tone,
        action: action,
      ),
    );
  }
}

/// A failure, with the next step spelled out.
///
/// A card with a hairline — not a red-tinted panel, which is what this used to be. The red
/// lives in the badge and nowhere else, and the retry is the theme's forest filled button. That
/// is a quieter treatment than a full red box and it is the right one: on a dashboard where one
/// section failed and three did not, a red rectangle reads as "the app is broken" rather than
/// "this list did not load".
///
/// THE MOCKUP'S OWN TAGS ARE NOT COPIED VERBATIM. 4:1590 says "ERROR STATE", 4:1577 says
/// "EMPTY STATE", 4:1601 says "SKELETON LOADING" — those are the spec frame labelling its
/// three examples for a designer, not words a resident should read. The tag SLOT is kept
/// because colour-coding the state at a glance is genuinely useful; what goes in it is a real
/// word. Here that is "Error", which is what the badge is actually saying.
class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final guidance = errorGuidance(error);

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: IconSize.md, color: tones.error),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(guidance.title, style: t.textTheme.labelLarge),
                  const SizedBox(height: Space.xxs),
                  Text(guidance.next, style: t.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return StateCard(
      badge: 'Error',
      tone: ApnivaasColors.error,
      child: StateBody(
        title: guidance.title,
        message: guidance.next,
        // The button appears only when trying again could plausibly work. Offering a retry
        // for a permission refusal teaches people to tap it forever.
        //
        // AN EXPIRED SIGN-IN GETS THE ACTION THAT DOES WORK. It is not retryable and it is not
        // a refusal; it is the one terminal state with a one-tap recovery, and an owner staring
        // at "Not your PG" over a dead token was the whole reason this branch exists.
        action: AppFailure.from(error).needsSignIn
            ? const SignInAgainButton()
            : guidance.canRetry && onRetry != null
                ? FilledButton(
                    onPressed: onRetry,
                    // Width 0 so it hugs its label rather than inheriting the theme's full-bleed
                    // Size.fromHeight; the height stays at the 48 tap target.
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: const Text('Try again'),
                  )
                : null,
      ),
    );
  }
}
