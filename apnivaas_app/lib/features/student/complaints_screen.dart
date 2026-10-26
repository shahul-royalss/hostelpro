library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay.dart';
import '../common/refresh.dart';
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
      // BOUNDED. The bare `await ref.read(provider.future)` had no deadline, and riverpod 3
      // retries a failed provider ten times behind a future it does not complete — so a
      // resident on a hostel Wi-Fi that had stopped answering held this spinner for over two
      // minutes. See features/common/refresh.dart.
      onRefresh: () {
        ref.invalidate(provider);
        return settleRefresh(context, () => ref.read(provider.future));
      },
      onLoadMore: () => ref.read(provider.notifier).loadMore(),
      // The list has no filter, so empty always means "this resident has raised nothing" and
      // never "no match" — which is why it can say so plainly, in one line under the art. The
      // banner above already explains what this screen is for, and already wears the complaint
      // art; nothing to fix is good news, so this takes the kit's good-news trophy. Centring is
      // done by the list, not here.
      empty: const EmptyNote(
        clay: ClayIcons.success,
        icon: Icons.report_problem_outlined,
        title: 'No complaints raised yet',
      ),
      itemBuilder: (context, complaint) => ComplaintTile(
        complaint: complaint,
        onTap: () => showComplaintDetailSheet(context, complaint: complaint),
      ),
    );
  }
}

/// The way in, at the head of the list: a Mist banner with the complaint art, one line on who
/// will read it, and the screen's one filled action.
///
/// The action is the banner's pill while its label fits there. From 1.6x text the pill would
/// cut "Raise a complaint" short, so the action moves under the banner as a full-width button
/// whose label can wrap.
class _RaiseButton extends StatelessWidget {
  const _RaiseButton({required this.me});
  final Student me;

  @override
  Widget build(BuildContext context) {
    final big = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    void raise() => raiseComplaint(context, me);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoBanner(
            title: 'Something not working?',
            message: 'Tell your warden. Other residents never see it.',
            icon: ClayIcons.complaint,
            action: big
                ? null
                : PillButton(
                    label: 'Raise a complaint',
                    icon: Icons.add_rounded,
                    filled: true,
                    onPressed: raise,
                  ),
          ),
          if (big) ...[
            const SizedBox(height: Space.sm),
            FilledButton.icon(
              onPressed: raise,
              icon: const Icon(Icons.add_rounded, size: IconSize.md),
              label: const Text('Raise a complaint'),
            ),
          ],
        ],
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
