/// R4.1: "Set rent for N new residents" — residents with no monthly rent yet. No dues are
/// created for them until it is set (docs/round4-api.md).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/tenant_admin.dart';
import '../../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../../data/repositories/tenant_admin_repository.dart';
import '../../../shared/clay/clay.dart';
import '../actions/rent_sheet.dart';

List<RentlessResident> _forHostel(List<RentlessResident> all, String? hostelId) =>
    hostelId == null ? all : [for (final r in all) if (r.hostelId == hostelId) r];

/// The home card; hidden while nobody needs rent (or the list cannot be read).
class RentNeededEntry extends ConsumerWidget {
  const RentNeededEntry({super.key, this.hostelId, this.padding = EdgeInsets.zero});

  /// Null: every PG of the caller.
  final String? hostelId;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(rentlessResidentsProvider).value ?? const <RentlessResident>[];
    final count = _forHostel(all, hostelId).length;
    if (count == 0) return const SizedBox.shrink();
    final title = count == 1 ? 'Set rent for 1 new resident' : 'Set rent for $count new residents';
    return Padding(
      padding: padding,
      child: ListRowCard(
        key: const ValueKey('rent-needed-card'),
        icon: ClayIcons.rentReminder,
        title: title,
        subtitle: 'No dues are created until their monthly rent is set',
        trailing: CountBadge(count: count, semanticLabel: '$count without rent'),
        semanticLabel: title,
        onTap: () => Navigator.of(context).push(RentNeededScreen.route(hostelId)),
      ),
    );
  }
}

class RentNeededScreen extends ConsumerWidget {
  const RentNeededScreen({super.key, this.hostelId});
  final String? hostelId;

  static Route<void> route(String? hostelId) =>
      MaterialPageRoute(builder: (_) => RentNeededScreen(hostelId: hostelId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final rows = ref.watch(rentlessResidentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Set monthly rent')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(rentlessResidentsProvider.future),
        child: rows.when(
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.md),
            child: ListSkeleton(rows: 4, semanticLabel: 'Loading residents'),
          ),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(Space.md),
            children: [
              Text(e is SignupFailure ? e.message : 'Could not load the residents.',
                  style: t.textTheme.bodyMedium),
              TextButton(
                onPressed: () => ref.invalidate(rentlessResidentsProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
          data: (all) {
            final list = _forHostel(all, hostelId);
            if (list.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(Space.md),
                children: const [
                  EmptyState(
                    icon: ClayIcons.success,
                    title: 'Every resident has a rent',
                    body: 'New residents appear here until you set their monthly rent.',
                  ),
                ],
              );
            }
            final manyPgs = list.map((r) => r.hostelId).toSet().length > 1;
            return ListView(
              padding: const EdgeInsets.all(Space.md),
              children: [
                const InfoNote(
                  icon: Icons.info_outline_rounded,
                  message: 'Rent is billed from the month they checked in. Payments cannot be '
                      'recorded until it is set.',
                ),
                const SizedBox(height: Space.md),
                ListGroup(children: [
                  for (final r in list)
                    ListRow(
                      key: ValueKey('rentless-${r.studentId}'),
                      avatarName: r.fullName,
                      title: r.fullName,
                      subtitle: [
                        if (manyPgs) ?r.hostelName,
                        if (r.roomNumber != null)
                          'Room ${r.roomNumber}${r.bedNumber == null ? '' : ' · bed ${r.bedNumber}'}'
                        else
                          'No bed yet',
                      ].join(' · '),
                      onTap: () => editRent(
                        context,
                        studentId: r.studentId,
                        studentName: r.fullName,
                        currentFee: 0,
                      ),
                    ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}
