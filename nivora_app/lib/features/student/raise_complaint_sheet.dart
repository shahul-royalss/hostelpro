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

              const CapsLabel('Category'),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final category in ComplaintCategory.values)
                    _CategoryChip(
                      category: category,
                      selected: _category == category,
                      onSelected: _sending
                          ? null
                          : () => setState(() {
                                _category = category;
                                _failure = null;
                              }),
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
              // The sheet's primary action, full-bleed and cream: this form's whole purpose is
              // the one button at the bottom of it. See the note on the Close button in
              // complaint_detail_sheet.dart for why the width has to be said out loud.
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: _sending
                      ? SizedBox(
                          width: IconSize.md,
                          height: IconSize.md,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            // The spinner sits ON the cream fill, so it takes that button's own
                            // foreground rather than the theme's default accent. `onPrimary` and
                            // not `onPrimaryContainer`: theme.dart wires the filled button to
                            // the CREAM `primaryContainer` in the dark theme and to `primary` in
                            // the light one, and `onPrimary` is the value that is right for both
                            // (near-black on cream, white on gold).
                            color: t.colorScheme.onPrimary,
                          ),
                        )
                      : const Text('Send to my warden'),
                ),
              ),
              const SizedBox(height: Space.xs),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _sending ? null : () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One category, as the design draws a chip: a 10% wash of the accent behind a full-strength
/// hairline, with the glyph and the label in the accent — and the hairline surface with the
/// ordinary control border when it is not chosen.
///
/// A hand-built box rather than Material's [ChoiceChip], which paints its selected state in
/// `secondaryContainer`. That is #25231C in this palette — a dark olive that reads as a
/// disabled chip rather than a chosen one — and there is no way to reach the design's recipe
/// through `ChipThemeData` without also changing every other chip in the app from a file this
/// agent does not own. The two alphas come from [NivoraSemantics], where the tightest contrast
/// case in the product is measured, so a chosen category is exactly as loud as a status pill.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onSelected,
  });

  final ComplaintCategory category;
  final bool selected;

  /// Null while the form is submitting. The chip greys out rather than disappearing, so the
  /// resident can still see what they picked.
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final enabled = onSelected != null;
    final accent = selected ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected ? tones.chipFill(t.colorScheme.primary) : Colors.transparent,
        borderRadius: Radii.rControl,
        child: InkWell(
          borderRadius: Radii.rControl,
          onTap: onSelected,
          child: Opacity(
            opacity: enabled ? 1 : Dim.readOnly,
            child: Container(
              // 44 high with 12/8 padding: a chip is a tap target before it is a decoration.
              constraints: const BoxConstraints(minHeight: Space.xxl + Space.sm),
              padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
              decoration: BoxDecoration(
                borderRadius: Radii.rControl,
                border: Border.all(
                  color: selected
                      ? tones.chipBorder(t.colorScheme.primary)
                      : t.colorScheme.outline,
                  width: Strokes.hairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(complaintIcon(category), size: IconSize.sm, color: accent),
                  const SizedBox(width: Space.xs),
                  Text(
                    category.label,
                    style: t.textTheme.labelLarge?.copyWith(color: accent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
