library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay.dart';
import '../../shared/glass/glass.dart';
import '../../shared/illustrations.dart';
import 'owner_format.dart';
import 'owner_providers.dart';
import 'owner_students_screen.dart';
import 'widgets/owner_header.dart';
import 'widgets/states.dart' show ErrorNote, whenAsync;

/// WHAT THE RESIDENTS ARE COMPLAINING ABOUT, AND WHO SAID IT.
///
/// Reached from the Complaints tile and the quick action on Home, the bell's activity list, and
/// More — which until this screen existed was a number with nothing behind it.
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
      body: Column(
        children: [
          OwnerSubpageHeader(title: 'Complaints', subtitle: watchActiveHostelName(ref)),
          Expanded(
            child: hostelId == null
                ? const _Page(
                    child: EmptyState(
                      icon: ClayIcons.rooms,
                      title: 'No PG on your account yet',
                      body: 'Complaints appear here once a PG is registered against your '
                          'account.',
                    ),
                  )
                : _Body(hostelId: hostelId),
          ),
        ],
      ),
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
        loading: () => const _Page(
          child: ListSkeleton(rows: 4, semanticLabel: 'Loading complaints'),
        ),
        error: (error) => _Page(
          child: ErrorNote(
            error: error,
            onRetry: () => ref.invalidate(complaintsProvider(query)),
          ),
        ),
        data: (page) => page.items.isEmpty
            ? _Page(
                // Unfiltered: this list has no search and no status filter, so empty here
                // always means "nobody has raised one", never "no match" — so it is safe to
                // say exactly that, with the first-run art.
                child: EmptyState(
                  icon: EmptyArt.clayFor(EmptyArt.complaints),
                  title: 'No complaints yet',
                  body: 'When a resident raises one it lands here, with who raised it and '
                      'every step taken since.',
                ),
              )
            : _Page(
                child: ListGroup(
                  children: [for (final c in page.items) _ComplaintRow(complaint: c)],
                ),
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
        padding: OwnerRhythm.pagePadding,
        children: [child],
      );
}

/// A complaint's status as a word and the tone it is drawn in, the same three the warden's
/// queue uses.
(String, StatusTone) _statusFace(ComplaintStatus status) => switch (status) {
      ComplaintStatus.open => ('Open', StatusTone.warning),
      ComplaintStatus.inProgress => ('In progress', StatusTone.info),
      ComplaintStatus.resolved => ('Resolved', StatusTone.success),
    };

class _ComplaintRow extends ConsumerWidget {
  const _ComplaintRow({required this.complaint});
  final Complaint complaint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = complaint;
    final (label, tone) = _statusFace(c.status);
    // The author's name, when it has arrived. Never blocks the row: a complaint whose student
    // row is still loading still shows its title, its category and its age.
    final who = ref.watch(studentProvider(c.studentId)).value?.fullName;

    return ListRow(
      avatarName: who ?? 'Resident',
      title: c.title,
      subtitle: '${c.category.label} · ${who ?? 'Resident'} · ${relativeTime(c.createdAt)}',
      trailing: StatusChip(label: label, tone: tone, dot: true),
      onTap: () => showGlassSheet<void>(
        context: context,
        builder: (_) => _ComplaintDetail(complaint: c),
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
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final c = complaint;
    final (label, tone) = _statusFace(c.status);
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
            Expanded(
              child: Semantics(
                header: true,
                child: Text(c.title, style: t.textTheme.titleLarge, maxLines: 3),
              ),
            ),
            const SizedBox(width: Space.xs),
            StatusChip(label: label, tone: tone, dot: true),
          ],
        ),
        const SizedBox(height: Space.xxs),
        Text('${c.category.label} · raised ${relativeTime(c.createdAt)}', style: muted),

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
                    child: Text('The attached photo could not be loaded.', style: muted),
                  ),
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const Skeleton(height: 160, radius: Radii.rCard),
                ),
              ),
            ],
          AsyncLoading() => const [
              SizedBox(height: Space.md),
              Skeleton(height: 160, radius: Radii.rCard),
            ],
          _ => const <Widget>[],
        },

        const SizedBox(height: Space.lg),
        const SectionHeader(title: 'Raised by', size: SectionHeaderSize.form),
        const SizedBox(height: Space.xs),
        if (student == null)
          const ListSkeleton(rows: 1, semanticLabel: 'Loading who raised it')
        else
          ListRowCard(
            avatarName: student.fullName,
            title: student.fullName,
            subtitle: student.phone,
            onTap: () {
              Navigator.of(context).pop();
              showStudentDetail(context, student);
            },
          ),

        const SizedBox(height: Space.lg),
        const SectionHeader(title: 'History', size: SectionHeaderSize.form),
        const SizedBox(height: Space.xs),
        whenAsync(
          timeline,
          loading: () => const SkeletonPulse(
            semanticLabel: 'Loading history',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Skeleton(widthFactor: 0.6),
                SizedBox(height: Space.sm),
                Skeleton(widthFactor: 0.45),
              ],
            ),
          ),
          error: (error) => ErrorNote(
            error: error,
            compact: true,
            onRetry: () => ref.invalidate(complaintTimelineProvider(c.id)),
          ),
          data: (events) => events.isEmpty
              ? Text('No updates yet.', style: muted)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in events) ...[
                      _TimelineRow(event: e),
                      const SizedBox(height: Space.sm),
                    ],
                  ],
                ),
        ),

        if (c.status == ComplaintStatus.resolved &&
            (c.resolutionNote ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: Space.md),
          const SectionHeader(title: 'Resolution', size: SectionHeaderSize.form),
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
    final (label, tone) = _statusFace(event.status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The dot is a graphic, so it takes the canonical tone; the words beside it say the
        // same thing in the theme's ink.
        Padding(
          padding: const EdgeInsets.only(top: Space.tight),
          child: ExcludeSemantics(
            child: Container(
              width: Space.xs,
              height: Space.xs,
              decoration: BoxDecoration(color: tone.canonical, shape: BoxShape.circle),
            ),
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label · ${relativeTime(event.createdAt)}', style: t.textTheme.bodyMedium),
              if ((event.note ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: Space.xxs),
                Text(
                  event.note!.trim(),
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
