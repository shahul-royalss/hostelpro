library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../capture.dart';
import '../models/models.dart';

/// The complaint photo, both ways: the bytes going up, and the URL that shows them coming back.
///
/// ═══ WHY THIS IS NOT `db.storage.from('complaint-photos')` ═══
/// `complaint-photos` is a PRIVATE bucket and `storage.objects` is default-deny for anon and
/// authenticated — db/rls-policies.sql declares no storage policies at all, deliberately. The
/// phone holds the anon key and an ordinary user session, and storage accepts neither for a
/// read or a write. A direct `uploadBinary` here would 403, and a direct `createSignedUrl`
/// would 403, every time, for every role. So the bytes go to an Edge Function that holds the
/// service-role key, and the function decides.
///
/// ═══ WHY `complaints.photo_url` CANNOT JUST BE RENDERED ═══
/// It is a storage KEY — `<hostelId>/complaints/<uuid>.jpg` — not a URL. Handing it to
/// `Image.network` produces a broken-image icon, which is exactly what the warden's sheet said
/// out loud for months ("Open it from the web console"). The URL has to be minted, per viewer,
/// per look, and it expires.
///
/// ═══ THE AUTHORISATION IS NOT HERE ═══
/// [signedUrl] sends a complaint id, not a path. The function re-reads that complaint with the
/// caller's own JWT, so `complaints_select` — owner and warden of the hostel, or the resident
/// who raised it — is what decides, and the hostel prefix the object must sit under comes off
/// the row rather than off this request. Nothing this class sends can widen what its caller may
/// see; a student who asks for another hostel's complaint gets a 404 with the same sentence a
/// deleted complaint gets.
///
/// ═══ NAMED LIKE A HELPER, NOT LIKE A REPOSITORY ═══
/// It does not extend [Repository] because it never touches PostgREST and returns no model. It
/// is the other half of [ComplaintRepository]'s boundary, the way `ReceiptExporter` sits beside
/// the payment repository — one class knows the rows, one knows the bytes.
final class ComplaintPhotos {
  const ComplaintPhotos(this.db);

  /// The anon-key client. Its only job here is to attach the caller's access token; the
  /// function verifies that token with GoTrue before it believes anything.
  final SupabaseClient db;

  static const functionName = 'complaint-photo';

  /// How long the phone waits for an upload before giving up on the ANSWER.
  ///
  /// Deliberately longer than the 12s [dataDeadline] every read gets. A 300 KB body on the 3G
  /// a stairwell offers is a genuinely slow request, and the whole point of compressing on the
  /// device was to make it survivable rather than instant. Giving up at 12s would turn an
  /// ordinary upload into a failure the resident could do nothing about but retry — which
  /// costs another 300 KB.
  static const uploadDeadline = Duration(seconds: 45);

  /// Send one compressed image and get back the storage KEY to persist on the complaint.
  ///
  /// ═══ GUARD, NOT guardWrite, AND THE REASON IS THE KEY ═══
  /// A repeat of this call does not double anything the user can see. The function invents a
  /// fresh uuid for every object, so a retry after a timeout produces a SECOND object and a
  /// second key — and the first key was never persisted anywhere, so nothing points at it and
  /// nothing shows it twice. The orphan costs bytes in a private bucket, not correctness, and
  /// [discard] is how the sheet cleans it up when it knows about it. The rule in guardWrite's
  /// doc comment ("writes the server makes idempotent … say so at the call site") is what this
  /// paragraph is.
  Future<String> upload(CapturedDocument photo) => guard(
        () async {
          // Checked here as well as at the server so a resident on a bad connection is told
          // before the bytes go up rather than after. 1600px at quality 70 lands far under this
          // — a file over it is a picked gallery original, not a capture.
          if (photo.isTooLarge) {
            throw InvalidInputFailure(
              'That photo is ${photo.sizeLabel}. Pick a smaller one, or take a new photo.',
              technical: 'complaint photo ${photo.sizeBytes} B exceeds '
                  '${CapturedDocument.maxBytes} B before base64',
            );
          }
          final data = await _invoke({
            'action': 'upload',
            'photoBase64': photo.toBase64(),
          });
          final path = data['path'];
          if (path is! String || path.isEmpty) {
            throw RowShapeError(functionName, 'path', 'the function stored no key for the photo');
          }
          return path;
        },
        deadline: uploadDeadline,
      );

  /// A short-lived URL for the photo on one complaint.
  ///
  /// Returns null when this complaint has no photo — that is an ordinary answer, not a failure,
  /// and the screens draw nothing for it. Every other refusal throws, because "you may not see
  /// this" and "there is nothing to see" are different sentences and a screen that draws the
  /// empty state for both is lying to one of them.
  Future<Uri?> signedUrl(String complaintId) => guard(() async {
        final Map<String, dynamic> data;
        try {
          data = await _invoke({'action': 'sign', 'complaintId': complaintId});
        } on NotFoundFailure catch (error) {
          // The function distinguishes these two in its own message; the app has to, because
          // one of them is the common case and must be silent.
          if (error.message.startsWith('No photo')) return null;
          rethrow;
        }
        final url = data['url'];
        if (url is! String || url.isEmpty) {
          throw RowShapeError(functionName, 'url', 'the function signed nothing');
        }
        return Uri.parse(url);
      });

  /// Throw away a photo that was uploaded for a complaint the server then refused to create.
  ///
  /// BEST EFFORT, AND IT NEVER THROWS. It runs on the failure path of raising a complaint,
  /// where the resident is already being shown why their complaint did not go through. A
  /// second error on top of that one — about a file they never knew existed — would replace
  /// the sentence that matters with one they cannot act on. A photo that survives this is an
  /// orphan in a private bucket costing bytes; that is the cheaper mistake.
  Future<void> discard(String path) async {
    try {
      await _invoke({'action': 'discard', 'path': path}).timeout(dataDeadline);
    } catch (error) {
      // debugPrint is stripped in release, so this cannot reach a production device log.
      debugPrint('could not discard orphan complaint photo: ${error.runtimeType} $error');
    }
  }

  /// One POST, one envelope, one failure vocabulary.
  ///
  /// The functions all answer `{ ok, data, error }` (supabase/functions/_shared/http.ts), and
  /// supabase_flutter raises [FunctionException] for any non-2xx with the parsed body in
  /// `details`. Everything below turns that into the sealed [AppFailure] the rest of the app
  /// switches on, so a screen never has to know an Edge Function was involved.
  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final FunctionResponse response;
    try {
      response = await db.functions.invoke(functionName, body: body);
    } on FunctionException catch (error, stack) {
      Error.throwWithStackTrace(_failureFrom(error), stack);
    }
    final envelope = response.data;
    if (envelope is! Map) {
      throw RowShapeError(functionName, '(body)', 'expected a JSON object envelope');
    }
    final data = envelope['data'];
    if (data is! Map) {
      throw RowShapeError(functionName, 'data', 'the function answered with no data — check its logs');
    }
    return data.cast<String, dynamic>();
  }

  /// The status-to-sentence mapping for this endpoint.
  ///
  /// Written here rather than shared with `WardenRepository.failureFrom` and
  /// `staffFailureFrom` because those two are about creating a LOGIN and their sentences say
  /// so ("the resident was NOT registered", "check the roster"). The statuses overlap; the
  /// words a person reads do not, and a shared function would have to take every one of them
  /// as a parameter, which is the same code with more indirection.
  ///
  /// PUBLIC so the mapping can be asserted in a test without a live Supabase project — the
  /// 404-with-no-body branch in particular, which is the one that is easy to get wrong.
  static AppFailure failureFrom(FunctionException error) => _failureFrom(error);

  static AppFailure _failureFrom(FunctionException error) {
    final message = _messageFrom(error.details);

    if (error is FunctionsFetchException || error.status == 0) {
      return OfflineFailure(
        'Cannot reach Nivora, so the photo could not be attached. Check your connection.',
        technical: error.toString(),
      );
    }

    return switch (error.status) {
      401 => SignedOutFailure(
          message ?? 'Your session has ended. Sign in again to continue.',
          technical: error.toString(),
        ),
      // The lapsed-subscription conversation belongs to the owner, not to the resident holding
      // the phone, and [ReadOnlyFailure] is the type every screen in this app already renders
      // that way.
      403 when _isBillingRefusal(message) => ReadOnlyFailure(
          message ?? 'This hostel is read-only until the subscription is renewed.',
          technical: error.toString(),
        ),
      403 => AccessDeniedFailure(
          message ?? 'You are not allowed to do that.',
          technical: error.toString(),
        ),
      // ═══ A 404 WITH NO BODY IS NOT A MISSING PHOTO ═══
      // The function ran and said "no photo" / "not visible" in its own envelope — that is
      // [message]. OR the request never reached a function at all because complaint-photo is
      // not deployed on this project, and the gateway answers 404 with nothing in it. Telling
      // a resident their photo is not attached, when NO photo will ever attach on this server,
      // sends them to retry forever. Same branch, for the same reason, as the 404 in
      // WardenRepository.failureFrom.
      404 when message == null => NotFoundFailure(
          'Photos are not available on this server yet. You can still send the complaint '
              'without one.',
          technical: 'complaint-photo answered 404 with no body — the Edge Function is not '
              'deployed on this project. $error',
        ),
      404 => NotFoundFailure(message!, technical: error.toString()),
      409 => ConflictFailure(
          message ?? 'That photo is already attached to a complaint.',
          technical: error.toString(),
        ),
      413 => InvalidInputFailure(
          message ?? 'That photo is too large. Take a new one and try again.',
          technical: error.toString(),
        ),
      400 => InvalidInputFailure(
          message ?? 'That photo could not be read. Pick it again.',
          technical: error.toString(),
        ),
      // 429 and 503 are both "not now" and both worth retrying — the limiter on this endpoint
      // fails closed, so an unreachable limiter refuses rather than waving the upload through.
      429 || 503 => ServerFailure(
          message ?? 'Too many photos just now. Wait a moment and try again.',
          technical: error.toString(),
        ),
      _ => ServerFailure(
          message ?? 'Nivora could not attach that photo. You can send the complaint without '
              'one.',
          technical: error.toString(),
        ),
    };
  }

  static bool _isBillingRefusal(String? message) {
    if (message == null) return false;
    final text = message.toLowerCase();
    return text.contains('subscription') || text.contains('read-only') || text.contains('suspended');
  }

  /// The function's own `{ ok: false, error: "..." }` body, when there is one.
  static String? _messageFrom(Object? details) {
    if (details is Map) {
      final error = details['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }
    return null;
  }
}
