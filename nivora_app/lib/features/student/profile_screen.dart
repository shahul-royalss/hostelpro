library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/router/router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import 'student_providers.dart';
import 'widgets/common.dart';
import 'widgets/format.dart';
import 'widgets/rent.dart';

/// Everything the hostel holds about this resident, and who to call about it.
///
/// READS
///   public.students          — own row, via `myStudentProvider`.
///   public.st_my_roommates() — names, phones and bed numbers of the people in the same room.
///   public.st_hostel_contacts() — the hostel name, address, rules and the staff contact card.
///   public.rpc_fee_ledger    — reused only to name the room and bed (see `myRentThisMonthProvider`).
///
/// WHAT A RESIDENT MAY SEE ABOUT ANOTHER RESIDENT IS THREE FIELDS. `st_my_roommates()` returns
/// name, phone and bed number, and that is the entire permitted set (Hard rule §4.8). No photo —
/// the storage key is itself a capability. No address, no guardian, no fee, no id. This screen
/// does not ask for more, and it must never grow a "see profile" tap that implies more exists:
/// the RLS policy would refuse it, but a control that has to refuse a request the UI offered is
/// a UI that promised something it had no business promising.
class StudentProfileScreen extends StatelessWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResidentBuilder(builder: (context, ref, me) => _Profile(me: me));
  }
}

class _Profile extends ConsumerWidget {
  const _Profile({required this.me});
  final Student me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final rent = ref.watch(myRentThisMonthProvider);
    final roommates = ref.watch(roommatesProvider);

    return RefreshIndicator(
      onRefresh: () {
        refreshStudentData(ref);
        return awaitStudentRefresh(context, ref);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _Identity(me: me),

          const SizedBox(height: Space.xl),
          const SectionHeading(
            title: 'Your room',
            domain: NivoraDomain.rooms,
            icon: Icons.bed_rounded,
          ),
          AsyncSection<FeeLedgerRow?>(
            value: rent,
            onRetry: () => ref.invalidate(myRentThisMonthProvider),
            // NO `roommates:` HERE, unlike Home. The roommate read has its own section
            // immediately below, and it is the better one: it names the people rather than
            // counting them. Passing the count as well would draw one read twice — a summary
            // line and a list of the same names on a good day, and on a bad one the same
            // failure said twice in a row.
            //
            // THE ONE DOMAIN-TINTED CARD ON THIS SCREEN. The room is what this section is
            // about and it carries no status, so it takes the rooms colour on its ground — the
            // rule in [NivoraDomain] allows exactly one such card per screen.
            builder: (row) => RoomBedCard(
              roomNumber: row?.roomNumber,
              bedNumber: row?.bedNumber,
              hero: true,
            ),
          ),

          const SizedBox(height: Space.md),
          AsyncSection<List<Roommate>>(
            value: roommates,
            onRetry: () => ref.invalidate(roommatesProvider),
            // Sized like the card it becomes, so "still fetching your roommates" does not look
            // like the one-line "No roommates listed" that means the opposite.
            loading: const SkeletonCard(lines: 2),
            builder: (mates) => _Roommates(mates: mates),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeading(
            title: 'My details',
            // One person, so the single figure rather than the domain's group glyph.
            domain: NivoraDomain.people,
            icon: Icons.person_rounded,
          ),
          OutlineCard(
            child: Column(
              children: [
                DetailRow(label: 'Full name', value: me.fullName),
                DetailRow(label: 'Phone', value: me.phone),
                DetailRow(label: 'Email', value: me.email),
                DetailRow(label: 'Joined', value: dayLabel(me.dateOfJoining)),
                DetailRow(label: 'Agreed rent', value: '${rupees(me.monthlyFee)} per month'),
                DetailRow(label: 'Guardian', value: me.guardianName),
                DetailRow(label: 'Guardian phone', value: me.guardianPhone),
                DetailRow(label: 'Address', value: me.permanentAddress),
                DetailRow(label: 'ID proof', value: me.idProofType),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          // ── WHY "Your hostel" IS NOT HERE ────────────────────────────────────────────────
          // It was: name, address, warden, manager, owner and the house rules. The product
          // owner removed it — "students don't need that section in profile" — and they are
          // right that it is not part of a person's own record. The read itself is NOT dead:
          // hostelContactsProvider still backs the home screen and the payment receipt, so
          // deleting the section removed a duplicate, not a capability.
          const SectionHeading(
            title: 'Account',
            domain: NivoraDomain.security,
            icon: Icons.lock_rounded,
          ),
          OutlineCard(
            child: Column(
              children: [
                _AccountAction(
                  icon: Icons.password_rounded,
                  label: 'Change password',
                  caption: 'Confirm it is you, then choose a new one.',
                  onTap: () => Navigator.of(context).pushNamed(changePasswordRoute),
                ),
                Divider(color: t.colorScheme.outlineVariant, height: Space.lg),
                _AccountAction(
                  icon: Icons.logout_rounded,
                  label: 'Sign out',
                  caption: 'You will need your password to get back in.',
                  danger: true,
                  onTap: () => ref.read(authControllerProvider.notifier).signOut(),
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          Text(
            'Only you, your warden and the hostel owner can see your details. '
            'Other residents see your name, phone number and bed — nothing else.',
            style: t.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The name at the top, with the one status that changes how a resident is treated.
class _Identity extends StatelessWidget {
  const _Identity({required this.me});
  final Student me;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Initials, not a photo. `students.photo_url` is a storage key that has to be signed
        // before it can be fetched, and this app has no signing path — a broken image is worse
        // than none. The disc, its measured tint and the way a name becomes one or two letters
        // all live in [InitialsAvatar] now, so the face beside this name and the cluster on the
        // home room card cannot drift apart.
        InitialsAvatar(name: me.fullName, size: Space.huge + Space.xxs),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(me.fullName, style: t.textTheme.titleLarge,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: Space.xxs),
              Text(me.phone, style: t.textTheme.bodyMedium),
            ],
          ),
        ),
        if (me.status != StudentStatus.active)
          StatusPill(label: me.status.label, tone: NivoraColors.warning),
      ],
    );
  }
}

class _Roommates extends StatelessWidget {
  const _Roommates({required this.mates});
  final List<Roommate> mates;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (mates.isEmpty) {
      return EmptyNote(
        icon: Icons.person_outline_rounded,
        title: 'No roommates listed',
        message: 'Either you have the room to yourself, or you have not been placed in one yet.',
        // Neither good nor bad news — a room to yourself is fine — so the glyph takes the
        // people domain's teal rather than the neutral outline or a congratulating green.
        tone: NivoraDomain.people.tone,
      );
    }
    return OutlineCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CapsLabel('Sharing with you'),
          const SizedBox(height: Space.xs),
          for (var i = 0; i < mates.length; i++) ...[
            if (i > 0) Divider(color: t.colorScheme.outlineVariant),
            _RoommateRow(mate: mates[i]),
          ],
        ],
      ),
    );
  }
}

class _RoommateRow extends StatelessWidget {
  const _RoommateRow({required this.mate});
  final Roommate mate;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          // The same disc the home room card clusters, at directory size. Three fields is the
          // entire permitted set for one resident looking at another (§4.8) — a face here would
          // be a fourth, and there is no signing path to fetch one anyway.
          InitialsAvatar(name: mate.fullName),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mate.fullName, style: t.textTheme.bodyLarge,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.xxs),
                SelectionArea(child: Text(mate.phone, style: t.textTheme.bodySmall)),
              ],
            ),
          ),
          if (mate.bedNumber != null)
            Text('Bed ${mate.bedNumber}', style: t.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// One row of the Account card: an icon, a label, a line of consequence, and a tap target that
/// covers the whole width.
///
/// The two actions it carries were both reachable before — sign-out from the header icon on
/// every screen, the password change only by being FORCED there at sign-in when
/// `must_change_password` is set. Neither was discoverable from the one screen a resident
/// thinks of as theirs, which is what the product owner was reporting. This does not replace
/// the header icon; a resident who has learned it keeps it.
class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  /// Sign-out ends the session; it is tinted with the same red the rest of the app uses for an
  /// action with a consequence, rather than being given a different one of its own.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = danger ? t.colorScheme.error : t.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.rCard,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tone),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: t.textTheme.bodyLarge?.copyWith(color: tone)),
                  const SizedBox(height: Space.xxs),
                  Text(caption, style: t.textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: t.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
