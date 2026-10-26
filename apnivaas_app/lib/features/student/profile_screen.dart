library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/router/router.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay.dart';
import '../legal/account_deletion.dart';
import '../settings/security_screen.dart';
import '../shell/change_photo.dart';
import '../../shared/person_avatar.dart';
import '../../data/models/stay.dart';
import '../../data/repositories/stay_repository.dart';
import 'stay_screens.dart';
import 'student_providers.dart';
import 'widgets/common.dart';
import 'widgets/format.dart';
import 'widgets/rent.dart';

/// Everything the hostel holds about this resident, and who to call about it.
///
/// READS
///   public.students          — own row, via `myStudentProvider`.
///   public.st_my_roommates() — names, phones and bed numbers of the people in the same room.
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
          const SectionHeader(title: 'Your room'),
          const SizedBox(height: Space.sm),
          AsyncSection<FeeLedgerRow?>(
            value: rent,
            onRetry: () => ref.invalidate(myRentThisMonthProvider),
            // NO `roommates:` HERE. The roommate read has its own section immediately below,
            // and it is the better one: it names the people rather than counting them. Passing
            // the count as well would draw one read twice — a summary line and a list of the
            // same names on a good day, and on a bad one the same failure said twice in a row.
            //
            // THE ONE MIST CARD ON THIS SCREEN. The room is what this section is about and it
            // carries no status, so it takes the tonal tile's ground.
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
            // Sized like the list it becomes, so "still fetching your roommates" does not look
            // like the one-line "No roommates listed" that means the opposite.
            loading: const SkeletonCard(lines: 2),
            builder: (mates) => _Roommates(mates: mates),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeader(title: 'My details'),
          const SizedBox(height: Space.sm),
          OutlineCard(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, fact) in <(String, String?)>[
                  ('Full name', me.fullName),
                  ('Phone', me.phone),
                  ('Email', me.email),
                  ('Joined', dayLabel(me.dateOfJoining)),
                  ('Agreed rent', '${rupees(me.monthlyFee)} per month'),
                  ('Guardian', me.guardianName),
                  ('Guardian phone', me.guardianPhone),
                  ('Address', me.permanentAddress),
                  ('ID proof', me.idProofType),
                ].indexed) ...[
                  if (i > 0) Divider(height: Strokes.hairline, color: t.dividerTheme.color),
                  DetailRow(label: fact.$1, value: fact.$2),
                ],
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          // Round 3: the stay from check-in (R2) and the check-out request (R6).
          const SectionHeader(title: 'Your stay'),
          const SizedBox(height: Space.sm),
          ListGroup(
            children: [
              _AccountRow(
                art: ClayIcons.calendar,
                label: 'Timeline',
                caption: 'Check-in, rooms, rent, payments and requests, from your first day.',
                onTap: () => Navigator.of(context).push(TimelineScreen.route()),
              ),
              _AccountRow(
                art: ClayIcons.moveOut,
                label: 'Request check-out',
                caption: _checkoutCaption(ref.watch(myCheckoutRequestProvider).value),
                onTap: () => Navigator.of(context).push(CheckoutScreen.route()),
              ),
            ],
          ),

          const SizedBox(height: Space.xl),
          // ── WHY "Your hostel" IS NOT HERE ────────────────────────────────────────────────
          // It was: name, address, warden, manager, owner and the house rules. The product
          // owner removed it — "students don't need that section in profile" — and they are
          // right that it is not part of a person's own record. The read itself is NOT dead:
          // hostelContactsProvider still backs the home screen and the payment receipt, so
          // deleting the section removed a duplicate, not a capability.
          const SectionHeader(title: 'Account'),
          const SizedBox(height: Space.sm),
          ListGroup(
            children: [
              _AccountRow(
                art: ClayIcons.security,
                label: 'Change password',
                caption: 'Confirm it is you, then choose a new one.',
                // A go_router push, not Navigator.pushNamed: the app's routes live in GoRouter,
                // which gives the Navigator no onGenerateRoute, so a named push found nothing
                // and threw. Pushed, the form has this screen to go back to.
                onTap: () => context.push(changePasswordRoute),
              ),
              // ── MOVED HERE FROM THE HEADER ──────────────────────────────────────────────
              //
              // The resident's masthead carried a shield icon for this and a door for sign
              // out. Both were asked to go. Sign out was already on this card; security was
              // NOT — the icon was its only route — so deleting it alone would have removed
              // two-factor authentication from residents entirely. That is a security
              // downgrade wearing a layout change, so the capability moved instead of going.
              _AccountRow(
                art: ClayIcons.kyc,
                label: 'Security',
                caption: 'App lock and two-factor authentication.',
                onTap: () => openSecurity(context),
              ),
              // Google Play requires an in-app path to request account deletion; see
              // features/legal/account_deletion.dart for why it files a request.
              _AccountRow(
                art: ClayIcons.agreement,
                label: 'Delete my account and data',
                caption: 'Ask your hostel to erase your account and personal details.',
                danger: true,
                onTap: () => openAccountDeletion(context),
              ),
              _AccountRow(
                art: ClayIcons.moveOut,
                label: 'Sign out',
                caption: 'You will need your password to get back in.',
                onTap: () => ref.read(authControllerProvider.notifier).signOut(),
              ),
            ],
          ),

          const SizedBox(height: Space.lg),
          const InfoNote(
            icon: Icons.lock_outline_rounded,
            message: 'Only you, your warden and the hostel owner can see your details. '
                'Other residents see your name, phone number and bed — nothing else.',
          ),
        ],
      ),
    );
  }
}

String _checkoutCaption(CheckoutRequest? r) => switch (r?.status) {
      CheckoutStatus.pending => 'Requested for ${dayLabel(r!.preferredDate)} · waiting for the warden',
      CheckoutStatus.accepted => 'Accepted · ${dayLabel(r!.checkoutDate ?? r.preferredDate)}',
      _ => 'Tell your warden when you plan to leave.',
    };

/// The name at the top, with the one status that changes how a resident is treated.
class _Identity extends StatelessWidget {
  const _Identity({required this.me});
  final Student me;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return OutlineCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The account's own photo (users.avatar_path, signed for 60 seconds), initials until it
          // loads or when there is none — the same disc the roommates below are drawn with.
          MyAvatar(name: me.fullName, size: ClaySize.tile),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me.fullName,
                  style: context.textRoles.tileTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.hair),
                Text(
                  'Tenant · ${me.phone}',
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
                if (me.status != StudentStatus.active) ...[
                  const SizedBox(height: Space.xs),
                  StatusPill(label: me.status.label, tone: ApnivaasColors.warning),
                ],
                const ChangePhotoButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Roommates extends StatelessWidget {
  const _Roommates({required this.mates});
  final List<Roommate> mates;

  @override
  Widget build(BuildContext context) {
    if (mates.isEmpty) {
      // Neither good nor bad news — a room to yourself is fine — so it is said plainly, at the
      // compact size: the room card above already heads this section.
      return const EmptyNote(
        clay: ClayIcons.navPeople,
        icon: Icons.person_outline_rounded,
        title: 'No roommates listed',
        message: 'Either you have the room to yourself, or you have not been placed in one yet.',
        compact: true,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Sharing with you', size: SectionHeaderSize.form),
        const SizedBox(height: Space.xs),
        ListGroup(children: [for (final mate in mates) _RoommateRow(mate: mate)]),
      ],
    );
  }
}

class _RoommateRow extends StatelessWidget {
  const _RoommateRow({required this.mate});
  final Roommate mate;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    // A list row's anatomy, built by hand for one reason: the phone number stays SELECTABLE, so
    // a resident can copy a roommate's number instead of retyping it. Three fields is the
    // entire permitted set for one resident looking at another (§4.8) — no tap and no chevron,
    // because there is nothing further to open.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ListRow.minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          children: [
            InitialsDisc(name: mate.fullName),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mate.fullName,
                    style: t.textTheme.titleMedium,
                    // Two lines once text is large, as a list row's title does.
                    maxLines: MediaQuery.textScalerOf(context).scale(1) >= 1.3 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.hair),
                  SelectionArea(
                    child: Text(mate.phone, style: t.textTheme.bodySmall?.copyWith(color: muted)),
                  ),
                ],
              ),
            ),
            if (mate.bedNumber != null) ...[
              const SizedBox(width: Space.xs),
              Text('Bed ${mate.bedNumber}', style: t.textTheme.titleSmall?.copyWith(color: muted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of the Account card: clay art, a label, a line of consequence, and a tap target that
/// covers the whole row — the kit's [ListRow], so these rows match every settings list in the
/// app.
///
/// The actions were all reachable before — sign-out from the header icon on every screen, the
/// password change only by being FORCED there at sign-in when `must_change_password` is set.
/// Neither was discoverable from the one screen a resident thinks of as theirs, which is what
/// the product owner was reporting.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.art,
    required this.label,
    required this.caption,
    required this.onTap,
    this.danger = false,
  });

  final String art;
  final String label;
  final String caption;
  final VoidCallback onTap;

  /// Deleting the account is the one action here that cannot be taken back; its label takes
  /// the error ink the rest of the app uses for an action with that kind of consequence.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final row = ListRow(icon: art, title: label, subtitle: caption, onTap: onTap);
    if (!danger) return row;
    final t = Theme.of(context);
    return Theme(
      data: t.copyWith(
        textTheme: t.textTheme.copyWith(
          titleMedium: t.textTheme.titleMedium?.copyWith(color: context.tones.error),
        ),
      ),
      child: row,
    );
  }
}
