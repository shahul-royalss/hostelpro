import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/router/router.dart';
import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';
import '../settings/security_screen.dart';

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

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      builder: (context, controller) => FlatSurface(
        weight: GlassWeight.thick,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        padding: EdgeInsets.zero,
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.xl),
          children: [
            Center(
              child: Container(
                width: Space.xxl,
                height: Space.xxs,
                margin: const EdgeInsets.only(bottom: Space.md),
                decoration: BoxDecoration(
                  color: t.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(Space.xxs),
                ),
              ),
            ),
            Row(
              children: [
                AccountAvatar(name: name, size: Space.huge),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.role.label.toUpperCase(),
                        style: t.textTheme.labelSmall,
                      ),
                      const SizedBox(height: Space.xxs),
                      Text(
                        name,
                        style: t.textTheme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                ],
              ),
            ),

            const SizedBox(height: Space.lg),
            GlassCard(
              child: Column(
                children: [
                  _Action(
                    icon: Icons.shield_rounded,
                    label: 'Two-factor authentication',
                    caption: 'A code from your authenticator app at sign-in.',
                    onTap: () {
                      Navigator.of(context).pop();
                      openSecurity(context);
                    },
                  ),
                  Divider(color: t.colorScheme.outlineVariant, height: Space.lg),
                  _Action(
                    icon: Icons.password_rounded,
                    label: 'Change password',
                    caption: 'Confirm it is you, then choose a new one.',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamed(changePasswordRoute);
                    },
                  ),
                  Divider(color: t.colorScheme.outlineVariant, height: Space.lg),
                  _Action(
                    icon: Icons.logout_rounded,
                    label: 'Sign out',
                    caption: 'You will need your password to get back in.',
                    danger: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      ref.read(authControllerProvider.notifier).signOut();
                    },
                  ),
                ],
              ),
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
            child: Text(label, style: t.textTheme.bodySmall),
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

/// One row of the actions card. Deliberately the same shape as the resident's `_AccountAction`,
/// because the owner asked for this to feel like that screen.
class _Action extends StatelessWidget {
  const _Action({
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
            Icon(icon, size: IconSize.md, color: tone),
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
            Icon(Icons.chevron_right_rounded, size: IconSize.md, color: t.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
