/// Cashfree rent (2026-11-04): which gateway a tenant's rent uses, Cashfree orders and their
/// status, the owner's Easy Split vendor account, payments, settlements and refunds.
///
/// Every money decision is the server's: this file sends no amount, owner or vendor, and reads
/// payment states only from the database (rent_payments) or from cashfree-order's `status`, which
/// re-reads Cashfree first. See supabase/functions/cashfree-*/ and docs/cashfree-rent.md.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers.dart' show supabaseClientProvider;
import 'signup_repository.dart' show SignupFailure;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// What st_rent_gateway answers for the signed-in tenant.
class RentGateway {
  const RentGateway({required this.gateway, required this.ready, this.message});
  final String gateway;
  final bool ready;
  final String? message;

  bool get isRazorpay => gateway == 'razorpay';

  factory RentGateway.fromJson(Map<String, dynamic> j) => RentGateway(
        gateway: _str(j['gateway']) ?? 'cashfree',
        ready: j['ready'] == true,
        message: _str(j['message']),
      );
}

/// A Cashfree order opened by cashfree-order, ready for the SDK's checkout.
class CashfreeOrder {
  const CashfreeOrder({
    required this.orderId,
    required this.paymentSessionId,
    required this.amountPaise,
    required this.periodMonth,
    required this.sandbox,
  });
  final String orderId;
  final String paymentSessionId;
  final int amountPaise;
  final String periodMonth;
  final bool sandbox;

  factory CashfreeOrder.fromJson(Map<String, dynamic> j) => CashfreeOrder(
        orderId: '${j['order_id']}',
        paymentSessionId: '${j['payment_session_id']}',
        amountPaise: _int(j['amount_paise']),
        periodMonth: '${j['period_month'] ?? ''}',
        sandbox: j['environment'] != 'production',
      );
}

enum PayState { initiated, pending, success, failed, cancelled, refunded }

enum SettleState { notStarted, splitPending, splitCreated, settlementPending, settled, settlementFailed }

PayState payStateOf(String? s) => switch (s) {
      'PENDING' => PayState.pending,
      'SUCCESS' => PayState.success,
      'FAILED' => PayState.failed,
      'CANCELLED' => PayState.cancelled,
      'REFUNDED' => PayState.refunded,
      _ => PayState.initiated,
    };

SettleState settleStateOf(String? s) => switch (s) {
      'SPLIT_PENDING' => SettleState.splitPending,
      'SPLIT_CREATED' => SettleState.splitCreated,
      'SETTLEMENT_PENDING' => SettleState.settlementPending,
      'SETTLED' => SettleState.settled,
      'SETTLEMENT_FAILED' => SettleState.settlementFailed,
      _ => SettleState.notStarted,
    };

/// One rent_payments row, as the tenant, the owner or the Super Admin may read it.
class RentPayment {
  const RentPayment({
    required this.id,
    required this.orderId,
    required this.periodMonth,
    required this.amountPaise,
    required this.status,
    required this.settlement,
    this.tenantId,
    this.tenantName,
    this.pgName,
    this.receiptNo,
    this.paymentId,
    this.bankReference,
    this.paidAt,
    this.createdAt,
    this.failureReason,
    this.refundedPaise = 0,
    this.overpaid = false,
    this.creditError,
    this.settlementUtr,
    this.settledAt,
  });

  final String id;
  final String orderId;
  final String periodMonth;
  final int amountPaise;
  final PayState status;
  final SettleState settlement;
  final String? tenantId;
  final String? tenantName;
  final String? pgName;
  final String? receiptNo;
  final String? paymentId;
  final String? bankReference;
  final DateTime? paidAt;
  final DateTime? createdAt;
  final String? failureReason;
  final int refundedPaise;
  final bool overpaid;
  final String? creditError;
  final String? settlementUtr;
  final DateTime? settledAt;

  static const columns =
      'id, cashfree_order_id, period_month, amount_in_paise, payment_status, settlement_status, tenant_id, '
      'receipt_no, cashfree_payment_id, bank_reference, payment_time, created_at, failure_reason, '
      'refunded_paise, overpaid, credit_error, settlement_utr, settled_at, '
      'students(full_name), hostels(name)';

  bool get isFinal => status == PayState.success || status == PayState.refunded;
  int get refundablePaise => status == PayState.success ? amountPaise - refundedPaise : 0;

  factory RentPayment.fromJson(Map<String, dynamic> j) {
    final student = j['students'];
    final hostel = j['hostels'];
    return RentPayment(
      id: '${j['id']}',
      orderId: '${j['cashfree_order_id']}',
      periodMonth: '${j['period_month'] ?? ''}',
      amountPaise: _int(j['amount_in_paise']),
      status: payStateOf(_str(j['payment_status'])),
      settlement: settleStateOf(_str(j['settlement_status'])),
      tenantId: _str(j['tenant_id']),
      tenantName: student is Map ? _str(student['full_name']) : null,
      pgName: hostel is Map ? _str(hostel['name']) : null,
      receiptNo: _str(j['receipt_no']),
      paymentId: _str(j['cashfree_payment_id']),
      bankReference: _str(j['bank_reference']),
      paidAt: _date(j['payment_time']),
      createdAt: _date(j['created_at']),
      failureReason: _str(j['failure_reason']),
      refundedPaise: _int(j['refunded_paise']),
      overpaid: j['overpaid'] == true,
      creditError: _str(j['credit_error']),
      settlementUtr: _str(j['settlement_utr']),
      settledAt: _date(j['settled_at']),
    );
  }
}

/// The owner's Cashfree vendor account, as stored (the server never returns the PAN).
class OwnerPaymentAccount {
  const OwnerPaymentAccount({
    required this.vendorStatus,
    required this.verification,
    required this.legalName,
    required this.email,
    required this.phone,
    required this.upiVpa,
    required this.beneficiaryName,
    this.panLast4,
    this.gstin,
    this.scheduleMessage,
    this.lastError,
    this.activatedAt,
  });

  final String vendorStatus;
  final String verification;
  final String legalName;
  final String email;
  final String phone;
  final String upiVpa;
  final String beneficiaryName;
  final String? panLast4;
  final String? gstin;
  final String? scheduleMessage;
  final String? lastError;
  final DateTime? activatedAt;

  bool get verified => verification == 'verified' && vendorStatus == 'ACTIVE';
  bool get rejected => verification == 'rejected';

  factory OwnerPaymentAccount.fromJson(Map<String, dynamic> j) => OwnerPaymentAccount(
        vendorStatus: _str(j['vendor_status']) ?? '',
        verification: _str(j['verification_status']) ?? 'pending',
        legalName: _str(j['legal_name']) ?? '',
        email: _str(j['email']) ?? '',
        phone: _str(j['phone']) ?? '',
        upiVpa: _str(j['upi_vpa']) ?? '',
        beneficiaryName: _str(j['beneficiary_name']) ?? '',
        panLast4: _str(j['pan_last4']),
        gstin: _str(j['gstin']),
        scheduleMessage: _str(j['settlement_schedule_message']),
        lastError: _str(j['last_error']),
        activatedAt: _date(j['activated_at']),
      );
}

/// ow_rent_payment_summary: the owner dashboard's figures, in paise.
class RentPaymentSummary {
  const RentPaymentSummary({
    this.collectedPaise = 0,
    this.collectedThisMonthPaise = 0,
    this.verifiedCount = 0,
    this.awaitingSettlementPaise = 0,
    this.settledPaise = 0,
    this.failedSettlements = 0,
    this.needsAttention = 0,
    this.pendingRentPaise = 0,
  });

  final int collectedPaise;
  final int collectedThisMonthPaise;
  final int verifiedCount;
  final int awaitingSettlementPaise;
  final int settledPaise;
  final int failedSettlements;
  final int needsAttention;
  final int pendingRentPaise;

  factory RentPaymentSummary.fromJson(Map<String, dynamic> j) => RentPaymentSummary(
        collectedPaise: _int(j['collected_paise']),
        collectedThisMonthPaise: _int(j['collected_this_month_paise']),
        verifiedCount: _int(j['verified_count']),
        awaitingSettlementPaise: _int(j['awaiting_settlement_paise']),
        settledPaise: _int(j['settled_paise']),
        failedSettlements: _int(j['failed_settlements']),
        needsAttention: _int(j['needs_attention']),
        pendingRentPaise: _int(j['pending_rent_paise']),
      );
}

/// One Cashfree settlement to the owner's UPI ID (a batch row from a settlement webhook).
class OwnerSettlement {
  const OwnerSettlement({required this.settlementId, required this.status, this.amount, this.utr, this.settledAt, this.reason});
  final String settlementId;
  final String status;
  final double? amount;
  final String? utr;
  final DateTime? settledAt;
  final String? reason;

  factory OwnerSettlement.fromJson(Map<String, dynamic> j) => OwnerSettlement(
        settlementId: '${j['settlement_id']}',
        status: _str(j['settlement_status']) ?? 'PENDING',
        amount: j['settlement_amount'] is num ? (j['settlement_amount'] as num).toDouble() : double.tryParse('${j['settlement_amount']}'),
        utr: _str(j['settlement_reference']),
        settledAt: _date(j['settled_at']),
        reason: _str(j['failure_reason']),
      );
}

abstract interface class CashfreeApi {
  Future<RentGateway> gateway();
  Future<CashfreeOrder> createOrder();
  Future<RentPayment?> orderStatus(String orderId);
  Future<List<RentPayment>> myPayments();
  Future<List<RentPayment>> payments({String? hostelId, int limit = 100});
  Future<RentPaymentSummary> ownerSummary();
  Future<List<OwnerSettlement>> settlements();
  Future<({OwnerPaymentAccount? account, bool configured})> account({bool refresh = false});
  Future<OwnerPaymentAccount?> submitAccount(Map<String, String> fields);
  Future<String> refund({required String paymentId, required int amountPaise, String? note});
}

final class CashfreeRepository implements CashfreeApi {
  const CashfreeRepository(this.db);
  final SupabaseClient db;

  static const _deadline = Duration(seconds: 25);

  Future<T> _run<T>(Future<T> Function() body) async {
    try {
      return await body().timeout(_deadline);
    } on SignupFailure {
      rethrow;
    } catch (e, stack) {
      Error.throwWithStackTrace(SignupFailure.from(e), stack);
    }
  }

  /// `{ok: true, data}` or a refusal whose sentence is shown as it is; branch on `code`.
  Future<Map<String, dynamic>> _fn(String name, Map<String, dynamic> body) => _run(() async {
        try {
          final response = await db.functions.invoke(name, body: body);
          final envelope = response.data;
          if (envelope is Map && envelope['ok'] == false) {
            throw SignupFailure('${envelope['error'] ?? 'Something went wrong. Please try again.'}',
                code: envelope['code']?.toString());
          }
          final data = envelope is Map ? envelope['data'] : null;
          return data is Map ? data.cast<String, dynamic>() : const <String, dynamic>{};
        } on FunctionException catch (e) {
          final d = e.details;
          if (d is Map && d['error'] is String) {
            throw SignupFailure(d['error'] as String, code: d['code']?.toString());
          }
          throw SignupFailure(switch (e.status) {
            401 => 'Your session has ended. Sign in again.',
            404 => 'This is not available on the server yet. Please try again later.',
            429 => 'Too many attempts. Please wait a minute and try again.',
            503 => 'Online payment is not available right now. Please pay your PG directly.',
            _ => 'Apnivaas could not finish that. Please try again in a minute.',
          });
        }
      });

  @override
  Future<RentGateway> gateway() => _run(() async {
        final data = await db.rpc('st_rent_gateway');
        return RentGateway.fromJson(data is Map ? data.cast<String, dynamic>() : const {});
      });

  @override
  Future<CashfreeOrder> createOrder() async =>
      CashfreeOrder.fromJson(await _fn('cashfree-order', const {'action': 'create'}));

  @override
  Future<RentPayment?> orderStatus(String orderId) async {
    final data = await _fn('cashfree-order', {'action': 'status', 'order_id': orderId});
    if (data.isEmpty) return null;
    return RentPayment.fromJson(data);
  }

  @override
  Future<List<RentPayment>> myPayments() => payments();

  @override
  Future<List<RentPayment>> payments({String? hostelId, int limit = 100}) => _run(() async {
        var q = db.from('rent_payments').select(RentPayment.columns);
        if (hostelId != null) q = q.eq('pg_id', hostelId);
        final rows = await q.order('created_at', ascending: false).limit(limit);
        return [for (final r in rows) RentPayment.fromJson(r)];
      });

  @override
  Future<RentPaymentSummary> ownerSummary() => _run(() async {
        final data = await db.rpc('ow_rent_payment_summary');
        return RentPaymentSummary.fromJson(data is Map ? data.cast<String, dynamic>() : const {});
      });

  @override
  Future<List<OwnerSettlement>> settlements() => _run(() async {
        final rows = await db
            .from('owner_settlements')
            .select('settlement_id, settlement_amount, settlement_status, settlement_reference, settled_at, failure_reason')
            .isFilter('payment_id', null)
            .order('created_at', ascending: false)
            .limit(50);
        return [for (final r in rows) OwnerSettlement.fromJson(r)];
      });

  @override
  Future<({OwnerPaymentAccount? account, bool configured})> account({bool refresh = false}) async {
    final data = await _fn('cashfree-vendor', {'action': refresh ? 'refresh' : 'get'});
    final a = data['account'];
    return (
      account: a is Map ? OwnerPaymentAccount.fromJson(a.cast<String, dynamic>()) : null,
      configured: data['configured'] != false,
    );
  }

  @override
  Future<OwnerPaymentAccount?> submitAccount(Map<String, String> fields) async {
    final data = await _fn('cashfree-vendor', {'action': 'submit', ...fields});
    final a = data['account'];
    return a is Map ? OwnerPaymentAccount.fromJson(a.cast<String, dynamic>()) : null;
  }

  @override
  Future<String> refund({required String paymentId, required int amountPaise, String? note}) async {
    final data = await _fn('cashfree-refund', {
      'payment_id': paymentId,
      'amount_paise': amountPaise,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return '${data['status'] ?? 'PENDING'}';
  }
}

final cashfreeApiProvider = Provider<CashfreeApi>((ref) => CashfreeRepository(ref.watch(supabaseClientProvider)));

final rentGatewayProvider = FutureProvider.autoDispose<RentGateway>((ref) => ref.watch(cashfreeApiProvider).gateway());
final myRentPaymentsProvider =
    FutureProvider.autoDispose<List<RentPayment>>((ref) => ref.watch(cashfreeApiProvider).myPayments());
final ownerRentPaymentsProvider =
    FutureProvider.autoDispose<List<RentPayment>>((ref) => ref.watch(cashfreeApiProvider).payments());
final ownerRentSummaryProvider =
    FutureProvider.autoDispose<RentPaymentSummary>((ref) => ref.watch(cashfreeApiProvider).ownerSummary());
final ownerSettlementsProvider =
    FutureProvider.autoDispose<List<OwnerSettlement>>((ref) => ref.watch(cashfreeApiProvider).settlements());
final ownerPaymentAccountProvider = FutureProvider.autoDispose<({OwnerPaymentAccount? account, bool configured})>(
    (ref) => ref.watch(cashfreeApiProvider).account());
final hostelRentPaymentsProvider = FutureProvider.autoDispose.family<List<RentPayment>, String>(
    (ref, hostelId) => ref.watch(cashfreeApiProvider).payments(hostelId: hostelId));
