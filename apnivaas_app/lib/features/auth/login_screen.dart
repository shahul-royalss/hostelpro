import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/google_id_token.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../shared/clay/sheet.dart';
import '../../shared/glass/glass.dart';
import '../../shared/wordmark.dart';
import '../common/form_parts.dart';
import '../legal/legal_screen.dart';
import 'auth_scaffold.dart';
import 'social_buttons.dart';

/// Sign in — the sign-in board of the design canvas (`SignIn.dc.html`).
///
/// One field for both audiences: staff type an email, students type their phone number, and
/// resolveLoginEmail() maps the latter onto the synthetic address the database uses. That
/// mapping has to match the web app exactly or the same person cannot sign in on both clients.
///
/// ROUND 3 LAYOUT: the centred brand logo and "Apnivaas", then the form, the round Google
/// button and "New here? Create an account". The documents stay linked at the foot; agreeing
/// is the separate consent step after sign-in (features/legal/consent_gate.dart).
///
/// NOT changed either: everything about what this screen DOES. The 15-second deadline on each
/// network step and the server-not-responding sentence ([serverNotResponding]) both live in
/// [AuthController] and were added to fix a real field failure — a wedged backend completes the
/// TLS handshake and then answers nothing, so the button span forever and the person holding the
/// phone could not tell a dead server from a slow one. The quiet Google attempt, the error room
/// that keeps the button still, the keyboard scroll padding and the arrival message are all as
/// they were. This is a restyle. It does not get to touch any of that.
///
/// The page is anchored to the top ([AuthScaffold]), so opening the keyboard or showing an error
/// moves nothing above the button. The why, with the measurements, is on that class.
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
  // Google has its own flag so its spinner sits on its own button: the quiet attempt below runs
  // without anyone pressing anything, and a spinner on "Sign in" would read as "I pressed that".
  bool _googleBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // "Automated": a returning Google user is signed straight back in. After a deliberate
    // sign-out there is nothing to restore — AuthController.signOut makes the phone forget the
    // Google account — so this does nothing for them, and nothing at all in a build without Google.
    WidgetsBinding.instance.addPostFrameCallback((_) => _google(quietly: true));
  }

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  /// "Continue with Google", or — [quietly] — the automatic attempt when the screen opens.
  Future<void> _google({bool quietly = false}) async {
    if (!mounted || _busy || _googleBusy) return;
    if (!ref.read(googleIdTokenSourceProvider).isAvailable) return;
    // Not when the router brought us here to say why (deactivated, not set up): a quiet attempt
    // would only repeat the refusal over the top of the sentence explaining it.
    if (quietly) {
      final phase = ref.read(authControllerProvider).value;
      if (phase is AuthSignedOut && phase.message != null) return;
    }
    if (!quietly) FocusScope.of(context).unfocus();
    setState(() {
      _googleBusy = true;
      if (!quietly) _error = null;
    });
    final attempt =
        await ref.read(authControllerProvider.notifier).continueWithGoogle(quietly: quietly);
    // On success the router navigates away and this widget is gone.
    if (!mounted) return;
    // NO ACCOUNT FOR THIS GOOGLE ADDRESS: "Who are you?" is where an account is made
    // (docs/self-signup-api.md §1.1). Branched on the code, never on the sentence, and never
    // for the quiet attempt nobody asked for.
    if (!quietly && attempt.noAccount) {
      setState(() => _googleBusy = false);
      GoRouter.of(context).go(startRoute);
      return;
    }
    final message = attempt.message;
    setState(() {
      _googleBusy = false;
      if (message != null && !(quietly && attempt.noAccount)) _error = message;
    });
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
        return Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetTitle(
                title: 'Reset your password',
                subtitle: 'Enter the email address you sign in with. We will send you a link to '
                    'set a new password.',
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
  ///
  /// ── AND THE ERROR ARM, WHICH WAS THE OTHER HALF OF THE SAME BUG ─────────────────────────
  ///
  /// `.value` is null on an AsyncError, so a restore that FAILED — rather than one that
  /// completed and decided to sign you out — fell straight through this to `null`. That is the
  /// no-network cold start: the app holds a perfectly good saved session, cannot reach the
  /// server to refresh it, spends its retry budget, and lands the user on an empty form with
  /// nothing said. They then type the correct password into a device with no network and are
  /// told nothing again.
  ///
  /// It is also the single most common real-world case, because it is every metro, lift and
  /// dropped connection. The restore's own doc-comment calls a mute arrival at this screen the
  /// exact failure it was written to kill; it killed the infinite splash and left this behind.
  String? _arrivalMessage() {
    final auth = ref.watch(authControllerProvider);

    final phase = auth.value;
    if (phase is AuthSignedOut && phase.message != null) return phase.message;

    // A failed restore says so, in the user's terms rather than the exception's. There is
    // nothing for them to fix by typing, so the sentence points at the one thing that is
    // actually wrong.
    if (auth.hasError) {
      return 'We could not reach Apnivaas to check your session. Your details are safe — check '
          'your connection and sign in again.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final busy = _busy || _googleBusy;
    final google = ref.watch(googleIdTokenSourceProvider);
    // This attempt's own failure first: it is about what the user just typed, and it replaces
    // whatever brought them here. The arrival message is suppressed while a submission is in
    // flight so a stale reason cannot sit under a spinner.
    final error = _error ?? (busy ? null : _arrivalMessage());

    // ROOM FOR TWO LINES OF ERROR, KEPT WHETHER OR NOT ONE IS SHOWING. An error that appears
    // or disappears must not move the button the user is about to press again: the common
    // refusals ("That login or password is not right.", "Cannot reach Apnivaas. Check your
    // connection and try again.") fit in two lines of the running-text step on a 360 dp phone,
    // so they land in space that was already there. Only a longer message — the server-down
    // paragraph — grows the form, and it grows DOWNWARD: the page is anchored to the top, so
    // nothing above it moves either way.
    final bodyStyle = t.textTheme.bodyMedium;
    final errorSlot = MediaQuery.textScalerOf(context).scale(bodyStyle?.fontSize ?? 13) *
        (bodyStyle?.height ?? 1.4) *
        2;

    return AuthScaffold(
      footer: const _Foot(),
      // Round 3: no brand bar and no hero card — the logo itself heads the page.
      topBar: const SizedBox.shrink(),
      children: [
        const SizedBox(height: Space.lg),
        const _BrandLogo(),
        const SizedBox(height: Space.lg),
        Semantics(
          header: true,
          child: Text('Welcome back', style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
        ),
        const SizedBox(height: Space.xxs),
        Text(
          'Use the email or phone number on your account.',
          textAlign: TextAlign.center,
          style: bodyStyle?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.md),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _id,
                enabled: !busy,
                autofillHints: const [AutofillHints.username],
                // Neither strictly email nor strictly phone: both are valid logins.
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                // Keeps the password field, the error room and Sign in above the keyboard when
                // this field is scrolled into view — on a 360x640 phone Sign in sat UNDER the
                // keyboard with the focus here.
                scrollPadding: keepVisibleBelow(
                  context,
                  Space.sm + 56 + Space.xs + errorSlot + Space.xs + 52 + Space.md,
                ),
                decoration: const InputDecoration(
                  // 'Email or phone', not '… phone number': the longer label was cut to
                  // 'Email or phone num…' at text scale 1.4 on a 360 dp phone, and a label
                  // that is cut off is a label nobody can read. The validator below still
                  // says "phone number" in full, where the line is free to wrap.
                  labelText: 'Email or phone',
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
                scrollPadding: keepVisibleBelow(
                  context,
                  Space.xs + errorSlot + Space.xs + 52 + Space.md,
                ),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
              ),
              const SizedBox(height: Space.xs),
              // Announced to a screen reader, and never a driver message. [FormNote] sets it in
              // the theme-resolved TEXT red with a glyph in front, never colour alone, at the
              // running-text size: the longest thing this line ever says is the two-sentence
              // server-down message, and the metadata step is not a size to read a paragraph at.
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: errorSlot),
                child: error == null ? const SizedBox.shrink() : FormNote(error),
              ),
              const SizedBox(height: Space.xs),
              BusyFilledButton(
                label: 'Sign in',
                busy: _busy,
                onPressed: busy ? null : _submit,
              ),
              const SizedBox(height: Space.xxs),
              // HERE, not behind a signed-in settings screen. A person who has forgotten their
              // password is standing on THIS screen and cannot get past it; a recovery link
              // anywhere else is a door on the inside of a locked room.
              Center(
                child: TextButton(
                  onPressed: busy ? null : _forgotPassword,
                  child: const Text('Forgot your password?'),
                ),
              ),
            ],
          ),
        ),
        // Only in a build that carries a Web client ID (Env.googleWebClientId). A button that
        // can only fail is worse than no button.
        if (google.isAvailable) ...[
          const SizedBox(height: Space.sm),
          const OrDivider(),
          const SizedBox(height: Space.md),
          SocialButtonRow(buttons: [
            SocialCircleButton(
              provider: SocialProvider.google,
              busy: _googleBusy,
              onPressed: busy ? null : _google,
            ),
          ]),
        ],
        const SizedBox(height: Space.sm),
        // SELF SIGN-UP (1.3.0): owners and tenants make their own account from "Who are you?".
        Center(
          child: TextButton(
            onPressed: busy ? null : () => GoRouter.of(context).go(startRoute),
            child: const Text('New here? Create an account'),
          ),
        ),
      ],
    );
  }
}

/// The brand mark, about 112dp wide and sharp at any density, with "Apnivaas" in Outfit.
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  static const asset = 'assets/brand/apnivaas_logo.webp';
  static const width = 112.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      label: 'Apnivaas',
      excludeSemantics: true,
      child: Column(
        children: [
          Image.asset(
            asset,
            width: width,
            height: width * 349 / 480,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) =>
                Icon(Icons.home_rounded, size: width / 2, color: t.colorScheme.primary),
          ),
          const SizedBox(height: Space.sm),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: ApnivaasTypeMark(color: t.colorScheme.primary, fontSize: 30, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}

class _Foot extends StatelessWidget {
  const _Foot();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const _DocumentLink(label: 'Terms of Use', document: 'terms'),
            ExcludeSemantics(child: Text('·', style: muted)),
            const _DocumentLink(label: 'Privacy Policy', document: 'privacy'),
          ],
        ),
      ],
    );
  }
}

class _DocumentLink extends StatelessWidget {
  const _DocumentLink({required this.label, required this.document});

  final String label;

  /// A [LegalDocument] id.
  final String document;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return TextButton(
      onPressed: () => openLegal(context, initial: document),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        textStyle: t.textTheme.labelMedium,
      ),
      child: Text(label),
    );
  }
}
