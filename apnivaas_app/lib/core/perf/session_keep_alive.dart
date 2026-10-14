/// The other half of the no-skeleton contract: data that has been fetched STAYS fetched.
///
/// `TabWarmer` (tab_warmer.dart) starts a tab's first request early; this file is what stops
/// the result being thrown away. An autoDispose provider dies when its listener count drops —
/// which for a warmed-but-never-tapped tab is the instant the warm read completes, and for a
/// visited tab could be any rebuild that briefly detaches it. [holdForSession] pins the state
/// for exactly as long as it is safe to: the life of the signed-in user.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

/// Holds an autoDispose provider's state for the lifetime of the signed-in session.
///
/// Call it first thing in the provider's build:
///
/// ```dart
/// final thingsProvider = FutureProvider.autoDispose.family<List<Thing>, String>((ref, id) {
///   holdForSession(ref);
///   return ref.watch(thingRepositoryProvider).things(id);
/// });
/// ```
///
/// WHAT IT DOES, precisely:
///
///  * While a user is signed in, takes a [Ref.keepAlive] link, so the state survives its
///    listeners. A tab revisit renders instantly from the held value; `ref.invalidate` still
///    refreshes it in place (AsyncValue keeps the previous value across a rebuild, which is
///    what the AsyncSection widgets render while the refresh is in flight).
///
///  * Watches the signed-in user's id — nothing else off the session, so a token refresh or a
///    profile edit does not thrash every cache in the app. When the id CHANGES (one account
///    signs out and another signs in), every held provider rebuilds and refetches under the
///    new session's RLS.
///
///  * When the id becomes NULL (sign-out), the rebuild runs this function again, which now
///    closes the link it just took: the provider is back to plain autoDispose and is disposed
///    the moment its last listener unmounts — which the sign-out redirect does immediately.
///    Cached tenant data therefore cannot survive into the next login. Hostel switches need
///    no help from here: tab-backing providers are families keyed by hostelId, so a different
///    hostel is a different provider instance altogether.
///
/// This is a LIFETIME tool, not an authorization one. It never widens a read — the provider
/// fetches whatever it always fetched, under the same RLS; this only decides how long the
/// answer is kept.
void holdForSession(Ref ref) {
  final link = ref.keepAlive();
  final userId = ref.watch(sessionProvider.select((s) => s?.userId));
  if (userId == null) {
    link.close();
    return;
  }
  // The watch above already forces a rebuild on any change of user — and the rebuilt build
  // runs this function again, which closes the fresh link when nobody is signed in. The
  // listen is belt and braces: it releases THIS build's hold the moment a sign-out lands,
  // without waiting for that rebuild to be flushed.
  ref.listen(sessionProvider.select((s) => s?.userId), (_, next) {
    if (next == null) link.close();
  });
}
