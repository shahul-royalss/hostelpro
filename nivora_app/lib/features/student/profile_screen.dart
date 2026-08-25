library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final contacts = ref.watch(hostelContactsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        refreshStudentData(ref);
        await awaitStudentRefresh(ref);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _Identity(me: me),

          const SizedBox(height: Space.xl),
          const SectionHeading(title: 'Your room'),
          AsyncSection<FeeLedgerRow?>(
            value: rent,
            onRetry: () => ref.invalidate(myRentThisMonthProvider),
            // NO `roommates:` HERE, unlike Home. The roommate read has its own section
            // immediately below, and it is the better one: it names the people rather than
            // counting them. Passing the count as well would draw one read twice — a summary
            // line and a list of the same names on a good day, and on a bad one the same
            // failure said twice in a row.
            builder: (row) => RoomBedCard(
              roomNumber: row?.roomNumber,
              bedNumber: row?.bedNumber,
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
            caption: 'Recorded by your warden. Ask at the office to change any of it.',
          ),
          OutlineCard(
            child: Column(
              children: [
                DetailRow(label: 'Full name', value: me.fullName),
                DetailRow(label: 'Phone', value: me.phone),
                DetailRow(label: 'Email', value: me.email),
                DetailRow(label: 'Joined', value: dayLabel(me.dateOfJoining)),
                DetailRow(label: 'Agreed rent', value: '${rupees(me.monthlyFee)} a month'),
                DetailRow(label: 'Guardian', value: me.guardianName),
                DetailRow(label: 'Guardian phone', value: me.guardianPhone),
                DetailRow(label: 'Address', value: me.permanentAddress),
                DetailRow(label: 'ID proof', value: me.idProofType),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeading(title: 'Your hostel'),
          AsyncSection<HostelContacts?>(
            value: contacts,
            onRetry: () => ref.invalidate(hostelContactsProvider),
            builder: (card) => card == null
                ? const EmptyNote(
                    icon: Icons.apartment_outlined,
                    title: 'Hostel details unavailable',
                    message: 'Pull down to try again.',
                    tone: NivoraColors.textMuted,
                  )
                : _HostelCard(contacts: card),
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
        // than none.
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // The tint comes from the one place the alphas were measured. 0.12 was invented
            // here, beside a chipFill that is 0.08 on light and 0.10 on dark — and it is the
            // dark number that matters, because a tint lightens a dark fill toward the text
            // sitting on it, which is why the measured value is the smaller one.
            color: context.tones.chipFill(t.colorScheme.primary),
          ),
          child: Text(_initials(me.fullName), style: t.textTheme.titleLarge),
        ),
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

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

class _Roommates extends StatelessWidget {
  const _Roommates({required this.mates});
  final List<Roommate> mates;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (mates.isEmpty) {
      return const EmptyNote(
        icon: Icons.person_outline_rounded,
        title: 'No roommates listed',
        message: 'Either you have the room to yourself, or you have not been placed in one yet.',
        tone: NivoraColors.textMuted,
      );
    }
    return OutlineCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SHARING WITH YOU', style: t.textTheme.labelSmall),
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

class _HostelCard extends StatelessWidget {
  const _HostelCard({required this.contacts});
  final HostelContacts contacts;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rules = contacts.rules?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlineCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(contacts.hostelName, style: t.textTheme.titleMedium),
              if (contacts.address != null) ...[
                const SizedBox(height: Space.xxs),
                SelectionArea(
                  child: Text(contacts.address!, style: t.textTheme.bodyMedium),
                ),
              ],
              const SizedBox(height: Space.sm),
              Divider(color: t.colorScheme.outlineVariant),
              const SizedBox(height: Space.xs),
              // Names and numbers come from st_hostel_contacts(), a SECURITY DEFINER function,
              // because a resident cannot read public.users at all (§4.8). A join would have
              // been refused; this hands back exactly the fields they are allowed to have.
              DetailRow(
                label: 'Warden',
                value: _person(contacts.wardenName, contacts.wardenPhone),
                missing: 'No warden listed',
              ),
              DetailRow(
                label: 'Manager',
                value: _person(contacts.managerName, contacts.managerPhone),
                missing: 'No manager listed',
              ),
              DetailRow(
                label: 'Owner',
                value: contacts.ownerName,
                missing: 'Not listed',
              ),
            ],
          ),
        ),
        if (rules != null && rules.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          OutlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HOSTEL RULES', style: t.textTheme.labelSmall),
                const SizedBox(height: Space.xs),
                SelectionArea(child: Text(rules, style: t.textTheme.bodyMedium)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// "Priya Nair · 9876500003", or just whichever half exists. A post can be vacant, and a
  /// staff member can be on record without a number.
  String? _person(String? name, String? phone) {
    if (name == null && phone == null) return null;
    if (phone == null) return name;
    if (name == null) return phone;
    return '$name · $phone';
  }
}
