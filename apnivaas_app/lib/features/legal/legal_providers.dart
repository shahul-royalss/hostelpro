library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../data/providers.dart';
import 'legal_documents.dart';
import 'legal_repository.dart';

/// The store the gate reads and writes through.
///
/// Exposed as a provider for exactly one reason: [ConsentGate] stands in front of every screen
/// in the product, so every widget test that mounts a role shell through the router has to be
/// able to say what this user's consent state is without a network. Overriding this is how.
final legalConsentStoreProvider = Provider<LegalConsentStore>(
  (ref) => LegalRepository(ref.watch(supabaseClientProvider)),
);

/// When the signed-in user accepted [kLegalVersion], or null if they have not.
///
/// ═══ WHY THIS IS NOT PART OF THE SESSION ROW ═══
/// It would have been cheaper to add a column to `public.users` and let it ride along in the
/// select `AuthController._resolve()` already makes. It is separate because the acceptance is
/// evidence, not state: it belongs in an append-only table with a foreign key to the version
/// that was actually published, and a denormalised copy on `users` would be a second answer to
/// the same question that nothing keeps true.
///
/// The cost is one extra round trip on the way into the app, once, and only for a user who is
/// past the password and second-factor gates. The benefit is that the routing decision in
/// core/router/router.dart stays a pure function of [AuthPhase] — untouched by this work, so
/// its exhaustive every-phase-against-every-route matrix keeps meaning exactly what it meant.
///
/// AUTODISPOSE AND KEYED BY USER. Reading the user id from the session inside the build (rather
/// than as a family key) means signing out and back in as somebody else re-asks the question,
/// because [sessionProvider] changes and this rebuilds. Nothing awaits this provider's future
/// from the outside — the gate WATCHES it — which is what keeps riverpod 3 from throwing
/// UnmountedRefException across the await gap.
final legalConsentProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  final session = ref.watch(sessionProvider);
  // No session means no question to ask. The gate is only ever mounted behind a signed-in
  // route, so this is the moment between a sign-out and the router catching up, not a state a
  // person can sit in.
  if (session == null) return null;
  final store = ref.watch(legalConsentStoreProvider);
  return store.acceptedAt(userId: session.userId, version: kLegalVersion);
});
