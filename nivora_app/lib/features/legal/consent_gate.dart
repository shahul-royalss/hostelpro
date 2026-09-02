library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/failure.dart';
import '../../shared/glass/glass.dart';
import 'legal_documents.dart';
import 'legal_providers.dart';
import 'legal_screen.dart';

/// STANDS BETWEEN A SIGNED-IN USER AND THE PRODUCT UNTIL THEY HAVE AGREED TO THE DOCUMENTS.
///
/// ═══ WHY THIS IS A REQUIREMENT AND NOT A PREFERENCE ═══
/// NIVORA holds residents' names, phone numbers, permanent addresses, guardian contact details,
/// government-ID scans and a payment ledger. Google Play will not list an app that handles
/// personal data without a publicly reachable privacy policy, and the DPDP Act 2023 requires
/// notice and consent before that processing begins. The listing is rejected without the URL;
/// the processing is unlawful without the consent. This widget is the second half.
///
/// ═══ WHERE IT SITS, AND WHY NOT IN THE ROUTER ═══
/// It wraps each role home in `appScreens` (core/router/router.dart), which is the whole of the
/// signed-in surface: all five role subtrees render through `RoleShell`, and the pre-app
/// obligations — change password, second-factor enrolment — are separate routes that
/// deliberately stay OUTSIDE it. Somebody forced to change a temporary password should not have
/// to agree to a privacy policy first to be allowed to secure their account.
///
/// It is NOT an arm in `resolveRedirect`, and that was a considered choice. Consent state is
/// fetched, not carried in the session row, so a redirect arm would have to either block
/// sign-in on an extra round trip or invent a spinner route to wait on. More importantly,
/// `resolveRedirect` is a pure function with an exhaustive every-phase-against-every-route
/// matrix in test/router_redirect_test.dart; adding a fetched condition to it would have made
/// that matrix's meaning depend on data it cannot see. The router is untouched by this feature.
///
/// ═══ THE FOUR STATES ARE FOUR STATES ═══
/// The house rule (see data/models/failure.dart) is that LOADING, EMPTY, FAILED and REFUSED
/// never collapse into each other. Here they are:
///
///   · CHECKING — a spinner. We do not yet know and do not pretend to.
///   · NOT ACCEPTED — the documents and the two buttons. This is the "empty" case: a successful
///     read that found no acceptance. It is the only one that is a normal part of using the app.
///   · FAILED — offline, or the server did not answer. Try again, and a way out.
///   · REFUSED / SIGNED OUT — the credential is the problem. No Try again button, because
///     retrying cannot help; the offer is to sign in again.
///
/// FAILING CLOSED IS DELIBERATE. If we cannot establish that this person agreed, they do not go
/// in. The alternative — letting them through on a failed check — would mean the gate stops
/// existing the moment the network is bad, which is the same as not having one. What must never
/// happen is that failing closed also strands them, so every non-passing state on this screen
/// carries Sign out.
class ConsentGate extends ConsumerStatefulWidget {
  const ConsentGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends ConsumerState<ConsentGate> {
  /// Set the moment the server confirms an acceptance, so the person goes straight in.
  ///
  /// WHY NOT JUST INVALIDATE AND RE-READ. Invalidating alone would send someone who has just
  /// successfully agreed back through a network read that can itself fail — and being shown
  /// "we could not check whether you agreed" one second after agreeing is the app calling the
  /// user a liar. The server said yes; that is the answer. The provider is invalidated as well,
  /// so every later build reads the durable fact rather than this flag.
  bool _acceptedNow = false;

  bool _busy = false;
  AppFailure? _writeError;

  @override
  Widget build(BuildContext context) {
    if (_acceptedNow) return widget.child;

    final consent = ref.watch(legalConsentProvider);

    // ═══ WHY THIS IS NOT `consent.when(...)` ═══
    //
    // Riverpod 3 represents A FAILED READ THAT IT IS STILL RETRYING as an `AsyncLoading` that
    // CARRIES the error, and `when` dispatches on the runtime type. Written the obvious way,
    // this gate showed a spinner for the entire default ten-retry backoff — about 38 seconds —
    // to a user whose only problem was no signal, and only then admitted that the check had
    // failed. Caught by 'FAILED offers a retry' in test/legal_consent_test.dart; the same trap
    // is documented at features/student/widgets/rent.dart and features/common/refresh.dart.
    //
    // So the state is read by ASKING, in the order the answers matter:

    // 1. A KNOWN ACCEPTANCE. `hasValue` and not just `value != null`, because the value type is
    //    itself nullable and `.value` alone cannot tell "no answer yet" from "answered: never
    //    accepted". Once we know somebody agreed, a later failed refresh does not take that
    //    back — they did agree, and we read it.
    if (consent.hasValue && consent.value != null) return widget.child;

    // 2. FAILED or REFUSED, including while a retry is still scheduled.
    if (consent.hasError) {
      return _GateScaffold(
        child: _CheckFailed(
          failure: AppFailure.from(consent.error!),
          onRetry: () => ref.invalidate(legalConsentProvider),
        ),
      );
    }

    // 3. CHECKING. No answer and no error yet — the only honest thing to draw is a wait.
    if (consent.isLoading) {
      return const _GateScaffold(child: Center(child: CircularProgressIndicator()));
    }

    // 4. A successful read that found no acceptance. The gate proper.
    return _GateScaffold(
      child: _ConsentPrompt(
        busy: _busy,
        error: _writeError,
        onAccept: _accept,
      ),
    );
  }

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _writeError = null;
    });
    try {
      await ref.read(legalConsentStoreProvider).accept(
            version: kLegalVersion,
            surface: 'android',
          );
      if (!mounted) return;
      // Order matters: mark accepted BEFORE invalidating, so the rebuild the invalidation
      // triggers already knows the answer and never flashes the gate again.
      setState(() => _acceptedNow = true);
      ref.invalidate(legalConsentProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() => _writeError = AppFailure.from(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// The shell every non-passing state is drawn in. One place, so the four states cannot drift
/// into four different-looking screens.
class _GateScaffold extends StatelessWidget {
  const _GateScaffold({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: child),
    );
  }
}

/// FAILED and REFUSED, told apart.
class _CheckFailed extends ConsumerWidget {
  const _CheckFailed({required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `isRetryable` already encodes both halves of the question — could it work, and could
    // repeating it do harm. A read cannot do harm, so this is purely "is it worth a button".
    final canRetry = failure.isRetryable;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: StateCard(
          badge: failure.needsSignIn ? 'SIGN IN AGAIN' : 'CANNOT CHECK',
          tone: NivoraColors.warning,
          child: StateBody(
            title: failure.needsSignIn
                ? 'Your session has ended'
                : 'Cannot check your agreement',
            message: canRetry || failure.needsSignIn
                ? failure.message
                : '${failure.message}\n\nNIVORA cannot let you in until it can confirm that '
                    'you have agreed to the Terms of Use and Privacy Policy.',
            action: canRetry
                ? FilledButton(onPressed: onRetry, child: const Text('Try again'))
                : null,
            link: TextButton(
              onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
              child: const Text('Sign out'),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gate proper: read this, then agree or decline.
class _ConsentPrompt extends ConsumerStatefulWidget {
  const _ConsentPrompt({required this.busy, required this.error, required this.onAccept});

  final bool busy;
  final AppFailure? error;
  final Future<void> Function() onAccept;

  @override
  ConsumerState<_ConsentPrompt> createState() => _ConsentPromptState();
}

class _ConsentPromptState extends ConsumerState<_ConsentPrompt> {
  /// Which document is on screen. Both are here in full; this chooses which one is showing.
  int _index = 0;

  /// Ticked by the person, not by us. An unticked box is the default on purpose: a pre-ticked
  /// consent is not consent, and every regulator that has written about it says so.
  bool _agreed = false;

  /// True once the person has actually declined, which turns this screen into the explanation
  /// of what declining means rather than silently doing nothing.
  bool _declined = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (_declined) {
      return _DeclinedNotice(
        // COMING BACK CLEARS THE TICK. Somebody who ticked the box, thought better of it, read
        // what declining means and then returned is making the decision again — so they make it
        // again, rather than finding it already made and one stray tap from being final.
        onBack: () => setState(() {
          _declined = false;
          _agreed = false;
        }),
      );
    }

    final document = kLegalDocuments[_index];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BEFORE YOU START', style: t.textTheme.labelSmall),
              const SizedBox(height: Space.xxs),
              Text('Please read and agree', style: t.textTheme.titleLarge),
              const SizedBox(height: Space.xxs),
              Text(
                'NIVORA keeps personal information about you and, if you are staff, about the '
                'residents you look after. These two documents say exactly what is kept, who '
                'can see it and how long it is held. You can read them again at any time from '
                'the header of any screen.',
                style: t.textTheme.bodyMedium,
              ),
              const SizedBox(height: Space.sm),
              SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < kLegalDocuments.length; i++)
                    ButtonSegment<int>(value: i, label: Text(kLegalDocuments[i].title)),
                ],
                selected: {_index},
                onSelectionChanged: (s) => setState(() => _index = s.first),
                showSelectedIcon: false,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.md),
            children: [LegalDocumentView(document: document)],
          ),
        ),
        _AgreeBar(
          agreed: _agreed,
          busy: widget.busy,
          error: widget.error,
          onChanged: (v) => setState(() => _agreed = v),
          onAccept: widget.onAccept,
          onDecline: () => setState(() => _declined = true),
        ),
      ],
    );
  }
}

/// The pinned bottom bar: the tick, the two buttons and any failure from the write.
class _AgreeBar extends StatelessWidget {
  const _AgreeBar({
    required this.agreed,
    required this.busy,
    required this.error,
    required this.onChanged,
    required this.onAccept,
    required this.onDecline,
  });

  final bool agreed;
  final bool busy;
  final AppFailure? error;
  final ValueChanged<bool> onChanged;
  final Future<void> Function() onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FlatSurface(
      weight: GlassWeight.regular,
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The whole row is the tap target, not just the 20dp box.
          InkWell(
            onTap: busy ? null : () => onChanged(!agreed),
            borderRadius: Radii.rControl,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: agreed,
                    onChanged: busy ? null : (v) => onChanged(v ?? false),
                  ),
                  const SizedBox(width: Space.xxs),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: Text(
                        'I have read and agree to the Terms of Use and the Privacy Policy.',
                        style: t.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: Space.xs),
            Semantics(
              liveRegion: true,
              child: Text(
                // A write that timed out is not reported as a failure anywhere else in this
                // app and is not reported as one here either — accept_legal_terms() is
                // idempotent, so the honest instruction is simply to try again.
                error!.message,
                style: t.textTheme.bodyMedium?.copyWith(color: context.tones.error),
              ),
            ),
          ],
          const SizedBox(height: Space.sm),
          FilledButton(
            // Disabled until the box is ticked. The button being dead is the feedback that the
            // tick is required; the tick row above is one tap away and clearly the thing to do.
            onPressed: agreed && !busy ? () => onAccept() : null,
            child: busy
                ? SizedBox(
                    width: IconSize.md,
                    height: IconSize.md,
                    child: CircularProgressIndicator(
                      strokeWidth: Strokes.glyph,
                      color: t.colorScheme.onPrimary,
                    ),
                  )
                : const Text('Agree and continue'),
          ),
          const SizedBox(height: Space.xxs),
          // A REAL OPTION, not a decoration. It is never disabled — including while a write is
          // in flight, for the same reason Sign out on the change-password screen is not: the
          // one moment somebody most needs a door is the moment the button they pressed has not
          // come back.
          TextButton(
            onPressed: onDecline,
            child: const Text('I do not agree'),
          ),
        ],
      ),
    );
  }
}

/// What declining actually means, said plainly, with the two ways forward.
///
/// Declining must not be a dead end and must not be a trick. It does not silently do nothing
/// (which reads as a broken button), it does not sign the person out from under themselves
/// (which loses them the chance to change their mind), and it does not nag. It explains, offers
/// the way back, and offers the door.
class _DeclinedNotice extends ConsumerWidget {
  const _DeclinedNotice({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: StateCard(
          badge: 'NOT AGREED',
          tone: NivoraColors.warning,
          child: StateBody(
            title: 'NIVORA cannot be used without agreeing',
            message:
                'That is a genuine choice, and nothing has been recorded. But the app keeps '
                'personal information about you in order to work at all, and it may not do '
                'that without your agreement — so there is no version of it that runs from '
                'here.\n\n'
                'If something in the documents is the problem, your hostel can raise it, or '
                'you can write to the address in the Privacy Policy. Your account stays as it '
                'is either way, and you can come back and agree at any time.',
            action: FilledButton(
              onPressed: onBack,
              child: const Text('Back to the documents'),
            ),
            link: TextButton(
              onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
              child: const Text('Sign out'),
            ),
          ),
        ),
      ),
    );
  }
}
