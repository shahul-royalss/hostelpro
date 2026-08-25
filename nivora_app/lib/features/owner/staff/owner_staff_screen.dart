library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';
import '../owner_providers.dart';
import '../widgets/states.dart';
import 'add_staff_sheet.dart';
import 'staff_models.dart';
import 'staff_providers.dart';

/// The manager and the warden who run one PG — who holds each post, and how to change it.
///
/// ── WHY THIS SCREEN EXISTS ───────────────────────────────────────────────────────────────
///
/// Until now an owner could not create a staff login from the app at all. The only route was
/// the web console, which the product owner has ruled out in as many words: "nothing has to go
/// to browser, everything has to be done in the application". So there is no WebView here, no
/// url_launcher, and no "finish this on the website" — [showAddStaffSheet] posts to an Edge
/// Function and the account exists.
///
/// ── THE ONE RULE THAT SHAPES THE LAYOUT ──────────────────────────────────────────────────
///
/// Hard rule §4.3: one active manager and one active warden per hostel. That is why this is two
/// posts with a holder each rather than a list with an Add button — a list implies you can have
/// several, and finding out otherwise from a 409 after typing somebody's details in is a worse
/// way to learn it. `app.enforce_role_limits` and the partial unique index
/// `users_one_active_staff_per_hostel` are what actually enforce it; this screen only draws it.
///
/// READS: public.users (via [ownerStaffProvider], under RLS).
/// WRITES: supabase/functions/owner-create-staff, and a status update on public.users.
class OwnerStaffScreen extends ConsumerWidget {
  const OwnerStaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final hostelId = ref.watch(activeHostelIdProvider);
    final hostelName = _hostelName(ref, hostelId);

    return Scaffold(
      body: Column(
        children: [
          GlassHeader(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('STAFF ACCOUNTS', style: t.textTheme.labelSmall),
                      Text(
                        hostelName ?? 'Your PG',
                        style: t.textTheme.titleLarge,
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
            child: hostelId == null
                ? const _NoHostel()
                : _StaffBody(hostelId: hostelId, hostelName: hostelName),
          ),
        ],
      ),
    );
  }

  /// The name of the PG the switcher is on, if the owner's hostel list has arrived.
  ///
  /// Null while it is still loading, which is why the header falls back to "Your PG" rather
  /// than to an empty string that would make the title jump when the name lands.
  static String? _hostelName(WidgetRef ref, String? hostelId) {
    if (hostelId == null) return null;
    final owned = ref.watch(myHostelsProvider).value;
    if (owned == null) return null;
    for (final h in owned) {
      if (h.id == hostelId) return h.name;
    }
    return null;
  }
}

class _NoHostel extends StatelessWidget {
  const _NoHostel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(Space.md),
      child: EmptyNote(
        icon: Icons.apartment_rounded,
        title: 'No PG selected',
        message: 'Staff accounts belong to a PG. Pick one on the PGs tab first.',
      ),
    );
  }
}

class _StaffBody extends ConsumerWidget {
  const _StaffBody({required this.hostelId, required this.hostelName});

  final String hostelId;
  final String? hostelName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final staff = ref.watch(ownerStaffProvider(hostelId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(ownerStaffProvider(hostelId));
        try {
          await ref.read(ownerStaffProvider(hostelId).future).timeout(ownerRefreshTimeout);
        } catch (_) {
          // Rendered by the body below; rethrowing here would make it unhandled.
        }
      },
      child: whenAsync(
        staff,
        loading: () => ListView(
          padding: const EdgeInsets.all(Space.md),
          children: const [
            SkeletonCard(lines: 3),
            SizedBox(height: Space.md),
            SkeletonCard(lines: 3),
          ],
        ),
        error: (error) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Space.md),
          children: [
            ErrorNote(
              error: error,
              onRetry: () => ref.invalidate(ownerStaffProvider(hostelId)),
            ),
          ],
        ),
        data: (members) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Space.md),
          children: [
            Text(
              'One manager and one warden run a PG. Each gets their own login, and each sees '
              'only their own part of it.',
              style: t.textTheme.bodyMedium,
            ),
            const SizedBox(height: Space.md),
            for (final role in StaffRole.values) ...[
              _RoleSection(
                role: role,
                members: members,
                hostelId: hostelId,
                hostelName: hostelName,
              ),
              const SizedBox(height: Space.md),
            ],
            const _DeactivationNote(),
            const SizedBox(height: Space.xl),
          ],
        ),
      ),
    );
  }
}

/// One post: who holds it, and the two things an owner can do about that.
class _RoleSection extends ConsumerStatefulWidget {
  const _RoleSection({
    required this.role,
    required this.members,
    required this.hostelId,
    required this.hostelName,
  });

  final StaffRole role;
  final List<StaffMember> members;
  final String hostelId;
  final String? hostelName;

  @override
  ConsumerState<_RoleSection> createState() => _RoleSectionState();
}

class _RoleSectionState extends ConsumerState<_RoleSection> {
  bool _busy = false;

  /// Which roles already have an active holder — passed to the sheet so a filled post is drawn
  /// as filled rather than offered and then refused.
  Set<StaffRole> get _taken => {
        for (final role in StaffRole.values)
          if (widget.members.activeIn(role) != null) role,
      };

  Future<void> _add() async {
    final created = await showAddStaffSheet(
      context,
      hostelId: widget.hostelId,
      hostelName: widget.hostelName,
      initialRole: widget.role,
      taken: _taken,
    );
    if (created == true && mounted) {
      // The sheet already invalidated the list; this is here so the section that opened it is
      // certainly showing the new holder even if the sheet's own invalidation was disposed
      // with it.
      ref.invalidate(ownerStaffProvider(widget.hostelId));
    }
  }

  /// Deactivate or reactivate, after a confirmation that says what actually happens.
  Future<void> _setStatus(StaffMember member, StaffStatus to) async {
    if (_busy) return;
    final deactivating = to == StaffStatus.inactive;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(deactivating
            ? 'Deactivate ${member.fullName}?'
            : 'Reactivate ${member.fullName}?'),
        content: Text(
          deactivating
              // Precise on purpose. This is not "sign them out" — see
              // OwnerStaffRepository.setStaffStatus for exactly how much of the session dies
              // and what does not.
              ? '${member.fullName} loses access to this PG immediately: every screen and every '
                  'record stops loading for them. Their history stays. You can reactivate them, '
                  'or add a different ${member.role.label.toLowerCase()} once the post is free.'
              : 'This only works if the ${member.role.label.toLowerCase()} post is free — a PG '
                  'can have one active ${member.role.label.toLowerCase()} at a time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(deactivating ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(ownerStaffWritesProvider).setStaffStatus(
            hostelId: widget.hostelId,
            userId: member.id,
            status: to,
          );
      ref.invalidate(ownerStaffProvider(widget.hostelId));
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(
        content: Text(deactivating
            ? '${member.role.label} deactivated'
            : '${member.role.label} reactivated'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (error) {
      final failure = AppFailure.from(error);
      if (!mounted) return;
      setState(() => _busy = false);
      // The snackbar keeps its themed midnight background and says "this failed" with an icon;
      // repainting the bar red puts its own white text at 4.35:1. Same reasoning as the
      // warden's runAction().
      messenger.showSnackBar(SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                size: IconSize.md, color: NivoraColors.errorDark),
            const SizedBox(width: Space.sm),
            Expanded(child: Text(failure.message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: Motion.readMessage,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final role = widget.role;
    final inRole = widget.members.inRole(role);
    final active = widget.members.activeIn(role);
    // No active holder: show the most recent person who did hold it, so "reactivate" is one tap
    // rather than a search. inRole is already ordered active-first, then newest-first.
    final primary = active ?? (inRole.isEmpty ? null : inRole.first);

    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(role.label.toUpperCase(), style: t.textTheme.labelSmall),
                    const SizedBox(height: Space.xxs),
                    Text(role.blurb, style: t.textTheme.bodySmall),
                  ],
                ),
              ),
              if (primary != null) ...[
                const SizedBox(width: Space.xs),
                StatusChip(
                  label: primary.status.label,
                  tone: primary.isActive ? NivoraColors.success : NivoraColors.textMuted,
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.md),
          if (primary == null)
            EmptyNote(
              icon: Icons.person_add_alt_rounded,
              title: 'No ${role.label.toLowerCase()} yet',
              message: 'Nobody can do this job in ${widget.hostelName ?? 'this PG'} until you '
                  'add one.',
              compact: true,
            )
          else
            _StaffDetails(member: primary),
          const SizedBox(height: Space.md),
          _Actions(
            role: role,
            primary: primary,
            hasActive: active != null,
            busy: _busy,
            onAdd: _add,
            onDeactivate:
                primary == null ? null : () => _setStatus(primary, StaffStatus.inactive),
            onReactivate:
                primary == null ? null : () => _setStatus(primary, StaffStatus.active),
          ),
          if (active != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              'One ${role.label.toLowerCase()} at a time. Deactivate ${active.fullName} to free '
              'the post.',
              style: t.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Name, login and contact for whoever holds a post.
class _StaffDetails extends StatelessWidget {
  const _StaffDetails({required this.member});

  final StaffMember member;

  static final DateFormat _added = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = context.tones.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(member.fullName, style: t.textTheme.titleMedium),
        const SizedBox(height: Space.xs),
        if (member.email != null)
          _DetailLine(icon: Icons.mail_outline_rounded, text: member.email!),
        if (member.phone != null) ...[
          const SizedBox(height: Space.xxs),
          _DetailLine(icon: Icons.phone_outlined, text: member.phone!),
        ],
        const SizedBox(height: Space.xs),
        Text(
          'Added ${_added.format(member.createdAt.toLocal())}',
          style: t.textTheme.labelSmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: IconSize.sm, color: context.tones.muted),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Text(
            text,
            style: t.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Add / Deactivate / Reactivate.
///
/// Add is DISABLED, not hidden, while the post is filled: hiding it would read as a missing
/// feature, and the sentence under it explains the rule. Disabling here is a drawing decision —
/// the server refuses the same create with §4.3's own message if this is ever wrong.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.role,
    required this.primary,
    required this.hasActive,
    required this.busy,
    required this.onAdd,
    required this.onDeactivate,
    required this.onReactivate,
  });

  final StaffRole role;
  final StaffMember? primary;
  final bool hasActive;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback? onDeactivate;
  final VoidCallback? onReactivate;

  @override
  Widget build(BuildContext context) {
    final label = role.label.toLowerCase();
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        FilledButton.icon(
          onPressed: hasActive || busy ? null : onAdd,
          icon: const Icon(Icons.person_add_alt_rounded, size: IconSize.md),
          label: Text('Add $label'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        ),
        if (primary != null && primary!.isActive)
          OutlinedButton.icon(
            onPressed: busy ? null : onDeactivate,
            icon: const Icon(Icons.person_off_outlined, size: IconSize.md),
            label: const Text('Deactivate'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
        if (primary != null && !primary!.isActive)
          OutlinedButton.icon(
            onPressed: busy ? null : onReactivate,
            icon: const Icon(Icons.person_outline_rounded, size: IconSize.md),
            label: const Text('Reactivate'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
      ],
    );
  }
}

/// What deactivation does and does not do, said once at the foot of the page.
///
/// Worth the space: an owner who thinks deactivating deletes somebody will not do it, and an
/// owner who thinks it only hides them from a list will hand the PG to their replacement
/// without doing it at all.
class _DeactivationNote extends StatelessWidget {
  const _DeactivationNote();

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
          Expanded(
            child: Text(
              'Deactivating keeps the record and the history — the expenses a manager entered '
              'and the residents a warden registered all stay. It only takes away their access, '
              'and it frees the post so you can add somebody else.',
              style: t.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
