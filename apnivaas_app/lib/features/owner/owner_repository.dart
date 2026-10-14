library;

import '../../data/models/models.dart';
import '../../data/repositories/repository.dart';

/// The one read the shared data layer does not already have: "which PGs do I own?"
///
/// WHY IT LIVES HERE AND NOT IN lib/data. Every method in `HostelRepository` answers a question
/// about ONE hostel, because every other role in this app belongs to exactly one — a warden, a
/// manager and a resident all have `users.hostel_id` and that is the end of it. The owner is
/// the only role that can hold more than one deed: `hostels.owner_user_id` is indexed, and
/// `app.owns_hostel()` in db/schema.sql resolves ownership from that column rather than from
/// `users.hostel_id`. So this is an owner-shaped question, and it sits in the owner feature
/// until a second role needs it — at which point it should move to HostelRepository unchanged.
///
/// It is still a repository, not a query inside a widget: it returns models, it goes through
/// [guard], and it extends the same base as the rest of the data layer.
///
/// TABLES: public.hostels.
final class OwnerRepository extends Repository {
  const OwnerRepository(super.db);

  /// Every hostel this user owns, by name.
  ///
  /// THE FILTER IS NOT THE CONTROL. `hostels_select` is `using (app.can_read_hostel(id))`, so
  /// the server would refuse another owner's rows with or without the `.eq()` below. The
  /// filter is there so Postgres does less work and so the intent is legible — passing someone
  /// else's user id here returns nothing, because RLS evaluates `auth.uid()`, not this
  /// argument.
  ///
  /// NOT PAGINATED. `total_rooms` is capped at 5 000 per hostel by a check constraint, but the
  /// number of hostels one owner holds is a handful — this list feeds a switcher, and a
  /// switcher that paginates is a menu you cannot read.
  Future<List<Hostel>> hostelsOwnedBy(String ownerUserId) => guard(() async {
        final rows = await db
            .from('hostels')
            .select(Hostel.columns)
            .eq('owner_user_id', ownerUserId)
            .order('name', ascending: true);
        return rows.map(Hostel.fromJson).toList(growable: false);
      });
}
