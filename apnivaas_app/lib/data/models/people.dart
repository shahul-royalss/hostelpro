/// Rows for the owner/warden side of the 1.3.0 round: join requests, staff deletion and plans.
/// Built only against docs/self-signup-api.md (§3, §5, §6, §7).
///
/// LENIENT ON PURPOSE. Every value here is DISPLAYED, never sent back as authority: the request
/// id goes back to `ow_decide_join_request`, which re-checks everything, and the plan id goes to
/// `subscription-order`, which reads the amount from its own table. So a missing optional column
/// is drawn as "not given" rather than failing the whole list.
library;

import 'signup.dart' show documentKinds;

String? _s(Map row, String key) {
  final v = row[key];
  if (v == null) return null;
  final text = v.toString().trim();
  return text.isEmpty ? null : text;
}

int _i(Map row, String key) {
  final v = row[key];
  if (v is num) return v.round();
  return int.tryParse('${v ?? ''}') ?? 0;
}

DateTime? _t(Map row, String key) {
  final v = _s(row, key);
  return v == null ? null : DateTime.tryParse(v)?.toLocal();
}

/// Lists from PostgREST arrive as a List of Maps; a single jsonb as a Map.
List<Map<String, dynamic>> rowsOf(Object? data) {
  if (data is List) {
    return [
      for (final r in data)
        if (r is Map) r.cast<String, dynamic>(),
    ];
  }
  if (data is Map) return [data.cast<String, dynamic>()];
  return const [];
}

Map<String, dynamic>? rowOf(Object? data) {
  final rows = rowsOf(data);
  return rows.isEmpty ? null : rows.first;
}

/// One identity document attached to a join request (`documents` jsonb).
class ReviewDocument {
  const ReviewDocument({required this.id, required this.kind, required this.storagePath, this.createdAt});

  factory ReviewDocument.fromJson(Map<String, dynamic> row) => ReviewDocument(
        id: _s(row, 'id') ?? '',
        kind: _s(row, 'kind') ?? 'other',
        storagePath: _s(row, 'storage_path') ?? '',
        createdAt: _t(row, 'created_at'),
      );

  final String id;
  final String kind;
  final String storagePath;
  final DateTime? createdAt;

  String get label => documentKinds[kind] ?? 'Document';
  bool get isPdf => storagePath.toLowerCase().endsWith('.pdf');
}

/// One row of `ow_join_requests`.
class ReviewJoinRequest {
  const ReviewJoinRequest({
    required this.requestId,
    required this.hostelId,
    required this.hostelName,
    required this.userId,
    required this.fullName,
    required this.status,
    this.phone,
    this.email,
    this.avatarPath,
    this.gender,
    this.dateOfBirth,
    this.emergencyName,
    this.emergencyPhone,
    this.message,
    this.createdAt,
    this.decidedAt,
    this.decisionNote,
    this.documents = const [],
  });

  factory ReviewJoinRequest.fromJson(Map<String, dynamic> row) {
    final docs = row['documents'];
    return ReviewJoinRequest(
      requestId: _s(row, 'request_id') ?? '',
      hostelId: _s(row, 'hostel_id') ?? '',
      hostelName: _s(row, 'hostel_name') ?? 'Your PG',
      userId: _s(row, 'user_id') ?? '',
      fullName: _s(row, 'full_name') ?? 'Someone',
      status: _s(row, 'status') ?? 'pending',
      phone: _s(row, 'phone'),
      email: _s(row, 'email'),
      avatarPath: _s(row, 'avatar_path'),
      gender: _s(row, 'gender'),
      dateOfBirth: _t(row, 'date_of_birth'),
      emergencyName: _s(row, 'emergency_contact_name'),
      emergencyPhone: _s(row, 'emergency_contact_phone'),
      message: _s(row, 'message'),
      createdAt: _t(row, 'created_at'),
      decidedAt: _t(row, 'decided_at'),
      decisionNote: _s(row, 'decision_note'),
      documents: [
        for (final d in rowsOf(docs is List ? docs : const []))
          if ((d['storage_path'] ?? '').toString().isNotEmpty) ReviewDocument.fromJson(d),
      ],
    );
  }

  final String requestId;
  final String hostelId;
  final String hostelName;
  final String userId;
  final String fullName;
  final String status;
  final String? phone;
  final String? email;
  final String? avatarPath;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? message;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String? decisionNote;
  final List<ReviewDocument> documents;

  bool get isPending => status == 'pending';

  String? get genderLabel => switch (gender) {
        'male' => 'Male',
        'female' => 'Female',
        'other' => 'Other',
        _ => null,
      };

  /// Whole years on [today]; null without a date of birth.
  int? ageOn(DateTime today) {
    final dob = dateOfBirth;
    if (dob == null) return null;
    var years = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) years--;
    return years < 0 ? null : years;
  }
}

/// One row of `plan_catalog()`. Display only: the app never sends an amount.
class PlanOption {
  const PlanOption({
    required this.planId,
    required this.name,
    required this.months,
    required this.bonusMonths,
    required this.totalMonths,
    required this.pricePerMonth,
    required this.amount,
    required this.savingVsMonthly,
    required this.sortOrder,
  });

  factory PlanOption.fromJson(Map<String, dynamic> row) => PlanOption(
        planId: _s(row, 'plan_id') ?? '',
        name: _s(row, 'name') ?? 'Plan',
        months: _i(row, 'months'),
        bonusMonths: _i(row, 'bonus_months'),
        totalMonths: _i(row, 'total_months'),
        pricePerMonth: _i(row, 'price_per_month'),
        amount: _i(row, 'amount'),
        savingVsMonthly: _i(row, 'saving_vs_monthly'),
        sortOrder: _i(row, 'sort_order'),
      );

  final String planId;
  final String name;
  final int months;
  final int bonusMonths;
  final int totalMonths;

  /// Rupees.
  final int pricePerMonth;

  /// Rupees, the whole payment.
  final int amount;

  /// Rupees saved against the monthly price for the same total months.
  final int savingVsMonthly;
  final int sortOrder;
}

/// `ow_plan_status.state`.
enum PlanState { trial, active, expiring, expired, unknown }

/// `ow_plan_status(p_hostel_id)`.
class PlanStatus {
  const PlanStatus({
    required this.hostelId,
    required this.hostelName,
    required this.state,
    this.planKind,
    this.startDate,
    this.endDate,
    this.daysLeft,
    this.writable = true,
    this.lastPaymentPlanId,
    this.lastPaidAt,
  });

  factory PlanStatus.fromJson(Map<String, dynamic> row) {
    final last = row['last_payment'];
    final lastRow = last is Map ? last.cast<String, dynamic>() : null;
    final days = row['days_left'];
    return PlanStatus(
      hostelId: _s(row, 'hostel_id') ?? '',
      hostelName: _s(row, 'hostel_name') ?? 'Your PG',
      state: switch (_s(row, 'state')) {
        'trial' => PlanState.trial,
        'active' => PlanState.active,
        'expiring' => PlanState.expiring,
        'expired' => PlanState.expired,
        _ => PlanState.unknown,
      },
      planKind: _s(row, 'plan_kind'),
      startDate: _t(row, 'start_date'),
      endDate: _t(row, 'end_date'),
      daysLeft: days is num ? days.round() : int.tryParse('${days ?? ''}'),
      writable: row['writable'] != false,
      lastPaymentPlanId: lastRow == null ? null : _s(lastRow, 'plan_id'),
      lastPaidAt: lastRow == null ? null : _t(lastRow, 'paid_at'),
    );
  }

  final String hostelId;
  final String hostelName;
  final PlanState state;
  final String? planKind;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? daysLeft;
  final bool writable;
  final String? lastPaymentPlanId;
  final DateTime? lastPaidAt;

  bool get ended => state == PlanState.expired;
}

/// What `subscription-order` `create` hands back: everything checkout needs, all the server's.
class PlanOrder {
  const PlanOrder({
    required this.orderId,
    required this.keyId,
    required this.amountPaise,
    required this.currency,
    required this.planName,
    required this.hostelName,
    this.prefillName,
    this.prefillEmail,
  });

  factory PlanOrder.fromJson(Map<String, dynamic> row) {
    final prefill = row['prefill'];
    final p = prefill is Map ? prefill.cast<String, dynamic>() : const <String, dynamic>{};
    return PlanOrder(
      orderId: _s(row, 'order_id') ?? '',
      keyId: _s(row, 'key_id') ?? '',
      amountPaise: _i(row, 'amount_paise'),
      currency: _s(row, 'currency') ?? 'INR',
      planName: _s(row, 'plan_name') ?? 'Plan',
      hostelName: _s(row, 'hostel_name') ?? 'Apnivaas',
      prefillName: _s(p, 'name'),
      prefillEmail: _s(p, 'email'),
    );
  }

  final String orderId;
  final String keyId;
  final int amountPaise;
  final String currency;
  final String planName;
  final String hostelName;
  final String? prefillName;
  final String? prefillEmail;

  bool get usable => orderId.isNotEmpty && keyId.isNotEmpty && amountPaise > 0;
}

/// `subscription-order` `verify`: `paid` and `duplicate` are both success.
class PlanActivation {
  const PlanActivation({required this.outcome, this.periodEnd});

  factory PlanActivation.fromJson(Map<String, dynamic> row) =>
      PlanActivation(outcome: _s(row, 'outcome') ?? 'paid', periodEnd: _t(row, 'period_end'));

  final String outcome;
  final DateTime? periodEnd;
}

/// One row of `sa_demo_requests`.
class DemoRequestRow {
  const DemoRequestRow({
    required this.id,
    required this.status,
    this.ownerName,
    this.ownerEmail,
    this.name,
    this.phone,
    this.pgName,
    this.city,
    this.bedBand,
    this.slotStart,
    this.note,
    this.createdAt,
  });

  factory DemoRequestRow.fromJson(Map<String, dynamic> row) => DemoRequestRow(
        id: _s(row, 'id') ?? '',
        status: _s(row, 'status') ?? 'requested',
        ownerName: _s(row, 'owner_name'),
        ownerEmail: _s(row, 'owner_email'),
        name: _s(row, 'name'),
        phone: _s(row, 'phone'),
        pgName: _s(row, 'pg_name'),
        city: _s(row, 'city'),
        bedBand: _s(row, 'bed_band'),
        slotStart: _t(row, 'slot_start'),
        note: _s(row, 'note'),
        createdAt: _t(row, 'created_at'),
      );

  final String id;
  final String status;
  final String? ownerName;
  final String? ownerEmail;
  final String? name;
  final String? phone;
  final String? pgName;
  final String? city;
  final String? bedBand;
  final DateTime? slotStart;
  final String? note;
  final DateTime? createdAt;
}

/// The statuses `sa_update_demo_request` accepts, with their labels.
const demoStatuses = <String, String>{
  'requested': 'Requested',
  'confirmed': 'Confirmed',
  'done': 'Done',
  'no_show': 'No show',
  'cancelled': 'Cancelled',
};
