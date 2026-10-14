library;

import '../../data/models/models.dart';
import '../../data/repositories/repository.dart';
import 'legal_documents.dart';

/// Reading and writing the record of who agreed to the legal documents.
///
/// TABLES: public.legal_acceptances (read). RPC: public.accept_legal_terms (write).
///
/// ═══ WHY THE WRITE IS AN RPC AND NOT AN INSERT ═══
/// `legal_acceptances` has a SELECT policy and NO insert, update or delete policy at all — not
/// even for the person the row is about. That is the whole design: if the subject of a consent
/// record could write it, they could choose its timestamp, name a surface they never used, or
/// delete it and re-agree later with a fresh date. Every one of those destroys the only thing
/// the record is for. The RPC runs as definer, stamps `accepted_at` from the server clock, and
/// refuses a version that was never published.
///
/// See db/migrations/2026-09-02-legal-consent.sql.
///
/// An interface, like [NoticeWrites], because [ConsentGate] is the one screen every user must
/// pass and its interesting states — offline, refused, a dead session, a version the server has
/// never heard of — are exactly what belongs in `flutter test` rather than in a manual pass on
/// a phone.
abstract interface class LegalConsentStore {
  /// When this user accepted [version], or null if they have not.
  Future<DateTime?> acceptedAt({required String userId, String version});

  /// Record acceptance. Returns the server's timestamp for it.
  Future<DateTime> accept({required String version, required String surface, String? appVersion});
}

final class LegalRepository extends Repository implements LegalConsentStore {
  const LegalRepository(super.db);

  @override
  Future<DateTime?> acceptedAt({
    required String userId,
    String version = kLegalVersion,
  }) =>
      guard(() async {
        // THE NULL FROM THIS READ DECIDES WHETHER A GATE APPEARS, so it has to mean one thing.
        //
        // RLS on legal_acceptances is `user_id = auth.uid()`, which returns NO ROWS to an
        // anonymous caller — identical on the wire to a signed-in user who has genuinely never
        // agreed. Without this line a session whose token had died would be shown the consent
        // screen, would tap Agree, and would be refused by the RPC with a message about not
        // being signed in: the app would have asked for something it then refused to accept.
        // With it, a dead credential is a SignedOutFailure and the gate offers the one thing
        // that helps, which is signing in again.
        requireLiveSession('legal_acceptances.acceptedAt');
        final row = await db
            .from('legal_acceptances')
            .select('accepted_at')
            .eq('user_id', userId)
            .eq('version', version)
            .maybeSingle();
        if (row == null) return null;
        return DateTime.tryParse((row['accepted_at'] as String?) ?? '');
      });

  @override
  Future<DateTime> accept({
    required String version,
    required String surface,
    String? appVersion,
  }) =>
      // `guard`, NOT `guardWrite`, and this is the case its documentation names explicitly: an
      // RPC that no-ops the second time. accept_legal_terms() is idempotent on
      // (user_id, version) — a repeat returns the ORIGINAL timestamp and writes no second audit
      // row — so a timeout here is safe to retry and must not be reported as "we cannot tell
      // whether that worked". Verified against the live project: two calls, one row, one audit
      // entry, same timestamp.
      guard(() async {
        requireLiveSession('accept_legal_terms');
        final result = await db.rpc('accept_legal_terms', params: {
          'p_version': version,
          'p_surface': surface,
          'p_app_version': appVersion,
        });
        // The function returns timestamptz, which PostgREST sends as an ISO-8601 string. A
        // value this build cannot parse is not a reason to tell somebody their acceptance
        // failed — the row is written either way — so it degrades to "now" rather than
        // throwing, and the server's own copy remains the record that counts.
        final parsed = result is String ? DateTime.tryParse(result) : null;
        return parsed ?? DateTime.now();
      });
}
