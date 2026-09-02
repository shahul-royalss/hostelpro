library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../glass/glass.dart';

/// RENAMING A ROOM AND CHANGING HOW MANY BEDS ARE IN IT.
///
/// Shared by the owner and the warden deliberately, because the database now permits both and
/// the question they are answering is the same one. It lives in shared/ rather than in either
/// feature so the two cannot drift into disagreeing about what a room is.
///
/// ── WHY THIS DID NOT EXIST ────────────────────────────────────────────────────────────────
///
/// RoomRepository.updateRoom() has been in the codebase the whole time with ZERO callers, and
/// the RLS admitted only the warden while warden/rooms/room_sheet.dart told the warden that
/// capacity is "which only the owner can change". Both halves were wrong in opposite
/// directions, and the net effect was that nobody could rename a room at all.
///
/// ── CHANGING CAPACITY IS NOT CHANGING A NUMBER ───────────────────────────────────────────
///
/// app.rooms_capacity_sync adds bed rows when the count goes up and removes FREE beds when it
/// goes down, refusing to strip a bed somebody is sleeping in. So lowering capacity below the
/// number of residents already placed is REFUSED BY THE SERVER, and this sheet says so before
/// the tap rather than after it — the occupied count is right there.
Future<bool> showEditRoomSheet(
  BuildContext context, {
  required String roomId,
  required String roomNumber,
  required int capacity,
  required int occupied,
  required int floorNumber,
}) async {
  final changed = await showGlassSheet<bool>(
    context: context,
    builder: (_) => _EditRoom(
      roomId: roomId,
      roomNumber: roomNumber,
      capacity: capacity,
      occupied: occupied,
      floorNumber: floorNumber,
    ),
  );
  return changed ?? false;
}

class _EditRoom extends ConsumerStatefulWidget {
  const _EditRoom({
    required this.roomId,
    required this.roomNumber,
    required this.capacity,
    required this.occupied,
    required this.floorNumber,
  });

  final String roomId;
  final String roomNumber;
  final int capacity;
  final int occupied;
  final int floorNumber;

  @override
  ConsumerState<_EditRoom> createState() => _EditRoomState();
}

class _EditRoomState extends ConsumerState<_EditRoom> {
  late final TextEditingController _number =
      TextEditingController(text: widget.roomNumber);
  late int _capacity = widget.capacity;
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  /// The floor's own prefix, offered as a shortcut rather than imposed.
  ///
  /// The scaffolding names rooms 101, 102 … 201, 202 — floor number then a sequence — and that
  /// is a convention, not a rule. A PG that calls its rooms "A", "Annexe 2" or simply "1" is
  /// not doing anything wrong, and the column is text precisely so it can. This button offers
  /// the house style in one tap and never enforces it.
  String get _suggested => '${widget.floorNumber}01';

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_formKey.currentState?.validate() != true) return;
    final name = _number.text.trim();
    if (name == widget.roomNumber && _capacity == widget.capacity) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(roomRepositoryProvider).updateRoom(
            roomId: widget.roomId,
            roomNumber: name == widget.roomNumber ? null : name,
            capacity: _capacity == widget.capacity ? null : _capacity,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (e) {
      if (mounted) setState(() => _error = AppFailure.from(e).message);
    } finally {
      // A `finally`, so no failure path can leave the button disabled with nothing said.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final error = _error;
    // Never below the number of people already sleeping there: the server refuses it, and a
    // control that offers a value the server will reject is a trap.
    final floor = widget.occupied < 1 ? 1 : widget.occupied;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit room', style: t.textTheme.titleLarge),
          const SizedBox(height: Space.xxs),
          Text('Floor ${widget.floorNumber} · ${widget.occupied} of ${widget.capacity} beds taken',
              style: t.textTheme.bodySmall),
          const SizedBox(height: Space.md),

          TextFormField(
            controller: _number,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [LengthLimitingTextInputFormatter(16)],
            decoration: InputDecoration(
              labelText: 'Room name or number',
              helperText: 'Anything your residents will recognise.',
              suffixIcon: TextButton(
                onPressed: _busy ? null : () => _number.text = _suggested,
                child: Text(_suggested),
              ),
            ),
            validator: (raw) {
              final v = (raw ?? '').trim();
              if (v.isEmpty) return 'Give the room a name';
              return null;
            },
          ),
          const SizedBox(height: Space.md),

          Text('Beds in this room', style: t.textTheme.bodyMedium),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              IconButton.outlined(
                onPressed: _busy || _capacity <= floor
                    ? null
                    : () => setState(() => _capacity--),
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Text('$_capacity',
                    textAlign: TextAlign.center, style: t.textTheme.headlineMedium),
              ),
              IconButton.outlined(
                onPressed: _busy || _capacity >= 12
                    ? null
                    : () => setState(() => _capacity++),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          if (_capacity != widget.capacity) ...[
            const SizedBox(height: Space.xs),
            Text(
              _capacity > widget.capacity
                  ? 'Adding ${_capacity - widget.capacity} empty bed(s).'
                  // Only free beds are removed, and the stepper cannot go below the occupied
                  // count, so this can never mean "somebody loses their bed".
                  : 'Removing ${widget.capacity - _capacity} empty bed(s).',
              style: t.textTheme.bodySmall,
            ),
          ],
          if (widget.occupied > 0 && _capacity == floor) ...[
            const SizedBox(height: Space.xxs),
            Text(
              'This is as low as it goes — ${widget.occupied} bed(s) are occupied. Move those '
              'residents first.',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
            ),
          ],

          if (error != null) ...[
            const SizedBox(height: Space.sm),
            Semantics(
              liveRegion: true,
              child: Text(error,
                  style: t.textTheme.bodyMedium?.copyWith(color: context.tones.error)),
            ),
          ],

          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? SizedBox.square(
                    dimension: IconSize.md,
                    child: CircularProgressIndicator(
                        strokeWidth: Strokes.glyph, color: t.colorScheme.onPrimary),
                  )
                : const Text('Save changes'),
          ),
          const SizedBox(height: Space.xs),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
