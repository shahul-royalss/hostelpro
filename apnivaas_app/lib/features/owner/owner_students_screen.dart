library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay.dart';
import '../../shared/glass/glass.dart';
import 'owner_format.dart';
import 'owner_providers.dart';
import 'owner_tabs.dart';
import '../shell/join_requests.dart';
import 'requests/staff_requests.dart';
import '../../shared/person_avatar.dart';
import 'staff/owner_staff_screen.dart';
import 'widgets/owner_header.dart';
import 'widgets/states.dart' show EmptyNote, ErrorNote, whenAsync;
import '../../data/repositories/tenant_admin_repository.dart' show tenantProfileProvider;
import '../warden/actions/rent_sheet.dart' show editRent;
import '../warden/students/edit_tenant_sheet.dart' show showEditTenantSheet;

/// EVERY RESIDENT, AND WHAT EACH ONE HAS PAID — the People tab.
///
/// The shell draws the forest header ("Residents", and the PG). Under it, first, the way into
/// staff accounts: the people who work here sit next to the people who live here, which is where
/// an owner looks for them.
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

  /// The search field's focus, so the home header's search pill can land the owner in it.
  final _searchFocus = FocusNode(debugLabel: 'Resident search');
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
    // The search pill on Home may have asked before this tab existed — an IndexedStack builds a
    // tab the first time it is shown — so the request is read once here as well as listened for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(ownerSearchRequestProvider)) _focusSearch();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Puts the cursor in the search field and clears the request. A field that has not been
  /// built yet — the roster still loading — takes the focus the moment it attaches.
  void _focusSearch() {
    ref.read(ownerSearchRequestProvider.notifier).consume();
    _searchFocus.requestFocus();
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
    // After the frame, not inside the notification: by then the shell has switched to this tab,
    // and a tab that is not selected cannot take focus (IndexedStack excludes it).
    ref.listen<bool>(ownerSearchRequestProvider, (_, asked) {
      if (!asked) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusSearch();
      });
    });
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
            child: const EmptyState(
              icon: ClayIcons.rooms,
              title: 'No PG on your account yet',
              body: 'Residents appear here once a PG is registered against your account.',
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
          searchFocus: _searchFocus,
          onSearchChanged: _onSearchChanged,
          term: _term,
          page: page,
        ),
      ),
    );
  }
}

/// The roster's page when it has one thing to say — loading, failed, no PG. The way into staff
/// accounts stays at the top whatever state the roster is in: who works here does not depend on
/// whether the residents loaded.
class _Page extends StatelessWidget {
  const _Page({required this.child, required this.controller});
  final Widget child;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => ListView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: OwnerRhythm.pagePadding,
        children: [
          const JoinRequestsEntry(padding: EdgeInsets.only(bottom: Space.sm)),
          const StaffRequestsEntry(padding: EdgeInsets.only(bottom: Space.sm)),
          const _StaffEntry(),
          const SizedBox(height: OwnerRhythm.sectionGap),
          child,
        ],
      );
}

/// Managers and wardens, one tap from the residents. The same screen More opens.
class _StaffEntry extends StatelessWidget {
  const _StaffEntry();

  @override
  Widget build(BuildContext context) => ListRowCard(
        icon: ClayIcons.team,
        title: 'Staff accounts',
        subtitle: 'The managers and wardens who run this PG',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const OwnerStaffScreen()),
        ),
      );
}

class _Roster extends StatelessWidget {
  const _Roster({
    required this.controller,
    required this.search,
    required this.searchFocus,
    required this.onSearchChanged,
    required this.term,
    required this.page,
  });

  final ScrollController controller;
  final TextEditingController search;
  final FocusNode searchFocus;
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
      padding: OwnerRhythm.pagePadding,
      children: [
        const JoinRequestsEntry(padding: EdgeInsets.only(bottom: Space.sm)),
        const StaffRequestsEntry(padding: EdgeInsets.only(bottom: Space.sm)),
        const _StaffEntry(),
        const SizedBox(height: OwnerRhythm.sectionGap),
        TextField(
          controller: search,
          focusNode: searchFocus,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search by name or phone',
            prefixIcon: Icon(Icons.search_rounded, size: IconSize.lg),
          ),
        ),
        const SizedBox(height: Space.md),
        if (rows.isEmpty)
          if (term.isEmpty)
            // The clay art says "there is nothing here yet", which is true on the first run.
            const EmptyState(
              icon: ClayIcons.addTenant,
              title: 'No residents yet',
              body: 'Residents appear here as your warden registers them at the desk.',
            )
          else
            // A search miss keeps the plain glyph: the art would be a lie over "no match for
            // that", and conflating the two is how an owner concludes their PG is empty when
            // they have merely mistyped a name.
            EmptyNote(
              icon: Icons.search_off_rounded,
              title: 'Nobody matches “$term”',
              message: 'Search covers name and phone number. Clear it to see everyone.',
            )
        else ...[
          SectionHeader(
            title: '${countLabel(rows.length, 'resident')} shown',
            size: SectionHeaderSize.card,
          ),
          const SizedBox(height: OwnerRhythm.headingGap),
          ListGroup(children: [for (final s in rows) _StudentRow(student: s)]),
          if (page.hasMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.md),
              child: Center(
                child: SizedBox.square(
                  dimension: IconSize.action,
                  child: CircularProgressIndicator(strokeWidth: Strokes.focus),
                ),
              ),
            )
          else if (rows.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Text(
                'That is everyone.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ],
    );
  }
}

/// One resident, as much as fits on a line a thumb can hit: who, how to reach them, whether
/// they are still here, and what their rent is.
class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    final s = student;
    final (label, tone) = switch (s.status) {
      StudentStatus.active => ('Active', StatusTone.success),
      StudentStatus.onLeave => ('On leave', StatusTone.warning),
      StudentStatus.vacated => ('Checked out', StatusTone.neutral),
    };

    return ListRow(
      leading: PersonAvatar(name: s.fullName, userId: s.userId),
      title: s.fullName,
      subtitle: s.phone,
      // The monthly rent with the resident's status under it — the rent they owe each month,
      // not anything they have paid; the sheet behind the row has the payments.
      trailing: ListRowAmount(amount: money(s.monthlyFee), status: label, tone: tone),
      onTap: () => showStudentDetail(context, s),
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
            InitialsDisc(name: s.fullName),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(s.fullName, style: t.textTheme.titleLarge, maxLines: 2),
                  ),
                  const SizedBox(height: Space.xxs),
                  Text(
                    'Joined ${dayLabel(s.dateOfJoining)}',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (s.isResident) ...[
          const SizedBox(height: Space.md),
          // R4.1 / R4.2: the owner edits the same details and rent as the warden. This sheet
          // shows a snapshot, so it closes after a save and the list re-reads.
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('owner-edit-tenant'),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final saved = await showEditTenantSheet(context,
                      studentId: s.id, studentName: s.fullName);
                  if (saved) {
                    ref.invalidate(studentsProvider);
                    nav.maybePop();
                  }
                },
                icon: const Icon(Icons.edit_note_rounded, size: IconSize.md),
                label: const Text('Edit details'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('owner-edit-rent'),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final change = await editRent(context,
                      studentId: s.id,
                      studentName: s.fullName,
                      currentFee: s.monthlyFee,
                      currentDueDay: ref.read(tenantProfileProvider(s.id)).value?.rentDueDay);
                  if (change != null) nav.maybePop();
                },
                icon: const Icon(Icons.currency_rupee_rounded, size: IconSize.md),
                label: Text(s.monthlyFee > 0 ? 'Change rent' : 'Set rent'),
              ),
            ],
          ),
        ],
        const SizedBox(height: Space.lg),

        const SectionHeader(title: 'Contact', size: SectionHeaderSize.form),
        const SizedBox(height: Space.xs),
        _Fact(label: 'Phone', value: s.phone),
        _Fact(label: 'Email', value: s.email),
        _Fact(label: 'Permanent address', value: s.permanentAddress),

        const SizedBox(height: Space.md),
        const SectionHeader(title: 'Next of kin', size: SectionHeaderSize.form),
        const SizedBox(height: Space.xs),
        _Fact(label: 'Guardian', value: s.guardianName),
        _Fact(label: 'Guardian phone', value: s.guardianPhone),

        const SizedBox(height: Space.md),
        const SectionHeader(title: 'Tenancy', size: SectionHeaderSize.form),
        const SizedBox(height: Space.xs),
        _Fact(label: 'Monthly rent', value: money(s.monthlyFee)),
        _Fact(label: 'ID proof', value: s.idProofType),
        // The room and bed are ids on this row, not numbers. Rendering a uuid would be worse
        // than saying nothing, and resolving them is a second query this sheet does not make —
        // the warden's roster is where placement is managed and shown.
        _Fact(label: 'Placed', value: s.bedId == null ? 'No bed assigned' : 'Bed assigned'),
        if (s.vacatedAt != null) _Fact(label: 'Checked out', value: dayLabel(s.vacatedAt!)),

        const SizedBox(height: Space.lg),
        const SectionHeader(title: 'Transactions', size: SectionHeaderSize.form),
        const SizedBox(height: Space.xs),
        whenAsync(
          history,
          loading: () =>
              const ListSkeleton(rows: 2, leading: false, semanticLabel: 'Loading transactions'),
          error: (error) => ErrorNote(
            error: error,
            compact: true,
            onRetry: () => ref.invalidate(studentFeeHistoryProvider(s.id)),
          ),
          data: (page) => page.items.isEmpty
              ? const EmptyState(
                  compact: true,
                  icon: ClayIcons.receipt,
                  title: 'Nothing recorded yet',
                  // Not "has not paid" — an empty ledger and an unpaid month are different
                  // facts, and only the warden's desk creates the first row either way.
                  body: 'Payments appear here once your warden records one at the desk.',
                )
              : ListGroup(children: [for (final f in page.items) _FeeRow(fee: f)]),
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
            child: Text(
              label,
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              shown.isEmpty ? 'Not recorded' : shown,
              // The muted ink, not the control border: an absence is still words to read.
              style: shown.isEmpty
                  ? t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)
                  : t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface),
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
    final f = fee;
    final (label, tone) = switch (f.status) {
      FeeStatus.paid => ('Paid', StatusTone.success),
      FeeStatus.partial => ('Part paid', StatusTone.warning),
      FeeStatus.unpaid => ('Unpaid', StatusTone.error),
    };

    return ListRow(
      title: monthLabel(f.periodMonth),
      // Both figures, always: "₹6,500 of ₹9,500" is the whole story of a part payment, and
      // showing only what was paid hides the shortfall.
      subtitle: '${money(f.amountPaid)} of ${money(f.amountDue)}'
          '${f.paidOn == null ? '' : ' · ${dayLabel(f.paidOn!)}'}',
      trailing: StatusChip(label: label, tone: tone),
    );
  }
}

class _RosterSkeleton extends StatelessWidget {
  const _RosterSkeleton();

  @override
  Widget build(BuildContext context) =>
      const ListSkeleton(rows: 5, semanticLabel: 'Loading residents');
}
