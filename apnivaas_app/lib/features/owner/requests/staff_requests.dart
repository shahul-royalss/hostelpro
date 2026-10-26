/// Staff requests for the owner (R8): people who signed up as staff and asked to join one of
/// the owner's PGs. Accept chooses Manager or Warden; Decline takes an optional note.
/// `ow_decide_staff_request` re-checks everything and its refusals are shown as they are.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/staff_request.dart';
import '../../../data/repositories/staff_request_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../../common/form_parts.dart';
import '../../student/stay_screens.dart' show stayErrorText;
import '../../student/widgets/format.dart' show dayLabel;
import '../staff/staff_providers.dart' show ownerStaffProvider;

/// "Staff requests · N waiting", shown to the owner only while something is waiting.
class StaffRequestsEntry extends ConsumerWidget {
  const StaffRequestsEntry({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingStaffRequestCountProvider).value ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: ListRowCard(
        icon: ClayIcons.team,
        title: 'Staff requests',
        subtitle: count == 1
            ? '1 person wants to join as staff'
            : '$count people want to join as staff',
        trailing: CountBadge(count: count, semanticLabel: '$count waiting'),
        semanticLabel: 'Staff requests, $count waiting',
        onTap: () => Navigator.of(context).push(StaffRequestsScreen.route()),
      ),
    );
  }
}

class StaffRequestsScreen extends ConsumerWidget {
  const StaffRequestsScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const StaffRequestsScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = staffRequestsProvider('pending');
    final requests = ref.watch(provider);
    final several =
        (requests.value ?? const <StaffRequestRow>[]).map((r) => r.hostelId).toSet().length > 1;

    Future<void> refresh() async {
      ref.invalidate(provider);
      ref.invalidate(pendingStaffRequestCountProvider);
      try {
        await ref.read(provider.future).timeout(const Duration(seconds: 20));
      } catch (_) {
        // Drawn below.
      }
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(
            title: 'Staff requests',
            subtitle: 'People asking to work at your PG',
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
                        icon: ClayIcons.team,
                        title: 'No staff requests',
                        body: 'When someone signs up as staff and asks to join your PG, it '
                            'appears here for you to accept or decline.',
                      ),
                    AsyncData(:final value) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final r in value) ...[
                            StaffRequestCard(request: r, showPg: several),
                            const SizedBox(height: Space.md),
                          ],
                        ],
                      ),
                    AsyncError(:final error) => EmptyState.error(
                        title: 'Could not load the requests',
                        message: stayErrorText(error),
                        onRetry: refresh,
                      ),
                    _ => const ListSkeleton(rows: 3, semanticLabel: 'Loading staff requests'),
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

class StaffRequestCard extends ConsumerStatefulWidget {
  const StaffRequestCard({super.key, required this.request, this.showPg = false});

  final StaffRequestRow request;
  final bool showPg;

  @override
  ConsumerState<StaffRequestCard> createState() => _StaffRequestCardState();
}

class _StaffRequestCardState extends ConsumerState<StaffRequestCard> {
  bool _busy = false;

  Future<void> _decide(bool accept) async {
    final r = widget.request;
    final messenger = ScaffoldMessenger.of(context);
    final answer = await showApnivaasSheet<_Answer>(
      context: context,
      builder: (_) => _DecisionSheet(request: r, accept: accept),
    );
    if (answer == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(staffRequestApiProvider).decide(
            r.requestId,
            accept: accept,
            role: answer.role,
            note: answer.note,
          );
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(accept
            ? '${r.fullName} is now a ${answer.role!.label} at ${r.hostelName}. They have been '
                'told and can sign in.'
            : 'Request declined. ${r.fullName} has been told.'),
      ));
      if (accept) ref.invalidate(ownerStaffProvider(r.hostelId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Motion.readMessage,
        content: Text(stayErrorText(e)),
      ));
    } finally {
      ref.invalidate(staffRequestsProvider);
      ref.invalidate(pendingStaffRequestCountProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = widget.request;
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(r.fullName, style: t.textTheme.titleMedium),
              StatusChip(
                label: r.status.label,
                tone: r.status == StaffRequestStatus.pending
                    ? StatusTone.warning
                    : StatusTone.neutral,
                dot: true,
              ),
            ],
          ),
          if (widget.showPg) Text('For ${r.hostelName}', style: muted),
          const SizedBox(height: Space.xxs),
          if (r.phone != null) SelectableText(r.phone!, style: t.textTheme.bodyMedium),
          if (r.email != null) SelectableText(r.email!, style: t.textTheme.bodyMedium),
          if (r.createdAt != null)
            Text('Asked on ${dayLabel(r.createdAt!.toLocal())}', style: muted),
          if (r.message != null) ...[
            const SizedBox(height: Space.xs),
            Text('“${r.message!}”', style: t.textTheme.bodyMedium),
          ],
          if (r.status == StaffRequestStatus.pending) ...[
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _decide(true),
                  child: Text(_busy ? 'Saving…' : 'Accept'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Decline'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Answer {
  const _Answer({this.role, this.note});
  final StaffGrant? role;
  final String? note;
}

class _DecisionSheet extends StatefulWidget {
  const _DecisionSheet({required this.request, required this.accept});
  final StaffRequestRow request;
  final bool accept;

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  final _note = TextEditingController();
  StaffGrant? _role;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.accept && _role == null) {
      setState(() => _error = 'Choose Manager or Warden.');
      return;
    }
    final note = _note.text.trim();
    Navigator.of(context).pop(_Answer(role: _role, note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = widget.request;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          Space.lg, 0, Space.lg, Space.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitle(
              title: widget.accept ? 'Add ${r.fullName} as staff' : 'Decline ${r.fullName}?',
              subtitle: widget.accept
                  ? 'Choose their role at ${r.hostelName}. They get access to this PG and can '
                      'sign in with the account they made.'
                  : 'They will be told. Add a note if it helps.',
            ),
            const SizedBox(height: Space.md),
            if (widget.accept) ...[
              for (final g in StaffGrant.values) ...[
                _RoleOption(
                  grant: g,
                  selected: _role == g,
                  onTap: () => setState(() {
                    _role = g;
                    _error = null;
                  }),
                ),
                const SizedBox(height: Space.xs),
              ],
              if (_error != null) FormNote(_error!),
            ] else
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                maxLength: 300,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            const SizedBox(height: Space.sm),
            BusyFilledButton(
              label: widget.accept ? 'Accept' : 'Decline',
              danger: !widget.accept,
              onPressed: _submit,
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: t.textTheme.labelLarge),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({required this.grant, required this.selected, required this.onTap});
  final StaffGrant grant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${grant.label}. ${grant.caption}',
      excludeSemantics: true,
      child: FlatSurface(
        borderRadius: Radii.rSurface,
        padding: const EdgeInsets.all(Space.sm),
        onTap: onTap,
        child: Row(
          children: [
            ClayIcon(
              grant == StaffGrant.manager ? ClayIcons.roleManager : ClayIcons.roleWarden,
              size: ClaySize.list,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(grant.label, style: t.textTheme.titleMedium),
                  Text(grant.caption,
                      style: t.textTheme.bodySmall
                          ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
