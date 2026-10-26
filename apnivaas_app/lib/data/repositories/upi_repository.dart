/// UPI settings, the tenant's payment claims and the warden/owner confirmation
/// (docs/round3-api.md §9). A claim is never "paid" until a warden or owner confirms it.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/perf/session_keep_alive.dart';
import '../models/upi.dart';
import '../providers.dart' show supabaseClientProvider;
import 'signup_repository.dart' show SignupFailure;

abstract interface class UpiApi {
  /// Null hostel means the caller's own PG; null result means not set up.
  Future<UpiSettings?> settings({String? hostelId});
  Future<UpiSettings?> saveSettings(String hostelId, {required String vpa, required String payeeName});

  Future<PaymentClaim?> submitClaim({
    required double amount,
    required String periodMonth,
    required String utr,
  });
  Future<List<PaymentClaim>> myClaims({int limit = 20});
  Future<PaymentClaim?> cancelClaim(String claimId);

  Future<List<PaymentClaim>> claims(String hostelId, {String? status = 'pending'});
  Future<PaymentClaim?> decide(String claimId, {required bool confirm, String? note});
}

final class UpiRepository implements UpiApi {
  const UpiRepository(this.db);
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
  Future<UpiSettings?> settings({String? hostelId}) async =>
      UpiSettings.tryParse(await _rpc('hostel_upi_settings', {'p_hostel_id': hostelId}));

  @override
  Future<UpiSettings?> saveSettings(String hostelId,
          {required String vpa, required String payeeName}) async =>
      UpiSettings.tryParse(await _rpc('ow_set_upi_settings', {
        'p_hostel_id': hostelId,
        'p_upi_vpa': normalizeVpa(vpa),
        'p_payee_name': payeeName.trim(),
      }));

  @override
  Future<PaymentClaim?> submitClaim({
    required double amount,
    required String periodMonth,
    required String utr,
  }) async =>
      PaymentClaim.tryParse(await _rpc('st_submit_payment_claim', {
        'p_amount': amount,
        'p_period_month': periodMonth,
        'p_utr': normalizeUtr(utr),
      }));

  @override
  Future<List<PaymentClaim>> myClaims({int limit = 20}) async =>
      PaymentClaim.listFrom(await _rpc('st_my_payment_claims', {'p_limit': limit}));

  @override
  Future<PaymentClaim?> cancelClaim(String claimId) async =>
      PaymentClaim.tryParse(await _rpc('st_cancel_payment_claim', {'p_claim_id': claimId}));

  @override
  Future<List<PaymentClaim>> claims(String hostelId, {String? status = 'pending'}) async =>
      PaymentClaim.listFrom(
          await _rpc('wd_payment_claims', {'p_hostel_id': hostelId, 'p_status': status}));

  @override
  Future<PaymentClaim?> decide(String claimId, {required bool confirm, String? note}) async {
    final n = note?.trim();
    return PaymentClaim.tryParse(await _rpc('wd_decide_payment_claim', {
      'p_claim_id': claimId,
      'p_confirm': confirm,
      'p_note': (n == null || n.isEmpty) ? null : n,
    }));
  }
}

final upiApiProvider = Provider<UpiApi>((ref) => UpiRepository(ref.watch(supabaseClientProvider)));

/// Settings for a PG (null key: the caller's own PG).
final upiSettingsProvider =
    FutureProvider.autoDispose.family<UpiSettings?, String?>((ref, hostelId) {
  holdForSession(ref);
  return ref.watch(upiApiProvider).settings(hostelId: hostelId);
});

final myPaymentClaimsProvider = FutureProvider.autoDispose<List<PaymentClaim>>((ref) {
  holdForSession(ref);
  return ref.watch(upiApiProvider).myClaims();
});

/// Pending claims for one PG (warden or owner).
final pendingClaimsProvider =
    FutureProvider.autoDispose.family<List<PaymentClaim>, String>((ref, hostelId) {
  holdForSession(ref);
  return ref.watch(upiApiProvider).claims(hostelId);
});

/// Every claim for one PG, newest first.
final allClaimsProvider =
    FutureProvider.autoDispose.family<List<PaymentClaim>, String>((ref, hostelId) =>
        ref.watch(upiApiProvider).claims(hostelId, status: null));

// ── Opening a UPI app ───────────────────────────────────────────────────────────────────────

/// Hands a `upi://pay` link to an installed UPI app as an Android intent (never a browser).
abstract interface class UpiLauncher {
  /// False when no UPI app could take it. The app's answer is never trusted either way.
  Future<bool> launch(Uri uri);
}

final class ChannelUpiLauncher implements UpiLauncher {
  const ChannelUpiLauncher();
  static const _channel = MethodChannel('apnivaas/upi');

  @override
  Future<bool> launch(Uri uri) async {
    if (uri.scheme != 'upi') return false;
    try {
      return await _channel.invokeMethod<bool>('pay', {'uri': uri.toString()}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final upiLauncherProvider = Provider<UpiLauncher>((_) => const ChannelUpiLauncher());
