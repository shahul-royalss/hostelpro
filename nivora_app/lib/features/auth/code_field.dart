library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';

/// Six boxes that are really one text field.
///
/// EXTRACTED FROM `mfa_screen.dart`, NOT REWRITTEN. The app now asks for a 6-digit code in two
/// places — the second factor at sign-in, and proving an email address — and the second one is
/// where a copy-paste would have gone. Both of the bugs below were found in the web build and
/// paid for once; a duplicate implementation is how you pay for them twice.
///
/// 1. **Boxes that collapse to slivers.** The web version gave each of six slots `w-full`
///    alongside `flex-1`, so all six asked for 100% of the row; flex-shrink crushed them and
///    the only thing left visible was the blinking caret — the reported "small vertical lines".
///    Here each slot is an [Expanded] with a `minWidth` floor, so under-allocation is
///    impossible by construction.
///
/// 2. **A correct code reported wrong.** The web version submitted a value read back from
///    state, which had not flushed yet, so the server got the previous keystroke and rejected
///    it; pressing Verify a moment later worked. [onCompleted] is therefore called with the
///    string the field JUST produced, never with a re-read — and callers must pass that value
///    through rather than reaching for their own controller.
///
/// The real field is a transparent [TextField] laid over the boxes rather than a hand-rolled
/// key handler, which is what keeps paste, autofill and the OS one-time-code suggestion
/// working. On a verification screen that last one matters more than anywhere else in the app:
/// the code is sitting in an email the phone can already read.
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onCompleted,
    this.enabled = true,
    this.hasError = false,
    this.length = 6,
    this.osAutofill = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Fired on every keystroke, so the caller can repaint the filled boxes.
  final ValueChanged<String> onChanged;

  /// Fired once the field holds [length] digits, with THAT value. See bug 2 above.
  final ValueChanged<String> onCompleted;

  final bool enabled;

  /// Paints every box in the error tone — the whole code was rejected, not one digit of it.
  final bool hasError;

  final int length;

  /// Whether to advertise this field to the OS one-time-code autofill service.
  ///
  /// OFF by default, and that default is the point. Android's autofill can only offer a code it
  /// can SEE — one that arrived by SMS or mail. A TOTP code does not arrive: it is computed
  /// inside an authenticator app that no autofill service can read. So on the two-factor screen
  /// the hint can never produce a suggestion, while still paying the cost: declaring
  /// `oneTimeCode` makes the platform open an autofill session on focus and re-establish it
  /// every time the app returns to the foreground — which is precisely the moment a user comes
  /// back from their authenticator and starts typing. Cost with no possible benefit.
  ///
  /// The email-verification screen turns it ON, where the code really is in the user's inbox
  /// and the suggestion is the difference between typing six digits and tapping once.
  final bool osAutofill;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final code = controller.text;

    return Stack(
      children: [
        Row(
          children: [
            for (var i = 0; i < length; i++) ...[
              if (i > 0) const SizedBox(width: Space.xs),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 56),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.colorScheme.surface,
                      borderRadius: Radii.rControl,
                      border: Border.all(
                        color: hasError
                            ? NivoraColors.error
                            : i == code.length
                                ? t.colorScheme.primary
                                : t.colorScheme.outline,
                        width: i == code.length ? 1.8 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        i < code.length ? code[i] : '',
                        style: t.textTheme.headlineMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        Positioned.fill(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            keyboardType: TextInputType.number,
            maxLength: length,
            showCursor: false,
            // Only where a code can actually be autofilled. See [osAutofill].
            autofillHints: osAutofill ? const [AutofillHints.oneTimeCode] : null,
            style: const TextStyle(color: Colors.transparent, height: 0.01),
            // EVERY border variant, not just `border`. InputDecoration.border is only the
            // FALLBACK: the theme's InputDecorationTheme sets enabledBorder/focusedBorder/
            // errorBorder as OutlineInputBorders, and those win whenever they are non-null. With
            // only `border` cleared, this invisible overlay still painted one rounded rectangle
            // across the whole row — on top of the six cells drawn underneath — which is exactly
            // the stray box the owner reported. contentPadding and isDense go too: this field
            // exists to catch keystrokes, and any geometry it contributes shifts the digits.
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) {
              onChanged(v);
              // `v` is what the field just produced. Never re-read state here.
              if (v.length == length && enabled) onCompleted(v);
            },
          ),
        ),
      ],
    );
  }
}
