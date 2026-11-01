/// The Play Store and Google Maps, opened as apps (round 6).
///
/// MainActivity's `apnivaas/apps` channel builds only `market://` and `geo:` intents, so nothing
/// here can land in a browser: "Update now" opens this app's listing in the Play Store app, and
/// a PG's pin opens in Google Maps (or another maps app when Google Maps is missing).
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Google Play's answer to "is a newer build of this app published?".
final class PlayUpdate {
  const PlayUpdate({required this.available, this.versionCode});

  /// Nothing to say: not installed from Play, no network, or already the newest.
  static const none = PlayUpdate(available: false);

  final bool available;

  /// The version code Play offers, when it says one.
  final int? versionCode;
}

abstract interface class AppsLauncher {
  Future<PlayUpdate> checkUpdate();

  /// True when the Play Store app opened on this app's listing.
  Future<bool> openStore();

  /// True when a maps app opened on the pin.
  Future<bool> openMap({required double latitude, required double longitude, String? label});
}

final class ChannelAppsLauncher implements AppsLauncher {
  const ChannelAppsLauncher();

  static const _channel = MethodChannel('apnivaas/apps');

  @override
  Future<PlayUpdate> checkUpdate() async {
    try {
      // No timeout timer: MainActivity answers on success, on failure and on a throw, and a
      // check that never answers simply never offers anything.
      final raw = await _channel.invokeMapMethod<String, Object?>('checkUpdate');
      if (raw?['available'] != true) return PlayUpdate.none;
      final code = raw?['versionCode'];
      return PlayUpdate(available: true, versionCode: code is int ? code : null);
    } catch (_) {
      // An update check that cannot answer is silence, never an error on screen.
      return PlayUpdate.none;
    }
  }

  @override
  Future<bool> openStore() async {
    try {
      return await _channel.invokeMethod<bool>('openStore') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> openMap({required double latitude, required double longitude, String? label}) async {
    try {
      return await _channel.invokeMethod<bool>('openMap', {
            'lat': latitude,
            'lng': longitude,
            'label': ?label,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final appsLauncherProvider = Provider<AppsLauncher>((_) => const ChannelAppsLauncher());
