library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
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

    return WardenScreen(
      title: 'Residents',
      subtitle: _term.isEmpty ? null : 'Matching "$_term"',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Register a resident',
          icon: const Icon(Icons.person_add_alt_1_rounded),
          onPressed: () => showRegisterStudentSheet(context, hostelId: hostelId),
        ),
      ],
      child: PagedList<Student>(
        value: students,
        onRefresh: () async => ref.invalidate(studentsProvider(query)),
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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final option in _Roster.values)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.xs),
                        child: ChoiceChip(
                          label: Text(option.label),
                          selected: _roster == option,
                          onSelected: (_) => setState(() => _roster = option),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        empty: EmptyState(
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

    return TapRow(
      onTap: () => showStudentSheet(context, studentId: student.id),
      semanticLabel: '${student.fullName}, $placement, ${student.status.label}',
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
                  style: t.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${student.phone} · $placement',
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
              Text(money(student.monthlyFee), style: t.textTheme.titleSmall),
              const SizedBox(height: Space.xxs),
              if (student.status != StudentStatus.active)
                StatusPill(status: student.status, dense: true),
            ],
          ),
        ],
      ),
    );
  }
}
