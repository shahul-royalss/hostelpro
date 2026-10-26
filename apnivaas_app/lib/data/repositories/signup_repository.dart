/// Every server call of the sign-up and onboarding round, built only against
/// docs/self-signup-api.md (§2–5).
///
/// THE APP NEVER SENDS AUTHORITY. No role, no amount, no hostel to link, no storage path outside
/// the caller's own folder: the RPCs and storage policies check every value again, and the
/// sentences they refuse with are shown verbatim ([SignupFailure.message]).
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/failure.dart';
import '../models/signup.dart';
import '../providers.dart' show supabaseClientProvider;

/// A refusal to show as it is. [field] is the PostgREST `hint` when it names a form field
/// (`name`, `pincode`, `slot_start`, …), so the screen can put the sentence under that field.
class SignupFailure implements Exception {
  const SignupFailure(this.message, {this.field, this.code});

  final String message;
  final String? field;

  /// The SQLSTATE when the server sent one.
  final String? code;

  /// `Not signed in.` (42501): the session or the profile is gone; the app routes to sign-in.
  bool get signedOut => code == '42501' && message == 'Not signed in.';

  static const _verbatimCodes = {'P0001', '42501', '22023', '23505'};

  factory SignupFailure.from(Object error) {
    if (error is SignupFailure) return error;
    if (error is PostgrestException && _verbatimCodes.contains(error.code)) {
      final hint = error.hint?.trim();
      final isField = hint != null && RegExp(r'^[a-z_]{1,40}$').hasMatch(hint);
      return SignupFailure(error.message, field: isField ? hint : null, code: error.code);
    }
    if (error is StorageException) {
      return SignupFailure(
        error.statusCode == '413'
            ? 'That file is too large. Choose a smaller one.'
            : 'The upload did not finish. Please try again.',
      );
    }
    return SignupFailure(AppFailure.from(error).message);
  }

  @override
  String toString() => 'SignupFailure($code, $field): $message';
}

/// A lowercase random UUID v4, for storage keys (`<uid>/avatar/<uuid>.jpg`). Keys are never
/// reused: there is no UPDATE or DELETE from the client.
String randomUuidV4([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) =>
      b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// The document type the bytes really are, by their first bytes, never by a file name.
/// Null for anything the `identity-documents` bucket would refuse.
({String ext, String contentType})? documentTypeOf(Uint8List bytes) {
  bool starts(List<int> sig, [int at = 0]) {
    if (bytes.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (starts(const [0xFF, 0xD8, 0xFF])) return (ext: 'jpg', contentType: 'image/jpeg');
  if (starts(const [0x89, 0x50, 0x4E, 0x47])) return (ext: 'png', contentType: 'image/png');
  if (starts(const [0x52, 0x49, 0x46, 0x46]) && starts(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return (ext: 'webp', contentType: 'image/webp');
  }
  if (starts(const [0x25, 0x50, 0x44, 0x46])) return (ext: 'pdf', contentType: 'application/pdf');
  return null;
}

const documentMaxBytes = 5 * 1024 * 1024;

/// `p_slot_start` wants ISO-8601 with `+05:30`. [slot] carries the Asia/Kolkata wall-clock
/// date and hour the person picked, whatever this phone's own zone is.
String kolkataIso(DateTime slot) =>
    '${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(slot)}+05:30';

/// What the sign-up screens need from the server. An interface so widget tests run offline.
abstract interface class SignupApi {
  Future<MyProfile> myProfile();
  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? gender,
    DateTime? dateOfBirth,
    String? emergencyName,
    String? emergencyPhone,
  });
  Future<String> uploadAvatar(Uint8List squareJpeg);
  Future<void> addDocument({required String kind, required Uint8List bytes});

  Future<FirstHostel> createFirstHostel({
    required String name,
    required String propertyType,
    required String genderPolicy,
    required String address,
    required String locality,
    required String city,
    required String pincode,
    required int floors,
    required int rooms,
    required int bedsPerRoom,
    double? latitude,
    double? longitude,
  });
  Future<void> bookDemo({
    required String name,
    required String phone,
    required String pgName,
    required String city,
    required String bedBand,
    required DateTime slotKolkata,
  });

  Future<List<HostelHit>> nearbyHostels(double lat, double lng);
  Future<List<HostelHit>> searchHostels(String query);
  Future<void> requestJoin(String hostelId, {String? message});
  Future<void> cancelJoinRequest();
  Future<JoinRequest?> myJoinRequest();
}

final class SignupRepository implements SignupApi {
  const SignupRepository(this.db);
  final SupabaseClient db;

  static const _deadline = Duration(seconds: 20);

  Future<T> _run<T>(Future<T> Function() body) async {
    try {
      return await body().timeout(_deadline);
    } catch (e, stack) {
      Error.throwWithStackTrace(SignupFailure.from(e), stack);
    }
  }

  Future<Object?> _rpc(String fn, [Map<String, dynamic>? params]) =>
      _run(() async => await db.rpc(fn, params: params));

  String get _uid {
    final id = db.auth.currentUser?.id;
    if (id == null) throw const SignupFailure('Not signed in.', code: '42501');
    return id;
  }

  @override
  Future<MyProfile> myProfile() => _run(() async {
        final row =
            await db.from('users').select(MyProfile.columns).eq('id', _uid).maybeSingle();
        return row == null ? const MyProfile() : MyProfile.fromJson(row);
      });

  @override
  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? gender,
    DateTime? dateOfBirth,
    String? emergencyName,
    String? emergencyPhone,
  }) async {
    // null means "leave unchanged" on the server, so only what was typed is sent.
    await _rpc('me_update_profile', {
      'p_full_name': fullName,
      'p_phone': phone,
      'p_gender': gender,
      'p_date_of_birth': dateOfBirth == null ? null : DateFormat('yyyy-MM-dd').format(dateOfBirth),
      'p_emergency_contact_name': emergencyName,
      'p_emergency_contact_phone': emergencyPhone,
    });
  }

  @override
  Future<String> uploadAvatar(Uint8List squareJpeg) => _run(() async {
        final path = '$_uid/avatar/${randomUuidV4()}.jpg';
        await db.storage.from('avatars').uploadBinary(
              path,
              squareJpeg,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
            );
        final result = await db.rpc('me_set_avatar', params: {'p_path': path});
        final row = result is Map ? result : null;
        return (row?['avatar_path'] as String?) ?? path;
      });

  @override
  Future<void> addDocument({required String kind, required Uint8List bytes}) => _run(() async {
        final type = documentTypeOf(bytes);
        if (type == null) {
          throw const SignupFailure('That file could not be used. Please try again.');
        }
        if (bytes.length > documentMaxBytes) {
          throw const SignupFailure('That file is too large. Choose one under 5 MB.');
        }
        final path = '$_uid/document/${randomUuidV4()}.${type.ext}';
        await db.storage.from('identity-documents').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: type.contentType, upsert: false),
            );
        await db.rpc('me_add_document', params: {'p_kind': kind, 'p_path': path});
      });

  @override
  Future<FirstHostel> createFirstHostel({
    required String name,
    required String propertyType,
    required String genderPolicy,
    required String address,
    required String locality,
    required String city,
    required String pincode,
    required int floors,
    required int rooms,
    required int bedsPerRoom,
    double? latitude,
    double? longitude,
  }) async {
    final data = await _rpc('ow_create_first_hostel', {
      'p_name': name,
      'p_property_type': propertyType,
      'p_gender_policy': genderPolicy,
      'p_address': address,
      'p_locality': locality,
      'p_city': city,
      'p_pincode': pincode,
      'p_floors': floors,
      'p_rooms': rooms,
      'p_beds_per_room': bedsPerRoom,
      // Both or neither: the server refuses one without the other.
      'p_latitude': latitude != null && longitude != null ? latitude : null,
      'p_longitude': latitude != null && longitude != null ? longitude : null,
    });
    final row = data is List ? (data.isEmpty ? null : data.first) : data;
    return FirstHostel.fromJson(row is Map<String, dynamic> ? row : const {});
  }

  @override
  Future<void> bookDemo({
    required String name,
    required String phone,
    required String pgName,
    required String city,
    required String bedBand,
    required DateTime slotKolkata,
  }) async {
    await _rpc('ow_book_demo', {
      'p_name': name,
      'p_phone': phone,
      'p_pg_name': pgName,
      'p_city': city,
      'p_bed_band': bedBand,
      'p_slot_start': kolkataIso(slotKolkata),
    });
  }

  List<HostelHit> _hits(Object? data) => data is List
      ? data.whereType<Map<String, dynamic>>().map(HostelHit.fromJson).toList(growable: false)
      : const [];

  @override
  Future<List<HostelHit>> nearbyHostels(double lat, double lng) async =>
      _hits(await _rpc('st_nearby_hostels', {'p_lat': lat, 'p_lng': lng}));

  @override
  Future<List<HostelHit>> searchHostels(String query) async =>
      _hits(await _rpc('st_search_hostels', {'p_query': query}));

  @override
  Future<void> requestJoin(String hostelId, {String? message}) async {
    final m = message?.trim();
    await _rpc('st_request_join', {
      'p_hostel_id': hostelId,
      'p_message': (m == null || m.isEmpty) ? null : m,
    });
  }

  @override
  Future<void> cancelJoinRequest() async => _rpc('st_cancel_join_request');

  @override
  Future<JoinRequest?> myJoinRequest() async => JoinRequest.tryParse(await _rpc('st_my_join_request'));
}

final signupApiProvider = Provider<SignupApi>(
  (ref) => SignupRepository(ref.watch(supabaseClientProvider)),
);
