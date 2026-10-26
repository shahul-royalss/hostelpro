/// PG profile, photos and reviews (docs/round3-api.md §5).
library;

import 'json_read.dart';

/// Amenity keys `ow_update_pg_profile` accepts, in display order, with labels.
const pgAmenities = <String, String>{
  'wifi': 'Wi-Fi',
  'ac': 'AC',
  'food': 'Food',
  'laundry': 'Laundry',
  'power_backup': 'Power backup',
  'parking': 'Parking',
  'cctv': 'CCTV',
  'housekeeping': 'Housekeeping',
  'attached_bathroom': 'Attached bathroom',
  'hot_water': 'Hot water',
  'gym': 'Gym',
  'study_room': 'Study room',
};

String amenityLabel(String key) => pgAmenities[key] ?? key;

/// [keys] in display order, unknown keys dropped.
List<String> orderedAmenities(Iterable<String> keys) {
  final set = keys.toSet();
  return [for (final k in pgAmenities.keys) if (set.contains(k)) k];
}

const pgMaxCovers = 6;
const pgDescriptionMax = 500;
const reviewCommentMax = 300;

/// '4.3' for a rating; null when there is none.
String? ratingLabel(double? avg) => avg?.toStringAsFixed(1);

/// The owner's editable profile, read from their own `hostels` row.
class OwnerPgProfile {
  const OwnerPgProfile({
    required this.hostelId,
    required this.name,
    this.description,
    this.amenities = const [],
    this.logoPath,
    this.coverPaths = const [],
    this.listed = false,
    this.latitude,
    this.longitude,
    this.rules,
  });

  static const columns =
      'id, name, description, amenities, logo_path, cover_paths, listed, latitude, longitude, rules';

  factory OwnerPgProfile.fromJson(Map<String, dynamic> row) => OwnerPgProfile(
        hostelId: jStr(row, 'id') ?? jStr(row, 'hostel_id') ?? '',
        name: jStr(row, 'name') ?? '',
        description: jStr(row, 'description'),
        amenities: jStrList(row, 'amenities'),
        logoPath: jStr(row, 'logo_path'),
        coverPaths: jStrList(row, 'cover_paths'),
        listed: jBool(row, 'listed') ?? false,
        latitude: jNum(row, 'latitude'),
        longitude: jNum(row, 'longitude'),
        rules: jStr(row, 'rules'),
      );

  final String hostelId;
  final String name;
  final String? description;
  final List<String> amenities;
  final String? logoPath;
  final List<String> coverPaths;
  final bool listed;
  final double? latitude;
  final double? longitude;
  final String? rules;

  bool get hasPin => latitude != null && longitude != null;
}

/// One row of `pg_review_list` (first name only).
class PgReview {
  const PgReview({
    required this.reviewId,
    required this.reviewerName,
    required this.rating,
    this.comment,
    this.createdAt,
    this.updatedAt,
    this.isMine = false,
  });

  final String reviewId;
  final String reviewerName;
  final int rating;
  final String? comment;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isMine;

  static PgReview? tryParse(Map row) {
    final id = jStr(row, 'review_id');
    final rating = jInt(row, 'rating');
    if (id == null || rating == null) return null;
    return PgReview(
      reviewId: id,
      reviewerName: jStr(row, 'reviewer_name') ?? 'Resident',
      rating: rating.clamp(1, 5),
      comment: jStr(row, 'comment'),
      createdAt: jDate(row, 'created_at'),
      updatedAt: jDate(row, 'updated_at'),
      isMine: jBool(row, 'is_mine') ?? false,
    );
  }

  static List<PgReview> listFrom(Object? data) =>
      [for (final r in jRows(data)) ?tryParse(r)];
}

/// `st_save_review` / `st_my_review`.
class MyReview {
  const MyReview({required this.reviewId, required this.rating, this.comment, this.updatedAt});

  final String reviewId;
  final int rating;
  final String? comment;
  final DateTime? updatedAt;

  static MyReview? tryParse(Object? data) {
    final row = jOne(data);
    if (row == null) return null;
    final id = jStr(row, 'review_id');
    final rating = jInt(row, 'rating');
    if (id == null || rating == null) return null;
    return MyReview(
      reviewId: id,
      rating: rating.clamp(1, 5),
      comment: jStr(row, 'comment'),
      updatedAt: jDate(row, 'updated_at'),
    );
  }
}

/// `st_pg_profile`: what anyone looking for a PG may see. Never an address or owner contact.
class PgPublicProfile {
  const PgPublicProfile({
    required this.hostelId,
    required this.name,
    this.propertyType,
    this.genderPolicy,
    this.locality,
    this.city,
    this.description,
    this.amenities = const [],
    this.rules,
    this.logoPath,
    this.coverPaths = const [],
    this.ratingAvg,
    this.ratingCount = 0,
    this.reviews = const [],
  });

  static PgPublicProfile? tryParse(Object? data) {
    final row = jOne(data);
    final id = row == null ? null : jStr(row, 'hostel_id');
    if (row == null || id == null) return null;
    return PgPublicProfile(
      hostelId: id,
      name: jStr(row, 'name') ?? 'PG',
      propertyType: jStr(row, 'property_type'),
      genderPolicy: jStr(row, 'gender_policy'),
      locality: jStr(row, 'locality'),
      city: jStr(row, 'city'),
      description: jStr(row, 'description'),
      amenities: orderedAmenities(jStrList(row, 'amenities')),
      rules: jStr(row, 'rules'),
      logoPath: jStr(row, 'logo_path'),
      coverPaths: jStrList(row, 'cover_paths'),
      ratingAvg: jNum(row, 'rating_avg'),
      ratingCount: jInt(row, 'rating_count') ?? 0,
      reviews: PgReview.listFrom(row['reviews']),
    );
  }

  final String hostelId;
  final String name;
  final String? propertyType;
  final String? genderPolicy;
  final String? locality;
  final String? city;
  final String? description;
  final List<String> amenities;
  final String? rules;
  final String? logoPath;
  final List<String> coverPaths;
  final double? ratingAvg;
  final int ratingCount;
  final List<PgReview> reviews;

  String get place => [locality, city].whereType<String>().join(', ');
}
