/// Confirm UPI payments (R9), for wardens and the owner. A tenant's report is only a claim:
/// it becomes a payment when someone here checks their UPI app or bank and confirms it,
/// which records it through `wd_record_payment` on the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/upi.dart';
import '../../../data/repositories/upi_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../../common/form_parts.dart';
import '../../student/stay_screens.dart' show stayErrorText, toneForStatus;
import '../../student/widgets/format.dart' show dayLabel, monthLabel, rupees;
import '../data/warden_providers.dart' show refreshFees;

/// "UPI payments to confirm · N", shown only while something is waiting.
class PaymentClaimsEntry extends ConsumerWidget {
  const PaymentClaimsEntry({super.key, required this.hostelId, this.padding = EdgeInsets.zero});

  final String? hostelId;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = hostelId;
    if (id == null) return const SizedBox.shrink();
    final count = ref.watch(pendingClaimsProvider(id)).value?.length ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: ListRowCard(
        icon: ClayIcons.collectPayment,
        title: 'UPI payments to confirm',
        subtitle: count == 1
            ? '1 tenant says they paid by UPI'
            : '$count tenants say they paid by UPI',
        trailing: CountBadge(count: count, semanticLabel: '$count waiting'),
        semanticLabel: 'UPI payments to confirm, $count waiting',
        onTap: () => Navigator.of(context).push(PaymentClaimsScreen.route(id)),
      ),
    );
  }
}

class PaymentClaimsScreen extends ConsumerStatefulWidget {
  const PaymentClaimsScreen({super.key, required this.hostelId});

  final String hostelId;

  static Route<void> route(String hostelId) =>
      MaterialPageRoute<void>(builder: (_) => PaymentClaimsScreen(hostelId: hostelId));

  @override
  ConsumerState<PaymentClaimsScreen> createState() => _PaymentClaimsScreenState();
}

class _PaymentClaimsScreenState extends ConsumerState<PaymentClaimsScreen> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final provider =
        _all ? allClaimsProvider(widget.hostelId) : pendingClaimsProvider(widget.hostelId);
    final claims = ref.watch(provider);

    Future<void> refresh() async {
      ref.invalidate(provider);
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
            title: 'UPI payments',
            subtitle: 'Check your UPI app, then confirm',
            leading: HeaderBackButton(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md, Space.huge),
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Waiting')),
                      ButtonSegment(value: true, label: Text('All')),
                    ],
                    selected: {_all},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _all = v.first),
                  ),
                  const SizedBox(height: Space.md),
                  switch (claims) {
                    AsyncData(:final value) when value.isEmpty => EmptyState(
                        icon: ClayIcons.collectPayment,
                        title: _all ? 'No UPI payments yet' : 'Nothing to confirm',
                        body: 'When a tenant pays with their UPI app and enters the UTR, it '
                            'appears here for you to check and confirm.',
                      ),
                    AsyncData(:final value) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final c in value) ...[
                            ClaimCard(hostelId: widget.hostelId, claim: c),
                            const SizedBox(height: Space.md),
                          ],
                        ],
                      ),
                    AsyncError(:final error) => EmptyState.error(
                        title: 'Could not load the payments',
                        message: stayErrorText(error),
                        onRetry: refresh,
                      ),
                    _ => const ListSkeleton(rows: 3, semanticLabel: 'Loading UPI payments'),
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

class ClaimCard extends ConsumerStatefulWidget {
  const ClaimCard({super.key, required this.hostelId, required this.claim});

  final String hostelId;
  final PaymentClaim claim;

  @override
  ConsumerState<ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends ConsumerState<ClaimCard> {
  bool _busy = false;

  Future<void> _decide(bool confirm) async {
    final c = widget.claim;
    final who = c.fullName ?? 'the tenant';
    final messenger = ScaffoldMessenger.of(context);
    final String? note;
    if (confirm) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Confirm ${rupees(c.amount)} from $who?'),
          content: Text('Only confirm after you see UTR ${c.utr} in your UPI app or bank. '
              'This records the payment for ${monthLabel(c.periodMonth)} and issues a receipt.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Back')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm payment'),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
      note = null;
    } else {
      note = await showApnivaasSheet<String>(
        context: context,
        builder: (_) => _RejectSheet(claim: c),
      );
      if (note == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(upiApiProvider).decide(c.claimId, confirm: confirm, note: note);
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(confirm
            ? 'Payment recorded. $who has been told.'
            : 'Marked as not found. $who has been told.'),
      ));
      if (confirm) refreshFees(ref);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Motion.readMessage,
        content: Text(stayErrorText(e)),
      ));
    } finally {
      ref.invalidate(pendingClaimsProvider(widget.hostelId));
      ref.invalidate(allClaimsProvider(widget.hostelId));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = widget.claim;
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
              Text(c.fullName ?? 'Tenant', style: t.textTheme.titleMedium),
              StatusChip(label: c.status.label, tone: toneForStatus(c.status.name), dot: true),
            ],
          ),
          if (c.roomNumber != null) Text('Room ${c.roomNumber}', style: muted),
          const SizedBox(height: Space.xs),
          Text('${rupees(c.amount)} for ${monthLabel(c.periodMonth)}',
              style: t.textTheme.titleSmall),
          SelectableText('UTR ${c.utr}', style: t.textTheme.bodyMedium),
          if (c.upiVpa != null) Text('To ${c.upiVpa}', style: muted),
          if (c.createdAt != null)
            Text('Reported on ${dayLabel(c.createdAt!.toLocal())}', style: muted),
          if (c.decisionNote != null) ...[
            const SizedBox(height: Space.xxs),
            Text('Note: ${c.decisionNote!}', style: muted),
          ],
          if (c.status == ClaimStatus.pending) ...[
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _decide(true),
                  child: Text(_busy ? 'Saving…' : 'Confirm'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Not found'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.claim});
  final PaymentClaim claim;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.claim;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          Space.lg, 0, Space.lg, Space.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitle(
              title: 'Payment not found?',
              subtitle: '${c.fullName ?? 'The tenant'} will be told, with your note. Nothing is '
                  'recorded.',
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Note',
                hintText: 'For example, no payment with this UTR reached my account',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: Space.sm),
            BusyFilledButton(
              label: 'Mark as not found',
              danger: true,
              onPressed: () {
                final n = _note.text.trim();
                if (n.isEmpty) {
                  setState(() => _error = 'Add a note saying why it was not found.');
                  return;
                }
                Navigator.of(context).pop(n);
              },
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}
