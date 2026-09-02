library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// WHETHER THE CREDENTIAL THIS APP IS ABOUT TO SPEAK WITH IS ONE THE SERVER WILL STILL LISTEN TO.
///
/// ═══ THE BUG THIS FILE EXISTS TO END ═══
/// A super admin holding a genuinely `aal2` session was told:
///
///     Not permitted — This console is for the Super Admin account. Sign in with that account
///     to see platform data.
///
/// The account was right, the role was right, the second factor was right, and the server was
/// willing: `rpc_sa_dashboard()` returns one row at aal2 on an empty platform, measured. What
/// had gone wrong was the TOKEN, and the path from "the token died" to "you are the wrong
/// person" is short, mechanical, and entirely inside our dependencies:
///
///   1. The access token's TTL is one hour. The screenshot was taken 1h48m after the last
///      successful refresh, during one of the windows in which this free-tier NANO instance
///      reports PostgREST and Auth Unhealthy.
///   2. A refresh that fails with anything other than [AuthRetryableFetchException] makes
///      gotrue drop the session outright — `_removeSession()` in gotrue_client.dart, inside
///      `_doRefresh`. `currentSession` becomes null.
///   3. `SupabaseClient._getAccessToken()` then returns null (supabase_client.dart:284), and
///      `AuthHttpClient` FILLS THE GAP WITH THE ANON KEY:
///
///          if (accessToken != null) {
///            request.headers.putIfAbsent("Authorization", () => 'Bearer $accessToken');
///          } else if (...) {
///            request.headers.putIfAbsent("Authorization", () => 'Bearer $_supabaseKey');
///          }
///
///      — auth_http_client.dart:24-32, supabase-2.16.1. The request goes out perfectly well
///      formed, signed as `anon`.
///   4. `app.is_super_admin()` is false for `anon`, so `rpc_sa_dashboard()` answers with ZERO
///      ROWS — which is exactly what it answers a real person in the wrong role, because the
///      function ends in a `where` rather than raising 42501.
///   5. `rpcRowOrRefusal` turned that emptiness into [AccessDeniedFailure], and the console
///      turned that into a sentence about who the reader is.
///
/// Every step is correct in isolation. The composition tells a person their identity is wrong
/// when the truth is that their session died — and sends them to re-verify an account that was
/// never the problem. Twice now that has cost a live debugging session.
///
/// ═══ SO: NEVER CONCLUDE ANYTHING ABOUT WHO SOMEBODY IS FROM AN EMPTY ANSWER UNTIL YOU KNOW
///     WHAT CREDENTIAL ASKED THE QUESTION ═══
/// That is the whole job of this enum. It is read at the moment an empty answer is classified,
/// not at the moment the request was built, because the interesting failures all happen in
/// between.
enum SessionStanding {
  /// This client is holding no session at all. Anything it sends goes out as `anon` (see
  /// above), so an empty answer is a statement about the ANONYMOUS role and about nobody else.
  none,

  /// A session is held and its access token is past its expiry. The server will reject it, or —
  /// worse, and this is the case that produced the bug — gotrue will quietly decline to send it
  /// and the anon key goes instead. Either way nothing that comes back is about the holder.
  expired,

  /// A session is held and its access token is still inside its lifetime. Only here is an empty
  /// answer evidence about the person: they asked, as themselves, and the server said nothing.
  live,
}

/// The rule, with no Supabase client in it, so it can be asserted in a unit test.
///
/// [accessTokenExpiry] is null when the token carries no `exp` — gotrue derives `expiresAt` by
/// decoding the JWT payload and returns null if that fails. A token whose expiry cannot be read
/// is treated as [SessionStanding.live]: we have no evidence it is dead, and inventing one would
/// sign people out over an unfamiliar token shape. The server remains the authority; this is
/// only ever used to decide what a SILENCE meant.
///
/// NO MARGIN, DELIBERATELY. gotrue's own `isExpired` adds a 30-second cushion so it can refresh
/// early; that is the right rule for "should I refresh now" and the wrong one for "was the
/// answer I just received about this person". A token that had four seconds left when the
/// request went out was a real credential and the server treated it as one.
SessionStanding standingAt({
  required bool hasSession,
  required DateTime? accessTokenExpiry,
  required DateTime now,
}) {
  if (!hasSession) return SessionStanding.none;
  if (accessTokenExpiry == null) return SessionStanding.live;
  return now.isBefore(accessTokenExpiry) ? SessionStanding.live : SessionStanding.expired;
}

/// [standingAt], read off a live client.
///
/// `Session.expiresAt` is the `exp` claim decoded out of the access token itself
/// (gotrue session.dart:77) — not a field the server sent alongside it and not a local clock
/// reading — so this asks the same question PostgREST will ask of the same bytes.
SessionStanding sessionStandingOf(SupabaseClient db, {DateTime? now}) {
  final session = db.auth.currentSession;
  final expiresAt = session?.expiresAt;
  return standingAt(
    hasSession: session != null,
    accessTokenExpiry:
        expiresAt == null ? null : DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000),
    now: now ?? DateTime.now(),
  );
}
