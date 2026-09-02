library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/glass/glass.dart';
import '../theme/tokens.dart';
import 'app_release.dart';
import 'release_check.dart';

/// THE NOTICE ON THE OLD APP THAT A NEW BUILD EXISTS.
///
/// The owner's words: "when I made changes they have to update our application through a
/// notice on our old application, by clicking on it they can update our application without
/// any error."
///
/// ═══ WHAT THIS CAN HONESTLY DO, AND WHAT IT CANNOT ═══
///
/// It CANNOT install anything. Android does not let an ordinary sideloaded app replace itself
/// silently: writing the APK and firing the package installer needs the
/// REQUEST_INSTALL_PACKAGES permission, a FileProvider, and a system confirmation screen the
/// user still has to accept — and Play reviews that permission hard, days before a submission.
/// An "auto-update" button that ends in Android's own installer dialog is not an auto-update;
/// it is the same three taps with a longer fuse and one more thing to go wrong.
///
/// So this banner does the two things that are actually true: it TELLS the person a newer
/// build exists, naming both version numbers so the claim is checkable, and it hands them the
/// install page — which is the one place the "Install unknown apps" step is explained. And,
/// because the owner's requirement was "without any error", the sheet says in advance what
/// Android will do if the two APKs disagree, and what to do about it. A message that arrives
/// before the failure is worth more than a retry button after it.
///
/// ═══ AND WHY IT COPIES A LINK RATHER THAN OPENING ONE ═══
///
/// Nothing in this app opens a browser — url_launcher is not a dependency, and
/// nivora_app/scripts/release.sh FAILS THE RELEASE if any browser or web-view escape appears
/// in lib/. That is a product decision older than this feature (every flow stays in the app),
/// and a download page is not the reason to reverse it. Copy is a real, visible action with a
/// confirmation, and pasting a link into Chrome is a step people already know. The URL is also
/// on screen in full, selectable, so a phone that refuses the clipboard still leaves something
/// a person can read out.

/// Wraps a role's shell and puts a bar above it when a newer build exists.
///
/// ═══ WHY IT WRAPS THE SHELL RATHER THAN LIVING INSIDE A HEADER ═══
///
/// [RoleShell] is the single widget behind all five role homes — warden, manager and super
/// admin delegate to their own shells from inside it, the owner and student draw theirs there.
/// Wrapping it is therefore ONE mounting point that reaches every signed-in screen, instead of
/// five edits in five feature directories that four future roles would have to remember.
///
/// THE STATUS-BAR INSET MOVES WITH THE BAR. [GlassHeader] adds `MediaQuery.paddingOf().top` to
/// its own padding, so a bar placed above it would sit UNDER the clock and the battery icon
/// while the header below reserved space for a notch that was no longer at the top of the
/// screen. This widget takes the top inset itself and then removes it from the subtree, so the
/// header underneath draws flush and nothing is counted twice.
class UpdateBannerHost extends ConsumerWidget {
  const UpdateBannerHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateStatusProvider);
    final release = ref.watch(latestReleaseProvider).value;

    // upToDate and unknown both draw nothing. See UpdateStatus: a check that has not answered,
    // or could not, is silence — not an error message about a question nobody asked.
    final showing = release != null &&
        (status == UpdateStatus.available || status == UpdateStatus.required);
    if (!showing) return child;

    // Dismissal is keyed by version code, so waving away 1.0.1 says nothing about 1.1.0.
    final dismissed = ref.watch(updateDismissalProvider) == release.versionCode;
    if (status == UpdateStatus.available && dismissed) return child;

    return Column(
      children: [
        _UpdateBar(release: release, blocking: status == UpdateStatus.required),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// The bar itself. One row: icon, sentence, and either a chevron or a chevron plus a dismiss.
class _UpdateBar extends ConsumerWidget {
  const _UpdateBar({required this.release, required this.blocking});

  final AppRelease release;

  /// `mandatory` on the release row. A blocking bar has NO dismiss control — the flag means the
  /// build being replaced gets something wrong, and a close button on that is a close button on
  /// the fix. It is constrained in the database too: a mandatory release must have a download
  /// URL, so this bar can never be an exit-less screen with nowhere to go.
  final bool blocking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    // Two registers, because they are two different events. An optional update is information
    // (info blue); a mandatory one is something to act on now (the warning gold).
    final tone = blocking ? context.tones.warning : context.tones.info;
    final label = blocking
        ? 'Update required — Nivora ${release.versionName}'
        : 'Nivora ${release.versionName} is available';

    return Material(
      color: t.colorScheme.surface,
      child: Ink(
        decoration: BoxDecoration(
          // The design's own chip recipe (NivoraSemantics.chipFill): a 10% tint of the tone,
          // which is all this palette takes before 12px type on it stops clearing AA.
          color: context.tones.chipFill(tone),
          border: Border(
            bottom: BorderSide(color: tone.withValues(alpha: 0.32), width: Strokes.hairline),
          ),
        ),
        child: InkWell(
          onTap: () => showUpdateSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ).add(EdgeInsets.only(top: MediaQuery.paddingOf(context).top)),
            child: Row(
              children: [
                Icon(Icons.system_update_rounded, size: IconSize.md, color: tone),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Tap to see how to install it',
                        style: t.textTheme.bodySmall?.copyWith(color: context.tones.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!blocking)
                  IconButton(
                    tooltip: 'Not now',
                    onPressed: () => ref
                        .read(updateDismissalProvider.notifier)
                        .dismiss(release.versionCode),
                    icon: Icon(Icons.close_rounded, size: IconSize.md, color: context.tones.muted),
                  )
                else
                  Icon(Icons.chevron_right_rounded, size: IconSize.md, color: tone),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the update sheet.
///
/// The sheet is opened FIRST and reads the providers from inside its own build, rather than
/// this function awaiting a value and then presenting it. Riverpod 3 throws
/// UnmountedRefException across an await gap when nothing is listening, and that pattern has
/// already cost this project a debugging session. Nothing here awaits anything.
Future<void> showUpdateSheet(BuildContext context) {
  return showGlassSheet<void>(context: context, builder: (_) => const _UpdateSheet());
}

class _UpdateSheet extends ConsumerWidget {
  const _UpdateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final installed = ref.watch(installedBuildProvider);
    final async = ref.watch(latestReleaseProvider);
    final release = async.value;
    final status = ref.watch(updateStatusProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status == UpdateStatus.required ? 'Update required' : 'A new Nivora is ready',
            style: t.textTheme.titleLarge,
          ),
          const SizedBox(height: Space.xs),

          // BOTH NUMBERS, ALWAYS. "An update is available" is a claim; "you have build 1, build
          // 4 is out" is a fact somebody can check against the install page, and it is the line
          // that makes a support call two minutes instead of twenty.
          Text(
            release == null
                ? 'You are running ${installed.label}.'
                : 'You are running ${installed.label}. '
                    'The current build is ${release.label}.',
            style: t.textTheme.bodyMedium?.copyWith(color: context.tones.muted),
          ),

          if (release?.notes case final notes? when notes.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            FlatSurface(
              weight: GlassWeight.regular,
              padding: const EdgeInsets.all(Space.sm),
              child: Text(notes, style: t.textTheme.bodyMedium),
            ),
          ],

          const SizedBox(height: Space.lg),

          // ── WHERE TO GET IT ──────────────────────────────────────────────
          Text('Where to get it', style: t.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          Text(
            'Open this page in your phone browser. It has the download and the one Android '
            'setting that has to be allowed the first time.',
            style: t.textTheme.bodyMedium?.copyWith(color: context.tones.muted),
          ),
          const SizedBox(height: Space.sm),
          FlatSurface(
            weight: GlassWeight.regular,
            padding: const EdgeInsets.all(Space.sm),
            child: SelectableText(
              installPageUrl,
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.primary),
            ),
          ),
          const SizedBox(height: Space.sm),
          const _CopyLinkButton(),

          const SizedBox(height: Space.lg),

          // ── THE PART THE OWNER CALLED "WITHOUT ANY ERROR" ────────────────
          Text('If Android refuses to install it', style: t.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          Text(
            'Installing over the top only works when the new file is signed with the same key '
            'as the one on your phone, and has a higher build number. Both are true of every '
            'build published from the release script, so the normal case is that it just '
            'replaces this app and your data stays.\n\n'
            'If you see "App not installed", the file you downloaded was signed with a '
            'different key — usually a test build. Do not keep retrying: uninstall Nivora '
            'first, then install the downloaded file. You will have to sign in again '
            'afterwards, and nothing kept on the server is lost.',
            style: t.textTheme.bodyMedium?.copyWith(color: context.tones.muted),
          ),

          const SizedBox(height: Space.lg),

          Row(
            children: [
              // A CONTROL THAT DOES SOMETHING VISIBLE: invalidating re-runs the read, this
              // sheet is watching it, and the numbers above redraw from the answer.
              TextButton(
                onPressed: async.isLoading
                    ? null
                    : () => ref.invalidate(latestReleaseProvider),
                child: Text(async.isLoading ? 'Checking…' : 'Check again'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Copy, with a confirmation that lasts long enough to be read.
///
/// Same shape as the copy buttons in the security screen and the credentials dialogs, and for
/// the same reason: `Clipboard.setData` crosses a MethodChannel and CAN throw, and a copy that
/// silently did not happen is worse than one that says so — the person walks away believing
/// they have the link.
class _CopyLinkButton extends StatefulWidget {
  const _CopyLinkButton();

  @override
  State<_CopyLinkButton> createState() => _CopyLinkButtonState();
}

class _CopyLinkButtonState extends State<_CopyLinkButton> {
  bool _copied = false;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(const ClipboardData(text: installPageUrl));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('This device would not take the clipboard — the address is on screen '
              'above and can be typed into your browser.'),
          behavior: SnackBarBehavior.floating,
          duration: Motion.readMessage,
        ));
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(Motion.confirmed);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _copy,
      icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: IconSize.md),
      label: Text(_copied ? 'Link copied' : 'Copy the link'),
    );
  }
}
