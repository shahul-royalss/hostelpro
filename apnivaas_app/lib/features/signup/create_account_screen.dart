/// Create your account — step 3 (docs/round3-spec.md R1).
///
/// The manual form on top (`signup_password`), then "or continue with" and the round provider
/// buttons. Facebook and Truecaller are drawn only when configured. Every refusal is the
/// server's own sentence. After sign-up the router takes over: consent, then onboarding.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/google_id_token.dart';
import '../../core/auth/social_sign_in.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../shared/clay/clay.dart';
import '../auth/auth_scaffold.dart';
import '../auth/password_policy.dart';
import '../auth/social_buttons.dart';
import '../common/form_parts.dart';
import '../legal/legal_screen.dart';
import 'persona_store.dart';
import 'signup_widgets.dart';

enum _Busy { form, google, facebook, truecaller }

/// Email shape only; the server decides the rest.
bool looksLikeEmail(String raw) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(raw.trim());

/// A 6-digit Indian pincode (no leading zero).
bool looksLikePincode(String raw) => RegExp(r'^[1-9]\d{5}$').hasMatch(raw.trim());

class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _city = TextEditingController();
  final _pincode = TextEditingController();
  bool _obscure = true;
  _Busy? _busy;
  String? _error;
  Map<String, String> _serverErrors = const {};

  @override
  void initState() {
    super.initState();
    _password.addListener(_onPassword);
  }

  void _onPassword() => setState(() {});

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password, _confirm, _city, _pincode]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _server(String key) => _serverErrors[key];

  Future<void> _submit(SignupPersona persona) async {
    if (_busy != null) return;
    setState(() => _serverErrors = const {});
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = _Busy.form;
      _error = null;
    });
    final personas = ref.read(pendingPersonaProvider.notifier);
    final withAddress = persona != SignupPersona.staff;
    final attempt = await ref.read(authControllerProvider.notifier).signUpWithPassword(
          persona: persona,
          fullName: _name.text,
          phone: _phone.text,
          email: _email.text,
          password: _password.text,
          city: withAddress ? _city.text : null,
          pincode: withAddress ? _pincode.text : null,
        );
    if (attempt.signedIn) personas.clear();
    if (!mounted) return;
    setState(() {
      _busy = null;
      _serverErrors = attempt.fieldErrors;
      // A field error is shown under its field; the note carries every other refusal.
      _error = attempt.fieldErrors.isEmpty ? attempt.message : null;
    });
    if (attempt.fieldErrors.isNotEmpty) _form.currentState?.validate();
  }

  Future<void> _social(_Busy provider, SignupPersona persona) async {
    if (_busy != null) return;
    setState(() {
      _busy = provider;
      _error = null;
    });
    // Captured before the await: on success the router replaces this screen.
    final auth = ref.read(authControllerProvider.notifier);
    final personas = ref.read(pendingPersonaProvider.notifier);
    final attempt = switch (provider) {
      _Busy.facebook => await auth.continueWithFacebook(persona: persona),
      _Busy.truecaller => await auth.continueWithTruecaller(persona: persona),
      _ => await auth.continueWithGoogle(persona: persona),
    };
    if (attempt.signedIn) personas.clear();
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = attempt.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final persona = ref.watch(pendingPersonaProvider);
    final google = ref.watch(googleIdTokenSourceProvider);
    final facebook = ref.watch(facebookCredentialSourceProvider);
    final truecaller = ref.watch(truecallerCredentialSourceProvider);
    final busy = _busy != null;

    if (persona == null) {
      // Reached without a pick (a stale link, or the hint was cleared): the pick comes first.
      return SignupPage(
        onBack: () => context.go(startRoute),
        children: [
          const SizedBox(height: Space.xl),
          const AuthHeading(
            title: 'Create your account',
            message: 'First, tell us whether you run a PG, stay in one or work at one.',
          ),
          const SizedBox(height: Space.lg),
          BusyFilledButton(label: 'Choose who you are', onPressed: () => context.go(startRoute)),
        ],
      );
    }

    final (message, art) = switch (persona) {
      SignupPersona.owner => ('You are signing up as an owner.', ClayIcons.roleOwner),
      SignupPersona.tenant => ('You are signing up as a tenant.', ClayIcons.roleTenant),
      SignupPersona.staff => (
          'You are signing up as staff. Next, you ask a PG to add you.',
          ClayIcons.roleWarden,
        ),
    };
    final withAddress = persona != SignupPersona.staff;
    final providers = <SocialCircleButton>[
      if (google.isAvailable)
        SocialCircleButton(
          provider: SocialProvider.google,
          busy: _busy == _Busy.google,
          onPressed: busy ? null : () => _social(_Busy.google, persona),
        ),
      if (facebook.isAvailable)
        SocialCircleButton(
          provider: SocialProvider.facebook,
          busy: _busy == _Busy.facebook,
          onPressed: busy ? null : () => _social(_Busy.facebook, persona),
        ),
      if (truecaller.isAvailable)
        SocialCircleButton(
          provider: SocialProvider.truecaller,
          busy: _busy == _Busy.truecaller,
          onPressed: busy ? null : () => _social(_Busy.truecaller, persona),
        ),
    ];
    Widget gap() => const SizedBox(height: Space.sm);

    return SignupPage(
      onBack: busy ? null : () => context.go(startRoute),
      footer: const _Terms(),
      children: [
        const SizedBox(height: Space.md),
        const StepIndicator(step: 3),
        const SizedBox(height: Space.md),
        AuthHeading(title: 'Create your account', message: message, icon: art),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: busy ? null : () => context.go(startRoute),
            child: const Text('Not you? Change'),
          ),
        ),
        AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('signup-name'),
                  controller: _name,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) {
                    final n = (v ?? '').trim().length;
                    return _server('fullName') ??
                        (n < 2 || n > 80 ? 'Enter a name between 2 and 80 characters.' : null);
                  },
                ),
                gap(),
                TextFormField(
                  key: const ValueKey('signup-phone'),
                  controller: _phone,
                  enabled: !busy,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                  decoration: const InputDecoration(labelText: 'Mobile number'),
                  validator: (v) =>
                      _server('phone') ??
                      (looksLikeIndianMobile(v ?? '')
                          ? null
                          : 'Enter a valid 10-digit mobile number.'),
                ),
                gap(),
                TextFormField(
                  key: const ValueKey('signup-email'),
                  controller: _email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) =>
                      _server('email') ??
                      (looksLikeEmail(v ?? '') ? null : 'Enter a valid email address'),
                ),
                gap(),
                TextFormField(
                  key: const ValueKey('signup-password'),
                  controller: _password,
                  enabled: !busy,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => _server('password') ?? validateNewPassword(v),
                ),
                if (_password.text.isNotEmpty) ...[
                  const SizedBox(height: Space.xs),
                  PasswordStrengthMeter(password: _password.text),
                ],
                gap(),
                TextFormField(
                  key: const ValueKey('signup-confirm'),
                  controller: _confirm,
                  enabled: !busy,
                  obscureText: _obscure,
                  textInputAction: withAddress ? TextInputAction.next : TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                  validator: (v) => v == _password.text ? null : "The two passwords don't match",
                ),
                if (withAddress) ...[
                  gap(),
                  TextFormField(
                    key: const ValueKey('signup-city'),
                    controller: _city,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.addressCity],
                    decoration: const InputDecoration(labelText: 'City'),
                    validator: (v) {
                      final n = (v ?? '').trim().length;
                      return _server('city') ?? (n < 2 || n > 60 ? 'Enter your city.' : null);
                    },
                  ),
                  gap(),
                  TextFormField(
                    key: const ValueKey('signup-pincode'),
                    controller: _pincode,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.postalCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(labelText: 'Pincode'),
                    validator: (v) =>
                        _server('pincode') ??
                        (looksLikePincode(v ?? '') ? null : 'Enter a valid 6-digit pincode.'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.sm),
          FormNote(_error!),
        ],
        const SizedBox(height: Space.md),
        BusyFilledButton(
          label: 'Create account',
          busy: _busy == _Busy.form,
          onPressed: busy ? null : () => _submit(persona),
        ),
        if (providers.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          const OrDivider(),
          const SizedBox(height: Space.md),
          SocialButtonRow(buttons: providers),
        ],
        const SizedBox(height: Space.md),
        Center(
          child: TextButton(
            onPressed: busy ? null : () => context.go('/login'),
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

class _Terms extends StatelessWidget {
  const _Terms();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('By continuing you agree to the', style: muted, textAlign: TextAlign.center),
        TextButton(
          onPressed: () => openLegal(context, initial: 'terms'),
          child: const Text('Terms'),
        ),
        Text('and', style: muted),
        TextButton(
          onPressed: () => openLegal(context, initial: 'privacy'),
          child: const Text('Privacy Policy'),
        ),
      ],
    );
  }
}
