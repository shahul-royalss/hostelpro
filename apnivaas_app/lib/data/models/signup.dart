/// Row shapes for the self sign-up round (docs/self-signup-api.md §3–5).
///
/// Parsed leniently on purpose: these feed onboarding screens, and a column this build cannot
/// read must degrade to "unknown", never throw a new account out of the flow.
library;

String? _str(Map<String, dynamic> row, String key) {
  final v = row[key];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? _date(Map<String, dynamic> row, String key) =>
    DateTime.tryParse(_str(row, key) ?? '');

/// The caller's own profile, as Your details shows it.
class MyProfile {
  const MyProfile({
    this.fullName,
    this.phone,
    this.gender,
    this.dateOfBirth,
    this.emergencyName,
    this.emergencyPhone,
    this.avatarPath,
  });

  factory MyProfile.fromJson(Map<String, dynamic> row) => MyProfile(
        fullName: _str(row, 'full_name'),
        phone: _str(row, 'phone'),
        gender: _str(row, 'gender'),
        dateOfBirth: _date(row, 'date_of_birth'),
        emergencyName: _str(row, 'emergency_contact_name'),
        emergencyPhone: _str(row, 'emergency_contact_phone'),
        avatarPath: _str(row, 'avatar_path'),
      );

  static const columns =
      'full_name, phone, gender, date_of_birth, emergency_contact_name, emergency_contact_phone, '
      'avatar_path';

  final String? fullName;
  final String? phone;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? avatarPath;
}

/// `ow_create_first_hostel` → `{hostel_id, name, trial_start, trial_end}`.
class FirstHostel {
  const FirstHostel({required this.hostelId, required this.name, this.trialEnd});

  factory FirstHostel.fromJson(Map<String, dynamic> row) => FirstHostel(
        hostelId: _str(row, 'hostel_id') ?? '',
        name: _str(row, 'name') ?? '',
        trialEnd: _date(row, 'trial_end'),
      );

  final String hostelId;
  final String name;
  final DateTime? trialEnd;
}

/// The two tenant search RPCs share this shape. Never an address or an owner contact.
class HostelHit {
  const HostelHit({
    required this.hostelId,
    required this.name,
    this.propertyType,
    this.genderPolicy,
    this.locality,
    this.city,
    this.distanceKm,
    this.logoPath,
    this.ratingAvg,
    this.ratingCount = 0,
    this.amenities = const [],
  });

  factory HostelHit.fromJson(Map<String, dynamic> row) => HostelHit(
        hostelId: _str(row, 'hostel_id') ?? '',
        name: _str(row, 'name') ?? 'PG',
        propertyType: _str(row, 'property_type'),
        genderPolicy: _str(row, 'gender_policy'),
        locality: _str(row, 'locality'),
        city: _str(row, 'city'),
        distanceKm: num.tryParse(_str(row, 'distance_km') ?? '')?.toDouble(),
        // Round 3 (§5.4): logo, rating and amenities.
        logoPath: _str(row, 'logo_path'),
        ratingAvg: num.tryParse(_str(row, 'rating_avg') ?? '')?.toDouble(),
        ratingCount: int.tryParse(_str(row, 'rating_count') ?? '') ?? 0,
        amenities: row['amenities'] is List
            ? [for (final a in row['amenities'] as List) if (a is String) a]
            : const [],
      );

  final String hostelId;
  final String name;
  final String? propertyType;
  final String? genderPolicy;
  final String? locality;
  final String? city;
  final double? distanceKm;
  final String? logoPath;
  final double? ratingAvg;
  final int ratingCount;
  final List<String> amenities;

  String get typeLabel => switch (propertyType) {
        'pg' => 'PG',
        'hostel' => 'Hostel',
        'co_living' => 'Co-living',
        'flats' => 'Flats',
        _ => 'PG',
      };

  String? get genderLabel => switch (genderPolicy) {
        'boys' => 'Boys',
        'girls' => 'Girls',
        'coed' => 'Co-ed',
        _ => null,
      };

  String get place => [locality, city].whereType<String>().join(', ');

  String? get distanceLabel {
    final d = distanceKm;
    if (d == null) return null;
    if (d < 1) return 'Under 1 km';
    return '${d < 10 ? d.toStringAsFixed(1) : d.round()} km';
  }
}

enum JoinStatus { pending, accepted, declined, cancelled, expired }

/// `st_my_join_request` → the pending request, or the latest decided within 30 days.
class JoinRequest {
  const JoinRequest({
    required this.requestId,
    required this.hostelName,
    required this.status,
    this.decisionNote,
  });

  static JoinRequest? tryParse(Object? data) {
    final row = data is List ? (data.isEmpty ? null : data.first) : data;
    if (row is! Map<String, dynamic>) return null;
    final status = JoinStatus.values.where((s) => s.name == _str(row, 'status')).firstOrNull;
    if (status == null) return null;
    return JoinRequest(
      requestId: _str(row, 'request_id') ?? '',
      hostelName: _str(row, 'hostel_name') ?? 'the PG',
      status: status,
      decisionNote: _str(row, 'decision_note'),
    );
  }

  final String requestId;
  final String hostelName;
  final JoinStatus status;
  final String? decisionNote;
}

/// The beds bands `ow_book_demo` accepts.
const demoBedBands = <String>['1-20', '21-50', '51-100', '100+'];

/// The document kinds `me_add_document` accepts, with their labels.
const documentKinds = <String, String>{
  'aadhaar_masked': 'Masked Aadhaar',
  'pan': 'PAN card',
  'driving_licence': 'Driving licence',
  'voter_id': 'Voter ID',
  'passport': 'Passport',
  'college_or_work_id': 'College or work ID',
  'other': 'Other ID',
};
