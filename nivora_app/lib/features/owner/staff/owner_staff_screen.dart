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
/// ── THE RULE THAT SHAPES THE LAYOUT ──────────────────────────────────────────────────────
///
/// Hard rule §4.3: up to [maxStaffPerRole] active managers and [maxStaffPerRole] active wardens
/// per hostel. It was ONE of each until 2026-09-12, which is why this screen used to be two
/// posts with a single holder drawn into each; the product owner needed staff for a second PG
/// and shift cover for the first.
///
/// So each post is now a LIST with a count on it — "2 of 5" — and Add stays live until the fifth.
/// The count is on the card rather than only in a refusal, because the question an owner opens
/// this screen with is "how many wardens do I have", and finding out from a 409 after typing
/// somebody's details in is the worst possible time to learn it.
///
/// `app.enforce_role_limits` is what actually enforces the limit — it takes an advisory lock on
/// (hostel, role) before it counts, which is what replaced the partial unique index that could
/// only ever say "at most one". This screen only draws it.
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
          // staff-directory.png's bar: the screen's name set in `primary` at headline weight,
          // with the property it belongs to underneath. The mockup's hamburger and avatar are
          // not drawn — this screen is a tab inside the shell's own chrome, not a page with
          // its own navigation.
          GlassHeader(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Staff accounts',
                        style: t.textTheme.titleLarge?.copyWith(color: t.colorScheme.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        hostelName ?? 'Your PG',
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
              'Up to $maxStaffPerRole managers and $maxStaffPerRole wardens per PG. Each gets '
              'their own login, and each sees only their own part of it.',
              style: t.textTheme.bodyMedium,
            ),
            const SizedBox(height: Space.lg),
            // 4:536's own section label for this block.
            const SectionLabel(label: 'Staff & access'),
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

  /// Which posts have no room left — passed to the sheet so a full post is drawn as full
  /// rather than offered and then refused.
  Set<StaffRole> get _full => {
        for (final role in StaffRole.values)
          if (widget.members.isFull(role)) role,
      };

  Future<void> _add() async {
    final created = await showAddStaffSheet(
      context,
      hostelId: widget.hostelId,
      hostelName: widget.hostelName,
      initialRole: widget.role,
      full: _full,
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
                  'record stops loading for them. Their history stays — the expenses they '
                  'entered and the residents they registered are unaffected — and you can '
                  'reactivate them at any time.'
              : 'This only works while there is a free place — a PG can have $maxStaffPerRole '
                  'active ${member.role.label.toLowerCase()}s at once.',
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
    // Active first, newest first within that — the order the repository asks the server for.
    // Everyone who has ever held the post is here: reactivating somebody who worked a season
    // ago is one tap, and a post that looks empty shows why it is empty.
    final everyone = widget.members.inRole(role);
    final active = widget.members.activeInRole(role);
    final full = active.length >= maxStaffPerRole;

    return GlassCard(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                // GOLD, which is 4:536's own treatment of a post: on the mockup's staff rows
                // the role is the one thing set in the accent. Measured 8.26:1 on the card.
                child: Text(
                  role.label.toUpperCase(),
                  style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.primary),
                ),
              ),
              // "2 of 5" — the answer to the question this screen is opened with, before any
              // scrolling and before any refusal.
              StatusChip(
                label: '${active.length} of $maxStaffPerRole',
                tone: full ? NivoraColors.textMuted : NivoraColors.success,
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          if (everyone.isEmpty)
            EmptyNote(
              icon: Icons.person_add_alt_rounded,
              title: 'No ${role.label.toLowerCase()} yet',
              message: 'Nobody can do this job in ${widget.hostelName ?? 'this PG'} until you '
                  'add one.',
              compact: true,
              // The people colour, not a warning: an unfilled post is a fact about staff, and
              // the button under it is how it changes.
              tone: NivoraDomain.people.tone,
            )
          else
            for (var i = 0; i < everyone.length; i++) ...[
              if (i > 0) const Divider(height: Space.lg),
              _StaffDetails(member: everyone[i]),
              const SizedBox(height: Space.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: everyone[i].isActive
                    ? OutlinedButton.icon(
                        onPressed:
                            _busy ? null : () => _setStatus(everyone[i], StaffStatus.inactive),
                        icon: const Icon(Icons.person_off_outlined, size: IconSize.md),
                        label: const Text('Deactivate'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      )
                    // Disabled rather than hidden when the post is full: the reason is the
                    // count above it, and a button that vanishes reads as a lost feature.
                    : OutlinedButton.icon(
                        onPressed: _busy || full
                            ? null
                            : () => _setStatus(everyone[i], StaffStatus.active),
                        icon: const Icon(Icons.person_outline_rounded, size: IconSize.md),
                        label: const Text('Reactivate'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      ),
              ),
            ],
          const SizedBox(height: Space.sm),
          Text(role.blurb, style: t.textTheme.bodySmall),
          const SizedBox(height: Space.md),
          // Add is DISABLED, not hidden, at the limit: hiding it would read as a missing
          // feature, and the sentence under it explains the rule. Disabling here is a drawing
          // decision — the server refuses the same create with §4.3's own message if this is
          // ever wrong.
          FilledButton.icon(
            onPressed: full || _busy ? null : _add,
            icon: const Icon(Icons.person_add_alt_rounded, size: IconSize.md),
            label: Text('Add ${role.label.toLowerCase()}'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
          const SizedBox(height: Space.xs),
          Text(
            full
                ? '$maxStaffPerRole is the limit. Deactivate one to free a place.'
                : 'You can add ${maxStaffPerRole - active.length} more.',
            style: t.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Name, login and contact for whoever holds a post — the mockup's card header and inner block.
class _StaffDetails extends StatelessWidget {
  const _StaffDetails({required this.member});

  final StaffMember member;

  static final DateFormat _added = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = context.tones.muted;
    final active = member.isActive;
    final tone = active ? NivoraColors.success : NivoraColors.textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // `[avatar] Name / role  …  ● On Duty` — the design's card header.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InitialsAvatar(name: member.fullName, muted: !active),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.fullName,
                    style: t.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Added ${_added.format(member.createdAt.toLocal())}',
                    style: t.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.xs),
            StatusChip(label: member.status.label, tone: tone, dot: true),
          ],
        ),
        // The mockup's `ASSIGNED PROPERTY` block. Filled with the login and the phone rather
        // than the property, because this screen already names the PG in its header and
        // repeating it on both cards would be furniture. The shape is the design's: a step up
        // the container ramp, a square icon badge, a `label-caps` eyebrow over the value.
        if (member.email != null || member.phone != null) ...[
          const SizedBox(height: Space.sm),
          FlatSurface(
            weight: GlassWeight.regular,
            borderRadius: Radii.rControl,
            padding: const EdgeInsets.all(Space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (member.email != null)
                  _DetailLine(
                    icon: Icons.mail_outline_rounded,
                    label: 'Login id',
                    text: member.email!,
                  ),
                if (member.email != null && member.phone != null)
                  const SizedBox(height: Space.sm),
                if (member.phone != null)
                  _DetailLine(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    text: member.phone!,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.label, required this.text});

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        // AN ICON HOLDER, NOT WAYFINDING — and the neutral is the considered choice. This
        // block already says "staff" twice: the avatar two rows up is people-teal and the
        // heading above it names the post. A teal plate on every detail row would state the
        // same domain a third time inside one card, and a phone glyph on a row labelled PHONE
        // is not telling anyone where they are. So the tone stays canonical [textMuted],
        // resolved at the paint site to `context.tones.muted`, and the people colour stays on
        // the avatar and the heading where it does work. See [NivoraDomain].
        ToneBadge(icon: icon, tone: NivoraColors.textMuted),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: t.textTheme.labelSmall),
              Text(
                text,
                style: t.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
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
              'and it frees a place so you can add somebody else.',
              style: t.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
