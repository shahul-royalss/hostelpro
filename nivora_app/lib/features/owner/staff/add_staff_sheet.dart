library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';
import '../widgets/states.dart';
import 'staff_credentials_dialog.dart';
import 'staff_models.dart';
import 'staff_providers.dart';

/// Create a manager or warden login, from the phone.
///
/// ── WHAT THIS SHEET DECIDES, AND WHAT IT DOES NOT ────────────────────────────────────────
///
/// It decides what to DRAW. Which roles have a free slot, which field to put a message under,
/// whether Create is tappable. None of that is a permission.
///
/// supabase/functions/owner-create-staff decides everything else, and re-checks all of it: that
/// the caller's `public.users.role` really is `owner` (not what the JWT's app_metadata claims,
/// and certainly not what this app believes), that `hostels.owner_user_id` really is them, that
/// the hostel is not suspended and its subscription has not lapsed, that the rate limiter still
/// has an allowance, and that §4.3 leaves the role free. Deleting every check in this file would
/// change the error messages and nothing else.
///
/// NO BROWSER. The whole point of this screen: an owner adding a warden at 9pm does it here,
/// not on a laptop.
Future<bool?> showAddStaffSheet(
  BuildContext context, {
  required String hostelId,
  String? hostelName,
  required StaffRole initialRole,
  Set<StaffRole> taken = const {},
}) {
  return showGlassSheet<bool>(
    context: context,
    builder: (_) => _AddStaffSheet(
      hostelId: hostelId,
      hostelName: hostelName,
      initialRole: initialRole,
      taken: taken,
    ),
  );
}

class _AddStaffSheet extends ConsumerStatefulWidget {
  const _AddStaffSheet({
    required this.hostelId,
    required this.hostelName,
    required this.initialRole,
    required this.taken,
  });

  final String hostelId;
  final String? hostelName;
  final StaffRole initialRole;

  /// Roles that already have an active holder. Their card is drawn as taken rather than
  /// hidden, so the owner can see that the post exists and is filled — §4.3 is a rule about
  /// their PG, not a missing feature.
  final Set<StaffRole> taken;

  @override
  ConsumerState<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends ConsumerState<_AddStaffSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  late StaffRole _role = widget.initialRole;
  bool _busy = false;

  /// Client-side and server-side messages share this map, keyed by the function's own field
  /// names. The sheet cannot tell them apart, which is right — to the owner they are one event.
  Map<String, String> _errors = const {};

  /// A message about the whole form rather than one field.
  String? _banner;

  /// True when §4.3 was what refused. Changes the banner from a sentence into a next step.
  bool _roleLimitReached = false;

  /// Anything that was not about the input: offline, not your PG, subscription lapsed, a
  /// rollback report. Rendered with the owner's own error card, not as a field message.
  AppFailure? _failure;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  StaffDraft get _draft => StaffDraft(
        role: _role,
        fullName: _name.text,
        email: _email.text,
        phone: _phone.text,
      );

  /// Clears one field's message — it described the value that has just changed.
  void _touched(String field) {
    if (!_errors.containsKey(field) && _banner == null && _failure == null) return;
    setState(() {
      _errors = {
        for (final e in _errors.entries)
          if (e.key != field) e.key: e.value,
      };
      _banner = null;
      _roleLimitReached = false;
      _failure = null;
    });
  }

  void _pickRole(StaffRole role) {
    if (_busy || role == _role) return;
    setState(() {
      _role = role;
      // The messages under the fields belonged to the other role's attempt.
      _errors = const {};
      _banner = null;
      _roleLimitReached = false;
      _failure = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final draft = _draft;

    // Local validation first, so a typo costs nothing. It does not decide anything the server
    // would not also decide — see validateStaffDraft.
    final errors = validateStaffDraft(draft);
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _banner = 'Please check the highlighted fields.';
        _roleLimitReached = false;
        _failure = null;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errors = const {};
      _banner = null;
      _roleLimitReached = false;
      _failure = null;
    });

    try {
      final outcome = await ref.read(ownerStaffWritesProvider).createStaff(
            hostelId: widget.hostelId,
            draft: draft,
          );
      if (!mounted) return;

      switch (outcome) {
        case StaffCreated(:final credentials):
          // The list has gained a row and the other role's slot may now be the only free one.
          ref.invalidate(ownerStaffProvider(widget.hostelId));
          setState(() => _busy = false);

          // SHOWN FROM HERE, NOT FROM THE SCREEN BEHIND. The password crosses no route
          // boundary: this sheet is still mounted, and it stays mounted underneath the dialog
          // until the owner has ticked the box. Popping first and letting the screen present it
          // would put one more place in the path where the only copy of that password can be
          // dropped.
          await StaffCredentialsDialog.show(
            context,
            credentials: credentials,
            hostelName: widget.hostelName,
          );
          if (!mounted) return;
          Navigator.of(context).pop(true);

        case StaffRejected(:final message, :final fieldErrors, :final roleLimitReached):
          setState(() {
            _busy = false;
            _errors = fieldErrors;
            _banner = message;
            _roleLimitReached = roleLimitReached;
          });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = AppFailure.from(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.88 - media.padding.top;

    return PopScope(
      // A drag-to-dismiss mid-request would abandon a create that is already in flight and,
      // if it succeeded, throw away the only copy of the password it returned.
      canPop: !_busy,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // add-staff-details.png's head: a `label-caps` step marker in `primary` over the
            // step's own title. The mockup says "STEP 1 OF 3"; this flow has two steps, not
            // three — the permissions step it counts does not exist here (see the report) —
            // so the marker names the sheet instead of counting to a step that never arrives.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ADD STAFF',
                        style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.primary),
                      ),
                      const SizedBox(height: Space.xxs / 2),
                      Text(
                        'Add ${_role.label.toLowerCase()}',
                        style: t.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: Space.xxs),
            Text(
              'Enter the personal details and assign a role. They get their own login for '
              '${widget.hostelName ?? 'this PG'}.',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('SELECT ROLE', style: t.textTheme.labelSmall),
                    const SizedBox(height: Space.xs),
                    for (final role in StaffRole.values) ...[
                      if (role != StaffRole.values.first) const SizedBox(height: Space.xs),
                      StaffRoleCard(
                        role: role,
                        selected: role == _role,
                        // A taken post is drawn as taken rather than hidden: §4.3 is a rule
                        // about the owner's PG, not a missing feature.
                        taken: widget.taken.contains(role),
                        enabled: !_busy && !widget.taken.contains(role),
                        onTap: () => _pickRole(role),
                      ),
                    ],
                    const SizedBox(height: Space.md),
                    Divider(color: t.colorScheme.outlineVariant, height: Strokes.hairline),
                    const SizedBox(height: Space.md),

                    // The design labels every field with a `label-caps` eyebrow ABOVE the box
                    // and puts an example inside it. `FloatingLabelBehavior.always` plus a
                    // hint is exactly that arrangement, and it keeps the label a part of the
                    // field for screen readers rather than a loose line of text near it.
                    //
                    // THE HINTS DESCRIBE THE SHAPE, THEY DO NOT INVENT A PERSON. The mockup
                    // fills them with "John Doe" and "+91 98765 43210"; a placeholder is the
                    // one place invented-looking data sits inside a real control, and a hint
                    // that reads like a filled-in field is worth nothing anyway. The email one
                    // keeps `example.com`, which is the reserved domain and cannot be anybody.
                    TextField(
                      controller: _name,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      onChanged: (_) => _touched('fullName'),
                      decoration: InputDecoration(
                        labelText: 'Full name',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        hintText: 'First and last name',
                        errorText: _errors['fullName'],
                      ),
                    ),
                    const SizedBox(height: Space.sm),

                    TextField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      onChanged: (_) => _touched('email'),
                      decoration: InputDecoration(
                        labelText: 'Email',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        hintText: 'name@example.com',
                        // This is not a contact detail. It is what they will type to sign in,
                        // and it is unique across the whole platform.
                        helperText: 'This is their login id.',
                        errorText: _errors['email'],
                      ),
                    ),
                    const SizedBox(height: Space.sm),

                    TextField(
                      controller: _phone,
                      enabled: !_busy,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      // The server accepts spaces, +, - and brackets, so the keypad's own
                      // punctuation is allowed through rather than silently stripped.
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\s+\-()]')),
                        LengthLimitingTextInputFormatter(16),
                      ],
                      onChanged: (_) => _touched('phone'),
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Phone (optional)',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        hintText: '10-digit mobile number',
                        errorText: _errors['phone'],
                      ),
                    ),
                    const SizedBox(height: Space.sm),

                    // The mockup's `ASSIGN TO PROPERTY` control, drawn as a fact rather than a
                    // dropdown. The sheet is always opened FOR a PG — the caller passes its id
                    // — so a picker here would be a control with one option that cannot change
                    // where the account lands.
                    _AssignedProperty(hostelName: widget.hostelName),

                    if (_banner != null) ...[
                      const SizedBox(height: Space.md),
                      _Banner(message: _banner!, roleLimitReached: _roleLimitReached),
                    ],
                    if (_failure != null) ...[
                      const SizedBox(height: Space.md),
                      // No retry button: pressing Create again IS the retry, and a second
                      // button that does the same thing next to it is a second way to create
                      // two accounts by accident.
                      ErrorNote(error: _failure!, compact: true),
                    ],

                    const SizedBox(height: Space.md),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      child: _busy
                          ? const SizedBox(
                              height: IconSize.md,
                              width: IconSize.md,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('Create ${_role.label.toLowerCase()} account'),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'A temporary password is generated on the server and shown to you once. '
                      'Nivora never stores it.',
                      style: t.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One choosable role — add-staff-details.png's `SELECT ROLE` card.
///
/// The design draws each role as a card of its own: an icon badge top-left, a radio top-right,
/// the role's name in a title and what the person actually does underneath. That is a strictly
/// better control than the segmented button this replaces, and not only cosmetically — the
/// segments had room for the word "Manager" and nothing else, so the blurb could only be shown
/// for whichever role was already selected. Here both descriptions are on screen while the
/// choice is being made, which is when they are worth reading.
///
/// PUBLIC because owner_staff_test.dart drives §4.3 through it: a post with an active holder
/// arrives here as [taken], and the test asserts that such a card cannot be chosen.
class StaffRoleCard extends StatelessWidget {
  const StaffRoleCard({
    super.key,
    required this.role,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.taken = false,
  });

  final StaffRole role;
  final bool selected;

  /// False while a create is in flight, or when this post is [taken].
  final bool enabled;

  /// This PG already has an active holder for this role.
  final bool taken;

  final VoidCallback onTap;

  IconData get _icon => switch (role) {
        StaffRole.manager => Icons.manage_accounts_rounded,
        StaffRole.warden => Icons.shield_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final accent = selected ? scheme.primary : scheme.outline;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: taken
          ? '${role.label}. This PG already has an active ${role.label.toLowerCase()}.'
          : '${role.label}. ${role.blurb}',
      child: Opacity(
        // A taken post stays legible — it is information, not clutter — but visibly out of
        // reach. Not a colour of its own: the design ships no "disabled" role.
        opacity: enabled ? 1 : 0.5,
        child: FlatSurface(
          weight: GlassWeight.regular,
          borderRadius: Radii.rControl,
          padding: const EdgeInsets.all(Space.sm),
          onTap: enabled ? onTap : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ToneBadge(icon: _icon, tone: accent, tinted: selected),
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: IconSize.lg,
                    color: accent,
                  ),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(
                role.label,
                style: t.textTheme.titleMedium?.copyWith(
                  color: selected ? scheme.primary : null,
                ),
              ),
              const SizedBox(height: Space.xxs / 2),
              Text(
                taken
                    ? 'This PG already has an active ${role.label.toLowerCase()}.'
                    : role.blurb,
                style: t.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which PG the new login will belong to. A fact, in the shape of the mockup's control.
class _AssignedProperty extends StatelessWidget {
  const _AssignedProperty({required this.hostelName});

  final String? hostelName;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FlatSurface(
      weight: GlassWeight.regular,
      borderRadius: Radii.rControl,
      padding: const EdgeInsets.all(Space.sm),
      child: Row(
        children: [
          const ToneBadge(icon: Icons.apartment_rounded),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ASSIGNED PROPERTY', style: t.textTheme.labelSmall),
                Text(
                  hostelName ?? 'This PG',
                  style: t.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A message about the form as a whole.
///
/// §4.3 gets the warning tone and a next step; everything else is a plain refusal in the same
/// shape. A role limit is not an error the owner made — it is the product working — so it must
/// not be painted red next to a message about a malformed email.
class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.roleLimitReached});

  final String message;
  final bool roleLimitReached;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final tone = roleLimitReached ? tones.warning : tones.error;
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: tones.chipFill(tone),
        borderRadius: Radii.rControl,
        border: Border.all(color: tones.chipBorder(tone), width: Strokes.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            roleLimitReached ? Icons.info_outline_rounded : Icons.error_outline_rounded,
            size: IconSize.sm,
            color: tone,
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: t.textTheme.bodySmall),
                if (roleLimitReached) ...[
                  const SizedBox(height: Space.xxs),
                  Text(
                    'Close this, deactivate the person holding that post, then add the new one.',
                    style: t.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
