/// JOIN REQUESTS, for the owner and the warden (docs/self-signup-api.md §5, spec Flow 4).
///
/// A tenant who signed up in the app asks to join a PG; the owner and that PG's wardens see the
/// request here — name, phone, photo, the details they gave and the identity documents they
/// uploaded — and accept or decline it, with an optional note the tenant reads.
///
/// THE SERVER DECIDES. `ow_join_requests` lists only what the caller may review;
/// `ow_decide_join_request` re-checks the caller, the request's state, the PG's plan and the
/// person, and its refusals are shown as they are. Photos and documents open through 60-second
/// signed URLs that storage grants only while the request is pending.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart' show UserRole;
import '../../core/theme/tokens.dart';
import '../../data/models/failure.dart';
import '../../data/models/people.dart';
import '../../data/people_providers.dart';
import '../../data/providers.dart' show studentsProvider;
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../shared/clay/clay.dart';
import '../../shared/glass/glass.dart';
import '../../shared/person_avatar.dart';

const _pendingStatus = 'pending';

/// "Join requests · 3 waiting", shown only while something is waiting. People tab, Students
/// tab, owner home and warden home all draw this one widget, so they cannot disagree.
class JoinRequestsEntry extends ConsumerWidget {
  const JoinRequestsEntry({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingJoinCountProvider).value ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: ListRowCard(
        icon: ClayIcons.addTenant,
        title: 'Join requests',
        subtitle: count == 1 ? '1 person is waiting for your answer' : '$count people are waiting for your answer',
        trailing: CountBadge(count: count, semanticLabel: '$count waiting'),
        semanticLabel: 'Join requests, $count waiting',
        onTap: () => Navigator.of(context).push(JoinRequestsScreen.route()),
      ),
    );
  }
}

class JoinRequestsScreen extends ConsumerWidget {
  const JoinRequestsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const JoinRequestsScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = joinRequestsProvider(_pendingStatus);
    final requests = ref.watch(provider);
    final several = (requests.value ?? const <ReviewJoinRequest>[])
            .map((r) => r.hostelId)
            .toSet()
            .length >
        1;

    Future<void> refresh() async {
      ref.invalidate(provider);
      ref.invalidate(pendingJoinCountProvider);
      try {
        await ref.read(provider.future).timeout(const Duration(seconds: 20));
      } catch (_) {
        // Drawn by the list below.
      }
    }

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(
            title: 'Join requests',
            subtitle: 'People asking to live in your PG',
            leading: HeaderBackButton(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md, Space.huge),
                children: [
                  switch (requests) {
                    AsyncData(:final value) when value.isEmpty => const EmptyState(
                        icon: ClayIcons.addTenant,
                        title: 'No requests waiting',
                        body: 'When someone asks to join your PG in the Apnivaas app, their '
                            'request appears here for you to accept or decline.',
                      ),
                    AsyncData(:final value) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final r in value) ...[
                            JoinRequestCard(request: r, showPg: several),
                            const SizedBox(height: Space.md),
                          ],
                        ],
                      ),
                    AsyncError(:final error) => EmptyState.error(
                        title: 'Could not load the requests',
                        message: _sentence(error),
                        onRetry: refresh,
                      ),
                    _ => const ListSkeleton(rows: 3, semanticLabel: 'Loading join requests'),
                  },
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _sentence(Object error) => switch (error) {
      SignupFailure(:final message) => message,
      AppFailure(:final message) => message,
      _ => 'Something went wrong. Please try again.',
    };

final _dob = DateFormat('d MMM yyyy');
final _when = DateFormat('d MMM, h:mm a');

/// One request: who is asking, everything they gave, their documents, and the two answers.
class JoinRequestCard extends ConsumerStatefulWidget {
  const JoinRequestCard({super.key, required this.request, this.showPg = false});

  final ReviewJoinRequest request;

  /// The owner has requests for more than one PG on screen, so each card names its PG.
  final bool showPg;

  @override
  ConsumerState<JoinRequestCard> createState() => _JoinRequestCardState();
}

class _JoinRequestCardState extends ConsumerState<JoinRequestCard> {
  bool _busy = false;

  Future<void> _decide(bool accept) async {
    final r = widget.request;
    final messenger = ScaffoldMessenger.of(context);
    final note = await showDecisionSheet(context, request: r, accept: accept);
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(peopleApiProvider).decideJoinRequest(r.requestId, accept: accept, note: note);
      ref.invalidate(joinRequestsProvider);
      ref.invalidate(pendingJoinCountProvider);
      if (accept) ref.invalidate(studentsProvider);
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(accept
            ? '${r.fullName} joined ${r.hostelName}. Add their room and rent from Students.'
            : 'Request declined. ${r.fullName} has been told.'),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Motion.readMessage,
        content: Text(_sentence(e)),
      ));
      // "already handled" / "no longer available": the list is stale, so read it again.
      ref.invalidate(joinRequestsProvider);
      ref.invalidate(pendingJoinCountProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = widget.request;
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final age = r.ageOn(DateTime.now());
    final about = [
      ?r.genderLabel,
      if (age != null) '$age years',
      if (r.dateOfBirth != null) 'born ${_dob.format(r.dateOfBirth!)}',
    ].join(' · ');

    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PersonAvatar(
                name: r.fullName,
                avatarPath: r.avatarPath,
                size: AvatarSize.headerLarge + Space.md,
                semanticLabel: 'Photo of ${r.fullName}',
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.fullName, style: t.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (about.isNotEmpty) Text(about, style: muted),
                    if (widget.showPg) Text('For ${r.hostelName}', style: muted),
                    if (r.createdAt != null) Text('Asked ${_when.format(r.createdAt!)}', style: muted),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          _Line(label: 'Phone', value: r.phone),
          _Line(label: 'Email', value: r.email),
          _Line(
            label: 'Emergency',
            value: [?r.emergencyName, ?r.emergencyPhone].join(' · '),
          ),
          if (r.message != null) ...[
            const SizedBox(height: Space.xs),
            InfoNote(message: '“${r.message}”', icon: Icons.chat_bubble_outline_rounded),
          ],
          const SizedBox(height: Space.sm),
          Text('Documents', style: t.textTheme.titleSmall),
          const SizedBox(height: Space.xxs),
          if (r.documents.isEmpty)
            Text('No documents uploaded. You can ask for an ID when they arrive.', style: muted)
          else
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final d in r.documents)
                  OutlinedButton.icon(
                    onPressed: () => openReviewDocument(context, d, owner: r.fullName),
                    icon: Icon(d.isPdf ? Icons.picture_as_pdf_outlined : Icons.badge_outlined,
                        size: IconSize.md),
                    label: Text(d.label),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  ),
              ],
            ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                onPressed: _busy || !r.isPending ? null : () => _decide(false),
                style: OutlinedButton.styleFrom(minimumSize: const Size(96, 48)),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: _busy || !r.isPending ? null : () => _decide(true),
                style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
                child: _busy
                    ? const SizedBox.square(
                        dimension: IconSize.md,
                        child: CircularProgressIndicator(strokeWidth: Strokes.focus),
                      )
                    : const Text('Accept'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final shown = (value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectionArea(
              child: Text(
                shown.isEmpty ? 'Not given' : shown,
                style: shown.isEmpty
                    ? t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)
                    : t.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Accept or decline, with an optional note the tenant reads. Returns the note ('' for none),
/// or null when the owner backed out.
Future<String?> showDecisionSheet(
  BuildContext context, {
  required ReviewJoinRequest request,
  required bool accept,
}) =>
    showApnivaasSheet<String>(
      context: context,
      title: accept ? 'Accept ${request.fullName}?' : 'Decline ${request.fullName}?',
      subtitle: accept
          ? 'They join ${request.hostelName} as a resident with no room yet. Add their room '
              'and rent afterwards from Students.'
          : 'They are told, and can ask another PG.',
      builder: (ctx) => _DecisionForm(accept: accept),
    );

class _DecisionForm extends StatefulWidget {
  const _DecisionForm({required this.accept});
  final bool accept;

  @override
  State<_DecisionForm> createState() => _DecisionFormState();
}

class _DecisionFormState extends State<_DecisionForm> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _note,
                maxLength: 300,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Note for them (optional)',
                  hintText: widget.accept
                      ? 'For example: Come to the office with your ID on Monday.'
                      : 'For example: We have no beds free this month.',
                ),
              ),
              const SizedBox(height: Space.sm),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_note.text.trim()),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Text(widget.accept ? 'Accept request' : 'Decline request'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
}

/// Opens one document through a fresh 60-second signed URL. Images are shown in the app; a PDF
/// cannot be drawn here and nothing opens a browser, so it says so.
Future<void> openReviewDocument(BuildContext context, ReviewDocument doc, {required String owner}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(Space.md),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${doc.label} · $owner', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: Space.sm),
              Flexible(child: _DocumentView(doc: doc)),
              const SizedBox(height: Space.sm),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );

class _DocumentView extends ConsumerWidget {
  const _DocumentView({required this.doc});
  final ReviewDocument doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (doc.isPdf) {
      return const InfoNote(
        message: 'This document is a PDF, which the app cannot show. Ask the person to show '
            'you the original when they arrive.',
        icon: Icons.picture_as_pdf_outlined,
      );
    }
    final url = ref.watch(signedUrlProvider((bucket: Buckets.documents, path: doc.storagePath)));
    const failed = InfoNote(
      message: 'This document could not be opened. The request may have been handled already.',
      icon: Icons.error_outline_rounded,
    );
    return switch (url) {
      AsyncData(:final value) when value != null => InteractiveViewer(
          child: Image.network(
            value,
            fit: BoxFit.contain,
            semanticLabel: doc.label,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
            errorBuilder: (_, _, _) => failed,
          ),
        ),
      AsyncLoading() => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
      _ => failed,
    };
  }
}

/// Whether this signed-in role reviews join requests at all.
bool reviewsJoinRequests(WidgetRef ref) {
  final role = ref.watch(sessionProvider.select((s) => s?.role));
  return role == UserRole.owner || role == UserRole.warden;
}
