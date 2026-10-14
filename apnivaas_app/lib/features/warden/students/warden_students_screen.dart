library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../common/refresh.dart';
import '../../../shared/illustrations.dart';
import '../actions/register_student_sheet.dart';
import '../widgets/paged_list.dart';
import '../widgets/warden_ui.dart';
import 'student_sheet.dart';

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
  Timer? _debounce;

  /// The term actually sent to Postgres. Lags the text field by [_settle].
  String _term = '';
  _Roster _roster = _Roster.all;

  static const _settle = Duration(milliseconds: 350);

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
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
    final hostelId = ref.watch(currentHostelIdProvider);
    if (hostelId == null) {
      return const WardenScreen(
        title: 'Residents',
        child: EmptyState(
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
    // rather than reporting the twenty rows that happen to be downloaded.
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
              TextField(
                controller: _controller,
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
              const SizedBox(height: Space.sm),
              // `chips` (4:747): gold-filled for the one that is on, raised surface behind a
              // hairline for the rest. Material's ChoiceChip — a capsule with a check mark
              // that slides in, in the scheme's secondaryContainer — is in no frame of the
              // file.
              FilterBar<_Roster>(
                options: _Roster.values,
                selected: _roster,
                labelOf: (option) => option.label,
                onSelected: (option) => setState(() => _roster = option),
              ),
              const SizedBox(height: Space.md),
              // `list-header` (4:757): the caps heading with the count opposite it.
              SectionLabel(
                label: 'Student directory',
                trailing: total == null
                    ? null
                    : Text(
                        '$total ${total == 1 ? 'resident' : 'residents'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            ],
          ),
        ),
        empty: EmptyState(
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
    final t = Theme.of(context);

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

    // `student-row` (4:761), exactly: a 32dp avatar, the name at 13/600, ONE quiet 11/400
    // line of placement under it, and the state badge hard against the right edge. Nothing
    // else is on the row in the file, and the two things that used to be — a glyphed metadata
    // pair and a second right-hand column carrying the rent — are what made the list twice as
    // tall as the design's.
    //
    // THE PHONE NUMBER MOVED, IT DID NOT GO. It is the resident sheet's subtitle, one tap
    // away, and the search field above this list still matches on it.
    return TapRow(
      onTap: () => showStudentSheet(context, studentId: student.id),
      semanticLabel: '${student.fullName}, $placement, ${student.phone}, '
          '${student.status.label}',
      child: Row(
        children: [
          Avatar(name: student.fullName, tone: toneFor(context, student.status)),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.fullName,
                  style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.xxs / 2),
                Text(
                  '$placement · ${money(student.monthlyFee)}',
                  style: t.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          // The design badges EVERY row, including the ordinary one. A list where only the
          // exceptions are marked makes a reader check each unmarked row to see whether it is
          // fine or whether the badge simply failed to draw.
          StatusPill(status: student.status),
        ],
      ),
    );
  }
}
