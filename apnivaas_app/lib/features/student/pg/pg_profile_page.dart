/// A PG's public page (R5): covers, amenities, rating and reviews, locality and city.
/// Owner contacts, the address and the map pin are never part of `st_pg_profile`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/pg_profile.dart';
import '../../../data/models/signup.dart' show HostelHit;
import '../../../data/repositories/pg_profile_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../../common/form_parts.dart';
import '../stay_screens.dart' show stayErrorText;
import '../widgets/format.dart' show dayLabel;
import 'pg_widgets.dart';

class PgProfilePage extends ConsumerWidget {
  const PgProfilePage({
    super.key,
    required this.hostelId,
    this.title,
    this.requestLabel,
  });

  final String hostelId;

  /// Shown in the header until the profile loads.
  final String? title;

  /// When set, a bottom button pops `true` so the caller sends the request.
  final String? requestLabel;

  static Route<bool> route(String hostelId, {String? title, String? requestLabel}) =>
      MaterialPageRoute<bool>(
        builder: (_) =>
            PgProfilePage(hostelId: hostelId, title: title, requestLabel: requestLabel),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = pgPublicProfileProvider(hostelId);
    final profile = ref.watch(provider);

    Future<void> refresh() async {
      ref.invalidate(provider);
      try {
        await ref.read(provider.future).timeout(const Duration(seconds: 20));
      } catch (_) {
        // Drawn below.
      }
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(
            title: profile.value?.name ?? title ?? 'PG',
            subtitle: profile.value?.place,
            leading: const HeaderBackButton(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: switch (profile) {
                AsyncData(:final value) => _Body(profile: value),
                AsyncError(:final error) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(Space.md),
                    children: [
                      EmptyState.error(message: stayErrorText(error), onRetry: refresh),
                    ],
                  ),
                _ => ListView(
                    padding: const EdgeInsets.all(Space.md),
                    children: const [ListSkeleton(rows: 3, semanticLabel: 'Loading the PG')],
                  ),
              },
            ),
          ),
          if (requestLabel != null && profile.hasValue)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.md),
                child: BusyFilledButton(
                  label: requestLabel!,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.profile});
  final PgPublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final hit = HostelHit(
      hostelId: profile.hostelId,
      name: profile.name,
      propertyType: profile.propertyType,
      genderPolicy: profile.genderPolicy,
    );
    final kind = [hit.typeLabel, ?hit.genderLabel].join(' · ');
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
      children: [
        CoverCarousel(paths: profile.coverPaths, logoPath: profile.logoPath),
        const SizedBox(height: Space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PgLogo(path: profile.logoPath, size: ClaySize.tile),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.name, style: t.textTheme.titleLarge),
                  Text(kind, style: muted),
                  if (profile.place.isNotEmpty) Text(profile.place, style: muted),
                  const SizedBox(height: Space.xxs),
                  RatingLine(average: profile.ratingAvg, count: profile.ratingCount),
                ],
              ),
            ),
          ],
        ),
        if (profile.description != null) ...[
          const SizedBox(height: Space.md),
          Text(profile.description!, style: t.textTheme.bodyLarge),
        ],
        if (profile.amenities.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          const SectionHeader(title: 'Amenities'),
          const SizedBox(height: Space.sm),
          AmenityChips(amenities: profile.amenities),
        ],
        if (profile.rules != null) ...[
          const SizedBox(height: Space.xl),
          const SectionHeader(title: 'House rules'),
          const SizedBox(height: Space.sm),
          Text(profile.rules!, style: t.textTheme.bodyMedium),
        ],
        const SizedBox(height: Space.xl),
        const SectionHeader(title: 'Reviews'),
        const SizedBox(height: Space.sm),
        if (profile.reviews.isEmpty)
          Text('No reviews yet. Residents can rate their PG from their profile.', style: muted)
        else
          for (final r in profile.reviews) ...[
            ReviewCard(review: r),
            const SizedBox(height: Space.sm),
          ],
        const SizedBox(height: Space.lg),
        const InfoNote(
          icon: Icons.lock_outline_rounded,
          message: 'The owner\'s phone number and the full address are shared once the PG '
              'accepts you.',
        ),
      ],
    );
  }
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review});
  final PgReview review;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final when = review.updatedAt ?? review.createdAt;
    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(review.isMine ? 'You' : review.reviewerName, style: t.textTheme.titleSmall),
              StarRow(rating: review.rating),
              if (when != null)
                Text(dayLabel(when.toLocal()),
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ],
          ),
          if (review.comment != null) ...[
            const SizedBox(height: Space.xxs),
            Text(review.comment!, style: t.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Swipeable cover photos with page dots; the logo (or clay art) when there are none.
class CoverCarousel extends StatefulWidget {
  const CoverCarousel({super.key, required this.paths, this.logoPath});
  final List<String> paths;
  final String? logoPath;

  @override
  State<CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends State<CoverCarousel> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final placeholder = Container(
      color: t.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const ClayIcon(ClayIcons.rooms, size: ClaySize.banner),
    );
    final paths = widget.paths;
    return Semantics(
      label: paths.isEmpty
          ? 'No photos yet'
          : 'Photo ${_page + 1} of ${paths.length}. Swipe for more.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.well),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: paths.isEmpty
              ? placeholder
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      itemCount: paths.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) =>
                          PgMediaImage(path: paths[i], fallback: placeholder, cacheWidth: 1200),
                    ),
                    if (paths.length > 1)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: Space.xs,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < paths.length; i++)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: i == _page ? 1 : 0.5),
                                ),
                              ),
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
