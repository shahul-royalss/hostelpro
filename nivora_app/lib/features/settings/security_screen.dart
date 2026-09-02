library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';
import '../legal/legal_documents.dart';
import '../legal/legal_screen.dart';
import 'mfa_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════════════════
// SECURITY — WHERE A USER SWITCHES TWO-FACTOR AUTHENTICATION ON
// ═══════════════════════════════════════════════════════════════════════════════════════════
//
// One screen, every role. It is pushed rather than routed, the same way the Super Admin's
// create wizard is (`Navigator.of(context).push(CreateWizardScreen.route())`), so it sits above
// whichever shell the user is in and go_router's redirect still owns every real destination.
//
// ── THERE IS NO FIGMA FRAME FOR THIS SCREEN ──────────────────────────────────────────────
//
// The file's nineteen `screen-*` frames are listed in design-figma/DESIGN-SYSTEM.md and none of
// them is a security or 2FA screen. Nothing here is copied from a mockup of something else and
// relabelled. What it does use is the system those frames define, through the shared widgets:
// the state card and badge (`screen-empty-error-skeleton`, 4:1562 — StateCard / StateBadge /
// StateBody), the raised surface for a well you could put a cursor in (4:77), the cream filled
// button as the one primary action (4:83), and the header with a bottom hairline (4:448).
//
// ── WHAT IS DELIBERATELY NOT HERE ────────────────────────────────────────────────────────
//
//  • No recovery codes. GoTrue issues none for TOTP, so a list of them would be fiction.
//
//  • No BackdropFilter anywhere, per the release-build decision.
//
// ── ONE SCREEN, TWO ARRIVALS ─────────────────────────────────────────────────────────────
//
// [SecurityScreen.required] is the difference between "I came here from the header to look at
// my security settings" and "the router put me here and this is the only screen I have". The
// second is a privileged account with no second factor: since 2026-08-31 Postgres refuses a
// privileged aal1 session that HOLDS a factor and grants grace to one that holds none, and this
// screen is where that grace ends. It is backed by app.mfa_required_roles() in the database and
// mirrored in mfaRequiredRoles — a claim that used to be unavailable to a phone, because it
// lived only in a Vercel environment variable.
//
// ── THE TRAP THAT WAS HERE, AND WHY IT WAS A TRAP IN FOUR SEPARATE WAYS ──────────────────
//
// Reported verbatim: "when i turn on 2FA i haven't any option / navigation to go back from the
// screen". All four causes were live at once, and the first three are why the back chevron in
// the screenshot looks like a control and behaves like a picture:
//
//  1. `widget.required` was declared and READ NOWHERE. Both arrivals drew the same header with
//     the same chevron, so the required arrival advertised an exit it did not have.
//  2. That chevron called `Navigator.maybePop()`. At /mfa-setup this screen is the FIRST route
//     in go_router's navigator, and `ModalRoute.popDisposition` is `isFirst ? bubble : pop`
//     (navigator.dart:389) — so `maybePop` hit the `bubble` arm, returned false and did
//     nothing at all. A chevron wired to a no-op.
//  3. Even a successful pop would have been undone: `resolveRedirect` returns mfaEnrolRoute for
//     [AuthNeedsMfaEnrolment] from every other location (router.dart:121).
//  4. THE ANDROID SYSTEM BACK GESTURE WAS WORSE THAN THE CHEVRON, and this is why the two are
//     not the same fix. `bubble` means "the Navigator declines this" — WidgetsApp then hands
//     the event to the engine, which BACKGROUNDS THE APP. Reopening lands on this screen again,
//     which is how a screen with no exit still manages to look like it closed.
//
// And the reason it did not release after a successful enrolment: `challengeAndVerify` emits
// only `AuthChangeEvent.mfaChallengeVerified` (gotrue 2.27.2, gotrue_mfa_api.dart:128), and
// AuthController's `onAuthStateChange` switch has arms for signedOut / signedIn / userUpdated /
// tokenRefreshed and `default: break` (auth_controller.dart:191). So the session was promoted
// to aal2, the server was satisfied, and the app went on holding [AuthNeedsMfaEnrolment] —
// pinned to this route by rule 3, for ever. That is the exact state the screenshot shows.
//
// ── HOW LEAVING WORKS NOW ────────────────────────────────────────────────────────────────
//
// A [PopScope] answers the gesture instead of letting it bubble, and BOTH the chevron and the
// system back go through the same three-way decision:
//
//   ordinary arrival          → pop, exactly as before. The pushed route has somewhere to go.
//   required, factor present  → `AuthController.reload()`, which re-resolves the phase from the
//                               token this session now holds (aal2) and lets the router take
//                               the user to their role home. This is the missing republish.
//   required, no factor yet   → REFUSED, and it says so — a banner that stands there for the
//                               whole visit, and a sentence in answer to the gesture itself.
//                               A refusal nobody is told about is indistinguishable from a bug,
//                               which is the whole complaint above.
//
// The refused case still has a way out, because "no way to leave" is never an acceptable state
// for a screen: Sign out is in the header. Enrol, or leave as somebody else. What is refused is
// walking INTO the app owing the factor the server is granting grace for.

/// Two-factor authentication: its current state, and the way to change it.
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key, this.required = false});

  /// Arrived here because the account MUST enrol, not because someone tapped a header icon.
  ///
  /// Defaults to false so the pushed route below — every existing caller — is untouched.
  final bool required;

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const SecurityScreen());

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  /// The two code fields are separate controllers on purpose: turning 2FA on and turning it off
  /// are different decisions, and a digit left behind in one must never arm the other.
  final _enrolCode = TextEditingController();
  final _disableCode = TextEditingController();

  /// Non-null exactly while a setup is in progress. Clearing it is what removes the secret from
  /// the screen — there is no other copy, so "shown once" is a consequence of this field's
  /// lifetime rather than a rule someone has to remember.
  TotpEnrollment? _enrollment;

  /// The explicit "I have saved this" confirmation. Confirm stays disabled until it is ticked,
  /// the same obstacle StaffCredentialsDialog puts in front of a one-time password.
  bool _savedKey = false;

  /// The turn-off panel is open.
  bool _turningOff = false;

  /// This screen has seen a verified factor on the account.
  ///
  /// Set from the confirm that just succeeded, cleared by a disable that just succeeded, and
  /// OR-ed with the server's own answer below. It exists for one frame-accurate reason: the
  /// only thing standing between a required arrival and the rest of the app is this fact, and
  /// `mfaStateProvider` is briefly loading-with-the-previous-value after the invalidate that
  /// follows a confirm. Reading only the provider would blink the way out off the screen at the
  /// exact moment it was earned.
  bool _confirmed = false;

  bool _busy = false;
  String? _error;
  String? _note;

  /// A failed attempt to LEAVE, which is a different failure from a failed enrolment step.
  ///
  /// Kept apart from [_error] so the two never show the same sentence twice on one screen, and
  /// so this one can be drawn where it belongs: beside the Continue button, which is the only
  /// control that can produce it.
  String? _leaveError;

  @override
  void dispose() {
    _enrolCode.dispose();
    _disableCode.dispose();
    super.dispose();
  }

  static final _added = DateFormat('d MMM yyyy');

  Future<void> _begin() async {
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    final session = ref.read(sessionProvider);
    try {
      final started = await ref.read(mfaServiceProvider).begin(
            // The web action's exact friendly name, so one account enrolled from either client
            // shows the same label in the authenticator app and in the Supabase dashboard.
            friendlyName: session == null ? null : 'NIVORA (${session.role.wire})',
          );
      if (!mounted) return;
      _enrolCode.clear();
      setState(() {
        _enrollment = started;
        _savedKey = false;
        _busy = false;
      });
    } on MfaFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.message;
      });
    }
  }

  Future<void> _confirm() async {
    final enrollment = _enrollment;
    // Read from the controller at the moment of the tap, never from a mirrored piece of state.
    // features/auth/mfa_screen.dart documents what the other way costs: the web build submitted
    // a value that had not flushed yet, so a correct code came back rejected.
    final code = _enrolCode.text.trim();
    if (enrollment == null || code.length != _codeLength) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mfaServiceProvider).confirm(factorId: enrollment.factorId, code: code);
      if (!mounted) return;
      _enrolCode.clear();
      setState(() {
        // The secret leaves the screen here and cannot be recalled: starting again asks the
        // server for a NEW factor with a NEW secret.
        _enrollment = null;
        _savedKey = false;
        _busy = false;
        // What a required arrival came here to do. Nothing else on this screen changes it, and
        // the way out appears in the same frame as the sentence saying it worked.
        _confirmed = true;
        _note = 'Two-factor authentication is on. You have been signed out on your other '
            'devices — sign in again there and Nivora will ask for a code.';
      });
      ref.invalidate(mfaStateProvider);
    } on MfaFailure catch (f) {
      if (!mounted) return;
      _enrolCode.clear();
      setState(() {
        _busy = false;
        _error = f.message;
      });
    }
  }

  Future<void> _disable(String factorId) async {
    final code = _disableCode.text.trim();
    if (code.length != _codeLength) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mfaServiceProvider).disable(factorId: factorId, code: code);
      if (!mounted) return;
      _disableCode.clear();
      setState(() {
        _turningOff = false;
        _busy = false;
        // Symmetrical with _confirm, and it matters on a required arrival: switching the factor
        // back off puts this screen back into the state that refuses to be left, and the banner
        // saying why returns with it. A sticky flag here would offer a Continue that the router
        // would bounce straight back.
        _confirmed = false;
        _note = 'Two-factor authentication is off. Sign-in now needs your password alone.';
      });
      ref.invalidate(mfaStateProvider);
    } on MfaFailure catch (f) {
      if (!mounted) return;
      _disableCode.clear();
      setState(() {
        _busy = false;
        _error = f.message;
      });
    }
  }

  void _cancelEnrolment() {
    _enrolCode.clear();
    setState(() {
      _enrollment = null;
      _savedKey = false;
      _error = null;
    });
  }

  /// Leave a REQUIRED arrival, now that the factor exists.
  ///
  /// There is nothing to pop — this is the first route in go_router's navigator — so leaving
  /// means changing the answer the redirect keeps giving. [AuthController.reload] re-resolves
  /// the phase from the token this session is already holding, which `challengeAndVerify`
  /// swapped for one carrying aal2, so `mfaGate` returns satisfied and the router draws the
  /// role home. Nothing else in the app does this: the event that promoted the session is one
  /// the auth stream's switch does not listen for. See the note at the top of this file.
  Future<void> _leaveRequired() async {
    setState(() {
      _busy = true;
      _leaveError = null;
    });
    await ref.read(authControllerProvider.notifier).reload();
    if (!mounted) return;

    // reload() SWALLOWS its failures on purpose — it is a background correction everywhere else
    // in the app. Here it is the button, so the outcome has to be looked at rather than assumed:
    // a phase that did not move means the router is still drawing this screen, and a Continue
    // that spins and returns you to where you were is the permanently-spinning button this
    // codebase treats as a bug. If it moved, the router has already replaced this widget.
    final phase = ref.read(authControllerProvider).value;
    setState(() {
      _busy = false;
      if (phase is AuthNeedsMfaEnrolment) {
        _leaveError =
            'Two-factor authentication is on, but Nivora could not confirm that with the '
            'server. Check your connection and tap Continue again.';
      }
    });
  }

  /// The gesture that cannot be granted, answered out loud.
  ///
  /// The banner above already says why, for the whole visit. This is for the person who did not
  /// read it and pressed back: swallowing the gesture in silence is what makes a deliberate
  /// refusal look like a broken button, and that misreading is the entire bug report this
  /// screen was fixed for.
  void _refuseToLeave() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Set up two-factor authentication to go on, or sign out to leave this screen.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _signOut() => ref.read(authControllerProvider.notifier).signOut();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final state = ref.watch(mfaStateProvider);
    // WATCHED, not read on demand. `_begin` needs the role to name the factor the way the web
    // action names it, and a `ref.read` in a callback returns null unless something has already
    // subscribed — on a device the router has, in a test nothing has. Subscribing here means
    // this screen does not depend on who else happened to look first.
    final session = ref.watch(sessionProvider);

    // THE ONE FACT THE WHOLE EXIT TURNS ON. The server's own answer, OR the confirm that just
    // succeeded — see [_confirmed] for why both.
    final satisfied = _confirmed || (state.value?.enrolled ?? false);

    // The only state in this app where leaving is legitimately refused: the router put this
    // account here because it owes a second factor, and it still owes one.
    final held = widget.required && !satisfied;

    return PopScope(
      // FALSE FOR EVERY REQUIRED ARRIVAL, including the one that may now leave. `false` does not
      // mean "trapped": it means this screen answers the gesture instead of letting the
      // Navigator decline it. Declining is what sent the gesture to the engine and backgrounded
      // the app — there is no route beneath this one to pop to, so leaving is never a pop here.
      // The ordinary pushed arrival keeps `true` and pops exactly as it always did.
      canPop: !widget.required,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        if (satisfied) {
          _leaveRequired();
        } else {
          _refuseToLeave();
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            GlassHeader(
              child: Row(
                children: [
                  // Drawn only where it does something. A chevron on the required arrival is a
                  // picture of a control — it was the whole of the bug report — because this
                  // route is `isFirst` and `maybePop` bubbles rather than pops.
                  if (!widget.required) ...[
                    IconButton(
                      tooltip: 'Back',
                      onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: Space.xxs),
                  ],
                  Expanded(child: Text('Security', style: t.textTheme.titleLarge)),
                  // The way out for the arrival that is being refused the other one. Someone
                  // who cannot enrol right now — no authenticator app, a borrowed handset —
                  // must still be able to put the phone down as somebody else.
                  //
                  // There is deliberately no twin of this for the satisfied case: that arrival's
                  // exit is the banner's own CTA, which sits outside the scroll view and is on
                  // screen at all times. Two controls that do one thing is how a person ends up
                  // wondering whether they do the same thing.
                  if (held)
                    TextButton(
                      onPressed: _busy ? null : _signOut,
                      child: const Text('Sign out'),
                    ),
                ],
              ),
            ),
            // Hoisted OUT of the scroll view and run full width, the shape
            // `screen-subscription-expired` (4:1520) gives a banner: a strip the page hangs
            // from rather than another card in the stack. warden_home_screen.dart does the same
            // with its subscription notice, and for the same reason — this one is about the
            // whole screen, not about one card on it.
            //
            // On a required arrival it is also the ANSWER TO "why can I not go back", standing
            // there for the whole visit rather than only in reply to a gesture.
            if (held)
              NoticeBanner(
                eyebrow: 'Required',
                icon: Icons.lock_outline_rounded,
                tone: NivoraColors.warning,
                message: session == null
                    ? 'Nivora requires two-factor authentication on this account, so this is '
                        'the only screen it can open. Set it up below, or sign out.'
                    : 'Nivora requires two-factor authentication on ${session.role.label} '
                        'accounts, so this is the only screen it can open. Set it up below, '
                        'or sign out.',
              )
            else if (widget.required)
              NoticeBanner(
                eyebrow: 'Done',
                message: _note ?? 'Two-factor authentication is on for this account.',
                tone: NivoraColors.success,
                icon: Icons.check_circle_outline_rounded,
                // The full-width CTA the banner was built with (4:1535), used here for the one
                // thing this arrival now needs: the router will not move on its own, because
                // nothing republished the phase when the factor was verified.
                action: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : _leaveRequired,
                      child: _busy ? const _ButtonSpinner() : const Text('Continue to Nivora'),
                    ),
                    // Beside the button that produced it. A Continue that spins and returns you
                    // to the screen you were on, saying nothing, is the shape of bug this whole
                    // change exists to remove — it must not come back as its own failure mode.
                    if (_leaveError != null) ...[
                      const SizedBox(height: Space.xs),
                      _ErrorLine(message: _leaveError!),
                    ],
                  ],
                ),
              )
            else if (_note != null)
              NoticeBanner(
                eyebrow: 'Saved',
                message: _note!,
                tone: NivoraColors.success,
                icon: Icons.check_circle_outline_rounded,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxxl),
                children: [
                  // Whose account this is. Staff phones get handed around, and 2FA is the one
                  // setting where changing it on the wrong account is discovered much later.
                  // Both values come from the `public.users` row the session was built from.
                  if (session != null) ...[
                    Text('${session.fullName} · ${session.role.label}',
                        style: t.textTheme.bodySmall),
                    const SizedBox(height: Space.md),
                  ],
                  // FOUR STATES, KEPT APART. Checking, on/off, a failure worth retrying, and a
                  // refusal that retrying cannot help. The mockups only ever draw the last of
                  // those as a happy path, so this switch is the app's own contract.
                  if (_enrollment != null)
                    _EnrolPanel(
                      enrollment: _enrollment!,
                      controller: _enrolCode,
                      savedKey: _savedKey,
                      busy: _busy,
                      error: _error,
                      onSavedKeyChanged: (v) => setState(() => _savedKey = v),
                      onChanged: () => setState(() {}),
                      onConfirm: _confirm,
                      onCancel: _cancelEnrolment,
                    )
                  else
                    state.when(
                      loading: () => const StateCard(
                        badge: 'Checking',
                        child: StateBody(
                          icon: Icons.shield_outlined,
                          title: 'Checking your security settings',
                          message: 'Asking Nivora whether an authenticator app is already set up.',
                        ),
                      ),
                      error: (e, _) => _Failed(
                        failure: e is MfaFailure
                            ? e
                            // Anything that reached here without being mapped is still a real
                            // failure; it just has no sentence of its own yet.
                            : const MfaFailure(
                                'Nivora could not read your security settings. Try again.',
                              ),
                        onRetry: () => ref.invalidate(mfaStateProvider),
                      ),
                      data: (mfa) => mfa.enrolled
                          ? _OnCard(
                              state: mfa,
                              added: _added,
                              controller: _disableCode,
                              turningOff: _turningOff,
                              busy: _busy,
                              error: _error,
                              onOpenTurnOff: () => setState(() {
                                _turningOff = true;
                                _error = null;
                                _note = null;
                              }),
                              onCancelTurnOff: () {
                                _disableCode.clear();
                                setState(() {
                                  _turningOff = false;
                                  _error = null;
                                });
                              },
                              onChanged: () => setState(() {}),
                              onDisable: () => _disable(mfa.factorId!),
                            )
                          : _OffCard(busy: _busy, error: _error, onStart: _begin),
                    ),
                  const SizedBox(height: Space.lg),
                  const _Footnote(),
                  const SizedBox(height: Space.lg),
                  // THE DOCUMENTS, READABLE AT ANY TIME — not only at the gate that asked.
                  //
                  // This screen is where it lives because it is the one account screen ALL FIVE
                  // roles can already reach: every role's header carries the shield (see the
                  // note in features/super_admin/sa_overview_screen.dart), whereas "More" and
                  // "Profile" exist for two roles between them. A policy a person can read only
                  // in the second before agreeing to it is a policy nobody has read, and Play's
                  // own guidance assumes the documents stay reachable after install.
                  const _LegalLink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Six, everywhere. TOTP is six digits and every field here agrees about that.
const _codeLength = 6;

/// 2FA is off: what it is, and the one button that changes it.
class _OffCard extends StatelessWidget {
  const _OffCard({required this.busy, required this.error, required this.onStart});

  final bool busy;
  final String? error;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return StateCard(
      badge: 'Off',
      tone: NivoraColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Two-factor authentication', style: t.textTheme.titleMedium),
          const SizedBox(height: Space.xxs),
          Text(
            'Right now your password is the only thing between someone and this account. '
            'Add an authenticator app and Nivora will also ask for a 6-digit code each time '
            'you sign in.',
            style: t.textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.md),
          FilledButton.icon(
            onPressed: busy ? null : onStart,
            icon: busy
                ? const _ButtonSpinner()
                : const Icon(Icons.smartphone_rounded, size: IconSize.md),
            label: const Text('Set up two-factor authentication'),
          ),
          if (error != null) ...[
            const SizedBox(height: Space.sm),
            _ErrorLine(message: error!),
          ],
        ],
      ),
    );
  }
}

/// 2FA is on: since when, and the guarded way back off it.
class _OnCard extends StatelessWidget {
  const _OnCard({
    required this.state,
    required this.added,
    required this.controller,
    required this.turningOff,
    required this.busy,
    required this.error,
    required this.onOpenTurnOff,
    required this.onCancelTurnOff,
    required this.onChanged,
    required this.onDisable,
  });

  final MfaState state;
  final DateFormat added;
  final TextEditingController controller;
  final bool turningOff;
  final bool busy;
  final String? error;
  final VoidCallback onOpenTurnOff;
  final VoidCallback onCancelTurnOff;
  final VoidCallback onChanged;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return StateCard(
      badge: 'On',
      tone: NivoraColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Two-factor authentication', style: t.textTheme.titleMedium),
          const SizedBox(height: Space.xxs),
          Text(
            'Signing in asks for a 6-digit code from your authenticator app.',
            style: t.textTheme.bodyMedium,
          ),
          if (state.addedOn != null) ...[
            const SizedBox(height: Space.xs),
            // A real column from `auth.mfa_factors`, not a decorative date.
            Text('Added ${added.format(state.addedOn!.toLocal())}',
                style: t.textTheme.bodySmall),
          ],
          const SizedBox(height: Space.md),
          if (!turningOff)
            OutlinedButton.icon(
              onPressed: busy ? null : onOpenTurnOff,
              icon: const Icon(Icons.shield_outlined, size: IconSize.md),
              label: const Text('Turn off two-factor authentication'),
            )
          else ...[
            Text(
              'Enter the code your authenticator app is showing now. Nivora checks it before '
              'removing the app, so a phone someone else is holding cannot switch this off.',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.sm),
            _CodeField(
              controller: controller,
              label: 'Current code',
              enabled: !busy,
              onChanged: onChanged,
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onCancelTurnOff,
                    child: const Text('Keep it on'),
                  ),
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: FilledButton(
                    onPressed: (busy || controller.text.trim().length != _codeLength)
                        ? null
                        : onDisable,
                    child: busy ? const _ButtonSpinner() : const Text('Turn off'),
                  ),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: Space.sm),
            _ErrorLine(message: error!),
          ],
        ],
      ),
    );
  }
}

/// Scan, or type the key, then prove it worked.
///
/// The key is on screen at the same time as the QR, never behind a "can't scan?" link. A camera
/// that will not focus, a cracked lens, a resident on a borrowed handset — none of those should
/// end in a dead end, and the manual path is the same two taps as the automatic one.
class _EnrolPanel extends StatelessWidget {
  const _EnrolPanel({
    required this.enrollment,
    required this.controller,
    required this.savedKey,
    required this.busy,
    required this.error,
    required this.onSavedKeyChanged,
    required this.onChanged,
    required this.onConfirm,
    required this.onCancel,
  });

  final TotpEnrollment enrollment;
  final TextEditingController controller;
  final bool savedKey;
  final bool busy;
  final String? error;
  final ValueChanged<bool> onSavedKeyChanged;
  final VoidCallback onChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ready = savedKey && controller.text.trim().length == _codeLength && !busy;

    return StateCard(
      badge: 'Setting up',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('1. Add Nivora to your authenticator app', style: t.textTheme.titleMedium),
          const SizedBox(height: Space.xxs),
          Text(
            'Google Authenticator, Authy, 1Password — any app that makes 6-digit codes.',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.sm),
          if (enrollment.qrSvg != null) ...[
            Center(child: _QrPlate(svg: enrollment.qrSvg!)),
            const SizedBox(height: Space.sm),
            Text('Scan the square, or type the key below by hand.',
                style: t.textTheme.bodySmall, textAlign: TextAlign.center),
          ] else
            Text(
              'This device could not draw the QR square. Type the key below into your '
              'authenticator app instead — it sets up exactly the same thing.',
              style: t.textTheme.bodySmall,
            ),
          const SizedBox(height: Space.sm),
          _SecretRow(secret: enrollment.secret),
          const SizedBox(height: Space.sm),
          const _SavedKeyWarning(),
          const SizedBox(height: Space.xs),
          Material(
            // A ListTile paints its fill and its ink onto the nearest Material, and the nearest
            // thing above this is a decorated box. Flutter asserts on that arrangement — the
            // same trap StaffCredentialsDialog documents.
            type: MaterialType.transparency,
            child: CheckboxListTile(
              value: savedKey,
              onChanged: busy ? null : (v) => onSavedKeyChanged(v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('I have saved this key', style: t.textTheme.bodyMedium),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text('2. Enter the code it shows', style: t.textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          _CodeField(
            controller: controller,
            label: 'Code from your app',
            enabled: !busy,
            onChanged: onChanged,
          ),
          if (error != null) ...[
            const SizedBox(height: Space.sm),
            _ErrorLine(message: error!),
          ],
          const SizedBox(height: Space.md),
          FilledButton(
            // Both gates, not either: a code alone would let someone finish setup without ever
            // having stored the key, and the key alone proves nothing works.
            onPressed: ready ? onConfirm : null,
            child: busy ? const _ButtonSpinner() : const Text('Turn on two-factor'),
          ),
          const SizedBox(height: Space.xxs),
          TextButton(
            onPressed: busy ? null : onCancel,
            child: const Text('Cancel setup'),
          ),
        ],
      ),
    );
  }
}

/// The QR, on a light plate.
///
/// The plate is [NivoraColors.primaryContainer] — the design's cream — and NOT the themed
/// surface, in either theme. A QR is a scanning target before it is a piece of interface: the
/// modules GoTrue draws are dark, and on this app's #0b0d0f ground they would be invisible to
/// the eye and to a camera alike. The web app makes the same call with `bg-white p-3`.
class _QrPlate extends StatelessWidget {
  const _QrPlate({required this.svg});

  final String svg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: const BoxDecoration(
        color: NivoraColors.primaryContainer,
        borderRadius: Radii.rControl,
      ),
      child: SizedBox.square(
        dimension: Space.huge * 4,
        child: SvgPicture.string(
          svg,
          fit: BoxFit.contain,
          semanticsLabel: 'QR code for setting up two-factor authentication',
        ),
      ),
    );
  }
}

/// The shared secret, selectable and copyable.
///
/// SelectableText rather than Text for the reason the staff credentials dialog gives: someone
/// reading a base32 key onto a phone call needs to be able to put a finger under it, and a key
/// with an I and a 1 in it is exactly the string that gets read out wrong.
class _SecretRow extends StatelessWidget {
  const _SecretRow({required this.secret});

  final String secret;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FlatSurface(
      weight: GlassWeight.regular,
      borderRadius: Radii.rControl,
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.xs, Space.xxs, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SETUP KEY', style: t.textTheme.labelSmall),
                const SizedBox(height: Space.xxs / 2),
                SelectableText(
                  secret,
                  style: t.textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 0.6,
                    color: t.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          _CopyButton(text: secret),
        ],
      ),
    );
  }
}

/// Why the key matters, in the tinted caution this app already uses for one-time values.
class _SavedKeyWarning extends StatelessWidget {
  const _SavedKeyWarning();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = context.tones.warning;
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: context.tones.chipFill(tone),
        borderRadius: Radii.rControl,
        border: Border.all(color: context.tones.chipBorder(tone), width: Strokes.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: IconSize.sm, color: tone),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              'This key is shown once. Nivora cannot show it again — starting setup over issues '
              'a different one. If you lose both the key and the phone, ask your administrator, '
              'because nobody can read it back to you.',
              style: t.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// A failure with the retry the failure actually deserves.
///
/// A retry button under something retrying cannot fix — an expired session, a rate limit that
/// has not run out — teaches people to tap it forever. [MfaFailure.retryable] is what decides.
class _Failed extends StatelessWidget {
  const _Failed({required this.failure, required this.onRetry});

  final MfaFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return StateCard(
      badge: failure.retryable ? 'Problem' : 'Refused',
      tone: NivoraColors.error,
      child: StateBody(
        title: 'Could not read your security settings',
        message: failure.message,
        action: failure.retryable
            ? FilledButton(onPressed: onRetry, child: const Text('Try again'))
            : null,
      ),
    );
  }
}

/// One 6-digit field.
///
/// Not the six separate boxes features/auth/mfa_screen.dart draws: there that treatment IS the
/// screen, here the code is one field in a form with a checkbox and two buttons around it, and
/// six boxes in that row would read as the main event rather than as the last step.
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      maxLength: _codeLength,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: t.textTheme.titleMedium?.copyWith(letterSpacing: 4),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        hintText: '000000',
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

/// Copy, with a confirmation that lasts long enough to be read.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  /// THE FAILURE IS SAID OUT LOUD. `Clipboard.setData` goes over a MethodChannel and can
  /// throw — a platform that refuses the clipboard, a channel that is not up yet. Unhandled,
  /// the tick never appeared and nothing else did either: the one-time password this button
  /// exists for was "copied" as far as the person could tell, and was gone by the time they
  /// found out otherwise.
  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('This device would not take the setup key — it is still on screen '
              'above, so it can be typed into your authenticator app by hand.'),
          behavior: SnackBarBehavior.floating,
          duration: Motion.readMessage,
        ));
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(Motion.confirmed);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: _copy,
        tooltip: _copied ? 'Copied' : 'Copy setup key',
        icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: IconSize.md),
      );
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: t.textTheme.bodySmall?.copyWith(color: context.tones.error),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: IconSize.md,
        height: IconSize.md,
        // onPrimaryContainer, not onPrimary: theme.dart flips the filled button to the design's
        // CREAM fill (`primaryContainer`, 4:83), so the ink on top of it is that pair's.
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      );
}

/// The one thing this screen must not overstate.
class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Text(
      'Codes are made by your authenticator app, not sent by SMS, so they keep working with no '
      'signal. Nivora holds no copy of your key and cannot recover it for you.',
      style: t.textTheme.bodySmall,
    );
  }
}

/// The way back to the Terms of Use and the Privacy Policy, from inside the app.
///
/// Drawn as a row that says what it opens rather than as a bare link, because the two documents
/// are the answer to a question people arrive with ("what happens to the photo of my ID?") and
/// the row is where they will look for it.
class _LegalLink extends StatelessWidget {
  const _LegalLink();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FlatSurface(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => openLegal(context),
        borderRadius: Radii.rCard,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              Icon(Icons.policy_outlined,
                  size: IconSize.md, color: t.colorScheme.onSurfaceVariant),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Terms & Privacy', style: t.textTheme.titleSmall),
                    const SizedBox(height: Space.xxs),
                    Text(
                      'What Nivora keeps about you, who can see it, and how long it is held. '
                      'Version $kLegalVersion.',
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: IconSize.md, color: t.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one line a role's header adds to reach this screen.
///
/// Each role builds the button from its own kit — `HeaderAction` for the warden, `SaIconButton`
/// for the Super Admin, a plain [IconButton] elsewhere — and calls this. Exporting the push
/// rather than a widget is what keeps five header kits from having to agree on one.
void openSecurity(BuildContext context) {
  Navigator.of(context).push(SecurityScreen.route());
}
