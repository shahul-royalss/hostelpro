library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../shared/glass/glass.dart';
import 'create/credentials_dialog.dart';
import 'data/sa_models.dart';
import 'data/sa_providers.dart';
import 'data/sa_repository.dart';
import 'widgets/sa_ui.dart';

/// The Super Admin's hands on one hostel: the owner's login, the plan, the status and the name.
///
/// THE OWNER ASKED FOR THESE BY NAME — reset a password for an owner who forgot it, correct
/// their email, suspend a PG or cancel its plan, and fix its name — and every one of them
/// changes something the owner, their staff or their residents will notice. So each goes
/// through a dialog or sheet that says exactly what will happen BEFORE it happens, does the
/// work where the admin can see it (busy on the button, the server's refusal in plain words
/// under it), and closes when the change has landed. Nothing started here ends without a word:
/// a sheet can still be flung shut while its request is out, and then the outcome is told on
/// the page underneath instead.
///
/// NOTHING HERE IS THE AUTHORITY. The validators below save a round trip; sa-owner-account and
/// the three sa_* RPCs re-check the caller, the second factor and every value.

// ─────────────────────────────────────────────────────────────────────────────
// VALIDATION — pure, so it is testable without a widget
// ─────────────────────────────────────────────────────────────────────────────

/// The bounds public.sa_rename_hostel and public.sa_cancel_subscription enforce, after trimming.
const hostelNameMin = 2;
const hostelNameMax = 120;
const cancelReasonMin = 3;
const cancelReasonMax = 300;

final RegExp _emailShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? validateHostelName(String raw, {String? current}) {
  final value = raw.trim();
  if (value.length < hostelNameMin) {
    return 'A hostel name needs at least $hostelNameMin characters.';
  }
  if (value.length > hostelNameMax) {
    return 'Keep the name to $hostelNameMax characters or fewer.';
  }
  if (current != null && value == current.trim()) return 'That is already the hostel\'s name.';
  return null;
}

String? validateCancelReason(String raw) {
  final value = raw.trim();
  if (value.length < cancelReasonMin) {
    return 'Give a reason of at least $cancelReasonMin characters. The owner is shown it.';
  }
  if (value.length > cancelReasonMax) {
    return 'Keep the reason to $cancelReasonMax characters or fewer.';
  }
  return null;
}

String? validateOwnerEmail(String raw, {String? current}) {
  final value = raw.trim();
  if (value.isEmpty) return 'Enter the new email address.';
  if (value.length > 254 || !_emailShape.hasMatch(value)) {
    return 'That does not look like an email address.';
  }
  // The phone-login namespace residents sign in under. Not a mailbox, and never an owner's.
  final domain = value.split('@').last.toLowerCase();
  if (domain == 'student.hostelpro.local' || domain.endsWith('.student.hostelpro.local')) {
    return 'Enter a real email address.';
  }
  if (current != null && value.toLowerCase() == current.trim().toLowerCase()) {
    return 'That is already the owner\'s login.';
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// THE BUTTONS ON THE CARDS
// ─────────────────────────────────────────────────────────────────────────────

/// "Edit name", for the hostel's own card.
class SaRenameControl extends ConsumerWidget {
  const SaRenameControl({super.key, required this.hostel});
  final SaHostelRow hostel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inFlight = ref.watch(saHostelActionProvider(hostel.hostelId));
    return _ControlWrap(children: [
      _ControlButton(
        label: 'Edit name',
        icon: Icons.edit_rounded,
        action: SaHostelAction.rename,
        inFlight: inFlight,
        onPressed: () => _rename(context, hostel),
      ),
    ]);
  }
}

/// "Reset password" and "Change email", for the Owner card.
class SaOwnerControls extends ConsumerWidget {
  const SaOwnerControls({super.key, required this.hostel});
  final SaHostelRow hostel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inFlight = ref.watch(saHostelActionProvider(hostel.hostelId));
    return _ControlWrap(children: [
      _ControlButton(
        label: 'Reset password',
        icon: Icons.key_rounded,
        action: SaHostelAction.resetPassword,
        inFlight: inFlight,
        onPressed: () => _resetPassword(context, hostel),
      ),
      _ControlButton(
        label: 'Change email',
        icon: Icons.alternate_email_rounded,
        action: SaHostelAction.changeEmail,
        inFlight: inFlight,
        onPressed: () => _changeEmail(context, hostel),
      ),
    ]);
  }
}

/// "Suspend hostel" or "Reactivate hostel", and "Cancel plan", for the Subscription card.
class SaSubscriptionControls extends ConsumerWidget {
  const SaSubscriptionControls({super.key, required this.hostel});
  final SaHostelRow hostel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inFlight = ref.watch(saHostelActionProvider(hostel.hostelId));
    final suspended = hostel.hostelStatus == HostelStatus.suspended;
    // rpc_sa_hostels already ignores cancelled periods, so a plan with days left is a plan
    // sa_cancel_subscription would find. An expired one it would refuse, so it is not offered.
    final hasCurrentPlan = hostel.subEnd != null && (hostel.daysLeft ?? -1) >= 0;

    return _ControlWrap(children: [
      if (suspended)
        _ControlButton(
          label: 'Reactivate hostel',
          icon: Icons.play_circle_outline_rounded,
          action: SaHostelAction.reactivate,
          inFlight: inFlight,
          onPressed: () => _setStatus(context, hostel, HostelStatus.active),
        )
      else
        _ControlButton(
          label: 'Suspend hostel',
          icon: Icons.pause_circle_outline_rounded,
          action: SaHostelAction.suspend,
          inFlight: inFlight,
          destructive: true,
          onPressed: () => _setStatus(context, hostel, HostelStatus.suspended),
        ),
      if (hasCurrentPlan)
        _ControlButton(
          label: 'Cancel plan',
          icon: Icons.event_busy_rounded,
          action: SaHostelAction.cancelPlan,
          inFlight: inFlight,
          destructive: true,
          onPressed: () => _cancelPlan(context, hostel),
        ),
    ]);
  }
}

class _ControlWrap extends StatelessWidget {
  const _ControlWrap({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: Space.xs, runSpacing: Space.xs, children: children);
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.icon,
    required this.action,
    required this.inFlight,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final SaHostelAction action;
  final SaHostelAction? inFlight;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      // Off while ANY change to this hostel is on the wire, not only this one.
      onPressed: inFlight == null ? onPressed : null,
      style: destructive ? OutlinedButton.styleFrom(foregroundColor: context.tones.error) : null,
      icon: inFlight == action ? const _Working() : Icon(icon, size: IconSize.sm),
      label: Text(label),
    );
  }
}

/// A spinner only while a request is actually out, and a still glyph for anyone who has asked
/// the system for less motion.
class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const Icon(Icons.hourglass_top_rounded, size: IconSize.sm);
    }
    return const RepaintBoundary(
      child: SizedBox.square(
        dimension: IconSize.sm,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE FLOWS
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _resetPassword(BuildContext context, SaHostelRow hostel) async {
  // The navigator shows the password, not this card: a card can be rebuilt away under a
  // refresh, and a password that was minted and then had nowhere to be shown is a lockout.
  final navigator = Navigator.of(context);
  final login = hostel.ownerEmail ?? 'their login';
  final credentials = await showDialog<IssuedCredentials>(
    context: context,
    builder: (_) => _WorkingDialog<IssuedCredentials>(
      hostelId: hostel.hostelId,
      title: 'Reset ${hostel.ownerName}\'s password?',
      body: [
        'Nivora issues a new temporary password for $login. It is shown to you once and stored '
            'nowhere, so be ready to pass it on.',
        '${hostel.ownerName} must choose their own password when they sign in with it, and is '
            'signed out on every device now. It is their login for every hostel they own.',
      ],
      confirmLabel: 'Reset and show password',
      run: (actions) => actions.resetOwnerPassword(),
    ),
  );
  if (credentials == null || !navigator.mounted) return;
  await CredentialsDialog.show(
    navigator.context,
    credentials: credentials,
    hostelName: hostel.hostelName,
    title: 'New temporary password',
  );
}

Future<void> _changeEmail(BuildContext context, SaHostelRow hostel) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _WorkingSheet<OwnerEmailChanged>(
      hostelId: hostel.hostelId,
      messenger: messenger,
      actionLabel: 'Change email',
      title: 'Change the owner\'s email',
      body: [
        '${hostel.ownerName} will sign in with the new address instead of '
            '${hostel.ownerEmail ?? 'the current one'}.',
        'They are signed out on every device now, and must verify the new address before '
            'Nivora treats it as theirs.',
      ],
      fieldLabel: 'New email',
      hint: 'owner@example.com',
      keyboardType: TextInputType.emailAddress,
      submitLabel: 'Save email',
      validator: (v) => validateOwnerEmail(v, current: hostel.ownerEmail),
      submit: (actions, value) async => switch (await actions.setOwnerEmail(value)) {
        final OwnerEmailChanged done => (result: done, fieldError: null),
        OwnerEmailRejected(:final emailError) => (result: null, fieldError: emailError),
      },
      announce: (changed) => '${changed.ownerName} now signs in with ${changed.loginId}. They '
          'have been signed out and must verify the new address.',
    ),
  );
}

Future<void> _setStatus(BuildContext context, SaHostelRow hostel, HostelStatus target) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final suspending = target == HostelStatus.suspended;
  final result = await showDialog<HostelStatus>(
    context: context,
    builder: (_) => _WorkingDialog<HostelStatus>(
      hostelId: hostel.hostelId,
      title: suspending ? 'Suspend ${hostel.hostelName}?' : 'Reactivate ${hostel.hostelName}?',
      body: suspending
          ? [
              'Suspended means every write in this PG is blocked until you reactivate it. No '
                  'resident can be registered, no payment recorded and no complaint resolved.',
              'Staff and residents can still sign in and read. ${hostel.ownerName} is notified.',
            ]
          : [
              'Writes are allowed again as soon as this is saved.',
              'If the plan has expired or was cancelled, the hostel stays read-only until it is '
                  'renewed. ${hostel.ownerName} is notified.',
            ],
      confirmLabel: suspending ? 'Suspend' : 'Reactivate',
      destructive: suspending,
      run: (actions) => actions.setStatus(target),
    ),
  );
  if (result == null) return;
  _announce(messenger, switch (result) {
    HostelStatus.suspended =>
      '${hostel.hostelName} is suspended. Every write is blocked until you reactivate it.',
    HostelStatus.active => '${hostel.hostelName} is active again.',
    HostelStatus.readonly => '${hostel.hostelName} is reactivated, but its plan has lapsed, so it '
        'stays read-only until renewed.',
  });
}

Future<void> _cancelPlan(BuildContext context, SaHostelRow hostel) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ends = hostel.subEnd == null ? '' : ', not on ${dateLabel(hostel.subEnd!)}';
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _WorkingSheet<int>(
      hostelId: hostel.hostelId,
      messenger: messenger,
      actionLabel: 'Cancel plan',
      title: 'Cancel the current plan',
      body: [
        'The plan ends now$ends. ${hostel.hostelName} becomes read-only immediately: nothing '
            'can be recorded there until a plan is renewed.',
        'A renewal starts a new period from the day it is recorded, rather than resuming this '
            'one. ${hostel.ownerName} is notified with your reason.',
      ],
      fieldLabel: 'Reason',
      helper: 'The owner is shown this. $cancelReasonMin to $cancelReasonMax characters.',
      maxLength: cancelReasonMax,
      maxLines: 4,
      submitLabel: 'Cancel the plan',
      dismissLabel: 'Keep the plan',
      destructive: true,
      validator: validateCancelReason,
      submit: (actions, value) async =>
          (result: await actions.cancelPlan(value), fieldError: null),
      announce: (_) =>
          'Plan cancelled. ${hostel.hostelName} is read-only until a new period is recorded.',
    ),
  );
}

Future<void> _rename(BuildContext context, SaHostelRow hostel) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _WorkingSheet<String>(
      hostelId: hostel.hostelId,
      messenger: messenger,
      actionLabel: 'Edit name',
      title: 'Edit hostel name',
      body: [
        'The new name shows everywhere this PG appears, to its owner, staff and residents. '
            '${hostel.ownerName} is notified.',
      ],
      fieldLabel: 'Hostel name',
      initialValue: hostel.hostelName,
      maxLength: hostelNameMax,
      capitalization: TextCapitalization.words,
      submitLabel: 'Save name',
      validator: (v) => validateHostelName(v, current: hostel.hostelName),
      submit: (actions, value) async => (result: await actions.rename(value), fieldError: null),
      announce: (stored) => 'Renamed to $stored.',
    ),
  );
}

void _announce(ScaffoldMessengerState? messenger, String text) {
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      duration: Motion.readMessage,
    ));
}

// ─────────────────────────────────────────────────────────────────────────────
// THE DIALOG AND THE SHEET THAT DO THE WORK
// ─────────────────────────────────────────────────────────────────────────────

/// A confirmation that runs its own action and stays open until it has landed.
///
/// The same shape as the payout dialog on this screen: busy on the confirm button, the failure
/// in the dialog under the words that described the action, and no way out while the request
/// is on the wire — the back gesture and the barrier both go through [PopScope].
class _WorkingDialog<T> extends ConsumerStatefulWidget {
  const _WorkingDialog({
    required this.hostelId,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.run,
    this.destructive = false,
  });

  final String hostelId;
  final String title;
  final List<String> body;
  final String confirmLabel;
  final Future<T> Function(SaHostelActionNotifier actions) run;
  final bool destructive;

  @override
  ConsumerState<_WorkingDialog<T>> createState() => _WorkingDialogState<T>();
}

class _WorkingDialogState<T> extends ConsumerState<_WorkingDialog<T>> {
  String? _error;

  Future<void> _confirm() async {
    setState(() => _error = null);
    try {
      final result = await widget.run(ref.read(saHostelActionProvider(widget.hostelId).notifier));
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) setState(() => _error = AppFailure.from(error).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final busy = ref.watch(saHostelActionProvider(widget.hostelId)) != null;
    final error = _error;

    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, paragraph) in widget.body.indexed) ...[
                if (i > 0) const SizedBox(height: Space.sm),
                Text(paragraph, style: t.textTheme.bodyMedium),
              ],
              if (error != null) ...[
                const SizedBox(height: Space.sm),
                _FailureText(error),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy ? null : _confirm,
            style: widget.destructive
                ? FilledButton.styleFrom(
                    backgroundColor: t.colorScheme.error,
                    foregroundColor: t.colorScheme.onError,
                  )
                : null,
            child: busy ? const _Working() : Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}

typedef _Submitted<T> = ({T? result, String? fieldError});

/// A one-field sheet that validates, runs its action, and shows the server's answer in place.
///
/// A refusal about the value itself ("that address is already in use") goes under the field,
/// through the field's own validator, so the admin fixes it without reopening anything; any
/// other failure sits under the field as a sentence. It closes itself on success, and says what
/// changed through [messenger].
///
/// IT CAN STILL BE DRAGGED SHUT MID-REQUEST. [PopScope] refuses the back gesture and the
/// barrier, but the sheet's drag closes it with a direct pop that no scope is asked about, and
/// showGlassSheet has no switch to turn the drag off. So when the answer arrives to a sheet that
/// is no longer on top, a refusal or failure goes through [messenger] as well, prefixed with
/// [actionLabel] so it is clear which change it is about.
class _WorkingSheet<T> extends ConsumerStatefulWidget {
  const _WorkingSheet({
    required this.hostelId,
    required this.messenger,
    required this.actionLabel,
    required this.title,
    required this.body,
    required this.fieldLabel,
    required this.submitLabel,
    required this.validator,
    required this.submit,
    required this.announce,
    this.initialValue = '',
    this.hint,
    this.helper,
    this.maxLength,
    this.maxLines = 1,
    this.keyboardType,
    this.capitalization = TextCapitalization.sentences,
    this.dismissLabel = 'Cancel',
    this.destructive = false,
  });

  final String hostelId;

  /// The page's messenger, taken before the sheet opened: the sheet may be gone when it is needed.
  final ScaffoldMessengerState? messenger;

  /// The control's own label, "Cancel plan", to lead a message the sheet was not there to show.
  final String actionLabel;
  final String title;
  final List<String> body;
  final String fieldLabel;
  final String submitLabel;
  final String? Function(String value) validator;
  final Future<_Submitted<T>> Function(SaHostelActionNotifier actions, String value) submit;

  /// The sentence for a change that landed.
  final String Function(T result) announce;
  final String initialValue;
  final String? hint;
  final String? helper;
  final int? maxLength;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  final String dismissLabel;
  final bool destructive;

  @override
  ConsumerState<_WorkingSheet<T>> createState() => _WorkingSheetState<T>();
}

class _WorkingSheetState<T> extends ConsumerState<_WorkingSheet<T>> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  final _formKey = GlobalKey<FormState>();
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  /// The value the server refused, and what it said. Kept together so the message disappears
  /// the moment the value it was about is edited.
  String? _rejectedValue;
  String? _rejection;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? raw) {
    final value = raw ?? '';
    final local = widget.validator(value);
    if (local != null) return local;
    if (_rejection != null && value.trim() == _rejectedValue) return _rejection;
    return null;
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _autovalidate = AutovalidateMode.onUserInteraction;
    });
    if (_formKey.currentState?.validate() != true) return;
    final value = _controller.text.trim();
    // Read before the await: after it, this state may be disposed.
    final messenger = widget.messenger;
    final label = widget.actionLabel;
    final announce = widget.announce;
    try {
      final outcome =
          await widget.submit(ref.read(saHostelActionProvider(widget.hostelId).notifier), value);
      final rejection = outcome.fieldError;
      if (rejection == null) {
        if (mounted && _onTop) Navigator.of(context).pop();
        _announce(messenger, announce(outcome.result as T));
      } else if (mounted && _onTop) {
        _rejectedValue = value;
        _rejection = rejection;
        _formKey.currentState?.validate();
      } else {
        _announce(messenger, '$label: $rejection');
      }
    } catch (error) {
      final message = AppFailure.from(error).message;
      if (mounted && _onTop) {
        setState(() => _error = message);
      } else {
        _announce(messenger, '$label: $message');
      }
    }
  }

  /// Still the top route; ask only while mounted. A sheet flung shut stays mounted through its
  /// exit animation, and popping then would close the hostel page underneath it instead.
  bool get _onTop => ModalRoute.isCurrentOf(context) ?? false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final busy = ref.watch(saHostelActionProvider(widget.hostelId)) != null;
    final error = _error;

    return PopScope(
      canPop: !busy,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: _autovalidate,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: t.textTheme.titleLarge),
              for (final paragraph in widget.body) ...[
                const SizedBox(height: Space.xs),
                Text(paragraph, style: t.textTheme.bodySmall),
              ],
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _controller,
                enabled: !busy,
                keyboardType:
                    widget.maxLines > 1 ? TextInputType.multiline : widget.keyboardType,
                textCapitalization: widget.keyboardType == TextInputType.emailAddress
                    ? TextCapitalization.none
                    : widget.capitalization,
                autocorrect: widget.keyboardType != TextInputType.emailAddress,
                maxLength: widget.maxLength,
                minLines: 1,
                maxLines: widget.maxLines,
                decoration: InputDecoration(
                  labelText: widget.fieldLabel,
                  hintText: widget.hint,
                  helperText: widget.helper,
                  helperMaxLines: 2,
                  errorMaxLines: 3,
                ),
                validator: _validate,
              ),
              if (error != null) ...[
                const SizedBox(height: Space.sm),
                _FailureText(error),
              ],
              const SizedBox(height: Space.lg),
              FilledButton(
                onPressed: busy ? null : _save,
                style: widget.destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: t.colorScheme.error,
                        foregroundColor: t.colorScheme.onError,
                      )
                    : null,
                child: busy ? const _Working() : Text(widget.submitLabel),
              ),
              const SizedBox(height: Space.xs),
              TextButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: Text(widget.dismissLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailureText extends StatelessWidget {
  const _FailureText(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = context.tones.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: IconSize.sm, color: tone),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Text(message, style: t.textTheme.bodySmall?.copyWith(color: tone)),
        ),
      ],
    );
  }
}
