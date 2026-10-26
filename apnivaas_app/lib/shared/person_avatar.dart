/// A person's face: their photo when there is one and it can be read, their initials otherwise.
///
/// Photos live in the private `avatars` bucket and are opened through a 60-second signed URL
/// (docs/self-signup-api.md §3). Storage decides who may read whose photo; when it refuses, or
/// the URL has expired, or the image fails to load, the initials stay — never a broken image.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import '../core/theme/tokens.dart';
import '../data/people_providers.dart';
import '../data/repositories/people_repository.dart' show Buckets;
import 'clay/app_header.dart' show HeaderAvatar;
import 'clay/list_row.dart' show InitialsDisc;

/// The signed URL for an avatar path, or null while it loads or when it was refused.
String? watchAvatarUrl(WidgetRef ref, String? path) {
  if (path == null || path.isEmpty) return null;
  return ref.watch(signedUrlProvider((bucket: Buckets.avatars, path: path))).value;
}

class PersonAvatar extends ConsumerWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.userId,
    this.avatarPath,
    this.size = AvatarSize.list,
    this.semanticLabel,
  });

  final String name;

  /// Looked up through [avatarDirectoryProvider] (one query per frame for a whole roster) when
  /// [avatarPath] is not already known.
  final String? userId;
  final String? avatarPath;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var path = avatarPath;
    final id = userId;
    if (path == null && id != null && id.isNotEmpty) {
      path = ref.watch(avatarDirectoryProvider.select((m) => m[id]));
      ref.read(avatarDirectoryProvider.notifier).request(id);
    }
    final fallback = InitialsDisc(name: name, size: size, semanticLabel: semanticLabel);
    final url = watchAvatarUrl(ref, path);
    if (url == null) return fallback;
    final photo = ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        frameBuilder: (_, child, frame, sync) => frame == null && !sync ? fallback : child,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: photo)
        : Semantics(label: semanticLabel, image: true, child: ExcludeSemantics(child: photo));
  }
}

/// The signed-in person's own face, at any size — the profile sheet, a profile card.
class MyAvatar extends ConsumerWidget {
  const MyAvatar({super.key, required this.name, this.size = AvatarSize.list, this.semanticLabel});

  final String name;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PersonAvatar(
        name: name,
        avatarPath: ref.watch(myAvatarPathProvider).value,
        size: size,
        semanticLabel: semanticLabel,
      );
}

/// [HeaderAvatar] for the signed-in person, with their photo when they have one.
class MyHeaderAvatar extends ConsumerWidget {
  const MyHeaderAvatar({super.key, required this.onTap, this.semanticLabel = 'Your account'});

  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(sessionProvider.select((s) => s?.fullName.trim() ?? ''));
    final url = watchAvatarUrl(ref, ref.watch(myAvatarPathProvider).value);
    return HeaderAvatar(
      name: name.isEmpty ? null : name,
      onTap: onTap,
      semanticLabel: semanticLabel,
      image: url == null ? null : NetworkImage(url),
    );
  }
}
