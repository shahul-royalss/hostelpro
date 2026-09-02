library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';

/// THE BUTTON A DEAD SESSION OWES THE PERSON HOLDING THE PHONE.
///
/// Every other terminal state in this app either has a Try again that can work or has nothing
/// to offer at all. An expired sign-in is neither: retrying sends the same dead token and fails
/// identically, but there IS a recovery, it takes one tap, and until this widget existed the
/// only way to reach it was to find Sign out in a menu — on a screen that had just told the
/// reader they were not permitted to be there.
///
/// ONE WIDGET, FIVE ROLES. The wording of a failure is written per role because the reader
/// differs; this is not wording. "Sign in again" is the same action for a resident and for the
/// platform admin, and five copies of it is five places for the next person to fix four of.
///
/// WHY `signOut()` AND NOT A `context.go(loginRoute)`. Navigating would leave the dead session
/// installed underneath the login screen, so `resolveRedirect` would bounce the user straight
/// back to a role home that cannot load — and every provider still mounted would go on asking
/// the server questions as `anon`. Ending the session publishes [AuthSignedOut], which drops
/// every session-held provider, and the router does the routing. It is also the only path that
/// clears the persisted token off the device.
class SignInAgainButton extends ConsumerStatefulWidget {
  const SignInAgainButton({super.key, this.outlined = false});

  /// The Super Admin console's error panels use outlined actions; the four card-based kits use
  /// the design's cream filled button. Same action, same label, the host's own weight.
  final bool outlined;

  @override
  ConsumerState<SignInAgainButton> createState() => _SignInAgainButtonState();
}

class _SignInAgainButtonState extends ConsumerState<SignInAgainButton> {
  /// `signOut()` reaches the network to revoke, and on the instance this app talks to that can
  /// take seconds or fail. Without this the button is tappable throughout, and a person who
  /// taps it three times fires three revocations at a server that is already struggling.
  bool _busy = false;

  Future<void> _go() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } finally {
      // The widget is normally gone by now — signing out re-routes to the login screen — so
      // this only runs when something kept it alive.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const label = Text('Sign in again');
    final onPressed = _busy ? null : _go;
    if (widget.outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
        child: label,
      );
    }
    return FilledButton(
      onPressed: onPressed,
      // Width 0 so it hugs its label rather than inheriting the theme's full-bleed
      // Size.fromHeight; the height stays at the 48dp tap target.
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      child: label,
    );
  }
}
