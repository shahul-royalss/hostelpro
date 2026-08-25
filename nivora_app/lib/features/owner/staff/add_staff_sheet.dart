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

  /// Roles that already have an active holder. Drawn as disabled segments rather than hidden,
  /// so the owner can see that the post exists and is filled — §4.3 is a rule about their PG,
  /// not a missing feature.
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ADD STAFF', style: t.textTheme.labelSmall),
                      Text(
                        widget.hostelName ?? 'This PG',
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
            const SizedBox(height: Space.md),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RolePicker(
                      value: _role,
                      taken: widget.taken,
                      enabled: !_busy,
                      onChanged: _pickRole,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(_role.blurb, style: t.textTheme.bodySmall),
                    const SizedBox(height: Space.md),

                    TextField(
                      controller: _name,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      onChanged: (_) => _touched('fullName'),
                      decoration: InputDecoration(
                        labelText: 'Full name',
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
                        errorText: _errors['phone'],
                      ),
                    ),

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

/// Manager or Warden. A taken post is shown disabled rather than removed.
class _RolePicker extends StatelessWidget {
  const _RolePicker({
    required this.value,
    required this.taken,
    required this.enabled,
    required this.onChanged,
  });

  final StaffRole value;
  final Set<StaffRole> taken;
  final bool enabled;
  final ValueChanged<StaffRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<StaffRole>(
      segments: [
        for (final role in StaffRole.values)
          ButtonSegment<StaffRole>(
            value: role,
            label: Text(role.label),
            enabled: enabled && !taken.contains(role),
            tooltip: taken.contains(role)
                ? 'This PG already has an active ${role.label.toLowerCase()}'
                : null,
          ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
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
