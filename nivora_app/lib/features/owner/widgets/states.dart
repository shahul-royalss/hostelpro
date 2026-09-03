import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';
import '../../../shared/sign_in_again.dart';
import '../owner_insights.dart';
import 'meter.dart';

/// The three things a screen is doing when it is not showing data: loading, empty, or broken.
///
/// ALL THREE ARE DESIGNED, because all three are what a user actually sees on a bad morning.
/// A full-screen spinner throws away the layout the user already knows and replaces it with a
/// grey void; a skeleton keeps the shape and fills it in. An empty list that says nothing looks
/// identical to a list that failed. And an error that says "something went wrong" is a dead end
/// — every error here says what to do next, and only offers a retry when retrying could work
/// (see [errorGuidance]).
///
/// The shapes come from Figma node 4:1562, `screen-empty-error-skeleton`, which draws all
/// three on one frame. The primitives it specifies — [StateCard], [StateBadge], [StateBody] —
/// live in `shared/glass/glass.dart`; this file is where they meet the app's real states.

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
// SKELETONS
// ─────────────────────────────────────────────────────────────────────────────

/// ONE TICKER FOR EVERY SKELETON IN THE APP, AND IT STOPS WHEN NOBODY IS WATCHING.
///
/// A loading dashboard can hold a dozen placeholder bars. Giving each its own
/// `AnimationController` meant a dozen tickers, a dozen curve evaluations and a dozen
/// independent phases per frame, all to draw the same pulse — and every one of them kept
/// running when its tab was swapped out, because an `IndexedStack` keeps its children alive.
///
/// This is one [Ticker] shared by all of them, and it exists only while at least one skeleton
/// is subscribed: the last one to leave disposes it, so an app with nothing loading schedules
/// no frames at all. That also means `pumpAndSettle` in a widget test settles the moment the
/// data arrives, instead of spinning on a controller nothing is looking at.
///
/// A skeleton subscribes only while it is actually being PAINTED, which is a stronger test
/// than any flag the shells could set. [_PaintProbe] records the frame each bar was last drawn
/// on; a bar that has not been drawn for two frames unsubscribes itself, and re-subscribes the
/// moment it is drawn again. That covers every way a placeholder goes out of sight — an
/// `IndexedStack` tab that is laid out but never painted, a route underneath the top one, a
/// list item scrolled past — without any of those five shells having to know that skeletons
/// exist.
class _ShimmerClock {
  _ShimmerClock._();
  static final _ShimmerClock instance = _ShimmerClock._();

  /// The current pulse, [Dim.skeletonPulse] .. 1. Read by every subscribed [Skeleton].
  final ValueNotifier<double> pulse = ValueNotifier<double>(1);

  int _subscribers = 0;
  Ticker? _ticker;

  void attach() {
    _subscribers++;
    _ticker ??= Ticker(_tick)..start();
  }

  void detach() {
    if (_subscribers > 0) _subscribers--;
    if (_subscribers == 0) {
      _ticker?.dispose();
      _ticker = null;
      // [pulse] is deliberately NOT reset here. The last detach usually arrives from inside
      // its own listener, and writing the value there would re-enter notifyListeners. Nothing
      // reads it while unsubscribed anyway — a detached bar paints at full strength.
    }
  }

  void _tick(Duration elapsed) {
    // A triangle wave: up over [Motion.slow], down over the same, eased so the turn at each
    // end is not a corner.
    final period = Motion.slow.inMicroseconds * 2;
    final phase = (elapsed.inMicroseconds % period) / period;
    final triangle = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    pulse.value =
        Dim.skeletonPulse + (1 - Dim.skeletonPulse) * Motion.move.transform(triangle);
  }

  /// Test hook: how many skeletons are currently animating.
  @visibleForTesting
  int get subscribers => _subscribers;

  /// Test hook: whether the shared ticker exists at all.
  @visibleForTesting
  bool get running => _ticker != null;
}

/// Test-only view of the shared shimmer ticker, so `theme_contrast_test.dart` can prove that
/// an off-screen skeleton really does stop.
@visibleForTesting
({int subscribers, bool running}) shimmerClockState() =>
    (subscribers: _ShimmerClock.instance.subscribers, running: _ShimmerClock.instance.running);

/// A placeholder block, sized like the thing it stands in for.
///
/// The design's shimmer bar (4:1604, 4:1605, 4:1609, 4:1610) is `bg-[#1d2227] rounded-[4px]`
/// at 6, 8 or 14dp high — [NivoraColors.surfaceBright], which is 1.15:1 against the card it
/// sits on. That is a whisper on purpose: a placeholder that is easy to read is a placeholder
/// people try to read.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.widthFactor,
    this.height = Space.xs,
    this.radius = Radii.tiny,
  });

  final double? width;

  /// A share of the available width. A placeholder line pinned to 180dp reads as a short
  /// phrase on a wide phone and as a full row on a 320dp one; a fraction reads the same on
  /// both, which is the only thing a placeholder has to do.
  final double? widthFactor;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> {
  /// Two frames of grace. One is too tight — a frame in which the ancestor happened not to
  /// repaint is not the same as being off-screen — and anything longer leaves a hidden tab
  /// ticking for noticeably long after it is hidden.
  static const _grace = Duration(milliseconds: 40);

  bool _attached = false;
  bool _animationsAllowed = true;
  Duration _lastPainted = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode is not the visibility test — the paint probe is — but a subtree that has
    // explicitly had its tickers muted, or a user who has asked the OS to reduce motion, has
    // said no in a way worth honouring before the first frame is even drawn.
    _animationsAllowed = TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (!_animationsAllowed) _detach();
  }

  @override
  void dispose() {
    // No setState on the way out: the element is already defunct by the time dispose runs.
    _detach(rebuild: false);
    super.dispose();
  }

  void _attach() {
    if (_attached || !mounted) return;
    _attached = true;
    _ShimmerClock.instance.attach();
    _ShimmerClock.instance.pulse.addListener(_onPulse);
    setState(() {});
  }

  void _detach({bool rebuild = true}) {
    if (!_attached) return;
    _attached = false;
    _ShimmerClock.instance.pulse.removeListener(_onPulse);
    _ShimmerClock.instance.detach();
    if (rebuild && mounted) setState(() {});
  }

  /// Runs once per frame while subscribed. Rebuilds the bar at the new pulse, and notices when
  /// the bar has stopped being drawn.
  void _onPulse() {
    if (!mounted) return;
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    if (now - _lastPainted > _grace) {
      _detach();
      return;
    }
    setState(() {});
  }

  /// Called from the render object every time the bar is actually painted.
  void _onPainted() {
    _lastPainted = SchedulerBinding.instance.currentFrameTimeStamp;
    if (_attached || !_animationsAllowed) return;
    // Back in view. Starting the ticker from inside a paint would be legal but is the kind of
    // thing that bites later; the next frame is soon enough for a 340ms pulse.
    SchedulerBinding.instance.addPostFrameCallback((_) => _attach());
  }

  @override
  Widget build(BuildContext context) {
    // Alpha on the fill rather than an `Opacity` widget: a translucent colour inside a
    // BoxDecoration composites in place, where `Opacity` would push a saveLayer for every bar
    // on the screen, every frame.
    final opacity = _attached ? _ShimmerClock.instance.pulse.value : 1.0;
    Widget box = _PaintProbe(
      onPainted: _onPainted,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: NivoraColors.surfaceBright.withValues(alpha: opacity),
          borderRadius: BorderRadius.all(Radius.circular(widget.radius)),
        ),
      ),
    );
    if (widget.widthFactor != null) {
      box = FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widget.widthFactor,
        child: box,
      );
    }
    return box;
  }
}

/// Reports every paint of its child upwards. The cheapest honest answer to "is this on screen
/// right now?" — a render object that is laid out but never painted (an `IndexedStack`'s other
/// children, an `Offstage` route) simply never calls back.
class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({required this.onPainted, required super.child});

  final VoidCallback onPainted;

  @override
  _RenderPaintProbe createRenderObject(BuildContext context) =>
      _RenderPaintProbe(onPainted: onPainted);

  @override
  void updateRenderObject(BuildContext context, _RenderPaintProbe renderObject) {
    renderObject.onPainted = onPainted;
  }
}

class _RenderPaintProbe extends RenderProxyBox {
  _RenderPaintProbe({required this.onPainted});

  VoidCallback onPainted;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPainted();
    super.paint(context, offset);
  }
}

/// A skeleton in the shape of a card, for a section that has not arrived yet.
///
/// It is the REAL CARD with placeholder bars in it, not an outlined ghost of one, and its
/// anatomy is the design's own `skeleton-layout` (4:1602): a RAISED card carrying a short
/// title bar, then the pending content inside a block at the CARD fill one rung down. That
/// inner block is what makes the bars legible — #1D2227 on #111417 is the pairing Figma
/// draws, and on the raised surface alone the bars would all but vanish.
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
            // shimmer-title: 8dp high, a short fixed run.
            const Align(
              alignment: Alignment.centerLeft,
              child: Skeleton(width: 60, height: Space.xs),
            ),
            const SizedBox(height: Space.sm),
            FlatSurface(
              borderRadius: Radii.rControl,
              border: false,
              padding: const EdgeInsets.all(Space.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < lines; i++) ...[
                    // The first line is the value bar (14dp in the design); the rest are the
                    // 8dp text lines, alternating full width and short.
                    // The design's bars are 14 for a value and 8 for a text line; 12 and 8
                    // are the same two steps on the 4dp grid.
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

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY AND FAILED
// ─────────────────────────────────────────────────────────────────────────────

/// Nothing to show, and that is fine. Says what would appear here rather than sitting blank.
///
/// The standalone form is the design's empty-state card (4:1575): a raised card, an outlined
/// 54dp glyph, a 14/600 title, an 11/400 support line, and at most one button. [compact] drops
/// the card and the glyph for use inside a card that already has its own heading — the design
/// has no such variant, but half the empty states in this app are a section of a card rather
/// than the whole screen.
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
/// The design's error card (4:1588) is a RAISED card with a hairline — not a red-tinted panel,
/// which is what this used to be. The red lives in the caps badge and nowhere else, and the
/// retry is the cream filled button (4:1596). That is a quieter treatment than a full red box
/// and it is the right one: on a dashboard where one section failed and three did not, a red
/// rectangle reads as "the app is broken" rather than "this list did not load".
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
      tone: NivoraColors.error,
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

/// A small state pill. Tinted, never filled: a row of saturated chips turns a list into a bag
/// of sweets and stops any one of them meaning anything.
///
/// The recipe is the design's badge — a 10% wash of the tone with a full-strength 1px edge and
/// the label in the tone — and the alphas come from [NivoraSemantics], where the one tight
/// contrast case in the app is measured.
///
/// [dot] draws the mockups' leading status dot. Opt-in rather than always-on, because a dot
/// means "this is a live state": a chip that merely labels something ("On your dashboard")
/// does not get one.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone, this.dot = false});

  final String label;
  final Color tone;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    // Callers name the meaning with a canonical colour; the paint site picks the value that
    // is legible on this theme. See NivoraSemantics.resolve.
    final accent = tones.resolve(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xxs / 2),
      decoration: BoxDecoration(
        color: tones.chipFill(accent),
        borderRadius: Radii.rTiny,
        border: Border.all(color: tones.chipBorder(accent), width: Strokes.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: Space.xxs,
              height: Space.xxs,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: Space.xxs),
          ],
          Flexible(
            child: Text(
              label,
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

// ─────────────────────────────────────────────────────────────────────────────
// CARD ANATOMY — the three shapes every mockup in this area repeats.
// ─────────────────────────────────────────────────────────────────────────────
//
// Read off the Figma frames rather than invented. A card in this design is: a small uppercase
// eyebrow with an icon badge opposite it, then the figure, then one supporting line. Writing
// that once is what stops the four KPI cards drifting apart.

/// The design's icon holder — the 28dp `rounded-full` disc behind an activity glyph (4:517)
/// and the 32dp `rounded-[8px]` square behind the header's bell (4:454).
///
/// TWO FILLS, BOTH THE DESIGN'S OWN. The RAISED surface `#171A1E` where the badge is simply an
/// icon holder, and a tint of the tone itself where the colour is the point. The tint alpha is
/// [NivoraSemantics.chipFill]'s, so a badge and a chip carrying the same meaning are the same
/// weight of colour.
///
/// The neutral fill was `surfaceBright` (`#1D2227`) and is now `surfaceContainer` (`#171A1E`),
/// which is what Figma actually paints: the activity discs on 4:437 and the header's bell
/// button on 4:454 are both `#171A1E`, and DESIGN-SYSTEM.md lists that hex against "room card,
/// ICON BUTTONS". `#1D2227` is the design's skeleton-shimmer bar and belongs to [Skeleton].
class ToneBadge extends StatelessWidget {
  const ToneBadge({
    super.key,
    required this.icon,
    this.tone,
    this.circular = false,
    this.tinted = false,
  });

  final IconData icon;

  /// Canonical or scheme colour, resolved here to this theme's legible value. Null is the
  /// theme's primary — the design's own default for a badge that means nothing in particular.
  final Color? tone;

  /// `rounded-full` rather than the square: the activity feed's disc, not a header button.
  final bool circular;

  /// Fill with a tint of [tone] instead of the neutral holder.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = context.tones.resolve(tone ?? scheme.primary);
    return Container(
      padding: const EdgeInsets.all(Space.xs),
      decoration: BoxDecoration(
        color: tinted ? context.tones.chipFill(accent) : scheme.surfaceContainer,
        borderRadius: circular ? Radii.rPill : Radii.rControl,
      ),
      child: Icon(icon, size: IconSize.xs, color: accent),
    );
  }
}

/// A card's own header: the uppercase eyebrow on the left, its icon badge on the right.
///
/// The eyebrow is uppercased here rather than at every call site, because a TextStyle cannot
/// do it and forgetting once is a card that reads as a sentence in the middle of a grid.
class CardEyebrow extends StatelessWidget {
  const CardEyebrow({
    super.key,
    required this.label,
    this.icon,
    this.tone,
    this.tinted = false,
    this.trailing,
  });

  final String label;

  /// The badge's glyph. Omitted for a card the design gives no badge.
  final IconData? icon;
  final Color? tone;
  final bool tinted;

  /// Anything that goes where the badge would — a chevron on a card that opens something.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            // The badge is taller than the label; this drops the label onto its optical centre
            // rather than pinning it to the top of a 30dp box.
            padding: const EdgeInsets.only(top: Space.xxs),
            child: Text(
              label.toUpperCase(),
              style: t.textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: Space.xs),
        if (trailing != null)
          trailing!
        else if (icon != null)
          ToneBadge(icon: icon!, tone: tone, tinted: tinted),
      ],
    );
  }
}

/// A person, as a circle — initials on a tinted disc with the design's hairline ring.
///
/// INITIALS, NOT A PHOTO. The mockups show head-and-shoulders portraits; `public.users` has no
/// avatar column and nothing in this app uploads one, so a photo here could only be a stock
/// face standing in for a real employee. The initials are derived from `full_name`, which is a
/// value the database actually holds.
///
/// The ring is the design's `#292E33` hairline — Figma's own note is "hairline: every card
/// border, dividers, avatar discs" — and not a tint of the tone, which at full strength would
/// put a coloured ring around every face in a staff list.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.tone, this.muted = false});

  final String name;
  final Color? tone;

  /// For somebody who no longer has access: the disc goes neutral rather than branded.
  final bool muted;

  /// Up to two initials from a full name. Falls back to a single glyph rather than to an empty
  /// circle, because a blank disc looks like a failed image load.
  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return (words.first.characters.first + words.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // No tone given: a colour of THEIR OWN, from the name, so a staff list is a list of people
    // rather than a column of identical gold discs. Stable across screens — see [avatarToneFor].
    // A caller that passes a tone is saying something about the person (a payment's state,
    // say) and keeps it.
    final accent =
        muted ? context.tones.muted : context.tones.resolve(tone ?? avatarToneFor(name));
    return Container(
      width: Space.xxxl,
      height: Space.xxxl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.tones.chipFill(accent),
        border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      child: Text(
        initialsOf(name),
        style: t.textTheme.labelSmall?.copyWith(color: accent),
      ),
    );
  }
}

/// The design's section label: a caps eyebrow on the page ground, above the block it names.
///
/// 4:437 and 4:536 both use it — `30-DAY CASH FLOW`, `RECENT ACTIVITY`, `REGISTERED HOSTELS`,
/// `STAFF & ACCESS`. It is what replaced a `title-lg` heading INSIDE a card on these screens:
/// the design's sections are labelled from outside, which is what lets the chart well and the
/// activity rows sit on the ground instead of each needing a card to hang a title on.
///
/// ── THE ONE COLOUR NOT COPIED ────────────────────────────────────────────────────────────
///
/// Figma paints these `#6F747A` ([ColorScheme.outline]). MEASURED, that is 4.13:1 on the page
/// ground and 3.92:1 on a card — a fail at 12px, which is not large text by any definition
/// WCAG offers. Hard rule 6 says fix the colour, never the assertion, so the label is painted
/// `#A2A6AB` (`onSurfaceVariant`, 7.55:1 on a card) — the same secondary the type scale already
/// gives `labelMedium`. It is one step brighter than the mockup and legible on a phone in
/// daylight, which the mockup's own value is not.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label, this.trailing});

  /// Uppercased here, because a TextStyle cannot do it and forgetting once is a section that
  /// reads as a sentence in a column of labels.
  final String label;

  /// The design's right-hand slot: the cash-flow legend on 4:437.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final text = Text(
      label.toUpperCase(),
      style: t.textTheme.labelMedium,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      // NO TRAILING: a bare Text, which the column above bounds, so a long label soft-wraps.
      //
      // WITH A TRAILING: a Wrap rather than `Row(Expanded(text), trailing)`. A non-flex child
      // of a Row is laid out against infinity, so the cash-flow legend never shrank — it just
      // overflowed the label row by 38 pixels at 1.4x on a 320dp phone. A Wrap pushes the two
      // apart while they both fit and drops the trailing onto its own line when they do not,
      // which is the right answer for a key: it belongs beside its heading, and failing that,
      // under it — never clipped.
      child: trailing == null
          ? text
          : Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.sm,
              runSpacing: Space.xxs,
              children: [text, trailing!],
            ),
    );
  }
}

/// One cell of the design's 2×2 KPI grid — Figma 4:437's own card, top to bottom.
///
/// ANATOMY, MEASURED OFF THE FRAME: a 175dp card at [Radii.rCard] with [Space.sm] padding,
/// carrying a caps eyebrow, the figure at 20/700 (`headlineMedium`, cap height 14px in the
/// export), one supporting line at 11/400, and — on the two cards that are a share of
/// something — a meter with its percentage trailing it in the meter's own tone.
///
/// [valueTone] IS THE MOCKUP'S OWN COLOUR CODING and it is information, not decoration: two of
/// the four figures are cream because they are simply counts, one is red because it is money
/// nobody has paid, one is amber because it is work nobody has done. Passing a tone for a
/// figure that is merely large would spend the only colour signal this grid has.
///
/// [meta] is optional. A card whose second fact does not exist in the schema shows the figure
/// and stops, rather than filling the slot with a sentence the database cannot support.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.valueTone,
    this.meta,
    this.meterValue,
    this.meterTone,
    this.showMeterPercent = true,
    this.trailing,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
  final String value;

  /// Canonical or scheme colour, resolved at paint. Null leaves the figure in the primary ink.
  final Color? valueTone;
  final String? meta;

  /// 0.0–1.0, or null for a card that is not a share of anything. Null draws no meter.
  final double? meterValue;
  final Color? meterTone;
  final bool showMeterPercent;

  /// The eyebrow's right-hand slot — a chevron on a card that opens something.
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    // ═══ A TONED FIGURE TINTS ITS OWN TILE ═══
    //
    // [valueTone] is already set only where the number means something — the dashboard's own
    // rule is "two of the four values are cream because they are counts; pending fees is red
    // and open complaints is amber because those two cost the owner something". So the tint
    // carries no new claim: it is the colour that was on the figure, spread to the card, and
    // the two tiles that are merely counting stay plain. That is the opposite of the rainbow
    // grid [GlassStatCard] warns about — it is what makes the two that matter separate from
    // the two that do not.
    //
    // NO RAIL. A 4dp strip inside a half-width tile padded at 12 spends a third of the gutter
    // on decoration; the rail is for full-width cards.
    //
    // There is no chip on this tile, so the rule in [NivoraSemantics.surfaceTintAlpha] is not
    // in play. Do not add one.
    //
    // AN UNTINTED TILE IS STILL A [GlassSurface], which is what it has always been. That is not
    // a cosmetic detail: GlassSurface is the half of the pane layer that tracks nesting depth
    // and asserts when one pane is put inside another, and a plain tile dropped into a card
    // would otherwise be the same hex as the card and simply vanish. A tinted tile has its own
    // fill and cannot disappear that way, so it does not need the guard.
    if (valueTone == null) {
      return GlassSurface(
        // `p-3` on the frame: 12dp, not the 16 a full-width card gets. Half-width cards spend
        // their padding on nothing, and at 1.4x text the figure needs the room.
        padding: const EdgeInsets.all(Space.sm),
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: body,
      );
    }
    return ToneSurface(
      tone: valueTone,
      rail: false,
      // `p-3` on the frame: 12dp, not the 16 a full-width card gets. Half-width cards spend
      // their padding on nothing, and at 1.4x text the figure needs the room.
      padding: const EdgeInsets.all(Space.sm),
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: body,
    );
  }

  /// The tile's contents, identical whichever surface ends up behind them. Split out so the
  /// tinted and untinted branches cannot drift into two slightly different tiles.
  Widget _body(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CardEyebrow(label: label, trailing: trailing),
        const SizedBox(height: Space.xs),
        Text(
          value,
          style: t.textTheme.headlineMedium?.copyWith(
            color: valueTone == null ? null : context.tones.resolve(valueTone!),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (meta != null) ...[
          const SizedBox(height: Space.xxs),
          Text(meta!, style: t.textTheme.bodySmall),
        ],
        if (meterValue != null) ...[
          const SizedBox(height: Space.sm),
          ProportionMeter(
            value: meterValue,
            tone: meterTone,
            showPercent: showMeterPercent,
            // The card already carries a semantic label naming this figure; a second one on
            // the bar inside it would read the same fact twice.
            semanticLabel: null,
          ),
        ],
      ],
    );
  }
}

/// A section title, optionally with one action on the right.
///
/// [domain] puts the domain's coloured icon before the title, so an owner finds a section by
/// its colour before reading a word. Drawn at [DomainIconSize.sm] — the same 28dp plate the SA
/// kit's `SaHeading` puts before its own headings, so one object is one size product-wide and
/// the icon marks the title rather than outgrowing it. See [NivoraDomain] for the rule that
/// keeps it honest.
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
