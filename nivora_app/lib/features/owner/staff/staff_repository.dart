library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/models.dart';
import '../../../data/repositories/repository.dart';
import 'staff_models.dart';

/// The two staff writes, behind an interface.
///
/// The list is a plain read and a screen that reads is tested by overriding the provider that
/// holds the answer. These two are not: one mints a credential that exists exactly once, and
/// the other takes somebody's access to a running PG away. Their interesting states — a
/// validator refusing three fields at once, §4.3 refusing a second warden, a deactivation that
/// RLS silently matched no rows for — are the states worth holding down in `flutter test`, and
/// a test needs a stand-in for them. Same shape and same reasoning as `SaPlatformWrites`.
abstract interface class OwnerStaffWrites {
  /// Creates the manager or warden login. supabase/functions/owner-create-staff.
  Future<StaffCreateOutcome> createStaff({
    required String hostelId,
    required StaffDraft draft,
  });

  /// Activates or deactivates one staff account, returning the row as it now stands.
  Future<StaffMember> setStaffStatus({
    required String hostelId,
    required String userId,
    required StaffStatus status,
  });
}

/// Manager and warden accounts for one PG.
///
/// TABLES: public.users.
/// EDGE:   owner-create-staff.
///
/// ── WHAT IS AND IS NOT A CONTROL IN THIS FILE ────────────────────────────────────────────
///
/// Nothing here authorises anything. `.eq('hostel_id', …)` narrows a query so the server does
/// less work and the screen gets the rows it asked for; what actually stops one owner reading
/// or editing another's staff is `users_select` / `users_update` in db/rls-policies.sql plus
/// the `users_update_guard` trigger, all evaluated against `auth.uid()` — and they would still
/// hold if every filter below were deleted.
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

  /// Every manager and warden of one PG, active first, newest first within that.
  ///
  /// Mirrors `getStaff()` in lib/queries/owner.ts exactly, including the ordering. `status` is
  /// the `public.user_status` enum, declared `('active','inactive')`, so ascending puts the
  /// people currently running the PG at the top — an ordering that comes from the enum's
  /// declaration order, not from the alphabet, and would silently invert if that declaration
  /// were ever reordered.
  ///
  /// NOT PAGINATED. §4.3 caps this at one active manager and one active warden; the rest of the
  /// list is the handful of people who have held those posts before.
  ///
  /// SOFT-DELETED ROWS ARE EXCLUDED, not because RLS hides them (it does not — `users_select`
  /// admits any row of a hostel the owner can read) but because a deleted account is not staff.
  Future<List<StaffMember>> staff(String hostelId) => guard(() async {
        final rows = await db
            .from('users')
            .select(StaffMember.columns)
            .eq('hostel_id', hostelId)
            .inFilter('role', const ['manager', 'warden'])
            .isFilter('deleted_at', null)
            .order('status', ascending: true)
            .order('created_at', ascending: false);
        return rows.map(StaffMember.fromJson).toList(growable: false);
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
  /// AUTHORISATION IS THE DATABASE'S. `users_update` admits `role in ('manager','warden') and
  /// app.owns_hostel(hostel_id)`, its WITH CHECK adds `app.hostel_writable(hostel_id)` so a
  /// lapsed subscription refuses, and `app.users_update_guard` independently confirms that
  /// whoever is changing a status actually administers that account. The filters below only
  /// pick the row.
  ///
  /// AN EMPTY RESULT IS A REFUSAL, NOT A SUCCESS. When the USING clause does not admit the row,
  /// Postgres updates nothing and PostgREST reports no error at all — so without the `.select()`
  /// and the check beneath it, "you may not do that" and "done" would look identical.
  ///
  /// REACTIVATION CAN FAIL, ON PURPOSE. `app.enforce_role_limits` fires on `update of status`
  /// too, so reactivating a warden while another one holds the post raises P0001 with its own
  /// sentence, which [AppFailure] passes through verbatim as an [InvalidInputFailure].
  @override
  Future<StaffMember> setStaffStatus({
    required String hostelId,
    required String userId,
    required StaffStatus status,
  }) =>
      guard(() async {
        final rows = await db
            .from('users')
            .update({'status': status.wire})
            .eq('id', userId)
            .eq('hostel_id', hostelId)
            .inFilter('role', const ['manager', 'warden'])
            .isFilter('deleted_at', null)
            .select(StaffMember.columns);

        if (rows.isEmpty) {
          throw const AccessDeniedFailure(
            'That account is no longer part of this PG, or it is not yours to change. '
            'Pull down to refresh the list.',
          );
        }
        return StaffMember.fromJson(rows.first);
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
///   • the function's friendly pre-count           → 409 "This hostel already has an active
///                                                    manager. Deactivate the current manager
///                                                    first."
///   • `app.enforce_role_limits` winning the race  → P0001, mapped by dbError to a 400, then
///                                                    re-wrapped by rollbackAwareError, which
///                                                    hard-codes 400 once the auth user has
///                                                    been rolled back
///   • `users_one_active_staff_per_hostel`         → 23505, dbError's 409 wording, then the
///                                                    same 400 re-wrap
///
/// All three end in the words below, and all three mean exactly one thing to the owner.
final RegExp _roleTaken = RegExp('already has an active', caseSensitive: false);

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
