/// "Set a new password": where the "Forgot password" email's link lands (round 5).
///
/// The router shows this only while [passwordRecoveryProvider] holds, i.e. after gotrue has
/// exchanged the link's code for a session. Saving sets the password on that session, then signs
/// out everywhere ([AuthController.completePasswordRecovery]), so the person signs in with the
/// new password and every sign-in check runs. An account with a second factor may be asked for
/// its 6-digit code first.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../core/auth/auth_controller.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/tokens.dart';
import '../../shared/clay/clay.dart';
import '../common/form_parts.dart';
import 'auth_scaffold.dart';
import 'password_policy.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.email});

  /// The address the link was for; read from the session when not given (tests give it).
  final String? email;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _needsCode = false;
  String? _error;

  @override
  void dispose() {
    _next.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  String? get _email {
    if (widget.email != null) return widget.email;
    try {
      return Supabase.instance.client.auth.currentUser?.email;
    } catch (_) {
      return null; // No client (a test without one): the heading simply leaves it out.
    }
  }

  Future<void> _save() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await ref.read(authControllerProvider.notifier).completePasswordRecovery(
          _next.text,
          code: _needsCode ? _code.text : null,
        );
    // On success the router has already moved to sign-in and this screen is gone.
    if (!mounted) return;
    setState(() {
      _busy = false;
      _needsCode = outcome.needsCode;
      _error = outcome.error ??
          (outcome.needsCode
              ? 'Your account uses an authenticator app. Enter its 6-digit code to finish.'
              : null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final email = _email;
    return AuthScaffold(
      children: [
        const SizedBox(height: Space.md),
        AuthHeading(
          icon: ClayIcons.security,
          title: 'Set a new password',
          message: email == null
              ? 'Choose a new password for your account.'
              : 'Choose a new password for $email.',
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('reset-new'),
                controller: _next,
                enabled: !_busy,
                obscureText: _obscure,
                autofillHints: null,
                textInputAction: TextInputAction.next,
                scrollPadding: keepVisibleBelow(context, Space.xs + 64),
                decoration: InputDecoration(
                  labelText: context.tr('New password'),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon:
                        Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: validateNewPassword,
              ),
              const SizedBox(height: Space.xs),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _next,
                builder: (context, value, _) => PasswordStrengthMeter(password: value.text),
              ),
              const SizedBox(height: Space.sm),
              TextFormField(
                key: const ValueKey('reset-confirm'),
                controller: _confirm,
                enabled: !_busy,
                obscureText: _obscure,
                autofillHints: null,
                textInputAction: _needsCode ? TextInputAction.next : TextInputAction.done,
                onFieldSubmitted: (_) => _needsCode ? null : _save(),
                scrollPadding: keepVisibleBelow(context, Space.xl + 52 + Space.xxs + 48),
                decoration: InputDecoration(labelText: context.tr('Confirm new password')),
                validator: (v) => v != _next.text ? "Passwords don't match" : null,
              ),
              if (_needsCode) ...[
                const SizedBox(height: Space.sm),
                TextFormField(
                  key: const ValueKey('reset-code'),
                  controller: _code,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: null,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onFieldSubmitted: (_) => _save(),
                  decoration: InputDecoration(labelText: context.tr('Code from your authenticator app')),
                  validator: (v) =>
                      (v ?? '').trim().length == 6 ? null : 'Enter the 6-digit code.',
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: Space.sm),
                FormNote(_error!, tone: _needsCode && _error!.startsWith('Your account')
                    ? FormNoteTone.warning
                    : FormNoteTone.error),
              ],
              const SizedBox(height: Space.xl),
              BusyFilledButton(
                label: 'Save new password',
                busy: _busy,
                onPressed: _save,
              ),
              const SizedBox(height: Space.xxs),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => ref.read(authControllerProvider.notifier).abandonPasswordRecovery(),
                child: const Text('Back to sign in'),
              ),
              const SizedBox(height: Space.sm),
              const InfoNote(
                icon: Icons.lock_outline_rounded,
                message: 'After saving, every phone signed in to this account is signed out. '
                    'Sign in again with your new password.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
