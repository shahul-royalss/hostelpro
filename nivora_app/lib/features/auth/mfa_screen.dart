import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';
import 'code_field.dart';

/// Second factor.
///
/// The six-digit entry — and the two web-build bugs designed out of it — now lives in
/// [CodeField], because the app asks for a 6-digit code here AND on the email-verification
/// screen, and those bugs are not worth paying for twice. This screen keeps what is specific
/// to a second factor: the wording, and the fact that a rejected code clears the field.
class MfaScreen extends ConsumerStatefulWidget {
  const MfaScreen({super.key});
  @override
  ConsumerState<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends ConsumerState<MfaScreen> {
  static const _len = 6;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Local for the same reason as the login form: the router watches the shared auth state,
  // so putting an in-flight verification there navigated away from this screen mid-check.
  bool _busy = false;
  String? _error;

  Future<void> _verify(String code) async {
    // ONE VERIFICATION AT A TIME. [CodeField] fires `onCompleted` the moment the sixth digit
    // lands and the button below is also live at six digits, so a user who types the last digit
    // and taps Verify could send the same code twice. That is not free: the server allows six
    // codes per ten minutes per account (LIMITS.mfaVerifyPerUser), a TOTP cannot be presented
    // twice, and the second attempt would spend a slot and come back rejected — the person is
    // then told their correct code was wrong.
    if (_busy) return;

    final phase = ref.read(authControllerProvider).value;
    if (phase is! AuthNeedsMfa) {
      // THIS USED TO `return` IN SILENCE, and a button that does nothing is the same bug as a
      // button that spins forever: the code field sits there, the tap is swallowed, and there is
      // nothing on screen to act on. The phase can genuinely change under this screen — the
      // first factor's session can end while the code is being typed — so say what happened.
      setState(() {
        _busy = false;
        _error = 'Your sign-in ended before this code could be checked. '
            'Sign in again to carry on.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final message = await ref
        .read(authControllerProvider.notifier)
        .verifyMfa(factorId: phase.factorId, code: code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
    // A rejected code leaves the field holding a value the user must clear to retry.
    if (message != null) {
      _controller.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final busy = _busy;
    final error = _error;
    final code = _controller.text;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GlassCard(
                padding: const EdgeInsets.all(Space.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Two-factor authentication',
                        style: t.textTheme.titleLarge, textAlign: TextAlign.center),
                    const SizedBox(height: Space.xxs),
                    Text('Enter the 6-digit code from your authenticator app.',
                        style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
                    const SizedBox(height: Space.xl),
                    CodeField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: !busy,
                      hasError: error != null,
                      length: _len,
                      onChanged: (_) => setState(() {}),
                      onCompleted: _verify,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: Space.sm),
                      Semantics(
                        liveRegion: true,
                        // The theme-resolved TEXT red, not NivoraColors.error. That one is the
                        // canonical GRAPHIC red — it measures 4.05:1 on this card, which is
                        // below AA for type, and tokens.dart says outright not to set small
                        // text in it. The sign-in and create-password screens carried the same
                        // mistake; all three now go through context.tones. Size is the design's
                        // running text rather than its 11px metadata step, because the longest
                        // sentence here is "Codes change every 30 seconds — try the current
                        // one."
                        child: Text(
                          error,
                          style: t.textTheme.bodyMedium
                              ?.copyWith(color: context.tones.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.lg),
                    FilledButton(
                      onPressed:
                          (busy || code.length < _len) ? null : () => _verify(code),
                      child: busy
                          ? SizedBox(
                              width: IconSize.md,
                              height: IconSize.md,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.onPrimary),
                            )
                          : const Text('Verify and continue'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => ref.read(authControllerProvider.notifier).signOut(),
                      child: const Text('Use a different account'),
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
