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

/// The four UPI apps offered by name (R4.3), each opened by a package-targeted intent.
enum UpiApp {
  phonepe('PhonePe', 'com.phonepe.app'),
  paytm('Paytm', 'net.one97.paytm'),
  gpay('Google Pay', 'com.google.android.apps.nbu.paisa.user'),
  bhim('BHIM', 'in.org.npci.upiapp');

  const UpiApp(this.label, this.package);
  final String label;
  final String package;
}

/// What came back from a UPI app: whether one opened, and its response string (a hint only).
class UpiLaunchResult {
  const UpiLaunchResult({required this.opened, this.response = const UpiResponse()});
  final bool opened;
  final UpiResponse response;
}

/// Hands a `upi://pay` link to a UPI app as an Android intent (never a browser).
abstract interface class UpiLauncher {
  /// Which of [UpiApp] are installed and can take a `upi://pay` link.
  Future<Set<UpiApp>> installedApps();

  /// Opens [app] directly, or the system chooser when [app] is null.
  Future<UpiLaunchResult> launch(Uri uri, {UpiApp? app});
}

final class ChannelUpiLauncher implements UpiLauncher {
  const ChannelUpiLauncher();
  static const _channel = MethodChannel('apnivaas/upi');

  @override
  Future<Set<UpiApp>> installedApps() async {
    try {
      final raw = await _channel.invokeListMethod<String>('installed', {
        'packages': [for (final a in UpiApp.values) a.package],
      });
      final found = raw?.toSet() ?? const <String>{};
      return {for (final a in UpiApp.values) if (found.contains(a.package)) a};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  @override
  Future<UpiLaunchResult> launch(Uri uri, {UpiApp? app}) async {
    if (uri.scheme != 'upi' || uri.host != 'pay') return const UpiLaunchResult(opened: false);
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('pay', {
        'uri': uri.toString(),
        'package': ?app?.package,
      });
      final opened = raw?['opened'] == true;
      final response = raw?['response'];
      return UpiLaunchResult(
        opened: opened,
        response: UpiResponse.parse(response is String ? response : null),
      );
    } on PlatformException {
      return const UpiLaunchResult(opened: false);
    } on MissingPluginException {
      return const UpiLaunchResult(opened: false);
    }
  }
}

final upiLauncherProvider = Provider<UpiLauncher>((_) => const ChannelUpiLauncher());

/// The installed named UPI apps, read once per sheet.
final installedUpiAppsProvider = FutureProvider.autoDispose<Set<UpiApp>>(
    (ref) => ref.watch(upiLauncherProvider).installedApps());
