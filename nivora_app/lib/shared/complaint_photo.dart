library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/tokens.dart';
import '../data/models/models.dart';
import '../data/providers.dart';

/// The photo on a complaint, drawn the same way for the resident who attached it, the warden
/// working the queue and the owner reading over both their shoulders.
///
/// ═══ ONE WIDGET, THREE ROLES, ON PURPOSE ═══
/// Who may see a complaint's photo is decided in exactly one place — the `complaints_select`
/// policy, re-asked on the server when the URL is minted (see
/// supabase/functions/complaint-photo/index.ts). A per-role copy of this widget would be three
/// chances to draw a photo one of those roles is not entitled to, guarded by three client-side
/// conditions that are not the guard. So it lives in lib/shared and takes only a complaint id.
///
/// ═══ FOUR STATES, KEPT APART ═══
/// LOADING is a sized skeleton, not a spinner, because the card is about to be a picture of a
/// known size and the layout must not jump. EMPTY (`photoUrl` null) draws nothing at all — a
/// complaint without a photo should not carry a box explaining that it has no photo. FAILED
/// says what went wrong and offers Retry. REFUSED says the reader is not allowed and offers
/// nothing, because retrying a refusal is theatre. They are four different renderings and none
/// of them is another one's placeholder.
///
/// ═══ WHY THE URL IS NOT CACHED FOR LONG ═══
/// It is signed and lives thirty minutes. `complaintPhotoProvider` is autoDispose with no
/// session hold for exactly that reason — a sheet reopened an hour later mints a fresh URL
/// instead of rendering a broken image.

/// How tall the preview stands. Fixed so the skeleton, the image and the failure note are all
/// the same size and the sheet does not resize under the reader as the photo arrives.
const double _previewHeight = 200;

/// The photo preview, or nothing at all when the complaint carries no photo.
///
/// [hasPhoto] comes off `complaints.photo_url` — a KEY, never a URL, which is why it can say
/// whether there is a photo but cannot show one. Passing it lets the common case (no
/// attachment) cost zero network calls: without it every complaint sheet in the app would ask
/// the server to sign a photo that is not there.
class ComplaintPhotoCard extends ConsumerWidget {
  const ComplaintPhotoCard({
    super.key,
    required this.complaintId,
    required this.hasPhoto,
    this.label = 'Photo from the resident',
  });

  final String complaintId;
  final bool hasPhoto;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasPhoto) return const SizedBox.shrink();
    final t = Theme.of(context);
    final photo = ref.watch(complaintPhotoProvider(complaintId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.image_outlined, size: IconSize.md, color: t.colorScheme.primary),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(
                label,
                style: t.textTheme.labelSmall?.copyWith(letterSpacing: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        photo.when(
          loading: () => const _PhotoFrame(child: _PhotoSkeleton()),
          error: (error, _) => _PhotoProblem(
            failure: error is AppFailure ? error : null,
            onRetry: () => ref.invalidate(complaintPhotoProvider(complaintId)),
          ),
          data: (url) {
            if (url == null) {
              // The row says there is a photo and the server says there is not. That is a
              // disagreement, not an empty state, and saying so plainly beats a blank space
              // the reader would have to guess about.
              return const _PhotoNote(
                icon: Icons.image_not_supported_outlined,
                message: 'The attached photo is no longer in storage.',
              );
            }
            return _PhotoImage(url: url, complaintId: complaintId, label: label);
          },
        ),
      ],
    );
  }
}

/// The image itself: tap to fill the screen.
class _PhotoImage extends StatelessWidget {
  const _PhotoImage({required this.url, required this.complaintId, required this.label});

  final Uri url;
  final String complaintId;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, tap to view full screen',
      child: _PhotoFrame(
        child: InkWell(
          borderRadius: Radii.rCard,
          onTap: () => showComplaintPhoto(context, url: url, label: label),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url.toString(),
                fit: BoxFit.cover,
                // The bytes are a second wait after the URL, and the frame is already sized —
                // so this keeps the same skeleton rather than collapsing to nothing and
                // snapping back.
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const _PhotoSkeleton(),
                errorBuilder: (context, error, _) => const _PhotoNote(
                  icon: Icons.broken_image_outlined,
                  message: 'That photo could not be loaded. Pull down to try again.',
                  inFrame: true,
                ),
              ),
              // The affordance. A picture that opens is not obviously a picture that opens,
              // and there is no hover state on a phone to discover it with.
              Positioned(
                right: Space.xs,
                bottom: Space.xs,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.86),
                    borderRadius: Radii.rControl,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xxs),
                    child: Icon(
                      Icons.fullscreen_rounded,
                      size: IconSize.lg,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bordered, clipped box every state above sits in, so all four are the same shape.
class _PhotoFrame extends StatelessWidget {
  const _PhotoFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      height: _previewHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerLowest,
        borderRadius: Radii.rCard,
        border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      child: child,
    );
  }
}

/// A flat tinted fill, NOT a blur and NOT a shimmer that outlives its frame. Hard rule: no
/// blur anywhere in this app.
class _PhotoSkeleton extends StatelessWidget {
  const _PhotoSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ColoredBox(
      color: t.colorScheme.surfaceContainerHigh,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: IconSize.xl,
          color: t.colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

/// A sentence where the picture would have been.
class _PhotoNote extends StatelessWidget {
  const _PhotoNote({required this.icon, required this.message, this.inFrame = false});

  final IconData icon;
  final String message;

  /// True when this is already inside a [_PhotoFrame] (the image's own errorBuilder).
  final bool inFrame;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final body = Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: IconSize.xl, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(height: Space.xs),
            Text(message, style: t.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
    return inFrame ? body : _PhotoFrame(child: body);
  }
}

/// FAILED and REFUSED, kept apart.
///
/// A refusal gets no Retry: [AppFailure.isRetryable] is false for [AccessDeniedFailure] and
/// [ReadOnlyFailure], and a button that cannot work is worse than no button — it invites the
/// reader to keep pressing something the server has already settled.
class _PhotoProblem extends StatelessWidget {
  const _PhotoProblem({required this.failure, required this.onRetry});

  final AppFailure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final f = failure;
    final refused = f != null && (f.isRefusal || f.needsSignIn);
    final tone = context.tones.resolve(refused ? NivoraColors.warning : NivoraColors.error);

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: context.tones.chipFill(tone),
        borderRadius: Radii.rCard,
        border: Border.all(color: context.tones.chipBorder(tone), width: Strokes.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                refused ? Icons.lock_outline_rounded : Icons.error_outline_rounded,
                size: IconSize.md,
                color: tone,
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  f?.message ?? 'That photo could not be opened.',
                  style: t.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (f == null || f.isRetryable) ...[
            const SizedBox(height: Space.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onRetry, child: const Text('Try again')),
            ),
          ],
        ],
      ),
    );
  }
}

/// The photo, filling the screen, pinchable.
///
/// A ROUTE RATHER THAN A DIALOG, so the system back gesture closes it and it gets its own entry
/// in the navigator — the two things a reader expects of anything that covers the screen.
///
/// NO BLUR behind it. The scrim is the theme's own darkest surface at full opacity, which is
/// what this app uses everywhere a layer has to sit over another one.
Future<void> showComplaintPhoto(
  BuildContext context, {
  required Uri url,
  required String label,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _FullScreenPhoto(url: url, label: label),
    ),
  );
}

class _FullScreenPhoto extends StatelessWidget {
  const _FullScreenPhoto({required this.url, required this.label});

  final Uri url;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: t.colorScheme.surfaceContainerLowest,
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.network(
            url.toString(),
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator()),
            errorBuilder: (context, error, _) => Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(
                'That photo could not be loaded. Close this and try again.',
                style: t.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
