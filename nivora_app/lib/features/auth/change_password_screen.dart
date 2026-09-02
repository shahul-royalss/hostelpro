import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
// For [roleHome] — the role → home mapping, which mirrors the web app's lib/roles.ts and must
// exist in exactly one place. router.dart imports this file back; Dart resolves the cycle, and
// the alternative (restating '/owner' and its four siblings here) is how two clients start
// landing the same person in two different places.
import '../../core/router/router.dart';
import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';
// The policy, the validator and the meter, shared with the recovery-link screen so the three
// places this app sets a password cannot drift into three different rules.
import 'password_policy.dart';

/// Set a new password — `screen-create-password`, node 4:89.
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
///   - the password in hand is asked for either way. A FORCED change calls it the TEMPORARY
///     password, because that is the thing the person is holding.
///
/// ═══ 2026-09-01: WHY THE FORCED PATH GREW A THIRD FIELD ═══
/// It used to have two, on the reasoning that the user had just typed the temporary password on
/// the previous screen and asking again reads as a bug. Measured against the live project that
/// day, `PUT /auth/v1/user {"password":"…"}` answers
///     400 current_password_required — "Current password required when setting new password."
/// and the same call WITH `current_password` answers 200. The project has
/// `GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD` on.
///
/// Every account this platform creates is routed here before it can reach anything else, so
/// with two fields NO ACCOUNT COULD EVER FINISH ITS FIRST LOGIN — the form submitted, the
/// server refused, the flag stayed set, and the person went round again. A field somebody has
/// to fill in is a smaller cost than a product nobody can enter, and the alternative — carrying
/// a plaintext password across a route so the form can post it invisibly — is worse than
/// asking.
///
/// What the FORCED/VOLUNTARY split still decides is REAUTHENTICATION, in
/// [AuthController.changePassword]: a voluntary change spends a throttled grant through the
/// mobile-auth endpoint first, a forced one lets GoTrue do the single check. That decision is
/// read from the profile row the server returned, never from anything this form sends.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

/// How long the confirmation stands before the dashboard replaces it.
///
/// The owner asked to be shown that the change worked and then taken to their dashboard, and
/// those two wishes pull against each other: a confirmation nobody can read is not one, and a
/// wait a person notices is an app being slow at them. This is the time it takes to read one
/// short line, and it is spent on a panel that is ALREADY the answer — the tick and the words
/// are on screen for the whole of it. It is not a fake progress bar and there is nothing behind
/// it still working; the password was saved and the session re-resolved before this begins.
const _confirmationHold = Duration(milliseconds: 900);

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  /// The change landed. The form is replaced by [_Confirmation] and the screen is on its way
  /// out — see [_submit] and [_leave].
  bool _done = false;

  /// Where to go afterwards, read from the session BEFORE the write.
  ///
  /// Captured early on purpose. A password change does not change anybody's role, and reading
  /// the destination from a phase that has just been re-resolved makes the exit depend on that
  /// read having succeeded — which is exactly the thing that may have failed. This way the only
  /// question left at the end is "did the password save", and that one has already been answered.
  String? _home;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool forced}) async {
    // A second tap while the first is in flight would spend another reauthentication grant
    // against the same throttle budget. The button is disabled for it, but `onFieldSubmitted`
    // is not a button.
    if (_busy || _done) return;
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final session = ref.read(sessionProvider);
    _home = session == null ? null : roleHome[session.role];

    setState(() {
      _busy = true;
      _error = null;
    });

    String? message;
    try {
      message = await ref.read(authControllerProvider.notifier).changePassword(
            newPassword: _next.text,
            // Sent on BOTH paths — GoTrue refuses a password change without it. [forced] does
            // not decide whether it travels, only whether this app reauthenticates first.
            currentPassword: _current.text,
            forced: forced,
          );
    } catch (e, stack) {
      // ═══ THE TRY THAT WAS NOT THERE, AND WHAT ITS ABSENCE LOOKED LIKE ═══
      //
      // `changePassword` returns a message on every outcome it anticipates, so this catch is
      // for the outcome it does not: a future that completes with an ERROR rather than a value.
      // Without it that error propagated out of `_submit`, the setState below never ran, and
      // `_busy` stayed true FOREVER — submit a dead slab, all three fields locked, the spinner
      // turning, and not one word of explanation. That is the screenshot in the bug report, and
      // it is unrecoverable without killing the app. A button that can stay disabled forever is
      // a defect whatever threw, so this catch names no cause it cannot prove and simply refuses
      // to let the screen die.
      //
      // The sentence deliberately does NOT claim the password was not changed — nobody here
      // knows that, and "could not save your password" would send somebody who HAS a new
      // password back to type the old one. It names the only cause it can prove (no answer
      // arrived) and gives the one action that settles it.
      debugPrint('changePassword threw: ${e.runtimeType} $e\n$stack');
      message = 'Nivora did not get an answer to that, so it cannot say whether your password '
          'changed — try the new one when you sign in.';
    } finally {
      // ALWAYS, on every path out of the await. This is the line that makes "permanently
      // disabled" impossible rather than merely unlikely.
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    if (message != null) {
      // Every failure ends here: button live again, fields unlocked, one sentence naming the
      // cause. Never a silent return to the form.
      setState(() => _error = message);
      return;
    }

    // ═══ SUCCESS HAS TO ARRIVE SOMEWHERE ═══
    // It did not, and not because anything failed. `resolveRedirect` has no arm for a signed-in
    // user sitting on /change-password: with the flag cleared this route is not the splash, not
    // public and not another role's subtree, so the honest answer to "where should the router
    // send them" is null — STAY PUT. The router was never going to move anybody off this screen,
    // whatever the controller re-resolved. So the screen leaves under its own power.
    setState(() => _done = true);
    await Future<void>.delayed(_confirmationHold);
    if (!mounted) return;
    _leave();
  }

  /// Go to the dashboard, and let the router overrule that if it has a better idea.
  ///
  /// [GoRouter.maybeOf] rather than [GoRouter.of]: this screen is also mounted directly in
  /// tests and could be pushed from a settings stack one day, and a missing router must not
  /// throw out of a password change that already succeeded.
  ///
  /// A null destination means the phase is no longer a plain signed-in session — the account
  /// owes a second factor, or the session ended while the form was open. Every one of those
  /// phases is one `resolveRedirect` DOES divert on, so the router is already moving and the
  /// right thing to do here is nothing.
  void _leave() {
    final home = _home ?? _homeFromPhase();
    if (home == null) return;
    GoRouter.maybeOf(context)?.go(home);
  }

  String? _homeFromPhase() {
    final session = ref.read(sessionProvider);
    return session == null ? null : roleHome[session.role];
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
                // The whole card is replaced rather than a banner being added above the form.
                // A confirmation sitting on top of the fields that produced it leaves the
                // person looking at a form they have already submitted and wondering whether
                // to submit it again — and this one is a farewell, not a status line.
                child: _done
                    ? const _Confirmation()
                    : Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // The design's wordmark step (4:69, 24/ExtraBold) — the same mark, at the
                          // same size, as the splash and the sign-in screen this user just came
                          // through.
                          Text(
                            'NIVORA',
                            style: t.textTheme.displayMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Space.md),
                          Text(
                            forced ? 'Set your password' : 'Change your password',
                            // 20/700, the design's heading step.
                            style: t.textTheme.titleLarge,
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

                          // Asked either way, because GoTrue refuses the change without it — see
                          // the header. The LABEL differs, and that is the part that stops it
                          // reading as a bug: on a forced change the person is holding a slip of
                          // paper with a temporary password on it, and "Current password" invites
                          // them to look for one they never chose.
                          TextFormField(
                            controller: _current,
                            enabled: !_busy,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: forced ? 'Temporary password' : 'Current password',
                              helperText: forced
                                  ? 'The one you were given, to confirm it is you.'
                                  : null,
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? (forced
                                    ? 'Enter the temporary password you were given'
                                    : 'Enter your current password')
                                : null,
                          ),
                          const SizedBox(height: Space.sm),

                          TextFormField(
                            controller: _next,
                            enabled: !_busy,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'New password',
                              prefixIcon: const Icon(Icons.lock_reset_rounded),
                              // The helper line that used to sit here — "At least 8 characters,
                              // with a letter and a number" — is gone because the meter below
                              // says the same thing and then keeps saying it as the password is
                              // typed. Two statements of one rule is one too many, and the static
                              // one is the one that never updates.
                              suffixIcon: IconButton(
                                tooltip: _obscure ? 'Show password' : 'Hide password',
                                icon: Icon(_obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: validateNewPassword,
                          ),
                          const SizedBox(height: Space.xs),
                          // Listens to the field's own controller rather than a setState on every
                          // keystroke, so typing a password rebuilds the meter and nothing else —
                          // not the form, not the other two fields.
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _next,
                            builder: (context, value, _) => PasswordStrengthMeter(password: value.text),
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
                            // context.tones.error, not NivoraColors.error: the canonical red is a
                            // GRAPHIC colour and measures 4.05:1 on this card, below AA for type.
                            // See the header of tokens.dart.
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: t.textTheme.bodyMedium
                                    ?.copyWith(color: context.tones.error),
                              ),
                            ),
                          ],

                          const SizedBox(height: Space.xl),
                          FilledButton(
                            onPressed: _busy ? null : () => _submit(forced: forced),
                            child: _busy
                                ? SizedBox(
                                    width: IconSize.md,
                                    height: IconSize.md,
                                    child: CircularProgressIndicator(
                                        strokeWidth: Strokes.glyph,
                                        color: t.colorScheme.onPrimary),
                                  )
                                : const Text('Save password'),
                          ),
                          const SizedBox(height: Space.xxs),
                          // The way out. Without this the screen is a trap for anyone who cannot
                          // complete it right now — the exact failure this file replaced.
                          //
                          // AND IT IS NO LONGER SWITCHED OFF BY `_busy`. It used to be, which meant
                          // the one state where a person most needs a door — a submit that has not
                          // come back — was the one state with no door in it: three locked fields, a
                          // dead button and a spinner. Everything below this await is deadlined, so
                          // the wait is bounded, but "bounded" is not "brief" and a bounded trap is
                          // still a trap. Signing out mid-flight is safe: the controller's next
                          // resolve finds no current user and republishes signed-out, so a request
                          // that lands afterwards cannot pull anybody back in.
                          TextButton(
                            onPressed: () =>
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

}

/// THE CONFIRMATION THE OWNER ASKED FOR, IN THE PLACE THE FORM WAS.
///
/// "it is not showing any confirmation screen and it has to take me from there to my dashboard"
/// — one sentence naming both halves of what was missing. This is the first half; [_leave] is
/// the second.
///
/// It is NOT a new route. A whole screen for a state that lasts under a second would add a
/// destination the router has to know about, a back stack entry pointing at a form that has
/// already been submitted, and a second place for the redirect rules to disagree with
/// themselves. Replacing the card's body says the same thing in the same place the person is
/// already looking, and it cannot be navigated back to.
///
/// A SNACKBAR WAS THE OTHER CANDIDATE AND IT IS THE WRONG SHAPE. It floats over the form,
/// leaves the fields and the button standing behind it, and its whole design is to be ignorable
/// — which is exactly wrong for the one moment this screen has to be unmistakable about.
class _Confirmation extends StatelessWidget {
  const _Confirmation();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;

    return Semantics(
      liveRegion: true,
      // One announcement, in the order it is read. Without this a screen reader meets a tick
      // with no name and a heading that arrived from nowhere.
      label: 'Password changed. Taking you to your dashboard.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The same wordmark at the same size as the form this replaces, so the card reads
            // as the same card answering, rather than as a different screen arriving.
            Text(
              'NIVORA',
              style: t.textTheme.displayMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xl),
            Center(
              child: Container(
                width: Space.huge,
                height: Space.huge,
                decoration: BoxDecoration(
                  // The design's status shape: the tone at 10% behind the tone itself. Same
                  // construction as the state badges on `screen-empty-error-skeleton`.
                  color: tones.success.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: IconSize.xl,
                  color: tones.success,
                ),
              ),
            ),
            const SizedBox(height: Space.md),
            Text(
              'Password changed',
              style: t.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xxs),
            Text(
              'Taking you to your dashboard.',
              style: t.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
