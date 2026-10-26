/// The provider buttons (round 3): 56dp round logo buttons in a row — Google always, Facebook
/// and Truecaller only when configured. Each brand's mark keeps its own colours.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/tokens.dart';
import '../../shared/clay/pressable.dart';

enum SocialProvider { google, facebook, truecaller }

/// One round logo button. The label is for screen readers ("Continue with Google").
class SocialCircleButton extends StatelessWidget {
  const SocialCircleButton({
    super.key,
    required this.provider,
    required this.busy,
    required this.onPressed,
  });

  final SocialProvider provider;
  final bool busy;
  final VoidCallback? onPressed;

  static const size = 56.0;

  /// Google's "G", as published with its sign-in button assets.
  static const _mark =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">'
      '<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
      '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>'
      '<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
      '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>'
      '<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 '
      '16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>'
      '<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
      '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>'
      '</svg>';

  /// Facebook's "f", white on its blue disc.
  static const _f =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#FFFFFF" '
      'd="M15.12 5.32H17V2.14A26 26 0 0 0 14.26 2c-2.72 0-4.58 1.66-4.58 4.7v2.62H6.61v3.56h3.07V22'
      'h3.68v-9.12h3.06l.46-3.56h-3.52V7.05c0-1.03.28-1.73 1.76-1.73z"/></svg>';

  String get label => switch (provider) {
        SocialProvider.google => 'Continue with Google',
        SocialProvider.facebook => 'Continue with Facebook',
        SocialProvider.truecaller => 'Continue with Truecaller',
      };

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color ink, BorderSide side) = switch (provider) {
      SocialProvider.google =>
        (Colors.white, const Color(0xFF1F1F1F), const BorderSide(color: Color(0xFF747775))),
      SocialProvider.facebook => (const Color(0xFF1877F2), Colors.white, BorderSide.none),
      SocialProvider.truecaller => (const Color(0xFF0087FF), Colors.white, BorderSide.none),
    };
    final enabled = onPressed != null;
    final Widget glyph = busy
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: ink),
          )
        : switch (provider) {
            SocialProvider.google => SvgPicture.string(_mark, width: 24, height: 24),
            SocialProvider.facebook => SvgPicture.string(_f, width: 26, height: 26),
            SocialProvider.truecaller => Icon(Icons.phone_in_talk_rounded, size: 26, color: ink),
          };
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled && !busy,
        scale: 0.94,
        child: AnimatedOpacity(
          duration: Motion.fast,
          opacity: enabled || busy ? 1 : 0.5,
          child: DecoratedBox(
            decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: Shadows.lift),
            child: Material(
              color: fill,
              shape: CircleBorder(side: side),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: busy ? null : onPressed,
                child: SizedBox.square(dimension: size, child: Center(child: glyph)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The row of round buttons, centred, wrapping if the screen is very narrow.
class SocialButtonRow extends StatelessWidget {
  const SocialButtonRow({super.key, required this.buttons});

  final List<SocialCircleButton> buttons;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        spacing: Space.lg,
        runSpacing: Space.sm,
        children: buttons,
      );
}

/// "──── or continue with ────".
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, this.label = 'or continue with'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rule =
        t.brightness == Brightness.dark ? t.colorScheme.outlineVariant : ApnivaasColors.rule;
    Widget line() => Expanded(
          child: Divider(color: rule, height: Strokes.hairline, thickness: Strokes.hairline),
        );
    return Row(
      children: [
        line(),
        Flexible(
          flex: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm - Space.hair),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        line(),
      ],
    );
  }
}
