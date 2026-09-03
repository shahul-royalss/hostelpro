import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import '../../shared/rooms/edit_room_sheet.dart';
import 'owner_format.dart';
import 'owner_providers.dart';
import 'widgets/meter.dart';
import 'widgets/states.dart';

/// One PG, floor by floor: which rooms have space and who is in which bed.
///
/// READS: rpc_room_occupancy (the grid) · hostels (the header) · beds and students (one room's
/// beds, on demand).
///
/// THE GRID IS NOT PAGINATED, deliberately — see RoomRepository.occupancy. A room grid exists
/// to show a building at a glance, and a grid that paginates cannot. What IS lazy is the
/// per-floor build: the outer list builds a floor at a time, so a fifty-storey hostel does not
/// lay out three thousand tiles to draw the twelve on screen.
class OwnerPgDetailScreen extends ConsumerWidget {
  const OwnerPgDetailScreen({super.key, required this.hostelId});

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
                        'Rooms & beds',
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
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(roomOccupancyProvider(hostelId));
                try {
                  await ref
                      .read(roomOccupancyProvider(hostelId).future)
                      .timeout(ownerRefreshTimeout);
                } catch (_) {
                  // Rendered by the body below; rethrowing would make it unhandled.
                }
              },
              child: whenAsync(
                rooms,
                loading: () => ListView(
                  padding: const EdgeInsets.all(Space.md),
                  // Heights are the card's own business. Pinning them meant the real
                  // cards outgrew the placeholder at 1.4x text scale and the page jumped.
                  children: const [
                    SkeletonCard(lines: 1),
                    SizedBox(height: Space.md),
                    SkeletonCard(lines: 2),
                    SizedBox(height: Space.md),
                    SkeletonCard(lines: 2),
                  ],
                ),
                error: (error) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(Space.md),
                  children: [
                    ErrorNote(
                      error: error,
                      onRetry: () => ref.invalidate(roomOccupancyProvider(hostelId)),
                    ),
                  ],
                ),
                data: (list) => _Floors(rooms: list),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Floors extends StatelessWidget {
  const _Floors({required this.rooms});

  final List<RoomOccupancy> rooms;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.md),
        children: const [
          EmptyNote(
            icon: Icons.meeting_room_outlined,
            title: 'No rooms set up yet',
            message: 'Nivora scaffolds the floors, rooms and beds when a PG is created. '
                'Contact your account manager if this PG should already have them.',
          ),
        ],
      );
    }

    // The RPC already returns rows ordered by floor then room number, so grouping is a single
    // pass and the floors come out in the order a person would walk them.
    final byFloor = <int, List<RoomOccupancy>>{};
    for (final room in rooms) {
      byFloor.putIfAbsent(room.floorNumber, () => <RoomOccupancy>[]).add(room);
    }
    final floors = byFloor.keys.toList(growable: false)..sort();

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
      // One extra leading item: the building-wide summary.
      itemCount: floors.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _BuildingSummary(rooms: rooms);
        final floor = floors[index - 1];
        return _FloorBlock(floorNumber: floor, rooms: byFloor[floor]!);
      },
    );
  }
}

/// The totals for the whole building, added up from the very rows drawn below — so the header
/// and the grid can never tell two different stories.
class _BuildingSummary extends StatelessWidget {
  const _BuildingSummary({required this.rooms});
  final List<RoomOccupancy> rooms;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    var capacity = 0;
    var occupied = 0;
    var roomsWithSpace = 0;
    for (final r in rooms) {
      capacity += r.capacity;
      occupied += r.occupied;
      if (!r.isFull) roomsWithSpace++;
    }
    final rate = capacity == 0 ? null : occupied / capacity;

    // The dashboard's Occupancy card, on the screen it opens onto: the same eyebrow, the same
    // figure size and the same meter, so the tap does not land somewhere that looks like a
    // different app. The `bed` glyph at its head is in the rooms colour — this card IS the
    // building, and violet is what says "rooms" everywhere. Only the icon: the meter below
    // is a figure, and the card stays a plain card rather than a [DomainCard].
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: GlassCard(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardEyebrow(
              label: 'Occupancy',
              trailing: DomainIcon(
                domain: NivoraDomain.rooms,
                icon: Icons.bed_rounded,
                size: DomainIconSize.sm,
              ),
            ),
            const SizedBox(height: Space.md),
            Text('$occupied of $capacity beds filled', style: t.textTheme.headlineMedium),
            const SizedBox(height: Space.md),
            ProportionMeter(value: rate, semanticLabel: 'Beds occupied'),
            const SizedBox(height: Space.sm),
            Text(
              rate == null
                  ? 'No beds have been set up in these rooms yet.'
                  : '${percentLabel(rate)} full · '
                      '${countLabel(roomsWithSpace, 'room')} with space · '
                      '${countLabel(rooms.length, 'room')} in total',
              style: t.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FloorBlock extends StatelessWidget {
  const _FloorBlock({required this.floorNumber, required this.rooms});

  final int floorNumber;
  final List<RoomOccupancy> rooms;

  @override
  Widget build(BuildContext context) {
    var free = 0;
    for (final r in rooms) {
      free += r.free;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            // Floor numbering is whatever the hostel was scaffolded with — ground floor may be
            // 0 or 1 — so the number is printed as stored, never as `n + 1`. See Floor.
            title: 'Floor $floorNumber',
            caption: free == 0
                ? '${countLabel(rooms.length, 'room')} · full'
                : '${countLabel(rooms.length, 'room')} · ${countLabel(free, 'bed')} free',
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final room in rooms) _RoomTile(room: room),
            ],
          ),
        ],
      ),
    );
  }
}

/// One room. The dots are the point: capacity is 1–12 by check constraint, so a bed-per-dot
/// reading is exact rather than a bar to be estimated against.
class _RoomTile extends ConsumerWidget {
  const _RoomTile({required this.room});

  /// At 1.0x. Two tiles and their gutter fit a 320dp phone with the page padding on.
  static const _tileWidth = 104.0;

  final RoomOccupancy room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final tones = context.tones;
    final hasSpace = !room.isFull;
    return SizedBox(
      // Scaled with the text inside it. A fixed 104 was sized against 1.0x type; at 1.4x the
      // room number and the "3 free" line under it both grew and the tile clipped.
      width: MediaQuery.textScalerOf(context).scale(_tileWidth),
      child: Material(
        // A step UP the container ramp: the tiles sit on the page ground, and in the dark
        // theme a `thin` tile on that ground is barely a shape. `surface-container` is what
        // the design paints a block that content sits ON rather than under.
        color: GlassWeight.regular.surfaceOf(t.colorScheme),
        borderRadius: Radii.rCard,
        child: InkWell(
          borderRadius: Radii.rCard,
          onTap: () => _showBeds(context, room),
          child: Container(
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              borderRadius: Radii.rCard,
              border: Border.all(
                // Vacancy is what an owner is scanning for, so vacancy is what the border
                // marks. A full room is not a problem and does not get an alarm colour.
                color: hasSpace
                    ? tones.chipBorder(NivoraColors.success)
                    : t.colorScheme.outlineVariant,
                width: Strokes.hairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(room.roomNumber,
                    style: t.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.xs),
                _BedDots(capacity: room.capacity, occupied: room.occupied),
                const SizedBox(height: Space.xs),
                Text(
                  hasSpace ? '${room.free} free' : 'Full',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: hasSpace ? tones.success : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showBeds(BuildContext context, RoomOccupancy room) {
    return showGlassSheet<void>(
      context: context,
      builder: (ctx) => _BedSheet(room: room),
    );
  }
}

class _BedDots extends StatelessWidget {
  const _BedDots({required this.capacity, required this.occupied});

  final int capacity;
  final int occupied;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      label: '$occupied of $capacity beds occupied',
      child: Wrap(
        spacing: Space.xxs,
        runSpacing: Space.xxs,
        children: [
          for (var i = 0; i < capacity; i++)
            Container(
              width: Space.xs,
              height: Space.xs,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < occupied ? t.colorScheme.primary : Colors.transparent,
                border: i < occupied ? null : Border.all(color: t.colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}

/// Who is in which bed. Opened from a room tile, because "3 free" is a number whose next
/// question is "which beds, and who has the others".
class _BedSheet extends ConsumerWidget {
  const _BedSheet({required this.room});
  final RoomOccupancy room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final beds = ref.watch(bedsInRoomProvider(room.roomId));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Room ${room.roomNumber}', style: t.textTheme.titleLarge),
        // EDIT LIVES HERE, not on the tile. The tile's tap already means "show me this room",
        // and re-pointing an established gesture at a write is how people change something
        // they only meant to look at.
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              final changed = await showEditRoomSheet(
                context,
                roomId: room.roomId,
                roomNumber: room.roomNumber,
                capacity: room.capacity,
                occupied: room.occupied,
                floorNumber: room.floorNumber,
              );
              if (!changed || !context.mounted) return;
              // Capacity changes add or remove bed rows server-side, so BOTH the grid and this
              // room's beds are stale — see RoomRepository.updateRoom.
              // The whole family, not one key: RoomOccupancy carries no hostel id, and a
              // room edit is rare enough that refetching every open grid costs nothing.
              ref.invalidate(roomOccupancyProvider);
              ref.invalidate(bedsInRoomProvider(room.roomId));
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.edit_outlined, size: IconSize.sm),
            label: const Text('Edit room'),
          ),
        ),
        Text(
          'Floor ${room.floorNumber} · ${room.occupied} of ${room.capacity} beds taken',
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: Space.md),
        whenAsync(
          beds,
          loading: () => const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Skeleton(widthFactor: 0.65),
              SizedBox(height: Space.sm),
              Skeleton(widthFactor: 0.5),
            ],
          ),
          error: (error) => ErrorNote(
            error: error,
            onRetry: () => ref.invalidate(bedsInRoomProvider(room.roomId)),
          ),
          data: (list) => list.isEmpty
              ? const EmptyNote(
                  icon: Icons.bed_outlined,
                  title: 'No beds in this room',
                  message: 'Capacity is set per room; the beds are created with it.',
                  compact: true,
                )
              : Column(
                  children: [
                    for (final bed in list) _BedRow(bed: bed),
                  ],
                ),
        ),
      ],
    );
  }
}

class _BedRow extends ConsumerWidget {
  const _BedRow({required this.bed});
  final Bed bed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final studentId = bed.studentId;

    // The occupant's name is a second read, and only for beds that have one. Resolving every
    // bed in the building up front would be a query per bed for information nobody has asked
    // to see yet; here the sheet is open and the question has been asked.
    final name = studentId == null
        ? null
        : ref.watch(studentProvider(studentId)).value?.fullName;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          Icon(
            bed.isFree ? Icons.bed_outlined : Icons.person_rounded,
            size: IconSize.md,
            color: bed.isFree ? context.tones.success : t.colorScheme.outline,
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text('Bed ${bed.bedNumber}', style: t.textTheme.titleMedium),
          ),
          if (bed.isFree)
            const StatusChip(label: 'Free', tone: NivoraColors.success)
          else if (name != null)
            Flexible(
              child: Text(name,
                  style: t.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          else
            // Occupied, name still in flight — or hidden from this caller by RLS. Either way
            // the bed is taken, and saying so is more honest than an empty gap.
            Text(bed.status.label, style: t.textTheme.bodySmall),
        ],
      ),
    );
  }
}
