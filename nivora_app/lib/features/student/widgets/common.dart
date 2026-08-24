library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';

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

/// A placeholder block, sized like the thing it stands in for.
///
/// A skeleton rather than a spinner: it keeps the layout the resident already knows and fills
/// it in, instead of replacing the screen with a grey void and then snapping back.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.widthFactor,
    this.height = Space.md - Space.xxs / 2,
  });

  final double? width;

  /// A share of the available width, for a placeholder that has to survive a 320dp screen.
  /// A fixed 160dp line looked like a paragraph on a wide phone and like a full row on a
  /// narrow one; a fraction reads as the same placeholder on both.
  final double? widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: Radii.rControl,
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
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 2});
  final int lines;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          borderRadius: Radii.rCard,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Skeleton(widthFactor: 0.35, height: Space.sm - Space.xxs / 2),
            const SizedBox(height: Space.sm),
            for (var i = 0; i < lines; i++) ...[
              Skeleton(widthFactor: i.isEven ? 1 : 0.6),
              if (i != lines - 1) const SizedBox(height: Space.xs),
            ],
          ],
        ),
      );
}

/// Nothing here — which, for a resident, is usually good news. Says what WOULD appear rather
/// than sitting blank: an empty list and a broken one look identical otherwise.
class EmptyNote extends StatelessWidget {
  const EmptyNote({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Defaults to the calm green of "nothing outstanding", which is what most empty states on
  /// these screens actually mean.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: IconSize.md,
                  color: context.tones.resolve(tone ?? NivoraColors.success)),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(title, style: t.textTheme.titleMedium)),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: Space.xxs),
            Text(message!, style: t.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// A failure, with the next step spelled out and a retry only where retrying could work.
class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final guidance = errorGuidance(error);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        // The tinted panel and its edge come from the one place the alphas were measured.
        // Canonical #DC3F3F painted here directly measured 3.79:1 as an icon on the dark
        // theme's elevated surface.
        color: tones.chipFill(NivoraColors.error),
        border: Border.all(color: tones.chipBorder(NivoraColors.error), width: Strokes.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: IconSize.md, color: tones.error),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(guidance.title, style: t.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(guidance.next, style: t.textTheme.bodySmall),
          if (guidance.canRetry && onRetry != null) ...[
            const SizedBox(height: Space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: IconSize.md),
                label: const Text('Try again'),
                // Width 0 so the button hugs its label instead of inheriting the theme's
                // full-bleed Size.fromHeight. The HEIGHT stays 48: it is still a tap target,
                // and the 40 that was here is below both Material's and Apple's minimum.
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
            ),
          ],
        ],
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
class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.caption, this.trailing});

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
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

/// A plain bordered card.
///
/// Deliberately NOT glass. Glass marks one step of elevation, so a screen where every row is a
/// glass pane has flattened the very distinction the material exists to draw — and the glass
/// primitive asserts against that nesting for the same reason. One glass card per screen
/// carries the thing that matters; everything else sits quietly behind an outline.
class OutlineCard extends StatelessWidget {
  const OutlineCard({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final body = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        border: Border.all(color: t.colorScheme.outlineVariant),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: t.colorScheme.surface,
      borderRadius: Radii.rCard,
      child: InkWell(borderRadius: Radii.rCard, onTap: onTap, child: body),
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
