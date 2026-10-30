/// Round 4 (docs/round4-api.md R4.1, R4.2): rent and tenant details for owners and wardens.
///
/// The app sends a student id and the typed values only; who may change them, and whether the
/// values are valid, is decided on the server. Refusals are shown as they are
/// ([SignupFailure.message], with [SignupFailure.field] from the PostgREST hint).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/perf/session_keep_alive.dart';
import '../models/tenant_admin.dart';
import '../providers.dart' show supabaseClientProvider;
import 'signup_repository.dart' show SignupFailure;

abstract interface class TenantAdminApi {
  /// Residents of the caller's PGs whose rent is unset (null hostel: all of them).
  Future<List<RentlessResident>> residentsNeedingRent({String? hostelId});

  /// `wd_set_tenant_rent`. A null [dueDay] keeps the current one.
  Future<RentChange> setRent(String studentId, {required double monthlyFee, int? dueDay});

  /// The prefill for the Edit details and rent sheets.
  Future<TenantProfile?> profile(String studentId);

  /// `wd_update_tenant_profile` with only the changed fields.
  Future<void> updateProfile(String studentId, TenantProfilePatch patch);
}

final class TenantAdminRepository implements TenantAdminApi {
  const TenantAdminRepository(this.db);
  final SupabaseClient db;

  static const _deadline = Duration(seconds: 20);

  Future<T> _run<T>(Future<T> Function() body) async {
    try {
      return await body().timeout(_deadline);
    } catch (e, stack) {
      Error.throwWithStackTrace(SignupFailure.from(e), stack);
    }
  }

  @override
  Future<List<RentlessResident>> residentsNeedingRent({String? hostelId}) => _run(() async =>
      RentlessResident.listFrom(
          await db.rpc('wd_residents_needing_rent', params: {'p_hostel_id': hostelId})));

  @override
  Future<RentChange> setRent(String studentId, {required double monthlyFee, int? dueDay}) =>
      _run(() async => RentChange.fromJson(
            await db.rpc('wd_set_tenant_rent', params: {
              'p_student_id': studentId,
              'p_monthly_fee': monthlyFee,
              'p_due_day': dueDay,
            }),
            fallbackFee: monthlyFee,
          ));

  @override
  Future<TenantProfile?> profile(String studentId) => _run(() async {
        final s = await db
            .from('students')
            .select('id, user_id, full_name, phone, email, guardian_name, guardian_phone, '
                'permanent_address, monthly_fee, rent_due_day')
            .eq('id', studentId)
            .maybeSingle();
        final userId = s?['user_id'];
        Map<String, dynamic>? u;
        if (userId is String && userId.isNotEmpty) {
          u = await db
              .from('users')
              .select('gender, date_of_birth, emergency_contact_name, emergency_contact_phone, '
                  'city, pincode')
              .eq('id', userId)
              .maybeSingle();
        }
        return TenantProfile.from(s, u);
      });

  @override
  Future<void> updateProfile(String studentId, TenantProfilePatch patch) => _run(() async {
        if (patch.isEmpty) return;
        await db.rpc('wd_update_tenant_profile', params: patch.toParams(studentId));
      });
}

final tenantAdminApiProvider =
    Provider<TenantAdminApi>((ref) => TenantAdminRepository(ref.watch(supabaseClientProvider)));

/// The warden home card's list (all of the caller's PGs).
final rentlessResidentsProvider = FutureProvider.autoDispose<List<RentlessResident>>((ref) {
  holdForSession(ref);
  return ref.watch(tenantAdminApiProvider).residentsNeedingRent();
});

final tenantProfileProvider =
    FutureProvider.autoDispose.family<TenantProfile?, String>((ref, studentId) =>
        ref.watch(tenantAdminApiProvider).profile(studentId));
