/// DEMO REQUESTS, for the Super Admin (docs/self-signup-api.md §4): owners who booked a
/// walkthrough from sign-up or from More, and the status the platform team keeps on each.
///
/// `sa_demo_requests` and `sa_update_demo_request` refuse anyone but the Super Admin ("Not
/// allowed."), so this screen holds no authority of its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/people.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../shared/clay/clay.dart';

Duration? _noRetry(int _, Object _) => null;

final saDemoRequestsProvider = FutureProvider.autoDispose<List<DemoRequestRow>>(
  (ref) => ref.watch(peopleApiProvider).demoRequests(),
  retry: _noRetry,
);

final _slot = DateFormat('EEE d MMM, h a');

String _sentence(Object e) =>
    e is SignupFailure ? e.message : 'Something went wrong. Please try again.';

StatusTone _tone(String status) => switch (status) {
      'confirmed' => StatusTone.info,
      'done' => StatusTone.success,
      'no_show' || 'cancelled' => StatusTone.neutral,
      _ => StatusTone.warning,
    };

/// The Overview's way in.
class SaDemoRequestsEntry extends StatelessWidget {
  const SaDemoRequestsEntry({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        child: ListRowCard(
          icon: ClayIcons.calendar,
          title: 'Demo requests',
          subtitle: 'Owners who booked a walkthrough',
          onTap: () => Navigator.of(context).push(SaDemoRequestsScreen.route()),
        ),
      );
}

class SaDemoRequestsScreen extends ConsumerWidget {
  const SaDemoRequestsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const SaDemoRequestsScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(saDemoRequestsProvider);
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(
            title: 'Demo requests',
            subtitle: 'Newest first',
            leading: HeaderBackButton(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(saDemoRequestsProvider);
                try {
                  await ref.read(saDemoRequestsProvider.future).timeout(const Duration(seconds: 20));
                } catch (_) {}
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md, Space.huge),
                children: [
                  switch (rows) {
                    AsyncData(:final value) when value.isEmpty => const EmptyState(
                        icon: ClayIcons.calendar,
                        title: 'No demo requests',
                        body: 'Owners who book a walkthrough appear here.',
                      ),
                    AsyncData(:final value) => ListGroup(
                        children: [
                          for (final r in value)
                            ListRow(
                              icon: ClayIcons.calendar,
                              title: '${r.pgName ?? 'PG'} · ${r.city ?? ''}',
                              subtitle: [
                                if (r.slotStart != null) _slot.format(r.slotStart!),
                                ?r.name,
                                ?r.phone,
                                if (r.bedBand != null) '${r.bedBand} beds',
                              ].join(' · '),
                              trailing: StatusChip(
                                label: demoStatuses[r.status] ?? r.status,
                                tone: _tone(r.status),
                              ),
                              onTap: () => _edit(context, ref, r),
                            ),
                        ],
                      ),
                    AsyncError(:final error) => EmptyState.error(
                        message: _sentence(error),
                        onRetry: () => ref.invalidate(saDemoRequestsProvider),
                      ),
                    _ => const ListSkeleton(rows: 4, semanticLabel: 'Loading demo requests'),
                  },
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, DemoRequestRow r) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showApnivaasSheet<({String status, String note})>(
      context: context,
      title: r.pgName ?? 'Demo request',
      subtitle: [
        if (r.ownerName != null) r.ownerName!,
        if (r.ownerEmail != null) r.ownerEmail!,
      ].join(' · '),
      builder: (_) => DemoStatusForm(status: r.status, note: r.note),
    );
    if (result == null) return;
    try {
      await ref.read(peopleApiProvider).updateDemoRequest(r.id, status: result.status, note: result.note);
      ref.invalidate(saDemoRequestsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Saved'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_sentence(e)), behavior: SnackBarBehavior.floating));
    }
  }
}

/// The demo's status chips and a note; pops `(status, note)`. Shared with the sign-ups list.
class DemoStatusForm extends StatefulWidget {
  const DemoStatusForm({super.key, required this.status, this.note});
  final String status;
  final String? note;

  @override
  State<DemoStatusForm> createState() => _DemoStatusFormState();
}

class _DemoStatusFormState extends State<DemoStatusForm> {
  late String _status = widget.status;
  late final _note = TextEditingController(text: widget.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final e in demoStatuses.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _status == e.key,
                      onSelected: (_) => setState(() => _status = e.key),
                    ),
                ],
              ),
              const SizedBox(height: Space.sm),
              TextField(
                controller: _note,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: Space.sm),
              FilledButton(
                onPressed: () => Navigator.of(context).pop((status: _status, note: _note.text)),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
}
