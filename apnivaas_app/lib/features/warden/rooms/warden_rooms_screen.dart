library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../common/refresh.dart';
import '../../../shared/clay/clay.dart' show ClayIcon, ClayIcons, StatusChip, StatusTone;
import '../../../shared/glass/glass.dart';
import '../widgets/warden_ui.dart';
import '../../owner/rooms/floor_plan_screen.dart';
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
/// repair is not something this schema can express. The superseded Stitch directory drew a
/// MAINTENANCE figure on its summary card and an "Under Repair" bed row underneath; both are
/// omitted here rather than drawn as a zero, because a zero would read as "nothing is broken"
/// and that is a claim the database cannot make. The summary and the pips name two states and
/// mean them.
///
/// THE SUMMARY IS THE LEGEND. The card at the top labels its figures with dots in the very
/// colours the pips below are painted — forest for a bed that is taken, the free tint for one
/// that is not — so the figures ARE the key, and no separate legend strip repeats the same two
/// swatches a centimetre lower.
class WardenRoomsScreen extends ConsumerWidget {
  const WardenRoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);
    if (hostelId == null) {
      return const WardenScreen(
        title: 'Rooms & beds',
        child: WardenEmptyState(
          icon: Icons.apartment_rounded,
          title: 'No hostel on this account',
          detail: 'A warden is attached to one hostel. Ask the owner to check the assignment.',
        ),
      );
    }

    final occupancy = ref.watch(roomOccupancyProvider(hostelId));

    return WardenScreen(
      // The building's figures used to be a sentence in this bar. They are now the mockup's
      // hero card at the top of the grid (_BuildingSummary) — same fold over the same list, so
      // the summary still cannot disagree with the tiles beneath it.
      title: 'Rooms & beds',
      actions: [
        // THE WARDEN EDITS THE LAYOUT TOO, as of 2026-09-12. The product owner: "like how admin
        // can edit layout same as like that warden also can have edit layout option."
        // public.ow_set_floor_plan admits an active warden of this hostel now
        // (app.can_edit_layout), and this grid is the screen a warden is standing on when a
        // floor is split or a room is added. The owner reaches the same editor from the PG
        // detail card.
        HeaderAction(
          tooltip: 'Edit layout',
          icon: Icons.dashboard_customize_outlined,
          onPressed: () => Navigator.of(context).push(FloorPlanScreen.route(hostelId)),
        ),
      ],
      child: RefreshIndicator(
        // The grid is the one screen a warden pulls standing in a stairwell, which is also
        // where the signal goes. Bounded and spoken — see features/common/refresh.dart.
        onRefresh: () {
          ref.invalidate(roomOccupancyProvider(hostelId));
          return settleRefresh(context, () => ref.read(roomOccupancyProvider(hostelId).future));
        },
        child: AsyncSection<List<RoomOccupancy>>(
          value: occupancy,
          onRetry: () => ref.invalidate(roomOccupancyProvider(hostelId)),
          builder: (list) {
            if (list.isEmpty) {
              return ListView(
                // Named rather than inherited from ScrollView's `primary` inference, which
                // holds only while this list has no controller of its own. A hostel showing
                // no rooms is precisely when a warden pulls, so the gesture must not depend
                // on a default nothing in this file mentions.
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  WardenEmptyState(
                    icon: Icons.meeting_room_outlined,
                    art: ClayIcons.rooms,
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
          // Same reason as the empty state above: a small building fits on one screen, and
          // content that fits over-scrolls only because a controller-less vertical list is
          // `primary`. Stated, so adding a ScrollController here cannot silently kill the pull.
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _BuildingSummary(rooms: rooms),
            for (final entry in floors.entries) ...[
              SectionLabel(
                // What the PG calls this storey, falling back to "Floor N" for the great
                // majority that have never been named. rpc_room_occupancy carries the name on
                // every room of the floor, so the first room's copy is the floor's.
                label: floorLabel(entry.key, entry.value.first.floorName),
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

/// The building at a glance: how many beds are free, how full that makes it, and the four
/// figures underneath — total, occupied, free, rooms.
///
/// The free beds lead, in words and beside the clay bed, because "where is there a bed" is the
/// question the screen exists for; the meter under them is the same split in the pips' own two
/// colours. Every figure is folded from the very list the grid below is drawing, so the card and
/// the tiles cannot drift apart.
///
/// THERE IS NO MAINTENANCE FIGURE AND IT IS NOT FAKED. public.bed_status is exactly
/// ('free','occupied'); a bed under repair is not a state this schema can hold, so the figure is
/// absent rather than drawn as a zero. A zero would read as "nothing is broken", which is a
/// claim the database cannot make.
class _BuildingSummary extends StatelessWidget {
  const _BuildingSummary({required this.rooms});
  final List<RoomOccupancy> rooms;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final beds = rooms.fold<int>(0, (sum, r) => sum + r.capacity);
    final taken = rooms.fold<int>(0, (sum, r) => sum + r.occupied);
    final free = beds - taken;
    final scale = MediaQuery.textScalerOf(context).scale(1);

    return GlassCard(
      padding: const EdgeInsets.all(Space.md),
      semanticLabel: '$beds beds, $taken occupied, $free free',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const ClayIcon(ClayIcons.beds, size: ClaySize.tile),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      beds == 0
                          ? 'No beds set up yet'
                          : free == 0
                              ? 'Every bed is taken'
                              : '${countOf(free, 'bed')} free',
                      style: context.textRoles.tileTitle,
                    ),
                    if (beds > 0)
                      Text(
                        '${(taken / beds * 100).round()}% of the building is full',
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (beds > 0) ...[
            const SizedBox(height: Space.sm),
            _Meter(taken: taken, beds: beds),
          ],
          const SizedBox(height: Space.md),
          Divider(height: Strokes.hairline, color: t.colorScheme.outlineVariant),
          const SizedBox(height: Space.sm),
          LayoutBuilder(
            builder: (context, box) {
              // Four across while the labels fit on one line; two by two on a narrow phone or
              // with large text, rather than four squeezed figures.
              final columns = box.maxWidth >= 300 && scale < 1.3 ? 4 : 2;
              final cell = (box.maxWidth - Space.xs * (columns - 1)) / columns;
              return Wrap(
                spacing: Space.xs,
                runSpacing: Space.sm,
                children: [
                  for (final figure in [
                    _Figure(label: 'Total beds', value: '$beds'),
                    _Figure(label: 'Occupied', value: '$taken', dot: t.colorScheme.primary),
                    _Figure(label: 'Free', value: '$free', dot: context.tones.success),
                    _Figure(label: 'Rooms', value: '${rooms.length}'),
                  ])
                    SizedBox(width: cell, child: figure),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The building's split as one bar: forest for the beds that are taken, the free tint for the
/// rest — the pips' own two colours, so the bar reads as all the pips laid end to end.
class _Meter extends StatelessWidget {
  const _Meter({required this.taken, required this.beds});
  final int taken;
  final int beds;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: Radii.rPill,
        child: SizedBox(
          height: Space.xs,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: context.tones.chipFill(context.tones.success)),
              ),
              FractionallySizedBox(
                widthFactor: beds == 0 ? 0 : (taken / beds).clamp(0.0, 1.0),
                heightFactor: 1,
                alignment: AlignmentDirectional.centerStart,
                child: ColoredBox(color: t.colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One figure of the summary: the number, and under it what it counts — with the dot of its
/// state where it has one.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.dot});
  final String label;
  final String value;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: t.textTheme.headlineMedium, maxLines: 1),
        Row(
          children: [
            if (dot != null) ...[
              ToneDot(tone: dot!, size: Space.tight),
              const SizedBox(width: Space.xxs),
            ],
            Flexible(
              child: Text(
                label,
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A floor's free beds, opposite its heading — the chip a whole storey earns.
class _FloorSummary extends StatelessWidget {
  const _FloorSummary({required this.rooms});
  final List<RoomOccupancy> rooms;

  @override
  Widget build(BuildContext context) {
    final free = rooms.fold<int>(0, (sum, r) => sum + r.free);
    return free == 0
        ? const StatusChip(label: 'Floor full')
        : StatusChip(label: '$free free', tone: StatusTone.success, dot: true);
  }
}

/// One room. Big enough to hit without aiming: the whole tile is the target.
///
/// The room number heads the tile with its bed count opposite, the pips under them, and the
/// answer at the foot — "2 free" in the free ink, or "Full" in the quiet one. A room with space
/// is edged in the free tint, so it says so before you read it. The pips stay, because per-bed
/// rows need a bed-to-person mapping the grid's RPC does not return — see the note on
/// [WardenRoomsScreen]. Tapping through to the room sheet is where that mapping exists.
class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room});
  final RoomOccupancy room;

  /// The tile's height at 1.0x text. It scales with the text, so the number, the pips and the
  /// free line never overrun it.
  static const _tileHeight = 112.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final full = room.isFull;
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);

    return Semantics(
      button: true,
      label: 'Room ${room.roomNumber}, ${room.occupied} of ${room.capacity} beds occupied',
      excludeSemantics: true,
      child: Material(
        color: t.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rCard,
          side: BorderSide(
            color: full ? t.colorScheme.outlineVariant : tones.chipBorder(tones.success),
            width: Strokes.hairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showRoomSheet(
            context,
            roomId: room.roomId,
            roomNumber: room.roomNumber,
            floorNumber: room.floorNumber,
            capacity: room.capacity,
            occupied: room.occupied,
          ),
          child: Container(
            height: MediaQuery.textScalerOf(context).scale(_tileHeight),
            padding: const EdgeInsets.all(Space.sm + Space.hair),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        room.roomNumber,
                        style: context.textRoles.tileTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Space.xxs),
                    Text(countOf(room.capacity, 'bed'), style: muted),
                  ],
                ),
                _BedPips(capacity: room.capacity, occupied: room.occupied),
                Text(
                  full ? 'Full' : '${room.free} free',
                  style: t.textTheme.labelMedium?.copyWith(
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
