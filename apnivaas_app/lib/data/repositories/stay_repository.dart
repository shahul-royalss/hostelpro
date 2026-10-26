/// Round 3 stay RPCs (docs/round3-api.md §3 and §7): timeline, months since check-in and
/// check-out requests. Refusals are [SignupFailure]s carrying the server's sentence verbatim,
/// with `field` naming the input when the server gave a hint.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/perf/session_keep_alive.dart';
import '../models/stay.dart';
import '../providers.dart' show supabaseClientProvider, currentHostelIdProvider;
import 'signup_repository.dart' show SignupFailure;

abstract interface class StayApi {
  Future<List<TimelineEntry>> timeline({String? studentId});
  Future<List<FeeMonth>> feeMonths({String? studentId});

  Future<CheckoutRequest?> requestCheckout({required DateTime preferredDate, String? reason});
  Future<CheckoutRequest?> myCheckoutRequest();
  Future<CheckoutRequest?> cancelCheckoutRequest();

  Future<List<CheckoutRequestRow>> checkoutRequests(String hostelId, {String? status});
  Future<CheckoutRequest?> decideCheckout(
    String requestId, {
    required bool accept,
    DateTime? checkoutDate,
    String? note,
  });
  Future<CheckoutSummary> checkoutSummary({String? hostelId});
}

final class StayRepository implements StayApi {
  const StayRepository(this.db);
  final SupabaseClient db;

  static const _deadline = Duration(seconds: 20);

  Future<Object?> _rpc(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await db.rpc(fn, params: params).timeout(_deadline);
    } catch (e, stack) {
      Error.throwWithStackTrace(SignupFailure.from(e), stack);
    }
  }

  @override
  Future<List<TimelineEntry>> timeline({String? studentId}) async =>
      TimelineEntry.listFrom(await _rpc('st_timeline', {'p_student_id': studentId}));

  @override
  Future<List<FeeMonth>> feeMonths({String? studentId}) async =>
      FeeMonth.listFrom(await _rpc('rpc_student_fee_months', {'p_student_id': studentId}));

  @override
  Future<CheckoutRequest?> requestCheckout({
    required DateTime preferredDate,
    String? reason,
  }) async {
    final r = reason?.trim();
    return CheckoutRequest.tryParse(await _rpc('st_request_checkout', {
      'p_preferred_date': dateWire(preferredDate),
      'p_reason': (r == null || r.isEmpty) ? null : r,
    }));
  }

  @override
  Future<CheckoutRequest?> myCheckoutRequest() async =>
      CheckoutRequest.tryParse(await _rpc('st_my_checkout_request'));

  @override
  Future<CheckoutRequest?> cancelCheckoutRequest() async =>
      CheckoutRequest.tryParse(await _rpc('st_cancel_checkout_request'));

  @override
  Future<List<CheckoutRequestRow>> checkoutRequests(String hostelId, {String? status}) async =>
      CheckoutRequestRow.listFrom(
          await _rpc('wd_checkout_requests', {'p_hostel_id': hostelId, 'p_status': status}));

  @override
  Future<CheckoutRequest?> decideCheckout(
    String requestId, {
    required bool accept,
    DateTime? checkoutDate,
    String? note,
  }) async {
    final n = note?.trim();
    return CheckoutRequest.tryParse(await _rpc('wd_decide_checkout_request', {
      'p_request_id': requestId,
      'p_accept': accept,
      'p_checkout_date': checkoutDate == null ? null : dateWire(checkoutDate),
      'p_note': (n == null || n.isEmpty) ? null : n,
    }));
  }

  @override
  Future<CheckoutSummary> checkoutSummary({String? hostelId}) async =>
      CheckoutSummary.parse(await _rpc('ow_checkout_summary', {'p_hostel_id': hostelId}));
}

final stayApiProvider = Provider<StayApi>((ref) => StayRepository(ref.watch(supabaseClientProvider)));

/// The signed-in tenant's own timeline.
final myTimelineProvider = FutureProvider.autoDispose<List<TimelineEntry>>((ref) {
  holdForSession(ref);
  return ref.watch(stayApiProvider).timeline();
});

/// The signed-in tenant's open (or latest) check-out request.
final myCheckoutRequestProvider = FutureProvider.autoDispose<CheckoutRequest?>((ref) {
  holdForSession(ref);
  return ref.watch(stayApiProvider).myCheckoutRequest();
});

/// The warden's list for one PG: pending first, then accepted, then the rest.
final checkoutRequestsProvider =
    FutureProvider.autoDispose.family<List<CheckoutRequestRow>, String>((ref, hostelId) {
  holdForSession(ref);
  return ref.watch(stayApiProvider).checkoutRequests(hostelId);
});

/// Pending requests in the warden's current PG, for the badge. Null while unknown.
final pendingCheckoutCountProvider = Provider.autoDispose<int?>((ref) {
  final hostelId = ref.watch(currentHostelIdProvider);
  if (hostelId == null) return null;
  return ref
      .watch(checkoutRequestsProvider(hostelId))
      .value
      ?.where((r) => r.status == CheckoutStatus.pending)
      .length;
});

/// The owner's home notice: every PG they own.
final ownerCheckoutSummaryProvider = FutureProvider.autoDispose<CheckoutSummary>((ref) {
  holdForSession(ref);
  return ref.watch(stayApiProvider).checkoutSummary();
});
