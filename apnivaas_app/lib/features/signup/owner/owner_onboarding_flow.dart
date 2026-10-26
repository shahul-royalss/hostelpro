/// An owner's onboarding after sign-up (docs/self-signup-onboarding-spec.md, Flow 3):
///
///     Tell us about your PG  →  "Your first month is free" sheet  →  Book a free demo (or Skip)
///
/// It runs inside [SignupGate], behind every existing gate (MFA, consent, password, email).
/// [onFinished] hands back to the gate, which re-reads the hostels and the profile and opens the
/// owner home.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/clay/clay.dart';
import '../../common/form_parts.dart';
import 'book_demo_screen.dart';
import 'pg_details_screen.dart';

class OwnerOnboardingFlow extends StatefulWidget {
  const OwnerOnboardingFlow({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OwnerOnboardingFlow> createState() => _OwnerOnboardingFlowState();
}

class _OwnerOnboardingFlowState extends State<OwnerOnboardingFlow> {
  CreatedPg? _created;

  Future<void> _onCreated(CreatedPg created) async {
    if (created.alreadySetUp) {
      // A double tap or a retry: the PG exists. Nothing to celebrate twice.
      widget.onFinished();
      return;
    }
    await showTrialSheet(context, trialEnd: created.hostel.trialEnd);
    if (!mounted) return;
    setState(() => _created = created);
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: created == null
          ? PgDetailsScreen(key: const ValueKey('pg'), onCreated: _onCreated)
          : BookDemoScreen(
              key: const ValueKey('demo'),
              pgName: created.name,
              city: created.city,
              onDone: widget.onFinished,
            ),
    );
  }
}

/// "Your first month is free", with the trial's end date and one button.
Future<void> showTrialSheet(BuildContext context, {DateTime? trialEnd}) {
  return showApnivaasSheet<void>(
    context: context,
    builder: (ctx) {
      final t = Theme.of(ctx);
      final until = trialEnd == null ? null : DateFormat('d MMMM yyyy').format(trialEnd);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: ClayIcon(ClayIcons.success, size: 112)),
            const SizedBox(height: Space.md),
            Semantics(
              header: true,
              child: Text(
                'Your first month is free',
                textAlign: TextAlign.center,
                style: t.textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              until == null
                  ? 'Your PG is live. Everything is open to you for the first month.'
                  : 'Your PG is live. Everything is open to you until $until.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.lg),
            BusyFilledButton(
              label: 'Start my free month',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    },
  );
}
