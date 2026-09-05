import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/aurora.dart';
import '../../shared/beam_card.dart';
import '../../shared/glass/glass.dart';

/// Sign in — `screen-signin`, node 4:60.
///
/// One field for both audiences: staff type an email, students type their phone number, and
/// resolveLoginEmail() maps the latter onto the synthetic address the database uses. That
/// mapping has to match the web app exactly or the same person cannot sign in on both clients.
///
/// ── WHAT THE RESTYLE CHANGED, AND WHAT IT DID NOT ────────────────────────────────────────
///
/// Changed, all of it from the design's own nodes: the wordmark is the design's wordmark
/// (4:69, 24/ExtraBold — it was a 10px tracked-out label), the heading is the design's
/// heading step (4:73, 20/700), and the block rhythm is the design's own — 24 between blocks,
/// 12 between fields. The input fill, the hairline and the cream CTA come from the theme,
/// which already carries 4:77 and 4:83 verbatim.
///
/// NOT changed, deliberately: everything about what this screen DOES. The 15-second deadline
/// on each network step and the "The Nivora server is not responding right now" sentence both
/// live in [AuthController] and were added to fix a real field failure — a wedged backend
/// completes the TLS handshake and then answers nothing, so the button span forever and the
/// person holding the phone could not tell a dead server from a slow one. This is a restyle.
/// It does not get to touch that.
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

  /// Ask for an address and send a reset link to it.
  ///
  /// The confirmation is deliberately the SAME whether or not that address has an account.
  /// Saying "no such user" here would turn this screen into a way to discover which people
  /// live in a PG, which is precisely the kind of question a resident's address should not
  /// answer to a stranger.
  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _id.text.trim());
    final formKey = GlobalKey<FormState>();

    final email = await showGlassSheet<String>(
      context: context,
      builder: (sheetContext) {
        final t = Theme.of(sheetContext);
        return Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reset your password', style: t.textTheme.titleLarge),
              const SizedBox(height: Space.xxs),
              Text(
                'Enter the email address you sign in with. We will send you a link to set a '
                'new password.',
                style: t.textTheme.bodySmall,
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter your email address' : null,
              ),
              const SizedBox(height: Space.lg),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.of(sheetContext).pop(controller.text.trim());
                },
                child: const Text('Send the link'),
              ),
              const SizedBox(height: Space.xs),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );

    if (email == null || !mounted) return;
    setState(() => _busy = true);
    final problem =
        await ref.read(authControllerProvider.notifier).sendPasswordReset(email);
    if (!mounted) return;
    setState(() => _busy = false);

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          problem ??
              'If that address has an account, a reset link is on its way. Check your inbox.',
        ),
      ),
    );
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

  /// Why the router put us here, when it was not the user's own doing.
  ///
  /// [AuthSignedOut] has carried a `message` for as long as it has existed, and NOTHING HAS
  /// EVER READ IT. Three sentences were being composed with care and then dropped on the floor:
  /// "This account has been deactivated", "Your account is not set up yet. Contact your
  /// administrator", and — since the cold-start restore got a deadline — the server-down
  /// sentence. A user who was signed out mid-session for any of those reasons was simply
  /// teleported to an empty login form, which reads as "the app forgot me" and is answered by
  /// typing the same correct password again and being thrown out again.
  ///
  /// LOADING, EMPTY, FAILED and REFUSED are four states everywhere else in this app. A refusal
  /// rendered as a blank form is that rule broken on the one screen every user reaches.
  String? _arrivalMessage() {
    final phase = ref.watch(authControllerProvider).value;
    return phase is AuthSignedOut ? phase.message : null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final busy = _busy;
    // This attempt's own failure first: it is about what the user just typed, and it replaces
    // whatever brought them here. The arrival message is suppressed while a submission is in
    // flight so a stale reason cannot sit under a spinner.
    final error = _error ?? (busy ? null : _arrivalMessage());

    return Scaffold(
      // TRANSPARENT so the aurora underneath is the ground. Scaffold would otherwise paint its
      // own opaque background over it and the glow would never be seen.
      backgroundColor: Colors.transparent,
      body: AuroraField(
        child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: BeamCard(
                padding: const EdgeInsets.all(Space.xl),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 4:69 — the design's wordmark, 24/ExtraBold. displayMedium is that step,
                      // and it is the same mark at the same size the splash opens with, so the
                      // launch animation resolves INTO this screen rather than being replaced
                      // by a different logo.
                      Text(
                        'NIVORA',
                        style: t.textTheme.displayMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Space.md),
                      // 4:73. titleLarge is the design's 20/700 heading; headlineMedium is the
                      // same metrics with TABULAR figures, which is a stat card's slot, not a
                      // sentence's.
                      Text('Welcome back',
                          style: t.textTheme.titleLarge, textAlign: TextAlign.center),
                      const SizedBox(height: Space.xxs),
                      // 4:74 — body 13/400.
                      Text('Sign in to your PG workspace',
                          style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
                      // The design's block gap on this screen.
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
                        //
                        // Two corrections here. The colour is `context.tones.error`, the
                        // theme-resolved TEXT red, not NivoraColors.error — that one is the
                        // canonical graphic red and measures 4.05:1 on this card, which is
                        // below AA for type; tokens.dart says in as many words not to set
                        // small text in it. And the size is the design's running text (13)
                        // rather than its metadata step (11), because the longest thing this
                        // line ever says is the two-sentence server-down message and 11px is
                        // not a size to read a paragraph at.
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error,
                            style: t.textTheme.bodyMedium
                                ?.copyWith(color: context.tones.error),
                          ),
                        ),
                      ],
                      const SizedBox(height: Space.xl),
                      FilledButton(
                        onPressed: busy ? null : _submit,
                        child: busy
                            ? SizedBox(
                                width: IconSize.md,
                                height: IconSize.md,
                                // onPrimary, not the theme's progress colour: the default is
                                // the gold, and gold on the cream button is a pairing you
                                // cannot see. In BOTH themes onPrimary is the same value the
                                // filled button already uses for its label.
                                child: CircularProgressIndicator(
                                    strokeWidth: Strokes.glyph,
                                    color: t.colorScheme.onPrimary),
                              )
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: Space.xs),
                      // HERE, not behind a signed-in settings screen. A person who has
                      // forgotten their password is standing on THIS screen and cannot get
                      // past it; a recovery link anywhere else is a door on the inside of a
                      // locked room.
                      TextButton(
                        onPressed: busy ? null : _forgotPassword,
                        child: const Text('Forgot your password?'),
                      ),
                      // 4:86 puts a gold "Contact your hostel admin" here. It is a STATEMENT
                      // in this build, not the design's link: gold means interactive
                      // everywhere else in this app, and there is nothing a signed-out client
                      // could open — the app holds no support address, and a user with no
                      // session cannot be shown their own hostel's contact details. A control
                      // that cannot act is worse than a plain sentence.
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
      ),
    );
  }
}
