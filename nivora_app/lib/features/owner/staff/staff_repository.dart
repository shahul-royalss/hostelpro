library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/models.dart';
import '../../../data/repositories/repository.dart';
import 'staff_models.dart';

/// The three staff writes, behind an interface.
///
/// The list is a plain read and a screen that reads is tested by overriding the provider that
/// holds the answer. These are not: one mints a credential that exists exactly once, and the
/// other two take somebody's access to a running PG away. Their interesting states (a validator
/// refusing three fields at once, §4.3 refusing a sixth warden, a deactivation that RLS silently
/// matched no rows for, an access change that would leave somebody with no PG at all) are the
/// states worth holding down in `flutter test`, and a test needs a stand-in for them. Same shape
/// and same reasoning as `SaPlatformWrites`.
abstract interface class OwnerStaffWrites {
  /// Creates the manager or warden login. supabase/functions/owner-create-staff.
  Future<StaffCreateOutcome> createStaff({
    required String hostelId,
    required StaffDraft draft,
  });

  /// Activates or deactivates one staff account, across EVERY PG they have access to.
  Future<void> setStaffStatus({
    required String userId,
    required StaffStatus status,
  });

  /// Replaces which of the owner's PGs one staff member may work in with exactly [hostelIds].
  /// public.owner_set_staff_hostels.
  Future<List<StaffHostelGrant>> setStaffHostels({
    required String userId,
    required List<String> hostelIds,
  });
}

/// Manager and warden accounts for one PG.
///
/// TABLES: public.users (the status write).
/// RPCs:   public.owner_hostel_staff, public.owner_set_staff_hostels.
/// EDGE:   owner-create-staff.
///
/// ── WHAT IS AND IS NOT A CONTROL IN THIS FILE ────────────────────────────────────────────
///
/// Nothing here authorises anything. The two RPCs are SECURITY DEFINER and check ownership
/// themselves, from `auth.uid()`: `owner_hostel_staff` refuses a PG the caller does not own,
/// and `owner_set_staff_hostels` refuses unless the caller owns EVERY PG named and the staff
/// member is their own. The status write is a plain update under `users_update` in
/// db/rls-policies.sql plus the `users_update_guard` trigger, evaluated against `auth.uid()`.
/// Every one of those would still hold if every filter below were deleted.
///
/// The create does not happen here at all. Minting a login needs `auth.admin.createUser`, which
/// needs the service-role key, which bypasses RLS for the entire project and therefore may
/// never be inside an APK. [createStaff] posts to an Edge Function that holds that key
/// server-side, re-reads the caller's role from `public.users`, re-checks
/// `hostels.owner_user_id`, and re-applies the writability gate RLS would have applied. The
/// phone asks; the server decides.
///
/// NO BROWSER, NO WEBVIEW, NO REDIRECT anywhere in this file. `functions.invoke` is an HTTPS
/// POST from the app to a Deno process on Supabase, signed with the current session's access
/// token.
final class OwnerStaffRepository extends Repository implements OwnerStaffWrites {
  const OwnerStaffRepository(super.db);

  /// Every manager and warden with ACCESS to one PG, active first and by name within that.
  /// public.owner_hostel_staff.
  ///
  /// ── WHY NOT `users` FILTERED BY `hostel_id` ANY MORE ──────────────────────────────────
  ///
  /// `users.hostel_id` is the ONE PG somebody is working in right now. A warden with access to
  /// two of the owner's PGs would appear under whichever they switched to last and vanish from
  /// the other, and a warden who is absent from a PG's list cannot be deactivated or given a
  /// task from it. The RPC lists everybody with access, active AND inactive (the inactive are
  /// who the owner reactivates from here), which is also the set the five-per-role limit
  /// counts. See [StaffMember] for the columns.
  ///
  /// THE ORDER IS SETTLED HERE, NOT ON THE SERVER. The function orders by role and then name;
  /// this screen has always led each post with the people running the PG today, so the
  /// active are moved ahead of the inactive and the server's name order is kept within each.
  /// `List.sort` is not stable, which is why this is two passes rather than a comparator.
  ///
  /// NOT PAGINATED. Five active of each role per PG, plus the handful who used to hold them.
  Future<List<StaffMember>> staff(String hostelId) => guard(() async {
        final data = await db.rpc('owner_hostel_staff', params: {'p_hostel_id': hostelId});
        final members =
            rpcRows(data, 'owner_hostel_staff').map(StaffMember.fromJson).toList(growable: false);
        return [
          ...members.where((m) => m.isActive),
          ...members.where((m) => !m.isActive),
        ];
      });

  /// Creates the manager or warden account. supabase/functions/owner-create-staff.
  ///
  /// RETURNS A REJECTION RATHER THAN THROWING ONE — see [StaffCreateOutcome].
  @override
  Future<StaffCreateOutcome> createStaff({
    required String hostelId,
    required StaffDraft draft,
  }) async {
    final FunctionResponse response;
    try {
      response = await db.functions.invoke(
        'owner-create-staff',
        body: draft.toJson(hostelId),
      );
    } on FunctionException catch (error, stack) {
      final rejection = staffRejectionFrom(error);
      if (rejection != null) return rejection;
      Error.throwWithStackTrace(staffFailureFrom(error), stack);
    } catch (error, stack) {
      Error.throwWithStackTrace(AppFailure.from(error), stack);
    }

    final envelope = response.data;
    if (envelope is! Map) {
      throw RowShapeError('owner-create-staff', '(body)', 'expected a JSON object envelope');
    }
    final data = envelope['data'];
    if (data is! Map) {
      throw RowShapeError(
        'owner-create-staff',
        'data',
        'the function answered without an account — check its logs',
      );
    }
    return StaffCreated(IssuedStaffCredentials.fromJson(data.cast<String, dynamic>()));
  }

  /// Deactivates or reactivates a staff account.
  ///
  /// ── A PLAIN UPDATE, AND WHY THAT IS ENOUGH HERE ────────────────────────────────────────
  ///
  /// The web app's `setAccountStatus()` uses the ADMIN client, because it does two things:
  /// flips `public.users.status`, and bans the auth user at GoTrue so an already-issued token
  /// cannot be reused. This app cannot do the second — banning is an `auth.admin` call and the
  /// service-role key is not in the APK — and there is no Edge Function for it, so this does
  /// the first only.
  ///
  /// That is not the security hole it looks like. `app.user_role()` and `app.user_hostel_id()`
  /// are both `select … where id = auth.uid() and status = 'active' and deleted_at is null`, so
  /// the moment this update commits, a deactivated warden's surviving token resolves to a null
  /// role: every RLS policy in db/rls-policies.sql fails closed for them, `users_select` stops
  /// returning even their own row, and this app signs them out on sight (see NivoraSession).
  /// What is left is that the token itself remains technically valid at GoTrue until it expires
  /// — a difference worth knowing about, and the reason the confirmation copy says "loses
  /// access" rather than "is signed out".
  ///
  /// ACCOUNT-WIDE, ON PURPOSE. Status lives on the account, not on an access row, so a warden
  /// with three PGs loses all three. Taking away ONE PG is [setStaffHostels]; the confirmation
  /// on the screen says which of the two the owner is about to do.
  ///
  /// NO `hostel_id` FILTER, AND THAT IS A FIX RATHER THAN A LOOSENING. It used to carry
  /// `.eq('hostel_id', <the PG on screen>)`. A warden with access to two PGs who is working in
  /// the other one right now has `users.hostel_id` set to THAT one, so the filter matched no
  /// row and the owner was told the account was not theirs. What decides is unchanged:
  /// `users_update` admits `role in ('manager','warden') and app.owns_hostel(hostel_id)` (the
  /// active PG is always one of the owner's, because access is only ever granted within one
  /// owner's PGs), its WITH CHECK adds `app.hostel_writable(hostel_id)` so a lapsed
  /// subscription refuses, and `app.users_update_guard` independently confirms that whoever is
  /// changing a status actually administers that account. The id and role filters only pick
  /// the row.
  ///
  /// AN EMPTY RESULT IS A REFUSAL, NOT A SUCCESS. When the USING clause does not admit the row,
  /// Postgres updates nothing and PostgREST reports no error at all — so without the `.select()`
  /// and the check beneath it, "you may not do that" and "done" would look identical.
  ///
  /// REACTIVATION CAN FAIL, ON PURPOSE. The per-PG staff limit fires on `update of status`
  /// too, so reactivating a warden into a PG that already has five raises P0001 with its own
  /// sentence, which [AppFailure] passes through verbatim as an [InvalidInputFailure].
  @override
  Future<void> setStaffStatus({
    required String userId,
    required StaffStatus status,
  }) =>
      guard(() async {
        final rows = await db
            .from('users')
            .update({'status': status.wire})
            .eq('id', userId)
            .inFilter('role', const ['manager', 'warden'])
            .isFilter('deleted_at', null)
            .select('id');

        if (rows.isEmpty) {
          throw const AccessDeniedFailure(
            'That account is no longer one of your staff, or it is not yours to change. '
            'Pull down to refresh the list.',
          );
        }
      });

  /// Gives one staff member access to exactly [hostelIds], no more and no fewer.
  /// public.owner_set_staff_hostels.
  ///
  /// A REPLACEMENT, NOT A DIFF, which is what makes it safe under [guard]: sending the same
  /// list twice leaves the same rows, so a timed-out save may simply be saved again.
  ///
  /// THE SERVER DECIDES EVERYTHING THAT MATTERS, from `auth.uid()`:
  ///   · the caller must own EVERY PG in the list ('You can only give access to your own PGs.');
  ///   · the person must be the caller's own warden or manager ('That staff member is not
  ///     yours.');
  ///   · the list must not be empty ('Choose at least one PG.'). The sheet refuses that first,
  ///     but only so the owner is not sent on a round trip to hear it;
  ///   · each newly granted PG must have room under the five-per-role limit ('This PG already
  ///     has 5 active wardens. Remove one from it first.').
  /// All four are P0001 with sentences written for the owner, passed through verbatim.
  ///
  /// When the PG they are working in is taken away, the RPC moves them to the first remaining
  /// PG by name, and the row with `is_active` set says where they landed.
  @override
  Future<List<StaffHostelGrant>> setStaffHostels({
    required String userId,
    required List<String> hostelIds,
  }) =>
      guard(() async {
        final data = await db.rpc('owner_set_staff_hostels', params: {
          'p_user_id': userId,
          'p_hostel_ids': hostelIds,
        });
        return rpcRows(data, 'owner_set_staff_hostels')
            .map(StaffHostelGrant.fromJson)
            .toList(growable: false);
      });
}

// ─────────────────────────────────────────────────────────────────────────────
// TRANSLATING THE FUNCTION'S FAILURES
//
// Top-level and pure, so the branch that matters most can be tested without a network, a
// Supabase client or a widget. The interesting one is §4.3: the rule is refused in three
// different places, and they do not agree on a status code (see [_roleTaken]). Getting that
// wrong turns "you already have a warden" into "Something went wrong. Please try again."
// ─────────────────────────────────────────────────────────────────────────────

/// §4.3, in whichever of its three wordings arrived.
///
/// The rule is refused in three places and they do not share a status code, which is why this
/// matches on the message rather than on the number:
///
///   • the function's friendly pre-count           → 409 "This PG already has 5 active
///                                                    managers. Remove one from it first."
///                                                    (the PG's name in place of "This PG"
///                                                    when several were asked for)
///   • `app.enforce_role_limits` winning the race  → P0001, mapped by dbError to a 400, then
///                                                    re-wrapped by rollbackAwareError, which
///                                                    hard-codes 400 once the auth user has
///                                                    been rolled back
///   • dbError's 23505 wording                     → "…already has an active manager or warden
///                                                    in that role", now unreachable: the
///                                                    unique index it names was dropped when
///                                                    the limit became five, and the advisory
///                                                    lock in the trigger settles the race
///                                                    instead. Still matched, because a
///                                                    database that still had the index would
///                                                    otherwise produce an unrecognised error.
///
/// All of them mean exactly one thing to the owner, so this matches the SHAPE of the sentence
/// rather than a count that changed once and can change again.
final RegExp _roleTaken =
    RegExp(r'already has (an active|\d+ active)', caseSensitive: false);

/// A rejection the form can act on, or null when this was not about the input at all.
StaffRejected? staffRejectionFrom(FunctionException error) {
  final details = error.details;
  if (details is! Map) return null;
  final message = _messageFrom(details);

  // The validator's own output: every field that failed, in one pass.
  final raw = details['fieldErrors'];
  final fields = <String, String>{};
  if (raw is Map) {
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String) continue;
      if (value is List && value.isNotEmpty && value.first is String) {
        fields[key] = value.first as String;
      } else if (value is String) {
        fields[key] = value;
      }
    }
  }
  if (fields.isNotEmpty) {
    return StaffRejected(
      message ?? 'Please check the highlighted fields.',
      fieldErrors: fields,
    );
  }

  if (message == null) return null;

  // Hard rule §4.3. Not a field error: no amount of retyping fixes it, and the next step is a
  // button ("Deactivate the current one") rather than an edit.
  if (_roleTaken.hasMatch(message)) {
    return StaffRejected(message, roleLimitReached: true);
  }

  if (error.status == 409 || error.status == 400) {
    // "An account with this email already exists." — one field, one fix, and putting it under
    // the email box saves the owner reading the whole form looking for what to change.
    if (message.toLowerCase().contains('email')) {
      return StaffRejected(message, fieldErrors: {'email': message});
    }
    return StaffRejected(message);
  }
  return null;
}

/// Everything that is not about the input, in the same sealed type the rest of the data layer
/// throws — so the screen's existing error handling covers it without a special case.
AppFailure staffFailureFrom(FunctionException error) {
  final message = _messageFrom(error.details);

  // No response at all. Nothing was created, so this is safe to retry.
  if (error is FunctionsFetchException || error.status == 0) {
    return OfflineFailure(
      'Cannot reach Nivora. Check your connection and try again.',
      technical: error.toString(),
    );
  }

  return switch (error.status) {
    401 => SignedOutFailure(
        message ?? 'Your session has ended. Sign in again to continue.',
        technical: error.toString(),
      ),
    403 => _forbidden(message, error),
    // A BODYLESS 404 IS THE ENDPOINT, NOT THE PG. When the function ran and decided the hostel
    // is gone it says so in its `{ ok: false, error }` envelope, which is [message]. When the
    // function is not deployed on this project the gateway answers 404 with nothing in it, and
    // "that PG could not be found" sends an owner looking for a PG that is sitting right there
    // on the previous screen. Same precedent as the 404 branch in
    // features/auth/email_verification_service.dart, which was added after this exact confusion
    // cost a live debugging session.
    404 when message == null => NotFoundFailure(
        'Staff accounts cannot be managed on this server yet. Nothing was changed. Ask Nivora '
            'to enable it.',
        technical: 'the staff Edge Function answered 404 with no body — it is not deployed on '
            'this project, so nothing decided that a PG was missing. $error',
      ),
    404 => NotFoundFailure(
        message ?? 'That PG could not be found.',
        technical: error.toString(),
      ),
    // The limiter on this endpoint is fail-closed on purpose — it mints a credential, so a
    // limiter it cannot consult refuses (503) rather than waving through. Both mean "wait".
    429 || 503 => ServerFailure(
        message ?? 'Too many account operations just now. Wait a minute and try again.',
        technical: error.toString(),
      ),
    // Includes the rollback report, whose message names the orphaned auth user id and says what
    // to do about it. That is more useful than anything this file could invent, so it is passed
    // through verbatim.
    _ => ServerFailure(
        message ?? 'Nivora could not finish creating that account. Refresh the staff list '
            'before trying again.',
        technical: error.toString(),
      ),
  };
}

/// A 403 is two completely different conversations, and the function says which in words.
///
/// `assertWritable()` throws "This hostel is suspended. Contact NIVORA support." or
/// "Subscription expired — the hostel is read-only until it is renewed."; every other 403 means
/// "not you". The first is a billing problem with a renewal at the end of it, the second is a
/// permissions problem with nothing the owner can do. Collapsing them into one message sends
/// the wrong person to support.
AppFailure _forbidden(String? message, FunctionException error) {
  final text = (message ?? '').toLowerCase();
  if (text.contains('read-only') ||
      text.contains('read only') ||
      text.contains('suspended') ||
      text.contains('expired')) {
    return ReadOnlyFailure(message!, technical: error.toString());
  }
  return AccessDeniedFailure(
    message ?? 'Only the owner of this PG can create staff accounts.',
    technical: error.toString(),
  );
}

/// The function's own `{ ok: false, error: "..." }` body, when there is one.
String? _messageFrom(Object? details) {
  if (details is Map) {
    final error = details['error'];
    if (error is String && error.trim().isNotEmpty) return error.trim();
  }
  return null;
}
