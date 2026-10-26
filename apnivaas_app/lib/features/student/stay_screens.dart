/// The tenant's stay (round 3): Timeline (R2) and Request check-out (R6). Both are pushed from
/// Profile. Every refusal is the server's sentence.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/failure.dart';
import '../../data/models/stay.dart';
import '../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../data/repositories/stay_repository.dart';
import '../../shared/clay/clay.dart';
import '../common/form_parts.dart';
import 'widgets/common.dart';
import 'widgets/format.dart';

/// The sentence for a failed read or write.
String stayErrorText(Object e) => e is SignupFailure ? e.message : AppFailure.from(e).message;

/// A sub-page frame: the forest header with a back button, then a scrolling body.
class _StayPage extends StatelessWidget {
  const _StayPage({required this.title, required this.children, this.onRefresh});

  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          Space.md, Space.md, Space.md, Space.xxxl + MediaQuery.paddingOf(context).bottom),
      children: children,
    );
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(leading: const HeaderBackButton(), title: title),
          Expanded(
            child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormNote(stayErrorText(error)),
          const SizedBox(height: Space.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      );
}

StatusTone toneForStatus(String? status) => switch (status) {
      'paid' || 'resolved' || 'closed' || 'completed' || 'accepted' || 'confirmed' =>
        StatusTone.success,
      'partial' || 'pending' || 'in_progress' || 'submitted' => StatusTone.warning,
      'unpaid' || 'declined' || 'rejected' || 'open' => StatusTone.error,
      _ => StatusTone.neutral,
    };

String statusWord(String status) {
  final s = status.replaceAll('_', ' ');
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Timeline ────────────────────────────────────────────────────────────────────────────────

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const TimelineScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = ref.watch(myTimelineProvider);
    return _StayPage(
      title: 'Timeline',
      onRefresh: () async {
        ref.invalidate(myTimelineProvider);
        await ref.read(myTimelineProvider.future).catchError((_) => <TimelineEntry>[]);
      },
      children: [
        timeline.when(
          skipLoadingOnRefresh: true,
          loading: () => const Column(children: [
            SkeletonCard(lines: 2),
            SizedBox(height: Space.sm),
            SkeletonCard(lines: 2),
          ]),
          error: (e, _) =>
              _LoadError(error: e, onRetry: () => ref.invalidate(myTimelineProvider)),
          data: (entries) => entries.isEmpty
              ? const EmptyState(
                  title: 'Nothing here yet',
                  body: 'Your stay appears here from the day you check in.',
                  icon: ClayIcons.calendar,
                )
              : TimelineList(entries: entries),
        ),
      ],
    );
  }
}

/// The entries, newest first, on a rail.
class TimelineList extends StatelessWidget {
  const TimelineList({super.key, required this.entries});
  final List<TimelineEntry> entries;

  static IconData iconFor(TimelineKind kind) => switch (kind) {
        TimelineKind.checkedIn => Icons.login_rounded,
        TimelineKind.room => Icons.bed_outlined,
        TimelineKind.due => Icons.event_note_outlined,
        TimelineKind.payment => Icons.payments_outlined,
        TimelineKind.complaint => Icons.build_outlined,
        TimelineKind.checkoutRequest => Icons.outbox_outlined,
        TimelineKind.checkoutDecision => Icons.fact_check_outlined,
        TimelineKind.checkedOut => Icons.logout_rounded,
        TimelineKind.upiClaim => Icons.qr_code_2_rounded,
        TimelineKind.other => Icons.circle_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, e) in entries.indexed)
          _TimelineRow(entry: e, last: i == entries.length - 1),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.last});
  final TimelineEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final status = entry.status;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: t.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(TimelineList.iconFor(entry.kind),
                      size: 18, color: t.colorScheme.onPrimaryContainer),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: t.colorScheme.outlineVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : Space.md),
              child: Semantics(
                container: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, style: t.textTheme.titleSmall),
                    if (entry.detail != null) ...[
                      const SizedBox(height: Space.hair),
                      Text(entry.detail!, style: t.textTheme.bodyMedium),
                    ],
                    const SizedBox(height: Space.xxs),
                    Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(dayLabel(entry.at.toLocal()), style: muted),
                        if (entry.amount != null && entry.amount! > 0)
                          Text(rupees(entry.amount!), style: t.textTheme.labelLarge),
                        if (status != null)
                          StatusChip(label: statusWord(status), tone: toneForStatus(status)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Check-out ───────────────────────────────────────────────────────────────────────────────

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const CheckoutScreen());

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _reason = TextEditingController();
  DateTime? _date;
  bool _busy = false;
  String? _error;
  String? _dateError;
  String? _reasonError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? _today,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 90)),
      helpText: 'Preferred check-out date',
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _dateError = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_date == null) {
      setState(() => _dateError = 'Choose a date from today up to 90 days ahead.');
      return;
    }
    if (_reason.text.trim().length > 300) {
      setState(() => _reasonError = 'Keep the reason under 300 characters.');
      return;
    }
    await _run(() => ref
        .read(stayApiProvider)
        .requestCheckout(preferredDate: _date!, reason: _reason.text));
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel your check-out request?'),
        content: const Text('Your warden will no longer see it. You can ask again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cancel request')),
        ],
      ),
    );
    if (ok == true) await _run(() => ref.read(stayApiProvider).cancelCheckoutRequest());
  }

  Future<void> _run(Future<Object?> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
      _dateError = null;
      _reasonError = null;
    });
    try {
      await body();
      ref.invalidate(myCheckoutRequestProvider);
      ref.invalidate(myTimelineProvider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _date = null;
        _reason.clear();
      });
    } catch (e) {
      if (!mounted) return;
      final field = e is SignupFailure ? e.field : null;
      setState(() {
        _busy = false;
        if (field == 'date') {
          _dateError = stayErrorText(e);
        } else if (field == 'reason') {
          _reasonError = stayErrorText(e);
        } else {
          _error = stayErrorText(e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(myCheckoutRequestProvider);
    return _StayPage(
      title: 'Check-out',
      onRefresh: () async {
        ref.invalidate(myCheckoutRequestProvider);
        await ref.read(myCheckoutRequestProvider.future).catchError((_) => null);
      },
      children: [
        request.when(
          skipLoadingOnRefresh: true,
          loading: () => const SkeletonCard(lines: 3),
          error: (e, _) =>
              _LoadError(error: e, onRetry: () => ref.invalidate(myCheckoutRequestProvider)),
          data: (r) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (r != null) ...[
                CheckoutStatusCard(request: r),
                const SizedBox(height: Space.md),
              ],
              if (r != null && r.status == CheckoutStatus.pending)
                OutlinedButton(
                  onPressed: _busy ? null : _cancel,
                  child: const Text('Cancel request'),
                ),
              if (r == null || !r.status.isOpen) _form(context),
              if (_error != null) ...[
                const SizedBox(height: Space.sm),
                FormNote(_error!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Request check-out', style: t.textTheme.titleMedium),
        const SizedBox(height: Space.xxs),
        Text(
          'Tell your warden when you plan to leave. Once they accept, your bed is freed on that '
          'date and later rent stops.',
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.md),
        InkWell(
          onTap: _busy ? null : _pickDate,
          borderRadius: BorderRadius.circular(Radii.control),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Preferred date',
              errorText: _dateError,
              errorMaxLines: 3,
              suffixIcon: const Icon(Icons.calendar_today_outlined),
            ),
            child: Text(_date == null ? 'Choose a date' : dayLabel(_date!)),
          ),
        ),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _reason,
          enabled: !_busy,
          minLines: 2,
          maxLines: 4,
          maxLength: 300,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Reason (optional)',
            errorText: _reasonError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: Space.sm),
        BusyFilledButton(
          label: 'Request check-out',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

/// The request as it stands: status, dates, and the warden's note.
class CheckoutStatusCard extends StatelessWidget {
  const CheckoutStatusCard({super.key, required this.request});
  final CheckoutRequest request;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = request;
    final facts = <(String, String)>[
      ('Preferred date', dayLabel(r.preferredDate)),
      if (r.checkoutDate != null) ('Check-out date', dayLabel(r.checkoutDate!)),
      if (r.reason != null) ('Reason', r.reason!),
      if (r.decisionNote != null) ('Note from the PG', r.decisionNote!),
    ];
    final line = switch (r.status) {
      CheckoutStatus.pending => 'Your warden has your request.',
      CheckoutStatus.accepted =>
        'Accepted. You will be checked out on ${dayLabel(r.checkoutDate ?? r.preferredDate)}.',
      CheckoutStatus.completed => 'You have been checked out.',
      CheckoutStatus.declined => 'Your request was declined. You can ask again.',
      CheckoutStatus.cancelled => 'You cancelled this request.',
    };
    return OutlineCard(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Your check-out request', style: t.textTheme.titleSmall),
              StatusChip(
                label: r.status.label,
                tone: toneForStatus(r.status.name),
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(line, style: t.textTheme.bodyMedium),
          for (final f in facts) ...[
            const SizedBox(height: Space.xs),
            DetailRow(label: f.$1, value: f.$2),
          ],
        ],
      ),
    );
  }
}
