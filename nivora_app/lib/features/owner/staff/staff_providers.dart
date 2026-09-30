library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/perf/session_keep_alive.dart';
import '../../../data/providers.dart';
import 'staff_models.dart';
import 'staff_repository.dart';

/// Wiring for the owner's staff screen. Hand-written, matching lib/data/providers.dart — no
/// codegen, nothing to regenerate.

final ownerStaffRepositoryProvider = Provider<OwnerStaffRepository>(
  (ref) => OwnerStaffRepository(ref.watch(supabaseClientProvider)),
);

/// The three writes, TYPED BY THE INTERFACE rather than by the class, so a test can stand in
/// for them without a network or a Supabase client. See [OwnerStaffWrites].
final ownerStaffWritesProvider = Provider<OwnerStaffWrites>(
  (ref) => ref.watch(ownerStaffRepositoryProvider),
);

/// Every manager and warden with access to one PG. public.owner_hostel_staff.
///
/// A warden with access to two of the owner's PGs is in BOTH PGs' lists, whichever one they
/// are working in right now. So a change to one person (a status, their PG access) can move
/// rows in several of these entries at once, and the writes invalidate the whole family
/// rather than the one PG on screen.
///
/// TAB-BACKING, SO SESSION-HELD — the lifetime policy at the top of lib/data/providers.dart.
/// This list is what the owner's More tab renders, and it is in the shell's warm-up list
/// (see OwnerSection in owner_tabs.dart), so it calls `holdForSession`: a revisit renders
/// instantly from the held roster, and a refresh updates it in place instead of blanking to a
/// skeleton. The hold cannot show one PG's staff under another's name even for a frame: the
/// family is keyed by hostelId, so a switch reads a different cache entry altogether — and
/// holdForSession drops everything on sign-out or a change of user, so a roster of contact
/// details never survives into the next login.
///
/// AN EMPTY LIST IS READ AS "NO STAFF YET". The function checks that the caller owns the PG
/// before it lists anybody, and the id it is asked about comes from the owner's own PG list,
/// so for every PG this screen can reach zero rows means nobody has been added. The empty
/// state is still phrased so that it stays true if that ever changes.
final ownerStaffProvider =
    FutureProvider.autoDispose.family<List<StaffMember>, String>((ref, hostelId) {
  holdForSession(ref);
  return ref.watch(ownerStaffRepositoryProvider).staff(hostelId);
});
