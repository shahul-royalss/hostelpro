library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/env.dart';
import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';
import 'email_verification_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════════════════
// VERIFY YOUR EMAIL — a link, opened somewhere else
// ═══════════════════════════════════════════════════════════════════════════════════════════
//
// ── IT IS A SCREEN YOU CAN LEAVE, AND THAT IS THE DECISION ───────────────────────────────
//
// This is pushed, not routed, and it has a working back button. That is deliberate and it is
// the whole design decision restated in one property: verification is a REQUIREMENT, not a
// TRAP. `resolveRedirect()` in core/router/router.dart does not divert on
// [NivoraSession.needsEmailVerification], the way it does on `needsPasswordChange`, because a
// forced password change can always be completed by the person standing there and a forced
// email verification cannot — the link may be going to a typo'd address, or to a mailbox on a
// phone the resident does not have with them. Trapping them here would mean an unusable app
// with no way back, at a hostel desk, over a mail server nobody present controls.
//
// What holds the requirement instead is the server: `requireVerifiedEmail()` refuses the one
// action where an unproved address becomes credentials in a stranger's inbox — creating
// another account. Everything else keeps working, with the banner asking until it is done.
//
// ── 2026-09-01: THE LINK OPENS NIVORA. IT DOES NOT OPEN A WEB PAGE ANY MORE ──────────────
//
// What the owner reported: tapping the link opened hostelpro-three.vercel.app and showed "Page
// not found — That link doesn't exist, or you don't have access to it". What the owner asked
// for: "it has to ask to login through that link, once they login through that link they have
// to verify".
//
// Those turn out to be the same fix. The redirect is now a custom scheme,
// `app.nivora.mobile://verify-email` ([Env.emailConfirmRedirectUrl]), matched by a VIEW
// intent-filter in AndroidManifest.xml. The app pins AuthFlowType.pkce, so it — and only it —
// holds the verifier for a link it asked for; the link therefore lands in Nivora, Nivora
// exchanges what GoTrue appends, and the person is SIGNED IN BY THE LINK. That sign-in is the
// proof, exactly as asked. A browser holds no verifier and never could complete it, which is
// why deploying the missing web page would not have been the fix.
//
// THE PROOF DOES NOT DEPEND ON ANY OF THAT WORKING. GoTrue matches the single-use token at
// /auth/v1/verify BEFORE it redirects anywhere, and public.email_link_proof() reads that back
// out of GoTrue's own tables. So a laptop that cannot open a custom scheme, or a project whose
// allow-list has not been updated yet, costs the person a tap — not the verification. Every
// state on this screen keeps "I have opened the link" live for exactly that reason, and the
// screen never dead-ends on any of them.
//
// ── THE PART THAT IS STILL HARD ──────────────────────────────────────────────────────────
//
// A 6-digit code was typed HERE. A link is opened THERE — in a mail app, in a browser, maybe on
// a different device entirely. Nothing tells this screen when that happened. So:
//
//   · [didChangeAppLifecycleState] re-checks on resume. Leaving to a mail app and coming back
//     IS the completion signal, and it is free: one call, at the only moment the answer is
//     likely to have changed.
//   · There is NO TIMER. Polling would spend requests on an instance already short of RAM, on
//     the overwhelmingly common case where the user has not opened their mail yet.
//   · There is still an explicit button, because the resume signal misses one real case: the
//     user who opens the link on a LAPTOP and never leaves the app at all. That button reports
//     failures; the resume check does not — see [EmailVerificationRecheck].
//
// The re-check is shared with [VerifyEmailBanner], so a user who never opens this screen — who
// just taps the link in their inbox and returns to Nivora — sees the banner disappear anyway.
//
// ── THE FIELD THAT IS NOT HERE ANY MORE ──────────────────────────────────────────────────
//
// [CodeField] is gone from this screen and stays in the codebase: the 2FA screen still asks for
// six digits and still uses it. What is deleted is the second verification path, not the
// widget — two ways to prove one thing is how one of them rots.
//
// ── THE PANEL THAT IS NOT HERE ANY MORE EITHER ───────────────────────────────────────────
//
// Until 2026-09-01 this screen carried an unfoldable note — "The link opened a page that would
// not load" — with the Site URL and Redirect URL an administrator had to paste into the
// Supabase dashboard. It was shown UNPROMPTED, on a screen a resident opens, and it asserted
// "Nothing is wrong with your link" UNCONDITIONALLY — which is false of an expired or
// already-used link, the one case where a failed landing page really does mean a failed click.
// Both faults are why it went, and neither is restored here.
//
// WHAT IS HERE INSTEAD IS EARNED, AND IT IS EARNED BY EVIDENCE. [_notYetCount] counts
// consecutive checks that came back "the server has no proof". One of those is ordinary: mail
// is slow, or the newest link is still unread. TWO in a row, after the person has said twice
// that they opened it, is the shape of a link that is not coming back to the app — and the
// commonest cause is a dashboard field, measured as missing on this project on 2026-09-01. So
// the second one, and only the second one, names the setting and the exact value
// ([Env.emailRedirectSetupHint]). It appears under the same "not something you can fix from
// here" framing every operator fault on this screen already uses, so nobody reads it as
// homework for the resident.
//
// It claims nothing about the link. It says what an administrator can check, next to a "Send it
// again" and an "I have opened the link" that both still work.
//
// ── NO FIGMA FRAME FOR THIS SCREEN ───────────────────────────────────────────────────────
//
// design-figma/DESIGN-SYSTEM.md lists nineteen `screen-*` frames and none of them is an email
// verification screen. Nothing here is a mockup of something else relabelled; it is built from
// the system those frames define — the raised well (4:77), the cream filled button as the one
// primary action (4:83), the notice banner (4:1535) and the state card. No BackdropFilter, per
// the release-build decision.

/// Proving control of the address on the account.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  static Route<bool> route() =>
      MaterialPageRoute<bool>(builder: (_) => const VerifyEmailScreen());

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen>
    with WidgetsBindingObserver {
  /// Local, not in a shared provider, for the reason the sign-in form gives: the router watches
  /// the auth state, so an in-flight request published there navigates away mid-check.
  bool _sending = false;
  bool _checking = false;
  bool _verified = false;

  /// Set after a check that came back "still not proved". Distinct from [_error], which is a
  /// failure — this one means the question was answered, and the answer was no.
  bool _notYet = false;

  /// How many checks IN A ROW have come back "no proof". Reset by a send, by a failure, and by
  /// success, so it only ever counts an unbroken run of the same answer.
  ///
  /// One is ordinary — mail takes a minute, and people tap before reading. Two is evidence: the
  /// person has now told us twice that they opened the link and the server has still never seen
  /// it. That is when the setup note below is worth showing and not before; see the header.
  int _notYetCount = 0;

  String? _error;

  /// Set when the failure is an administrator's to fix — CAPTCHA, a project with no mail sender,
  /// a function that was never deployed. Presented differently because "try again" is the wrong
  /// advice for it.
  bool _operatorFault = false;

  /// The address the link was sent to. Shown so a typo is visible to the person who can report
  /// it, which is the only way a wrong address ever gets fixed.
  String? _sentTo;

  /// When the resend button becomes live again. Null before the first send. This is the
  /// AUTHORITY on whether a resend is allowed — a wall-clock deadline cannot be shortened by
  /// suspending the app, whereas a tick counter can.
  DateTime? _resendAt;

  /// What the countdown DISPLAYS, decremented one second per tick.
  ///
  /// Deliberately not derived from DateTime.now(). A widget test drives a FAKE clock:
  /// `tester.pump(Duration(seconds: 3))` advances Flutter's notion of time and fires three
  /// timer ticks, but DateTime.now() keeps returning the real wall clock, which has barely
  /// moved. A wall-clock countdown therefore reads 59 where the test pumped three seconds and
  /// expects 57 — the cooldown could then only be tested by making the suite sleep in real
  /// seconds, which is how test suites become slow and flaky. Ticks are also what a countdown
  /// IS. The wall clock re-enters below, on resume, where it belongs.
  Duration _ticked = Duration.zero;
  Timer? _ticker;

  /// The automatic first send has happened (or been started). See [build].
  bool _autoSent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  Duration get _cooldown => _ticked.isNegative ? Duration.zero : _ticked;

  /// Coming back into the app is the completion signal for a link opened somewhere else, so
  /// this is where the screen asks whether it has been.
  ///
  /// It also snaps the countdown: timers are throttled or stopped outright while an app is
  /// backgrounded, so a tick counter alone would resume showing a cooldown that expired minutes
  /// ago. On the way back in, the wall-clock deadline — which kept running — is the truth.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    final until = _resendAt;
    if (until != null) {
      final left = until.difference(DateTime.now());
      setState(() => _ticked = left.isNegative ? Duration.zero : left);
      if (_ticked == Duration.zero) {
        _ticker?.cancel();
        _ticker = null;
      }
    }

    _recheckQuietly();
  }

  /// The resume check. Silent on failure by design — see [EmailVerificationRecheck].
  Future<void> _recheckQuietly() async {
    if (_verified || _checking) return;
    final proved = await ref.read(emailVerificationRecheckProvider).run();
    if (!mounted || !proved) return;
    setState(() {
      _verified = true;
      _error = null;
      _notYet = false;
    });
  }

  bool get _canResend => !_sending && !_checking && _cooldown == Duration.zero;

  /// One 1s timer for the whole countdown, started only while one is running and cancelled the
  /// moment it reaches zero. A `setState` every second forever would keep the screen awake for
  /// no reason.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      _ticked -= const Duration(seconds: 1);
      if (_cooldown == Duration.zero) {
        timer.cancel();
        _ticker = null;
      }
      setState(() {});
    });
  }

  void _armCooldown(Duration d) {
    if (d <= Duration.zero) return;
    _resendAt = DateTime.now().add(d);
    _ticked = d;
    _startTicker();
  }

  Future<void> _send() async {
    if (_sending || _checking) return;
    final address = _sentTo ?? ref.read(sessionProvider)?.email ?? '';
    setState(() {
      _sending = true;
      _error = null;
      _notYet = false;
      _operatorFault = false;
      // A new link is a new question. Whatever the previous ones answered is about a link that
      // is no longer the newest one, and only the newest one works.
      _notYetCount = 0;
    });

    try {
      final outcome = await ref.read(emailVerificationServiceProvider).sendLink(address);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sentTo = outcome.email;
        _armCooldown(outcome.resendAfter);
      });
    } on VerificationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = f.message;
        _operatorFault = f.operatorFault;
        // A throttle carries GoTrue's own wait. Arming from it means the button comes back
        // exactly when the server would start saying yes, rather than when we guessed.
        if (f.retryAfter != null) _armCooldown(f.retryAfter!);
      });
    }
  }

  /// The explicit "I have opened it". Unlike the resume check, this one REPORTS: the user asked
  /// a question, so silence would be the wrong answer.
  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
      _notYet = false;
      _operatorFault = false;
    });

    try {
      final status = await ref.read(emailVerificationServiceProvider).status();
      if (!mounted) return;
      if (status.verified) {
        _notYetCount = 0;
        // The proof is written by the Edge Function with the service role, so nothing in this
        // app would ever notice it otherwise and the banner would sit there after the link was
        // opened. See AuthController.reload().
        await ref.read(authControllerProvider.notifier).reload();
        if (!mounted) return;
        setState(() {
          _checking = false;
          _verified = true;
        });
        return;
      }
      setState(() {
        _checking = false;
        _notYet = true;
        _notYetCount++;
      });
    } on VerificationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = f.message;
        _operatorFault = f.operatorFault;
        // A failure is not an answer, so the run of "no proof" answers is broken rather than
        // extended. Counting it would let two dropped requests conjure a setup note about a
        // setting that may be perfectly correct.
        _notYetCount = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final address = _sentTo ?? session?.email ?? '';

    // THE AUTOMATIC FIRST SEND, and why it is here rather than in initState().
    //
    // The user arrived by deliberately tapping "Verify now", so asking them to tap "Send" for
    // what they just asked for is a step with no decision in it. But the address comes from the
    // session, and the session is an AsyncNotifier: on a cold start it can still be resolving
    // when the first frame is built. A post-frame callback from initState therefore fired with
    // NO ADDRESS and mailed the empty string — caught by a test, not by a person, which is the
    // only reason it is not in a release.
    //
    // So the trigger is the arrival of the address, not the arrival of the frame. `_autoSent`
    // makes it once-only; the work is deferred out of build() because starting a request during
    // a build is how you get a setState-during-build crash.
    if (!_autoSent && (session?.email ?? '').isNotEmpty) {
      _autoSent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send();
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _verified ? _done(t) : _form(t, address),
            ),
          ),
        ),
      ),
    );
  }

  Widget _done(ThemeData t) => GlassCard(
        padding: const EdgeInsets.all(Space.xl),
        child: StateBody(
          icon: Icons.mark_email_read_rounded,
          title: 'Email verified',
          message: 'Thanks — ${_sentTo ?? 'your address'} is confirmed. You can create and '
              'manage accounts as normal.',
          tone: context.tones.success,
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Done'),
          ),
        ),
      );

  Widget _form(ThemeData t, String address) {
    final cooldown = _cooldown;
    final error = _error;

    return GlassCard(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.mark_email_unread_rounded,
              size: IconSize.xl, color: t.colorScheme.primary),
          const SizedBox(height: Space.md),
          Text('Check your email',
              style: t.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: Space.xxs),
          Text(
            address.isEmpty
                ? 'Nivora is sending a confirmation link to the address on your account.'
                : 'Nivora sent a confirmation link to $address',
            style: t.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.sm),
          // THE ONE THING THIS SCREEN CANNOT SEE: the link is opened somewhere else — a mail
          // app, a browser, sometimes another device — and nothing tells this screen when. So
          // the instruction has to include the return trip, which is the step people skip.
          //
          // SINCE THE DEEP LINK IT HAS TWO CASES, AND IT MAY NOT TELL ONLY THE HAPPY ONE. On
          // this phone the link opens Nivora and signs the person in, and that is the whole
          // proof. On a laptop — or any device without Nivora — the browser cannot open a
          // custom scheme and lands on a web page instead, and no browser could ever complete
          // the exchange anyway because it holds no PKCE verifier. That case is named here
          // rather than discovered, and it is named as SURVIVABLE, because it is: the proof was
          // minted by GoTrue before any redirect, so the button below finishes it.
          //
          // What it still refuses to do is predict how the landing page will LOOK. The version
          // that promised the page "may show an error" was written for a project whose Site URL
          // was localhost; predicting a failure that has been fixed teaches the next person to
          // ignore a page that is, on an expired link, telling them the truth.
          Text(
            'Open that email and tap the link. On this phone it opens Nivora and signs you in — '
            'that sign-in is the proof, and there is nothing more to do. Opened on a laptop or '
            'another device it lands on a web page instead: come back to Nivora and tap the '
            'button below, which finishes it just as well.',
            style: t.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),

          if (error != null) ...[
            const SizedBox(height: Space.md),
            Semantics(
              liveRegion: true,
              // context.tones.error, not NivoraColors.error: that one is the canonical GRAPHIC
              // red and measures below AA for small text on this card. tokens.dart says so
              // outright.
              child: Text(
                error,
                style: t.textTheme.bodyMedium?.copyWith(color: context.tones.error),
                textAlign: TextAlign.center,
              ),
            ),
            if (_operatorFault) ...[
              const SizedBox(height: Space.xs),
              Text(
                'This is a setting on the Nivora project, not something you can fix from here. '
                'Nothing you do in the app will work until an administrator changes it.',
                style: t.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ] else if (_notYet) ...[
            const SizedBox(height: Space.md),
            Semantics(
              liveRegion: true,
              child: Text(
                'Not confirmed yet. Open the newest email from Nivora and tap the link — check '
                'your spam folder if it is not in the inbox. Only the newest link works, so if '
                'you tapped an older one, send a new email and use that.',
                style: t.textTheme.bodyMedium?.copyWith(color: context.tones.warning),
                textAlign: TextAlign.center,
              ),
            ),
            // THE SECOND ONE IN A ROW, AND ONLY THE SECOND. See the header: one "no proof" is
            // ordinary — mail is slow, people tap before reading. Two consecutive ones, after
            // the person has twice said they opened it, is the shape of a link that is not
            // getting back to the app, and the commonest cause is a dashboard field that was
            // measured missing on this project (the redirect is substituted for the Site URL,
            // silently, so nothing else in the system can report it).
            //
            // It claims NOTHING about the link — the sentence above still stands, and both
            // escapes below stay live. It names a setting and the exact value, under the same
            // "not something you can fix from here" framing every operator fault on this screen
            // uses, so a resident reads it as somebody else's job rather than their homework.
            if (_notYetCount >= 2) ...[
              const SizedBox(height: Space.sm),
              Text(
                'If this keeps happening it is usually one setting on the Nivora project, not '
                'something you can fix from here. ${Env.emailRedirectSetupHint}',
                style: t.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ] else ...[
            const SizedBox(height: Space.md),
            Text(
              'The email can take a minute to arrive. Only the newest link works.',
              style: t.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: _checking ? null : _check,
            child: _checking
                ? SizedBox(
                    width: IconSize.md,
                    height: IconSize.md,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: t.colorScheme.onPrimary),
                  )
                : const Text('I have opened the link'),
          ),

          TextButton(
            onPressed: _canResend ? _send : null,
            child: _sending
                ? const Text('Sending…')
                : Text(cooldown == Duration.zero
                    ? 'Send it again'
                    : 'Send again in ${cooldown.inSeconds}s'),
          ),

          // The way out. Restates that leaving is allowed, so nobody sits here believing the
          // app is stuck.
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('I will do this later'),
          ),
        ],
      ),
    );
  }
}

/// Open the verification screen from anywhere. Returns true when the address was proved.
Future<bool> openEmailVerification(BuildContext context) async {
  final result = await Navigator.of(context).push(VerifyEmailScreen.route());
  return result ?? false;
}

/// The persistent ask, shown above every role's content until the address is proved.
///
/// It is a BANNER and not a blocking dialog because of the decision at the top of this file:
/// the account works, and this is the one outstanding thing. It draws nothing at all when the
/// session has no reachable address — a resident who signs in with a phone number is never
/// asked for a proof they cannot produce, and that exemption is carved by ADDRESS rather than
/// by role, so a student whose warden collected a real email is asked exactly like an owner.
///
/// IT IS STATEFUL FOR ONE REASON: the resume re-check. A link is opened outside the app, and
/// the user who taps it in their inbox and comes straight back to their home screen never opens
/// the verification screen at all. If only that screen listened, their banner would sit there
/// after the work was done, asking for something they had already given. So the banner listens
/// too — one call, on the transition that actually means something.
///
/// MOUNTED ON ALL FIVE HOME SCREENS — super admin, owner, manager, warden, student. It carries
/// its OWN trailing gap rather than leaving one to each mount site, because the widget
/// collapses to nothing for a verified account and for a phone-login resident: a
/// `SizedBox(height: …)` written next to it at five call sites would be five stray gaps at the
/// top of the screen for everyone who does not owe a proof, which is eventually everyone.
class VerifyEmailBanner extends ConsumerStatefulWidget {
  const VerifyEmailBanner({super.key});

  @override
  ConsumerState<VerifyEmailBanner> createState() => _VerifyEmailBannerState();
}

class _VerifyEmailBannerState extends ConsumerState<VerifyEmailBanner>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Fire-and-forget: the result reaches this widget through the session, which
    // [EmailVerificationRecheck] republishes, so there is nothing to await and nothing to
    // setState. A failure is swallowed there on purpose — see its comment.
    ref.read(emailVerificationRecheckProvider).run();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session == null || !session.needsEmailVerification) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: NoticeBanner(
        eyebrow: 'Verify your email',
        icon: Icons.mark_email_unread_rounded,
        tone: context.tones.warning,
        message: 'Open the link Nivora emails to ${session.email} to create or manage '
            'accounts. Everything else keeps working.',
        action: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => openEmailVerification(context),
            child: const Text('Verify now'),
          ),
        ),
      ),
    );
  }
}
