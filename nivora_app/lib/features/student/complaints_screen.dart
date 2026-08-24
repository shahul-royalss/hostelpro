library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import 'complaint_detail_sheet.dart';
import 'raise_complaint_sheet.dart';
import 'widgets/common.dart';
import 'widgets/complaint.dart';
import 'widgets/paged_list.dart';

/// The resident's own complaints: raise one, and watch what happens to it.
///
/// READS: public.complaints, through `complaintsProvider` → `ComplaintRepository.page`.
/// WRITES: an insert into public.complaints, through the raise sheet.
///
/// THE SAME QUERY SERVES THE WARDEN'S QUEUE. It is not two queries because it is not two
/// questions asked of the database: the `complaints` select policy narrows a student to
/// `student_id = app.current_student_id()` and a warden to their hostel. Adding an
/// `if (isStudent)` branch here would duplicate a control that has already run, and would drift
/// from it the first time either side changed.
class StudentComplaintsScreen extends StatelessWidget {
  const StudentComplaintsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResidentBuilder(builder: (context, ref, me) => _Complaints(me: me));
  }
}

class _Complaints extends ConsumerWidget {
  const _Complaints({required this.me});
  final Student me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ComplaintQuery(hostelId: me.hostelId);
    final provider = complaintsProvider(query);

    return StudentPagedList<Complaint>(
      value: ref.watch(provider),
      header: _RaiseButton(me: me),
      onRefresh: () async {
        ref.invalidate(provider);
        try {
          await ref.read(provider.future);
        } catch (_) {
          // Drawn by the section itself; escaping here would hang the refresh spinner.
        }
      },
      onLoadMore: () => ref.read(provider.notifier).loadMore(),
      empty: const EmptyNote(
        icon: Icons.check_circle_outline_rounded,
        title: 'You have not raised anything',
        message: 'If something in the hostel is not working — food, cleaning, Wi-Fi, a repair — '
            'tell your warden here and you can follow what happens to it.',
      ),
      itemBuilder: (context, complaint) => ComplaintTile(
        complaint: complaint,
        onTap: () => showComplaintDetailSheet(context, complaint: complaint),
      ),
    );
  }
}

class _RaiseButton extends StatelessWidget {
  const _RaiseButton({required this.me});
  final Student me;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: FilledButton.icon(
        onPressed: () => raiseComplaint(context, me),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Raise a complaint'),
      ),
    );
  }
}

/// Opens the raise sheet and confirms what happened.
///
/// Shared with the home screen's quick action, so the confirmation a resident sees is the same
/// wherever they started from. The sheet itself invalidates the cached list on success — that
/// belongs next to the write, not next to each button that triggers it.
Future<void> raiseComplaint(BuildContext context, Student me) async {
  final messenger = ScaffoldMessenger.of(context);
  final complaint = await showRaiseComplaintSheet(context, me: me);
  if (complaint == null) return;
  messenger.showSnackBar(
    SnackBar(content: Text('Sent. Your warden can see "${complaint.title}".')),
  );
}
