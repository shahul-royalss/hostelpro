/// The pieces every sign-up and onboarding page shares: the step indicator, the page frame (the
/// sign-in screen's own [AuthScaffold], so the round reads as one product), the ask-in-words
/// dialog, and a wrapping set of choice pills.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../auth/auth_scaffold.dart';

/// "Step 2 of 4" and a segmented bar. The words carry the meaning; the bar is decoration.
class StepIndicator extends StatelessWidget {
  const StepIndicator({super.key, required this.step, this.of = 4});

  final int step;
  final int of;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final on = t.colorScheme.primary;
    final off = t.colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step $step of $of',
          style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.xs),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 1; i <= of; i++) ...[
                if (i > 1) const SizedBox(width: Space.xxs),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    height: 6,
                    decoration: BoxDecoration(
                      color: i <= step ? on : off,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The page frame for every onboarding step: the sign-in screen's scaffold and top bar, with an
/// optional back arrow and, once there is an account, Sign out (nobody is ever trapped in a
/// step they cannot finish).
class SignupPage extends ConsumerWidget {
  const SignupPage({
    super.key,
    required this.children,
    this.onBack,
    this.showSignOut = false,
    this.footer,
  });

  final List<Widget> children;
  final VoidCallback? onBack;
  final bool showSignOut;
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AuthScaffold(
      footer: footer,
      topBar: AuthTopBar(
        leading: onBack == null
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onBack,
              ),
        trailing: showSignOut
            ? TextButton(
                onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                child: const Text('Sign out'),
              )
            : null,
      ),
      children: children,
    );
  }
}

/// THE WORDS BEFORE THE SYSTEM PROMPT. Answers true only on an explicit "Continue".
Future<bool> askInWords(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Continue',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(confirm)),
      ],
    ),
  );
  return ok ?? false;
}

/// One-of-several pills that wrap onto as many lines as the text size needs.
class ChoicePills<T> extends StatelessWidget {
  const ChoicePills({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final Map<T, String> options;
  final T? selected;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final e in options.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: e.key == selected,
            onSelected: enabled ? (_) => onSelected(e.key) : null,
          ),
      ],
    );
  }
}

/// A small label above a group of pills, matching the form's field labels.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.error});
  final String text;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: t.textTheme.titleSmall),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xxs),
              child: Text(error!,
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

/// Indian mobile numbers as the server accepts them: 10 digits, `+91` and spaces allowed.
/// The server checks again; this only saves a round trip.
bool looksLikeIndianMobile(String raw) {
  var d = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (d.startsWith('+91')) d = d.substring(3);
  return RegExp(r'^[6-9]\d{9}$').hasMatch(d);
}
