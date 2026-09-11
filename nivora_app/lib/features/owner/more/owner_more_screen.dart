library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/finance/expense_stats_screen.dart';
import '../../../shared/glass/glass.dart';
import '../owner_providers.dart';
import '../staff/owner_staff_screen.dart';
import '../tasks/owner_tasks_screen.dart';

/// THE OWNER'S FIFTH TAB, WHICH IS A MENU NOW.
///
/// owner_tabs.dart used to say: "More was the only tab with nothing behind it... Putting it
/// behind a menu with one item in it would be a speed bump on the only route to it, so More
/// lands directly on the screen for now. The moment a second thing belongs here, this becomes a
/// small menu and the index stays where it is."
///
/// That moment is 2026-09-12. Tasks belong here — the owner assigns them and the manager works
/// them, and none of the other four tabs is about that.
///
/// ONE ROW PER DESTINATION, EACH SAYING WHAT IS BEHIND IT. A menu of bare nouns makes somebody
/// tap three things to find the one they meant; the second line is what stops that.
class OwnerMoreScreen extends ConsumerWidget {
  const OwnerMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    // Null while the owner's hostel list is in flight, and for an owner with no PG at all. The
    // destinations handle that themselves — each says which PG it is about — so this menu does
    // not gate on it.
    final hostelId = ref.watch(activeHostelIdProvider);

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
                      Text(
                        'More',
                        style: t.textTheme.titleLarge?.copyWith(color: t.colorScheme.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Staff and jobs',
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
            child: ListView(
              padding: const EdgeInsets.all(Space.md),
              children: [
                _MoreRow(
                  domain: NivoraDomain.people,
                  icon: Icons.badge_outlined,
                  title: 'Staff accounts',
                  detail: 'Managers and wardens — up to five of each, each with their own login',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const OwnerStaffScreen()),
                  ),
                ),
                const SizedBox(height: Space.sm),
                _MoreRow(
                  domain: NivoraDomain.complaints,
                  icon: Icons.checklist_rounded,
                  title: 'Tasks',
                  detail: hostelId == null
                      ? 'Jobs you put on your manager, with a due date and a status'
                      : 'Jobs you put on your manager — assign one, and see what came back',
                  onTap: () => Navigator.of(context).push(OwnerTasksScreen.route()),
                ),
                const SizedBox(height: Space.sm),
                _MoreRow(
                  domain: NivoraDomain.money,
                  icon: Icons.bar_chart_rounded,
                  title: 'Expenses month by month',
                  detail: 'What this PG spends, next to the months before it',
                  onTap: () =>
                      Navigator.of(context).push(ExpenseStatsScreen.route(hostelId)),
                ),
                const SizedBox(height: Space.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One destination: a tap target the width of the screen, with the area's own colour on the
/// glyph so the menu reads as a map rather than as a list of words.
class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.domain,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final NivoraDomain domain;
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: GlassWeight.regular.surfaceOf(t.colorScheme),
      borderRadius: Radii.rCard,
      child: InkWell(
        borderRadius: Radii.rCard,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            borderRadius: Radii.rCard,
            border: Border.all(
              color: t.colorScheme.outlineVariant,
              width: Strokes.hairline,
            ),
          ),
          child: Row(
            children: [
              DomainIcon(domain: domain, icon: icon, size: DomainIconSize.sm),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.textTheme.titleMedium),
                    const SizedBox(height: Space.xxs / 2),
                    Text(detail, style: t.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              Icon(Icons.chevron_right_rounded,
                  size: IconSize.lg, color: t.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
