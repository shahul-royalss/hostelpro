library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/models.dart';
import '../../../data/repositories/repository.dart';
import 'sa_models.dart';

/// The two calls that CHANGE something on the platform, behind an interface.
///
/// EVERY OTHER METHOD ON [SaRepository] IS A READ, and a screen that reads is tested by
/// overriding the provider that holds the answer. These two are not: one mints a credential
/// that exists exactly once, the other is the only mutation the database permits on an
/// evidence table. Their interesting states — a validator rejecting four fields at once, a
/// rollback that itself failed, an acknowledgement refused by RLS — are the states worth
/// holding down in `flutter test`, and a test needs a stand-in for them.
///
/// The same reasoning (and the same shape) as `RentPayments` in the payment repository: the
/// concrete class stays `final`, and the one seam a test needs is named.
abstract interface class SaPlatformWrites {
  /// Marks one security alert as seen. public.ack_security_alert(bigint).
  Future<void> acknowledgeAlert(int alertId);

  /// Creates the owner (or reuses one), the hostel, its scaffold and its subscription.
  /// supabase/functions/sa-create-owner.
  Future<CreateOutcome> createOwnerAndHostel(CreateOwnerHostelDraft draft);
}

/// Everything the platform console reads and writes.
///
/// TABLES: public.users, public.hostels, public.subscriptions, public.security_alerts.
/// RPCs:   public.rpc_sa_hostels(), public.rpc_sa_onboarding_series(),
///         public.ack_security_alert(bigint).
/// EDGE:   sa-create-owner.
///
/// (public.rpc_sa_dashboard() is read by the shared DashboardRepository, which already had it.)
///
/// ── THE PART WORTH READING TWICE ─────────────────────────────────────────────────────────
///
/// None of the filters below is a permission. Four of these five RPCs end in
/// `where app.is_super_admin()`, which returns ZERO ROWS to anybody else rather than an error,
/// and `security_alerts_select` scopes the table the same way. So an empty result from this
/// class means either "the platform is empty" or "you are not the Super Admin", and the two are
/// indistinguishable here on purpose — the server is not in the business of telling a prober
/// which. Screens must not render emptiness as "no hostels exist"; see [hostels].
///
/// The one write that mints a credential does not happen here at all. Creating a login needs
/// the service-role key, which bypasses RLS for the entire project and therefore may never be
/// inside an APK. [createOwnerAndHostel] posts to an Edge Function that holds it server-side,
/// re-verifies the caller's role against public.users, and then calls
/// sa_create_hostel_with_subscription AS THE CALLER so the RPC's own `app.is_super_admin()`
/// guard still runs. The phone asks; the server decides.
final class SaRepository extends Repository implements SaPlatformWrites {
  const SaRepository(super.db);

  // ───────────────────────────────────────────────────────────────────────────
  // HOSTELS
  // ───────────────────────────────────────────────────────────────────────────

  /// One page of public.rpc_sa_hostels(), optionally narrowed.
  ///
  /// THE SEARCH IS SERVER-SIDE, which for an RPC is not obvious: PostgREST applies filters,
  /// ordering and range to the RESULT of a set-returning function, so `hostel_name` and
  /// `owner_name` below are columns of the function's `returns table (...)` and never reach
  /// this device unless they match. Filtering a page after it arrives would silently hide
  /// hostels 21 and later from a search that should have found them.
  ///
  /// [search] is passed through [sanitizeSearch] first: PostgREST parses the `or=(...)`
  /// parameter itself, so a comma or a bracket in "Sharma, R." would otherwise produce a
  /// malformed filter and a 400 on a completely ordinary name.
  Future<PagedResult<SaHostelRow>> hostels({
    int page = 0,
    int pageSize = PagedResult.defaultPageSize,
    String? search,
    SubscriptionState? subState,
    HostelStatus? hostelStatus,
  }) =>
      guard(() async {
        final bounds = rangeFor(page, pageSize);
        var query = db.rpc('rpc_sa_hostels');

        final needle = sanitizeSearch(search ?? '');
        if (needle.isNotEmpty) {
          query = query.or(
            'hostel_name.ilike.*$needle*,'
            'owner_name.ilike.*$needle*,'
            'owner_email.ilike.*$needle*,'
            'address.ilike.*$needle*',
          );
        }
        if (subState != null) query = query.eq('sub_state', subState.wire);
        if (hostelStatus != null) query = query.eq('hostel_status', hostelStatus.wire);

        final data = await query.range(bounds.from, bounds.to);
        return PagedResult.fromOverfetch(
          rpcRows(data, 'rpc_sa_hostels')
              .map(SaHostelRow.fromJson)
              .toList(growable: false),
          page: page,
          pageSize: pageSize,
        );
      });

  /// The single row for one hostel, from the same function the list is built on.
  ///
  /// Reading the detail screen from rpc_sa_hostels rather than from public.hostels is
  /// deliberate: the owner's name, the subscription state and the bed counts are all computed
  /// there, in one query, and a detail page that recomputed them from separate reads would be
  /// able to disagree with the row the admin just tapped.
  Future<SaHostelRow?> hostel(String hostelId) => guard(() async {
        final data = await db.rpc('rpc_sa_hostels').eq('hostel_id', hostelId).limit(1);
        final row = rpcRow(data, 'rpc_sa_hostels');
        return row == null ? null : SaHostelRow.fromJson(row);
      });

  /// Hostels onboarded per month for the last twelve. public.rpc_sa_onboarding_series().
  ///
  /// Always twelve rows — the function generates the months and counts into them, so a quiet
  /// month is a zero rather than a gap the chart would have to invent.
  Future<List<OnboardingPoint>> onboardingSeries() => guard(() async {
        final data = await db.rpc('rpc_sa_onboarding_series');
        return rpcRows(data, 'rpc_sa_onboarding_series')
            .map(OnboardingPoint.fromJson)
            .toList(growable: false);
      });

  // ───────────────────────────────────────────────────────────────────────────
  // SUBSCRIPTIONS
  // ───────────────────────────────────────────────────────────────────────────

  /// Every paid period for one hostel, newest end date first.
  ///
  /// NOT PAGINATED. One row is written per renewal, so this is a handful of rows for a hostel
  /// that has been on the platform for years, and it is read as a history rather than scrolled.
  Future<List<SubscriptionRecord>> subscriptionHistory(String hostelId) => guard(() async {
        final rows = await db
            .from('subscriptions')
            .select(SubscriptionRecord.columns)
            .eq('hostel_id', hostelId)
            .order('end_date', ascending: false)
            .order('created_at', ascending: false);
        return rows.map(SubscriptionRecord.fromJson).toList(growable: false);
      });

  // ───────────────────────────────────────────────────────────────────────────
  // SECURITY CONSOLE
  // ───────────────────────────────────────────────────────────────────────────

  /// Alerts the detector has raised, newest first.
  ///
  /// CAPPED, NOT PAGINATED. app.raise_security_alert() de-duplicates to one row per
  /// (kind, actor) per hour while unacknowledged, so a sustained attack produces a readable
  /// handful rather than thousands — and retention deletes acknowledged rows older than a year.
  /// A console that scrolled forever would be a console nobody reaches the bottom of.
  Future<List<SecurityAlert>> securityAlerts({
    bool openOnly = false,
    int limit = 100,
  }) =>
      guard(() async {
        var query = db.from('security_alerts').select(SecurityAlert.columns);
        if (openOnly) query = query.isFilter('acknowledged_at', null);
        final rows = await query.order('at', ascending: false).limit(limit);
        return rows.map(SecurityAlert.fromJson).toList(growable: false);
      });

  /// Marks one alert as seen. public.ack_security_alert(p_alert_id).
  ///
  /// AN RPC, NOT AN UPDATE, and the reason is in db/rls-policies.sql: security_alerts has no
  /// write policy of any kind, because anyone able to edit or delete an alert could erase the
  /// evidence of their own activity. Acknowledgement is the only mutation the database permits,
  /// it stamps `acknowledged_by = auth.uid()`, and it is idempotent — the UPDATE carries
  /// `where acknowledged_at is null`, so acknowledging twice does not rewrite who saw it first.
  @override
  Future<void> acknowledgeAlert(int alertId) => guard(() async {
        await db.rpc('ack_security_alert', params: {'p_alert_id': alertId});
      });

  // ───────────────────────────────────────────────────────────────────────────
  // OWNERS
  // ───────────────────────────────────────────────────────────────────────────

  /// Owner accounts that can receive another hostel, with how many they hold today.
  ///
  /// TWO READS, ONE JOIN DONE HERE — the same shape as the web's fetchOwners(). There is no
  /// counter column on public.users and adding one would be a lie the moment a hostel was
  /// created in another session; counting the ids that come back from public.hostels is the
  /// only number that is true at read time. Both reads are RLS-scoped: for anybody who is not
  /// the Super Admin, `users_select` and `hostels_select` return their own rows or none, so
  /// this cannot be used to enumerate the platform.
  Future<List<SaOwnerOption>> owners() => guard(() async {
        final results = await Future.wait<List<Map<String, dynamic>>>([
          db
              .from('users')
              .select(SaOwnerOption.columns)
              .eq('role', 'owner')
              .isFilter('deleted_at', null)
              .order('full_name', ascending: true),
          db.from('hostels').select('owner_user_id'),
        ]);
        final ownerRows = results[0];
        final hostelRows = results[1];

        final counts = <String, int>{};
        for (final row in hostelRows) {
          final id = row['owner_user_id'];
          if (id is String) counts[id] = (counts[id] ?? 0) + 1;
        }
        return ownerRows
            .map((row) => SaOwnerOption.fromJson(row, hostelCount: counts[row['id']] ?? 0))
            .toList(growable: false);
      });

  // ───────────────────────────────────────────────────────────────────────────
  // CREATE OWNER & HOSTEL
  // ───────────────────────────────────────────────────────────────────────────

  /// Creates the hostel, its subscription, its floors/rooms/beds, and — in the `new` branch —
  /// the owner's login. supabase/functions/sa-create-owner.
  ///
  /// RETURNS A REJECTION RATHER THAN THROWING ONE. A form whose fields the server refused is an
  /// ordinary outcome of pressing Create, not an exception: the wizard needs the per-field
  /// messages to put back onto the steps that own them, and `fieldErrors` keys them by the same
  /// dotted paths [CreateOwnerHostelDraft.toJson] writes. Everything that is NOT about the input
  /// — no signal, session expired, not permitted, the server fell over — still throws
  /// [AppFailure], because none of it is something the admin can fix in a text field.
  ///
  /// NO BROWSER, NO WEBVIEW, NO REDIRECT. `functions.invoke` is an HTTPS POST from the app to a
  /// Deno process on Supabase, signed with the current session's access token. The service-role
  /// key that mints the login stays there.
  @override
  Future<CreateOutcome> createOwnerAndHostel(CreateOwnerHostelDraft draft) async {
    final FunctionResponse response;
    try {
      response = await db.functions.invoke('sa-create-owner', body: draft.toJson());
    } on FunctionException catch (error, stack) {
      final rejection = _rejectionFrom(error);
      if (rejection != null) return rejection;
      Error.throwWithStackTrace(_failureFrom(error), stack);
    } catch (error, stack) {
      Error.throwWithStackTrace(AppFailure.from(error), stack);
    }

    final envelope = response.data;
    if (envelope is! Map) {
      throw RowShapeError('sa-create-owner', '(body)', 'expected a JSON object envelope');
    }
    final data = envelope['data'];
    if (data is! Map) {
      throw RowShapeError(
        'sa-create-owner',
        'data',
        'the function answered without a hostel id — check its logs',
      );
    }
    return CreateSucceeded(CreatedHostel.fromJson(data.cast<String, dynamic>()));
  }

  /// A 400 carrying `fieldErrors`, or a 409 that names one field's problem in prose.
  ///
  /// The 409 is worth the extra branch: "An account with this email already exists" is about
  /// exactly one field, on exactly one step, and showing it as a page-level banner sends the
  /// admin looking through four steps for the thing to change.
  static CreateRejected? _rejectionFrom(FunctionException error) {
    final details = error.details;
    if (details is! Map) return null;
    final message = _messageFrom(details);

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
      return CreateRejected(
        message ?? 'Please fix the highlighted fields.',
        fieldErrors: fields,
      );
    }
    // 409 — a real conflict the admin can resolve by editing one field.
    if (error.status == 409 && message != null) {
      final field = message.toLowerCase().contains('email')
          ? 'owner.email'
          : message.toLowerCase().contains('phone')
              ? 'owner.phone'
              : null;
      return CreateRejected(
        message,
        fieldErrors: field == null ? const {} : {field: message},
      );
    }
    return null;
  }

  /// Everything that is not about the input, in the same sealed type the rest of the data layer
  /// throws — so a screen's existing error handling covers it without a special case.
  static AppFailure _failureFrom(FunctionException error) {
    final message = _messageFrom(error.details);

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
      403 => AccessDeniedFailure(
          message ?? 'Only a Super Admin can create owners and hostels.',
          technical: error.toString(),
        ),
      404 => NotFoundFailure(
          message ?? 'That owner account could not be found.',
          technical: error.toString(),
        ),
      // The limiter on this endpoint is fail-closed on purpose: it mints a credential, so a
      // limiter it cannot consult refuses rather than waves through.
      429 => ServerFailure(
          message ?? 'Too many accounts created just now. Wait a minute and try again.',
          technical: error.toString(),
        ),
      // The rollback report. The function's own message names the orphaned auth user id and
      // says what to do about it, which is more useful than anything this file could invent —
      // so it is passed through verbatim.
      _ => ServerFailure(
          message ?? 'Nivora could not finish creating that hostel. Check the hostels list '
              'before trying again.',
          technical: error.toString(),
        ),
    };
  }

  /// The function's own `{ ok: false, error: "..." }` body, when there is one.
  static String? _messageFrom(Object? details) {
    if (details is Map) {
      final error = details['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }
    return null;
  }
}

/// What pressing "Create owner & hostel" produced.
///
/// TWO OUTCOMES, NOT A THROW AND A RETURN. Rejection is the ordinary case of a four-step form
/// meeting a validator that owns the rules; making it an exception would push the field
/// messages through a catch block that has already lost which step they belong to.
sealed class CreateOutcome {
  const CreateOutcome();
}

final class CreateSucceeded extends CreateOutcome {
  const CreateSucceeded(this.result);
  final CreatedHostel result;
}

final class CreateRejected extends CreateOutcome {
  const CreateRejected(this.message, {this.fieldErrors = const {}});

  /// Safe to show as a banner.
  final String message;

  /// Keyed by the dotted path the function used: 'owner.email', 'hostel.rooms',
  /// 'subscription.endDate'. One message per field — the function accumulates a list, and the
  /// first is the one that explains the others.
  final Map<String, String> fieldErrors;
}
