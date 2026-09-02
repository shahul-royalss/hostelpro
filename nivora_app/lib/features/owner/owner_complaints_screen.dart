library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import '../../shared/illustrations.dart';
import 'owner_format.dart';
import 'owner_providers.dart';
import 'owner_students_screen.dart';
import 'widgets/states.dart';

/// WHAT THE RESIDENTS ARE COMPLAINING ABOUT, AND WHO SAID IT.
///
/// Reached from the Complaints card on the dashboard, which until now was a number with nothing
/// behind it — the count said "2 open" and tapping it did nothing.
///
/// ── READ-ONLY, LIKE THE REST OF THE OWNER'S SIDE ──────────────────────────────────────────
///
/// The owner cannot change a complaint's status here. Resolving one is the warden's job,
/// because resolving it means having actually fixed the tap — and a status set from a phone in
/// another city is a status that lies. The owner gets the whole record and no buttons.
///
/// ── READS ─────────────────────────────────────────────────────────────────────────────────
///
/// public.complaints (complaintsProvider, RLS-scoped), public.students for the author's name
/// (studentProvider — the same one the warden's sheet uses), public.complaint_events for the
/// timeline, and a signed URL for the photo when there is one.
class OwnerComplaintsScreen extends ConsumerWidget {
  const OwnerComplaintsScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const OwnerComplaintsScreen(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(activeHostelIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Complaints')),
      body: hostelId == null
          ? const _Page(
              child: EmptyNote(
                icon: Icons.apartment_rounded,
                title: 'No PG on your account yet',
                message: 'Complaints appear here once a PG is registered against your account.',
              ),
            )
          : _Body(hostelId: hostelId),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ComplaintQuery(hostelId: hostelId);
    final complaints = ref.watch(complaintsProvider(query));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(complaintsProvider(query));
        try {
          await ref.read(complaintsProvider(query).future).timeout(ownerRefreshTimeout);
        } catch (_) {
          // Rendered below. Rethrowing would turn a handled failure into a crash.
        }
      },
      child: whenAsync(
        complaints,
        loading: () => const _Page(child: _ComplaintsSkeleton()),
        error: (error) => _Page(
          child: ErrorNote(
            error: error,
            onRetry: () => ref.invalidate(complaintsProvider(query)),
          ),
        ),
        data: (page) => page.items.isEmpty
            ? const _Page(
                child: EmptyNote(
                  icon: Icons.check_circle_outline_rounded,
                  // Unfiltered: this list has no search and no status filter, so empty here
                  // always means "nobody has raised one", never "no match".
                  illustration: EmptyArt.complaints,
                  title: 'Nothing outstanding',
                  message: 'Complaints your residents raise appear here, newest first.',
                ),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
                children: [
                  for (final c in page.items) ...[
                    _ComplaintRow(complaint: c),
                    const SizedBox(height: Space.xs),
                  ],
                ],
              ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
        children: [child],
      );
}

(String, Color) _statusFace(BuildContext context, ComplaintStatus status) {
  final tones = context.tones;
  return switch (status) {
    ComplaintStatus.open => ('Open', tones.warning),
    ComplaintStatus.inProgress => ('In progress', tones.info),
    ComplaintStatus.resolved => ('Resolved', tones.success),
  };
}

class _ComplaintRow extends ConsumerWidget {
  const _ComplaintRow({required this.complaint});
  final Complaint complaint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final c = complaint;
    final (label, tone) = _statusFace(context, c.status);
    // The author's name, when it has arrived. Never blocks the row: a complaint whose student
    // row is still loading still shows its title, its category and its age.
    final who = ref.watch(studentProvider(c.studentId)).value?.fullName;

    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      onTap: () => showGlassSheet<void>(
        context: context,
        builder: (_) => _ComplaintDetail(complaint: c),
      ),
      semanticLabel: '${c.title}, $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(c.title,
                    style: t.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: Space.xs),
              StatusChip(label: label, tone: tone, dot: true),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(
            '${c.category.label} · ${who ?? 'Resident'} · ${relativeTime(c.createdAt)}',
            style: t.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The whole complaint: what was said, the photo if there is one, who said it, and every step
/// the warden has taken since.
class _ComplaintDetail extends ConsumerWidget {
  const _ComplaintDetail({required this.complaint});
  final Complaint complaint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final c = complaint;
    final (label, tone) = _statusFace(context, c.status);
    final student = ref.watch(studentProvider(c.studentId)).value;
    final photo = ref.watch(complaintPhotoProvider(c.id));
    final timeline = ref.watch(complaintTimelineProvider(c.id));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(c.title, style: t.textTheme.titleLarge, maxLines: 3)),
            const SizedBox(width: Space.xs),
            StatusChip(label: label, tone: tone, dot: true),
          ],
        ),
        const SizedBox(height: Space.xxs),
        Text('${c.category.label} · raised ${relativeTime(c.createdAt)}',
            style: t.textTheme.bodySmall),

        if ((c.description ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text(c.description!.trim(), style: t.textTheme.bodyMedium),
        ],

        // The photo, only once a signed URL has actually been minted. A complaint with no
        // photo draws nothing here rather than an empty frame — see complaintPhotoProvider on
        // why the URL is short-lived and re-minted per look.
        ...switch (photo) {
          AsyncData(:final value) when value != null => [
              const SizedBox(height: Space.md),
              ClipRRect(
                borderRadius: Radii.rCard,
                child: Image.network(
                  value.toString(),
                  fit: BoxFit.cover,
                  // A photo that will not load must not look like a photo that does not exist.
                  errorBuilder: (_, _, _) => Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Text('The attached photo could not be loaded.',
                        style: t.textTheme.bodySmall),
                  ),
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const SkeletonCard(lines: 1, height: 160),
                ),
              ),
            ],
          AsyncLoading() => const [SizedBox(height: Space.md), SkeletonCard(lines: 1, height: 160)],
          _ => const <Widget>[],
        },

        const SizedBox(height: Space.lg),
        SectionLabel(label: 'Raised by'),
        const SizedBox(height: Space.xs),
        if (student == null)
          const SkeletonCard(lines: 1, height: 64)
        else
          FlatSurface(
            padding: const EdgeInsets.all(Space.md),
            onTap: () {
              Navigator.of(context).pop();
              showStudentDetail(context, student);
            },
            child: Row(
              children: [
                InitialsAvatar(name: student.fullName),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(student.fullName, style: t.textTheme.titleMedium),
                      const SizedBox(height: Space.xxs),
                      Text(student.phone, style: t.textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.colorScheme.outline),
              ],
            ),
          ),

        const SizedBox(height: Space.lg),
        SectionLabel(label: 'History'),
        const SizedBox(height: Space.xs),
        whenAsync(
          timeline,
          loading: () => const SkeletonCard(lines: 2),
          error: (error) => ErrorNote(
            error: error,
            compact: true,
            onRetry: () => ref.invalidate(complaintTimelineProvider(c.id)),
          ),
          data: (events) => events.isEmpty
              ? Text('No updates yet.', style: t.textTheme.bodySmall)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in events) ...[
                      _TimelineRow(event: e),
                      const SizedBox(height: Space.xs),
                    ],
                  ],
                ),
        ),

        if (c.status == ComplaintStatus.resolved &&
            (c.resolutionNote ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: Space.md),
          SectionLabel(label: 'Resolution'),
          const SizedBox(height: Space.xs),
          Text(c.resolutionNote!.trim(), style: t.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event});
  final ComplaintEvent event;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (label, tone) = _statusFace(context, event.status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(Icons.circle, size: 8, color: tone),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label · ${relativeTime(event.createdAt)}',
                  style: t.textTheme.bodyMedium),
              if ((event.note ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: Space.xxs),
                Text(event.note!.trim(), style: t.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ComplaintsSkeleton extends StatelessWidget {
  const _ComplaintsSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonCard(lines: 2, height: 84),
          SizedBox(height: Space.xs),
          SkeletonCard(lines: 2, height: 84),
          SizedBox(height: Space.xs),
          SkeletonCard(lines: 2, height: 84),
        ],
      );
}
