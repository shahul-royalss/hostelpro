/// Super Admin round 3 (R7, docs/round3-api.md §8): self sign-ups with trials and demos,
/// deleted accounts, and the permanent delete. Refusals are [SignupFailure]s (verbatim).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/stay.dart' show dateWire;
import '../../../data/providers.dart' show supabaseClientProvider;
import '../../../data/repositories/signup_repository.dart' show SignupFailure;

String? _s(Map row, String k) {
  final v = row[k];
  return v is String && v.trim().isNotEmpty ? v : null;
}

DateTime? _d(Map row, String k) => DateTime.tryParse(_s(row, k) ?? '');

int? _i(Map row, String k) {
  final v = row[k];
  return v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
}

List<Map<String, dynamic>> _rows(Object? data) =>
    data is List ? [for (final r in data) if (r is Map<String, dynamic>) r] : const [];

/// `plan_status` values and their words.
const saPlanStatuses = <String, String>{
  'no_pg': 'No PG yet',
  'trial': 'Trial',
  'paid': 'Paid',
  'manual': 'Manual',
  'expired': 'Expired',
};

/// `p_demo_status` values (`none` = never booked).
const saDemoFilters = <String, String>{
  'none': 'No demo',
  'requested': 'Requested',
  'confirmed': 'Confirmed',
  'done': 'Done',
  'no_show': 'No show',
  'cancelled': 'Cancelled',
};

/// `kind` values of a deleted account.
const saDeletionKinds = <String, String>{
  'owner_deleted_staff': 'Removed by owner',
  'self_request': 'Asked to be deleted',
  'self_deleted': 'Deleted by themselves',
  'sa_deleted': 'Deleted by Super Admin',
  'deleted': 'Deactivated',
};

@immutable
class SaSignup {
  const SaSignup({
    required this.userId,
    required this.fullName,
    this.phone,
    this.email,
    this.signupSource,
    this.signedUpAt,
    this.hostelId,
    this.hostelName,
    this.hostelCity,
    this.trialStart,
    this.trialEnd,
    this.planStatus,
    this.planEnd,
    this.demoId,
    this.demoSlot,
    this.demoBedBand,
    this.demoStatus,
  });

  final String userId;
  final String fullName;
  final String? phone;
  final String? email;
  final String? signupSource;
  final DateTime? signedUpAt;
  final String? hostelId;
  final String? hostelName;
  final String? hostelCity;
  final DateTime? trialStart;
  final DateTime? trialEnd;
  final String? planStatus;
  final DateTime? planEnd;
  final String? demoId;
  final DateTime? demoSlot;
  final String? demoBedBand;
  final String? demoStatus;

  static SaSignup? tryParse(Map<String, dynamic> r) {
    final id = _s(r, 'user_id');
    if (id == null) return null;
    return SaSignup(
      userId: id,
      fullName: _s(r, 'full_name') ?? 'Owner',
      phone: _s(r, 'phone'),
      email: _s(r, 'email'),
      signupSource: _s(r, 'signup_source'),
      signedUpAt: _d(r, 'signed_up_at'),
      hostelId: _s(r, 'hostel_id'),
      hostelName: _s(r, 'hostel_name'),
      hostelCity: _s(r, 'hostel_city'),
      trialStart: _d(r, 'trial_start'),
      trialEnd: _d(r, 'trial_end'),
      planStatus: _s(r, 'plan_status'),
      planEnd: _d(r, 'plan_end'),
      demoId: _s(r, 'demo_id'),
      demoSlot: _d(r, 'demo_slot'),
      demoBedBand: _s(r, 'demo_bed_band'),
      demoStatus: _s(r, 'demo_status'),
    );
  }
}

@immutable
class SaDeletedAccount {
  const SaDeletedAccount({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.kind,
    this.role,
    this.hostelName,
    this.reason,
    this.byName,
    this.at,
    this.purgedAt,
    this.canPurge = false,
  });

  final String id;
  final String userId;
  final String fullName;
  final String kind;
  final String? role;
  final String? hostelName;
  final String? reason;
  final String? byName;
  final DateTime? at;
  final DateTime? purgedAt;
  final bool canPurge;

  static SaDeletedAccount? tryParse(Map<String, dynamic> r) {
    final id = _s(r, 'id');
    final user = _s(r, 'user_id');
    if (id == null || user == null) return null;
    return SaDeletedAccount(
      id: id,
      userId: user,
      fullName: _s(r, 'full_name') ?? 'Deleted user',
      kind: _s(r, 'kind') ?? 'deleted',
      role: _s(r, 'role'),
      hostelName: _s(r, 'hostel_name'),
      reason: _s(r, 'reason'),
      byName: _s(r, 'by_name'),
      at: _d(r, 'at'),
      purgedAt: _d(r, 'purged_at'),
      canPurge: r['can_purge'] == true,
    );
  }
}

/// One page and the server's total for the filter.
@immutable
class SaPage<T> {
  const SaPage(this.items, this.total);
  final List<T> items;
  final int total;
}

@immutable
class SaSignupQuery {
  const SaSignupQuery({this.from, this.to, this.planStatus, this.demoStatus, this.limit = 50});
  final DateTime? from;
  final DateTime? to;
  final String? planStatus;
  final String? demoStatus;
  final int limit;

  SaSignupQuery copyWith({
    DateTime? Function()? from,
    DateTime? Function()? to,
    String? Function()? planStatus,
    String? Function()? demoStatus,
    int? limit,
  }) =>
      SaSignupQuery(
        from: from == null ? this.from : from(),
        to: to == null ? this.to : to(),
        planStatus: planStatus == null ? this.planStatus : planStatus(),
        demoStatus: demoStatus == null ? this.demoStatus : demoStatus(),
        limit: limit ?? this.limit,
      );

  @override
  bool operator ==(Object other) =>
      other is SaSignupQuery &&
      other.from == from &&
      other.to == to &&
      other.planStatus == planStatus &&
      other.demoStatus == demoStatus &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(from, to, planStatus, demoStatus, limit);
}

@immutable
class SaDeletionQuery {
  const SaDeletionQuery({this.kind, this.from, this.to, this.limit = 50});
  final String? kind;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is SaDeletionQuery &&
      other.kind == kind &&
      other.from == from &&
      other.to == to &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(kind, from, to, limit);
}

abstract interface class SaRound3Api {
  Future<SaPage<SaSignup>> signups(SaSignupQuery q);
  Future<SaPage<SaDeletedAccount>> deletedAccounts(SaDeletionQuery q);
  Future<void> purgeAccount(String userId, {required String reason});
}

final class SaRound3Repository implements SaRound3Api {
  const SaRound3Repository(this.db);
  final SupabaseClient db;

  Future<Object?> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      return await db.rpc(fn, params: params).timeout(const Duration(seconds: 20));
    } catch (e, stack) {
      Error.throwWithStackTrace(SignupFailure.from(e), stack);
    }
  }

  static int _total(List<Map<String, dynamic>> rows) =>
      rows.isEmpty ? 0 : (_i(rows.first, 'total_count') ?? rows.length);

  @override
  Future<SaPage<SaSignup>> signups(SaSignupQuery q) async {
    final rows = _rows(await _rpc('sa_signups', {
      'p_from': q.from == null ? null : dateWire(q.from!),
      'p_to': q.to == null ? null : dateWire(q.to!),
      'p_plan_status': q.planStatus,
      'p_demo_status': q.demoStatus,
      'p_limit': q.limit,
      'p_offset': 0,
    }));
    return SaPage([for (final r in rows) ?SaSignup.tryParse(r)], _total(rows));
  }

  @override
  Future<SaPage<SaDeletedAccount>> deletedAccounts(SaDeletionQuery q) async {
    final rows = _rows(await _rpc('sa_deleted_accounts', {
      'p_kind': q.kind,
      'p_from': q.from == null ? null : dateWire(q.from!),
      'p_to': q.to == null ? null : dateWire(q.to!),
      'p_limit': q.limit,
      'p_offset': 0,
    }));
    return SaPage([for (final r in rows) ?SaDeletedAccount.tryParse(r)], _total(rows));
  }

  @override
  Future<void> purgeAccount(String userId, {required String reason}) async {
    await _rpc('sa_purge_account', {'p_user': userId, 'p_reason': reason.trim()});
  }
}

final saRound3ApiProvider =
    Provider<SaRound3Api>((ref) => SaRound3Repository(ref.watch(supabaseClientProvider)));

Duration? _noRetry(int _, Object _) => null;

final saSignupsProvider = FutureProvider.autoDispose.family<SaPage<SaSignup>, SaSignupQuery>(
  (ref, q) => ref.watch(saRound3ApiProvider).signups(q),
  retry: _noRetry,
);

final saDeletedAccountsProvider =
    FutureProvider.autoDispose.family<SaPage<SaDeletedAccount>, SaDeletionQuery>(
  (ref, q) => ref.watch(saRound3ApiProvider).deletedAccounts(q),
  retry: _noRetry,
);
