/// Choose your language (round 5): the FIRST step on a new phone, before the tour and before
/// "Who are you?", and a row in every profile to change it later.
///
/// The heading is written in all six languages at once, because the person who most needs this
/// screen may not read the English line. Picking a language previews it on the screen; Continue
/// keeps it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/i18n/language.dart';
import '../../core/theme/tokens.dart';
import '../../shared/clay/clay.dart';
import '../../shared/glass/glass.dart';
import '../auth/auth_scaffold.dart';
import '../common/form_parts.dart';

/// Shows [child] once this phone has a language; until then, the picker.
class LanguageGate extends ConsumerWidget {
  const LanguageGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // As OnboardingGate does: the child while the small file is read, the picker only once it
    // is known that nothing was chosen. A phone that chose long ago never sees a flash of it.
    return switch (ref.watch(languageProvider)) {
      AsyncData(value: null) => const LanguagePickerScreen(),
      _ => child,
    };
  }
}

class LanguagePickerScreen extends ConsumerStatefulWidget {
  const LanguagePickerScreen({super.key});

  @override
  ConsumerState<LanguagePickerScreen> createState() => _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends ConsumerState<LanguagePickerScreen> {
  AppLanguage _picked = AppLanguage.english;
  bool _saving = false;

  /// The heading in every language, so it is read whatever the reader's script.
  static String _everyLanguage(String english) => [
        for (final l in AppLanguage.values)
          if (l != AppLanguage.english) translate(english, l.code),
      ].join('  ·  ');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    String say(String english) => translate(english, _picked.code);
    return AuthScaffold(
      topBar: const SizedBox.shrink(),
      children: [
        const SizedBox(height: Space.lg),
        const Center(child: ClayIcon(ClayIcons.apnivaasMark, size: ClaySize.banner)),
        const SizedBox(height: Space.md),
        Semantics(
          header: true,
          child: Text(
            say('Choose your language'),
            textAlign: TextAlign.center,
            style: t.textTheme.displaySmall,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          _everyLanguage('Choose your language'),
          textAlign: TextAlign.center,
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.lg),
        for (final l in AppLanguage.values) ...[
          LanguageOption(
            language: l,
            selected: l == _picked,
            onTap: _saving ? null : () => setState(() => _picked = l),
          ),
          const SizedBox(height: Space.xs),
        ],
        const SizedBox(height: Space.md),
        BusyFilledButton(
          label: say('Continue'),
          busy: _saving,
          onPressed: () async {
            setState(() => _saving = true);
            await ref.read(languageProvider.notifier).choose(_picked);
          },
        ),
        const SizedBox(height: Space.sm),
        Text(
          say('You can change it any time in your profile.'),
          textAlign: TextAlign.center,
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// One language: its own name large, the English name under it, a tick when chosen.
class LanguageOption extends StatelessWidget {
  const LanguageOption({
    super.key,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      label: '${language.nativeName}, ${language.englishName}',
      excludeSemantics: true,
      child: FlatSurface(
        borderRadius: Radii.rSurface,
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(language.nativeName, style: t.textTheme.titleLarge),
                  if (language != AppLanguage.english)
                    Text(
                      language.englishName,
                      style: t.textTheme.bodySmall
                          ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? t.colorScheme.primary : t.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile → Language: the same six, changed in place.
Future<void> showLanguageSheet(BuildContext context) {
  return showApnivaasSheet<void>(
    context: context,
    title: context.tr('Language'),
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final current = ref.watch(languageProvider).value ?? AppLanguage.english;
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final l in AppLanguage.values) ...[
                LanguageOption(
                  language: l,
                  selected: l == current,
                  onTap: () async {
                    await ref.read(languageProvider.notifier).choose(l);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
                const SizedBox(height: Space.xs),
              ],
            ],
          ),
        );
      },
    ),
  );
}

/// The row profiles carry: "Language · हिन्दी".
class LanguageRow extends ConsumerWidget {
  const LanguageRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(languageProvider).value ?? AppLanguage.english;
    return ListRow(
      icon: ClayIcons.settings,
      title: 'Language',
      subtitle: current.nativeName,
      onTap: () => showLanguageSheet(context),
    );
  }
}
