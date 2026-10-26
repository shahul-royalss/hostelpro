/// "Change photo", for every role: camera or gallery, a square JPEG of at most 512 px, uploaded
/// to the caller's own `avatars/<uid>/avatar/<uuid>.jpg` and set with `me_set_avatar`
/// (docs/self-signup-api.md §3). Or "Remove photo", which is `me_set_avatar(null)`.
///
/// The storage policy refuses any other path and the RPC checks the object exists, so nothing
/// here is trusted by the server; the refusal sentences are shown as they are.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../data/device/signup_device.dart';
import '../../data/models/failure.dart';
import '../../data/people_providers.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/signup_repository.dart';
import '../../shared/clay/clay.dart';
import '../signup/signup_widgets.dart' show askInWords;
import '../signup/tenant/tenant_details_screen.dart' show avatarEncoderProvider;

enum _PhotoChoice { camera, gallery, remove }

/// Runs the whole change. Safe to call from a sheet that may close meanwhile: it reads the
/// providers through the container, not through a widget's ref.
Future<void> changeMyPhoto(BuildContext context, {required bool hasPhoto}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);

  final choice = await showApnivaasSheet<_PhotoChoice>(
    context: context,
    title: 'Profile photo',
    subtitle: 'Your owner, warden and the people you ask to join can see it.',
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_rounded),
          title: const Text('Take a photo'),
          onTap: () => Navigator.of(ctx).pop(_PhotoChoice.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_rounded),
          title: const Text('Choose from gallery'),
          onTap: () => Navigator.of(ctx).pop(_PhotoChoice.gallery),
        ),
        if (hasPhoto)
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Remove photo'),
            onTap: () => Navigator.of(ctx).pop(_PhotoChoice.remove),
          ),
        const SizedBox(height: Space.sm),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;

  void say(String text) => messenger?.showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );

  final uid = container.read(sessionProvider)?.userId;
  try {
    if (choice == _PhotoChoice.remove) {
      await container.read(peopleApiProvider).removeMyAvatar();
      if (uid != null) container.read(avatarDirectoryProvider.notifier).put(uid, null);
      container.invalidate(myAvatarPathProvider);
      say('Photo removed');
      return;
    }
    final picked = await container.read(signupPhotoSourceProvider).pick(
          choice == _PhotoChoice.camera ? CaptureSource.camera : CaptureSource.gallery,
          explainCamera: () async => context.mounted &&
              await askInWords(
                context,
                title: 'Use the camera?',
                message: 'Apnivaas will ask to use your camera so you can take your photo now. '
                    'It is used only for the picture you take. You can choose an existing photo '
                    'instead.',
              ),
        );
    if (picked == null) return;
    say('Uploading your photo…');
    final jpeg = await container.read(avatarEncoderProvider)(picked.bytes);
    final path = await container.read(signupApiProvider).uploadAvatar(jpeg);
    if (uid != null) container.read(avatarDirectoryProvider.notifier).put(uid, path);
    container.invalidate(myAvatarPathProvider);
    messenger?.hideCurrentSnackBar();
    say('Photo updated');
  } catch (e) {
    messenger?.hideCurrentSnackBar();
    say(switch (e) {
      SignupFailure(:final message) => message,
      AppFailure(:final message) => message,
      FormatException(:final message) => message,
      _ => 'That photo could not be used. Please try again.',
    });
  }
}

/// The face and the "Change photo" link under it, for a profile sheet or card.
class ChangePhotoButton extends ConsumerWidget {
  const ChangePhotoButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPhoto = ref.watch(myAvatarPathProvider).value != null;
    return TextButton.icon(
      onPressed: () => changeMyPhoto(context, hasPhoto: hasPhoto),
      icon: const Icon(Icons.photo_camera_outlined, size: IconSize.md),
      label: const Text('Change photo'),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
