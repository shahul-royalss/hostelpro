/// PG profile, pg-media uploads, reviews and the public PG page (docs/round3-api.md §5).
/// Refusals are [SignupFailure]s carrying the server's sentence, `field` naming the input.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/perf/session_keep_alive.dart';
import '../models/pg_profile.dart';
import '../providers.dart' show supabaseClientProvider;
import 'signup_repository.dart' show SignupFailure, randomUuidV4;

const pgMediaBucket = 'pg-media';

enum PgMediaKind { logo, cover }

abstract interface class PgProfileApi {
  Future<OwnerPgProfile> ownerProfile(String hostelId);

  /// Uploads a JPEG under a fresh key and returns the key, for [saveProfile].
  Future<String> uploadMedia(String hostelId, PgMediaKind kind, Uint8List jpeg);

  Future<OwnerPgProfile> saveProfile({
    required String hostelId,
    required String name,
    required String? description,
    required List<String> amenities,
    required String? logoPath,
    required List<String> coverPaths,
    bool? listed,
    double? latitude,
    double? longitude,
  });

  Future<void> updateRules(String hostelId, String rules);

  Future<PgPublicProfile> pgProfile(String hostelId);
  Future<List<PgReview>> reviews(String hostelId, {int limit = 20, int offset = 0});

  Future<MyReview?> myReview();
  Future<MyReview?> saveReview({required int rating, String? comment});
}

final class PgProfileRepository implements PgProfileApi {
  const PgProfileRepository(this.db);
  final SupabaseClient db;

  static const _deadline = Duration(seconds: 20);
  static const _uploadDeadline = Duration(seconds: 60);

  Future<T> _run<T>(Future<T> Function() body, [Duration deadline = _deadline]) async {
    try {
      return await body().timeout(deadline);
    } catch (e, stack) {
      Error.throwWithStackTrace(SignupFailure.from(e), stack);
    }
  }

  Future<Object?> _rpc(String fn, [Map<String, dynamic>? params]) =>
      _run(() async => await db.rpc(fn, params: params));

  @override
  Future<OwnerPgProfile> ownerProfile(String hostelId) => _run(() async {
        final row = await db
            .from('hostels')
            .select(OwnerPgProfile.columns)
            .eq('id', hostelId)
            .maybeSingle();
        if (row == null) throw const SignupFailure('You can only edit your own PG.');
        return OwnerPgProfile.fromJson(row);
      });

  @override
  Future<String> uploadMedia(String hostelId, PgMediaKind kind, Uint8List jpeg) => _run(() async {
        final path = '$hostelId/${kind.name}/${randomUuidV4()}.jpg';
        await db.storage.from(pgMediaBucket).uploadBinary(
              path,
              jpeg,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
            );
        return path;
      }, _uploadDeadline);

  @override
  Future<OwnerPgProfile> saveProfile({
    required String hostelId,
    required String name,
    required String? description,
    required List<String> amenities,
    required String? logoPath,
    required List<String> coverPaths,
    bool? listed,
    double? latitude,
    double? longitude,
  }) async {
    final pin = latitude != null && longitude != null;
    final data = await _rpc('ow_update_pg_profile', {
      'p_hostel_id': hostelId,
      'p_name': name.trim(),
      'p_description': description?.trim(),
      'p_amenities': amenities,
      'p_logo_path': logoPath,
      'p_cover_paths': coverPaths,
      'p_listed': listed,
      // Both or neither: the server refuses one without the other.
      'p_latitude': pin ? latitude : null,
      'p_longitude': pin ? longitude : null,
    });
    final row = data is List ? (data.isEmpty ? null : data.first) : data;
    return OwnerPgProfile.fromJson(row is Map<String, dynamic> ? row : {'hostel_id': hostelId});
  }

  @override
  Future<void> updateRules(String hostelId, String rules) async {
    await _rpc('ow_update_hostel_rules', {'p_hostel_id': hostelId, 'p_rules': rules});
  }

  @override
  Future<PgPublicProfile> pgProfile(String hostelId) async {
    final p = PgPublicProfile.tryParse(await _rpc('st_pg_profile', {'p_hostel_id': hostelId}));
    if (p == null) throw const SignupFailure('This PG is not available.');
    return p;
  }

  @override
  Future<List<PgReview>> reviews(String hostelId, {int limit = 20, int offset = 0}) async =>
      PgReview.listFrom(await _rpc('pg_review_list', {
        'p_hostel_id': hostelId,
        'p_limit': limit,
        'p_offset': offset,
      }));

  @override
  Future<MyReview?> myReview() async => MyReview.tryParse(await _rpc('st_my_review'));

  @override
  Future<MyReview?> saveReview({required int rating, String? comment}) async {
    final c = comment?.trim();
    return MyReview.tryParse(await _rpc('st_save_review', {
      'p_rating': rating,
      'p_comment': (c == null || c.isEmpty) ? null : c,
    }));
  }
}

final pgProfileApiProvider =
    Provider<PgProfileApi>((ref) => PgProfileRepository(ref.watch(supabaseClientProvider)));

/// The owner's editable profile for one PG.
final ownerPgProfileProvider =
    FutureProvider.autoDispose.family<OwnerPgProfile, String>((ref, hostelId) {
  holdForSession(ref);
  return ref.watch(pgProfileApiProvider).ownerProfile(hostelId);
});

/// The public PG page.
final pgPublicProfileProvider =
    FutureProvider.autoDispose.family<PgPublicProfile, String>((ref, hostelId) {
  holdForSession(ref);
  return ref.watch(pgProfileApiProvider).pgProfile(hostelId);
});

/// The signed-in tenant's review of their current PG.
final myReviewProvider = FutureProvider.autoDispose<MyReview?>((ref) {
  holdForSession(ref);
  return ref.watch(pgProfileApiProvider).myReview();
});
