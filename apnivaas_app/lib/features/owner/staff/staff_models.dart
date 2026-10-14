library;

import '../../../data/models/models.dart';
import '../../../data/models/parse.dart';

/// The manager and warden accounts an owner runs a PG with, and the payload that creates one.
///
/// WHY THESE LIVE HERE. `public.users` is read by three features already, but never as *staff*:
/// the manager's directory wants contacts, the session wants an identity, and neither cares
/// about the rule that shapes this screen — Hard rule §4.3, at most [maxStaffPerRole] active
/// managers and [maxStaffPerRole] active wardens per hostel. Everything below is modelled
/// around that rule. Promote it into lib/data the moment a second role needs it.
///
/// Coerced through parse.dart like the rest of the data layer, so a renamed column names itself
/// instead of turning into a blank field.

// ─────────────────────────────────────────────────────────────────────────────
// ROLES
// ─────────────────────────────────────────────────────────────────────────────

/// The two roles `owner-create-staff` will accept. NOT `UserRole`.
///
/// `UserRole` in core/auth/session.dart covers all five roles the database knows. This covers
/// the two an owner is allowed to mint, which is a different set for a reason: the Edge
/// Function's `v.oneOf("role", ["manager", "warden"])` rejects anything else, and modelling the
/// form's choices as the full five-value enum would let a screen offer "Super Admin" in a
/// dropdown and only find out on the round trip.
///
/// The blurbs are the web app's, verbatim from components/owner/staff-card.tsx, so the same
/// person is described the same way whichever client the owner happens to be holding.
enum StaffRole implements WireValue {
  manager(
    'manager',
    'Manager',
    'Runs finance and operations — daily expenses, revenue, mess menu, and your tasks.',
  ),
  warden(
    'warden',
    'Warden',
    'Runs students and rooms — registrations, beds, fees, leaves, visitors, complaints.',
  );

  const StaffRole(this.wire, this.label, this.blurb);

  /// The literal `public.user_role` label. The only string that may go over the wire.
  @override
  final String wire;

  @override
  final String label;

  /// What this person actually does, for the empty state and the add form.
  final String blurb;
}

/// HOW MANY ACTIVE MANAGERS, AND HOW MANY ACTIVE WARDENS, ONE PG MAY HAVE.
///
/// FIVE SINCE 2026-09-12; it was one of each. The product owner: "owner can create upto 5
/// warden & 5 manager accounts." A second PG needs its own pair, and one building with two
/// shifts needs two wardens who are both real accounts rather than one login handed around.
///
/// THE DATABASE IS THE RULE, NOT THIS. `app.enforce_role_limits` refuses the sixth, taking an
/// advisory lock on (hostel, role) before it counts so two simultaneous creates cannot both
/// pass at four — that lock replaced the `users_one_active_staff_per_hostel` unique index,
/// which could only ever express "at most one". This constant exists so the screen can draw
/// the limit and disable Add before the round trip; if the two disagree, this one is the bug.
///
/// COUNTED BY ACCESS, NOT BY WHERE PEOPLE ARE WORKING. Since `public.staff_hostel_access` a
/// warden may hold several PGs and work in one at a time. The limit counts every active warden
/// with ACCESS to a PG, wherever they are working right now, so switching cannot be used to
/// squeeze a sixth into a PG and taking one PG away from somebody frees a place in it. The
/// list this screen draws comes from the same set (`owner_hostel_staff`), so the count on the
/// card is the count the database applies.
const maxStaffPerRole = 5;

/// Mirrors `public.user_status`.
///
/// Two values, and the difference between them is not cosmetic: `app.user_role()` and
/// `app.user_hostel_id()` both resolve only for `status = 'active'`, so an inactive account
/// fails every RLS policy in the schema rather than merely being hidden from a list.
enum StaffStatus implements WireValue {
  active('active', 'Active'),
  inactive('inactive', 'Inactive');

  const StaffStatus(this.wire, this.label);

  @override
  final String wire;

  @override
  final String label;
}

// ─────────────────────────────────────────────────────────────────────────────
// THE ROW
// ─────────────────────────────────────────────────────────────────────────────

/// One manager or warden with access to one PG, as `public.owner_hostel_staff()` returns them.
///
/// ── WHY AN RPC AND NOT `users` FILTERED BY `hostel_id` ───────────────────────────────────
///
/// A warden or manager can now be given access to several of an owner's PGs
/// (`public.staff_hostel_access`), and `users.hostel_id` only says which ONE they are working
/// in right now. Filtering on it would show a two-PG warden under whichever PG they happened to
/// switch to last, and hide them from the other. The RPC lists everybody with ACCESS to the PG,
/// which is also what the five-per-role limit now counts, so the "2 of 5" on the card and the
/// database's refusal count the same people.
///
/// [hostelIds] is restricted by the server to the CALLER's own PGs, so a person who also works
/// for somebody else never shows that other owner's buildings here.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.role,
    required this.fullName,
    required this.status,
    required this.createdAt,
    this.email,
    this.phone,
    this.mustChangePassword = false,
    this.activeHostelId,
    this.activeHostelName,
    this.hostelIds = const <String>[],
  });

  final String id;
  final StaffRole role;
  final String fullName;
  final StaffStatus status;
  final DateTime createdAt;

  /// The login id. Nullable in the schema, so a row written before staff logins existed does
  /// not crash a screen — but every account this feature creates has one.
  final String? email;
  final String? phone;

  /// True until they have signed in once and replaced the temporary password.
  final bool mustChangePassword;

  /// The PG they are working in NOW: `users.hostel_id`. May be another of the owner's PGs than
  /// the one on screen, because the person switched to it.
  final String? activeHostelId;
  final String? activeHostelName;

  /// Every one of the owner's PGs this person may work in, the one on screen included.
  final List<String> hostelIds;

  bool get isActive => status == StaffStatus.active;

  /// More than one PG, so deactivating them takes away more than the one on screen.
  bool get hasSeveralPgs => hostelIds.length > 1;

  factory StaffMember.fromJson(Map<String, dynamic> row) {
    const src = 'owner_hostel_staff';
    return StaffMember(
      id: reqString(row, src, 'user_id'),
      role: wireOrThrow(StaffRole.values, row['role'], src, 'role'),
      fullName: reqString(row, src, 'full_name'),
      status: wireOrThrow(StaffStatus.values, row['status'], src, 'status'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      email: optString(row, 'email'),
      phone: optString(row, 'phone'),
      mustChangePassword: reqBool(row, src, 'must_change_password'),
      activeHostelId: optString(row, 'active_hostel_id'),
      activeHostelName: optString(row, 'active_hostel_name'),
      hostelIds: stringList(row, src, 'hostel_ids'),
    );
  }

  StaffMember copyWith({StaffStatus? status}) => StaffMember(
        id: id,
        role: role,
        fullName: fullName,
        status: status ?? this.status,
        createdAt: createdAt,
        email: email,
        phone: phone,
        mustChangePassword: mustChangePassword,
        activeHostelId: activeHostelId,
        activeHostelName: activeHostelName,
        hostelIds: hostelIds,
      );
}

/// Who holds a post right now, and who used to.
extension StaffRoster on List<StaffMember> {
  /// Everyone who has ever held this post, active first and by name within that: the order
  /// `OwnerStaffRepository.staff()` puts the server's rows in.
  List<StaffMember> inRole(StaffRole role) =>
      where((s) => s.role == role).toList(growable: false);

  /// The people who hold it TODAY. Up to [maxStaffPerRole] of them.
  List<StaffMember> activeInRole(StaffRole role) =>
      where((s) => s.role == role && s.isActive).toList(growable: false);

  /// Whether this PG can take another. Asked before the sheet opens rather than after the
  /// server refuses, which is the whole reason the count is on the screen.
  bool isFull(StaffRole role) => activeInRole(role).length >= maxStaffPerRole;
}

// ─────────────────────────────────────────────────────────────────────────────
// THE CREDENTIAL — returned once, never stored
// ─────────────────────────────────────────────────────────────────────────────

/// The one-time login handed back by `owner-create-staff`.
///
/// This object is the ONLY copy of that password anywhere. The function generates it, returns
/// it in a single `Cache-Control: no-store` response, and writes it to no table, no log and no
/// audit row. Nothing in this app persists it either. It lives in a widget's state until the
/// dialog is dismissed and is then gone for good — see StaffCredentialsDialog for why that
/// dialog is deliberately awkward to close.
class IssuedStaffCredentials {
  const IssuedStaffCredentials({
    required this.userId,
    required this.name,
    required this.roleLabel,
    required this.loginId,
    required this.password,
    this.hostelIds,
  });

  final String userId;
  final String name;

  /// "Manager" / "Warden" — the function sends `ROLE_LABEL[role]`, not the wire value, so this
  /// is display text and must not be parsed back into a [StaffRole].
  final String roleLabel;

  /// The email address. `createStaffAccount` returns the email as the login id for staff.
  final String loginId;
  final String password;

  /// Every PG the new account may work in, the first being where it starts. Null when the
  /// function that answered predates staff_hostel_access and does not send the field, which is
  /// how the sheet knows it cannot claim more than the one PG it is sure about.
  final List<String>? hostelIds;

  factory IssuedStaffCredentials.fromJson(Map<String, dynamic> data) {
    const src = 'owner-create-staff';
    return IssuedStaffCredentials(
      userId: reqString(data, src, 'userId'),
      name: reqString(data, src, 'name'),
      roleLabel: reqString(data, src, 'role'),
      loginId: reqString(data, src, 'loginId'),
      password: reqString(data, src, 'password'),
      hostelIds: _lenientIds(data['hostelIds']),
    );
  }

  /// READ LENIENTLY ON PURPOSE. This response is the only place the one-time password ever
  /// appears, and the account already exists by the time it arrives. A strict parse would throw
  /// on an unexpected shape of this informational field and the owner would never see the
  /// password. The credential outranks a shape check: anything but a list of strings is null,
  /// which the sheet already treats as "only sure about the one PG".
  static List<String>? _lenientIds(Object? raw) {
    if (raw is! List || raw.any((e) => e is! String)) return null;
    return List<String>.unmodifiable(raw.cast<String>());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE FORM
// ─────────────────────────────────────────────────────────────────────────────

/// What the owner has typed so far.
class StaffDraft {
  const StaffDraft({
    this.role = StaffRole.manager,
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.hostelIds = const <String>[],
  });

  final StaffRole role;
  final String fullName;
  final String email;

  /// Optional in `createStaffSchema` and in the function's `v.optionalPhone("phone")`.
  final String phone;

  /// The PGs the owner ticked, the one the account starts in FIRST. Empty when the owner has a
  /// single PG and was never asked, which sends the old single-PG body unchanged.
  final List<String> hostelIds;

  StaffDraft copyWith({
    StaffRole? role,
    String? fullName,
    String? email,
    String? phone,
    List<String>? hostelIds,
  }) {
    return StaffDraft(
      role: role ?? this.role,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      hostelIds: hostelIds ?? this.hostelIds,
    );
  }

  /// The exact body `supabase/functions/owner-create-staff/index.ts` parses.
  ///
  /// Verified field for field against its `parseBody()`:
  ///   role      v.oneOf("role", ["manager","warden"])            → StaffRole.wire
  ///   fullName  v.string("fullName", {min:2, max:80})            → trimmed
  ///   email     v.email("email")                                 → trimmed, lowercased
  ///   phone     v.optionalPhone("phone")                         → omitted when blank
  ///   hostelId  v.optionalUuid("hostelId")                       → always sent, see below
  ///   hostelIds v.optionalUuidList("hostelIds", {max: 20})       → only for two or more PGs
  ///
  /// [hostelId] IS ALWAYS SENT even though the function will fall back to `caller.hostelId`.
  /// An owner may hold several PGs and the switcher decides which one is on screen; letting the
  /// server guess would create the account against `users.hostel_id`, which for a multi-PG owner
  /// is whichever hostel they were first attached to and not the one they are looking at.
  ///
  /// Sending it is safe because it is not trusted: `requireOwnedHostel()` re-reads
  /// `hostels.owner_user_id` with the service role and answers "Hostel not found." for a hostel
  /// that is not this caller's — the same message it gives for one that does not exist, so the
  /// endpoint cannot be used to probe which ids are real.
  ///
  /// ── [hostelIds], AND WHY `hostelId` STILL TRAVELS WITH IT ─────────────────────────────
  ///
  /// With ONE PG chosen the body is exactly what it was before PG access existed: `hostelId`
  /// names it and `hostelIds` is absent. That is the shape the live Android build sends, and
  /// the shape the function treats as "exactly as today".
  ///
  /// With TWO OR MORE, `hostelIds` carries them all, the starting PG first, and the function
  /// lets it decide. `hostelId` is sent as well, set to that same first PG, for one reason: a
  /// function deployed before `hostelIds` existed ignores keys it does not know, and without
  /// `hostelId` it would fall back to the owner's own `users.hostel_id` and create the account
  /// in a PG the owner never picked. With it, the worst an old function can do is create the
  /// account in the right PG only, which the sheet then says (see
  /// [IssuedStaffCredentials.hostelIds]).
  ///
  /// Duplicates are dropped here, keeping the first; the function deduplicates too, and each
  /// of the ids is checked against `hostels.owner_user_id` there, never trusted from here.
  Map<String, dynamic> toJson(String hostelId) {
    final trimmedPhone = phone.trim();
    final chosen = <String>[];
    for (final id in hostelIds) {
      if (!chosen.contains(id)) chosen.add(id);
    }
    return {
      'role': role.wire,
      'fullName': fullName.trim(),
      'email': email.trim().toLowerCase(),
      if (trimmedPhone.isNotEmpty) 'phone': trimmedPhone,
      'hostelId': chosen.isEmpty ? hostelId : chosen.first,
      if (chosen.length > 1) 'hostelIds': chosen,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VALIDATION
//
// Top-level and pure, so it is testable without a widget, a container or a network.
//
// ── WHY THIS IS DUPLICATED, AND WHY THAT IS NOT DUPLICATION ─────────────────────────────
//
// supabase/functions/owner-create-staff owns these rules and is the only place that can: this
// app ships as an APK, and an APK is a zip file anyone can edit. The copy below does a
// different job — telling somebody their email is malformed without a round trip that would
// otherwise burn one of the rate limiter's account-creation attempts.
//
// So the messages are matched WORD FOR WORD to what the server would have said, taken from
// _shared/validate.ts (which is itself a port of createStaffSchema in lib/validators/owner.ts).
// When the server rejects something this misses, its `fieldErrors` land in the same map under
// the same flat keys — 'role', 'fullName', 'email', 'phone' — and the form cannot tell the two
// apart. Which is correct: to the owner filling it in they are the same event.
//
// One knowing divergence from the browser: zod's `createStaffSchema` writes "Enter a valid
// email address." with a full stop and the Edge Function's `v.email()` writes it without one.
// The function's wording wins here, because that is the string that will arrive over the wire
// and sit next to this one in the same map.
// ─────────────────────────────────────────────────────────────────────────────

/// `EMAIL_RE` from supabase/functions/_shared/validate.ts.
final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// `PHONE_LOOSE_RE` — digits, spaces and the separators people actually type, 8 to 16 of them.
/// Deliberately loose: this number is a contact detail, not a login id, so "+91 98765 43210"
/// and "9876543210" are both fine.
final RegExp _phoneLoose = RegExp(r'^[\d\s+\-()]{8,16}$');

/// Everything wrong with [draft], keyed by the field name the function uses.
///
/// An empty map means the server's validator would also have accepted it — not that the create
/// will succeed. Whether this hostel already has an active manager, whether the email is taken,
/// and whether the subscription still permits writes are all decided server-side.
Map<String, String> validateStaffDraft(StaffDraft draft) {
  final errors = <String, String>{};

  final name = draft.fullName.trim();
  if (name.length < 2) {
    errors['fullName'] = 'Enter the full name.';
  } else if (name.length > 80) {
    errors['fullName'] = 'Keep this under 80 characters.';
  }

  final email = draft.email.trim();
  if (email.length < 3 || !_email.hasMatch(email)) {
    errors['email'] = 'Enter a valid email address';
  } else if (email.length > 200) {
    errors['email'] = 'Keep this under 200 characters.';
  }

  // Blank is a legal value — the column is nullable and the schema marks it optional.
  final phone = draft.phone.trim();
  if (phone.isNotEmpty && !_phoneLoose.hasMatch(phone)) {
    errors['phone'] = 'Enter a valid phone number.';
  }

  return errors;
}

// ─────────────────────────────────────────────────────────────────────────────
// WHAT PRESSING "CREATE" PRODUCED
// ─────────────────────────────────────────────────────────────────────────────

/// Two outcomes, not a throw and a return.
///
/// A form whose fields the server refused is an ordinary result of pressing Create, not an
/// exception: the sheet needs the per-field messages to put back onto the fields that own them,
/// and a catch block has already lost which field they belonged to. Everything that is NOT
/// about the input — no signal, session expired, not the owner of this PG, the subscription
/// lapsed, the server fell over mid-rollback — still throws [AppFailure], because none of it is
/// something the owner can fix by editing a text field.
sealed class StaffCreateOutcome {
  const StaffCreateOutcome();
}

final class StaffCreated extends StaffCreateOutcome {
  const StaffCreated(this.credentials);

  /// Show once. See [IssuedStaffCredentials].
  final IssuedStaffCredentials credentials;
}

final class StaffRejected extends StaffCreateOutcome {
  const StaffRejected(
    this.message, {
    this.fieldErrors = const {},
    this.roleLimitReached = false,
  });

  /// Safe to show as a banner — it came from the function's own `{ ok: false, error }`.
  final String message;

  /// Keyed by the flat field names the function accumulates: 'role', 'fullName', 'email',
  /// 'phone', 'hostelId', 'hostelIds'. One message per field; the first is the one that explains
  /// the others.
  final Map<String, String> fieldErrors;

  /// True when §4.3 was what refused: this hostel already has an active holder of that role.
  ///
  /// Worth its own flag rather than a string match at every call site. It is not a field error
  /// — nothing the owner can retype fixes it — and the only useful next step is "deactivate the
  /// current one first", which the screen can offer as a button instead of as a sentence.
  final bool roleLimitReached;
}
