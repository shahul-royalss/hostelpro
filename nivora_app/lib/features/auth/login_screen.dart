import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';

/// Sign in. One field for both audiences: staff type an email, students type their phone
/// number, and resolveLoginEmail() maps the latter onto the synthetic address the database
/// uses. That mapping has to match the web app exactly or the same person cannot sign in on
/// both clients.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _obscure = true;
  // Submission state is local on purpose. It used to live in the shared auth provider, which
  // the router watches — so tapping Sign in read as "still restoring the session" and pushed
  // the user to the splash screen mid-login.
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = await ref
        .read(authControllerProvider.notifier)
        .signIn(identifier: _id.text, password: _pw.text);
    // On success the router navigates away and this widget is gone, so guard the setState.
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final busy = _busy;
    final error = _error;

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
                      Text('Welcome back',
                          style: t.textTheme.headlineMedium, textAlign: TextAlign.center),
                      const SizedBox(height: Space.xxs),
                      Text('Sign in to your PG workspace',
                          style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
                      const SizedBox(height: Space.xl),
                      TextFormField(
                        controller: _id,
                        enabled: !busy,
                        autofillHints: const [AutofillHints.username],
                        // Neither strictly email nor strictly phone: both are valid logins.
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email or phone number',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your email or phone number'
                            : null,
                      ),
                      const SizedBox(height: Space.sm),
                      TextFormField(
                        controller: _pw,
                        enabled: !busy,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Enter your password' : null,
                      ),
                      if (error != null) ...[
                        const SizedBox(height: Space.sm),
                        // Announced to a screen reader, and never a driver message.
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error,
                            style: t.textTheme.bodySmall
                                ?.copyWith(color: NivoraColors.error),
                          ),
                        ),
                      ],
                      const SizedBox(height: Space.lg),
                      FilledButton(
                        onPressed: busy ? null : _submit,
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: Space.xs),
                      Text('Accounts are created by your administrator.',
                          style: t.textTheme.bodySmall, textAlign: TextAlign.center),
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
}
