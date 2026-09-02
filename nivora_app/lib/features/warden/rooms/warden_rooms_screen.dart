library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../common/refresh.dart';
import '../../../shared/glass/glass.dart';
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
/// repair is not something this schema can express. The superseded Stitch directory drew a
/// MAINTENANCE figure on its summary card and an "Under Repair" bed row underneath; both are
/// omitted here rather than drawn as a zero, because a zero would read as "nothing is broken"
/// and that is a claim the database cannot make. The summary and the pips name two states and
/// mean them.
///
/// THE LEGEND IS GONE AND THE SUMMARY REPLACED IT. The hero card labels each figure with its
/// own dot in the very colours the pips below are painted, so the figures ARE the key. A
/// separate legend strip repeated the same two swatches a centimetre lower.
///
/// ── ON THE FIGMA FRAME FOR THIS SCREEN ───────────────────────────────────────────────────
///
/// `screen-warden-room-management` is node 4:821. It could not be read while this restyle was
/// made — the Figma MCP account hit its plan's tool-call ceiling after `screen-warden-dashboard`
/// (4:640) and `screen-warden-students-list` (4:723). So this screen is built from the shared
/// language those two DO pin down and the file's own tokens: the 56dp header with its brand
/// dot, uppercase section headings, the card fill behind a hairline at the 8 corner, the 4px
/// state badge, and 16/700 cream card titles. Anything the frame specifies beyond that —
/// most likely a floor filter across the top, since 4:660 puts one on the dashboard — is NOT
/// implemented here and should be checked against 4:821 by whoever next has quota.
class WardenRoomsScreen extends ConsumerWidget {
  const WardenRoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);
    if (hostelId == null) {
      return const WardenScreen(
        title: 'Rooms & beds',
        child: EmptyState(
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
          // Same reason as the empty state above: a small building fits on one screen, and
          // content that fits over-scrolls only because a controller-less vertical list is
          // `primary`. Stated, so adding a ScrollController here cannot silently kill the pull.
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _BuildingSummary(rooms: rooms),
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

/// The building in four figures — rooms-beds-directory.png's hero card.
///
/// The mockup runs TOTAL BEDS / OCCUPIED / FREE / MAINTENANCE as a two-by-two of `label-caps`
/// eyebrows over `headline-lg` figures, each eyebrow marked with its state's dot, and it is the
/// first thing on the screen. Three of those four are figures this app has.
///
/// THE FOURTH IS NOT BUILT AND IS NOT FAKED. public.bed_status is exactly ('free','occupied');
/// a bed under repair is not a state this schema can hold, so the MAINTENANCE cell is absent
/// rather than drawn as a zero. A zero would read as "nothing is broken", which is a claim the
/// database cannot make.
///
/// Every figure is folded from the very list the grid below is drawing, so the card and the
/// tiles cannot drift apart.
class _BuildingSummary extends StatelessWidget {
  const _BuildingSummary({required this.rooms});
  final List<RoomOccupancy> rooms;

  @override
  Widget build(BuildContext context) {
    final beds = rooms.fold<int>(0, (sum, r) => sum + r.capacity);
    final taken = rooms.fold<int>(0, (sum, r) => sum + r.occupied);

    return GlassCard(
      padding: const EdgeInsets.all(Space.md),
      semanticLabel: '$beds beds, $taken occupied, ${beds - taken} free',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _Figure(label: 'Total beds', value: '$beds')),
              Expanded(
                child: _Figure(
                  label: 'Occupied',
                  value: '$taken',
                  tone: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Free',
                  value: '${beds - taken}',
                  tone: NivoraColors.success,
                ),
              ),
              Expanded(child: _Figure(label: 'Rooms', value: '${rooms.length}')),
            ],
          ),
        ],
      ),
    );
  }
}

/// One cell of the summary: a dotted `label-caps` eyebrow over a `headline-lg` figure.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.tone});
  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? null : context.tones.resolve(tone!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CapsLabel(label, tone: accent, dot: accent != null),
        const SizedBox(height: Space.xxs),
        Text(
          value,
          style: t.textTheme.headlineMedium?.copyWith(color: accent),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _FloorSummary extends StatelessWidget {
  const _FloorSummary({required this.rooms});
  final List<RoomOccupancy> rooms;

  @override
  Widget build(BuildContext context) {
    final free = rooms.fold<int>(0, (sum, r) => sum + r.free);
    return CapsLabel(
      free == 0 ? 'full' : '$free free',
      tone: free == 0 ? null : NivoraColors.success,
      dot: free != 0,
    );
  }
}

/// One room. Big enough to hit without aiming: the whole tile is the target.
///
/// rooms-beds-directory.png heads each room card with the room number in `primary` and a
/// `label-caps` bed count on the right; that pairing is what this tile borrows. The pips stay,
/// because the mockup's per-bed rows need a bed-to-person mapping the grid's RPC does not
/// return — see the note on [WardenRoomsScreen]. Tapping through to the room sheet is where
/// that mapping exists.
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
        borderRadius: Radii.rControl,
        child: InkWell(
          borderRadius: Radii.rControl,
          onTap: () => showRoomSheet(
            context,
            roomId: room.roomId,
            roomNumber: room.roomNumber,
            floorNumber: room.floorNumber,
            capacity: room.capacity,
            occupied: room.occupied,
          ),
          child: Container(
            // Scaled with its own text. A fixed 116 was sized against 1.0x type; at 1.4x the
            // room number, the pips and the "3 free" line together overran it.
            height: MediaQuery.textScalerOf(context).scale(_tileHeight),
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              // A grid tile is one of the file's SMALL cards, so it takes the 8 corner its
              // list rows take rather than a full card's 12.
              borderRadius: Radii.rControl,
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        room.roomNumber,
                        // Cream at 16/700, which is what every card title in the Figma file
                        // is. It used to be 20/700 in the gold: that is the accent this design
                        // spends on ONE thing per screen, and twelve gold room numbers in a
                        // grid leave the free-bed count — the answer the screen exists to
                        // give — with nothing louder than itself.
                        style: t.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // `2 BEDS`, exactly as the mockup labels each room card.
                    CapsLabel('${room.capacity} beds'),
                  ],
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
