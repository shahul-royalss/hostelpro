/// Small pieces shared by the PG profile page, Find your PG and the owner's editor (R5).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/pg_profile.dart';
import '../../../data/people_providers.dart' show signedUrlProvider;
import '../../../data/repositories/pg_profile_repository.dart' show pgMediaBucket;
import '../../../shared/clay/clay.dart';

/// A pg-media photo through a short signed URL, or [bytes] picked on this phone. Draws
/// [fallback] while loading, when refused, or when there is nothing to show.
class PgMediaImage extends ConsumerWidget {
  const PgMediaImage({
    super.key,
    this.path,
    this.bytes,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String? path;
  final Uint8List? bytes;
  final Widget fallback;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = bytes;
    if (local != null) {
      return Image.memory(local, fit: fit, cacheWidth: cacheWidth, excludeFromSemantics: true);
    }
    final p = path;
    if (p == null || p.isEmpty) return fallback;
    final url = ref.watch(signedUrlProvider((bucket: pgMediaBucket, path: p))).value;
    if (url == null) return fallback;
    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (_, child, frame, sync) => frame == null && !sync ? fallback : child,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// A round PG logo; the clay building when there is none.
class PgLogo extends StatelessWidget {
  const PgLogo({super.key, this.path, this.bytes, this.size = ClaySize.list});

  final String? path;
  final Uint8List? bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fallback = Container(
      color: t.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: ClayIcon(ClayIcons.rooms, size: size * 0.72),
    );
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: PgMediaImage(
          path: path,
          bytes: bytes,
          fallback: fallback,
          cacheWidth: (size * 3).round(),
        ),
      ),
    );
  }
}

/// "★ 4.3 · 12 reviews", or "No reviews yet".
class RatingLine extends StatelessWidget {
  const RatingLine({super.key, required this.average, required this.count, this.dense = false});

  final double? average;
  final int count;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final style = (dense ? t.textTheme.bodySmall : t.textTheme.bodyMedium)
        ?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final avg = ratingLabel(average);
    if (avg == null || count == 0) return Text('No reviews yet', style: style);
    final words = '$avg · ${count == 1 ? '1 review' : '$count reviews'}';
    return Semantics(
      label: 'Rated $avg out of 5 from ${count == 1 ? '1 review' : '$count reviews'}',
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.xxs,
        children: [
          Icon(Icons.star_rounded, size: dense ? 16 : 20, color: context.tones.warning),
          Text(words, style: style),
        ],
      ),
    );
  }
}

/// Five stars for display.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.size = 18});
  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$rating out of 5 stars',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              Icon(
                i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: i <= rating
                    ? context.tones.warning
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      );
}

IconData amenityIcon(String key) => switch (key) {
      'wifi' => Icons.wifi_rounded,
      'ac' => Icons.ac_unit_rounded,
      'food' => Icons.restaurant_rounded,
      'laundry' => Icons.local_laundry_service_rounded,
      'power_backup' => Icons.battery_charging_full_rounded,
      'parking' => Icons.local_parking_rounded,
      'cctv' => Icons.videocam_rounded,
      'housekeeping' => Icons.cleaning_services_rounded,
      'attached_bathroom' => Icons.bathtub_rounded,
      'hot_water' => Icons.hot_tub_rounded,
      'gym' => Icons.fitness_center_rounded,
      'study_room' => Icons.menu_book_rounded,
      _ => Icons.check_circle_outline_rounded,
    };

/// Amenities as quiet chips; [limit] shows the first few.
class AmenityChips extends StatelessWidget {
  const AmenityChips({super.key, required this.amenities, this.limit});

  final List<String> amenities;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final keys = orderedAmenities(amenities);
    final shown = limit == null ? keys : keys.take(limit!).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final k in shown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xxs),
            decoration: BoxDecoration(
              color: t.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(amenityIcon(k), size: 16, color: t.colorScheme.primary),
                const SizedBox(width: Space.xxs),
                Flexible(child: Text(amenityLabel(k), style: t.textTheme.labelMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
