library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/illustrations.dart';
import '../../../shared/sign_in_again.dart';

/// The small kit every student screen is built from.
///
/// Kept inside this feature rather than in `shared/` on purpose: the owner and warden apps have
/// their own, and their wording is written for staff. A resident is not a colleague of the
/// warden — "ask your warden" is the right next step here and the wrong one there — so the copy
/// diverges even where the shape does not.
///
/// THE SHAPES ARE THE CLAY KIT'S NOW. Cards are the card fill at the surface radius with a
/// hairline, empty and failed states are [EmptyState] with clay art, status words are
/// [StatusChip]s and avatars are [InitialsDisc]s — so a resident's screens and an owner's are
/// visibly one product. What stays here is the resident's half: the words, and the few
/// constructions only these screens need.

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
        next: 'Your phone cannot reach Apnivaas. Check your Wi-Fi or mobile data and try again.',
        canRetry: true,
      ),
    ServerFailure() => (
        title: 'Apnivaas is busy',
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
/// THE CLAY KIT'S FILL, HELD STILL. The colour is the one the kit's own skeleton bars use — the
/// warm `skeleton` beige on a card in light, the raised surface in dark — at the kit's pill
/// corner. What it leaves out is [SkeletonPulse]: a looping animation never settles, and these
/// placeholders sit on screens whose every test waits for the frame to settle. A still bar says
/// "not here yet" just as plainly. Named for that difference, so it never shadows the kit's own
/// [Skeleton], which pulses.
class StillSkeleton extends StatelessWidget {
  const StillSkeleton({
    super.key,
    this.width,
    this.widthFactor,
    this.height = Space.sm,
    this.radius,
    this.circle = false,
  });

  final double? width;

  /// A share of the available width, for a placeholder that has to survive a 320dp screen.
  /// A fixed 160dp line looked like a paragraph on a wide phone and like a full row on a
  /// narrow one; a fraction reads as the same placeholder on both.
  final double? widthFactor;

  /// A text line is [Space.sm]; a figure is taller. The kit's bars are pills, so the corner
  /// follows the height unless [radius] says otherwise.
  final double height;
  final double? radius;

  /// A disc the size of [height] — the stand-in for a 46dp clay icon or an avatar.
  final bool circle;

  /// The fill: the kit's own block colour for this theme, so the two cannot drift apart.
  static Color barColor(BuildContext context) => Skeleton.colorOf(context);

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: barColor(context),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius:
            circle ? null : BorderRadius.all(Radius.circular(radius ?? height / 2)),
      ),
    );
    if (widthFactor == null || circle) return box;
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: box,
    );
  }
}

/// A card-shaped placeholder for a section that has not arrived yet.
///
/// Drawn in the shape most of these sections arrive as — a clay icon's disc and two lines of
/// words, on the same card a list row sits on — so the screen does not change shape when the
/// data lands. [lines] beyond two become full-width lines beneath, for the taller cards (the
/// rent card, a day of the menu).
///
/// One "Loading" for a screen reader, rather than a run of unlabelled boxes.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 2, this.height});

  final int lines;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Loading',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: Radii.rSurface,
          border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
          child: SizedBox(
            height: height,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    StillSkeleton(height: ClaySize.list, circle: true),
                    SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StillSkeleton(widthFactor: 0.6),
                          SizedBox(height: Space.xs),
                          StillSkeleton(widthFactor: 0.4),
                        ],
                      ),
                    ),
                  ],
                ),
                for (var i = 2; i < lines; i++) ...[
                  const SizedBox(height: Space.sm),
                  StillSkeleton(widthFactor: i.isEven ? 1 : 0.7),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Nothing here — which, for a resident, is usually good news. Says what WOULD appear rather
/// than sitting blank: an empty list and a broken one look identical otherwise.
///
/// THE KIT'S EMPTY STATE: clay art on a Mist disc, a title, one helpful sentence and at most one
/// button. [clay] names the art; a first-run state can name its [EmptyArt] state through
/// [illustration] instead, and gets the art drawn for that state. The words are always real
/// Text, never baked into the picture.
///
/// [icon] is the fallback — a glyph on the same Mist disc, for a caller that names no art. Every
/// screen in this feature names some.
///
/// [compact] is the small form, for an empty section inside a sheet or a card that already has
/// its own heading.
class EmptyNote extends StatelessWidget {
  const EmptyNote({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.compact = false,
    this.action,
    this.illustration,
    this.clay,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Inside a sheet or a card that already has its own heading.
  final bool compact;

  /// The one button. Most empty states here have nothing useful to offer, and a button that
  /// does nothing is worse than no button.
  final Widget? action;

  /// An [EmptyArt] state name. The art drawn is [EmptyArt.clayFor] of it.
  final String? illustration;

  /// A [ClayIcons] path. Wins over [illustration] when both are given.
  final String? clay;

  @override
  Widget build(BuildContext context) {
    final art = clay ?? (illustration == null ? null : EmptyArt.clayFor(illustration!));
    if (art != null) {
      return EmptyState(
        icon: art,
        title: title,
        body: message,
        action: action,
        compact: compact,
      );
    }
    return _GlyphEmpty(
      icon: icon,
      title: title,
      message: message,
      action: action,
      compact: compact,
    );
  }
}

/// [EmptyState]'s anatomy with a glyph where the clay art would be.
class _GlyphEmpty extends StatelessWidget {
  const _GlyphEmpty({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final disc = compact ? ClaySize.tile : ClaySize.promo;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: EmptyState.maxWidth),
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
                  child: Icon(
                    icon,
                    size: compact ? IconSize.action : IconSize.xl,
                    color: t.colorScheme.primary,
                  ),
                ),
              ),
              SizedBox(height: compact ? Space.sm : Space.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: compact ? t.textTheme.titleMedium : t.textTheme.headlineSmall,
              ),
              if (message != null) ...[
                const SizedBox(height: Space.tight),
                Text(message!, textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
              ],
              if (action != null) ...[
                SizedBox(height: compact ? Space.md : Space.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A failure, with the next step spelled out and a retry only where retrying could work.
///
/// THE KIT'S ERROR STATE, WITH THIS FEATURE'S WORDS. The title and the sentence come from
/// [errorGuidance], so the honesty lives in one switch; the drawing is [EmptyState]'s — clay
/// art, a headline, the sentence and at most one button — and no red panel. On a screen where
/// one section failed and three did not, a red rectangle reads as "the app is broken" rather
/// than "this did not load".
///
/// The retry is the FILLED button: it is the only action in the state, so it is the primary
/// one.
///
/// [compact] is the inline form, for a failure inside a form or a sheet — a full-size state
/// there would push the fields the resident was typing into off the screen.
class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;

  /// Inline, inside a form or a sheet.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final guidance = errorGuidance(error);

    // Only where trying again could plausibly work. A retry under a permission refusal teaches
    // people to tap it forever.
    //
    // A DEAD SIGN-IN IS THE ONE CASE WITH A THIRD ANSWER. Retrying cannot help and there is
    // nobody to ask, but one tap fixes it — and a resident told "sign in again" with no way to
    // do it from here goes looking for their warden instead.
    final Widget? action = AppFailure.from(error).needsSignIn
        ? const SignInAgainButton()
        : guidance.canRetry && onRetry != null
            ? FilledButton(onPressed: onRetry, child: const Text('Try again'))
            : null;

    if (compact) {
      return _InlineError(title: guidance.title, message: guidance.next, action: action);
    }
    return EmptyState(
      icon: ClayIcons.complaint,
      title: guidance.title,
      body: guidance.next,
      action: action,
    );
  }
}

/// The inline failure: the error ink's glyph and words on a well, under the field they are
/// about.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.title, required this.message, this.action});

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // The neutral well rather than a red wash: the glyph and the title carry the state,
          // and the sentence stays in the ordinary ink where it is easiest to read.
          color: t.colorScheme.surfaceContainer,
          borderRadius: Radii.rButton,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, size: IconSize.lg, color: tones.error),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: t.textTheme.titleSmall?.copyWith(color: tones.error)),
                    const SizedBox(height: Space.xxs),
                    Text(message, style: t.textTheme.bodyMedium),
                    if (action != null) ...[
                      const SizedBox(height: Space.sm),
                      Align(alignment: AlignmentDirectional.centerStart, child: action),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
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

/// The fill a resting card paints in the current theme — the card in light, one rung up in
/// dark. [GlassWeight.thin] makes that decision once for the whole app; anything that has to
/// sit flush with a card (an avatar's cut-out ring) reads it from here rather than naming a hex.
Color cardSurfaceOf(BuildContext context) =>
    GlassWeight.thin.surfaceOf(Theme.of(context).colorScheme);

/// A plain card: the card fill at the surface radius, with a hairline.
///
/// FLAT, AS EVERY RESTING CARD IN THE KIT IS. Elevation is spent on the bar and the sheets;
/// a list of shadowed cards is a list of things shouting over each other.
///
/// The fill is on the Material, not in a decoration over it, so an ink splash lands ON the
/// card rather than under it. A null [onTap] leaves the InkWell inert rather than absorbing the
/// gesture — and a card that cannot be tapped draws no ripple, because a ripple promises
/// something will happen.
class OutlineCard extends StatelessWidget {
  const OutlineCard({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: cardSurfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.rSurface,
        // outlineVariant, not outline: this is a card's decorative edge, not a control's.
        side: BorderSide(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(Space.md),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

/// The design's filled meter: a 7dp pill on the warm track, filled in the state's ink.
///
/// WHAT IT IS ALLOWED TO MEAN. [fraction] must be a ratio of two values the server returned,
/// and both of them must be stated as text somewhere on the same card. A meter is a graphic; it
/// is not permission to derive a figure that is not in the ledger.
class Meter extends StatelessWidget {
  const Meter({super.key, required this.fraction, required this.tone, this.semanticLabel});

  final double fraction;

  /// A CANONICAL tone, resolved here — so the bar and the chip above it are one colour rather
  /// than two shades of an argument.
  final Color tone;

  final String? semanticLabel;

  static const _height = 7.0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bar = ClipRRect(
      borderRadius: Radii.rPill,
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: dark ? ApnivaasColors.surfaceContainerHighest : ApnivaasColors.track,
              ),
            ),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              heightFactor: 1,
              alignment: AlignmentDirectional.centerStart,
              child: ColoredBox(color: context.tones.resolve(tone)),
            ),
          ],
        ),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: bar);
    return Semantics(label: semanticLabel, excludeSemantics: true, child: bar);
  }
}

/// The overlapping discs the mockups put beside a room's occupancy line.
///
/// NO NAME IS PRINTED, and no name is needed: the initials come from `st_my_roommates()`, which
/// is the same read the sentence beside it already counts. The ring is the surface the cluster
/// sits on, so the overlap reads as a cut-out in the card rather than as a grey halo.
class AvatarCluster extends StatelessWidget {
  const AvatarCluster({super.key, required this.names, this.max = 3, this.ring});

  final List<String> names;

  /// Beyond this the cluster stops adding discs. It is a texture, not a list.
  final int max;

  /// The surface the cluster is sitting ON. Defaults to the card.
  final Color? ring;

  static const _disc = Space.xxl; // 32
  static const _overlap = Space.sm; // 12

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    final shown = names.take(max).toList();
    final ring = this.ring ?? cardSurfaceOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: _disc,
        width: _disc + (shown.length - 1) * (_disc - _overlap),
        child: Stack(
          children: [
            for (var i = shown.length - 1; i >= 0; i--)
              PositionedDirectional(
                start: i * (_disc - _overlap),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
                  child: Padding(
                    padding: const EdgeInsets.all(Strokes.focus),
                    child: InitialsDisc(name: shown[i], size: _disc - Strokes.focus * 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A status word, tinted by meaning — the kit's [StatusChip], in capitals.
///
/// The WORD is always present, not just the colour. A pill that distinguishes paid from unpaid
/// by hue alone is unreadable to the roughly eight percent of men with a red-green deficiency —
/// which, in a full boys' PG, is several residents per floor.
///
/// CAPITALS, AND ONE CASE FOR EVERY CHIP IN THE RESIDENT'S APP. The rent states are matched by
/// that case in tests outside this feature (UNPAID, PARTLY PAID, PAID), and a resident who saw
/// "PAID" on the rent card and "In progress" on a complaint would be reading two systems. So
/// every chip here takes the same case from one place.
///
/// [tone] is CANONICAL — [feeTone] and [complaintTone] are pure functions with no
/// BuildContext — and the chip resolves it for today's theme.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.dot = false,
  });

  final String label;
  final Color tone;
  final IconData? icon;

  /// The kit's leading dot, for a chip that sits in a dense row.
  final bool dot;

  @override
  Widget build(BuildContext context) => StatusChip(
        label: label.toUpperCase(),
        tone: StatusTone.fromCanonical(tone),
        icon: icon,
        dot: dot,
      );
}

/// The colour that carries a fee state's meaning. Defined once, so the home card and a history
/// row can never disagree about what "partly paid" looks like.
Color feeTone(FeeStatus status) => switch (status) {
      FeeStatus.paid => ApnivaasColors.success,
      FeeStatus.partial => ApnivaasColors.warning,
      FeeStatus.unpaid => ApnivaasColors.error,
    };

/// The same, for a complaint's progress.
Color complaintTone(ComplaintStatus status) => switch (status) {
      ComplaintStatus.open => ApnivaasColors.warning,
      ComplaintStatus.inProgress => ApnivaasColors.info,
      ComplaintStatus.resolved => ApnivaasColors.success,
    };

/// One labelled fact. Used by "My details".
///
/// The label is the quiet half and the value the one worth reading, so the value takes the
/// ink and the weight. A divider between facts is the card's business, not the row's.
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
    final labelText = Text(
      label,
      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
    );
    // Selectable so a resident can copy their guardian's number or their own address out of
    // the app instead of retyping it.
    final valueText = SelectionArea(
      child: Text(
        shown.isEmpty ? missing : shown,
        style: shown.isEmpty
            ? t.textTheme.bodyMedium?.copyWith(color: context.tones.muted)
            : t.textTheme.titleSmall?.copyWith(fontFeatures: const []),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: LayoutBuilder(
        builder: (context, box) {
          // Side by side while there is room for both halves to read; stacked once large text
          // would leave the value a sliver. Was a fixed 112dp label once — on a 320dp phone at
          // 1.4x an address wrapped to five lines beside a one-word label.
          final stacked = box.maxWidth < 260 || MediaQuery.textScalerOf(context).scale(1) >= 1.6;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [labelText, const SizedBox(height: Space.xxs), valueText],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: labelText),
              const SizedBox(width: Space.sm),
              Expanded(flex: 6, child: valueText),
            ],
          );
        },
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
///
/// EVERY STATE HERE SCROLLS. These three are drawn straight into a tab body, under the header
/// and over the bar, and at 2.0x text on a 320dp phone a failure's art and sentence are taller
/// than the space between them. A list cannot overflow; it scrolls.
class ResidentBuilder extends ConsumerWidget {
  const ResidentBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, WidgetRef ref, Student me) builder;

  static const _padding = EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxxl);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget scroll(Widget child) => ListView(
          padding: _padding,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [child],
        );
    // The cold first paint: a page's worth of placeholders — a tall card and two rows — so the
    // screen arrives at roughly the shape it is about to have, rather than one card adrift.
    const firstPaint = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonCard(lines: 4),
        SizedBox(height: Space.sm),
        SkeletonCard(),
        SizedBox(height: Space.sm),
        SkeletonCard(),
      ],
    );
    // The same three branches [AsyncSection] draws, spelled out so each can be put inside the
    // list — and with the same two flags, so a refresh keeps the screen instead of blanking it.
    return ref.watch(myStudentProvider).when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => scroll(firstPaint),
          error: (error, _) => scroll(
            ErrorNote(error: error, onRetry: () => ref.invalidate(myStudentProvider)),
          ),
          data: (me) {
            if (me == null) {
              return scroll(
                const EmptyNote(
                  clay: ClayIcons.roleTenant,
                  icon: Icons.person_off_rounded,
                  title: 'No resident record for this account',
                  message: 'These screens are for residents. If you live here and are seeing '
                      'this, ask your warden to check your registration.',
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
///
/// The page wears the forest header every screen in the app does, with the back button in its
/// leading slot, so a pushed page reads as a deeper level of the same app rather than a
/// different one.
class StudentPushPage extends StatelessWidget {
  const StudentPushPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader(title: title, leading: const HeaderBackButton()),
          Expanded(child: child),
        ],
      ),
    );
  }
}
