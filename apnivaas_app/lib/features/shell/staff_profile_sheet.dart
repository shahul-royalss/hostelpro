import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart';
import '../../core/router/router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay_icons.dart';
import '../../shared/clay/list_row.dart';
import '../../shared/person_avatar.dart';
import '../../shared/clay/status_chip.dart';
import '../../shared/glass/glass.dart';
import '../common/staff_hostel_switcher.dart';
import '../legal/account_deletion.dart';
import '../settings/security_screen.dart';
import 'change_photo.dart';

/// Who you are signed in as, and the two things you can do about it.
///
/// ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────
///
/// Every role's header used to end in two bare icons: a shield for two-factor enrolment and a
/// door for sign-out. A resident got something better — a Profile tab with an Account card that
/// names both actions and says what each one costs — and the product owner asked for the same
/// treatment everywhere else: "take them and keep in profile like in student profile".
///
/// A staff member has no Profile TAB to put it in. A manager's tabs are their work, and adding a
/// fifth tab that is read almost never would push the four that matter into less room. So this
/// is a sheet, opened from the avatar that now sits at the top left of every non-resident
/// header, which is the same gesture every phone user already has for "my account".
///
/// ── WHAT IT DELIBERATELY DOES NOT DO ──────────────────────────────────────────────────────
///
/// It does not let a staff member EDIT anything. Their name, phone and email are set when their
/// owner or super admin creates the account, the same way a resident's are set by their warden,
/// and there is no self-service write for them anywhere in the product. Drawing an edit affordance
/// here would promise a screen that does not exist behind it.
Future<void> showStaffProfile(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  // The sheet draws its own grip on its own pane. Left to the theme, Material adds a second one
  // in a 48dp band ABOVE the pane — a grey pill floating over the dimmed page, the bug
  // showGlassSheet's grip exists to avoid (see shared/glass/glass.dart).
  showDragHandle: false,
  builder: (_) => const _StaffProfileSheet(),
);

class _StaffProfileSheet extends ConsumerWidget {
  const _StaffProfileSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final session = ref.watch(sessionProvider);

    if (session == null) return const SizedBox.shrink();

    final name = session.fullName.trim().isEmpty ? 'Your account' : session.fullName.trim();

    // THE PG, FOR THE TWO ROLES THAT WORK IN ONE. A warden or manager may now hold access to
    // several PGs and work in one at a time, so "which PG am I in" belongs next to who they are.
    // The switch action is offered only for two or more: the list is empty for every other
    // role without a round trip, and a single PG has nowhere to switch to.
    final staffRole = session.role == UserRole.warden || session.role == UserRole.manager;
    final hostels = staffRole
        ? ref.watch(myStaffHostelsProvider).value ?? const <StaffHostel>[]
        : const <StaffHostel>[];
    String? pgName;
    for (final h in hostels) {
      if (h.hostelId == session.hostelId) pgName = h.name;
    }
    if (staffRole && pgName == null && session.hostelId != null) {
      pgName = ref.watch(hostelProvider(session.hostelId!)).value?.name;
    }
    final canSwitch = hostels.length >= 2;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      builder: (context, controller) => FlatSurface(
        weight: GlassWeight.thick,
        borderRadius: Radii.rSheetTop,
        padding: EdgeInsets.zero,
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.xl),
          children: [
            // The grip every other sheet has: 36 by 4, in the control border, because a handle
            // is a control and 3:1 applies to it.
            Semantics(
              label: 'Drag down to dismiss',
              child: Center(
                child: Container(
                  width: Space.xxl + Space.xxs,
                  height: Space.xxs,
                  margin: const EdgeInsets.only(bottom: Space.md),
                  decoration: BoxDecoration(
                    color: t.brightness == Brightness.dark
                        ? ApnivaasColors.darkControlBorder
                        : ApnivaasColors.controlBorder,
                    borderRadius: Radii.rPill,
                  ),
                ),
              ),
            ),
            Row(
              children: [
                MyAvatar(name: name, size: AvatarSize.headerLarge),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          name,
                          style: t.textTheme.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: Space.xxs),
                      // The role as a word on a chip, not an all-caps eyebrow: it is a fact
                      // about the account, read after the name.
                      StatusChip(label: session.role.label, tone: StatusTone.brand),
                      const ChangePhotoButton(),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: Space.lg),
            GlassCard(
              child: Column(
                children: [
                  // Phone before email: staff sign in with an email, but the number is what a
                  // colleague standing in the corridor actually needs.
                  _Row(label: 'Phone', value: session.phone),
                  _Row(label: 'Email', value: session.email),
                  if (staffRole) _Row(label: 'Working in', value: pgName),
                ],
              ),
            ),
            if (canSwitch) ...[
              const SizedBox(height: Space.lg),
              ListGroup(
                children: [
                  _Action(
                    icon: ClayIcons.navProperty,
                    label: 'Switch PG',
                    caption:
                        'You have access to ${hostels.length} PGs. Choose the one you are '
                        'working in.',
                    onTap: () {
                      Navigator.of(context).pop();
                      openStaffHostelSwitcher(context);
                    },
                  ),
                ],
              ),
            ],

            const SizedBox(height: Space.lg),
            // The resident's Account card, row for row: the same clay art for the same action,
            // so "my account" reads the same whoever is signed in.
            ListGroup(
              children: [
                _Action(
                  icon: ClayIcons.kyc,
                  label: 'Two-factor authentication',
                  caption: 'A code from your authenticator app at sign-in.',
                  onTap: () {
                    Navigator.of(context).pop();
                    openSecurity(context);
                  },
                ),
                _Action(
                  icon: ClayIcons.security,
                  label: 'Change password',
                  caption: 'Confirm it is you, then choose a new one.',
                  onTap: () {
                    // The router is read before the sheet closes, and the route is pushed
                    // through it: GoRouter gives the Navigator no onGenerateRoute, so the
                    // Navigator.pushNamed this used to make found nothing and threw.
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.push(changePasswordRoute);
                  },
                ),
                // Google Play requires an in-app path to request account deletion; see
                // features/legal/account_deletion.dart for why it files a request.
                _Action(
                  icon: ClayIcons.agreement,
                  label: 'Delete my account and data',
                  caption: 'Ask for this account and your personal data to be erased.',
                  danger: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    openAccountDeletion(context);
                  },
                ),
                _Action(
                  icon: ClayIcons.moveOut,
                  label: 'Sign out',
                  caption: 'You will need your password to get back in.',
                  onTap: () {
                    Navigator.of(context).pop();
                    ref.read(authControllerProvider.notifier).signOut();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final shown = (value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: Text(
                // "Not recorded" rather than an empty gap: a blank line reads as a rendering
                // fault, and the absence is itself information for whoever created the account.
                shown.isEmpty ? 'Not recorded' : shown,
                style: shown.isEmpty
                    ? t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)
                    : t.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the account card: the resident's `_AccountRow`, because the owner asked for this
/// to feel like that screen — a clay icon, the action in words, one line saying what it costs.
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
    this.danger = false,
  });

  /// A [ClayIcons] path.
  final String icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  /// Deleting the account is the one action here that cannot be taken back; its label takes
  /// the error ink, as it does on the resident's profile.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final row = ListRow(icon: icon, title: label, subtitle: caption, onTap: onTap);
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
