library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// autoDispose and keyed by hostel: an owner switching between two PGs must not see the first
/// one's staff under the second one's name for the length of a frame, and leaving the screen
/// should not hold a list of people's contact details in memory.
///
/// AN EMPTY LIST IS AMBIGUOUS AND THE SCREEN SAYS SO. `users_select` returns rows to an owner
/// only for a hostel `app.can_read_hostel()` admits, so zero rows means either "this PG has no
/// staff yet" or "these are not your rows". The first is the overwhelmingly likely reading and
/// the screen leads with it, but the empty state is phrased so it is also true of the second.
final ownerStaffProvider =
    FutureProvider.autoDispose.family<List<StaffMember>, String>((ref, hostelId) {
  return ref.watch(ownerStaffRepositoryProvider).staff(hostelId);
});
