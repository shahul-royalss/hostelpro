library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import 'widgets/common.dart';
import 'widgets/complaint.dart';

/// Raise a complaint.
///
/// THE LIMITS BELOW ARE THE WEB APP'S, TO THE CHARACTER. `lib/validators/student.ts` in the
/// Next.js app requires a category, a title of 3–120 characters and a description of at most
/// 2000, with those exact messages. The `complaints` table itself constrains none of it — so if
/// this form disagreed, the same resident would be told different things depending on which
/// client they happened to open, and a title accepted on the phone would be rejected on the
/// web. One product, one rule.
///
/// AND THE LIMITS THAT ARE NOT HERE. Whether the insert is ALLOWED at all is decided by the
/// `complaints_insert` policy: `student_id = app.current_student_id()`, `hostel_id =
/// app.user_hostel_id()`, and the hostel still writable. Passing someone else's ids fails at
/// the server with 42501 rather than succeeding, and an expired subscription fails the same way
/// with a different message. This form does not pre-empt either; it shows what the server said.
///
/// NO PHOTO FIELD YET. `complaints.photo_url` holds a Supabase Storage key, and this app has no
/// upload path in its data layer. A picker that produced nothing would be worse than its
/// absence, so the column is left null and the field is left out.
Future<Complaint?> showRaiseComplaintSheet(BuildContext context, {required Student me}) {
  return showGlassSheet<Complaint>(
    context: context,
    builder: (_) => _RaiseComplaintSheet(me: me),
  );
}

class _RaiseComplaintSheet extends ConsumerStatefulWidget {
  const _RaiseComplaintSheet({required this.me});
  final Student me;

  @override
  ConsumerState<_RaiseComplaintSheet> createState() => _RaiseComplaintSheetState();
}

class _RaiseComplaintSheetState extends ConsumerState<_RaiseComplaintSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();

  ComplaintCategory? _category;
  bool _sending = false;
  Object? _failure;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // The category is a chip row, not a form field, so it is validated by hand.
    if (_category == null) {
      setState(() => _failure = const InvalidInputFailure('Pick a category.'));
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;

    final navigator = Navigator.of(context);
    setState(() {
      _sending = true;
      _failure = null;
    });

    try {
      final description = _description.text.trim();
      final complaint = await ref.read(complaintRepositoryProvider).create(
            hostelId: widget.me.hostelId,
            studentId: widget.me.id,
            category: _category!,
            title: _title.text.trim(),
            description: description.isEmpty ? null : description,
          );
      // The list is a cached page; without this the new complaint would not appear until the
      // resident pulled to refresh, which reads as the app having lost it.
      ref.invalidate(complaintsProvider);
      ref.invalidate(unreadCountProvider);
      if (!mounted) return;
      navigator.pop(complaint);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failure = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Raise a complaint', style: t.textTheme.titleLarge),
              const SizedBox(height: Space.xxs),
              Text(
                'Your warden and the owner see this. Other residents never do.',
                style: t.textTheme.bodySmall,
              ),
              const SizedBox(height: Space.md),

              Text('CATEGORY', style: t.textTheme.labelSmall),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final category in ComplaintCategory.values)
                    ChoiceChip(
                      selected: _category == category,
                      onSelected: _sending
                          ? null
                          : (_) => setState(() {
                                _category = category;
                                _failure = null;
                              }),
                      avatar: Icon(complaintIcon(category), size: IconSize.sm),
                      label: Text(category.label),
                      shape: const RoundedRectangleBorder(borderRadius: Radii.rControl),
                    ),
                ],
              ),
              const SizedBox(height: Space.md),

              TextFormField(
                controller: _title,
                enabled: !_sending,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Bathroom tap leaking on 1st floor',
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.length < 3) return 'Give your complaint a short title';
                  if (text.length > 120) return 'Keep the title under 120 characters';
                  return null;
                },
              ),
              const SizedBox(height: Space.xs),

              TextFormField(
                controller: _description,
                enabled: !_sending,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What is happening? (optional)',
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if ((value ?? '').trim().length > 2000) {
                    return 'Keep the description under 2000 characters';
                  }
                  return null;
                },
              ),

              if (_failure != null) ...[
                const SizedBox(height: Space.xs),
                ErrorNote(error: _failure!),
              ],

              const SizedBox(height: Space.md),
              FilledButton(
                onPressed: _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send to my warden'),
              ),
              const SizedBox(height: Space.xs),
              TextButton(
                onPressed: _sending ? null : () => Navigator.of(context).maybePop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
