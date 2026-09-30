library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';
import 'staff_models.dart';
import 'staff_providers.dart';

/// Which of the owner's PGs one warden or manager may work in.
///
/// ── WHAT THIS IS FOR ─────────────────────────────────────────────────────────────────────
///
/// An owner with two buildings and one warden who looks after both used to need two logins
/// for that one person. Now the warden has one login and ACCESS to both, works in one at a
/// time, and switches from the app. This sheet is where the owner decides which PGs that is:
/// one checkbox per PG they own, saved with `public.owner_set_staff_hostels`.
///
/// ── WHAT IT DECIDES, AND WHAT IT DOES NOT ────────────────────────────────────────────────
///
/// It decides what to DRAW, including the one rule it enforces before the round trip: at least
/// one PG stays ticked. A staff account with no PG would be a login that opens onto nothing,
/// and the RPC refuses an empty list anyway ('Choose at least one PG.'). Everything else is
/// the server's: that the owner owns every PG ticked, that this person is theirs, and that a
/// PG being added still has room under the five-per-role limit.
///
/// DEACTIVATING IS NOT HERE. That stays on the staff card and stays account-wide. Taking one
/// PG away is this sheet; taking the person's access away altogether is Deactivate, and the
/// two confirmations say which is which.
///
/// Returns the saved grants, or null when nothing was saved.
Future<List<StaffHostelGrant>?> showStaffAccessSheet(
  BuildContext context, {
  required StaffMember member,
  required List<Hostel> owned,
}) {
  return showGlassSheet<List<StaffHostelGrant>>(
    context: context,
    builder: (_) => StaffAccessSheet(member: member, owned: owned),
  );
}

/// PUBLIC so owner_staff_test.dart can pump it on its own and hold the one-PG rule down.
class StaffAccessSheet extends ConsumerStatefulWidget {
  const StaffAccessSheet({super.key, required this.member, required this.owned});

  final StaffMember member;

  /// Every PG this owner holds, by name: the order `myHostelsProvider` asks the server for,
  /// and the order the RPC uses to pick a new active PG when the current one is removed.
  final List<Hostel> owned;

  @override
  ConsumerState<StaffAccessSheet> createState() => _StaffAccessSheetState();
}

class _StaffAccessSheetState extends ConsumerState<StaffAccessSheet> {
  late Set<String> _selected = _initial();
  bool _busy = false;
  bool _keepOne = false;
  String? _error;

  /// What the server says they hold, narrowed to PGs on the owner's list. The RPC already
  /// restricts `hostel_ids` to the caller's own PGs; narrowing again only keeps a checkbox from
  /// being ticked for a PG this sheet cannot draw.
  Set<String> _initial() {
    final owned = {for (final h in widget.owned) h.id};
    return {
      for (final id in widget.member.hostelIds)
        if (owned.contains(id)) id,
    };
  }

  bool get _changed {
    final before = _initial();
    return before.length != _selected.length || !before.containsAll(_selected);
  }

  /// The ticked PGs in the owner's name order. The RPC treats the list as a set; the order is
  /// only so the request reads the same way twice.
  List<String> get _ordered => [
    for (final h in widget.owned)
      if (_selected.contains(h.id)) h.id,
  ];

  void _toggle(String hostelId) {
    if (_busy) return;
    setState(() {
      _error = null;
      if (!_selected.contains(hostelId)) {
        _selected = {..._selected, hostelId};
        _keepOne = false;
      } else if (_selected.length == 1) {
        // The last one stays. Said rather than silently ignored, so the tap does not read as a
        // broken checkbox.
        _keepOne = true;
      } else {
        _selected = {..._selected}..remove(hostelId);
        _keepOne = false;
      }
    });
  }

  Future<void> _save() async {
    if (_busy || _selected.isEmpty || !_changed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final grants = await ref
          .read(ownerStaffWritesProvider)
          .setStaffHostels(userId: widget.member.id, hostelIds: _ordered);
      // The WHOLE family, not the PG on screen: this person has just appeared in, or vanished
      // from, the lists of every PG that was ticked or unticked.
      ref.invalidate(ownerStaffProvider);
      if (!mounted) return;
      Navigator.of(context).pop(grants);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppFailure.from(error).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final member = widget.member;
    final media = MediaQuery.of(context);
    final active = member.activeHostelId;

    // Where they would land if the PG they are working in is unticked: the RPC moves them to
    // the first remaining PG by name, and the owner should know that before saving, not after.
    String? movesTo;
    if (active != null && !_selected.contains(active)) {
      for (final h in widget.owned) {
        if (_selected.contains(h.id)) {
          movesTo = h.name;
          break;
        }
      }
    }
    String? activeName = member.activeHostelName;
    for (final h in widget.owned) {
      if (h.id == active) activeName = h.name;
    }

    return PopScope(
      canPop: !_busy,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.88 - media.padding.top),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'PG ACCESS',
                style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.primary),
              ),
              const SizedBox(height: Space.xxs / 2),
              Text(
                member.fullName,
                style: t.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Space.xxs),
              Text(
                'Choose the PGs this ${member.role.label.toLowerCase()} can work in. They work '
                'in one at a time and switch between them in the app.',
                style: t.textTheme.bodySmall,
              ),
              const SizedBox(height: Space.md),
              StaffPgChecklist(
                hostels: widget.owned,
                selected: _selected,
                enabled: !_busy,
                workingIn: active,
                onToggle: _toggle,
              ),
              if (_keepOne) ...[
                const SizedBox(height: Space.xs),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Keep at least one PG. To take away all access, deactivate them instead.',
                    style: t.textTheme.bodySmall,
                  ),
                ),
              ],
              if (movesTo != null) ...[
                const SizedBox(height: Space.sm),
                _Note(
                  // A deactivated member is working nowhere, so the sentence names the PG they
                  // would come back to instead of claiming they are in it now.
                  text: !member.isActive
                      ? 'If reactivated, they will start in $movesTo.'
                      : activeName == null
                      ? 'The PG they are working in is being removed. Saving moves them to '
                            '$movesTo.'
                      : 'They are working in $activeName now. Saving moves them to $movesTo.',
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: Space.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: t.textTheme.bodyMedium?.copyWith(color: context.tones.error),
                  ),
                ),
              ],
              const SizedBox(height: Space.md),
              FilledButton(
                // Dark until something changed: saving the list it already has would spend a
                // round trip to be told nothing happened.
                onPressed: _busy || !_changed ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                child: _busy
                    ? const SizedBox(
                        height: IconSize.md,
                        width: IconSize.md,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save PG access'),
              ),
              const SizedBox(height: Space.xs),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The owner's PGs as checkboxes. Shared by this sheet and the add-staff sheet, so choosing
/// PGs for a new account and changing them for an existing one are the same control.
///
/// It does not decide the at-least-one rule; it reports every tap through [onToggle] and the
/// sheet that owns the selection decides what a tap on the last ticked box means.
class StaffPgChecklist extends StatelessWidget {
  const StaffPgChecklist({
    super.key,
    required this.hostels,
    required this.selected,
    required this.enabled,
    required this.onToggle,
    this.workingIn,
  });

  final List<Hostel> hostels;
  final Set<String> selected;
  final bool enabled;
  final ValueChanged<String> onToggle;

  /// The PG the person is working in now, marked so the owner can see what unticking it
  /// means. Null on the add sheet, where nobody is working anywhere yet.
  final String? workingIn;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FlatSurface(
      weight: GlassWeight.regular,
      borderRadius: Radii.rControl,
      padding: const EdgeInsets.symmetric(vertical: Space.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final h in hostels)
            CheckboxListTile(
              value: selected.contains(h.id),
              onChanged: enabled ? (_) => onToggle(h.id) : null,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.xs),
              title: Text(
                h.name,
                style: t.textTheme.bodyLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: h.id == workingIn
                  ? Text('Working here now', style: t.textTheme.bodySmall)
                  : (h.address?.trim().isNotEmpty ?? false)
                  ? Text(
                      h.address!.trim(),
                      style: t.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

/// A quiet fact about what saving will do. The info tone, because nothing is wrong.
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: tones.chipFill(NivoraColors.info),
        borderRadius: Radii.rControl,
        border: Border.all(color: tones.chipBorder(NivoraColors.info), width: Strokes.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: IconSize.sm, color: tones.info),
          const SizedBox(width: Space.xs),
          Expanded(child: Text(text, style: t.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
