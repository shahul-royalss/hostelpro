/// Deleted accounts (round 3, R7): accounts removed by their owner, by a self-deletion request,
/// or by the Super Admin, and the PERMANENT delete. A permanent delete erases the login, profile
/// details, photos and documents; payments, receipts, dues and audit records stay, anonymised to
/// "Deleted user" (docs/round3-api.md §8).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../shared/clay/clay.dart';
import '../../shared/glass/glass.dart';
import '../common/form_parts.dart';
import 'data/sa_round3.dart';
import 'sa_signups_screen.dart' show SaDateRangeButton, SaFilterChips, saMaxRows, saSentence;

final _when = DateFormat('d MMM yyyy, h:mm a');

/// What the Super Admin types to confirm.
const purgeConfirmWord = 'DELETE';

class SaDeletedAccountsEntry extends StatelessWidget {
  const SaDeletedAccountsEntry({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        child: ListRowCard(
          icon: ClayIcons.agreement,
          title: 'Deleted accounts',
          subtitle: 'Removals, deletion requests and permanent deletes',
          onTap: () => Navigator.of(context).push(SaDeletedAccountsScreen.route()),
        ),
      );
}

class SaDeletedAccountsScreen extends ConsumerStatefulWidget {
  const SaDeletedAccountsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const SaDeletedAccountsScreen());

  @override
  ConsumerState<SaDeletedAccountsScreen> createState() => _SaDeletedAccountsScreenState();
}

class _SaDeletedAccountsScreenState extends ConsumerState<SaDeletedAccountsScreen> {
  SaDeletionQuery _q = const SaDeletionQuery();

  void _set({Object? kind = _keep, Object? from = _keep, Object? to = _keep, int? limit}) {
    setState(() => _q = SaDeletionQuery(
          kind: identical(kind, _keep) ? _q.kind : kind as String?,
          from: identical(from, _keep) ? _q.from : from as DateTime?,
          to: identical(to, _keep) ? _q.to : to as DateTime?,
          limit: limit ?? 50,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(saDeletedAccountsProvider(_q));
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(
            title: 'Deleted accounts',
            subtitle: page.value == null ? 'Newest first' : '${page.value!.total} accounts',
            leading: const HeaderBackButton(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(saDeletedAccountsProvider(_q));
                try {
                  await ref.read(saDeletedAccountsProvider(_q).future);
                } catch (_) {}
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
                children: [
                  SaDateRangeButton(
                    from: _q.from,
                    to: _q.to,
                    onChanged: (f, t) => _set(from: f, to: t),
                  ),
                  const SizedBox(height: Space.sm),
                  SaFilterChips(
                    label: 'How',
                    options: saDeletionKinds,
                    selected: _q.kind,
                    onSelected: (v) => _set(kind: v),
                  ),
                  const SizedBox(height: Space.md),
                  switch (page) {
                    AsyncData(:final value) when value.items.isEmpty => const EmptyState(
                        icon: ClayIcons.agreement,
                        title: 'No deleted accounts',
                        body: 'Accounts that are removed or ask to be deleted appear here.',
                      ),
                    AsyncData(:final value) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final a in value.items) ...[
                            _DeletedCard(account: a, onPurge: () => _purge(a)),
                            const SizedBox(height: Space.sm),
                          ],
                          if (value.total > value.items.length)
                            _q.limit < saMaxRows
                                ? OutlinedButton(
                                    onPressed: () => _set(limit: _q.limit + 50),
                                    child: Text(
                                        'Show more (${value.total - value.items.length} left)'),
                                  )
                                : const InfoNote(
                                    message: 'Showing the newest 200. Narrow the dates to see '
                                        'older ones.',
                                  ),
                        ],
                      ),
                    AsyncError(:final error) => EmptyState.error(
                        message: saSentence(error),
                        onRetry: () => ref.invalidate(saDeletedAccountsProvider(_q)),
                      ),
                    _ => const ListSkeleton(rows: 4, semanticLabel: 'Loading deleted accounts'),
                  },
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _purge(SaDeletedAccount a) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PurgeAccountDialog(account: a),
    );
    if (done != true) return;
    ref.invalidate(saDeletedAccountsProvider);
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('${a.fullName} was permanently deleted. Payment records are kept.'),
    ));
  }
}

const _keep = Object();

class _DeletedCard extends StatelessWidget {
  const _DeletedCard({required this.account, required this.onPurge});
  final SaDeletedAccount account;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a = account;
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
              Text(a.fullName, style: t.textTheme.titleMedium),
              StatusChip(
                label: a.purgedAt != null ? 'Permanently deleted' : (saDeletionKinds[a.kind] ?? a.kind),
                tone: a.purgedAt != null
                    ? StatusTone.neutral
                    : (a.kind == 'self_request' ? StatusTone.warning : StatusTone.info),
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text([?_role(a.role), ?a.hostelName].join(' · '), style: t.textTheme.bodyMedium),
          Text(
            [
              if (a.at != null) _when.format(a.at!.toLocal()),
              if (a.byName != null) 'by ${a.byName}',
            ].join(' '),
            style: muted,
          ),
          if (a.reason != null) ...[
            const SizedBox(height: Space.xxs),
            Text('Reason: ${a.reason!}', style: t.textTheme.bodyMedium),
          ],
          if (a.purgedAt != null)
            Text('Erased ${_when.format(a.purgedAt!.toLocal())}', style: muted),
          if (a.canPurge) ...[
            const SizedBox(height: Space.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.tones.error,
                  side: BorderSide(color: context.tones.error),
                ),
                icon: const Icon(Icons.delete_forever_rounded, size: IconSize.sm),
                label: const Text('Permanently delete'),
                onPressed: onPurge,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String? _role(String? r) => switch (r) {
        'owner' => 'Owner',
        'manager' => 'Manager',
        'warden' => 'Warden',
        'student' => 'Tenant',
        null => null,
        _ => r,
      };
}

/// The strong confirmation: what goes, what stays, a reason, and the word typed out.
/// Pops true once the server has erased the account.
class PurgeAccountDialog extends ConsumerStatefulWidget {
  const PurgeAccountDialog({super.key, required this.account});
  final SaDeletedAccount account;

  @override
  ConsumerState<PurgeAccountDialog> createState() => _PurgeAccountDialogState();
}

class _PurgeAccountDialogState extends ConsumerState<PurgeAccountDialog> {
  final _reason = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reason.addListener(_changed);
    _confirm.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _reason.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _ready {
    final n = _reason.text.trim().length;
    return n >= 5 && n <= 300 && _confirm.text.trim() == purgeConfirmWord && !_busy;
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(saRound3ApiProvider).purgeAccount(widget.account.userId, reason: _reason.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = saSentence(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: context.tones.error),
      title: Text('Permanently delete ${widget.account.fullName}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This cannot be undone. Their login, profile details, photos and documents are '
              'erased.',
              style: t.textTheme.bodyMedium,
            ),
            const SizedBox(height: Space.sm),
            const InfoNote(
              icon: Icons.receipt_long_outlined,
              message: 'Payments, receipts, dues and audit records are kept for legal and '
                  'accounting reasons. They will show "Deleted user" instead of the name.',
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reason',
                helperText: 'Between 5 and 300 characters. Kept in the audit trail.',
              ),
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Type $purgeConfirmWord to confirm'),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              FormNote(_error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        BusyFilledButton(
          label: 'Delete permanently',
          danger: true,
          busy: _busy,
          onPressed: _ready ? _go : null,
        ),
      ],
    );
  }
}
