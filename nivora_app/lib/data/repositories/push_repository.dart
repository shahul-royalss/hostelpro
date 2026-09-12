library;

// guardWrite is a top-level function in models/failure.dart, not a method on Repository.
import '../models/models.dart';
import 'repository.dart';

/// WHICH PHONE TO RING.
///
/// TABLE: public.push_devices, through two SECURITY DEFINER RPCs.
///
/// ── WHY RPCs AND NOT AN UPSERT ───────────────────────────────────────────────────────────
///
/// public.push_devices has a select policy and a delete policy for your own rows, and
/// deliberately NO insert or update policy. A token has to be able to MOVE between accounts —
/// one phone, two people, one after the other, which is exactly what a warden's handset does
/// when the shift changes — and an insert policy that allowed that would be an insert policy
/// that allowed writing somebody else's row. register_push_device() does the move itself, under
/// `auth.uid()`, and is the only thing that can.
///
/// ── FAILURE HERE IS NEVER FATAL ──────────────────────────────────────────────────────────
///
/// Both calls are made in the background after sign-in. A phone that could not register is a
/// phone that does not buzz; it is not a phone that cannot run the app, and nothing in the UI
/// waits on either of these. The caller swallows what these throw — see core/notify/.
final class PushRepository extends Repository {
  const PushRepository(super.db);

  /// Claim this device for the signed-in account.
  ///
  /// [platform] is 'android' or 'ios'; the RPC refuses anything else, and the column has a
  /// CHECK saying the same thing.
  Future<void> registerDevice({required String token, required String platform}) => guardWrite(
        () async {
          await db.rpc('register_push_device', params: {
            'p_token': token,
            'p_platform': platform,
          });
        },
        unresolved: 'Nivora could not confirm this phone for notifications. It will try again '
            'the next time you open the app.',
      );

  /// Give it up again — called on sign-out, so the next person to use this handset does not
  /// receive the last person's rent reminders.
  Future<void> unregisterDevice(String token) => guardWrite(
        () async {
          await db.rpc('unregister_push_device', params: {'p_token': token});
        },
        unresolved: 'This phone may still be registered for notifications.',
      );
}
