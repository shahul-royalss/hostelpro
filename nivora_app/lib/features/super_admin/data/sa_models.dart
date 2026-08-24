library;

import '../../../data/models/models.dart';
import '../../../data/models/parse.dart';

/// The rows and payloads the Super Admin console needs that lib/data does not already carry.
///
/// WHY THEY LIVE HERE. `SaStats` and `SaHostelRow` are already in lib/data/models/stats.dart,
/// because rpc_sa_dashboard and rpc_sa_hostels are dashboard reads like any other. Everything
/// below belongs to ONE role and to no other: an owner account seen as a pickable option, a
/// subscription's full history, a security alert, and the payload of the create wizard. Modelled
/// to the Super Admin's need, in the Super Admin's directory, following the shared layer's rules
/// exactly — coerced through parse.dart so a wrong column names itself, matched on wire values,
/// never a raw map handed to a widget. Promote any of them into lib/data the moment a second
/// role needs them.

// ─────────────────────────────────────────────────────────────────────────────
// OWNERS — the "existing owner" branch of the create wizard
// ─────────────────────────────────────────────────────────────────────────────

/// One pickable owner account. public.users where role = 'owner'.
///
/// [hostelCount] is counted from public.hostels rather than stored, exactly as the web's
/// fetchOwners() does it: there is no counter column and inventing one on the client would be
/// wrong the first time two hostels were created in one session.
class SaOwnerOption {
  const SaOwnerOption({
    required this.id,
    required this.fullName,
    required this.status,
    required this.hostelCount,
    this.email,
    this.phone,
  });

  static const columns = 'id, full_name, email, phone, status';

  final String id;
  final String fullName;
  final String? email;
  final String? phone;

  /// 'active' | 'inactive'. The edge function refuses an inactive owner, so the picker says so
  /// before the admin reaches step four.
  final String status;

  final int hostelCount;

  bool get isActive => status == 'active';

  factory SaOwnerOption.fromJson(Map<String, dynamic> row, {int hostelCount = 0}) {
    const src = 'users';
    return SaOwnerOption(
      id: reqString(row, src, 'id'),
      fullName: reqString(row, src, 'full_name'),
      email: optString(row, 'email'),
      phone: optString(row, 'phone'),
      status: reqString(row, src, 'status'),
      hostelCount: hostelCount,
    );
  }

  SaOwnerOption withHostelCount(int count) => SaOwnerOption(
        id: id,
        fullName: fullName,
        email: email,
        phone: phone,
        status: status,
        hostelCount: count,
      );

  /// Matches the picker's search box against the three things an admin would type.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fullName.toLowerCase().contains(q) ||
        (email ?? '').toLowerCase().contains(q) ||
        (phone ?? '').toLowerCase().contains(q);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUBSCRIPTIONS
// ─────────────────────────────────────────────────────────────────────────────

/// One row of public.subscriptions — a single paid period for a single hostel.
///
/// A hostel has MANY of these over its life: sa_renew_subscription inserts a new row rather
/// than moving the end date, so the table is the billing history. [SaHostelRow.subEnd] is the
/// latest one; this is all of them.
///
/// [status] is the stored column, maintained by the subscription_status_compute trigger and by
/// refresh_subscription_statuses(). It can lag the calendar by up to a day — the authority on
/// "is this hostel writable right now" is app.subscription_state(), which the Super Admin sees
/// as [SaHostelRow.subState]. Both are shown, and where they disagree the computed one wins.
class SubscriptionRecord {
  const SubscriptionRecord({
    required this.id,
    required this.hostelId,
    required this.ownerUserId,
    required this.startDate,
    required this.endDate,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.notes,
  });

  static const columns =
      'id, hostel_id, owner_user_id, start_date, end_date, amount, status, notes, created_at';

  final String id;
  final String hostelId;
  final String ownerUserId;
  final DateTime startDate;
  final DateTime endDate;
  final double amount;
  final SubscriptionState status;
  final String? notes;
  final DateTime createdAt;

  /// Days from today to the end date, inclusive of today. Negative once it has lapsed.
  int daysLeftFrom(DateTime today) {
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final now = DateTime(today.year, today.month, today.day);
    return end.difference(now).inDays;
  }

  factory SubscriptionRecord.fromJson(Map<String, dynamic> row) {
    const src = 'subscriptions';
    return SubscriptionRecord(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      ownerUserId: reqString(row, src, 'owner_user_id'),
      startDate: reqDate(row, src, 'start_date'),
      endDate: reqDate(row, src, 'end_date'),
      amount: reqDouble(row, src, 'amount'),
      status: wireOrThrow(SubscriptionState.values, row['status'], src, 'status'),
      notes: optString(row, 'notes'),
      createdAt: reqTimestamp(row, src, 'created_at'),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECURITY CONSOLE
// ─────────────────────────────────────────────────────────────────────────────

/// public.security_alerts.severity. A `text` column with a four-value CHECK, not a Postgres
/// enum — so it is mirrored here the same way an enum would be, and an unrecognised value
/// throws rather than being drawn as "low".
enum AlertSeverity implements WireValue {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High'),
  critical('critical', 'Critical');

  const AlertSeverity(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  /// Sort weight — critical first. Alerts arrive newest-first from the server; this is what
  /// lets the console offer "worst first" without a second query.
  int get rank => switch (this) {
        AlertSeverity.critical => 3,
        AlertSeverity.high => 2,
        AlertSeverity.medium => 1,
        AlertSeverity.low => 0,
      };

  /// Whether an unacknowledged alert of this severity should interrupt someone.
  bool get isUrgent => this == AlertSeverity.high || this == AlertSeverity.critical;

  static AlertSeverity? tryParse(String? v) => wireOrNull(AlertSeverity.values, v);
}

/// One row of public.security_alerts — a pattern the audit trail detected, not a log line.
///
/// READ-ONLY BY POLICY. `security_alerts_select` admits the Super Admin (and an owner, for their
/// own hostel) and there is no insert, update or delete policy at all: an attacker able to edit
/// an alert could erase the evidence of their own session. The single permitted mutation is
/// acknowledgement, and that goes through public.ack_security_alert().
class SecurityAlert {
  const SecurityAlert({
    required this.id,
    required this.at,
    required this.severity,
    required this.kind,
    required this.summary,
    required this.details,
    this.hostelId,
    this.actorUserId,
    this.ip,
    this.acknowledgedAt,
    this.acknowledgedBy,
  });

  static const columns = 'id, at, severity, kind, summary, hostel_id, actor_user_id, ip, '
      'details, acknowledged_at, acknowledged_by';

  /// `bigint generated always as identity`. Passed back to ack_security_alert(p_alert_id).
  final int id;
  final DateTime at;
  final AlertSeverity severity;

  /// The detector's name for the pattern, e.g. 'failed_login_burst'. Free text from
  /// app.detect_suspicious_activity(); rendered humanised rather than matched on.
  final String kind;
  final String summary;
  final String? hostelId;
  final String? actorUserId;
  final String? ip;

  /// `jsonb not null default '{}'`. Whatever the detector recorded. Rendered as key/value
  /// lines, never interpreted — a new detector must not need a client release.
  final Map<String, dynamic> details;

  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;

  bool get isOpen => acknowledgedAt == null;

  factory SecurityAlert.fromJson(Map<String, dynamic> row) {
    const src = 'security_alerts';
    final raw = row['details'];
    return SecurityAlert(
      id: reqInt(row, src, 'id'),
      at: reqTimestamp(row, src, 'at'),
      severity: wireOrThrow(AlertSeverity.values, row['severity'], src, 'severity'),
      kind: reqString(row, src, 'kind'),
      summary: reqString(row, src, 'summary'),
      hostelId: optString(row, 'hostel_id'),
      actorUserId: optString(row, 'actor_user_id'),
      ip: optString(row, 'ip'),
      details: raw is Map<String, dynamic>
          ? raw
          : raw is Map
              ? raw.cast<String, dynamic>()
              : const <String, dynamic>{},
      acknowledgedAt: optTimestamp(row, src, 'acknowledged_at'),
      acknowledgedBy: optString(row, 'acknowledged_by'),
    );
  }

  SecurityAlert acknowledgedNow(String byUserId) => SecurityAlert(
        id: id,
        at: at,
        severity: severity,
        kind: kind,
        summary: summary,
        hostelId: hostelId,
        actorUserId: actorUserId,
        ip: ip,
        details: details,
        acknowledgedAt: DateTime.now().toUtc(),
        acknowledgedBy: byUserId,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ONBOARDING SERIES
// ─────────────────────────────────────────────────────────────────────────────

/// One month of public.rpc_sa_onboarding_series() — hostels that joined the platform.
class OnboardingPoint {
  const OnboardingPoint({required this.month, required this.hostels});

  /// 'YYYY-MM', straight from `to_char(m, 'YYYY-MM')`.
  final String month;
  final int hostels;

  factory OnboardingPoint.fromJson(Map<String, dynamic> row) {
    const src = 'rpc_sa_onboarding_series';
    return OnboardingPoint(
      month: reqString(row, src, 'month'),
      hostels: reqInt(row, src, 'hostels'),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE CREATE WIZARD'S PAYLOAD
// ─────────────────────────────────────────────────────────────────────────────

/// Which of the two things the wizard is doing (Hard rule §4.1).
enum OwnerMode {
  /// Mint a brand-new owner login. A temporary password comes back, once.
  create('new'),

  /// Add a second hostel and its own subscription under an owner account that already exists.
  /// No login is created, so there are no credentials to show and nothing to roll back.
  existing('existing');

  const OwnerMode(this.wire);
  final String wire;
}

/// Everything the four steps collect, in one immutable value.
///
/// SHAPED TO THE EDGE FUNCTION, NOT TO THE SCREENS. [toJson] produces exactly the nested body
/// `sa-create-owner/index.ts` parses — `owner.mode`, `hostel.bedsPerRoom`, `subscription.amount`
/// — so the field paths in a `fieldErrors` response map back onto these fields by name. The web
/// form and this one are then rejected by the same validator for the same reason, which is the
/// point of the function owning the rules.
///
/// The unused branch's fields are KEPT rather than cleared when the mode is switched, so an
/// admin who typed a name, flipped to "existing owner" to check something and flipped back does
/// not find the form wiped. The function reads only the branch `owner.mode` selects.
class CreateOwnerHostelDraft {
  const CreateOwnerHostelDraft({
    this.mode = OwnerMode.create,
    this.ownerName = '',
    this.ownerEmail = '',
    this.ownerPhone = '',
    this.ownerUserId,
    this.hostelName = '',
    this.floors = 1,
    this.rooms = 10,
    this.bedsPerRoom = 3,
    this.address = '',
    required this.startDate,
    required this.endDate,
    this.amount,
    this.notes = '',
  });

  /// The defaults the wizard opens on: today to a year from today, matching the web's
  /// `addYears(today, 1)`. Amount is deliberately null — a subscription price is a decision,
  /// and pre-filling one is how a wrong number gets accepted by reflex.
  factory CreateOwnerHostelDraft.initial(DateTime today) {
    final start = DateTime(today.year, today.month, today.day);
    return CreateOwnerHostelDraft(
      startDate: start,
      endDate: DateTime(start.year + 1, start.month, start.day),
    );
  }

  final OwnerMode mode;
  final String ownerName;
  final String ownerEmail;
  final String ownerPhone;
  final String? ownerUserId;

  final String hostelName;
  final int floors;
  final int rooms;
  final int bedsPerRoom;
  final String address;

  final DateTime startDate;
  final DateTime endDate;

  /// Null until the admin types one. Never defaulted — see [CreateOwnerHostelDraft.initial].
  final double? amount;
  final String notes;

  /// What scaffold_hostel() will actually create. Shown on the hostel step and again on review,
  /// because "12 rooms" and "36 beds" are different sizes of decision.
  int get totalBeds => rooms * bedsPerRoom;

  CreateOwnerHostelDraft copyWith({
    OwnerMode? mode,
    String? ownerName,
    String? ownerEmail,
    String? ownerPhone,
    String? ownerUserId,
    bool clearOwnerUserId = false,
    String? hostelName,
    int? floors,
    int? rooms,
    int? bedsPerRoom,
    String? address,
    DateTime? startDate,
    DateTime? endDate,
    double? amount,
    bool clearAmount = false,
    String? notes,
  }) {
    return CreateOwnerHostelDraft(
      mode: mode ?? this.mode,
      ownerName: ownerName ?? this.ownerName,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      ownerPhone: ownerPhone ?? this.ownerPhone,
      ownerUserId: clearOwnerUserId ? null : (ownerUserId ?? this.ownerUserId),
      hostelName: hostelName ?? this.hostelName,
      floors: floors ?? this.floors,
      rooms: rooms ?? this.rooms,
      bedsPerRoom: bedsPerRoom ?? this.bedsPerRoom,
      address: address ?? this.address,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      amount: clearAmount ? null : (amount ?? this.amount),
      notes: notes ?? this.notes,
    );
  }

  /// The exact body `sa-create-owner` parses. Dotted paths in its `fieldErrors` (`owner.email`,
  /// `hostel.rooms`, `subscription.endDate`) address these keys.
  Map<String, dynamic> toJson() => {
        'owner': {
          'mode': mode.wire,
          if (mode == OwnerMode.create) ...{
            'name': ownerName.trim(),
            'email': ownerEmail.trim(),
            'phone': ownerPhone.trim(),
          } else
            'ownerUserId': ownerUserId,
        },
        'hostel': {
          'name': hostelName.trim(),
          'floors': floors,
          'rooms': rooms,
          'bedsPerRoom': bedsPerRoom,
          'address': address.trim().isEmpty ? null : address.trim(),
        },
        'subscription': {
          'startDate': toDateWire(startDate),
          'endDate': toDateWire(endDate),
          'amount': amount,
          'notes': notes.trim().isEmpty ? null : notes.trim(),
        },
      };
}

/// The login that was minted, shown ONCE (Hard rule §4.9).
///
/// NEVER PERSISTED. The password exists in this object, on this screen, until the admin
/// dismisses the dialog — the function does not write it to any table, log or audit row, and
/// neither does this app. There is nowhere to look it up afterwards; the recovery path is to
/// issue a new one.
class IssuedCredentials {
  const IssuedCredentials({
    required this.name,
    required this.loginId,
    required this.password,
  });

  final String name;

  /// The owner's email address — `createStaffAccount` returns the email as the login id.
  final String loginId;
  final String password;

  factory IssuedCredentials.fromJson(Map<String, dynamic> row) {
    const src = 'sa-create-owner';
    return IssuedCredentials(
      name: reqString(row, src, 'name'),
      loginId: reqString(row, src, 'loginId'),
      password: reqString(row, src, 'password'),
    );
  }
}

/// What came back from a successful create.
///
/// [credentials] is null for the existing-owner branch, and that is the whole difference
/// between the two outcomes: one has a password to hand over, the other does not.
class CreatedHostel {
  const CreatedHostel({required this.hostelId, this.credentials});

  final String hostelId;
  final IssuedCredentials? credentials;

  bool get issuedLogin => credentials != null;

  factory CreatedHostel.fromJson(Map<String, dynamic> data) {
    const src = 'sa-create-owner';
    final creds = data['credentials'];
    return CreatedHostel(
      hostelId: reqString(data, src, 'hostelId'),
      credentials: creds is Map
          ? IssuedCredentials.fromJson(creds.cast<String, dynamic>())
          : null,
    );
  }
}
