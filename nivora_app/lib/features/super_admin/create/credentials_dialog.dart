library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/glass/glass.dart';
import '../data/sa_models.dart';
import '../widgets/sa_ui.dart';

/// The temporary password, shown once (Hard rule §4.9).
///
/// ── WHY THIS DIALOG IS DIFFICULT TO CLOSE ON PURPOSE ─────────────────────────────────────
///
/// The password in front of the admin exists nowhere else. supabase/functions/sa-create-owner
/// generates it, returns it in one response marked `Cache-Control: no-store`, and writes it to
/// no table, no log and no audit row — `audit_event()` strips password-ish keys out of meta as
/// a second line of defence. This app does not persist it either. If it is lost the only
/// recovery is to issue a new one.
///
/// So this dialog behaves unlike every other dialog in the app:
///   • `barrierDismissible: false` — a stray tap outside cannot close it
///   • `PopScope(canPop: false)` — neither can the Android back gesture
///   • Done stays disabled until the admin ticks "I have saved these credentials"
///
/// That is three deliberate obstacles in the way of one tap, and each one prevents a specific
/// way an owner ends up locked out of an account that was created for them thirty seconds ago.
/// The web app's CredentialsDialog makes exactly the same three choices; this matches its care
/// rather than reinventing it.
///
/// Copy is offered per field and for all three at once, because the admin is usually about to
/// paste them into a message to the owner.
class CredentialsDialog extends StatefulWidget {
  const CredentialsDialog({
    super.key,
    required this.credentials,
    this.hostelName,
  });

  final IssuedCredentials credentials;

  /// Named in the heading, so an admin creating several in a row knows which one this is for.
  final String? hostelName;

  /// Presents it. Returns when the admin has confirmed they have saved the password — there is
  /// no other way for this future to complete.
  static Future<void> show(
    BuildContext context, {
    required IssuedCredentials credentials,
    String? hostelName,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: NivoraColors.midnight.withValues(alpha: 0.48),
      builder: (_) => CredentialsDialog(
        credentials: credentials,
        hostelName: hostelName,
      ),
    );
  }

  @override
  State<CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<CredentialsDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = widget.credentials;
    final all = '${c.name}\n'
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: context.tones.chipFill(t.colorScheme.primary),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.key_rounded,
                          size: IconSize.md, color: t.colorScheme.primary),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Owner account created', style: t.textTheme.titleMedium),
                          if (widget.hostelName != null)
                            Text(widget.hostelName!,
                                style: t.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text(
                  'Share these with ${c.name}. They will be asked to set their own password '
                  'the first time they sign in.',
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.md),

                _CredentialRow(label: 'Email (login)', value: c.loginId, copyLabel: 'email'),
                const SizedBox(height: Space.xs),
                _CredentialRow(
                  label: 'Temporary password',
                  value: c.password,
                  copyLabel: 'password',
                  monospace: true,
                ),

                const SizedBox(height: Space.md),
                // The design's badge recipe — a 10% fill of the tone under a full-strength
                // hairline of it, both measured once in NivoraSemantics. The 0.08/0.32 pair
                // this replaced was a light-theme alpha painted twice.
                Container(
                  padding: const EdgeInsets.all(Space.sm),
                  decoration: BoxDecoration(
                    color: context.tones.chipFill(context.tones.warning),
                    borderRadius: Radii.rControl,
                    border: Border.all(
                      color: context.tones.chipBorder(context.tones.warning),
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
                          'This password is shown once and is stored nowhere — not in Nivora, '
                          'not in the audit log. Copy it now. If it is lost, the only fix is '
                          'to issue a new one.',
                          style: t.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: Space.sm),
                CheckboxListTile(
                  value: _confirmed,
                  onChanged: (v) => setState(() => _confirmed = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'I have saved these credentials',
                    style: t.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    Expanded(
                      child: SaCopyButton(text: all, label: 'all three', expanded: true),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: _confirmed ? () => Navigator.of(context).pop() : null,
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One credential, with its own copy button.
///
/// SELECTABLE as well as copyable: an admin reading it onto a phone call needs to be able to
/// put a finger under the characters, and a password with an l and a 1 in it is exactly the
/// kind of string that gets read out wrong.
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
    return FlatSurface(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.xs, Space.xxs, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: t.textTheme.labelSmall),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: monospace
                      // Ambiguous glyphs are the whole risk with a generated password, so it is
                      // set in a monospace face where 1, l and I do not converge.
                      ? t.textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 0.6,
                        )
                      : t.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          SaCopyButton(text: value, label: copyLabel),
        ],
      ),
    );
  }
}
