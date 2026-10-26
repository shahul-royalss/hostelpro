library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay.dart';
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
              const SheetTitle(
                title: 'Raise a complaint',
                subtitle: 'Your warden and the owner see this. Other residents never do.',
              ),
              const SizedBox(height: Space.lg),

              const SectionHeader(title: 'Category', size: SectionHeaderSize.form),
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

              // Inline, under the fields it is about: a full-size failure state here would push
              // the form the resident was filling in off the sheet.
              if (_failure != null) ...[
                const SizedBox(height: Space.xs),
                ErrorNote(error: _failure!, compact: true),
              ],

              const SizedBox(height: Space.md),
              // The sheet's primary action, full-bleed and forest: this form's whole purpose is
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
                            // The spinner sits ON the button's fill, so it takes that button's own
                            // foreground rather than the theme's default accent — white on the
                            // forest in light.
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

/// One category, as the design's choice chip: the card fill with the control border when it is
/// not chosen, and the forest fill with a white label when it is.
///
/// A hand-built box rather than Material's [ChoiceChip], whose selected state is the scheme's
/// `secondaryContainer` and whose shape is the chip theme's — reaching the design's recipe
/// through `ChipThemeData` would change every other chip in the app. The selection is never
/// colour alone: the fill, the border and the label all change, and the semantics say
/// "selected".
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
    final dark = t.brightness == Brightness.dark;
    final enabled = onSelected != null;
    // Light: forest with white. Dark: the Mist with a forest label — the design's dark selected
    // chip — because forest on the dark ground is a hole, not a highlight.
    final fill = selected
        ? (dark ? ApnivaasColors.mist : ApnivaasColors.forest)
        : t.colorScheme.surface;
    final ink = selected
        ? (dark ? ApnivaasColors.forest : ApnivaasColors.headerTitle)
        : t.colorScheme.onSurface;
    final border = selected
        ? fill
        : (dark ? t.colorScheme.outline : ApnivaasColors.controlBorder);

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : Dim.readOnly,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.rControl,
            side: BorderSide(color: border, width: Strokes.control),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onSelected,
            child: ConstrainedBox(
              // 48 high: a chip is a tap target before it is a decoration.
              constraints: const BoxConstraints(minHeight: Space.huge),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(complaintIcon(category), size: IconSize.md, color: ink),
                    const SizedBox(width: Space.xs),
                    Flexible(
                      child: Text(
                        category.label,
                        style: t.textTheme.titleSmall
                            ?.copyWith(color: ink, fontFeatures: const []),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
