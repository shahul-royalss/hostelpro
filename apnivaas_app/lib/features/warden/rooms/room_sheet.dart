library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../../../shared/rooms/edit_room_sheet.dart';
import '../actions/assign_bed_sheet.dart';
import '../actions/sheet_scaffold.dart';
import '../data/warden_providers.dart';
import '../students/student_sheet.dart';
import '../widgets/warden_ui.dart';

/// One room, bed by bed.
///
/// THE GRID SHOWS A COUNT; THIS SHOWS THE BEDS. rpc_room_occupancy returns capacity and an
/// occupied count — enough to draw a building at a glance, and deliberately not enough to say
/// WHICH bed is free. That answer comes from public.beds, one query per room the warden opens,
/// which is also the only place beds.student_id is readable. Drawing named beds from a count
/// would mean inventing the mapping, and a warden who walks to bed 2 because the app said so
/// and finds someone asleep in it stops trusting the app.
///
/// The occupant's NAME is not on the bed row either — beds carries a student_id and nothing
/// else — so the residents of the room are fetched alongside and matched by bed. Both queries
/// are RLS-scoped: a manager opening this would get neither.
Future<void> showRoomSheet(
  BuildContext context, {
  required String roomId,
  required String roomNumber,
  required int floorNumber,
  required int capacity,
  required int occupied,
}) {
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _RoomSheet(
      roomId: roomId,
      roomNumber: roomNumber,
      floorNumber: floorNumber,
      capacity: capacity,
      occupied: occupied,
    ),
  );
}

class _RoomSheet extends ConsumerWidget {
  const _RoomSheet({
    required this.roomId,
    required this.roomNumber,
    required this.floorNumber,
    required this.capacity,
    required this.occupied,
  });

  final String roomId;
  final String roomNumber;
  final int floorNumber;
  final int capacity;
  final int occupied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final beds = ref.watch(bedsInRoomProvider(roomId));
    final residents = ref.watch(studentsInRoomProvider(roomId));

    return SheetBody(
      title: 'Room $roomNumber',
      subtitle: 'Floor $floorNumber',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The RLS admits the warden AND the owner to rooms_update (widened 2026-09-02; it
          // used to admit only the warden, while this sheet told the warden the opposite).
          // The person standing in the corridor when a room is split is usually this one.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final changed = await showEditRoomSheet(
                  context,
                  roomId: roomId,
                  roomNumber: roomNumber,
                  capacity: capacity,
                  occupied: occupied,
                  floorNumber: floorNumber,
                );
                if (!changed || !context.mounted) return;
                ref.invalidate(bedsInRoomProvider(roomId));
                refreshBeds(ref);
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.edit_outlined, size: IconSize.sm),
              label: const Text('Edit room'),
            ),
          ),
          AsyncSection<List<Bed>>(
        value: beds,
        onRetry: () => ref.invalidate(bedsInRoomProvider(roomId)),
        builder: (bedRows) {
          if (bedRows.isEmpty) {
            return const EmptyState(
              icon: Icons.bed_outlined,
              title: 'This room has no beds',
              detail: 'Bed rows follow the room capacity. Use Edit room to change it.',
            );
          }
          // The names are a nicety; the beds are the point. If the resident query is still in
          // flight or failed, the beds still draw — with "Occupied" where a name would be.
          final byBed = <String, Student>{
            for (final s in residents.value ?? const <Student>[])
              if (s.bedId != null) s.bedId!: s,
          };

          final free = bedRows.where((b) => b.isFree).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  StatusPill.text(
                    label: '${bedRows.length - free} of ${bedRows.length} occupied',
                    tone: Theme.of(context).colorScheme.primary,
                    dot: true,
                  ),
                  const SizedBox(width: Space.xs),
                  if (free > 0)
                    StatusPill.text(
                      label: '$free free',
                      tone: context.tones.success,
                      dot: true,
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              const SectionLabel(label: 'Beds'),
              for (final bed in bedRows)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: _BedRow(
                    bed: bed,
                    roomNumber: roomNumber,
                    occupant: bed.studentId == null ? null : byBed[bed.id],
                  ),
                ),
              const SizedBox(height: Space.md),
              InfoCallout(
                icon: Icons.info_outline_rounded,
                child: Text(
                  'Beds are free or occupied — the database has no maintenance state, so this '
                  'screen does not invent one.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
          ),
        ],
      ),
    );
  }
}

/// What can be done to a bed that somebody is in.
enum _BedAction { move, free }

/// One bed, in the shape rooms-beds-directory.png draws a bed row.
///
/// An OCCUPIED bed is a bed badge, the occupant's name, and their check-in date underneath —
/// the mockup's `Rahul Singh / Check-in: 12 Aug`. That date is `students.date_of_joining`, a
/// real column this sheet already has on the row it is drawing; nothing about it is invented.
///
/// A FREE bed is the mockup's inset "Available" row: a violet-edged well, `Ready for
/// assignment` underneath, and a round `+` at the right. The design draws it INSIDE the room
/// card rather than as a peer of the occupied rows, which is what the tone on the surrounding
/// [TapRow] does here.
class _BedRow extends ConsumerWidget {
  const _BedRow({required this.bed, required this.roomNumber, required this.occupant});

  final Bed bed;
  final String roomNumber;

  /// Null when the bed is free, or when the resident row was not readable.
  final Student? occupant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final label = 'Room $roomNumber · Bed ${bed.bedNumber}';

    if (bed.isFree) {
      return TapRow(
        semanticLabel: 'Bed ${bed.bedNumber}, free',
        tone: t.colorScheme.primary,
        onTap: () => showFillBedSheet(context, ref, bed: bed, bedLabel: label),
        child: Row(
          children: [
            _BedChip(number: bed.bedNumber, tone: context.tones.success, filled: false),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Available', style: t.textTheme.titleMedium),
                  Text('Bed ${bed.bedNumber} · ready for assignment',
                      style: t.textTheme.bodySmall,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            // The mockup's round `+`: a filled violet disc at the right edge of an available
            // bed. IconButton.filled gives it the 48dp target a warden needs; the design's own
            // circle is smaller than anything you can hit standing up.
            IconButton.filled(
              tooltip: 'Assign this bed',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => showFillBedSheet(context, ref, bed: bed, bedLabel: label),
            ),
          ],
        ),
      );
    }

    final resident = occupant;
    return TapRow(
      semanticLabel: 'Bed ${bed.bedNumber}, occupied by ${resident?.fullName ?? 'a resident'}',
      onTap: resident == null ? null : () => showStudentSheet(context, studentId: resident.id),
      child: Row(
        children: [
          _BedChip(number: bed.bedNumber, tone: t.colorScheme.primary, filled: true),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resident?.fullName ?? 'Occupied',
                  style: t.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  // The mockup's second line under an occupant is their check-in date. Where
                  // the resident row was not readable there is no date either, so the bed says
                  // only what it knows.
                  resident == null
                      ? 'Bed ${bed.bedNumber}'
                      : 'Check-in ${shortDate(resident.dateOfJoining)}',
                  style: t.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (resident != null)
            // MOVE and FREE are different actions and neither is a check-out. Moving keeps the
            // resident in the building; freeing the bed keeps them on the roster and on the fee
            // ledger with nowhere to sleep, which is the true state while a room is repainted.
            // Check-out is the third thing, and it lives on the resident's own sheet where the
            // consequences can be spelled out.
            PopupMenuButton<_BedAction>(
              tooltip: 'Bed actions',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) => switch (action) {
                _BedAction.move => showAssignBedSheet(context, ref, student: resident),
                _BedAction.free => showReleaseBedSheet(context, ref, student: resident),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _BedAction.move,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.swap_horiz_rounded),
                    title: Text('Move to another bed'),
                  ),
                ),
                PopupMenuItem(
                  value: _BedAction.free,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.bed_outlined),
                    title: Text('Free this bed'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The bed number as a square tile — filled when someone is in it, outlined when it is free.
///
/// Shape carries the meaning as well as colour, so the grid still reads for someone who cannot
/// distinguish the two hues.
class _BedChip extends StatelessWidget {
  const _BedChip({required this.number, required this.tone, required this.filled});
  final int number;
  final Color tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Filled and hollow are the same chip drawn two ways: one has the tint, the other has
    // the edge. Both alphas come from the measured recipe rather than from 0.14 and 0.5,
    // which were two numbers nobody could re-derive.
    return Container(
      width: Space.xxxl,
      height: Space.xxxl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? context.tones.chipFill(tone) : null,
        borderRadius: Radii.rControl,
        border: filled ? null : Border.all(color: tone, width: Strokes.hairline),
      ),
      child: Text('$number', style: t.textTheme.titleSmall?.copyWith(color: tone)),
    );
  }
}
