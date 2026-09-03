library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import '../../shared/illustrations.dart';
import 'owner_format.dart';
import 'owner_providers.dart';
import 'widgets/states.dart';

/// EVERY RESIDENT, AND WHAT EACH ONE HAS PAID.
///
/// The owner's tab 2 was a placeholder until now — the shell drew "This screen is not built
/// yet" over it, which is exactly what the product owner photographed.
///
/// ── WHY THIS IS NOT THE WARDEN'S ROSTER WITH A DIFFERENT COLOUR ───────────────────────────
///
/// The warden's students screen is a WORKING tool: it registers people, assigns beds, records
/// payments, checks residents out. This one is a READING tool. An owner is not at the desk; the
/// questions they ask on a phone are "who lives here", "who is this person", and "has this one
/// actually paid". So there is no action on this screen at all — no register button, no bed
/// assignment, no payment entry. Every one of those already exists on the warden's side, where
/// the person doing it is standing in front of the resident.
///
/// That is a deliberate refusal, not an omission. An owner recording a payment from home,
/// against a resident they cannot see, is how a ledger stops matching the cash box.
///
/// ── READS ─────────────────────────────────────────────────────────────────────────────────
///
/// public.students (via studentsProvider, paged, RLS-scoped to the owner's hostel) and
/// public.fee_payments (via studentFeeHistoryProvider, one resident at a time, opened only when
/// a row is tapped). The fee history is NOT fetched for the list — twenty residents would be
/// twenty extra round trips to render a column nobody has asked for yet.
class OwnerStudentsScreen extends ConsumerStatefulWidget {
  const OwnerStudentsScreen({super.key});

  @override
  ConsumerState<OwnerStudentsScreen> createState() => _OwnerStudentsScreenState();
}

class _OwnerStudentsScreenState extends ConsumerState<OwnerStudentsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  /// The term actually sent to Postgres. Distinct from the field's text because each value is
  /// a distinct provider family key — a distinct cache entry and a distinct request. Typing
  /// "Sharma" un-debounced is six queries and five wasted caches, which is the same reasoning
  /// the warden's roster documents.
  String _term = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final near = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 320;
    if (!near) return;
    final hostelId = ref.read(activeHostelIdProvider);
    if (hostelId == null) return;
    // loadMore is a no-op past the last page, so an eager scroll cannot over-fetch.
    unawaited(ref.read(studentsProvider(_query(hostelId)).notifier).loadMore());
  }

  StudentQuery _query(String hostelId) => StudentQuery(
        hostelId: hostelId,
        search: _term.isEmpty ? null : _term,
      );

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final next = raw.trim();
      if (next == _term) return;
      setState(() => _term = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hostelId = ref.watch(activeHostelIdProvider);
    final owned = ref.watch(myHostelsProvider);

    // The same triage the dashboard and the payments tab do: "no PG resolved yet" is three
    // different facts and only one of them is an error.
    if (hostelId == null) {
      return switch (owned) {
        AsyncError(:final error) => _Page(
            controller: _scroll,
            child: ErrorNote(error: error, onRetry: () => ref.invalidate(myHostelsProvider)),
          ),
        AsyncData() => _Page(
            controller: _scroll,
            child: const EmptyNote(
              icon: Icons.apartment_rounded,
              title: 'No PG on your account yet',
              message: 'Residents appear here once a PG is registered against your account.',
            ),
          ),
        _ => _Page(controller: _scroll, child: const _RosterSkeleton()),
      };
    }

    final query = _query(hostelId);
    final students = ref.watch(studentsProvider(query));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(studentsProvider(query));
        try {
          await ref.read(studentsProvider(query).future).timeout(ownerRefreshTimeout);
        } catch (_) {
          // Rendered by the body below. Rethrowing here would turn a handled failure into a
          // crash, and the spinner has already retracted by the time it would land.
        }
      },
      child: whenAsync(
        students,
        loading: () => _Page(controller: _scroll, child: const _RosterSkeleton()),
        error: (error) => _Page(
          controller: _scroll,
          child: ErrorNote(
            error: error,
            onRetry: () => ref.invalidate(studentsProvider(query)),
          ),
        ),
        data: (page) => _Roster(
          controller: _scroll,
          search: _search,
          onSearchChanged: _onSearchChanged,
          term: _term,
          page: page,
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.child, required this.controller});
  final Widget child;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => ListView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
        children: [child],
      );
}

class _Roster extends StatelessWidget {
  const _Roster({
    required this.controller,
    required this.search,
    required this.onSearchChanged,
    required this.term,
    required this.page,
  });

  final ScrollController controller;
  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;
  final String term;
  final PagedResult<Student> page;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rows = page.items;

    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
      children: [
        TextField(
          controller: search,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search by name or phone',
            prefixIcon: Icon(Icons.search_rounded, size: IconSize.md),
          ),
        ),
        const SizedBox(height: Space.md),
        if (rows.isEmpty)
          EmptyNote(
            icon: term.isEmpty ? Icons.people_outline_rounded : Icons.search_off_rounded,
            // Artwork for the first run, the glyph for a search miss. The drawing says "there
            // is nothing here yet", which would be a lie over "no match for that".
            illustration: term.isEmpty ? EmptyArt.residents : null,
            // The residents' own teal on the first-run state: it belongs to that area and is
            // neither good news nor bad. A search miss stays neutral — "no match" is a fact
            // about the search, not about the residents.
            tone: term.isEmpty ? NivoraDomain.people.tone : null,
            title: term.isEmpty ? 'No residents yet' : 'Nobody matches “$term”',
            // Two different facts, and conflating them is how an owner concludes their PG is
            // empty when they have merely mistyped a name.
            message: term.isEmpty
                ? 'Residents appear here as your warden registers them at the desk.'
                : 'Search covers name and phone number. Clear it to see everyone.',
          )
        else ...[
          SectionLabel(label: '${countLabel(rows.length, 'resident')} shown'),
          const SizedBox(height: Space.xs),
          for (final s in rows) ...[
            _StudentRow(student: s),
            const SizedBox(height: Space.xs),
          ],
          if (page.hasMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.md),
              child: Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (rows.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'That is everyone.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}

/// One resident, as much as fits on a line a thumb can hit.
class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final s = student;

    final (label, tone) = switch (s.status) {
      StudentStatus.active => ('Active', tones.success),
      StudentStatus.onLeave => ('On leave', tones.warning),
      StudentStatus.vacated => ('Checked out', t.colorScheme.outline),
    };

    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      onTap: () => showStudentDetail(context, s),
      semanticLabel: '${s.fullName}, $label',
      child: Row(
        children: [
          InitialsAvatar(name: s.fullName, muted: s.status == StudentStatus.vacated),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.fullName,
                    style: t.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.xxs),
                Text(
                  s.phone,
                  style: t.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusChip(label: label, tone: tone, dot: true),
              const SizedBox(height: Space.xxs),
              Text(money(s.monthlyFee), style: t.textTheme.bodySmall),
            ],
          ),
          Icon(Icons.chevron_right_rounded, color: t.colorScheme.outline),
        ],
      ),
    );
  }
}

/// The whole record, plus every rupee recorded against it.
void showStudentDetail(BuildContext context, Student student) {
  showGlassSheet<void>(
    context: context,
    builder: (_) => _StudentDetail(student: student),
  );
}

class _StudentDetail extends ConsumerWidget {
  const _StudentDetail({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final s = student;
    final history = ref.watch(studentFeeHistoryProvider(s.id));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InitialsAvatar(name: s.fullName, muted: s.status == StudentStatus.vacated),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.fullName, style: t.textTheme.titleLarge, maxLines: 2),
                  const SizedBox(height: Space.xxs),
                  Text('Joined ${dayLabel(s.dateOfJoining)}', style: t.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),

        SectionLabel(label: 'Contact'),
        const SizedBox(height: Space.xs),
        _Fact(label: 'Phone', value: s.phone),
        _Fact(label: 'Email', value: s.email),
        _Fact(label: 'Permanent address', value: s.permanentAddress),

        const SizedBox(height: Space.md),
        SectionLabel(label: 'Next of kin'),
        const SizedBox(height: Space.xs),
        _Fact(label: 'Guardian', value: s.guardianName),
        _Fact(label: 'Guardian phone', value: s.guardianPhone),

        const SizedBox(height: Space.md),
        SectionLabel(label: 'Tenancy'),
        const SizedBox(height: Space.xs),
        _Fact(label: 'Monthly rent', value: money(s.monthlyFee)),
        _Fact(label: 'ID proof', value: s.idProofType),
        // The room and bed are ids on this row, not numbers. Rendering a uuid would be worse
        // than saying nothing, and resolving them is a second query this sheet does not make —
        // the warden's roster is where placement is managed and shown.
        _Fact(label: 'Placed', value: s.bedId == null ? 'No bed assigned' : 'Bed assigned'),
        if (s.vacatedAt != null) _Fact(label: 'Checked out', value: dayLabel(s.vacatedAt!)),

        const SizedBox(height: Space.lg),
        SectionLabel(label: 'Transactions'),
        const SizedBox(height: Space.xs),
        whenAsync(
          history,
          loading: () => const SkeletonCard(lines: 3),
          error: (error) => ErrorNote(
            error: error,
            compact: true,
            onRetry: () => ref.invalidate(studentFeeHistoryProvider(s.id)),
          ),
          data: (page) => page.items.isEmpty
              ? const EmptyNote(
                  icon: Icons.receipt_long_outlined,
                  title: 'Nothing recorded yet',
                  // Not "has not paid" — an empty ledger and an unpaid month are different
                  // facts, and only the warden's desk creates the first row either way.
                  message: 'Payments appear here once your warden records one at the desk.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final f in page.items) ...[
                      _FeeRow(fee: f),
                      const SizedBox(height: Space.xs),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// One labelled fact. Absent values say so rather than collapsing, because a missing guardian
/// phone is information an owner wants to see.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final shown = (value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(label, style: t.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              shown.isEmpty ? 'Not recorded' : shown,
              style: shown.isEmpty
                  ? t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline)
                  : t.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({required this.fee});
  final FeePayment fee;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final f = fee;

    final (label, tone) = switch (f.status) {
      FeeStatus.paid => ('Paid', tones.success),
      FeeStatus.partial => ('Part paid', tones.warning),
      FeeStatus.unpaid => ('Unpaid', tones.error),
    };

    return FlatSurface(
      padding: const EdgeInsets.all(Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(monthLabel(f.periodMonth), style: t.textTheme.titleMedium),
                const SizedBox(height: Space.xxs),
                Text(
                  // Both figures, always: "₹6,500 of ₹9,500" is the whole story of a part
                  // payment, and showing only what was paid hides the shortfall.
                  '${money(f.amountPaid)} of ${money(f.amountDue)}'
                  '${f.paidOn == null ? '' : ' · ${dayLabel(f.paidOn!)}'}',
                  style: t.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          StatusChip(label: label, tone: tone),
        ],
      ),
    );
  }
}

class _RosterSkeleton extends StatelessWidget {
  const _RosterSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonCard(lines: 1, height: 56),
          SizedBox(height: Space.md),
          SkeletonCard(lines: 2, height: 76),
          SizedBox(height: Space.xs),
          SkeletonCard(lines: 2, height: 76),
          SizedBox(height: Space.xs),
          SkeletonCard(lines: 2, height: 76),
        ],
      );
}
