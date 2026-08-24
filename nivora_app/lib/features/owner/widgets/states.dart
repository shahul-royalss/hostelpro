import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../owner_insights.dart';

/// The three things a screen is doing when it is not showing data: loading, empty, or broken.
///
/// ALL THREE ARE DESIGNED, because all three are what a user actually sees on a bad morning.
/// A full-screen spinner throws away the layout the user already knows and replaces it with a
/// grey void; a skeleton keeps the shape and fills it in. An empty list that says nothing looks
/// identical to a list that failed. And an error that says "something went wrong" is a dead end
/// — every error here says what to do next, and only offers a retry when retrying could work
/// (see [errorGuidance]).

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

/// A placeholder block, sized like the thing it stands in for.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = Radii.control,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: Motion.slow,
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.outlineVariant;
    final box = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
    // A user who has asked the OS to reduce motion has usually asked for a reason. The
    // placeholder still appears; it just stops breathing.
    if (MediaQuery.disableAnimationsOf(context)) return box;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _pulse, curve: Motion.move),
      ),
      child: box,
    );
  }
}

/// A skeleton in the shape of a card, for a section that has not arrived yet.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 2, this.height});

  final int lines;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Skeleton(width: 96, height: 10),
          const SizedBox(height: Space.sm),
          for (var i = 0; i < lines; i++) ...[
            Skeleton(width: i.isEven ? double.infinity : 180, height: 14),
            if (i != lines - 1) const SizedBox(height: Space.xs),
          ],
        ],
      ),
    );
  }
}

/// Nothing to show, and that is fine. Says what would appear here rather than sitting blank.
class EmptyNote extends StatelessWidget {
  const EmptyNote({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.compact = false,
    this.tone,
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? Space.sm : Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: tone ?? t.colorScheme.outline),
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

/// A failure, with the next step spelled out.
class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final guidance = errorGuidance(error);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        border: Border.all(color: NivoraColors.error.withValues(alpha: 0.35)),
        color: NivoraColors.error.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, size: 18, color: NivoraColors.error),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(guidance.title, style: t.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(guidance.next, style: t.textTheme.bodySmall),
          // The button appears only when trying again could plausibly work. Offering a retry
          // for a permission refusal teaches people to tap it forever.
          if (guidance.canRetry && onRetry != null && !compact) ...[
            const SizedBox(height: Space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small state pill. Tinted, never filled: a row of saturated chips turns a list into a bag
/// of sweets and stops any one of them meaning anything.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xxs / 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: Radii.rControl,
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      child: Text(label, style: t.textTheme.labelSmall?.copyWith(color: tone)),
    );
  }
}

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
        crossAxisAlignment: CrossAxisAlignment.start,
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
