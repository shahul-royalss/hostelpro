import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'onboarding_screen.dart';

/// Shows [OnboardingScreen] the first time this install reaches the sign-in screen, and never
/// again.
///
/// ── WHY A FILE AND NOT A PREFERENCE ───────────────────────────────────────────────────────
///
/// `shared_preferences` is not a dependency of this app. It IS present transitively, because
/// supabase_flutter persists its session with it, and reaching through another package's
/// dependency to store our own state is the kind of thing that breaks on somebody else's minor
/// version bump. `path_provider` is already a direct dependency, so a zero-byte marker file in
/// the application support directory costs nothing and belongs to us.
///
/// ── WHY IT WRAPS SIGN-IN RATHER THAN BEING A ROUTE ────────────────────────────────────────
///
/// The obvious place is a new phase in `resolveRedirect`. That function is pure, and
/// test/router_redirect_test.dart exercises every AuthPhase against every route as a matrix —
/// adding a phase that depends on a disk read would have made the matrix depend on state it
/// cannot see, which is the same reason ConsentGate is a wrapper rather than a redirect arm
/// (see the note in core/router/router.dart). Onboarding is answering "what is this app",
/// which is a question a signed-out person has and nobody else, so the sign-in route is where
/// it belongs anyway.
///
/// ── WHY IT NEVER BLOCKS ───────────────────────────────────────────────────────────────────
///
/// While the marker is being read the child is shown, not a spinner. The read is a local stat
/// that takes under a millisecond, and the failure mode of guessing wrong is that a first-time
/// user sees the sign-in form for one frame before the carousel — which is invisible. The
/// failure mode of a spinner is a blank screen on every launch forever after, for a check that
/// matters exactly once. If the read throws, onboarding is skipped: a person who cannot be
/// shown the tour can still sign in.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  /// Overridable so a test can force either branch without touching a real disk.
  @visibleForTesting
  static Future<bool> Function()? seenOverride;

  /// Overridable so a test can observe the write without performing one.
  @visibleForTesting
  static Future<void> Function()? markOverride;

  static Future<File> _marker() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'onboarding_seen'));
  }

  /// TOTAL: this never throws, and the override is INSIDE the guard rather than in front of
  /// it. Putting the override first made the method total only on the production path, which a
  /// test then could not exercise — the first version of onboarding_test.dart caught exactly
  /// that by throwing from the override and watching the error escape.
  static Future<bool> hasSeen() async {
    try {
      if (seenOverride != null) return await seenOverride!();
      return (await _marker()).existsSync();
    } catch (_) {
      // An unreadable support directory counts as "seen". The tour is a courtesy; nothing
      // about it is worth standing between somebody and their sign-in form.
      return true;
    }
  }

  /// Also total, for the same reason: a tour that shows twice is a smaller problem than a
  /// crash on the way to sign-in.
  static Future<void> markSeen() async {
    try {
      if (markOverride != null) return await markOverride!();
      await (await _marker()).create(recursive: true);
    } catch (_) {
      // Deliberately swallowed. See above.
    }
  }

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  /// Starts TRUE, which is the whole of the no-spinner decision. The overwhelming majority of
  /// launches are repeat ones, so assuming "seen" until the marker says otherwise means those
  /// launches never render a frame they did not need.
  bool _seen = true;

  @override
  void initState() {
    super.initState();
    OnboardingGate.hasSeen().then((seen) {
      if (mounted && seen != _seen) setState(() => _seen = seen);
    });
  }

  void _done() {
    // Marked before the swap, not after: if the process dies between the two, the tour has
    // still been seen and showing it again would be the wrong recovery.
    OnboardingGate.markSeen();
    if (mounted) setState(() => _seen = true);
  }

  @override
  Widget build(BuildContext context) =>
      _seen ? widget.child : OnboardingScreen(onDone: _done);
}
