library;

import '../models/models.dart';
import 'repository.dart';

/// Reads about the tenant itself: the hostel row, its floors, and the contact card.
///
/// TABLES: public.hostels, public.floors.
/// RPCs:   public.st_hostel_contacts(), public.ow_update_hostel_rules().
final class HostelRepository extends Repository {
  const HostelRepository(super.db);

  /// The hostel a session is attached to.
  ///
  /// ═══ NULL HERE HAS EXACTLY ONE MEANING, AND IT IS KEPT ═══
  /// "This row is not visible to this account." public.hostels has no soft delete (no
  /// deleted_at — db/schema.sql:94), so the row is either there for you or it is not, and RLS
  /// (`app.can_read_hostel`) is designed to make "another tenant's" and "gone" identical from
  /// out here. There is no client-side reading that separates them, so a thrown failure would
  /// be inventing a distinction the server refuses to draw.
  ///
  /// It stays nullable for a second reason: null is not the ambiguous state on this call. A
  /// FAILED read already throws (via [guard]) and a LOADING one is the provider's AsyncLoading,
  /// so the three that mattered are already three different things — and the screens that read
  /// it word the null case as the plain, unalarming sentence the rule asks for rather than as
  /// an error with a retry that could not help. Turning it into a throw would take that wording
  /// away and replace it with an alarm.
  Future<Hostel?> byId(String hostelId) => guard(() async {
        final row = await db
            .from('hostels')
            .select(Hostel.columns)
            .eq('id', hostelId)
            .maybeSingle();
        return row == null ? null : Hostel.fromJson(row);
      });

  /// Storeys, lowest first. Small and bounded (1–50 by check constraint), so not paginated.
  Future<List<Floor>> floors(String hostelId) => guard(() async {
        final rows = await db
            .from('floors')
            .select(Floor.columns)
            .eq('hostel_id', hostelId)
            .order('floor_number', ascending: true);
        return rows.map(Floor.fromJson).toList(growable: false);
      });

  /// The names and numbers a resident is allowed to see.
  ///
  /// Goes through st_hostel_contacts() rather than joining public.users, because students
  /// cannot read that table at all (§4.8). The function resolves the caller's hostel itself,
  /// so there is nothing to pass and nothing to get wrong.
  ///
  /// ═══ ZERO ROWS IS ABOUT THE CALLER, NOT ABOUT THE HOSTEL ═══
  /// SECURITY DEFINER, and its only filter is
  /// `h.id = coalesce(app.user_hostel_id(), <the caller's student row's hostel>)`
  /// (db/schema.sql:1267). A hostel that resolves ALWAYS produces a row — hostels.name is NOT
  /// NULL, and every other column is allowed to be blank — so there is no such thing as "this
  /// hostel has no contact card". Zero rows means the coalesce found nothing: the caller is not
  /// staff at a hostel and has no live resident row either.
  ///
  /// That used to return null, which the profile screen drew as "Hostel details unavailable —
  /// pull down to try again". Pulling down cannot conjure a hostel assignment, so the screen was
  /// offering a recovery that does not exist. [NotFoundFailure] is not retryable, and it carries
  /// the sentence that actually helps.
  Future<HostelContacts> contacts() => guard(() async {
        final data = await db.rpc('st_hostel_contacts');
        return HostelContacts.fromJson(rpcRowOrMissing(
          data,
          'st_hostel_contacts',
          missing: 'Your account is not attached to a hostel, so there are no contact details '
              'to show. Ask your warden to check your registration.',
        ));
      });

  /// Owner-only edit of the hostel rules text.
  ///
  /// The only field an owner may change on `hostels` — everything else on that table is Super
  /// Admin's. The RPC re-checks ownership AND the read-only gate server-side and raises 42501
  /// on either, which surfaces here as [AccessDeniedFailure] or [ReadOnlyFailure].
  Future<void> updateRules({
    required String hostelId,
    required String rules,
  }) =>
      guard(() async {
        await db.rpc('ow_update_hostel_rules', params: {
          'p_hostel_id': hostelId,
          'p_rules': rules,
        });
      });
}
