/// Wiring for join requests, photos and plans. Hand-written like lib/data/providers.dart.
///
/// NONE OF THESE RETRY ON THEIR OWN. Each is a cheap read with its own refresh (pull down, a
/// "Check again", a write that invalidates it); a badge that quietly re-polls three times after
/// a refusal is noise, and a test that mounts a screen without a network must not be left with
/// retry timers running.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import 'models/people.dart';
import 'repositories/people_repository.dart';

Duration? _noRetry(int _, Object _) => null;

/// The account the cached people data belongs to. Watching it drops everything on sign-out or
/// a change of user, so one person's photos never draw on the next person's screen.
String? _uid(Ref ref) => ref.watch(sessionProvider.select((s) => s?.userId));

// ── JOIN REQUESTS (§5) ─────────────────────────────────────────────────────────────────────

/// Pending requests across every PG the caller owns, or the warden's PG. The People/Students
/// tab badge and the home attention row.
final pendingJoinCountProvider = FutureProvider.autoDispose<int>((ref) async {
  if (_uid(ref) == null) return 0;
  return ref.watch(peopleApiProvider).pendingJoinRequestCount();
}, retry: _noRetry);

/// The requests themselves, pending first by default.
final joinRequestsProvider =
    FutureProvider.autoDispose.family<List<ReviewJoinRequest>, String>((ref, status) async {
  if (_uid(ref) == null) return const [];
  return ref.watch(peopleApiProvider).joinRequests(status: status);
}, retry: _noRetry);

// ── PLANS (§7) ─────────────────────────────────────────────────────────────────────────────

final planCatalogProvider = FutureProvider.autoDispose<List<PlanOption>>((ref) async {
  _uid(ref);
  return ref.watch(peopleApiProvider).planCatalog();
}, retry: _noRetry);

final planStatusProvider =
    FutureProvider.autoDispose.family<PlanStatus, String>((ref, hostelId) async {
  _uid(ref);
  return ref.watch(peopleApiProvider).planStatus(hostelId);
}, retry: _noRetry);

// ── PHOTOS (§3) ────────────────────────────────────────────────────────────────────────────

/// The caller's own `users.avatar_path`. Invalidated after a change of photo.
final myAvatarPathProvider = FutureProvider.autoDispose<String?>((ref) async {
  if (_uid(ref) == null) return null;
  final link = ref.keepAlive();
  ref.onDispose(link.close);
  return ref.watch(peopleApiProvider).myAvatarPath();
}, retry: _noRetry);

/// A 60-second signed URL for one object. Held for 50 seconds, then let go, so a screen that
/// comes back later signs again instead of drawing a dead link.
final signedUrlProvider =
    FutureProvider.autoDispose.family<String?, ({String bucket, String path})>((ref, key) async {
  _uid(ref);
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 50), link.close);
  ref.onDispose(timer.cancel);
  return ref.watch(peopleApiProvider).signedUrl(key.bucket, key.path);
}, retry: _noRetry);

/// `users.avatar_path` for the people on a roster, fetched in ONE query per frame.
///
/// A roster row knows its own user id and nothing else. Each row asks for its id while it
/// builds ([request] only notes it); a microtask after the frame's builds sends every id noted
/// in that frame as one `in (...)` read and fills the map once. An id that came back without a
/// photo — or that RLS would not show — is stored as null, so it is never asked for again and
/// the row keeps its initials. No timers: nothing is left running when a test ends.
class AvatarDirectory extends Notifier<Map<String, String?>> {
  final Set<String> _pending = {};
  final Set<String> _asked = {};
  bool _scheduled = false;

  @override
  Map<String, String?> build() {
    _uid(ref);
    _pending.clear();
    _asked.clear();
    _scheduled = false;
    return const {};
  }

  /// Safe to call from build: it changes no state until the microtask runs.
  void request(String userId) {
    if (userId.isEmpty || _asked.contains(userId)) return;
    _asked.add(userId);
    _pending.add(userId);
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(_flush);
  }

  Future<void> _flush() async {
    _scheduled = false;
    if (_pending.isEmpty) return;
    final batch = _pending.toList(growable: false);
    _pending.clear();
    Map<String, String> found;
    try {
      found = await ref.read(peopleApiProvider).avatarPaths(batch);
    } catch (_) {
      found = const {};
    }
    if (!ref.mounted) return;
    state = {
      ...state,
      for (final id in batch) id: found[id],
    };
  }

  /// After the caller changes their own photo.
  void put(String userId, String? path) {
    _asked.add(userId);
    state = {...state, userId: path};
  }
}

final avatarDirectoryProvider =
    NotifierProvider<AvatarDirectory, Map<String, String?>>(AvatarDirectory.new);
