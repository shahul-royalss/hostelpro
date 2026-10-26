/// The two device capabilities sign-up needs: a photo (camera or gallery) and an approximate
/// position. Each is an interface so a widget test can hand over bytes or a position without a
/// plugin, exactly like [DocumentCapture] in data/capture.dart.
///
/// BOTH ASK IN WORDS FIRST. The system dialog is never the first thing a person sees: the
/// caller passes an `explain` callback that shows the app's own sentence about why, and the
/// system prompt is raised only after a yes. A permission already granted asks nothing.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../capture.dart' show CaptureSource;
import '../models/failure.dart';

export '../capture.dart' show CaptureSource;

/// Shows the app's own explanation and answers whether the person agreed to continue.
typedef ExplainFirst = Future<bool> Function();

/// A picked image, already shrunk by image_picker. The phone copy has been deleted.
final class PickedImage {
  const PickedImage({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}

abstract interface class SignupPhotoSource {
  /// Null when the person closed the picker or said no to the explanation.
  ///
  /// [forDocument] keeps more pixels (an ID must stay legible); a profile photo is cropped to
  /// 512 px afterwards, so it is asked for at 1024.
  Future<PickedImage?> pick(
    CaptureSource source, {
    required ExplainFirst explainCamera,
    bool forDocument = false,
  });
}

final class PluginSignupPhotoSource implements SignupPhotoSource {
  PluginSignupPhotoSource([ImagePicker? picker]) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  static String get _settingsPath => defaultTargetPlatform == TargetPlatform.iOS
      ? 'Settings → Apnivaas → Camera'
      : 'Settings → Apps → Apnivaas → Permissions → Camera';

  @override
  Future<PickedImage?> pick(
    CaptureSource source, {
    required ExplainFirst explainCamera,
    bool forDocument = false,
  }) async {
    if (source == CaptureSource.camera) {
      final status = await Permission.camera.status;
      if (status.isPermanentlyDenied) {
        throw AccessDeniedFailure(
          'Apnivaas cannot open the camera. Turn it on in $_settingsPath, then try again. '
          'You can also choose an existing photo.',
        );
      }
      if (!status.isGranted && !status.isLimited) {
        if (!await explainCamera()) return null;
        final asked = await Permission.camera.request();
        if (!asked.isGranted && !asked.isLimited) {
          throw const AccessDeniedFailure(
            'Apnivaas needs the camera to take this photo. You can choose an existing photo '
            'instead.',
          );
        }
      }
    }
    // The compression IS these settings: image_picker re-encodes to this size and quality on
    // the platform side, so nothing full-size crosses into Dart.
    final file = await _picker.pickImage(
      source: source == CaptureSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: forDocument ? 1600 : 1024,
      maxHeight: forDocument ? 1600 : 1024,
      imageQuality: forDocument ? 75 : 85,
      preferredCameraDevice: forDocument ? CameraDevice.rear : CameraDevice.front,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    // THE PHONE COPY IS NEVER KEPT (docs/self-signup-onboarding-spec.md, Flow 7): image_picker
    // writes its result into the app cache, and the bytes are in memory now.
    try {
      await File(file.path).delete();
    } catch (e) {
      debugPrint('picked image cleanup: $e');
    }
    return PickedImage(bytes: bytes, name: file.name);
  }
}

final signupPhotoSourceProvider = Provider<SignupPhotoSource>((_) => PluginSignupPhotoSource());

// ─────────────────────────────────────────────────────────────────────────────
// LOCATION (precise since round 3)
// ─────────────────────────────────────────────────────────────────────────────

sealed class LocationOutcome {
  const LocationOutcome();
}

final class LocationFix extends LocationOutcome {
  const LocationFix(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

/// The person said no to the explanation. Nothing to say; search is right there.
final class LocationSkipped extends LocationOutcome {
  const LocationSkipped();
}

final class LocationUnavailable extends LocationOutcome {
  const LocationUnavailable(this.message);
  final String message;
}

/// One location fix, asked for once (round 3 R4: precise).
abstract interface class DeviceLocator {
  Future<LocationOutcome> locate({required ExplainFirst explain});
}

/// Old names, kept so callers written against round 2 still compile.
typedef CoarseLocator = DeviceLocator;

abstract final class LocationWords {
  static const denied =
      'Location is off for Apnivaas, so you can search by name or city instead.';
  static const deniedForever =
      'Location is off for Apnivaas. You can turn it on in Settings → Apps → Apnivaas → '
      'Permissions → Location, or search by name or city instead.';
  static const serviceOff =
      "Your phone's location is switched off. Turn it on, or search by name or city instead.";
  static const noFix =
      "We couldn't find your location just now. Try again, or search by name or city instead.";
}

/// geolocator at HIGH accuracy (ACCESS_FINE_LOCATION), one fix, no stream.
///
/// THE "TURN ON LOCATION" POPUP: geolocator's fused client calls Play services
/// `SettingsClient.checkLocationSettings` and, when location is off, shows the system
/// resolution dialog in the app (`startResolutionForResult`). So this never bails out on
/// `isLocationServiceEnabled()`; it only allows longer for the person to answer the dialog.
/// Declining surfaces as [LocationServiceDisabledException] → [LocationWords.serviceOff].
final class GeolocatorDeviceLocator implements DeviceLocator {
  const GeolocatorDeviceLocator();

  static const _fixTimeout = Duration(seconds: 25);
  static const _withDialogTimeout = Duration(seconds: 60);

  @override
  Future<LocationOutcome> locate({required ExplainFirst explain}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        return const LocationUnavailable(LocationWords.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        if (!await explain()) return const LocationSkipped();
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationUnavailable(LocationWords.denied);
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationUnavailable(LocationWords.deniedForever);
      }
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      final position = await Geolocator.getCurrentPosition(
        locationSettings: defaultTargetPlatform == TargetPlatform.android
            ? AndroidSettings(accuracy: LocationAccuracy.high)
            : const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(serviceOn ? _fixTimeout : _withDialogTimeout);
      return LocationFix(position.latitude, position.longitude);
    } on LocationServiceDisabledException {
      return const LocationUnavailable(LocationWords.serviceOff);
    } catch (e) {
      debugPrint('location failed: ${e.runtimeType} $e');
      return const LocationUnavailable(LocationWords.noFix);
    }
  }
}

final deviceLocatorProvider = Provider<DeviceLocator>((_) => const GeolocatorDeviceLocator());

/// Old name (round 2).
final coarseLocatorProvider = deviceLocatorProvider;
