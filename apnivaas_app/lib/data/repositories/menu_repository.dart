library;

import '../models/models.dart';
import 'repository.dart';

/// The mess menu — the one path to public.menus, for both roles that touch it.
///
/// TABLES: public.menus.
///
/// IT USED TO LIVE IN ManagerRepository, AND THAT WAS RIGHT UNTIL THE RESIDENTS COULD SEE IT.
/// The manager writes the week; every resident of the hostel reads it. Two callers, one table,
/// so one file has the opinion about it — the alternative was a second `.from('menus')` under
/// lib/features/student/, free to select different columns from the ones the kitchen writes.
///
/// NONE OF THE FILTERS BELOW ARE A SECURITY CONTROL. `.eq('hostel_id', …)` is here so the
/// server returns the rows this screen asked for. What decides who may read a hostel's menu and
/// who may change it is row-level security, evaluated against the JWT:
///
///   menus_select  hostel-wide — super admin, the owner of the hostel, or anyone whose own
///                 users row carries that `hostel_id`. That last clause is the resident.
///   menus_write   the MANAGER of that hostel, and nobody else. An owner or a warden calling
///                 [saveMeal] gets 42501, which [AppFailure] renders as "You do not have
///                 access to that".
///
/// Both verified against the live project by executing the insert under the manager's JWT and
/// the select under a resident's: the resident's read returns exactly the row the manager had
/// just written, in the same transaction.
final class MenuRepository extends Repository {
  const MenuRepository(super.db);

  /// The whole week in one request.
  ///
  /// NOT PAGINATED, and that is a considered exception rather than an oversight: the unique
  /// index `menus_hostel_id_day_of_week_meal_key` caps this table at 28 rows per hostel
  /// forever (7 days times 4 meals). Paging 28 rows would cost a second round trip to save
  /// nothing, and fetching a day at a time would cost seven.
  ///
  /// A HOSTEL THAT HAS PLANNED NOTHING RETURNS ZERO ROWS, and that is a legitimate answer, not
  /// an error and not an empty week. [WeeklyMenu.itemsFor] hands back null for every meal and
  /// the screens say "not planned yet" — see the note on [WeeklyMenu].
  Future<WeeklyMenu> weeklyMenu(String hostelId) => guard(() async {
        final rows =
            await db.from('menus').select(MenuEntry.columns).eq('hostel_id', hostelId);
        return WeeklyMenu(rows.map(MenuEntry.fromJson).toList(growable: false));
      });

  /// Write one meal. Manager only.
  ///
  /// An UPSERT on the table's own unique key, so planning Monday's lunch for the first time and
  /// changing it later are the same call. Doing it as "select, then insert or update" would
  /// race a second device and end in a 23505 the user cannot act on.
  ///
  /// An empty [items] is a real value in this column (it is NOT NULL, default ''), so clearing
  /// a meal is a save rather than a delete — the row keeps its `updated_at`, so the week still
  /// shows when somebody last touched it.
  ///
  /// THERE IS NO PUBLISH STEP AND NOTHING BROADCASTS. The upsert IS the publication: every
  /// resident of the hostel can read the row the moment it lands, and there is no notification
  /// trigger on public.menus, so nobody is told. The sheet that calls this says both.
  Future<MenuEntry> saveMeal({
    required String hostelId,
    required MenuDay day,
    required Meal meal,
    required String items,
  }) =>
      guard(() async {
        final row = await db
            .from('menus')
            .upsert(
              {
                'hostel_id': hostelId,
                'day_of_week': day.wire,
                'meal': meal.wire,
                'items': items,
                'updated_by': ?db.auth.currentUser?.id,
              },
              onConflict: 'hostel_id,day_of_week,meal',
            )
            .select(MenuEntry.columns)
            .single();
        return MenuEntry.fromJson(row);
      });
}
