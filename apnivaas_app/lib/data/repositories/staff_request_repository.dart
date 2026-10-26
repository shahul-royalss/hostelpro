/// Staff applicants asking to join a PG, and the owner's answer (docs/round3-api.md §6).
/// The app sends a role only as the owner's choice; `ow_decide_staff_request` checks it.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/session.dart' show UserRole;
import '../../core/auth/auth_controller.dart' show sessionProvider;
import '../../core/perf/session_keep_alive.dart';
import '../models/staff_request.dart';
import '../providers.dart' show supabaseClientProvider;
import 'signup_repository.dart' show SignupFailure;

abstract interface class StaffRequestApi {
  Future<StaffJoinRequest?> requestJoin(String hostelId, {String? message});
  Future<StaffJoinRequest?> myRequest();
  Future<StaffJoinRequest?> cancel();

  Future<List<StaffRequestRow>> ownerRequests({String? status = 'pending'});
  Future<int> pendingCount();
  Future<StaffJoinRequest?> decide(
    String requestId, {
    required bool accept,
    StaffGrant? role,
    String? note,
  });
}

final class StaffRequestRepository implements StaffRequestApi {
  const StaffRequestRepository(this.db);
  final SupabaseClient db;

  static const _deadline = Duration(seconds: 20);

  Future<Object?> _rpc(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await db.rpc(fn, params: params).timeout(_deadline);
    } catch (e, stack) {
      Error.throwWithStackTrace(SignupFailure.from(e), stack);
    }
  }

  static String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  Future<StaffJoinRequest?> requestJoin(String hostelId, {String? message}) async =>
      StaffJoinRequest.tryParse(await _rpc(
          'stf_request_join', {'p_hostel_id': hostelId, 'p_message': _clean(message)}));

  @override
  Future<StaffJoinRequest?> myRequest() async =>
      StaffJoinRequest.tryParse(await _rpc('stf_my_join_request'));

  @override
  Future<StaffJoinRequest?> cancel() async =>
      StaffJoinRequest.tryParse(await _rpc('stf_cancel_join_request'));

  @override
  Future<List<StaffRequestRow>> ownerRequests({String? status = 'pending'}) async =>
      StaffRequestRow.listFrom(
          await _rpc('ow_staff_requests', {'p_hostel_id': null, 'p_status': status}));

  @override
  Future<int> pendingCount() async {
    final v = await _rpc('ow_pending_staff_request_count');
    return v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);
  }

  @override
  Future<StaffJoinRequest?> decide(
    String requestId, {
    required bool accept,
    StaffGrant? role,
    String? note,
  }) async =>
      StaffJoinRequest.tryParse(await _rpc('ow_decide_staff_request', {
        'p_request_id': requestId,
        'p_accept': accept,
        'p_role': accept ? role?.wire : null,
        'p_note': _clean(note),
      }));
}

final staffRequestApiProvider = Provider<StaffRequestApi>(
    (ref) => StaffRequestRepository(ref.watch(supabaseClientProvider)));

bool _isOwner(Ref ref) => ref.watch(sessionProvider.select((s) => s?.role)) == UserRole.owner;

/// Pending staff requests across the owner's PGs; 0 for anyone else (no call made).
final pendingStaffRequestCountProvider = FutureProvider.autoDispose<int>((ref) async {
  if (!_isOwner(ref)) return 0;
  holdForSession(ref);
  return ref.watch(staffRequestApiProvider).pendingCount();
});

/// The owner's list; `null` status means every status.
final staffRequestsProvider =
    FutureProvider.autoDispose.family<List<StaffRequestRow>, String?>((ref, status) {
  holdForSession(ref);
  return ref.watch(staffRequestApiProvider).ownerRequests(status: status);
});
