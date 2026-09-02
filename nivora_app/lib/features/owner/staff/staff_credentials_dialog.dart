library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/glass/glass.dart';
import 'staff_models.dart';

/// The temporary password for a new manager or warden, shown once (Hard rule §4.9).
///
/// ── WHY THIS DIALOG IS DIFFICULT TO CLOSE ON PURPOSE ─────────────────────────────────────
///
/// The password in front of the owner exists nowhere else. supabase/functions/owner-create-staff
/// generates it, returns it in one response marked `Cache-Control: no-store`, and writes it to
/// no table, no log and no audit row — `audit()` strips password-ish keys out of meta as a
/// second line of defence. This app does not persist it either. If it is lost, the only recovery
/// is a password reset, and there is no password-reset flow in this app yet: the owner would
/// have to go to the web console for it, which is precisely what this feature exists to avoid.
///
/// So this dialog behaves unlike every other dialog in the app:
///   • `barrierDismissible: false` — a stray tap outside cannot close it
///   • `PopScope(canPop: false)` — neither can the Android back gesture
///   • Done stays disabled until the owner ticks "I have saved these credentials"
///
/// Three deliberate obstacles in the way of one tap, each preventing a specific way a staff
/// member ends up locked out of an account created for them thirty seconds ago.
///
/// ── WHY THIS IS NOT AN IMPORT OF THE SUPER ADMIN'S DIALOG ────────────────────────────────
///
/// features/super_admin/create/credentials_dialog.dart makes the same three choices for the
/// same reason, and this is modelled on it deliberately rather than casually. It is not reused
/// because it is typed to the Super Admin's `IssuedCredentials`, titled "Owner account created",
/// and lives in a kit whose own header states that each role owns its vocabulary. What the two
/// share — the glass, the tokens, the type scale — is imported by both from shared/ and
/// core/theme/. If a third caller ever needs this, promote ONE of them into shared/ and delete
/// the other; two copies of a security-critical dialog is a thing to fix, not to extend.
class StaffCredentialsDialog extends StatefulWidget {
  const StaffCredentialsDialog({
    super.key,
    required this.credentials,
    this.hostelName,
  });

  final IssuedStaffCredentials credentials;

  /// Named in the heading, so an owner with several PGs knows which one this login is for.
  final String? hostelName;

  /// Presents it. Returns when the owner has confirmed they have saved the password — there is
  /// no other way for this future to complete.
  static Future<void> show(
    BuildContext context, {
    required IssuedStaffCredentials credentials,
    String? hostelName,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: NivoraColors.midnight.withValues(alpha: 0.48),
      builder: (_) => StaffCredentialsDialog(
        credentials: credentials,
        hostelName: hostelName,
      ),
    );
  }

  @override
  State<StaffCredentialsDialog> createState() => _StaffCredentialsDialogState();
}

class _StaffCredentialsDialogState extends State<StaffCredentialsDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = widget.credentials;
    final all = '${c.name} — ${c.roleLabel}\n'
        'Email: ${c.loginId}\n'
        'Temporary password: ${c.password}';

    return PopScope(
      // The back gesture must not be a way past the confirmation either.
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(Space.md),
        child: GlassSurface(
          weight: GlassWeight.thick,
          borderRadius: Radii.rCard,
          shadows: Shadows.level3,
          padding: const EdgeInsets.all(Space.lg),
          // THE ACTION BLOCK IS PINNED, THE STORY SCROLLS. add-staff-success.png is a full
          // page; this is a dialog on whatever phone the owner is holding, and stacking the
          // buttons the way the design does made the content tall enough that on a short
          // screen "Done" and the checkbox that arms it both fell below the fold. A dialog
          // whose only exit has scrolled out of sight is a trap, and this one already refuses
          // the barrier and the back gesture — so the confirmation and the two buttons sit
          // outside the scroll view and are always reachable.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // add-staff-success.png's hero: a mint tick on a haloed disc, centred,
                      // with the outcome under it as a heading rather than as a row title.
                      // Success is the whole content of this dialog, so it gets the width.
                      const _SuccessMark(),
                      const SizedBox(height: Space.md),
                      Text('${c.roleLabel} account created',
                          style: t.textTheme.titleLarge, textAlign: TextAlign.center),
                      if (widget.hostelName != null)
                        Text(widget.hostelName!,
                            style: t.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Space.sm),
                      Text(
                        'Share these with ${c.name}. They will be asked to set their own '
                        'password the first time they sign in.',
                        style: t.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Space.md),
                      _CredentialRow(
                          label: 'Email (login)', value: c.loginId, copyLabel: 'email'),
                      const SizedBox(height: Space.xs),
                      _CredentialRow(
                        label: 'Temporary password',
                        value: c.password,
                        copyLabel: 'password',
                        monospace: true,
                      ),
                      const SizedBox(height: Space.md),
                      // The mockup's tinted caution, drawn with the same chip recipe every
                      // other tinted box in this app uses rather than with its own two alphas.
                      Container(
                        padding: const EdgeInsets.all(Space.sm),
                        decoration: BoxDecoration(
                          color: context.tones.chipFill(NivoraColors.warning),
                          borderRadius: Radii.rControl,
                          border: Border.all(
                            color: context.tones.chipBorder(NivoraColors.warning),
                            width: Strokes.hairline,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: IconSize.sm, color: context.tones.warning),
                            const SizedBox(width: Space.xs),
                            Expanded(
                              child: Text(
                                'This password is shown once and is stored nowhere — not in '
                                'Nivora, not in the audit log. Copy it now. If it is lost, the '
                                'account has to be replaced.',
                                style: t.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              // The Material is not decoration. A ListTile paints its fill and its ink on
              // the nearest Material ancestor, and the nearest thing above this one is
              // GlassSurface's tinted DecoratedBox — which would swallow both. Flutter
              // asserts on exactly this arrangement, so without the wrapper the one dialog
              // that must never fail to appear throws on its way up in any debug build.
              Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  value: _confirmed,
                  onChanged: (v) => setState(() => _confirmed = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('I have saved these credentials',
                      style: t.textTheme.bodyMedium),
                ),
              ),
              const SizedBox(height: Space.xs),
              // The design stacks these full width and puts the emphasis on COPY, not on
              // dismiss: the loud violet pill under the halo is the one that saves the
              // password, and Done is the quiet neutral button below it. That is the right way
              // round — the tap that matters is the one that must not be missed.
              StaffCopyButton(text: all, label: 'all three', expanded: true),
              const SizedBox(height: Space.xs),
              FilledButton(
                onPressed: _confirmed ? () => Navigator.of(context).pop() : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  backgroundColor: t.colorScheme.surfaceContainerHighest,
                  foregroundColor: t.colorScheme.onSurface,
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mockup's haloed tick: a mint glyph on a disc of `surface-container-high`, ringed by the
/// tone's own tint so the halo reads without a blur behind it.
class _SuccessMark extends StatelessWidget {
  const _SuccessMark();

  static const _disc = Space.huge + Space.md; // 64

  @override
  Widget build(BuildContext context) {
    final tone = context.tones.success;
    return Center(
      child: Container(
        width: _disc,
        height: _disc,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          border: Border.all(color: context.tones.chipBorder(tone), width: Strokes.hairline),
          // The design's glow, in the positive tone rather than the FAB's violet. Same shape,
          // same radius, one call site.
          boxShadow: [
            for (final s in Shadows.glow)
              BoxShadow(color: context.tones.chipBorder(tone), blurRadius: s.blurRadius),
          ],
        ),
        child: Icon(Icons.check_circle_outline_rounded, size: IconSize.xl, color: tone),
      ),
    );
  }
}

/// One credential, with its own copy button.
///
/// SELECTABLE as well as copyable: an owner reading it onto a phone call needs to be able to
/// put a finger under the characters, and a generated password with an l and a 1 in it is
/// exactly the kind of string that gets read out wrong.
class _CredentialRow extends StatelessWidget {
  const _CredentialRow({
    required this.label,
    required this.value,
    required this.copyLabel,
    this.monospace = false,
  });

  final String label;
  final String value;
  final String copyLabel;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // The mockup sets the one-time password in a well of its own — a step up the container
    // ramp from the sheet behind it, at the control radius, with the value in `primary`.
    // Anything worth copying by hand should look like a field you could put a cursor in.
    return FlatSurface(
      weight: GlassWeight.regular,
      borderRadius: Radii.rControl,
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.xs, Space.xxs, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: t.textTheme.labelSmall),
                const SizedBox(height: Space.xxs / 2),
                SelectableText(
                  value,
                  style: monospace
                      // Ambiguous glyphs are the whole risk with a generated password, so it is
                      // set in a monospace face where 1, l and I do not converge.
                      ? t.textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 0.6,
                          color: t.colorScheme.primary,
                        )
                      : t.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          StaffCopyButton(text: value, label: copyLabel),
        ],
      ),
    );
  }
}

/// Copy to clipboard, with a confirmation that lasts long enough to be read.
class StaffCopyButton extends StatefulWidget {
  const StaffCopyButton({
    super.key,
    required this.text,
    required this.label,
    this.expanded = false,
  });

  final String text;

  /// What was copied, for the confirmation and for screen readers: "email", "password".
  final String label;

  /// A full-width labelled button rather than a bare icon.
  final bool expanded;

  @override
  State<StaffCopyButton> createState() => _StaffCopyButtonState();
}

class _StaffCopyButtonState extends State<StaffCopyButton> {
  bool _copied = false;

  /// THE FAILURE IS SAID OUT LOUD. `Clipboard.setData` goes over a MethodChannel and can
  /// throw — a platform that refuses the clipboard, a channel that is not up yet. Unhandled,
  /// the tick never appeared and nothing else did either: the one-time password this button
  /// exists for was "copied" as far as the person could tell, and was gone by the time they
  /// found out otherwise.
  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('This device would not take the ${widget.label} — it is still on '
              'screen above, so it can be written down.'),
          behavior: SnackBarBehavior.floating,
          duration: Motion.readMessage,
        ));
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    // Long enough to be read, short enough that a second copy is obviously a second copy.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final icon = _copied ? Icons.check_rounded : Icons.copy_rounded;
    if (widget.expanded) {
      // add-staff-success.png's `Copy Password`: a full-width violet pill under a violet halo.
      //
      // The mockup fills it with a gradient (`from-inverse-primary to-primary-container`) and
      // sets the label in white, which measures 3.17:1 on that fill. The theme's own
      // primary/on-primary pairing is 7.69:1 and is the same violet family, so the look is the
      // design's and the label is readable. The halo is [Shadows.glow] unmodified — the
      // design's own `shadow-[0_0_20px_rgba(160,120,255,0.4)]`, on the one control this dialog
      // exists for.
      return DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: Radii.rControl,
          boxShadow: Shadows.glow,
        ),
        child: FilledButton.icon(
          onPressed: _copy,
          icon: Icon(icon, size: IconSize.md),
          label: Text(_copied ? 'Copied' : 'Copy ${widget.label}'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        ),
      );
    }
    return IconButton(
      onPressed: _copy,
      tooltip: _copied ? 'Copied' : 'Copy ${widget.label}',
      icon: Icon(icon, size: IconSize.md),
    );
  }
}
