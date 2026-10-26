/// "Who's using Apnivaas?" — step 2 of the first launch (docs/self-signup-onboarding-spec.md,
/// Flow 1; design canvas RolePicker.dc.html): three horizontal cards, one picked, and a button
/// that says what happens next.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/social_sign_in.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../shared/clay/clay.dart';
import '../auth/auth_scaffold.dart';
import '../common/form_parts.dart';
import 'persona_store.dart';
import 'signup_widgets.dart';

enum _Pick { owner, tenant, staff }

class RolePickerScreen extends ConsumerStatefulWidget {
  const RolePickerScreen({super.key});

  @override
  ConsumerState<RolePickerScreen> createState() => _RolePickerScreenState();
}

class _RolePickerScreenState extends ConsumerState<RolePickerScreen> {
  _Pick? _picked;

  static const _cards = <_Pick, ({String title, String desc, String art, String cta})>{
    _Pick.owner: (
      title: 'Owner',
      desc: 'I run a PG or hostel',
      art: ClayIcons.roleOwner,
      cta: 'Continue as owner',
    ),
    _Pick.tenant: (
      title: 'Tenant',
      desc: 'I stay in, or am looking for, a PG',
      art: ClayIcons.roleTenant,
      cta: 'Continue as tenant',
    ),
    _Pick.staff: (
      title: 'Staff',
      desc: 'I work at a PG as a manager or warden',
      art: ClayIcons.roleWarden,
      cta: 'Continue as staff',
    ),
  };

  void _continue() {
    final pick = _picked ?? _initial;
    switch (pick) {
      case _Pick.owner:
        ref.read(pendingPersonaProvider.notifier).pick(SignupPersona.owner);
        context.go(createAccountRoute);
      case _Pick.tenant:
        ref.read(pendingPersonaProvider.notifier).pick(SignupPersona.tenant);
        context.go(createAccountRoute);
      case _Pick.staff:
        ref.read(pendingPersonaProvider.notifier).pick(SignupPersona.staff);
        context.go(createAccountRoute);
    }
  }

  /// A persona remembered from an earlier visit is pre-picked; otherwise Owner, as on the canvas.
  _Pick get _initial => switch (ref.read(pendingPersonaProvider)) {
        SignupPersona.tenant => _Pick.tenant,
        SignupPersona.staff => _Pick.staff,
        _ => _Pick.owner,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    ref.watch(pendingPersonaProvider);
    final picked = _picked ?? _initial;
    return SignupPage(
      children: [
        const SizedBox(height: Space.md),
        const StepIndicator(step: 2),
        const SizedBox(height: Space.md),
        const AuthHeading(title: "Who's using Apnivaas?", message: 'Pick one to get started.'),
        const SizedBox(height: Space.lg),
        for (final e in _cards.entries) ...[
          _PersonaCard(
            title: e.value.title,
            desc: e.value.desc,
            art: e.value.art,
            selected: picked == e.key,
            onTap: () => setState(() => _picked = e.key),
          ),
          const SizedBox(height: Space.sm),
        ],
        if (picked == _Pick.staff) ...[
          const InfoNote(
            message: 'Already have a login from your owner? Sign in instead.',
          ),
          const SizedBox(height: Space.sm),
        ],
        const SizedBox(height: Space.xs),
        BusyFilledButton(label: _cards[picked]!.cta, onPressed: _continue),
        const SizedBox(height: Space.xxs),
        Center(
          child: TextButton(
            onPressed: () => context.go('/login'),
            child: Text(
              'I already have an account — Sign in',
              textAlign: TextAlign.center,
              style: t.textTheme.labelLarge,
            ),
          ),
        ),
      ],
    );
  }
}

/// One persona: art on the left, words in the middle, a radio on the right. Announced as a
/// selectable button so a screen reader hears "Owner, I run a PG or hostel, selected".
class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.title,
    required this.desc,
    required this.art,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String desc;
  final String art;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final dark = t.brightness == Brightness.dark;
    final ring = selected ? scheme.primary : scheme.outlineVariant;
    final fill = selected
        ? (dark ? ApnivaasColors.darkSelected : ApnivaasColors.selectedSurface)
        : scheme.surfaceContainerLowest;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $desc',
      excludeSemantics: true,
      child: PressScale(
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.surface),
            side: BorderSide(color: ring, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 104),
              child: Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: Row(
                  children: [
                    ClayIcon(art, size: 72),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title, style: t.textTheme.titleLarge),
                          const SizedBox(height: Space.xxs),
                          Text(
                            desc,
                            style: t.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Icon(
                      selected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: selected ? scheme.primary : scheme.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
