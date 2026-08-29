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

/// The two writes, TYPED BY THE INTERFACE rather than by the class, so a test can stand in for
/// them without a network or a Supabase client. See [OwnerStaffWrites].
final ownerStaffWritesProvider = Provider<OwnerStaffWrites>(
  (ref) => ref.watch(ownerStaffRepositoryProvider),
);

/// Every manager and warden of one PG. public.users, under RLS.
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
/// AN EMPTY LIST IS AMBIGUOUS AND THE SCREEN SAYS SO. `users_select` returns rows to an owner
/// only for a hostel `app.can_read_hostel()` admits, so zero rows means either "this PG has no
/// staff yet" or "these are not your rows". The first is the overwhelmingly likely reading and
/// the screen leads with it, but the empty state is phrased so it is also true of the second.
final ownerStaffProvider =
    FutureProvider.autoDispose.family<List<StaffMember>, String>((ref, hostelId) {
  holdForSession(ref);
  return ref.watch(ownerStaffRepositoryProvider).staff(hostelId);
});
