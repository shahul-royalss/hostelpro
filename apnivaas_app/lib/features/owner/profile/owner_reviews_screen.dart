/// Owner → PG profile → Reviews (R5): what residents say about one PG, newest first, twenty at
/// a time. Owners read reviews; they cannot change or delete them (docs/round3-api.md §5.3).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/pg_profile.dart';
import '../../../data/repositories/pg_profile_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../../common/form_parts.dart';
import '../../student/pg/pg_profile_page.dart' show ReviewCard;
import '../../student/pg/pg_widgets.dart';
import '../../student/stay_screens.dart' show stayErrorText;
import '../widgets/owner_header.dart';

class OwnerReviewsScreen extends ConsumerStatefulWidget {
  const OwnerReviewsScreen({super.key, required this.hostelId});

  final String hostelId;

  static Route<void> route(String hostelId) =>
      MaterialPageRoute<void>(builder: (_) => OwnerReviewsScreen(hostelId: hostelId));

  @override
  ConsumerState<OwnerReviewsScreen> createState() => _OwnerReviewsScreenState();
}

class _OwnerReviewsScreenState extends ConsumerState<OwnerReviewsScreen> {
  static const _pageSize = 20;

  final _reviews = <PgReview>[];
  bool _loading = true;
  bool _end = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _fetch(reset: true);
  }

  Future<void> _fetch({required bool reset}) async {
    try {
      final page = await ref
          .read(pgProfileApiProvider)
          .reviews(widget.hostelId, limit: _pageSize, offset: reset ? 0 : _reviews.length);
      if (!mounted) return;
      setState(() {
        if (reset) _reviews.clear();
        _reviews.addAll(page);
        _end = page.length < _pageSize;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  Future<void> _load({bool reset = false}) {
    setState(() {
      _loading = true;
      _error = null;
    });
    return _fetch(reset: reset);
  }

  Future<void> _refresh() {
    ref.invalidate(pgPublicProfileProvider(widget.hostelId));
    return _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(pgPublicProfileProvider(widget.hostelId));
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OwnerSubpageHeader(
            title: 'Reviews',
            subtitle: summary.value?.name ?? 'What residents say',
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: OwnerRhythm.pagePadding,
                children: [
                  _Summary(summary: summary),
                  const SizedBox(height: OwnerRhythm.sectionGap),
                  if (_reviews.isEmpty && _loading)
                    const ListSkeleton(rows: 3, semanticLabel: 'Loading reviews')
                  else if (_reviews.isEmpty && _error != null)
                    EmptyState.error(
                      message: stayErrorText(_error!),
                      onRetry: () => _load(reset: true),
                    )
                  else if (_reviews.isEmpty)
                    const EmptyState(
                      icon: ClayIcons.reviews,
                      title: 'No reviews yet',
                      body: 'Residents can rate this PG from their profile. Their first name, '
                          'stars and words appear here and on the PG\'s page.',
                    )
                  else ...[
                    for (final r in _reviews) ...[
                      ReviewCard(review: r),
                      const SizedBox(height: Space.sm),
                    ],
                    if (_error != null) FormNote(stayErrorText(_error!)),
                    if (!_end)
                      Center(
                        child: TextButton(
                          onPressed: _loading ? null : _load,
                          child: Text(_loading ? 'Loading…' : 'Show more reviews'),
                        ),
                      ),
                  ],
                  const SizedBox(height: Space.lg),
                  const InfoNote(
                    icon: Icons.verified_user_outlined,
                    message: 'Only people living in this PG can post a review, one each. You '
                        'can read reviews but cannot change or delete them.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The server's average and count, from the PG's own page.
class _Summary extends StatelessWidget {
  const _Summary({required this.summary});
  final AsyncValue<PgPublicProfile> summary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final value = summary.value;
    final avg = ratingLabel(value?.ratingAvg);
    final count = value?.ratingCount ?? 0;
    final Widget body;
    if (value == null && summary.hasError) {
      body = Text('The average could not be loaded. Pull down to try again.', style: muted);
    } else if (value == null) {
      body = const SkeletonPulse(
        semanticLabel: 'Loading the rating',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Skeleton(widthFactor: 0.4), SizedBox(height: Space.xs), Skeleton(widthFactor: 0.6)],
        ),
      );
    } else if (avg == null || count == 0) {
      body = Text('No ratings yet', style: t.textTheme.titleMedium);
    } else {
      final reviews = count == 1 ? '1 review' : '$count reviews';
      body = Semantics(
        label: 'Rated $avg out of 5 from $reviews',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$avg out of 5', style: t.textTheme.headlineSmall),
            const SizedBox(height: Space.hair),
            StarRow(rating: value.ratingAvg!.round().clamp(1, 5), size: 22),
            const SizedBox(height: Space.hair),
            Text('From $reviews', style: muted),
          ],
        ),
      );
    }
    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          const ClayIcon(ClayIcons.reviews, size: ClaySize.list),
          const SizedBox(width: Space.sm),
          Expanded(child: body),
        ],
      ),
    );
  }
}
