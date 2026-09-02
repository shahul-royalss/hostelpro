library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// OPENING A RAZORPAY ORDER FOR THE SIGNED-IN RESIDENT'S OWN RENT.
///
/// ── THIS CLASS SENDS NO BODY, ON PURPOSE ─────────────────────────────────────────────────
///
/// [open] takes NO arguments. Not an amount, not a student id, not a period. That is not an
/// oversight and it is not a convenience — it is the whole security property of this path,
/// mirrored on the client so nobody can add a parameter here without noticing they are the
/// first person to do so. `razorpay-order` never reads its request body; every figure is
/// derived server-side from the caller's bearer token, and then derived a second time inside
/// `rz_open_intent`, which refuses the intent row if the two disagree.
///
/// The moment this method grows an `amount` parameter, the ₹1-order-for-a-₹9000-room attack is
/// back — not because the server would accept it, but because someone will eventually make the
/// server trust it to make the client compile.
///
/// ── ORDERS ARE REUSED, NOT MINTED PER TAP ────────────────────────────────────────────────
///
/// The function offers an existing unpaid order back for 15 minutes rather than creating a new
/// one, so a resident who opens the sheet, thinks better of it, and comes back does not litter
/// the Razorpay dashboard with dead orders. Calling [open] twice in a row is therefore cheap and
/// safe, which is what lets the UI retry without any bookkeeping of its own.
class CheckoutRepository {
  const CheckoutRepository(this.db);

  final SupabaseClient db;

  static const functionName = 'razorpay-order';

  /// The order for whatever this resident still owes this month.
  ///
  /// Throws like every other write in the app: an [AppFailure] a screen can show. A refusal here
  /// is genuinely safe to retry — no money has moved and no intent row survives a failure — so
  /// this uses [guard] rather than [guardWrite]. Opening an order is a read with a side effect
  /// the server itself makes idempotent.
  Future<CheckoutOrder> open() => guard(
        () async {
          final FunctionResponse response;
          try {
            // NO `body:`. See the class comment.
            response = await db.functions.invoke(functionName);
          } on FunctionException catch (error, stack) {
            Error.throwWithStackTrace(failureFrom(error), stack);
          } catch (error, stack) {
            Error.throwWithStackTrace(AppFailure.from(error), stack);
          }


          final envelope = response.data;
          if (envelope is! Map || envelope['data'] is! Map) {
            throw RowShapeError(functionName, '(body)', 'expected a JSON object envelope');
          }
          return CheckoutOrder.fromJson(
            (envelope['data'] as Map).cast<String, dynamic>(),
            source: functionName,
          );
        },
        deadline: dataDeadline,
      );

  /// PUBLIC so the mapping can be asserted without a live Supabase project — the 404-with-no-
  /// body branch in particular, which is the one that is easy to get wrong.
  ///
  /// Written here rather than shared with [ComplaintPhotoRepository.failureFrom] for the same
  /// reason that one is not shared: the statuses overlap, the SENTENCES do not. Every message
  /// below has to leave a resident certain about one thing above all — whether their money
  /// moved. "Could not be attached" is a fine thing to say about a photo and a terrible thing
  /// to say about a payment.
  static AppFailure failureFrom(FunctionException error) {
    final message = _messageFrom(error.details);

    if (error is FunctionsFetchException || error.status == 0) {
      return OfflineFailure(
        // Explicitly reassuring: this failure happened BEFORE any order existed, so there is
        // nothing outstanding and nothing to reconcile. A resident who fears a half-made
        // payment will otherwise refresh, retry, and pay twice.
        'Cannot reach Nivora, so the payment was not started. Nothing has been charged. '
        'Check your connection and try again.',
        technical: error.toString(),
      );
    }

    return switch (error.status) {
      401 => SignedOutFailure(
          message ?? 'Your session has ended. Sign in again to pay.',
          technical: error.toString(),
        ),
      403 when _isBillingRefusal(message) => ReadOnlyFailure(
          message ?? 'This hostel is read-only until the subscription is renewed.',
          technical: error.toString(),
        ),
      403 => AccessDeniedFailure(
          message ?? 'You are not allowed to do that.',
          technical: error.toString(),
        ),
      // ═══ A 404 WITH NO BODY MEANS THE FUNCTION IS NOT DEPLOYED ═══
      // Same branch, same reason, as the 404 in ComplaintPhotoRepository: the gateway answers
      // 404 with nothing in it when razorpay-order is absent from this project. Telling a
      // resident "you owe nothing" then would be a lie that costs them a late fee, so this
      // says what is actually true and points them at the desk.
      404 when message == null => NotFoundFailure(
          'Online payment is not available on this server yet. You can still pay your warden '
              'at the office.',
          technical: 'razorpay-order answered 404 with no body — the Edge Function is not '
              'deployed on this project. $error',
        ),
      404 => NotFoundFailure(message!, technical: error.toString()),
      // The function raises this when the resident owes nothing, or when the balance is under
      // Razorpay's minimum order. Both are ordinary answers rather than faults, and both are
      // already written for a person by the function itself.
      400 || 409 => InvalidInputFailure(
          message ?? 'There is nothing to pay right now.',
          technical: error.toString(),
        ),
      // 502/503 here is Razorpay refusing to mint the order. No order means no payment: safe.
      _ => ServerFailure(
          message ?? 'Payments are temporarily unavailable. Nothing has been charged.',
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
