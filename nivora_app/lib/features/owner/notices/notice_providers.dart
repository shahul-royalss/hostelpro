/// Wiring for the owner's noticeboard.
///
/// THERE IS NO SECOND READ PROVIDER HERE, and that is deliberate. `noticesProvider` in
/// lib/data/providers.dart already pages `public.announcements` for a hostel, and it is the
/// provider the student's notices tab and the owner's activity feed both watch. Adding an
/// owner-only copy of the same query would mean posting a notice invalidates one cache and not
/// the other — the dashboard's feed showing a notice the noticeboard below it does not.
///
/// The owner's list and the resident's list are the SAME rows read by different callers; which
/// of them each caller gets is `announcements_select`'s decision, not a parameter.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../data/repositories/notice_repository.dart';

/// The two writes, TYPED BY THE INTERFACE rather than by the class, so a test can stand in for
/// them without a network or a Supabase client. See [NoticeWrites].
final noticeWritesProvider = Provider<NoticeWrites>(
  (ref) => ref.watch(noticeRepositoryProvider),
);
