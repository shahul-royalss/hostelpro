// WHY EVERY SPINNER IN THE APP USED TO LAST THIRTY-EIGHT SECONDS.
//
// ── THE NUMBER, AND WHERE IT COMES FROM ────────────────────────────────────────────────────
//
// Riverpod 3 retries a failed provider on its own. `ProviderContainer.defaultRetry` allows ten
// attempts, backing off from 200ms and doubling to a 6,400ms ceiling:
//
//     200 + 400 + 800 + 1600 + 3200 + 6400 + 6400 + 6400 + 6400 + 6400  =  38,200 ms
//
// That is the "~38 seconds" the audit measured on the offline cold start and again on the 2FA
// enrolment screen, and it was never a coincidence. While a retry is scheduled the provider sits
// in `AsyncLoading`, so the router keeps the splash up, the 2FA screen keeps "Checking your
// security settings" up, and every AsyncSection keeps its skeleton pulsing — for a failure that
// had already been decided in the first hundred milliseconds.
//
// The default skips only `Error` and `ProviderException`. A dead socket, a refused connection,
// a twelve-second read deadline, an RLS refusal: all `Exception`s, all retried ten times.
//
// ── WHAT IS WORTH RETRYING ─────────────────────────────────────────────────────────────────
//
// Almost nothing, and the reasoning is per case rather than per mood:
//
//   OFFLINE       Waiting 400ms does not bring a network back. The person can see their own
//                 signal bars; the app saying "cannot reach Nivora" in under a second and
//                 offering Try again is strictly more useful than pretending for half a minute.
//   TIMED OUT     Every read already waited its full deadline (dataDeadline, 12s). Retrying a
//                 timeout is how one bad request becomes a two-minute spinner — refresh.dart
//                 documents exactly that. A deadline is the retry budget; it does not get one on
//                 top.
//   REFUSED       Access denied, not found, conflict, invalid input, signed out, expired: the
//                 server said no and meant it. AppFailure.isRetryable already returns false for
//                 these so the UI never draws a Try again button; the container must agree.
//   SERVER / ???  A 5xx or an unclassified transport hiccup is the one case where a second
//                 attempt genuinely might land. It gets exactly two, at 300ms and 600ms, and
//                 then the screen says what happened. Under a second, total.
//
// This is wired ONCE, on the root ProviderScope in main.dart, so it governs the auth restore,
// the MFA check and every data provider alike. Tests that build their own ProviderScope pass
// `retry: (_, _) => null` and are unaffected.

import 'dart:async';

import '../../data/models/failure.dart';

/// The container-wide retry schedule. Returns the delay before the next attempt, or null to
/// stop and surface the error.
Duration? nivoraRetry(int retryCount, Object error) {
  // Programming errors: retrying a null dereference produces the same null dereference.
  if (error is Error) return null;

  // A deadline already spent is a retry already spent.
  if (error is TimeoutException) return null;

  if (error is AppFailure) {
    // A wrapped timeout carries the original text ("no answer within the client deadline:
    // TimeoutException after 0:00:12…", see AppFailure.timedOut); treat it like the raw one.
    final technical = error.technical ?? '';
    if (technical.contains('TimeoutException') ||
        technical.contains('no answer within the client deadline')) {
      return null;
    }

    return switch (error) {
      OfflineFailure() => null,
      AccessDeniedFailure() ||
      ReadOnlyFailure() ||
      NotFoundFailure() ||
      ConflictFailure() ||
      InvalidInputFailure() ||
      SignedOutFailure() ||
      SessionExpiredFailure() =>
        null,
      ServerFailure() || UnexpectedFailure() => _briefly(retryCount),
    };
  }

  // Raw transport errors that escaped guard() — the auth restore is not wrapped in it.
  if (AppFailure.looksOffline(error)) return null;

  return _briefly(retryCount);
}

/// Two quick attempts, then stop. 300ms + 600ms is long enough for a load balancer to route
/// around a bad node and short enough that the screen still answers inside a second.
Duration? _briefly(int retryCount) =>
    retryCount >= maxQuickRetries ? null : Duration(milliseconds: 300 * (retryCount + 1));

/// How many times a transient server failure is retried before the screen reports it.
const maxQuickRetries = 2;
