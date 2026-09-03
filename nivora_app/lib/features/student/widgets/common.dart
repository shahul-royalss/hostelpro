library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../../../shared/sign_in_again.dart';

/// The small kit every student screen is built from.
///
/// Kept inside this feature rather than in `shared/` on purpose: the owner and warden apps have
/// their own, and their wording is written for staff. A resident is not a colleague of the
/// warden — "ask your warden" is the right next step here and the wrong one there — so the copy
/// diverges even where the shape does not.

// ─────────────────────────────────────────────────────────────────────────────
// FAILURE → WHAT TO DO NEXT
// ─────────────────────────────────────────────────────────────────────────────

/// Turns a failure into something a resident can act on.
///
/// "Something went wrong" is the worst sentence in software, and a Retry button under a
/// permission refusal teaches people to tap it forever. [AppFailure] is sealed, so this switch
/// is exhaustive and a new failure type cannot quietly fall through to a generic line.
({String title, String next, bool canRetry}) errorGuidance(Object error) {
  final failure = error is AppFailure ? error : AppFailure.from(error);
  return switch (failure) {
    OfflineFailure() => (
        title: 'No connection',
        next: 'Your phone cannot reach Nivora. Check your Wi-Fi or mobile data and try again.',
        canRetry: true,
      ),
    ServerFailure() => (
        title: 'Nivora is busy',
        next: 'The server did not answer in time. Try again in a moment.',
        canRetry: true,
      ),
    ReadOnlyFailure() => (
        title: 'Your hostel is read-only',
        next: 'The subscription for your PG has lapsed, so nothing can be saved right now. '
            'You can still read everything. Ask your warden when it will be renewed.',
        canRetry: false,
      ),
    AccessDeniedFailure() => (
        title: 'Not available to you',
        next: 'That belongs to another account. If you think this is wrong, ask your warden.',
        canRetry: false,
      ),
    NotFoundFailure() => (
        title: 'No longer there',
        next: 'That record has been removed. Pull down to refresh.',
        canRetry: false,
      ),
    ConflictFailure() => (title: 'Already recorded', next: failure.message, canRetry: false),
    InvalidInputFailure() => (title: 'Check that again', next: failure.message, canRetry: false),
    SignedOutFailure() => (
        title: 'Signed out',
        next: 'Your session has ended. Sign in again with your phone number.',
        canRetry: false,
      ),
    // A resident must never be sent to their warden over a dead token. "Ask your warden" is a
    // real errand for a young person in a strange city, and the warden cannot help with this.
    SessionExpiredFailure() => (
        title: 'Sign-in expired',
        next: 'Your sign-in ran out. Nothing is wrong with your account and there is no need '
            'to ask anyone — sign in again with your phone number.',
        canRetry: false,
      ),
    UnexpectedFailure() => (
        title: 'That did not work',
        next: 'Please try again. If it keeps happening, show this screen to your warden.',
        canRetry: true,
      ),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// THE THREE NON-DATA STATES
// ─────────────────────────────────────────────────────────────────────────────

/// A placeholder bar, sized like the thing it stands in for.
///
/// A skeleton rather than a spinner: it keeps the layout the resident already knows and fills
/// it in, instead of replacing the screen with a grey void and then snapping back.
///
/// THE BAR IS #1D2227 ON #111417, which is the pairing `screen-empty-error-skeleton` draws
/// (4:1604, 4:1605, 4:1609, 4:1610 — `bg-[#1d2227] rounded-[4px]`) and measures 1.15:1. That
/// is a whisper on purpose: a placeholder that is easy to read is a placeholder people try to
/// read. It used to be the hairline #292E33 at the control radius, which was both the wrong
/// colour and the wrong corner.
///
/// The light theme cannot use that hex — a near-black bar on a white card is not a placeholder,
/// it is a redaction — so it takes the hairline, which is the light palette's own quiet fill.
/// Both come off the scheme; neither is named here.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.widthFactor,
    this.height = Space.xs,
    this.radius = Radii.tiny,
  });

  final double? width;

  /// A share of the available width, for a placeholder that has to survive a 320dp screen.
  /// A fixed 160dp line looked like a paragraph on a wide phone and like a full row on a
  /// narrow one; a fraction reads as the same placeholder on both.
  final double? widthFactor;

  /// The design's bars are 6, 8 and 14 high — a text line, a label and a value. [Space.xs] and
  /// [Space.sm] are those two steps on the 4dp grid.
  final double height;
  final double radius;

  /// The design's shimmer fill in the dark theme, and something visible in the light one.
  static Color barColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? scheme.surfaceBright
        : scheme.outlineVariant;
  }

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: barColor(context),
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      ),
    );
    if (widthFactor == null) return box;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: box,
    );
  }
}

/// A card-shaped placeholder for a section that has not arrived yet.
///
/// The design's `skeleton-layout` (4:1602) is a RAISED card carrying a short title bar, then
/// the pending content inside a block at the CARD fill one rung down. That inner block is what
/// makes the bars legible: #1D2227 on #111417 is the pairing Figma draws, and on the raised
/// surface alone the bars all but vanish. This used to be an [OutlineCard] — the card rung,
/// with the bars painted straight onto it — which is one surface short of the mockup.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 2, this.height});

  final int lines;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return StateCard(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Skeleton(width: 60, height: Space.xs),
            ),
            const SizedBox(height: Space.sm),
            FlatSurface(
              borderRadius: Radii.rControl,
              // The design draws this inner block as a bare fill: a hairline inside a hairlined
              // card reads as a table.
              border: false,
              padding: const EdgeInsets.all(Space.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < lines; i++) ...[
                    // The first bar is the value (14 in the design, 12 on the grid); the rest
                    // are the 8dp text lines, alternating full width and short.
                    Skeleton(
                      widthFactor: i == 0 ? 0.62 : (i.isOdd ? 1 : 0.6),
                      height: i == 0 ? Space.sm : Space.xs,
                    ),
                    if (i != lines - 1) const SizedBox(height: Space.xs),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing here — which, for a resident, is usually good news. Says what WOULD appear rather
/// than sitting blank: an empty list and a broken one look identical otherwise.
///
/// The standalone form is the design's empty-state card (4:1575): a raised card, an outlined
/// 54dp glyph, a title, a support line and at most one button. It replaces the tinted circle
/// and left-aligned sentence that were here, which came from the Stitch activity row and are
/// not a state treatment in this design at all.
///
/// [compact] keeps that older shape for the one job it is still right for — an empty section
/// INSIDE a card that already has its own heading, where a second card would be a card in a
/// card. The design has no such variant; the app has several.
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

  /// NULL IS THE COMMON CASE NOW, and it is the design's neutral outline rather than the green
  /// this used to default to. "Nothing recorded yet" is not good news; a reassuring green tick
  /// over it is the interface congratulating itself. Pass a tone only where empty genuinely
  /// means something.
  final Color? tone;

  /// The design's caps tag. Left off by default — 4:1577's own "EMPTY STATE" is the spec frame
  /// labelling its examples for a designer, not a word a resident should read.
  final String? badge;

  /// The design's one button (4:1586 — a hairline outlined box, not the cream filled one).
  /// Most empty states here have nothing useful to offer, and a button that does nothing is
  /// worse than no button.
  final Widget? action;

  /// An [EmptyArt] path drawn at 160dp INSTEAD of the outlined glyph square.
  ///
  /// Only the states a brand-new account lands on get one — see the note on
  /// [StateBody.illustration]. IGNORED WHEN [compact] IS SET: a compact note is an empty
  /// section inside a card that already has a heading, and 160dp of artwork in that slot would
  /// be larger than the card it is explaining. [icon] stays required either way, because it is
  /// both the compact drawing and what the artwork falls back to.
  final String? illustration;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? t.colorScheme.outline : context.tones.resolve(tone!);

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: IconSize.md, color: accent),
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

/// A failure, with the next step spelled out and a retry only where retrying could work.
///
/// THE RED PANEL IS GONE. The design's error card (4:1588) is the same raised, hairlined box as
/// the empty and skeleton states, and the red lives in the caps badge and nowhere else. On a
/// screen where one section failed and three did not, a red rectangle reads as "the app is
/// broken" rather than "this list did not load" — and on the home screen a resident sees
/// exactly that arrangement most of the time.
///
/// The retry is the CREAM FILLED BUTTON (4:1596), not the outlined one that was here. It is the
/// only action on the card, so it is the primary one.
class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;

  /// Inside a card that already has its own heading — the same exception [EmptyNote] makes.
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
      // A real word, not the mockup's "ERROR STATE". The tag SLOT is worth keeping — colour-
      // coding the state at a glance is genuinely useful — but what goes in it is English.
      badge: 'Error',
      tone: NivoraColors.error,
      child: StateBody(
        title: guidance.title,
        message: guidance.next,
        // Only where trying again could plausibly work. A retry under a permission refusal
        // teaches people to tap it forever.
        //
        // A DEAD SIGN-IN IS THE ONE CASE WITH A THIRD ANSWER. Retrying cannot help and there is
        // nobody to ask, but one tap fixes it — and a resident told "sign in again" with no way
        // to do it from here goes looking for their warden instead.
        action: AppFailure.from(error).needsSignIn
            ? const SignInAgainButton()
            : guidance.canRetry && onRetry != null
                ? FilledButton(
                    onPressed: onRetry,
                    // Width 0 so it hugs its label rather than inheriting the theme's full-bleed
                    // Size.fromHeight; the height stays at the 48dp tap target.
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: const Text('Try again'),
                  )
                : null,
      ),
    );
  }
}

/// Draws one of the three states for an [AsyncValue] without each screen re-deciding.
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({
    super.key,
    required this.value,
    required this.builder,
    this.loading,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // skipLoading… keeps the rows on screen through a pull-to-refresh instead of blanking a
    // list the resident is in the middle of reading.
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => loading ?? const SkeletonCard(),
      error: (error, _) => ErrorNote(error: error, onRetry: onRetry),
      data: builder,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL PRIMITIVES
// ─────────────────────────────────────────────────────────────────────────────

/// A section title, optionally with one action on the right.
///
/// [domain] puts the domain's coloured icon before the title — the saffron plate before
/// "Today's food", the blue megaphone before "Notices" — so a resident scrolling the home
/// screen finds a section by its colour before reading a word. Drawn at [DomainIconSize.sm],
/// the same 28dp plate the owner kit's `SectionHeading` and the SA kit's `SaHeading` put before
/// their own headings: one object is one size product-wide, and a heading is a title with a
/// mark beside it rather than a 40dp box with a title beside IT — three of those stacked down
/// the resident's home is the furniture outranking the data. The 40dp default stays where it
/// belongs, in a list tile's leading slot. See [NivoraDomain] for the rule.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
    this.domain,
    this.icon,
  });

  final String title;
  final String? caption;
  final Widget? trailing;

  /// Which area of the product this section belongs to. Null draws no icon.
  final NivoraDomain? domain;

  /// A glyph more specific than the domain's own. Ignored without [domain].
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          if (domain != null) ...[
            DomainIcon(domain: domain!, icon: icon, size: DomainIconSize.sm),
            const SizedBox(width: Space.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.textTheme.titleLarge),
                if (caption != null) ...[
                  const SizedBox(height: Space.xxs),
                  Text(caption!, style: t.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The fill a resting card paints in the current theme.
///
/// `surface-container-low` on dark, `surface` on light — [GlassWeight.thin] makes that decision
/// once for the whole app and this is the way a widget outside `shared/glass/` asks it. Anything
/// that has to sit flush with a card (an avatar's cut-out ring, a skeleton) reads it from here
/// rather than naming a hex.
Color cardSurfaceOf(BuildContext context) =>
    GlassWeight.thin.surfaceOf(Theme.of(context).colorScheme);

/// The fill a RAISED card paints — `surface raised` #171A1E on dark.
///
/// The design gives this rung to a specific short list, and one of them is on this screen:
/// "icon buttons (4:454), inputs (4:77), **the room card**, the activity feed's disc, the chart
/// panel". See [RaisedCard].
Color raisedSurfaceOf(BuildContext context) =>
    GlassWeight.regular.surfaceOf(Theme.of(context).colorScheme);

/// A plain bordered card.
///
/// Deliberately NOT glass. Glass marks one step of elevation, so a screen where every row is a
/// glass pane has flattened the very distinction the material exists to draw — and the glass
/// primitive asserts against that nesting for the same reason. One glass card per screen
/// carries the thing that matters; everything else sits quietly behind an outline.
///
/// IT IS ALWAYS FILLED NOW, AND ON THE DARK PALETTE THAT IS THE WHOLE CARD. It used to paint a
/// fill only when it was tappable, which made a notice (not tappable) an outline drawn straight
/// onto the ground and a complaint (tappable) a filled card, side by side on the home screen.
/// Nobody noticed on the old light palette, where the ground and the card were both near-white.
/// On the design's ground they are two different colours: a card is `surface-container-low`,
/// one rung up, and the hairline is the boundary of a surface rather than the surface itself.
/// [cardSurfaceOf] now fills every one of them — which is also what [SkeletonCard]'s own
/// doc-comment has always claimed happened here.
class OutlineCard extends StatelessWidget {
  const OutlineCard({super.key, required this.child, this.padding, this.onTap, this.accent});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// A coloured rail down the leading edge — the mockups' accented notice card.
  ///
  /// Pass a CANONICAL tone; it is resolved here. Null is the common case: a rail is an accent
  /// and a screen where every row has one has said nothing.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // The fill is on the Material, not in this decoration, so an ink splash lands ON the card
    // rather than under it. An opaque box over a Material's ink is how a tappable row stops
    // responding to the eye while still responding to the finger.
    Widget inner = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        // outlineVariant, not outline: this is a card's decorative edge, not a control's.
        border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      child: child,
    );

    if (accent != null) {
      // A positioned strip under the Material's clip, not a thicker BorderSide: a BoxDecoration
      // asserts that a border with unequal sides cannot carry a borderRadius, and a
      // square-cornered card here would be the one square thing on the screen.
      inner = Stack(
        children: [
          inner,
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            // The design's `border-l-4`.
            width: Space.xxs,
            child: ColoredBox(color: context.tones.resolve(accent!)),
          ),
        ],
      );
    }

    return Material(
      color: cardSurfaceOf(context),
      borderRadius: Radii.rCard,
      // Only where something actually overflows the corners. A clip layer on every row of a
      // long list is not free, and the splash is already clipped by the InkWell's own radius.
      clipBehavior: accent == null ? Clip.none : Clip.antiAlias,
      // A null onTap leaves the InkWell inert rather than absorbing the gesture.
      child: InkWell(borderRadius: Radii.rCard, onTap: onTap, child: inner),
    );
  }
}

/// A card one rung UP — `surface raised` #171A1E, with the same hairline.
///
/// Not a decoration: the design assigns this rung by name, and on `screen-student-dashboard`
/// the room card is one of the things it assigns it to (see [raisedSurfaceOf]). The rent card
/// above it stays on the card rung #111417, and the one-step difference is what makes the pair
/// read as "the figure that matters, and the fact underneath it" rather than as two cards.
///
/// In the light theme both rungs are white and the hairline does the separating, which is why
/// this is a WEIGHT and not a colour.
class RaisedCard extends StatelessWidget {
  const RaisedCard({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FlatSurface(
        weight: GlassWeight.regular,
        padding: padding ?? const EdgeInsets.all(Space.md),
        onTap: onTap,
        child: child,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// THE DESIGN'S CARD FURNITURE
//
// Four small pieces, each lifted from a specific construction in the Stitch markup rather than
// invented to look like it. They are here and not in `shared/` for the same reason the rest of
// this file is: the owner and warden apps have their own kit, and a resident's card says
// different things from a manager's.
// ─────────────────────────────────────────────────────────────────────────────

/// The small icon box in a card's top-right corner.
///
/// The design's `bg-surface-bright p-1.5 rounded-md text-{tone}` for the neutral case and
/// `bg-{tone}/10 p-1.5 rounded-md text-{tone}` for a semantic one — the two variants that appear
/// on every KPI card in `owner-dashboard.html`. It is decoration with a job: it says what KIND
/// of fact the card holds before the figure has been read.
///
/// THE NEUTRAL FILL IS `surfaceBright` #1D2227 IN THE DARK THEME. tokens.dart names that hex
/// as "the brightest fill in the file … what an icon badge sits on", and it has to be that hex
/// rather than the "chips and inputs" step this used to take: [RaisedCard] IS that step, so a
/// tile drawn at `surfaceContainerHighest` inside the room card was the same colour as the card
/// and simply disappeared. In the light theme `fromSeed` puts `surfaceBright` a hair off white
/// and it would vanish the other way, so there the tile keeps the chips-and-inputs grey. Both
/// come off the scheme.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.tone});

  final IconData icon;

  /// A CANONICAL tone, resolved here. Null paints the neutral tile with a primary glyph.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tones = context.tones;
    final accent = tone == null ? scheme.primary : tones.resolve(tone!);
    final neutral = scheme.brightness == Brightness.dark
        ? scheme.surfaceBright
        : scheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.all(Space.xs),
      decoration: BoxDecoration(
        color: tone == null ? neutral : tones.chipFill(accent),
        borderRadius: Radii.rControl,
      ),
      child: Icon(icon, size: IconSize.md, color: accent),
    );
  }
}

/// The round tinted glyph that opens a row in the design's activity lists.
///
/// `bg-{tone}/10 p-2 rounded-full text-{tone}` — the same recipe as [IconTile] in a circle,
/// which is what the markup uses to separate "a fact about a thing" (square, in a card's
/// corner) from "a thing that happened" (round, at the head of a row).
class ToneBadge extends StatelessWidget {
  const ToneBadge({super.key, required this.icon, this.tone});

  final IconData icon;

  /// A CANONICAL tone, resolved here. Null falls back to primary.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final accent =
        tone == null ? Theme.of(context).colorScheme.primary : tones.resolve(tone!);
    return Container(
      padding: const EdgeInsets.all(Space.xs),
      decoration: BoxDecoration(color: tones.chipFill(accent), shape: BoxShape.circle),
      child: Icon(icon, size: IconSize.sm, color: accent),
    );
  }
}

/// The design's `label-caps` — Inter 12/600 at +0.05em, uppercase.
///
/// A TextStyle cannot uppercase, so the string is uppercased here and callers pass it however
/// it reads best in source. This exists because four screens had grown their own
/// `Text('PROGRESS', style: labelSmall)` — hand-shouted strings at the CHIP step, one size
/// below the step `DESIGN-SYSTEM.md` reserves for exactly this job ("label-caps 12/600
/// UPPERCASE · section labels"; 10/600 is "badges, avatar initials"). One widget, so a section
/// label cannot be two different sizes on two different screens again.
class CapsLabel extends StatelessWidget {
  const CapsLabel(this.label, {super.key, this.tone});

  final String label;

  /// Resolved here if given. Null is the design's secondary ink, which is what a label is.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: t.textTheme.labelMedium
          ?.copyWith(color: tone == null ? null : context.tones.resolve(tone!)),
    );
  }
}

/// A card's top line: an uppercase eyebrow, and one thing on the right.
///
/// The design's `flex justify-between items-start` header, with the eyebrow at [CapsLabel]'s
/// 12/600.
class CardHeader extends StatelessWidget {
  const CardHeader({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            // Centres a one-line eyebrow against a 32dp icon tile without a Stack.
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              label.toUpperCase(),
              style: t.textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: Space.xs), trailing!],
      ],
    );
  }
}

/// The design's filled meter: `w-full bg-surface-bright h-1.5 rounded-full` with a tone fill.
///
/// A [LinearProgressIndicator] rather than two Containers, because the theme already describes
/// exactly this object — `linearTrackColor: surfaceContainerHighest`, `linearMinHeight: 6` —
/// so the channel is one edit away in `theme.dart` like every other surface in the app.
///
/// WHAT IT IS ALLOWED TO MEAN. [fraction] must be a ratio of two values the server returned,
/// and both of them must be stated as text somewhere on the same card. A meter is a graphic; it
/// is not permission to derive a figure that is not in the ledger.
class Meter extends StatelessWidget {
  const Meter({super.key, required this.fraction, required this.tone, this.semanticLabel});

  final double fraction;

  /// A CANONICAL tone, resolved here. The bar is a graphical object, so the canonical value
  /// would have been legal — it is resolved anyway so the bar and the pill above it are one
  /// colour rather than two shades of an argument.
  final Color tone;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: LinearProgressIndicator(
        value: fraction.clamp(0, 1),
        color: context.tones.resolve(tone),
        borderRadius: Radii.rPill,
      ),
    );
  }
}

/// The one or two letters that stand for a person when there is no photo.
///
/// `students.photo_url` is a Supabase Storage key that has to be signed before it can be
/// fetched and this app has no signing path, so every face in the resident app is initials. One
/// function, so the avatar beside a name on Profile and the cluster on the home room card can
/// never disagree about a person's mark.
String initialsOf(String? fullName) {
  final parts =
      (fullName ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}

/// One initials disc.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = _default});

  static const _default = Space.xxl; // 32

  /// Above this, the letters step up from an eyebrow to a title. Two 12px characters centred in
  /// a 52dp disc read as a typo rather than as a face.
  static const _largeAbove = Space.xxxl; // 40

  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // A COLOUR OF THEIR OWN, from the name — the way Google Contacts gives every face a hue,
    // so three roommates in a cluster are three people and not three gold discs. Stable across
    // screens and sessions (see [avatarToneFor]); the chip recipe, so it is measured.
    final tone = context.tones.resolve(avatarToneFor(name));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.tones.chipFill(tone),
      ),
      child: Text(
        initialsOf(name),
        style: (size >= _largeAbove ? t.textTheme.titleLarge : t.textTheme.labelSmall)
            ?.copyWith(color: tone),
        maxLines: 1,
      ),
    );
  }
}

/// The overlapping discs the mockups put beside a room's occupancy line.
///
/// NO NAME IS PRINTED, and no name is needed: the initials come from `st_my_roommates()`, which
/// is the same read the sentence beside it already counts. The ring is [cardSurfaceOf] so the
/// overlap reads as a cut-out in the card rather than as a grey halo.
class AvatarCluster extends StatelessWidget {
  const AvatarCluster({super.key, required this.names, this.max = 3, this.ring});

  final List<String> names;

  /// Beyond this the cluster stops adding discs. It is a texture, not a list.
  final int max;

  /// The surface the cluster is sitting ON, so the overlap reads as a cut-out. Defaults to the
  /// card rung; the room card passes [raisedSurfaceOf] because it is one rung up, and a ring in
  /// the wrong fill is a grey halo rather than a gap.
  final Color? ring;

  static const _disc = Space.xl; // 24
  static const _overlap = Space.xs; // 8

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    final shown = names.take(max).toList();
    final ring = this.ring ?? cardSurfaceOf(context);
    return SizedBox(
      height: _disc,
      width: _disc + (shown.length - 1) * (_disc - _overlap),
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: i * (_disc - _overlap),
              child: Container(
                padding: const EdgeInsets.all(Strokes.hairline),
                decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
                child: InitialsAvatar(name: shown[i], size: _disc - Strokes.hairline * 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// The quiet "see the rest of them" action beside a section title.
///
/// `text-primary text-label-caps` with a `chevron_right`, which is how the design draws every
/// one of these — VIEW ALL, VIEW REPORT. It is 12px uppercase Inter and NOT the app's 14px
/// button label: this is a link at the end of a heading, not a call to action.
class SeeAllButton extends StatelessWidget {
  const SeeAllButton({super.key, required this.onPressed, this.label = 'See all'});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        // The theme's 48dp minimum is for a CTA. This one hugs its label, and keeps the 44dp
        // height so it is still a tap target.
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.primary),
          ),
          Icon(Icons.chevron_right_rounded, size: IconSize.sm, color: t.colorScheme.primary),
        ],
      ),
    );
  }
}

/// A status word, tinted by meaning.
///
/// The WORD is always present, not just the colour. A pill that distinguishes paid from unpaid
/// by hue alone is unreadable to the roughly eight percent of men with a red-green deficiency —
/// which, in a full boys' PG, is several residents per floor.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.tone, this.icon});

  final String label;
  final Color tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    // [feeTone] and [complaintTone] are pure functions with no BuildContext, so what arrives
    // here is CANONICAL. Resolving at the paint site is the whole point of the tone system:
    // the caller keeps naming the meaning, this decides what is legible on today's theme.
    final accent = tones.resolve(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xxs),
      decoration: BoxDecoration(
        color: tones.chipFill(accent),
        borderRadius: Radii.rControl,
        border: Border.all(color: tones.chipBorder(accent), width: Strokes.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: IconSize.xs, color: accent),
            const SizedBox(width: Space.xxs),
          ],
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: t.textTheme.labelSmall?.copyWith(color: accent),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The same status word as a [StatusPill], with the chip taken off.
///
/// FOR ONE SITUATION ONLY: a surface that is already tinted with this tone. See
/// [NivoraSemantics.surfaceTintAlpha] — a chip's fill is a tint of its tone, so on a ground
/// that is already a tint of the same tone it lands twice as far toward its own label and the
/// pair measures 3.98:1 in the DARK theme, which no alpha rescues. (Light measures 5.03:1 and
/// could have kept its chip; it does not, because one widget cannot be two designs.) The
/// tinted GROUND is the chip; drawing a second one inside it is both the contrast failure and
/// a box inside a box.
///
/// What does not change is the part that matters: the status is still a WORD. Hue alone is
/// unreadable to the roughly eight percent of men with a red-green deficiency — several
/// residents per floor in a full boys' PG — and that guarantee belongs to the label, never to
/// the decoration around it.
///
/// On the tint, at the 10/600 chip step, this measures 4.56:1 at its worst across both themes.
class StatusWord extends StatelessWidget {
  const StatusWord({super.key, required this.label, required this.tone, this.icon});

  final String label;

  /// Canonical or resolved — resolved here, as everywhere else.
  final Color tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = context.tones.resolve(tone);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: IconSize.xs, color: accent),
          const SizedBox(width: Space.xxs),
        ],
        Flexible(
          child: Text(
            label.toUpperCase(),
            // The same labelSmall step the pill uses, so a tinted card and a pill state their
            // status in identical type and only the box differs.
            style: t.textTheme.labelSmall?.copyWith(color: accent),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The colour that carries a fee state's meaning. Defined once, so the home card and a history
/// row can never disagree about what "partly paid" looks like.
Color feeTone(FeeStatus status) => switch (status) {
      FeeStatus.paid => NivoraColors.success,
      FeeStatus.partial => NivoraColors.warning,
      FeeStatus.unpaid => NivoraColors.error,
    };

/// The same, for a complaint's progress.
Color complaintTone(ComplaintStatus status) => switch (status) {
      ComplaintStatus.open => NivoraColors.warning,
      ComplaintStatus.inProgress => NivoraColors.info,
      ComplaintStatus.resolved => NivoraColors.success,
    };

/// One labelled fact. Used by "My details" and the contact card.
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value, this.missing = 'Not recorded'});

  final String label;

  /// Null renders as [missing] rather than as an empty gap. "Not recorded" is information; a
  /// blank line looks like the app failed to load something.
  final String? value;
  final String missing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final shown = (value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Was a fixed 112dp. On a 320dp phone at 1.4x that left the value about 160dp, and
          // an address wrapped to five lines beside a one-word label. Flexes hand the extra
          // width to the half worth reading.
          Expanded(flex: 4, child: Text(label, style: t.textTheme.bodySmall)),
          const SizedBox(width: Space.sm),
          Expanded(
            flex: 6,
            // Selectable so a resident can copy their guardian's number or their own address
            // out of the app instead of retyping it.
            child: SelectionArea(
              child: Text(
                shown.isEmpty ? missing : shown,
                style: shown.isEmpty
                    ? t.textTheme.bodyMedium?.copyWith(color: context.tones.muted)
                    : t.textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE RESIDENT THEMSELVES
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves the signed-in resident's own `public.students` row once and hands it to [builder].
///
/// Every student screen needs it, because the hostel id that keys every other query lives on
/// that row — `students.hostel_id` is NOT NULL, and it is the value the RLS policies are
/// written against. Loading, failure and "no resident record" are therefore decided here once
/// instead of five times.
///
/// A STAFF ACCOUNT LANDING HERE GETS THE EMPTY STATE, NOT AN ERROR. `StudentRepository.me()`
/// returns null for anyone without a resident row, which is exactly what a warden opening this
/// route would be. Saying so plainly beats an exception that reads like a bug.
class ResidentBuilder extends ConsumerWidget {
  const ResidentBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, WidgetRef ref, Student me) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncSection<Student?>(
      value: ref.watch(myStudentProvider),
      onRetry: () => ref.invalidate(myStudentProvider),
      loading: const Padding(
        padding: EdgeInsets.all(Space.md),
        child: SkeletonCard(lines: 3),
      ),
      builder: (me) {
        if (me == null) {
          return const Padding(
            padding: EdgeInsets.all(Space.md),
            child: EmptyNote(
              icon: Icons.person_off_rounded,
              title: 'No resident record for this account',
              message: 'These screens are for residents. If you live here and are seeing this, '
                  'ask your warden to check your registration.',
              tone: NivoraColors.textMuted,
            ),
          );
        }
        return builder(context, ref, me);
      },
    );
  }
}

/// A drill-down page: the same body a tab shows, pushed with a back button.
///
/// The shell owns the bottom navigation and the header, so tab bodies draw neither. "See all"
/// therefore PUSHES rather than switching tabs — a resident who taps into their notices from
/// the home screen expects Back to return them home, not to be left on another tab with no
/// memory of how they got there.
class StudentPushPage extends StatelessWidget {
  const StudentPushPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          GlassHeader(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: Space.xxs),
                Expanded(
                  child: Text(title,
                      style: t.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
