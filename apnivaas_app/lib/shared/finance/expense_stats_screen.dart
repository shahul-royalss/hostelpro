library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../glass/glass.dart';
import 'expense_stats_view.dart';

/// THE EXPENSE CHARTS, ON THEIR OWN SCREEN, FOR BOTH ROLES THAT MAY SEE THEM.
///
/// The owner reaches it from More; the manager from the Expenses tab. It is the same screen for
/// both because it is the same question over the same figures — `expenses_select` admits the
/// hostel's owner and its manager and nobody else — so two screens would only be two places for
/// the same numbers to drift apart.
///
/// ── WHY A SCREEN AND NOT A PANEL ON THE LIST ─────────────────────────────────────────────
///
/// The manager's Expenses tab is a working ledger: a filter strip and a paginated list, opened
/// to find one entry or to add one. A twelve-month chart above that would push the first row
/// below the fold on every visit, for the sake of something read once a week. The owner has no
/// expense list at all, so a panel there would have nothing to sit on.
///
/// ── TWELVE MONTHS, AND NO SELECTOR ───────────────────────────────────────────────────────
///
/// A "6 / 12 months" control would be a preference to set before the question can be asked. A
/// year is what "compares other months" means for a PG — it covers the season a hostel empties
/// and the month the rent went up — and twelve bars fit a phone. The RPC clamps to 24 anyway.
class ExpenseStatsScreen extends ConsumerWidget {
  const ExpenseStatsScreen({super.key, required this.hostelId, this.hostelName});

  /// Null while the owner's hostel list is in flight, and for an owner holding no PG. The
  /// screen says so rather than the menu row disabling itself: a row that greys out reads as a
  /// feature that is missing, where this reads as a step that has not been taken.
  final String? hostelId;

  /// Shown under the title when the caller knows it. An owner holds several PGs, so which one
  /// this is about is not obvious from the figures alone.
  final String? hostelName;

  static Route<void> route(String? hostelId, {String? hostelName}) =>
      MaterialPageRoute<void>(
        builder: (_) => ExpenseStatsScreen(hostelId: hostelId, hostelName: hostelName),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final id = hostelId;

    return Scaffold(
      body: Column(
        children: [
          GlassHeader(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: Space.xxs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Expenses month by month',
                        style: t.textTheme.titleLarge?.copyWith(color: t.colorScheme.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        hostelName ?? 'This PG',
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
                if (id == null)
                  const StateCard(
                    badge: 'NO PG SELECTED',
                    child: Text(
                      'These figures belong to one PG. Pick one on the PGs tab first.',
                    ),
                  )
                else ...[
                  ExpenseStatsView(hostelId: id, months: 12),
                  const SizedBox(height: Space.md),
                  // SAID ONCE, HERE, RATHER THAN UNDER EVERY FIGURE. Rent is collected into
                  // public.fee_payments by the warden and is not an expense — a manager cannot
                  // read that table at all. Somebody reading a spending chart is entitled to
                  // know what it does not contain.
                  FlatSurface(
                    weight: GlassWeight.regular,
                    borderRadius: Radii.rControl,
                    padding: const EdgeInsets.all(Space.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: IconSize.sm, color: context.tones.muted),
                        const SizedBox(width: Space.xs),
                        Expanded(
                          child: Text(
                            'Money out only. Rent collected from residents is a separate '
                            'ledger and is not in these bars.',
                            style: t.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: Space.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
