import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../owner_providers.dart';
import '../widgets/states.dart';
import 'floor_plan_edit.dart';

/// THE OWNER MAPS THE BUILDING: how many floors, how many rooms on each, and how many beds the
/// rooms Nivora is about to CREATE are given.
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
class OwnerFloorPlanScreen extends ConsumerWidget {
  const OwnerFloorPlanScreen({super.key, required this.hostelId});

  /// Pushed from the room grid, which is where an owner is already looking at the floors.
  static Route<void> route(String hostelId) => MaterialPageRoute<void>(
        builder: (_) => OwnerFloorPlanScreen(hostelId: hostelId),
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
                caption: 'The bed count sets how many beds a NEW room gets. Rooms that already '
                    'exist keep the beds they have — change those from the room grid.',
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
  });

  final FloorPlanEntry entry;

  /// Null for a storey being added, which has nothing to report about itself yet.
  final FloorSnapshot? existing;
  final bool enabled;
  final ValueChanged<int> onRooms;
  final ValueChanged<int> onBeds;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final now = existing;
    final blocked = now == null ? const <RoomOccupancy>[] : now.blockedBy(entry.rooms);

    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('Floor ${entry.floor}', style: t.textTheme.titleMedium),
              ),
              if (now == null)
                const StatusChip(label: 'New floor', tone: NivoraColors.info),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(
            // Counted from rpc_room_occupancy, never from hostels.total_rooms.
            now == null
                ? 'Nothing on this floor yet.'
                : '${roomsLabel(now.roomCount)} now · '
                    '${now.occupiedBeds} of ${now.bedCount} beds taken',
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
