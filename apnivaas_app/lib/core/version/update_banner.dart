library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/device/apps_launcher.dart';
import '../../shared/glass/glass.dart';
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
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
/// apnivaas_app/scripts/release.sh FAILS THE RELEASE if any browser or web-view escape appears
/// in lib/. That is a product decision older than this feature (every flow stays in the app),
/// and a download page is not the reason to reverse it. Copy is a real, visible action with a
/// confirmation, and pasting a link into Chrome is a step people already know. The URL is also
/// on screen in full, selectable, so a phone that refuses the clipboard still leaves something
/// a person can read out.
///
/// ═══ ROUND 6: THE APP IS ON GOOGLE PLAY NOW ═══
///
/// The owner's words: "whenever I release an update, the old version has to show a popup update
/// option and send them to the Play Store to update." So a newer build is now announced twice:
/// once as a POPUP when the shell first draws (once per version per launch), and as the bar
/// above the shell until it is updated or waved away. "Update now" opens this app's listing in
/// the Play Store APP through MainActivity's market:// intent — still no browser. Google Play
/// itself says a newer build exists ([playUpdateProvider]), so nothing has to be published by
/// hand; the app_releases row still works for a build that must be mandatory. The install page
/// stays as the fallback for a phone with no Play Store.

/// Wraps a role's shell and puts a bar above it when a newer build exists.
///
/// ═══ WHY IT WRAPS THE SHELL RATHER THAN LIVING INSIDE A HEADER ═══
///
/// [RoleShell] is the single widget behind all five role homes, so wrapping it is ONE mounting
/// point that reaches every signed-in screen.
///
/// THE STATUS-BAR INSET MOVES WITH THE BAR. Every header adds `MediaQuery.paddingOf().top` to its
/// own padding, so this widget takes the top inset itself and removes it from the subtree.
class UpdateBannerHost extends ConsumerStatefulWidget {
  const UpdateBannerHost({super.key, required this.child});

  final Widget child;

  /// The offer this run has already shown the popup for. Static: the shell is rebuilt as the
  /// person changes role tabs, and the popup is once per version per launch, not per rebuild.
  static Object? prompted;

  @override
  ConsumerState<UpdateBannerHost> createState() => _UpdateBannerHostState();
}

class _UpdateBannerHostState extends ConsumerState<UpdateBannerHost> {
  void _maybePrompt(UpdateOffer offer) {
    final key = offer.versionCode ?? offer.title;
    if (!offer.showing || UpdateBannerHost.prompted == key) return;
    UpdateBannerHost.prompted = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showUpdatePrompt(context, offer);
    });
  }

  @override
  Widget build(BuildContext context) {
    final offer = ref.watch(updateOfferProvider);
    // upToDate and unknown both draw nothing: a check that has not answered, or could not, is
    // silence — not an error message about a question nobody asked.
    if (!offer.showing) return widget.child;
    _maybePrompt(offer);

    // Dismissal is keyed by version code, so waving away 1.0.1 says nothing about 1.1.0.
    final code = offer.versionCode;
    final dismissed = code != null && ref.watch(updateDismissalProvider) == code;
    if (!offer.mandatory && dismissed) return widget.child;

    return Column(
      children: [
        _UpdateBar(offer: offer),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child),
        ),
      ],
    );
  }
}

/// Opens this app in the Play Store app; when that cannot happen, the sheet with the fallback.
Future<void> openPlayStore(BuildContext context, WidgetRef ref) async {
  final opened = await ref.read(appsLauncherProvider).openStore();
  if (!opened && context.mounted) await showUpdateSheet(context);
}

/// The popup: "Update available", with Update now and (unless mandatory) Later.
Future<void> showUpdatePrompt(BuildContext context, UpdateOffer offer) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !offer.mandatory,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final t = Theme.of(ctx);
        return AlertDialog(
          icon: Icon(Icons.system_update_rounded, color: t.colorScheme.primary, size: 40),
          title: Text(
            ctx.tr(offer.mandatory ? 'Update required' : 'Update available'),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ctx.tr('A new version of Apnivaas is on Google Play. Update now to get the '
                    'latest features and fixes.'),
                textAlign: TextAlign.center,
              ),
              if (offer.notes case final notes? when notes.isNotEmpty) ...[
                const SizedBox(height: Space.sm),
                Text(
                  notes,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            if (!offer.mandatory)
              TextButton(
                key: const Key('update-later'),
                onPressed: () {
                  final code = offer.versionCode;
                  if (code != null) ref.read(updateDismissalProvider.notifier).dismiss(code);
                  Navigator.of(ctx).pop();
                },
                child: Text(ctx.tr('Later')),
              ),
            FilledButton.icon(
              key: const Key('update-now'),
              onPressed: () {
                Navigator.of(ctx).pop();
                openPlayStore(context, ref);
              },
              icon: const Icon(Icons.shop_rounded, size: IconSize.md),
              label: Text(ctx.tr('Update now')),
            ),
          ],
        );
      },
    ),
  );
}

/// The bar itself. One row: icon, sentence, and either a dismiss or a chevron.
class _UpdateBar extends ConsumerWidget {
  const _UpdateBar({required this.offer});

  /// A mandatory offer has NO dismiss control: the flag means the build being replaced gets
  /// something wrong, and a close button on that is a close button on the fix.
  final UpdateOffer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final blocking = offer.mandatory;
    // An optional update is information (info blue); a mandatory one is the warning gold.
    final tone = blocking ? context.tones.warning : context.tones.info;
    final label = blocking
        ? '${context.tr('Update required')} — ${offer.title}'
        : '${offer.title} · ${context.tr('Update available')}';

    return Material(
      color: t.colorScheme.surface,
      child: Ink(
        decoration: BoxDecoration(
          color: context.tones.chipFill(tone),
          border: Border(
            bottom: BorderSide(color: tone.withValues(alpha: 0.32), width: Strokes.hairline),
          ),
        ),
        child: InkWell(
          onTap: () => openPlayStore(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm)
                .add(EdgeInsets.only(top: MediaQuery.paddingOf(context).top)),
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
                        style: t.textTheme.bodyMedium
                            ?.copyWith(color: tone, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        context.tr('Tap to update on Google Play'),
                        style: t.textTheme.bodySmall?.copyWith(color: context.tones.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!blocking && offer.versionCode != null)
                  IconButton(
                    tooltip: 'Not now',
                    onPressed: () => ref
                        .read(updateDismissalProvider.notifier)
                        .dismiss(offer.versionCode!),
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

/// The sheet behind "Update now" when the Play Store app could not be opened.
///
/// Opened FIRST and reading the providers from inside its own build: Riverpod 3 throws
/// UnmountedRefException across an await gap when nothing is listening.
Future<void> showUpdateSheet(BuildContext context) {
  return showGlassSheet<void>(context: context, builder: (_) => const _UpdateSheet());
}

class _UpdateSheet extends ConsumerWidget {
  const _UpdateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final installed = ref.watch(installedBuildProvider);
    final offer = ref.watch(updateOfferProvider);
    final checking =
        ref.watch(latestReleaseProvider).isLoading || ref.watch(playUpdateProvider).isLoading;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr(offer.mandatory ? 'Update required' : 'Update available'),
            style: t.textTheme.titleLarge,
          ),
          const SizedBox(height: Space.xs),
          // BOTH NUMBERS when both are known: a fact somebody can check.
          Text(
            offer.versionCode == null
                ? 'You are running ${installed.label}.'
                : 'You are running ${installed.label}. '
                    '${offer.title} (build ${offer.versionCode}) is out.',
            style: t.textTheme.bodyMedium?.copyWith(color: context.tones.muted),
          ),
          const SizedBox(height: Space.md),
          FilledButton.icon(
            onPressed: () async {
              final opened = await ref.read(appsLauncherProvider).openStore();
              if (opened && context.mounted) Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.shop_rounded, size: IconSize.md),
            label: Text(context.tr('Update now')),
          ),
          const SizedBox(height: Space.lg),
          Text('No Play Store on this phone?', style: t.textTheme.titleSmall),
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
          Row(
            children: [
              TextButton(
                onPressed: checking
                    ? null
                    : () {
                        ref.invalidate(latestReleaseProvider);
                        ref.invalidate(playUpdateProvider);
                      },
                child: Text(checking ? 'Checking…' : 'Check again'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(context.tr('Close')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Copy, with a confirmation that lasts long enough to be read. `Clipboard.setData` crosses a
/// MethodChannel and CAN throw, and a copy that silently did not happen is worse than one that
/// says so.
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
    return OutlinedButton.icon(
      onPressed: _copy,
      icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: IconSize.md),
      label: Text(_copied ? 'Link copied' : 'Copy the link'),
    );
  }
}
