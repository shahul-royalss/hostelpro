/// Pull-to-refresh, bounded and spoken.
///
/// ═══ THE TWO BUGS THIS FILE EXISTS TO CLOSE ═══
///
/// 1. AN UNBOUNDED `await ref.read(provider.future)` HOLDS THE SPINNER FOR MINUTES.
///    Riverpod 3 retries a failed provider by itself — `ProviderContainer.defaultRetry` allows
///    ten attempts with exponential backoff — and while a retry is scheduled the element's
///    state is `AsyncLoading(retrying: true)`, which does NOT complete `provider.future`
///    (riverpod-3.4.2 `element.dart`, `onLoading`: the completer is left pending). Every read in
///    this app is deadlined at twelve seconds by [guard], so a backend that accepts the socket
///    and never answers costs ten deadlines plus ~38 seconds of backoff before the future
///    finally completes. That is over two minutes of a turning spinner for one pull.
///
/// 2. THE SECTION UNDERNEATH WILL NOT SAY THE REFRESH FAILED — BY DESIGN.
///    `AsyncSection` renders `builder(value.requireValue)` whenever `hasValue` is true, so a
///    reload that fails over rows that had already loaded draws exactly what was there before.
///    That is the right call for the section — losing your place in a 200-row roster because a
///    lift ate one packet is worse than a stale row — but it means the GESTURE has to report its
///    own outcome. Otherwise pull-to-refresh is a control that does nothing when used, which is
///    the bug class this app treats as a defect.
///
/// So: bound the wait, and say what happened. The section keeps the data; the gesture speaks.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/failure.dart';

/// How long a pull-to-refresh holds its spinner before it stops waiting and says so.
///
/// The same twelve seconds [dataDeadline] gives one read, deliberately: a refresh that is still
/// waiting after the read it triggered has already run out of time is waiting on riverpod's
/// retry schedule, not on the server, and the person holding the phone has no way to know that.
const refreshDeadline = Duration(seconds: 12);

/// Runs a pull-to-refresh's wait to a conclusion the person can see.
///
/// Pass the read whose arrival means "the screen is up to date" — usually
/// `() => ref.read(theProviderThisScreenWatches.future)`. It is awaited with [deadline]; on a
/// failure or a timeout the reason is put on screen in a sentence and the spinner is released.
///
/// NEVER RETHROWS. An exception escaping a `RefreshIndicator.onRefresh` callback is an unhandled
/// async error — five screens in the super-admin console were throwing one on every failed pull
/// — and it buys nothing, because by then the failure has already been reported here.
///
/// THE TIMEOUT IS CLASSIFIED AS A READ. [AppFailure.from] has to assume [SideEffect.unknown]
/// because it cannot tell a read from a write, and its wording for that case — "nobody can say
/// yet whether it went through" — is nonsense about a refresh. A refresh changes nothing, so it
/// is [SideEffect.none] and gets the sentence written for that: the server is not answering,
/// your connection is fine.
Future<void> settleRefresh(
  BuildContext context,
  Future<void> Function() read, {
  Duration deadline = refreshDeadline,
}) async {
  // Both resolved BEFORE the await. After it this context may be gone — the tab was swapped,
  // the sheet was dismissed — and reading either off a defunct element throws.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final errorTone = context.tones.error;

  AppFailure failure;
  try {
    await read().timeout(deadline);
    return;
  } on TimeoutException catch (error) {
    failure = AppFailure.timedOut(error, sideEffect: SideEffect.none);
  } catch (error) {
    failure = AppFailure.from(error);
  }
  if (!context.mounted) return;
  _say(messenger, errorTone, failure);
}

/// The failure, in the snackbar shape the rest of the app already uses for one.
///
/// The tone is carried by a GLYPH and not by the bar's fill. Repainting the bar
/// [NivoraColors.error] puts the snackbar theme's own light content colour on it at 2.4:1 —
/// owner_staff_screen.dart and receipt_screen.dart both measured that and both landed here.
void _say(ScaffoldMessengerState? messenger, Color errorTone, AppFailure failure) {
  if (messenger == null || !messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: IconSize.md, color: errorTone),
          const SizedBox(width: Space.xs),
          Expanded(child: Text(failure.message)),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      duration: Motion.readMessage,
    ));
}
