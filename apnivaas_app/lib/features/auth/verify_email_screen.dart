library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart';
import '../../core/config/env.dart';
import '../../core/theme/tokens.dart';
import '../../shared/clay/banners.dart';
import '../../shared/clay/clay_icons.dart';
import '../../shared/clay/pill_button.dart';
import '../../shared/glass/glass.dart' show FlatSurface;
import '../common/form_parts.dart';
// For [kGrievanceEmail]: the support mailbox the legal documents name, in exactly one place.
import '../legal/legal_documents.dart';
import 'auth_scaffold.dart';
import 'email_verification_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════════════════
// VERIFY YOUR EMAIL — a link, opened somewhere else
// ═══════════════════════════════════════════════════════════════════════════════════════════
//
// ── 1.2.0: FOR STAFF IT IS THE ROUTER'S GATE; FOR RESIDENTS IT IS STILL A DETOUR ────────
//
// Until 1.2.0 this screen was only ever PUSHED — from the home-screen banner, and once at the
// end of a forced password change — on the reasoning that verification was a requirement and
// not a trap. The push after the password change was the flaw: anything that rebuilt the
// screen stack threw it away — signing out and back in, killing the app, or on Android the
// emailed link itself arriving as a navigation to '/' — and the account landed on its
// dashboard with only a banner. Staff accounts were reaching the product unverified.
//
// So, by the product owner's decision for 1.2.0, it has two modes:
//
//   · THE GATE ([blocking] true). /verify-email in core/router/router.dart builds it, and
//     `resolveRedirect()` sends every signed-in route there while
//     [ApnivaasSession.mustVerifyEmail] holds: an owner, manager, warden or super admin whose
//     address can receive mail and has never been proved — existing accounts included, on their
//     next sign-in. A rule the router re-evaluates on every navigation cannot be thrown away.
//     There is no back and no "later"; the one exit is Sign out, and the screen says who can
//     fix a wrong address, because a typo is the one thing the person holding the phone cannot
//     fix from here. A verified re-read of the profile row is what releases it: [reload()]
//     republishes the session and the router sends the account home.
//   · THE DETOUR ([blocking] false), pushed from [VerifyEmailBanner] for a resident with a real
//     address. Proving it changes nothing on the server for them, so it stays a requirement and
//     not a trap: a back button and "I will do this later".
//
// What holds the requirement on the server is unchanged: `requireVerifiedEmail()` refuses the
// one action where an unproved address becomes credentials in a stranger's inbox — creating
// another account. The router gate is UX, not a security boundary.
//
// ── 1.2.0: ASK FIRST, AND DO NOT MAIL ON EVERY MOUNT ─────────────────────────────────────
//
// As the gate this screen mounts on every cold start and every sign-in until the proof lands,
// and it used to send a link the moment it opened. Each send kills the previous link, so the
// person who tapped their link — which cold-starts the app and mounts this gate — would have
// been mailed a fresh one while the proof was being read, killing the link in their hand. So on
// mount it now:
//
//   1. asks the server, quietly, whether the address is ALREADY proved
//      ([EmailVerificationRecheck]); if it is, the re-read republishes the session and the
//      router releases the account without a single mail being sent;
//   2. sends automatically only if this phone has not sent a link to this address within
//      [autoSendWindow] (ten minutes), remembered by [VerificationSendLog]. Inside the window
//      it says when the waiting link was sent and arms "Send it again" for whatever is left of
//      the server's 60 s limit.
//
// The app reads nothing it did not write to make that decision — never the clipboard, never
// the mail. On Android the emailed link no longer reaches go_router at all
// (flutter_deeplinking_enabled is false in AndroidManifest.xml, as it already was on iOS);
// supabase_flutter still receives the code and exchanges it.
//
// ── 2026-09-01: THE LINK OPENS THE APP. IT DOES NOT OPEN A WEB PAGE ANY MORE ────────────
//
// What the owner reported: tapping the link opened hostelpro-three.vercel.app and showed "Page
// not found — That link doesn't exist, or you don't have access to it". What the owner asked
// for: "it has to ask to login through that link, once they login through that link they have
// to verify".
//
// Those turn out to be the same fix. The redirect is now a custom scheme,
// `com.nivorasr.app://verify-email` ([Env.emailConfirmRedirectUrl]), matched by a VIEW
// intent-filter in AndroidManifest.xml. The app pins AuthFlowType.pkce, so it — and only it —
// holds the verifier for a link it asked for; the link therefore lands in the app, the app
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
// just taps the link in their inbox and returns to the app — sees the banner disappear anyway.
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
// ── NO BOARD FOR THIS SCREEN ─────────────────────────────────────────────────────────────
//
// The design canvas draws no email verification screen. Nothing here is a mockup of something
// else relabelled; it is the sign-in family's page ([AuthScaffold]) — the brand bar, a heading
// with its clay icon, the card that says what happened, and the forest filled button as the one
// primary action. The banner residents see on their home is the clay kit's Mist [InfoBanner].
// No BackdropFilter, per the release-build decision.

/// Proving control of the address on the account.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.blocking = false});

  /// Whether this is the router's GATE (the /verify-email route, for staff), or the optional
  /// detour the home-screen banner pushes for a resident.
  ///
  /// An explicit flag rather than `Navigator.canPop()`, and that was a real bug rather than a
  /// style preference: when this screen was pushed from the change-password screen there WAS
  /// something to pop back to, so inferring from the stack offered "I will do this later" on
  /// the one path where later was not on offer. The route passes true; the banner passes
  /// nothing.
  final bool blocking;

  static Route<bool> route({bool blocking = false}) => MaterialPageRoute<bool>(
        builder: (_) => VerifyEmailScreen(blocking: blocking),
      );

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

  /// The opening sequence has been started. See [build] and [_open].
  bool _opened = false;

  /// The opening sequence is RUNNING: the quiet re-check, then the decision whether to send.
  /// "Send it again" is held off while it runs, so a tap cannot race the automatic send into
  /// two mails — the second of which would kill the first.
  bool _opening = false;

  /// When the link this screen is waiting on was sent, if it was sent BEFORE this screen opened
  /// — an earlier launch, an earlier sign-in. Null when this screen sent it, or sent nothing.
  /// Shown, because "sent a link" with no time on it reads as "just now" and sends people
  /// looking for a mail that arrived ten minutes ago.
  DateTime? _sentEarlierAt;

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

  bool get _canResend => !_opening && !_sending && !_checking && _cooldown == Duration.zero;

  /// What happens when the screen first has an address: ASK, then decide whether to MAIL.
  ///
  /// 1. The quiet re-check. If the address is already proved — the link was opened on a laptop,
  ///    or the tap that cold-started this app already did it — the re-check's reload()
  ///    republishes the verified session, the router releases the account, and no mail is sent.
  ///    Silent on failure, like every quiet check: a dropped request here is not news, and the
  ///    decision below still runs.
  /// 2. A link sent from this phone within [autoSendWindow] is left alone. Sending another would
  ///    kill it — only the newest link works — and spend the project's mail allowance on a link
  ///    the person very probably already has. The screen says when it went, and "Send it again"
  ///    is armed for whatever is left of the server's 60 s rule.
  /// 3. Otherwise, send. The person did not come here to press "Send" for the one thing this
  ///    screen exists to do.
  Future<void> _open(String address) async {
    setState(() => _opening = true);

    final proved = await ref.read(emailVerificationRecheckProvider).run();
    if (!mounted) return;
    if (proved) {
      setState(() {
        _opening = false;
        _verified = true;
        _sentTo ??= address;
      });
      return;
    }

    final last = await ref.read(verificationSendLogProvider).lastSent(address);
    if (!mounted) return;
    final now = DateTime.now();
    if (last != null && sentRecently(last, now)) {
      setState(() {
        _opening = false;
        _sentTo = address;
        _sentEarlierAt = last;
        _armCooldown(kVerificationResendInterval - now.difference(last));
      });
      return;
    }

    setState(() => _opening = false);
    await _send();
  }

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
      // Remembered BEFORE the mounted check: the mail has gone whether or not this screen is
      // still here to say so, and the next mount must know not to kill it. Not awaited — a
      // slow disk is no reason to hold the button.
      unawaited(ref.read(verificationSendLogProvider).record(outcome.email, DateTime.now()));
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sentTo = outcome.email;
        _sentEarlierAt = null;
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
    } catch (e, stack) {
      // The failure nobody anticipated. As the router's gate this screen has nothing behind
      // it, so an error escaping here would leave "Sending…" on a dead button forever. Name
      // the only thing that is certain — no link went — and give the button back.
      debugPrint('verification send threw: ${e.runtimeType} $e\n$stack');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Apnivaas could not send the link just now. Please try again in a few minutes.';
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
    } catch (e, stack) {
      // Same reason as in [_send]: a gate may not end on a spinner that never stops.
      debugPrint('verification check threw: ${e.runtimeType} $e\n$stack');
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Apnivaas could not check your address just now. Please try again.';
        _notYetCount = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final address = _sentTo ?? session?.email ?? '';

    // THE OPENING SEQUENCE ([_open]: re-check, then maybe send), and why it starts here
    // rather than in initState().
    //
    // The address comes from the session, and the session is an AsyncNotifier: on a cold start
    // it can still be resolving when the first frame is built. A post-frame callback from
    // initState once fired with NO ADDRESS and mailed the empty string — caught by a test, not
    // by a person, which is the only reason it never reached a release.
    //
    // So the trigger is the arrival of the address, not the arrival of the frame. `_opened`
    // makes it once-only; the work is deferred out of build() because starting a request during
    // a build is how you get a setState-during-build crash.
    final email = session?.email ?? '';
    if (!_opened && email.isNotEmpty) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open(email);
      });
    }

    return PopScope(
      // A gate the back gesture walks through is not a gate. When blocking, the visible way
      // out is Sign out — a real action rather than a dead end.
      canPop: !widget.blocking,
      // The sign-in screen's own page. As the gate this is one of the steps a new account walks
      // before it reaches a home, so it wears the steps' brand bar; as the resident's detour the
      // same bar carries a back arrow, because there is somewhere to go back to.
      child: AuthScaffold(
        topBar: AuthTopBar(
          leading: widget.blocking
              ? null
              : IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
        ),
        children: [
          const SizedBox(height: Space.md),
          const AuthHeading(
            icon: ClayIcons.bell,
            title: 'Verify your email',
            message: 'One tap on a link proves this address is yours.',
          ),
          const SizedBox(height: Space.lg),
          if (_verified) _done(t) else ..._form(t, address),
        ],
      ),
    );
  }

  Widget _done(ThemeData t) {
    final staff = ApnivaasSession.verificationGatedRoles.contains(ref.read(sessionProvider)?.role);
    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: ClayWell(ClayIcons.success)),
          const SizedBox(height: Space.md),
          Text('Email verified', style: t.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: Space.xxs),
          Text(
            // "Create and manage accounts" is a staff sentence — it is the one thing the proof
            // unlocks on the server — so a resident is thanked without being told about powers
            // they do not have.
            'Thanks — ${_sentTo ?? 'your address'} is confirmed.'
            '${staff ? ' You can create and manage accounts as normal.' : ''}',
            style: t.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.lg),
          FilledButton(
            // Pops when this was PUSHED from the home-screen banner. As the router's gate there is
            // nothing to pop to: the redirect releases the account the moment a re-read lands a
            // verified session — which has normally happened before this panel is even read. If
            // that re-read was dropped, this asks for it again, so the button is never inert.
            onPressed: () {
              final navigator = Navigator.of(context);
              if (navigator.canPop()) {
                navigator.pop(true);
              } else {
                ref.read(authControllerProvider.notifier).reload();
              }
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// "less than a minute ago", "1 minute ago", "7 minutes ago". Only ever shown for a link
  /// inside [autoSendWindow], so minutes are the only unit it needs.
  static String _ago(Duration age) {
    final minutes = age.inMinutes;
    if (minutes < 1) return 'less than a minute ago';
    return minutes == 1 ? '1 minute ago' : '$minutes minutes ago';
  }

  String _whatHappened(String address) {
    if (address.isEmpty) {
      return 'Apnivaas is sending a confirmation link to the address on your account.';
    }
    if (_opening) return 'Checking whether $address is already confirmed…';
    final earlier = _sentEarlierAt;
    if (earlier != null) {
      return 'Apnivaas sent a confirmation link to $address '
          '${_ago(DateTime.now().difference(earlier))}. That link still works.';
    }
    if (_sentTo != null) return 'Apnivaas sent a confirmation link to $address';
    if (_sending) return 'Sending a confirmation link to $address…';
    return 'The confirmation link goes to $address';
  }

  List<Widget> _form(ThemeData t, String address) {
    final cooldown = _cooldown;
    final error = _error;
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);

    return [
      // WHAT HAS HAPPENED, AND WHAT TO DO, in one card: the two sentences the person has to read
      // before any button makes sense. Everything under it is what they can do about it.
      FlatSurface(
        borderRadius: Radii.rSurface,
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Check your email',
              style: t.textTheme.headlineSmall?.copyWith(fontFeatures: const []),
            ),
            const SizedBox(height: Space.xxs),
            // WHAT HAS ACTUALLY HAPPENED, and nothing more. "Sent" is said only once a send has
            // succeeded — or a recent one from this phone is known, with its age — so the person
            // never goes looking for a mail that was never sent.
            Text(
              _whatHappened(address),
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface),
            ),
            const SizedBox(height: Space.sm),
            // THE ONE THING THIS SCREEN CANNOT SEE: the link is opened somewhere else — a mail
            // app, a browser, sometimes another device — and nothing tells this screen when. So
            // the instruction has to include the return trip, which is the step people skip.
            //
            // SINCE THE DEEP LINK IT HAS TWO CASES, AND IT MAY NOT TELL ONLY THE HAPPY ONE. On
            // this phone the link opens the app and signs the person in, and that is the whole
            // proof. On a laptop — or any device without the app — the browser cannot open a
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
              'Open that email and tap the link. On this phone it opens Apnivaas and signs you in '
              '— that sign-in is the proof, and there is nothing more to do. Opened on a laptop or '
              'another device it lands on a web page instead: come back to Apnivaas and tap the '
              'button below, which finishes it just as well.',
              style: t.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.md),

      if (error != null) ...[
        FormNote(error),
        if (_operatorFault) ...[
          const SizedBox(height: Space.xs),
          Text(
            'This is a setting on the Apnivaas project, not something you can fix from here. '
            'Nothing you do in the app will work until an administrator changes it.',
            style: muted,
          ),
        ],
      ] else if (_notYet) ...[
        FormNote(
          'Not confirmed yet. Open the newest email from Apnivaas and tap the link — check '
          'your spam folder if it is not in the inbox. Only the newest link works, so if '
          'you tapped an older one, send a new email and use that.',
          tone: FormNoteTone.warning,
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
            'If this keeps happening it is usually one setting on the Apnivaas project, not '
            'something you can fix from here. ${Env.emailRedirectSetupHint}',
            style: muted,
          ),
        ],
      ] else
        Text(
          'The email can take a minute to arrive. Only the newest link works.',
          style: muted,
        ),

      const SizedBox(height: Space.lg),
      BusyFilledButton(
        label: 'I have opened the link',
        busy: _checking,
        onPressed: _check,
      ),
      const SizedBox(height: Space.xxs),
      TextButton(
        onPressed: _canResend ? _send : null,
        child: _sending
            ? const Text('Sending…')
            : Text(cooldown == Duration.zero
                ? 'Send it again'
                : 'Send again in ${cooldown.inSeconds}s'),
      ),

      // THE WAY OUT, AND IT CHANGES MEANING WITH THE CONTEXT.
      //
      // From the home-screen banner this is a real "later": a resident's app is fully usable
      // unverified and nobody should be nagged into a dead end. As the router's GATE there is
      // nothing behind this screen, and "later" would either do nothing (a broken button) or
      // have to let them past, which is the one thing the gate exists to prevent. Signing
      // out is the honest alternative: a real action that always works, with the account
      // waiting when the mail arrives.
      if (!widget.blocking)
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('I will do this later'),
        )
      else
        TextButton(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          child: const Text('Sign out'),
        ),

      // WHO FIXES A WRONG ADDRESS. The one failure nobody on this screen can repair: the
      // link is going to a typo, and only someone with edit rights over this account can
      // change it — the PG owner for staff and residents, Apnivaas support for an owner.
      // Said here, in both modes, because a gate whose only exit is Sign out must at least
      // say where the door to the fix is. The mailbox is the one the legal documents name.
      const SizedBox(height: Space.xs),
      Text(
        'Wrong address? Ask your PG owner to correct it. '
        'Owners: contact Apnivaas support at $kGrievanceEmail.',
        style: muted,
        textAlign: TextAlign.center,
      ),
    ];
  }
}

// Open the verification screen from anywhere. Returns true when the address was proved.
Future<bool> openEmailVerification(BuildContext context) async {
  final result = await Navigator.of(context).push(VerifyEmailScreen.route());
  return result ?? false;
}

/// The persistent ask, shown above every role's content until the address is proved.
///
/// It is a BANNER and not a blocking dialog because of the decision at the top of this file:
/// for a resident the account works, and this is the one outstanding thing. It draws nothing at
/// all when the session has no reachable address — a resident who signs in with a phone number
/// is never asked for a proof they cannot produce, and that exemption is carved by ADDRESS
/// rather than by role, so a student whose warden collected a real email is asked.
///
/// SINCE 1.2.0 A STAFF ACCOUNT NEVER SEES IT. An unverified owner, manager, warden or super
/// admin is held on the /verify-email gate by the router and never reaches a home screen, so
/// in practice this is the residents' banner. It still keys on
/// [ApnivaasSession.needsEmailVerification] rather than on role, so it can never disagree with
/// the gate about who owes a proof.
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

    // THE CALM BANNER, NOT THE GOLD ONE. For a resident this is a requirement and not a trap —
    // the account works either way — so it is the Mist explanation a screen carries rather than
    // the gold task banner, which is for work that is due and which a home screen may already
    // be using for something that is.
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: InfoBanner(
        title: 'Verify your email',
        icon: ClayIcons.bell,
        // Not "to create or manage accounts": since 1.2.0 the people who read this are
        // residents, and that is a staff power. What is true for everyone is that the address
        // is confirmed as theirs.
        message: 'Open the link Apnivaas emails to ${session.email} to confirm it is yours. '
            'Everything else keeps working.',
        action: PillButton(
          label: 'Verify now',
          filled: true,
          onPressed: () => openEmailVerification(context),
        ),
      ),
    );
  }
}
