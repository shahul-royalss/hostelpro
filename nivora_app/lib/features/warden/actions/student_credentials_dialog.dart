library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/glass/glass.dart';
import '../data/warden_repository.dart';

/// The resident's login, shown once (Hard rule §4.9).
///
/// ── WHY THIS DIALOG IS DIFFICULT TO CLOSE ON PURPOSE ─────────────────────────────────────
///
/// The password in front of the warden exists nowhere else. supabase/functions/
/// warden-register-student generates it, returns it in one response marked
/// `Cache-Control: no-store`, and writes it to no table, no log and no audit row —
/// `audit_event()` strips password-ish keys out of meta as a second line of defence. This app
/// does not persist it either. If it is lost the only recovery is to issue a new one, which the
/// warden cannot do: it is an owner-or-above action on the web app's account screen. So a
/// dismissed dialog is a resident who cannot sign in and a trip to somebody else's desk.
///
/// This dialog therefore behaves unlike every other dialog in the app:
///   • `barrierDismissible: false` — a stray tap outside cannot close it
///   • `PopScope(canPop: false)` — neither can the Android back gesture
///   • Done stays disabled until the warden ticks "I have saved these credentials"
///
/// Three deliberate obstacles in the way of one tap, each preventing a specific way a resident
/// ends up locked out of an account created for them thirty seconds ago. The Super Admin's
/// CredentialsDialog makes the same three choices; this matches its care rather than
/// reinventing it.
///
/// ── AND WHY BOTH HALVES ARE ON SCREEN ────────────────────────────────────────────────────
///
/// A student signs in with their PHONE NUMBER, not an email — `studentLoginEmail()` maps it to
/// a synthetic address neither client ever shows. The pair is what the resident needs, so the
/// pair is what is displayed and what "Copy both" puts on the clipboard. Showing the password
/// alone would hand over half a credential.
class StudentCredentialsDialog extends StatefulWidget {
  const StudentCredentialsDialog({super.key, required this.credentials, this.bedLabel});

  final StudentCredentials credentials;

  /// "Room 204 · Bed 2", named in the heading so a warden registering several in a row knows
  /// which resident this belongs to.
  final String? bedLabel;

  /// Presents it. The future completes only once the warden has confirmed they saved the
  /// password — there is no other way out.
  static Future<void> show(
    BuildContext context, {
    required StudentCredentials credentials,
    String? bedLabel,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: NivoraColors.midnight.withValues(alpha: 0.48),
      builder: (_) => StudentCredentialsDialog(credentials: credentials, bedLabel: bedLabel),
    );
  }

  @override
  State<StudentCredentialsDialog> createState() => _StudentCredentialsDialogState();
}

class _StudentCredentialsDialogState extends State<StudentCredentialsDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = widget.credentials;
    final both = '${c.name}\n'
        'Phone (login): ${c.loginId}\n'
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
                          Text('${c.name} registered', style: t.textTheme.titleLarge,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (widget.bedLabel != null)
                            Text(widget.bedLabel!,
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
                  'Give these to ${c.name}. They sign in with their phone number, and will be '
                  'asked to set their own password the first time.',
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.md),

                _CredentialRow(label: 'Phone (login)', value: c.loginId, copyLabel: 'phone number'),
                const SizedBox(height: Space.xs),
                _CredentialRow(
                  label: 'Temporary password',
                  value: c.password,
                  copyLabel: 'password',
                  monospace: true,
                ),

                const SizedBox(height: Space.md),
                Container(
                  padding: const EdgeInsets.all(Space.sm),
                  decoration: BoxDecoration(
                    color: context.tones.warning.withValues(alpha: 0.08),
                    borderRadius: Radii.rControl,
                    border: Border.all(color: context.tones.warning.withValues(alpha: 0.32)),
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
                          'not in the audit log. Copy it now. If it is lost, only the owner can '
                          'issue a new one.',
                          style: t.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: Space.sm),
                // Material(transparency), not a bare CheckboxListTile. A ListTile paints its
                // splash on the nearest Material ancestor, and the nearest thing above this one
                // is GlassSurface's DecoratedBox — which draws its own background OVER that
                // splash. Flutter asserts on exactly this arrangement in debug.
                Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    value: _confirmed,
                    onChanged: (v) => setState(() => _confirmed = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('I have saved these credentials', style: t.textTheme.bodyMedium),
                  ),
                ),
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    Expanded(
                      child: CopyButton(text: both, label: 'both', expanded: true),
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
/// SELECTABLE as well as copyable: a warden reading it down a phone line needs to be able to
/// put a finger under the characters, and a generated password is exactly the kind of string
/// that gets read out wrong.
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
                      ? t.textTheme.titleMedium
                          ?.copyWith(fontFamily: 'monospace', letterSpacing: 0.6)
                      : t.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          CopyButton(text: value, label: copyLabel),
        ],
      ),
    );
  }
}

/// Copy to clipboard, with the confirmation on the button itself.
///
/// A LOCAL TWIN OF SaCopyButton, not an import of it. `sa_ui.dart` is the Super Admin console's
/// kit and nothing in features/warden reaches into another role's directory — a shared control
/// belongs in lib/shared or in that role's own kit, and this is the only warden screen that
/// copies anything. Promote it into warden_ui.dart the moment a second one does.
class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.text,
    required this.label,
    this.expanded = false,
  });

  final String text;

  /// What was copied, for the confirmation and for screen readers: "password", "both".
  final String label;

  /// A full-width labelled button rather than a bare icon.
  final bool expanded;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
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
      return OutlinedButton.icon(
        onPressed: _copy,
        icon: Icon(icon, size: IconSize.sm),
        label: Text(_copied ? 'Copied' : 'Copy ${widget.label}'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
      );
    }
    return IconButton(
      onPressed: _copy,
      tooltip: _copied ? 'Copied' : 'Copy ${widget.label}',
      icon: Icon(icon, size: IconSize.md),
    );
  }
}
