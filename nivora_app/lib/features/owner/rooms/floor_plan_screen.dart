import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../../../shared/rooms/edit_room_sheet.dart';
import '../owner_providers.dart';
import '../widgets/states.dart';
import 'floor_plan_edit.dart';

/// MAPPING THE BUILDING: how many floors, how many rooms on each, and how many beds the rooms
/// Nivora is about to CREATE are given.
///
/// ── THE WARDEN OPENS THIS TOO, AND THE FILE STAYS WHERE IT IS ────────────────────────────
///
/// It was OwnerFloorPlanScreen until 2026-09-12. The product owner: "like how admin can edit
/// layout same as like that warden also can have edit layout option". public.ow_set_floor_plan
/// admits an active warden of the hostel now (app.can_edit_layout), and the warden's room grid
/// pushes this screen.
///
/// It is NOT moved to lib/shared/. Everything it composes lives under features/owner —
/// refreshOwnerBuilding, the owner's state widgets — so shared/ would end up importing
/// features/owner, which is a worse dependency than a warden screen importing a sibling
/// feature. The name lost its prefix; the folder is where the code it uses is.
///
/// WRITES: public.ow_set_floor_plan, once, on Save.
/// READS:  rpc_room_occupancy — the same rows the room grid draws, and the only thing this
///         screen ever seeds itself from.
///
/// ── A SCREEN AND NOT A SHEET ─────────────────────────────────────────────────────────────
///
/// Every other room edit in this app is a bottom sheet, and this one deliberately is not: a
/// twelve-storey hostel is twelve rows of two steppers each, plus a preview, plus a save. A
/// sheet would put that behind a scroll inside a scroll on a 5" phone.
///
/// ── THE THREE THINGS IT HAS TO SAY BEFORE THE TAP, NOT AFTER IT ──────────────────────────
///
///   1. WHAT IS THERE NOW. Every row opens on the floor's real room count and prints the beds
///      taken on it, both counted from rpc_room_occupancy. There is no default plan and no
///      invented number anywhere on this screen.
///   2. WHAT A SAVE WOULD DO. The preview card names every floor that changes and by how many
///      rooms, so a deletion is read here rather than discovered in a snackbar afterwards.
///   3. WHAT WOULD BE REFUSED. ow_set_floor_plan removes the highest-numbered rooms on a floor
///      and refuses any that still hold a resident. This screen already knows the occupied
///      count of every room, so it names those rooms on the row and keeps Save switched off —
///      the same move `showEditRoomSheet` makes about a single room's capacity.
///
/// ── WHAT THE BED STEPPER DOES NOT DO ─────────────────────────────────────────────────────
///
/// It sets the capacity of rooms that do not exist yet. An existing room keeps its beds, and
/// the way to change THAT is `showEditRoomSheet`, one room at a time — which is the only place
/// the occupied count of that one room is known and therefore the only place a bed can safely
/// be taken away. The caption under the heading says so in the owner's words, because a stepper
/// labelled "beds" that silently ignores half the building is a lie told with a control.
class FloorPlanScreen extends ConsumerWidget {
  const FloorPlanScreen({super.key, required this.hostelId});

  /// Pushed from either room grid — the owner's PG detail, or the warden's Rooms tab — which is
  /// where the person is already looking at the floors.
  static Route<void> route(String hostelId) => MaterialPageRoute<void>(
        builder: (_) => FloorPlanScreen(hostelId: hostelId),
      );

  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final hostel = ref.watch(hostelProvider(hostelId));
    final rooms = ref.watch(roomOccupancyProvider(hostelId));

    return Scaffold(
      body: Column(
        children: [
          GlassHeader(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: Space.xxs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit layout',
                        style: t.textTheme.titleLarge?.copyWith(color: t.colorScheme.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        hostel.value?.name ?? 'PG',
                        style: t.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: whenAsync(
              rooms,
              loading: () => ListView(
                padding: const EdgeInsets.all(Space.md),
                children: const [
                  SkeletonCard(lines: 2),
                  SizedBox(height: Space.md),
                  SkeletonCard(lines: 2),
                ],
              ),
              error: (error) => ListView(
                padding: const EdgeInsets.all(Space.md),
                children: [
                  ErrorNote(
                    error: error,
                    onRetry: () => ref.invalidate(roomOccupancyProvider(hostelId)),
                  ),
                ],
              ),
              data: (list) {
                final building = snapshotBuilding(list);
                if (!planCanDescribe(building)) {
                  // ow_set_floor_plan takes floors numbered 1..N with none missing, and
                  // public.floors imposes no such thing — a PG scaffolded from a ground floor
                  // 0 is perfectly legal. Renumbering somebody's building to fit the editor is
                  // not this screen's decision to make, so it says so and stops.
                  return ListView(
                    padding: const EdgeInsets.all(Space.md),
                    children: [
                      EmptyNote(
                        icon: Icons.stairs_outlined,
                        title: 'These floors cannot be edited here',
                        message: 'This PG has floors numbered '
                            '${building.map((f) => f.floor).join(', ')}. The layout editor can '
                            'only describe a building whose floors run 1, 2, 3 and so on with '
                            'none missing. Rooms and beds can still be changed one at a time '
                            'from the room grid.',
                      ),
                    ],
                  );
                }
                return _Editor(
                  hostelId: hostelId,
                  building: building,
                  hostelBedsDefault: hostel.value?.bedsPerRoomDefault,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The plan being composed, held for as long as this screen is open.
///
/// Seeded ONCE, in the field initialiser, from the building handed in. It is deliberately not
/// re-seeded on rebuild: roomOccupancyProvider is only invalidated after a save (and this
/// screen pops itself at that point), and a plan that silently reset itself mid-edit because a
/// provider refreshed would throw away work with no explanation.
class _Editor extends ConsumerStatefulWidget {
  const _Editor({
    required this.hostelId,
    required this.building,
    required this.hostelBedsDefault,
  });

  final String hostelId;
  final List<FloorSnapshot> building;

  /// hostels.beds_per_room_default — used only for a building that has no rooms at all to
  /// learn a house style from. Null while the hostel row is still in flight.
  final int? hostelBedsDefault;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late List<FloorPlanEntry> _plan =
      seedPlan(widget.building, hostelBedsDefault: widget.hostelBedsDefault);

  bool _busy = false;
  String? _error;

  /// Every change to the plan goes through here, and every change CLEARS THE SERVER'S REFUSAL.
  ///
  /// `_error` holds a sentence about a plan that was actually sent — "Room 102 still has residents
  /// in it." Left standing after an edit it becomes a lie in a live region: the owner nudges a
  /// stepper, the headline changes to "Adding 2 rooms.", and above it sits a refusal about a
  /// removal the current plan no longer contains, naming a room it does not go near. The whole
  /// argument of this screen is that the sentence beside the button is true BEFORE the tap, so a
  /// stale one is worse here than nowhere.
  void _edit(void Function() change) {
    setState(() {
      change();
      _error = null;
    });
  }

  void _setRooms(int index, int rooms) =>
      _edit(() => _plan[index] = _plan[index].copyWith(rooms: rooms));

  void _setBeds(int index, int beds) =>
      _edit(() => _plan[index] = _plan[index].copyWith(bedsPerNewRoom: beds));

  /// A new storey on top, starting where the one below it stands — the owner's own most recent
  /// answer to "how many rooms is a floor here", not a number this screen made up. A building
  /// with nothing to copy falls back to the RPC's own minimum of one room.
  void _addFloor() {
    if (_plan.length >= maxFloors) return;
    final below = _plan.isEmpty ? null : _plan.last;
    _edit(() {
      _plan = [
        ..._plan,
        FloorPlanEntry(
          floor: _plan.length + 1,
          rooms: below?.rooms ?? minRoomsPerFloor,
          bedsPerNewRoom: below?.bedsPerNewRoom ??
              seedBedsForNewFloor(widget.building,
                  hostelBedsDefault: widget.hostelBedsDefault),
        ),
      ];
    });
  }

  /// Only ever the LAST one, because the plan has to stay 1..N with none missing — and never the
  /// only one. [minFloors] is what stops an owner walking down to zero storeys, agreeing to a
  /// confirmation dialog that lists the entire building, and putting `[]` on the wire for the
  /// server to refuse. Emptying a PG is the room grid's job, one deliberate deletion at a time.
  void _removeLastFloor() {
    if (_plan.length <= minFloors) return;
    _edit(() => _plan = _plan.sublist(0, _plan.length - 1));
  }

  /// ONE ROOM AT A TIME, FROM THE SCREEN WHERE THE BUILDING IS.
  ///
  /// -- WHY THIS IS HERE AND NOT ONLY IN THE ROOM GRID -----------------------------------
  ///
  /// It was already possible: the sheet exists, the RLS admits the owner, and the repository
  /// call has been there the whole time. It was reachable in three taps from a DIFFERENT screen
  /// -- tile, bed sheet, a text button -- and this screen's own caption told the owner to go and
  /// find it ("change those from the room grid") while offering no way to get there. The product
  /// owner read that caption, saw a stepper labelled "Beds in each new room", and concluded the
  /// app could not give room 103 four beds and room 104 three. A capability nobody can find is
  /// indistinguishable from one that does not exist.
  ///
  /// The chips also do something the room grid cannot: they put every room's bed count on one
  /// line per floor, so the VARIATION the owner is asking to create is legible at a glance
  /// rather than one sheet at a time.
  ///
  /// -- THE TWO WRITES DO NOT COLLIDE ---------------------------------------------------
  ///
  /// The sheet writes public.rooms directly; Save writes public.ow_set_floor_plan. They touch
  /// different things -- capacity and name here, which rooms exist there -- so an owner may do
  /// both in either order. The refresh below re-reads the building, which rebuilds this widget
  /// with a new `building` snapshot; `_plan` survives that because it is State and not a field,
  /// so a half-composed plan is not thrown away by a room rename.
  Future<void> _editRoom(RoomOccupancy room) async {
    if (_busy) return;
    // Resolved before the await, as _save does: this element may be gone by the time the sheet
    // closes, and invalidating through a dead WidgetRef throws.
    final container = ProviderScope.containerOf(context, listen: false);
    final period = ref.read(currentPeriodMonthProvider);

    final changed = await showEditRoomSheet(
      context,
      roomId: room.roomId,
      roomNumber: room.roomNumber,
      capacity: room.capacity,
      occupied: room.occupied,
      floorNumber: room.floorNumber,
    );
    if (!changed) return;

    // Capacity changes create and destroy BED rows server-side (app.rooms_capacity_sync), so
    // the counts on every staff dashboard for this PG have moved -- not just this screen.
    refreshOwnerBuilding(container, hostelId: widget.hostelId, period: period);
    // A refusal left standing after an edit can name a room by a name it no longer has.
    if (mounted) setState(() => _error = null);
  }

  /// The snapshot of one storey as it stands, or null for a storey only the plan knows about.
  FloorSnapshot? _snapshotFor(int floor) {
    for (final f in widget.building) {
      if (f.floor == floor) return f;
    }
    return null;
  }

  /// WHAT A STOREY IS CALLED.
  ///
  /// TWO PATHS, BECAUSE A FLOOR THAT DOES NOT EXIST CANNOT BE RENAMED. An existing floor is
  /// renamed IMMEDIATELY through public.set_floor_name — the same shape as renaming a room, and
  /// the reason is the same: a plan composed ten minutes ago must not travel back in time and
  /// undo somebody else's edit. A floor that only exists in the plan carries its name along
  /// with it and gets it at Save, which is the only moment it exists at all.
  Future<void> _renameFloor(int index) async {
    if (_busy) return;
    final entry = _plan[index];
    final existing = _snapshotFor(entry.floor);

    final typed = await showFloorNameDialog(
      context,
      floorNumber: entry.floor,
      current: existing?.name ?? entry.name,
    );
    if (typed == null || !mounted) return;
    final name = typed.trim().isEmpty ? null : typed.trim();

    final floorId = existing?.id;
    if (floorId == null) {
      _edit(() => _plan[index] = _plan[index].withName(name));
      return;
    }

    // Resolved before the await, as everything else on this screen is: the element may be gone
    // by the time the write returns, and invalidating through a dead WidgetRef throws.
    final container = ProviderScope.containerOf(context, listen: false);
    final period = ref.read(currentPeriodMonthProvider);
    setState(() => _busy = true);
    try {
      await ref.read(roomLayoutWritesProvider).setFloorName(floorId: floorId, name: name);
      refreshOwnerBuilding(container, hostelId: widget.hostelId, period: period);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppFailure.from(error).message;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final preview = previewPlan(building: widget.building, plan: _plan);
    // Both of these already switch the button off. Recomputed here anyway: the button's
    // enabled-ness is a rendering decision and this is the write.
    if (preview.changesNothing || preview.blocked.isNotEmpty) return;

    if (preview.removesAnything && !await _confirmRemoval(preview)) return;
    if (!mounted) return;

    // Resolved before the await: after it this element may be gone, and the screen pops itself
    // on success.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final period = ref.read(currentPeriodMonthProvider);
    // THE CONTAINER, NOT `ref`. The refresh below has to happen even when this screen is gone by
    // the time the write returns — see refreshOwnerBuilding: invalidating through a dead
    // WidgetRef throws a StateError, and the throw lands in a catch that cannot report it.
    final container = ProviderScope.containerOf(context, listen: false);

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(roomLayoutWritesProvider).setFloorPlan(
            hostelId: widget.hostelId,
            plan: _plan,
          );
      // Rooms and beds have moved under every screen that counts them — see
      // refreshOwnerBuilding for exactly which, and why the bed families go whole. Through the
      // CONTAINER and ABOVE the mounted check on purpose: an owner who taps Save and backs out
      // immediately is the ordinary case, and that is precisely the path where the refresh
      // matters most and where a WidgetRef would already be dead.
      refreshOwnerBuilding(container, hostelId: widget.hostelId, period: period);
      if (!mounted) return;
      setState(() => _busy = false);
      // The server's own tally, not the preview's. If the two ever disagree, the one that ran
      // inside the transaction is the one an owner is told.
      messenger.showSnackBar(SnackBar(
        content: Text(result.summary),
        behavior: SnackBarBehavior.floating,
      ));
      navigator.pop();
    } on AppFailure catch (failure) {
      // VERBATIM. A refusal from ow_set_floor_plan names the room that is in the way ("Room 102
      // still has residents in it…"), and a tidier generic sentence would send an owner to walk
      // the floor looking for it.
      if (mounted) {
        setState(() {
          _error = failure.message;
          _busy = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = AppFailure.from(error).message;
          _busy = false;
        });
      }
    }
  }

  /// Adding is free and is saved on one tap. Taking something away is agreed to out loud, with
  /// the same per-floor lines the preview card is already showing, because a room that goes is
  /// a room number that does not come back.
  Future<bool> _confirmRemoval(FloorPlanPreview preview) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove rooms?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Saving this layout makes these changes:'),
            const SizedBox(height: Space.sm),
            for (final line in preview.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xxs),
                child: Text(line),
              ),
            const SizedBox(height: Space.sm),
            const Text('Rooms that go are deleted, not archived. Only empty ones can go.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          // The confirm of the screen's ONE primary action, not a second one — the same
          // pattern the owner's staff screen uses for its deactivation.
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save layout'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final byFloor = {for (final floor in widget.building) floor.floor: floor};
    final preview = previewPlan(building: widget.building, plan: _plan);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.lg),
            children: [
              const SectionHeading(
                domain: NivoraDomain.rooms,
                icon: Icons.stairs_rounded,
                title: 'Floors and rooms',
                caption: 'The bed count sets how many beds a NEW room gets. Rooms that '
                    'already exist keep the beds they have — tap any room below to rename it '
                    'or give it a different number of beds.',
              ),
              if (_plan.isEmpty)
                const EmptyNote(
                  icon: Icons.stairs_outlined,
                  title: 'No floors yet',
                  message: 'Add the first floor and say how many rooms are on it.',
                  compact: true,
                ),
              for (var i = 0; i < _plan.length; i++) ...[
                _FloorRow(
                  entry: _plan[i],
                  existing: byFloor[_plan[i].floor],
                  enabled: !_busy,
                  onRooms: (value) => _setRooms(i, value),
                  onBeds: (value) => _setBeds(i, value),
                  onEditRoom: _editRoom,
                  onRename: () => _renameFloor(i),
                ),
                const SizedBox(height: Space.sm),
              ],
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  TextButton.icon(
                    onPressed: _busy || _plan.length >= maxFloors ? null : _addFloor,
                    icon: const Icon(Icons.add_rounded, size: IconSize.sm),
                    label: Text('Add floor ${_plan.length + 1}'),
                  ),
                  if (_plan.isNotEmpty)
                    TextButton.icon(
                      onPressed:
                          _busy || _plan.length <= minFloors ? null : _removeLastFloor,
                      icon: const Icon(Icons.remove_rounded, size: IconSize.sm),
                      label: Text('Remove floor ${_plan.length}'),
                    ),
                ],
              ),
              const SizedBox(height: Space.lg),
              _PreviewCard(preview: preview),
            ],
          ),
        ),
        _SaveBar(
          preview: preview,
          busy: _busy,
          error: _error,
          onSave: _save,
        ),
      ],
    );
  }
}

/// One storey: what is there now, and what the owner is asking for.
class _FloorRow extends StatelessWidget {
  const _FloorRow({
    required this.entry,
    required this.existing,
    required this.enabled,
    required this.onRooms,
    required this.onBeds,
    required this.onEditRoom,
    required this.onRename,
  });

  final FloorPlanEntry entry;

  /// Null for a storey being added, which has nothing to report about itself yet.
  final FloorSnapshot? existing;
  final bool enabled;
  final ValueChanged<int> onRooms;
  final ValueChanged<int> onBeds;

  /// Opens one EXISTING room for a rename or a change of beds.
  final ValueChanged<RoomOccupancy> onEditRoom;

  /// Names the storey itself.
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final now = existing;
    final blocked = now == null ? const <RoomOccupancy>[] : now.blockedBy(entry.rooms);
    // The saved name for a storey that exists, the pending one for a storey being added.
    final name = now?.name ?? entry.name;
    final hasName = (name ?? '').trim().isNotEmpty;
    final named = floorLabel(entry.floor, name);

    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                // The NAME when the PG has given this storey one, "Floor N" when it has not.
                // The number does not follow it into the title — a heading that reads
                // "Terrace (Floor 4)" is a screen that does not trust the person who typed the
                // name — it goes in the caption below, where the plan's own arithmetic is.
                child: Text(named, style: t.textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'Name this floor',
                onPressed: enabled ? onRename : null,
                icon: const Icon(Icons.drive_file_rename_outline_rounded, size: IconSize.md),
              ),
              if (now == null)
                const StatusChip(label: 'New floor', tone: NivoraColors.info),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(
            // Counted from rpc_room_occupancy, never from hostels.total_rooms.
            [
              if (hasName) 'Floor ${entry.floor}',
              if (now == null)
                'Nothing on this floor yet.'
              else
                '${roomsLabel(now.roomCount)} now · '
                    '${now.occupiedBeds} of ${now.bedCount} beds taken',
            ].join(' · '),
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.sm),
          _Stepper(
            label: 'Rooms',
            value: entry.rooms,
            min: minRoomsPerFloor,
            max: maxRoomsPerFloor,
            enabled: enabled,
            decreaseTooltip: 'One fewer room on floor ${entry.floor}',
            increaseTooltip: 'One more room on floor ${entry.floor}',
            onChanged: onRooms,
          ),
          const SizedBox(height: Space.xs),
          _Stepper(
            label: 'Beds in each new room',
            value: entry.bedsPerNewRoom,
            min: minBedsPerRoom,
            max: maxBedsPerRoom,
            enabled: enabled,
            decreaseTooltip: 'One fewer bed in new rooms on floor ${entry.floor}',
            increaseTooltip: 'One more bed in new rooms on floor ${entry.floor}',
            onChanged: onBeds,
          ),
          if (now != null && now.rooms.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text('Rooms on this floor', style: t.textTheme.bodyMedium),
            const SizedBox(height: Space.xxs),
            Text(
              // Said plainly, because the two bed controls on this card mean different things
              // and the difference is exactly what confused the owner. The stepper above is
              // about rooms that do not exist yet; these are the rooms that do.
              'Tap one to rename it or change its beds. Every room can be different.',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final room in now.rooms)
                  _RoomChip(
                    room: room,
                    enabled: enabled,
                    onTap: () => onEditRoom(room),
                  ),
              ],
            ),
          ],
          if (blocked.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                blockedSentence(blocked),
                style: t.textTheme.bodySmall?.copyWith(color: context.tones.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// NAMING A STOREY.
///
/// Returns null when it was cancelled, the typed name otherwise — and an EMPTY STRING means
/// "clear it", which is a real answer rather than a cancellation. The caller turns blank into
/// null; the database stores null and every screen falls back to "Floor N" (see [floorLabel]).
///
/// A StatefulWidget rather than a function holding a TextEditingController, because a
/// controller created inside a builder is never disposed — Flutter's test framework reports it,
/// and on a device it is a listener left attached to a dead route.
Future<String?> showFloorNameDialog(
  BuildContext context, {
  required int floorNumber,
  String? current,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _FloorNameDialog(floorNumber: floorNumber, current: current),
    );

class _FloorNameDialog extends StatefulWidget {
  const _FloorNameDialog({required this.floorNumber, required this.current});

  final int floorNumber;
  final String? current;

  @override
  State<_FloorNameDialog> createState() => _FloorNameDialogState();
}

class _FloorNameDialogState extends State<_FloorNameDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: Text('Name floor ${widget.floorNumber}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What this storey is called — "Ground floor", "Terrace", "Girls\' wing". Leave it '
            'empty to go back to "Floor ${widget.floorNumber}".',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _name,
            autofocus: true,
            // The column's own CHECK: 1–40 characters, trimmed. Enforced here so the refusal
            // is a keystroke that does not land rather than a round trip.
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Floor name', counterText: ''),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// ONE ROOM, AND WHAT IT HOLDS -- the smallest thing that can carry "103 has four beds".
///
/// The bed count is on the face of the chip rather than behind a tap, because a floor of
/// three-bed rooms with one four-bed room in it is precisely the state the owner is trying to
/// create, and a row of chips is where that becomes visible at all. The OCCUPIED count is not
/// here: it belongs to the decision about removing a bed, and that decision is made inside the
/// sheet, where the server's own refusal can be spelled out beside the stepper.
class _RoomChip extends StatelessWidget {
  const _RoomChip({required this.room, required this.enabled, required this.onTap});

  final RoomOccupancy room;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final beds = room.capacity == 1 ? '1 bed' : '${room.capacity} beds';

    return Semantics(
      button: true,
      label: 'Room ${room.roomNumber}, $beds, ${room.occupied} taken. Edit.',
      excludeSemantics: true,
      child: Material(
        color: GlassWeight.regular.surfaceOf(t.colorScheme),
        borderRadius: Radii.rControl,
        child: InkWell(
          borderRadius: Radii.rControl,
          onTap: enabled ? onTap : null,
          child: Container(
            // A real target, not a 32dp chip: this is a WRITE control on a phone held
            // one-handed in a corridor, so Material's 48dp floor applies to it like anything
            // else. minHeight rather than height, so it grows with the system text size
            // instead of clipping -- the failure the bottom bar had.
            constraints: const BoxConstraints(minHeight: Space.xxxl + Space.md),
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
            decoration: BoxDecoration(
              borderRadius: Radii.rControl,
              border: Border.all(
                color: t.colorScheme.outlineVariant,
                width: Strokes.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(room.roomNumber, style: t.textTheme.titleSmall),
                    Text(beds, style: t.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(width: Space.xs),
                Icon(
                  Icons.edit_outlined,
                  size: IconSize.sm,
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Plus, minus, and the number between them.
///
/// ONE AT A TIME, AND THAT IS NOT A DETAIL. A stepper in this app that skipped numbers has been
/// a real bug once already; matching `showEditRoomSheet`'s outlined +/- exactly is how the two
/// controls stay one control. The bounds are the RPC's own (1..200 rooms, 1..12 beds), so a
/// button is only ever dark because the server would refuse the value behind it.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.decreaseTooltip,
    required this.increaseTooltip,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final String decreaseTooltip;
  final String increaseTooltip;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: t.textTheme.bodyMedium)),
        IconButton.outlined(
          tooltip: decreaseTooltip,
          onPressed: enabled && value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Container(
          // Wide enough for three digits at the figure's own size, and it grows with the text
          // scale rather than clipping at 1.4x.
          constraints: BoxConstraints(
            minWidth: MediaQuery.textScalerOf(context).scale(Space.huge),
          ),
          alignment: Alignment.center,
          child: Text('$value', style: t.textTheme.titleLarge),
        ),
        IconButton.outlined(
          tooltip: increaseTooltip,
          onPressed: enabled && value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

/// WHAT A SAVE WOULD DO, floor by floor, before it is tapped.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final FloorPlanPreview preview;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardEyebrow(
            label: 'What saving does',
            trailing: DomainIcon(
              domain: NivoraDomain.rooms,
              icon: Icons.rule_rounded,
              size: DomainIconSize.sm,
            ),
          ),
          const SizedBox(height: Space.sm),
          if (preview.changesNothing)
            Text(
              'This is the building as it stands. Nothing will change.',
              style: t.textTheme.bodyMedium,
            )
          else
            for (final line in preview.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Text(line, style: t.textTheme.bodyMedium),
              ),
          if (preview.blocked.isNotEmpty) ...[
            const SizedBox(height: Space.xxs),
            Text(
              blockedSentence(preview.blocked),
              style: t.textTheme.bodySmall?.copyWith(color: context.tones.error),
            ),
          ],
        ],
      ),
    );
  }
}

/// The screen's one primary action, and the one line that says what it is about to do.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.preview,
    required this.busy,
    required this.error,
    required this.onSave,
  });

  final FloorPlanPreview preview;
  final bool busy;
  final String? error;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // THE REASON THE BUTTON IS DARK, BESIDE THE BUTTON.
    //
    // A blocked removal is named on the floor row that carries it — but dropping a whole FLOOR
    // removes that row, so the only remaining copy was in the preview card at the bottom of a
    // scrolling list. On the twelve-storey hostel this screen was written for, that card is off
    // screen, and the owner is left looking at a dead primary action with no explanation anywhere
    // near it. The server's own refusal already lands in this slot; the predicted one belongs
    // here too, and it takes precedence because it describes the plan as it stands now.
    final blocked = blockedSentence(preview.blocked);
    final message = blocked.isNotEmpty ? blocked : error;
    // Nothing to save, or something the server would refuse. Either way the button says so by
    // being dark rather than by finding out.
    final canSave = !busy && !preview.changesNothing && preview.blocked.isEmpty;

    return GlassSurface(
      weight: GlassWeight.regular,
      borderRadius: BorderRadius.zero,
      border: Border(
        top: BorderSide(color: GlassSurface.edgeColor(context), width: Strokes.hairline),
      ),
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.sm)
          .add(EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: t.textTheme.bodyMedium?.copyWith(color: context.tones.error),
              ),
            ),
            const SizedBox(height: Space.sm),
          ],
          Text(preview.headline, style: t.textTheme.bodySmall),
          const SizedBox(height: Space.xs),
          FilledButton(
            onPressed: canSave ? onSave : null,
            child: busy
                ? SizedBox.square(
                    dimension: IconSize.md,
                    child: CircularProgressIndicator(
                      strokeWidth: Strokes.glyph,
                      color: t.colorScheme.onPrimary,
                    ),
                  )
                : const Text('Save layout'),
          ),
        ],
      ),
    );
  }
}
