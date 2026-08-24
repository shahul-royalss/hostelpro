library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../actions/sheet_scaffold.dart';
import '../data/warden_providers.dart';
import '../students/student_sheet.dart';
import '../widgets/warden_ui.dart';

/// One complaint, and the only three states it can be in.
///
/// THE WORKFLOW IS THE DATABASE'S, NOT THIS SCREEN'S. public.complaint_status is exactly
/// ('open','in_progress','resolved'); there is no "acknowledged", no "escalated", no
/// "won't fix". This sheet offers those three and nothing else, because a fourth button would
/// have to write a value the enum would reject.
///
/// EVERYTHING EXCEPT THE STATUS IS WRITTEN BY TRIGGERS. app.complaints_after_change stamps
/// resolved_at, appends the complaint_events row and notifies the resident. So the write here is
/// one UPDATE of `status` (plus a note and updated_by) and the timeline below re-reads what the
/// server actually recorded — never a row this client optimistically added. If the trigger and
/// the screen ever disagree, the screen is showing the trigger's answer.
///
/// REOPENING IS ALLOWED, deliberately. complaints_update admits any status change by an owner
/// or warden, and a tap that leaks again two days later is the same complaint, not a new one.
/// The timeline keeps both passes.
Future<void> showComplaintSheet(BuildContext context, {required String complaintId}) {
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _ComplaintSheet(complaintId: complaintId),
  );
}

class _ComplaintSheet extends ConsumerWidget {
  const _ComplaintSheet({required this.complaintId});
  final String complaintId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complaint = ref.watch(complaintProvider(complaintId));

    return AsyncSection<Complaint?>(
      value: complaint,
      onRetry: () => ref.invalidate(complaintProvider(complaintId)),
      // A skeleton, not a spinner. A sheet that opens onto a turning circle throws away
      // the shape the warden is about to read and then snaps it in.
      loading: const SheetBody(
        title: 'Complaint',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: Space.md),
          child: SkeletonBlock(lines: 3),
        ),
      ),
      builder: (row) {
        if (row == null) {
          return const SheetBody(
            title: 'Complaint',
            child: EmptyState(
              icon: Icons.report_off_outlined,
              title: 'That complaint is not visible',
              detail: 'It may belong to another hostel.',
            ),
          );
        }
        return _Loaded(complaint: row);
      },
    );
  }
}

class _Loaded extends ConsumerStatefulWidget {
  const _Loaded({required this.complaint});
  final Complaint complaint;

  @override
  ConsumerState<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends ConsumerState<_Loaded> {
  bool _busy = false;

  Future<void> _move(ComplaintStatus to, {String? note}) async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      success: switch (to) {
        ComplaintStatus.open => 'Reopened',
        ComplaintStatus.inProgress => 'Marked in progress',
        ComplaintStatus.resolved => 'Marked resolved',
      },
      action: () => ref.read(complaintRepositoryProvider).updateStatus(
            complaintId: widget.complaint.id,
            status: to,
            resolutionNote: note,
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) refreshComplaints(ref);
  }

  Future<void> _resolve() async {
    final note = await showGlassSheet<String>(
      context: context,
      builder: (_) => const _ResolutionNoteSheet(),
    );
    // Null means the sheet was dismissed; an empty string means "resolve, no note".
    if (note == null || !mounted) return;
    await _move(ComplaintStatus.resolved, note: note.isEmpty ? null : note);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final complaint = widget.complaint;

    return SheetBody(
      title: complaint.title,
      subtitle: '${complaint.category.label} · raised ${age(complaint.createdAt)}',
      trailing: StatusPill(status: complaint.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Workflow(status: complaint.status),
          const SizedBox(height: Space.md),
          _Buttons(status: complaint.status, busy: _busy, onMove: _move, onResolve: _resolve),

          if (complaint.description != null) ...[
            const SectionLabel(label: 'What was reported'),
            Text(complaint.description!, style: t.textTheme.bodyLarge),
          ],
          if (complaint.photoUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Row(
                children: [
                  Icon(Icons.image_outlined,
                      size: IconSize.sm, color: t.colorScheme.onSurfaceVariant),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      // photo_url is a key into a PRIVATE bucket, not a link. Showing it as an
                      // image would need a signed URL this screen does not mint, and a broken
                      // image icon is worse than saying plainly that there is one.
                      'A photo was attached. Open it from the web console.',
                      style: t.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),

          const SectionLabel(label: 'Raised by'),
          _RaisedBy(studentId: complaint.studentId),

          if (complaint.resolutionNote != null) ...[
            const SectionLabel(label: 'Resolution'),
            Text(complaint.resolutionNote!, style: t.textTheme.bodyMedium),
          ],

          const SectionLabel(label: 'History'),
          _Timeline(complaintId: complaint.id),
        ],
      ),
    );
  }
}

/// open → in progress → resolved, with where this one has got to.
class _Workflow extends StatelessWidget {
  const _Workflow({required this.status});
  final ComplaintStatus status;

  static const _order = [
    ComplaintStatus.open,
    ComplaintStatus.inProgress,
    ComplaintStatus.resolved,
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final reached = _order.indexOf(status);

    return Row(
      children: [
        for (var i = 0; i < _order.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: Space.xxs / 2,
                margin: const EdgeInsets.symmetric(horizontal: Space.xxs),
                color: i <= reached
                    ? toneFor(context, _order[i])
                    : t.colorScheme.outlineVariant,
              ),
            ),
          Column(
            children: [
              Container(
                width: Space.xl,
                height: Space.xl,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i <= reached
                      ? context.tones.chipFill(toneFor(context, _order[i]))
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i <= reached
                        ? toneFor(context, _order[i])
                        : t.colorScheme.outlineVariant,
                    width: Strokes.hairline,
                  ),
                ),
                child: i < reached
                    ? Icon(Icons.check_rounded,
                        size: IconSize.xs, color: toneFor(context, _order[i]))
                    : null,
              ),
              const SizedBox(height: Space.xxs),
              Text(
                _order[i].label,
                style: t.textTheme.labelSmall?.copyWith(
                  color: i <= reached ? toneFor(context, _order[i]) : null,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.status,
    required this.busy,
    required this.onMove,
    required this.onResolve,
  });

  final ComplaintStatus status;
  final bool busy;
  final Future<void> Function(ComplaintStatus to, {String? note}) onMove;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    // 48 is the filled button's own height, so the row does not jump while the write runs.
    if (busy) return const InlineSpinner(replacing: 48);

    return switch (status) {
      ComplaintStatus.open => Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => onMove(ComplaintStatus.inProgress),
                icon: const Icon(Icons.play_arrow_rounded, size: IconSize.md),
                label: const Text('Start work'),
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: OutlinedButton(onPressed: onResolve, child: const Text('Resolve')),
            ),
          ],
        ),
      // No green repaint. A FilledButton is ALREADY "the main action here"; painting it
      // #188D43 added no meaning and put its own white label at 4.26:1, under the 4.5:1 a
      // 15px button label needs. The theme's indigo measures 5.98:1.
      ComplaintStatus.inProgress => FilledButton.icon(
          onPressed: onResolve,
          icon: const Icon(Icons.check_rounded, size: IconSize.md),
          label: const Text('Mark resolved'),
        ),
      ComplaintStatus.resolved => OutlinedButton.icon(
          onPressed: () => onMove(ComplaintStatus.open),
          icon: const Icon(Icons.replay_rounded, size: IconSize.md),
          label: const Text('Reopen'),
        ),
    };
  }
}

/// The resident who raised it — name, number, and a way into their record.
///
/// A separate read of public.students rather than an embed on the complaints query, because the
/// shared ComplaintRepository serves the resident's own list too, and a student may not read
/// another student's row. One query here, only for the staff who opened the sheet.
class _RaisedBy extends ConsumerWidget {
  const _RaisedBy({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final student = ref.watch(studentProvider(studentId)).value;
    if (student == null) {
      return Text('Loading the resident…', style: t.textTheme.bodySmall);
    }
    return TapRow(
      onTap: () => showStudentSheet(context, studentId: student.id),
      child: Row(
        children: [
          Avatar(name: student.fullName),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.fullName, style: t.textTheme.titleMedium,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(student.phone, style: t.textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: IconSize.lg),
        ],
      ),
    );
  }
}

/// public.complaint_events, oldest first. Written entirely by the trigger.
class _Timeline extends ConsumerWidget {
  const _Timeline({required this.complaintId});
  final String complaintId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final events = ref.watch(complaintTimelineProvider(complaintId));

    return AsyncSection<List<ComplaintEvent>>(
      value: events,
      onRetry: () => ref.invalidate(complaintTimelineProvider(complaintId)),
      loading: const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.md),
        child: SkeletonBlock(lines: 2),
      ),
      builder: (list) {
        if (list.isEmpty) {
          return Text('No history recorded.', style: t.textTheme.bodySmall);
        }
        return Column(
          children: [
            for (final event in list)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: Space.xs,
                      height: Space.xs,
                      margin: const EdgeInsets.only(top: Space.xxs, right: Space.sm),
                      decoration: BoxDecoration(
                        color: toneFor(context, event.status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(event.status.label, style: t.textTheme.bodyMedium?.copyWith(
                            color: t.colorScheme.onSurface,
                          )),
                          if (event.note != null)
                            Text(event.note!, style: t.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Text(
                      '${shortDate(event.createdAt)} ${timeOfDay(event.createdAt)}',
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// What was actually done. Optional — a note nobody has time to write is a note that stops the
/// complaint being closed at all, so "Resolve without a note" is a real button rather than a
/// grudging one.
class _ResolutionNoteSheet extends StatefulWidget {
  const _ResolutionNoteSheet();

  @override
  State<_ResolutionNoteSheet> createState() => _ResolutionNoteSheetState();
}

class _ResolutionNoteSheetState extends State<_ResolutionNoteSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: 'Resolve this complaint',
      subtitle: 'The resident is notified either way',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _note,
            autofocus: true,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What was done',
              hintText: 'Plumber replaced the tap on Tuesday',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_note.text.trim()),
            child: const Text('Mark resolved'),
          ),
          const SizedBox(height: Space.xs),
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Resolve without a note'),
          ),
        ],
      ),
    );
  }
}
