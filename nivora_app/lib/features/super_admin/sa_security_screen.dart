library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import '../common/refresh.dart';
import 'data/sa_models.dart';
import 'data/sa_providers.dart';
import 'widgets/sa_ui.dart';

/// SA-5 — the security console.
///
/// TABLE: public.security_alerts.  RPC: public.ack_security_alert(bigint).
///
/// ── WHAT THESE ROWS ARE ──────────────────────────────────────────────────────────────────
///
/// Not log lines. `app.detect_suspicious_activity()` runs as a trigger on every audit_log
/// insert and raises a row here only when it recognises a PATTERN — a burst of failed logins, a
/// session probing for rows it is not allowed to read, a privilege change out of hours. The
/// audit trail records what happened; this is the part that looks at it. One alert per
/// (kind, actor) per hour while unacknowledged, so a sustained attack produces one actionable
/// row rather than four thousand.
///
/// ── WHY ACKNOWLEDGEMENT IS AN RPC AND NOT A CHECKBOX ─────────────────────────────────────
///
/// `security_alerts` has a SELECT policy and no write policy at all — not an UPDATE, not a
/// DELETE. Anybody able to edit an alert could erase the evidence of their own session, so the
/// only mutation the database permits is `ack_security_alert()`, which stamps
/// `acknowledged_by = auth.uid()` and carries `where acknowledged_at is null` so it cannot
/// rewrite who saw it first. There is deliberately no way to dismiss, delete or edit an alert
/// from this screen, because there is deliberately no way to do it at all.
class SaSecurityScreen extends ConsumerWidget {
  const SaSecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(saAlertFilterProvider);
    final alerts = ref.watch(saAlertsProvider(filter.openOnly));

    // security_alerts has a SELECT policy and no write policy, so a caller it does not admit
    // reads ZERO ROWS rather than being refused — the same shape as the platform RPCs. An empty
    // security log and a security log this account cannot read are very different sentences to
    // put in front of a platform administrator, so the dashboard corroborates here too.
    final verdict = saEmptyVerdict(ref.watch(saStatsProvider));

    return SaScreen(
      title: 'Security',
      subtitle: 'Patterns the audit trail flagged',
      scrollable: false,
      child: Column(
        children: [
          _Filters(selected: filter),
          Expanded(
            child: saAsync<List<SecurityAlert>>(
              alerts,
              loading: () => ListView(
                padding: const EdgeInsets.all(Space.md),
                children: const [
                  SaSkeletonCard(lines: 2, height: 130),
                  SizedBox(height: Space.sm),
                  SaSkeletonCard(lines: 2, height: 130),
                  SizedBox(height: Space.sm),
                  SaSkeletonCard(lines: 2, height: 130),
                ],
              ),
              error: (e) => ListView(
                padding: const EdgeInsets.all(Space.md),
                children: [
                  SaError(
                    error: e,
                    onRetry: () => ref.invalidate(saAlertsProvider(filter.openOnly)),
                  ),
                ],
              ),
              data: (rows) => _AlertList(
                alerts: rows,
                filter: filter,
                verdict: verdict,
                onRecheck: () {
                  ref.invalidate(saStatsProvider);
                  ref.invalidate(saAlertsProvider(filter.openOnly));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.selected});
  final AlertFilter selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
        children: [
          for (final option in AlertFilter.values) ...[
            ChoiceChip(
              label: Text(option.label),
              selected: selected == option,
              onSelected: (_) => ref.read(saAlertFilterProvider.notifier).set(option),
            ),
            const SizedBox(width: Space.xs),
          ],
        ],
      ),
    );
  }
}

class _AlertList extends ConsumerWidget {
  const _AlertList({
    required this.alerts,
    required this.filter,
    required this.verdict,
    required this.onRecheck,
  });

  final List<SecurityAlert> alerts;
  final AlertFilter filter;

  /// What an empty read of security_alerts means, corroborated by rpc_sa_dashboard.
  ///
  /// LOWER STAKES THAN THE HOSTELS TAB, AND STILL WORTH GETTING RIGHT. "Nothing outstanding" is
  /// the sentence a platform admin most wants to be true and least wants to be a rendering
  /// accident: an empty security console is either the quietest possible good news or the
  /// loudest possible bad news, and those cannot share a screen.
  final SaEmptyVerdict verdict;

  /// Re-runs both reads. The only exit from [SaEmptyVerdict.unverified].
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (alerts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(Space.md),
        children: [
          switch (verdict) {
            SaEmptyVerdict.pending => const SaSkeletonCard(lines: 2, height: 130),

            SaEmptyVerdict.unverified => SaUnverified(
                title: 'The alert log came back empty, and we cannot say why',
                message: 'No alerts were returned, and the dashboard read this console checks '
                    'that against could not be read either. A quiet week and a log this '
                    'account cannot see look the same from here, so neither is being claimed.',
                onRetry: onRecheck,
                action: filter.openOnly
                    ? OutlinedButton.icon(
                        onPressed: () =>
                            ref.read(saAlertFilterProvider.notifier).set(AlertFilter.all),
                        icon: const Icon(Icons.history_rounded, size: IconSize.sm),
                        label: const Text('Read the history'),
                      )
                    : null,
              ),

            SaEmptyVerdict.refused => const SaNotPermitted(),

            // NOT SaNotPermitted, and not SaUnverified's "check again" either. The read
            // that would have explained this emptiness died with the access token, so the
            // only honest thing on screen is the way to get a live one.
            SaEmptyVerdict.credentialDead => const SaSessionEnded(),

            SaEmptyVerdict.confirmed => SaEmpty(
                icon: Icons.shield_outlined,
                tone: NivoraDomain.security.tone,
                title: filter.openOnly ? 'Nothing outstanding' : 'No alerts on record',
                message: filter.openOnly
                    ? 'Every alert the detector has raised has been acknowledged. Switch to All '
                        'to read the history.'
                    : 'The detector has not recognised a suspicious pattern yet. This stays '
                        'empty while nothing unusual is happening, which is the point of it.',
              ),
          },
        ],
      );
    }

    // Worst first among the open ones, then by time. The server orders by time alone, which is
    // right for a history and wrong for a queue: a critical raised an hour ago matters more
    // than a low raised a minute ago.
    final sorted = [...alerts]..sort((a, b) {
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        final severity = b.severity.rank.compareTo(a.severity.rank);
        if (severity != 0) return severity;
        return b.at.compareTo(a.at);
      });

    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(saAlertsProvider(filter.openOnly));
        return settleRefresh(
            context, () => ref.read(saAlertsProvider(filter.openOnly).future));
      },
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          Space.md,
          Space.xs,
          Space.md,
          Space.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, index) =>
            SaAlertCard(alert: sorted[index], openOnly: filter.openOnly),
      ),
    );
  }
}

/// One alert, with everything the detector recorded and the single action the database allows.
class SaAlertCard extends ConsumerStatefulWidget {
  const SaAlertCard({super.key, required this.alert, required this.openOnly});

  final SecurityAlert alert;
  final bool openOnly;

  @override
  ConsumerState<SaAlertCard> createState() => _SaAlertCardState();
}

class _SaAlertCardState extends ConsumerState<SaAlertCard> {
  bool _busy = false;
  bool _expanded = false;

  Future<void> _acknowledge() async {
    if (_busy) return;
    final userId = ref.read(sessionProvider)?.userId;
    // A MISSING SESSION USED TO RETURN IN SILENCE. The stamp on the row is `acknowledged_by`,
    // so there is genuinely nothing to write without a signed-in user — but a button that
    // reports nothing at all is the bug class this release exists to remove, and this is the
    // exact shape of it: tap, nothing, no spinner, no sentence. It happens for real when the
    // token dies while the console is open.
    if (userId == null) {
      _say('Your sign-in has ended, so this cannot be recorded against you. Sign in again.');
      return;
    }

    setState(() => _busy = true);
    final failure = await ref
        .read(saAlertsProvider(widget.openOnly).notifier)
        .acknowledge(widget.alert.id, userId);
    if (!mounted) return;
    setState(() => _busy = false);

    if (failure != null) {
      // A refusal here is not hypothetical: ack_security_alert() raises 42501 for anybody who
      // is neither the Super Admin nor the owner of the alert's hostel. Said in the failure's
      // own words rather than as "something went wrong".
      _say(failure.message);
    }
  }

  void _say(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: Motion.readMessage,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final alert = widget.alert;
    final tone = severityTone(context, alert.severity);

    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // NO SHIELD PLATE HERE. Every row on this console is a security alert, on the
              // tab whose own destination is a gold shield — so a gold shield at the head of
              // each of them identified nothing the tab and the row had not already said, and
              // it sat 8dp from a severity-toned pill, which is the one mark on this row that
              // actually varies. The identifying glyph that EARNS its colour is the pill's:
              // gpp_maybe for an urgent alert, an info circle for the rest, in the severity's
              // own tone. Domain colour still opens this screen — on the tab, and on the
              // section heading over on the Overview.
              SaPill(
                label: alert.severity.label,
                tone: tone,
                icon: alert.severity.isUrgent
                    ? Icons.gpp_maybe_rounded
                    : Icons.info_outline_rounded,
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  _humanKind(alert.kind),
                  style: t.textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(relativeTime(alert.at), style: t.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(alert.summary, style: t.textTheme.bodyLarge),
          const SizedBox(height: Space.xs),
          Text(stampLabel(alert.at), style: t.textTheme.bodySmall),

          if (alert.ip != null || alert.hostelId != null || alert.details.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: IconSize.sm,
                ),
                label: Text(_expanded ? 'Hide detail' : 'Show detail'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
            ),
            if (_expanded) _Evidence(alert: alert),
          ],

          const SizedBox(height: Space.xs),
          Divider(height: Space.md, color: t.colorScheme.outlineVariant),
          if (alert.isOpen)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Acknowledging records that you have seen this. It cannot be edited or '
                    'deleted — by anyone.',
                    style: t.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: Space.xs),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _acknowledge,
                  // The app theme's FilledButton minimum is Size.fromHeight(48) — full width,
                  // right for a form's primary action, but INFINITE inside this Row, whose
                  // unbounded width made the first real alert row ever rendered crash the
                  // console. Bounded here; the 48dp tap height is kept.
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded, size: IconSize.sm),
                  label: const Text('Acknowledge'),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: IconSize.sm, color: context.tones.success),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(
                    alert.acknowledgedAt == null
                        ? 'Acknowledged'
                        : 'Acknowledged ${relativeTime(alert.acknowledgedAt!)}',
                    style: t.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 'failed_login_burst' → 'Failed login burst'.
  ///
  /// Humanised, never matched on. `kind` is free text written by the detector in
  /// db/schema.sql, and a client that switched on known values would render a new detector's
  /// alerts as blank until the app shipped again — the exact moment an unrecognised alert is
  /// the one worth reading.
  static String _humanKind(String kind) {
    final words = kind.replaceAll('_', ' ').trim();
    if (words.isEmpty) return 'Alert';
    return words[0].toUpperCase() + words.substring(1);
  }
}

/// Everything the detector recorded, rendered as it was stored.
///
/// NOT INTERPRETED. `details` is jsonb whose keys are whatever the trigger put there; printing
/// the pairs means a detector added next month is readable here without a client release.
class _Evidence extends StatelessWidget {
  const _Evidence({required this.alert});
  final SecurityAlert alert;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final entries = alert.details.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: Space.xs),
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest,
        borderRadius: Radii.rControl,
        border: Border.all(color: t.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alert.ip != null) _Line(label: 'IP', value: alert.ip!),
          if (alert.actorUserId != null) _Line(label: 'Actor', value: alert.actorUserId!),
          if (alert.hostelId != null) _Line(label: 'Hostel', value: alert.hostelId!),
          for (final entry in entries)
            _Line(label: entry.key, value: '${entry.value}'),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label.toUpperCase(), style: t.textTheme.labelSmall),
          ),
          const SizedBox(width: Space.xs),
          Expanded(child: SelectableText(value, style: t.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
