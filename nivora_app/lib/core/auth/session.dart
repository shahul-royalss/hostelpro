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

/// The domain student logins are mapped onto. Must match the web app's STUDENT_LOGIN_DOMAIN,
/// `STUDENT_LOGIN_DOMAIN` in supabase/functions/_shared/validate.ts, and the literal inside
/// `app.email_is_reachable()` in Postgres.
///
/// It is not a real mail domain and no address in it is ever accepted as a resident's own
/// email — see the `isStudentLoginEmail` guard in the Edge Function. Only the phone mapping in
/// [resolveLoginEmail] writes here.
///
/// It lives in this file rather than beside [resolveLoginEmail] because [NivoraSession] is what
/// has to answer "does this account have an address worth verifying", and core/auth/session
/// must not import the controller that imports it. auth_controller.dart re-exports the name, so
/// every existing `import auth_controller.dart show studentLoginDomain` still resolves.
const studentLoginDomain = 'student.hostelpro.local';

/// Can mail actually be delivered to this address?
///
/// Mirrors `app.email_is_reachable()` in db/schema.sql and `isReachableAddress()` in
/// supabase/functions/_shared/verification.ts. False for the synthetic phone-mapping namespace,
/// which exists precisely because that resident gave no address at all: asking them to prove it
/// would be asking for something that cannot be produced.
bool isReachableLoginAddress(String? email) {
  final e = (email ?? '').trim().toLowerCase();
  return e.isNotEmpty && !e.endsWith('@$studentLoginDomain');
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
    this.emailVerifiedAt,
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

  /// `users.email_verified_at` — when the holder opened a confirmation link sent to [email], or
  /// null.
  ///
  /// NOT `auth.users.email_confirmed_at`. That one is stamped by every account-creation path so
  /// the temporary password works at all (the project has "Confirm email" ON, and GoTrue
  /// refuses a password grant to an unconfirmed user), which means it records that somebody
  /// TYPED an address and never that its owner answered. This column is the proof, it starts
  /// null for every account that has ever existed, and only the email-verification Edge
  /// Function can write it.
  final DateTime? emailVerifiedAt;

  bool get isActive => status == 'active';

  /// True when the account still owes an onboarding step, so routing must divert.
  bool get needsPasswordChange => mustChangePassword;

  /// Does this account have an address that can receive mail at all?
  bool get emailIsReachable => isReachableLoginAddress(email);

  /// The account owes a proof AND can produce one.
  ///
  /// A resident who signs in with a phone number is not held to this, and the exemption is
  /// carved by ADDRESS rather than by role: a student whose warden collected a real email is
  /// asked exactly like an owner is. Deliberately NOT a routing gate — see
  /// [resolveRedirect] in core/router/router.dart for why this shows a banner instead of
  /// trapping the user on a screen.
  bool get needsEmailVerification => emailIsReachable && emailVerifiedAt == null;

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
      // PostgREST sends timestamptz as an ISO-8601 string. Parsed leniently on purpose: a value
      // this build cannot read must not throw here, because [fromRow] failing signs the user
      // out. An unparseable stamp degrades to "not verified yet", which asks for a code the
      // person can actually supply, rather than to a locked account.
      emailVerifiedAt: DateTime.tryParse((row['email_verified_at'] as String?) ?? ''),
    );
  }
}
