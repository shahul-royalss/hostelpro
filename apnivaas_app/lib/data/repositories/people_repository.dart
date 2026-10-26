/// The owner/warden side of the 1.3.0 round — join requests, photos, deleting a staff account,
/// plans — built only against docs/self-signup-api.md (§3, §5, §6, §7).
///
/// THE APP NEVER SENDS AUTHORITY. A request id, a yes/no and a note; a user id to delete; a
/// hostel id and a plan id. Who may decide, whose staff it is, and what a plan costs are all
/// decided on the server from `auth.uid()`, and every refusal it writes is shown verbatim
/// ([SignupFailure.message]).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/people.dart';
import '../providers.dart' show supabaseClientProvider;
import 'signup_repository.dart' show SignupFailure;

/// The two private buckets whose objects are opened through a 60-second signed URL.
abstract final class Buckets {
  static const avatars = 'avatars';
  static const documents = 'identity-documents';
}

abstract interface class PeopleApi {
  // ── §5 join requests ──
  Future<int> pendingJoinRequestCount();
  Future<List<ReviewJoinRequest>> joinRequests({String status = 'pending'});
  Future<void> decideJoinRequest(String requestId, {required bool accept, String? note});

  // ── §3 photos ──
  /// A 60-second signed URL, or null when storage refuses (show initials).
  Future<String?> signedUrl(String bucket, String path);

  /// `users.avatar_path` for each id the caller may read; ids it may not are simply absent.
  Future<Map<String, String>> avatarPaths(List<String> userIds);

  /// The caller's own `users.avatar_path`.
  Future<String?> myAvatarPath();

  /// `me_set_avatar(null)`.
  Future<void> removeMyAvatar();

  // ── §6 staff ──
  Future<void> deleteStaffAccount(String userId);

  // ── §7 plans ──
  Future<List<PlanOption>> planCatalog();
  Future<PlanStatus> planStatus(String hostelId);
  Future<PlanOrder> createPlanOrder({required String hostelId, required String planId});
  Future<PlanActivation> verifyPlanPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  });

  // ── §4 demo requests (Super Admin) ──
  Future<List<DemoRequestRow>> demoRequests({String? status});
  Future<void> updateDemoRequest(String id, {required String status, String? note});
}

final class PeopleRepository implements PeopleApi {
  const PeopleRepository(this.db);
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

  /// An Edge Function call. Success is `{ok: true, data}`; a refusal is `{ok: false, error,
  /// code?}`, and the sentence in `error` is shown as it is. Branch on `code`, never wording.
  Future<Map<String, dynamic>> _fn(String name, Map<String, dynamic> body) async {
    try {
      final response = await db.functions.invoke(name, body: body).timeout(_deadline);
      final envelope = response.data;
      if (envelope is Map && envelope['ok'] == false) {
        throw SignupFailure(
          (envelope['error'] ?? 'Something went wrong. Please try again.').toString(),
          code: envelope['code']?.toString(),
        );
      }
      final data = envelope is Map ? envelope['data'] : null;
      return data is Map ? data.cast<String, dynamic>() : const <String, dynamic>{};
    } on FunctionException catch (e, stack) {
      final details = e.details;
      if (details is Map && details['error'] is String) {
        Error.throwWithStackTrace(
          SignupFailure(details['error'] as String, code: details['code']?.toString()),
          stack,
        );
      }
      Error.throwWithStackTrace(
        SignupFailure(switch (e.status) {
          401 => 'Your session has ended. Sign in again.',
          404 => 'This is not available on the server yet. Please try again later.',
          429 => 'Too many attempts. Please wait a minute and try again.',
          _ => 'Apnivaas could not finish that. Please try again in a minute.',
        }),
        stack,
      );
    } catch (e, stack) {
      Error.throwWithStackTrace(SignupFailure.from(e), stack);
    }
  }

  @override
  Future<int> pendingJoinRequestCount() async {
    final v = await _rpc('ow_pending_join_request_count');
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? 0}') ?? 0;
  }

  @override
  Future<List<ReviewJoinRequest>> joinRequests({String status = 'pending'}) async {
    final data = await _rpc('ow_join_requests', {'p_status': status, 'p_limit': 50});
    return [for (final r in rowsOf(data)) ReviewJoinRequest.fromJson(r)];
  }

  @override
  Future<void> decideJoinRequest(String requestId, {required bool accept, String? note}) async {
    final trimmed = note?.trim();
    await _rpc('ow_decide_join_request', {
      'p_request_id': requestId,
      'p_accept': accept,
      'p_note': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    });
  }

  @override
  Future<String?> signedUrl(String bucket, String path) async {
    if (path.isEmpty) return null;
    try {
      return await db.storage.from(bucket).createSignedUrl(path, 60).timeout(_deadline);
    } catch (_) {
      // A refused or missing object is drawn as initials / "could not open", never an error.
      return null;
    }
  }

  @override
  Future<Map<String, String>> avatarPaths(List<String> userIds) => _run(() async {
        if (userIds.isEmpty) return const <String, String>{};
        final rows = await db.from('users').select('id, avatar_path').inFilter('id', userIds);
        return {
          for (final r in rows)
            if (r['avatar_path'] is String && (r['avatar_path'] as String).isNotEmpty)
              r['id'] as String: r['avatar_path'] as String,
        };
      });

  @override
  Future<String?> myAvatarPath() => _run(() async {
        final uid = db.auth.currentUser?.id;
        if (uid == null) return null;
        final row = await db.from('users').select('avatar_path').eq('id', uid).maybeSingle();
        final path = row?['avatar_path'];
        return path is String && path.isNotEmpty ? path : null;
      });

  @override
  Future<void> removeMyAvatar() async {
    await _rpc('me_set_avatar', {'p_path': null});
  }

  @override
  Future<void> deleteStaffAccount(String userId) async {
    await _fn('owner-staff-account', {'action': 'delete', 'userId': userId});
  }

  @override
  Future<List<PlanOption>> planCatalog() async {
    final data = await _rpc('plan_catalog');
    final plans = [for (final r in rowsOf(data)) PlanOption.fromJson(r)]
      ..removeWhere((p) => p.planId.isEmpty)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return plans;
  }

  @override
  Future<PlanStatus> planStatus(String hostelId) async {
    final row = rowOf(await _rpc('ow_plan_status', {'p_hostel_id': hostelId}));
    if (row == null) throw const SignupFailure('Hostel not found.');
    return PlanStatus.fromJson(row);
  }

  @override
  Future<PlanOrder> createPlanOrder({required String hostelId, required String planId}) async {
    final data = await _fn('subscription-order', {
      'action': 'create',
      'hostelId': hostelId,
      'planId': planId,
    });
    final order = PlanOrder.fromJson(data);
    if (!order.usable) {
      throw const SignupFailure('Plan payment is temporarily unavailable. Please try again in a minute.');
    }
    return order;
  }

  @override
  Future<PlanActivation> verifyPlanPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async =>
      PlanActivation.fromJson(await _fn('subscription-order', {
        'action': 'verify',
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
      }));

  @override
  Future<List<DemoRequestRow>> demoRequests({String? status}) async {
    final data = await _rpc('sa_demo_requests', {'p_status': status, 'p_limit': 50});
    return [for (final r in rowsOf(data)) DemoRequestRow.fromJson(r)];
  }

  @override
  Future<void> updateDemoRequest(String id, {required String status, String? note}) async {
    final trimmed = note?.trim();
    await _rpc('sa_update_demo_request', {
      'p_id': id,
      'p_status': status,
      'p_note': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    });
  }
}

final peopleApiProvider = Provider<PeopleApi>(
  (ref) => PeopleRepository(ref.watch(supabaseClientProvider)),
);
