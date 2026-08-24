library;

/// Identity as the Flutter client understands it.
///
/// THE RULE THIS FILE EXISTS TO STATE. Nothing here is a security boundary. The role below is
/// used to decide which screens to *draw*; it never decides what data the user may *have*. That
/// is settled by Postgres row-level security on the server, evaluated against the JWT, and it
/// would still hold if this entire file were replaced with `role = owner`.
///
/// The web app learned this the hard way: two confirmed cross-tenant CRITICALs came from
/// trusting a value that looked authoritative on the client. The 63 RLS policies backing this
/// schema are the actual control, and they are attack-tested (see the repo's
/// scripts/_qa-rls-attack.mjs, 80 cases).

/// Mirrors `public.user_role` in Postgres exactly. Parsed from a string rather than an index,
/// because enum ordering is not a contract.
enum UserRole {
  superAdmin('super_admin', 'Super Admin'),
  owner('owner', 'Owner'),
  manager('manager', 'Manager'),
  warden('warden', 'Warden'),
  student('student', 'Student');

  const UserRole(this.wire, this.label);

  /// The exact string Postgres stores. Never send anything else.
  final String wire;
  final String label;

  static UserRole? tryParse(String? value) {
    if (value == null) return null;
    for (final r in UserRole.values) {
      if (r.wire == value) return r;
    }
    // An unrecognised role means the server knows about something this build does not.
    // Returning null routes to a "please update" state rather than guessing a permission set.
    return null;
  }
}

/// A signed-in user, as resolved from `public.users`.
///
/// Deliberately NOT read from the JWT's app_metadata: those claims lag until the token
/// refreshes, so a role change or a deactivation would not take effect for up to an hour. The
/// profile row is the source of truth, exactly as the web app does it.
class NivoraSession {
  const NivoraSession({
    required this.userId,
    required this.role,
    required this.fullName,
    required this.status,
    required this.mustChangePassword,
    this.hostelId,
    this.email,
    this.phone,
  });

  final String userId;
  final UserRole role;
  final String fullName;

  /// 'active' | 'inactive'. An inactive account is signed out on sight.
  final String status;

  /// Forces the change-password step before anything else is reachable.
  final bool mustChangePassword;

  /// The tenant this session is bound to. Null for a super admin, who is not inside a tenant.
  final String? hostelId;

  final String? email;
  final String? phone;

  bool get isActive => status == 'active';

  /// True when the account still owes an onboarding step, so routing must divert.
  bool get needsPasswordChange => mustChangePassword;

  static NivoraSession fromRow(Map<String, dynamic> row) {
    final role = UserRole.tryParse(row['role'] as String?);
    if (role == null) {
      throw StateError('Unknown role "${row['role']}" — this build cannot represent it.');
    }
    return NivoraSession(
      userId: row['id'] as String,
      role: role,
      fullName: (row['full_name'] as String?) ?? '',
      status: (row['status'] as String?) ?? 'inactive',
      mustChangePassword: (row['must_change_password'] as bool?) ?? false,
      hostelId: row['hostel_id'] as String?,
      email: row['email'] as String?,
      phone: row['phone'] as String?,
    );
  }
}
