import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';

/// Second factor.
///
/// Two bugs from the web build are designed out here rather than reimplemented:
///
/// 1. **Boxes that collapse to slivers.** The web version gave each of six slots `w-full`
///    alongside `flex-1`, so all six asked for 100% of the row; flex-shrink crushed them and
///    the only thing left visible was the blinking caret — the reported "small vertical lines".
///    Here each slot is an [Expanded] with a `minWidth` floor, so under-allocation is
///    impossible by construction.
///
/// 2. **A correct code reported wrong.** The web version submitted a value read back from
///    state, which had not flushed yet, so the server got the previous keystroke and rejected
///    it; pressing Verify a moment later worked. Here [_verify] is always called with the
///    string the field just produced, never with a re-read.
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

  Future<void> _verify(String code) async {
    final phase = ref.read(authControllerProvider).value;
    if (phase is! AuthNeedsMfa) return;
    await ref
        .read(authControllerProvider.notifier)
        .verifyMfa(factorId: phase.factorId, code: code);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final phase = ref.watch(authControllerProvider);
    final busy = phase.isLoading;
    final error = phase.hasError ? phase.error.toString() : null;
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
                    Stack(
                      children: [
                        Row(
                          children: [
                            for (var i = 0; i < _len; i++) ...[
                              if (i > 0) const SizedBox(width: Space.xs),
                              Expanded(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(minWidth: 36, minHeight: 56),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: t.colorScheme.surface,
                                      borderRadius: Radii.rControl,
                                      border: Border.all(
                                        color: error != null
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
                        // The real field, transparent over the boxes. Keeps paste, autofill and
                        // the OS one-time-code suggestion working — all of which a hand-rolled
                        // key handler throws away.
                        Positioned.fill(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focus,
                            enabled: !busy,
                            keyboardType: TextInputType.number,
                            maxLength: _len,
                            showCursor: false,
                            style: const TextStyle(
                                color: Colors.transparent, height: 0.01),
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                              filled: false,
                            ),
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (v) {
                              setState(() {});
                              // `v` is what the field just produced. Never re-read state here.
                              if (v.length == _len && !busy) _verify(v);
                            },
                          ),
                        ),
                      ],
                    ),
                    if (error != null) ...[
                      const SizedBox(height: Space.sm),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          style: t.textTheme.bodySmall
                              ?.copyWith(color: NivoraColors.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.lg),
                    FilledButton(
                      onPressed:
                          (busy || code.length < _len) ? null : () => _verify(code),
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
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
