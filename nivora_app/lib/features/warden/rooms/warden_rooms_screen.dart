library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../widgets/warden_ui.dart';
import 'room_sheet.dart';

/// The building, floor by floor.
///
/// THIS IS THE SCREEN THE PRODUCT IS FOR. A warden standing in a stairwell wants one question
/// answered — where is there a free bed? — and a table cannot answer it: a table makes you read
/// twelve rows and do arithmetic. A grid answers it in the shape of the building itself, with a
/// pip per bed, so "the second floor is full and 104 has two spare" is a glance rather than a
/// calculation.
///
/// WHAT THE PIPS ARE AND ARE NOT. rpc_room_occupancy returns capacity and a count of beds whose
/// student_id is set. That is a NUMBER of occupied beds, not a list of which ones, so the pips
/// are a fuel gauge: three pips with two filled means two of the three beds in that room are
/// taken. Tapping the room asks public.beds which specific ones — see showRoomSheet. Drawing
/// pips as if they were addressable beds would be a lie the data cannot support.
///
/// THERE IS NO MAINTENANCE STATE. public.bed_status is exactly ('free','occupied'); a bed under
/// repair is not something this schema can express. Inventing a third colour here would mean
/// inventing data, so the legend says two things and means them.
class WardenRoomsScreen extends ConsumerWidget {
  const WardenRoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);
    if (hostelId == null) {
      return const WardenScreen(
        title: 'Rooms',
        child: EmptyState(
          icon: Icons.apartment_rounded,
          title: 'No hostel on this account',
          detail: 'A warden is attached to one hostel. Ask the owner to check the assignment.',
        ),
      );
    }

    final occupancy = ref.watch(roomOccupancyProvider(hostelId));
    final rooms = occupancy.value;
    final beds = rooms?.fold<int>(0, (sum, r) => sum + r.capacity) ?? 0;
    final taken = rooms?.fold<int>(0, (sum, r) => sum + r.occupied) ?? 0;

    return WardenScreen(
      title: 'Rooms',
      // Counted from the very rows drawn below, so the heading can never disagree with the grid.
      subtitle: rooms == null ? null : '$taken of $beds beds occupied · ${beds - taken} free',
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(roomOccupancyProvider(hostelId)),
        child: AsyncSection<List<RoomOccupancy>>(
          value: occupancy,
          onRetry: () => ref.invalidate(roomOccupancyProvider(hostelId)),
          builder: (list) {
            if (list.isEmpty) {
              return ListView(
                children: const [
                  EmptyState(
                    icon: Icons.meeting_room_outlined,
                    title: 'No rooms yet',
                    detail: 'Rooms and beds are scaffolded when the hostel is set up. '
                        'Ask the owner if this looks wrong.',
                  ),
                ],
              );
            }
            return _FloorList(rooms: list);
          },
        ),
      ),
    );
  }
}

class _FloorList extends StatelessWidget {
  const _FloorList({required this.rooms});
  final List<RoomOccupancy> rooms;

  @override
  Widget build(BuildContext context) {
    // rpc_room_occupancy already returns floor_number, room_number order, so grouping in a
    // sequential pass preserves it — no second sort, and the storeys come out in walking order.
    final floors = <int, List<RoomOccupancy>>{};
    for (final room in rooms) {
      floors.putIfAbsent(room.floorNumber, () => []).add(room);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - Space.md * 2;
        // Two columns on the smallest phone still supported, more as the screen allows. Room
        // cards get wider, never taller: the text inside stays at its designed size.
        final columns = width < 380
            ? 2
            : width < Breakpoints.medium
                ? 3
                : 4;
        final tileWidth = (width - Space.xs * (columns - 1)) / columns;

        return ListView(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxxl),
          children: [
            const _Legend(),
            for (final entry in floors.entries) ...[
              SectionLabel(
                label: 'Floor ${entry.key}',
                trailing: _FloorSummary(rooms: entry.value),
              ),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final room in entry.value)
                    SizedBox(
                      width: tileWidth,
                      child: _RoomTile(room: room),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _FloorSummary extends StatelessWidget {
  const _FloorSummary({required this.rooms});
  final List<RoomOccupancy> rooms;

  @override
  Widget build(BuildContext context) {
    final free = rooms.fold<int>(0, (sum, r) => sum + r.free);
    return Text(
      free == 0 ? 'full' : '$free free',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: free == 0 ? null : context.tones.success,
          ),
    );
  }
}

/// One room. Big enough to hit without aiming: the whole tile is the target.
class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room});
  final RoomOccupancy room;

  /// At 1.0x. Scaled with the text inside it below.
  static const _tileHeight = 116.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final full = room.isFull;

    return Semantics(
      button: true,
      label: 'Room ${room.roomNumber}, ${room.occupied} of ${room.capacity} beds occupied',
      child: Material(
        color: t.colorScheme.surface,
        borderRadius: Radii.rCard,
        child: InkWell(
          borderRadius: Radii.rCard,
          onTap: () => showRoomSheet(
            context,
            roomId: room.roomId,
            roomNumber: room.roomNumber,
            floorNumber: room.floorNumber,
          ),
          child: Container(
            // Scaled with its own text. A fixed 116 was sized against 1.0x type; at 1.4x the
            // room number, the pips and the "3 free" line together overran it.
            height: MediaQuery.textScalerOf(context).scale(_tileHeight),
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              borderRadius: Radii.rCard,
              border: Border.all(
                // A room with space says so before you read it.
                color: full
                    ? t.colorScheme.outlineVariant
                    : tones.chipBorder(NivoraColors.success),
                width: Strokes.hairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  room.roomNumber,
                  style: t.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                _BedPips(capacity: room.capacity, occupied: room.occupied),
                Text(
                  full ? 'Full' : '${room.free} free',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: full ? t.colorScheme.onSurfaceVariant : tones.success,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pip per bed: filled for occupied, hollow for free.
///
/// Capped at eight so a dormitory of twenty does not wrap into three rows and break the grid;
/// past that the count in words carries the meaning and the pips would be unreadable anyway.
class _BedPips extends StatelessWidget {
  const _BedPips({required this.capacity, required this.occupied});
  final int capacity;
  final int occupied;

  static const _max = 8;

  /// One pip. Small enough that eight fit across a tile, large enough to see.
  static const _pip = 12.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final free = context.tones.success;
    final shown = capacity > _max ? _max : capacity;
    // Which pips are filled is arbitrary — the RPC gives a count, not a mapping — so they fill
    // from the left. See the class doc on WardenRoomsScreen.
    final filled = capacity > _max ? (occupied * _max / capacity).round() : occupied;

    return Row(
      children: [
        for (var i = 0; i < shown; i++)
          Padding(
            padding: const EdgeInsets.only(right: Space.xxs),
            child: Container(
              width: _pip,
              height: _pip,
              decoration: BoxDecoration(
                color: i < filled ? t.colorScheme.primary : context.tones.chipFill(free),
                borderRadius: Radii.rTiny,
                border: i < filled
                    ? null
                    : Border.all(color: free, width: Strokes.hairline),
              ),
            ),
          ),
        if (capacity > _max)
          Text('+${capacity - _max}', style: t.textTheme.labelSmall),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        _LegendItem(
          label: 'Occupied',
          colour: t.colorScheme.primary,
          filled: true,
        ),
        const SizedBox(width: Space.md),
        _LegendItem(label: 'Free', colour: context.tones.success, filled: false),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.colour, required this.filled});
  final String label;
  final Color colour;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _BedPips._pip,
          height: _BedPips._pip,
          decoration: BoxDecoration(
            color: filled ? colour : context.tones.chipFill(colour),
            borderRadius: Radii.rTiny,
            border: filled ? null : Border.all(color: colour, width: Strokes.hairline),
          ),
        ),
        const SizedBox(width: Space.xs),
        Text(label, style: t.textTheme.bodySmall),
      ],
    );
  }
}
