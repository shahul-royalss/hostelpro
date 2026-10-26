library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../common/refresh.dart';
import '../../../shared/clay/clay.dart' show ListRowCard;
import '../../../shared/illustrations.dart';
import '../actions/register_student_sheet.dart';
import '../data/warden_providers.dart';
import '../widgets/paged_list.dart';
import '../widgets/warden_ui.dart';
import 'student_sheet.dart';
import '../../shell/join_requests.dart';
import '../checkout/warden_checkouts_screen.dart';
import '../../../shared/person_avatar.dart';

/// Everyone living here.
///
/// SEARCH IS DONE BY POSTGRES, NOT BY THIS WIDGET. StudentRepository.page sends the term as an
/// `ilike` over name and phone; filtering the fetched page in Dart would search only the twenty
/// rows already downloaded. On a seeded demo the two look identical, and on a real hostel of two
/// hundred residents the client-side version quietly fails to find anyone past the first page —
/// the exact bug that only shows up in production.
///
/// KEYSTROKES ARE DEBOUNCED because each distinct term is a distinct provider family key, which
/// is a distinct cache entry and a distinct request. Typing "Sharma" un-debounced is six
/// queries and five wasted caches.
enum _Roster {
  all('All'),
  active('Active'),
  onLeave('On leave'),
  vacated('Checked out');

  const _Roster(this.label);
  final String label;

  /// Null on [all], which the repository reads as "everyone except the checked-out".
  StudentStatus? get status => switch (this) {
        _Roster.all => null,
        _Roster.active => StudentStatus.active,
        _Roster.onLeave => StudentStatus.onLeave,
        _Roster.vacated => StudentStatus.vacated,
      };
}

class WardenStudentsScreen extends ConsumerStatefulWidget {
  const WardenStudentsScreen({super.key});

  @override
  ConsumerState<WardenStudentsScreen> createState() => _WardenStudentsScreenState();
}

class _WardenStudentsScreenState extends ConsumerState<WardenStudentsScreen> {
  final _controller = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  /// The term actually sent to Postgres. Lags the text field by [_settle].
  String _term = '';
  _Roster _roster = _Roster.all;

  static const _settle = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    // The home header's search pill may have asked before this tab existed — the shell builds a
    // tab the first time it is warmed or shown — so the request is read once here as well as
    // listened for in build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(wardenSearchRequestProvider)) _focusSearch();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Puts the cursor in the search field and clears the request.
  void _focusSearch() {
    ref.read(wardenSearchRequestProvider.notifier).consume();
    _searchFocus.requestFocus();
  }

  void _onSearchChanged(String value) {
    // Immediate, so the clear button appears as the warden types. The QUERY still waits for
    // [_settle] — this rebuild costs nothing, a request per keystroke costs data.
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(_settle, () {
      if (!mounted) return;
      final trimmed = value.trim();
      if (trimmed != _term) setState(() => _term = trimmed);
    });
  }

  @override
  Widget build(BuildContext context) {
    // After the frame, not inside the notification: by then the shell has switched to this tab,
    // and a tab that is not showing cannot take focus.
    ref.listen<bool>(wardenSearchRequestProvider, (_, asked) {
      if (!asked) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusSearch();
      });
    });
    final hostelId = ref.watch(currentHostelIdProvider);
    if (hostelId == null) {
      return const WardenScreen(
        title: 'Residents',
        child: WardenEmptyState(
          icon: Icons.people_alt_rounded,
          title: 'No hostel on this account',
          detail: 'A warden is attached to one hostel. Ask the owner to check the assignment.',
        ),
      );
    }

    final query = StudentQuery(
      hostelId: hostelId,
      search: _term.isEmpty ? null : _term,
      status: _roster.status,
    );
    final students = ref.watch(studentsProvider(query));

    // The design's list header carries a count on the right ("48 students", 4:759). The
    // repository pages, so a count is only TRUE once the last page is in — `hasMore` is the
    // server's own word for that. While more pages exist the right-hand slot is left empty
    // rather than reporting the twenty rows that happen to be downloaded. Nor does it say "0":
    // the empty state under it already says so in words.
    final page = students.value;
    final total = (page != null && !page.hasMore) ? page.items.length : null;

    return WardenScreen(
      title: 'Residents',
      subtitle: _term.isEmpty ? null : 'Matching "$_term"',
      actions: [
        HeaderAction(
          tooltip: 'Register a resident',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: () => showRegisterStudentSheet(context, hostelId: hostelId),
        ),
      ],
      child: PagedList<Student>(
        value: students,
        // See features/common/refresh.dart. The roster is kept on screen through a failed
        // reload, so the gesture has to report its own outcome or it reports nothing.
        onRefresh: () {
          ref.invalidate(studentsProvider(query));
          return settleRefresh(context, () => ref.read(studentsProvider(query).future));
        },
        onLoadMore: () => ref.read(studentsProvider(query).notifier).loadMore(),
        header: Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const JoinRequestsEntry(padding: EdgeInsets.only(bottom: Space.sm)),
              const CheckoutRequestsEntry(padding: EdgeInsets.only(bottom: Space.sm)),
              TextField(
                controller: _controller,
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by name or phone',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            _debounce?.cancel();
                            setState(() => _term = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: Space.xs),
              FilterBar<_Roster>(
                options: _Roster.values,
                selected: _roster,
                labelOf: (option) => option.label,
                onSelected: (option) => setState(() => _roster = option),
              ),
              // The heading names the list actually on screen, with its count opposite — so the
              // chips and the heading cannot say different things.
              SectionLabel(
                label: _roster == _Roster.all ? 'Living here' : _roster.label,
                trailing: total == null || total == 0
                    ? null
                    : Text(
                        countOf(total, 'resident'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            ],
          ),
        ),
        empty: WardenEmptyState(
          // The artwork is for the hostel that has nobody on it YET. A search that matched
          // nothing is a different sentence and keeps the glyph — see EmptyArt.
          illustration: _term.isEmpty ? EmptyArt.residents : null,
          icon: _term.isEmpty ? Icons.people_outline_rounded : Icons.search_off_rounded,
          title: _term.isEmpty ? 'Nobody on this list yet' : 'No match for "$_term"',
          detail: _term.isEmpty
              ? 'Register the first resident with the button at the top right.'
              : 'Search covers full name and phone number.',
        ),
        itemBuilder: (context, student) => _StudentRow(student: student),
      ),
    );
  }
}

class _StudentRow extends ConsumerWidget {
  const _StudentRow({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // students carries room_id, not a room number. The occupancy list is already loaded for the
    // room grid, so the number is looked up there rather than joined per row — and when it has
    // not loaded, the row says "Placed" instead of inventing one.
    String placement;
    if (student.roomId == null) {
      placement = student.isResident ? 'No bed yet' : 'Checked out';
    } else {
      final rooms = ref.watch(roomOccupancyProvider(student.hostelId)).value;
      final match = rooms?.where((r) => r.roomId == student.roomId);
      placement = (match != null && match.isNotEmpty) ? 'Room ${match.first.roomNumber}' : 'Placed';
    }

    // One card per resident: their initials, the name, ONE quiet line of where they sleep and
    // what they pay, and their state as a chip at the trailing edge. The design badges EVERY
    // row, including the ordinary one: a list where only the exceptions are marked makes a
    // reader check each unmarked row to see whether it is fine or whether the badge simply
    // failed to draw.
    //
    // THE PHONE NUMBER IS ON THE SHEET, one tap away, and the search field above this list
    // still matches on it.
    return ListRowCard(
      leading: PersonAvatar(name: student.fullName, userId: student.userId),
      title: student.fullName,
      subtitle: '$placement · ${money(student.monthlyFee)}',
      trailing: StatusPill(status: student.status),
      onTap: () => showStudentSheet(context, studentId: student.id),
      semanticLabel: '${student.fullName}, $placement, ${student.phone}, '
          '${student.status.label}',
    );
  }
}
