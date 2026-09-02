library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../common/refresh.dart';
import 'widgets/common.dart';
import 'widgets/format.dart';
import 'widgets/menu.dart';

/// The week's food, as a resident reads it.
///
/// READS: public.menus, through `weeklyMenuProvider` → `MenuRepository.weeklyMenu`. The same
/// provider instance, with the same family key, that the manager's Menu tab writes through —
/// one definition of what is being served, so the screen the kitchen types into and the screen
/// the residents read cannot drift apart.
///
/// ONE REQUEST FOR THE WHOLE WEEK, AND NOTHING POLLS. The unique index on
/// (hostel_id, day_of_week, meal) caps this table at 28 rows per hostel, so the week is one
/// select — never one per day — and it is re-read when a resident pulls to refresh, opens the
/// app, or comes back to it. A mess menu changes when a manager changes it; a screen that
/// re-asked every few seconds would be spending a resident's mobile data to watch a list that
/// moves once a week.
///
/// TODAY FIRST. The days are rotated so the card a resident wants is the one under their thumb,
/// and the rest of the week reads forward from it. They are labelled by WEEKDAY and never by
/// date: `menus` has no date column, Monday has exactly one row forever, and printing
/// "8 Sep" over it would attach this week's calendar to a row that does not belong to a week.
class StudentMenuScreen extends StatelessWidget {
  const StudentMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResidentBuilder(builder: (context, ref, me) => _Menu(hostelId: me.hostelId));
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = weeklyMenuProvider(hostelId);
    final menu = ref.watch(provider);
    final today = MenuDay.of(DateTime.now());
    final t = Theme.of(context);

    return RefreshIndicator(
      // BOUNDED, and it reports its own failure. The week stays on screen through a failed
      // reload (AsyncSection keeps the last value), so the gesture is the only thing that can
      // say the pull did not land. See features/common/refresh.dart.
      onRefresh: () {
        ref.invalidate(provider);
        return settleRefresh(context, () => ref.read(provider.future));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AsyncSection<WeeklyMenu>(
            value: menu,
            onRetry: () => ref.invalidate(provider),
            loading: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonCard(lines: 4),
                SizedBox(height: Space.sm),
                SkeletonCard(lines: 4),
              ],
            ),
            builder: (week) {
              // NOTHING AT ALL IS ITS OWN STATE. Seven cards each saying "no menu set" is a
              // wall of the same sentence; one card says it once and names who fills it in.
              if (week.isEmpty) {
                return const EmptyNote(
                  icon: Icons.restaurant_menu_rounded,
                  title: 'No menu put up yet',
                  message: 'Your hostel manager writes the week here. Nothing has been '
                      'entered for any day so far.',
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final day in weekFrom(today)) ...[
                    DayMenuCard(day: day, week: week, isToday: day == today),
                    const SizedBox(height: Space.sm),
                  ],
                  if (week.lastUpdated != null) ...[
                    const SizedBox(height: Space.xs),
                    Text(
                      // A real column (`max(updated_at)` across the rows this device holds),
                      // not "up to date". It answers the one question a resident has about a
                      // menu they suspect is stale.
                      'Menu last changed ${dayLabel(week.lastUpdated!.toLocal())}',
                      style: t.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
