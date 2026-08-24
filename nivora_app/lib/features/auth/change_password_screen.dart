import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';

/// Set a new password.
///
/// WHY THIS SCREEN HAD TO EXIST. Every account this platform creates — owners made by the
/// super admin, staff made by an owner, students made by a warden — is created with
/// `must_change_password = true` and a temporary password shown to the creator exactly once.
/// The router sends any such account here before anything else. While this was a placeholder,
/// a brand-new owner who installed the app landed on a screen with no field, no button and no
/// way to sign out: locked out of the product on their very first login, by design rather than
/// by accident.
///
/// The rules mirror the web app's changePassword action deliberately, because the same person
/// may set their password on either client and must not meet two different policies:
///   - at least 8 characters, containing a letter and a digit
///   - the confirmation must match
///   - a FORCED change does not ask for the current password — the user just authenticated
///     with the temporary one. A VOLUNTARY change does, so that a stolen session cannot be
///     used to lock the real owner out. Which case applies is decided by the profile row the
///     server returned, never by anything this form sends.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool forced}) async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final message = await ref.read(authControllerProvider.notifier).changePassword(
          newPassword: _next.text,
          // Null for a forced change: the server-side rule is that reauthentication is only
          // demanded when the flag is not set, and sending a value here would not change that.
          currentPassword: forced ? null : _current.text,
        );

    // On success the flag clears, the router leaves this route and this widget is gone.
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final session = ref.watch(sessionProvider);
    // Read from the profile row, not from a route argument — the same reason the web app reads
    // it from the database: a client-supplied "this is forced" would skip reauthentication.
    final forced = session?.needsPasswordChange ?? true;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GlassCard(
                padding: const EdgeInsets.all(Space.xl),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'NIVORA',
                        style: t.textTheme.labelSmall?.copyWith(letterSpacing: 5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        forced ? 'Set your password' : 'Change your password',
                        style: t.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Space.xxs),
                      Text(
                        forced
                            ? 'Your account was created with a temporary password. Choose your own to continue.'
                            : 'Choose a new password for your account.',
                        style: t.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Space.xl),

                      // Only asked for a voluntary change. Showing it during a forced change
                      // would be asking for the temporary password the user just typed to
                      // get here, which reads as a bug to them.
                      if (!forced) ...[
                        TextFormField(
                          controller: _current,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Current password',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter your current password'
                              : null,
                        ),
                        const SizedBox(height: Space.sm),
                      ],

                      TextFormField(
                        controller: _next,
                        enabled: !_busy,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                          helperText: 'At least 8 characters, with a letter and a number',
                          helperMaxLines: 2,
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: _validateNew,
                      ),
                      const SizedBox(height: Space.sm),
                      TextFormField(
                        controller: _confirm,
                        enabled: !_busy,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(forced: forced),
                        decoration: const InputDecoration(
                          labelText: 'Confirm new password',
                          prefixIcon: Icon(Icons.check_circle_outline_rounded),
                        ),
                        validator: (v) =>
                            v != _next.text ? "Passwords don't match" : null,
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: Space.sm),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: t.textTheme.bodySmall
                                ?.copyWith(color: NivoraColors.error),
                          ),
                        ),
                      ],

                      const SizedBox(height: Space.lg),
                      FilledButton(
                        onPressed: _busy ? null : () => _submit(forced: forced),
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save password'),
                      ),
                      const SizedBox(height: Space.xs),
                      // The way out. Without this the screen is a trap for anyone who cannot
                      // complete it right now — the exact failure this file replaced.
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () =>
                                ref.read(authControllerProvider.notifier).signOut(),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Mirrors lib/validators/auth.ts. Kept as one function so the three rules stay together
  /// and cannot drift apart one edit at a time.
  String? _validateNew(String? v) {
    final value = v ?? '';
    if (value.length < 8) return 'Use at least 8 characters';
    if (value.length > 200) return 'That password is too long';
    if (!RegExp(r'[A-Za-z]').hasMatch(value)) return 'Include at least one letter';
    if (!RegExp(r'\d').hasMatch(value)) return 'Include at least one number';
    return null;
  }
}
