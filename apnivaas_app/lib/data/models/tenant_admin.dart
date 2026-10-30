/// Round 4 (docs/round4-api.md): a resident's rent and sign-up details, as the owner or a
/// warden manages them. The server re-checks every value and who is asking.
library;

import 'json_read.dart';

/// One row of `wd_residents_needing_rent`.
class RentlessResident {
  const RentlessResident({
    required this.studentId,
    required this.hostelId,
    required this.fullName,
    this.hostelName,
    this.phone,
    this.roomNumber,
    this.bedNumber,
    this.dateOfJoining,
    this.hasAccount = false,
  });

  final String studentId;
  final String hostelId;
  final String fullName;
  final String? hostelName;
  final String? phone;
  final String? roomNumber;
  final int? bedNumber;
  final DateTime? dateOfJoining;
  final bool hasAccount;

  static RentlessResident? fromRow(Map row) {
    final id = jStr(row, 'student_id');
    final hostel = jStr(row, 'hostel_id');
    final name = jStr(row, 'full_name');
    if (id == null || hostel == null || name == null) return null;
    return RentlessResident(
      studentId: id,
      hostelId: hostel,
      fullName: name,
      hostelName: jStr(row, 'hostel_name'),
      phone: jStr(row, 'phone'),
      roomNumber: jStr(row, 'room_number'),
      bedNumber: jInt(row, 'bed_number'),
      dateOfJoining: jDate(row, 'date_of_joining'),
      hasAccount: jBool(row, 'has_account') ?? false,
    );
  }

  static List<RentlessResident> listFrom(Object? data) =>
      [for (final r in jRows(data)) ?fromRow(r)];
}

/// What `wd_set_tenant_rent` answered. [appliesFrom] is `YYYY-MM`.
class RentChange {
  const RentChange({required this.monthlyFee, this.rentDueDay, this.appliesFrom});
  final double monthlyFee;
  final int? rentDueDay;
  final String? appliesFrom;

  static RentChange fromJson(Object? data, {required double fallbackFee}) {
    final row = jOne(data) ?? const <String, dynamic>{};
    final month = jStr(row, 'applies_from');
    return RentChange(
      monthlyFee: jNum(row, 'monthly_fee') ?? fallbackFee,
      rentDueDay: jInt(row, 'rent_due_day'),
      appliesFrom: (month != null && RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) ? month : null,
    );
  }
}

/// Every detail a tenant gives at sign-up, prefilled from `students` and `users`.
class TenantProfile {
  const TenantProfile({
    required this.studentId,
    required this.fullName,
    required this.phone,
    required this.hasAccount,
    this.email,
    this.gender,
    this.dateOfBirth,
    this.emergencyName,
    this.emergencyPhone,
    this.address,
    this.city,
    this.pincode,
    this.monthlyFee = 0,
    this.rentDueDay,
  });

  final String studentId;
  final String fullName;
  final String phone;
  final bool hasAccount;
  final String? email;

  /// `male`, `female` or `other`.
  final String? gender;
  final DateTime? dateOfBirth;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? address;
  final String? city;
  final String? pincode;
  final double monthlyFee;
  final int? rentDueDay;

  /// [student] is the roster row; [user] the tenant's `users` row, when they have one.
  static TenantProfile? from(Map? student, Map? user) {
    if (student == null) return null;
    final id = jStr(student, 'id');
    if (id == null) return null;
    final u = user ?? const <String, dynamic>{};
    final g = jStr(u, 'gender')?.toLowerCase();
    return TenantProfile(
      studentId: id,
      fullName: jStr(student, 'full_name') ?? '',
      phone: jStr(student, 'phone') ?? '',
      hasAccount: jStr(student, 'user_id') != null,
      email: jStr(student, 'email'),
      gender: const {'male', 'female', 'other'}.contains(g) ? g : null,
      dateOfBirth: jDate(u, 'date_of_birth'),
      emergencyName: jStr(u, 'emergency_contact_name') ?? jStr(student, 'guardian_name'),
      emergencyPhone: jStr(u, 'emergency_contact_phone') ?? jStr(student, 'guardian_phone'),
      address: jStr(student, 'permanent_address'),
      city: jStr(u, 'city'),
      pincode: jStr(u, 'pincode'),
      monthlyFee: jNum(student, 'monthly_fee') ?? 0,
      rentDueDay: jInt(student, 'rent_due_day'),
    );
  }
}

/// The fields `wd_update_tenant_profile` takes. Null keeps a value; '' clears an optional one.
class TenantProfilePatch {
  const TenantProfilePatch({
    this.fullName,
    this.phone,
    this.email,
    this.gender,
    this.dateOfBirth,
    this.emergencyName,
    this.emergencyPhone,
    this.address,
    this.city,
    this.pincode,
  });

  final String? fullName;
  final String? phone;
  final String? email;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? address;
  final String? city;
  final String? pincode;

  bool get isEmpty => toParams('').length == 1;

  Map<String, dynamic> toParams(String studentId) {
    final dob = dateOfBirth;
    return {
      'p_student_id': studentId,
      'p_full_name': ?fullName,
      'p_phone': ?phone,
      'p_email': ?email,
      'p_gender': ?gender,
      if (dob != null)
        'p_date_of_birth': '${dob.year.toString().padLeft(4, '0')}-'
            '${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}',
      'p_emergency_contact_name': ?emergencyName,
      'p_emergency_contact_phone': ?emergencyPhone,
      'p_address': ?address,
      'p_city': ?city,
      'p_pincode': ?pincode,
    };
  }
}
