library;

import 'package:flutter/services.dart' show appBuildName, appBuildNumber;

/// WHICH BUILD THIS IS, AND WHETHER A NEWER ONE EXISTS.
///
/// Everything in this file is pure: no network, no plugins, no widgets. The decision that
/// drives the update banner — [decideUpdate] — is a function of two records, so the whole of
/// "does this phone need a new APK?" is testable without an emulator. See
/// test/app_update_test.dart.
///
/// ═══ THE VERSION COMES FROM THE BUILD, NOT FROM A CONSTANT SOMEBODY MAINTAINS ═══
///
/// [InstalledBuild.current] reads `appBuildName` and `appBuildNumber` from
/// `package:flutter/services.dart`. Those are compile-time constants the Flutter TOOL injects
/// as `--dart-define`s from pubspec.yaml's `version:` line on every `flutter run`, `flutter
/// test` and `flutter build` — see flutter_tools/lib/src/runner/flutter_command.dart, which
/// adds `FLUTTER_BUILD_NAME` and `FLUTTER_BUILD_NUMBER` to the dart-defines of every build.
/// Measured on this checkout with Flutter 3.47.1: `1.0.0` and `1` from `version: 1.0.0+1`.
///
/// That matters more than it looks. A hardcoded `const kVersionCode = 1` rots the first time
/// somebody bumps pubspec.yaml and forgets the second edit — and the failure is silent and
/// exactly backwards: the app compares a stale number, decides it is out of date, and nags
/// everyone to install the build they are already running. Reading it from the build makes
/// that impossible, because there is only one number.
///
/// NO NEW DEPENDENCY. package_info_plus would answer the same question by asking Android at
/// runtime, and is NOT a dependency of this project — checked. It would also have to be
/// resolved by Gradle, and this machine cannot reach Maven through its TLS-intercepting
/// antivirus (see nivora_app/scripts/release.sh), so adding a plugin here would risk the
/// release build for a value the framework already hands us for free.

/// The build running right now.
final class InstalledBuild {
  const InstalledBuild({required this.versionName, required this.versionCode});

  /// pubspec.yaml's `version:` before the `+` — "1.0.0". Never null in a real build; the
  /// fallback exists only for the pathological case below.
  final String versionName;

  /// pubspec.yaml's `version:` after the `+`, which Flutter writes into the APK as
  /// `android:versionCode`. NULL means this build could not tell us what it is, and every
  /// caller must treat that as "do not know", never as "0".
  final int? versionCode;

  /// This build, read from the dart-defines the Flutter tool injected.
  ///
  /// Both halves are `String?` because a pubspec with no `version:` line produces neither.
  /// This one has a version, so in practice both are present in every build the release
  /// script will ever produce — but the null arm is real code rather than a `!`, because the
  /// consequence of guessing is a nag screen on a phone that is perfectly up to date.
  static InstalledBuild get current => InstalledBuild(
        versionName: appBuildName ?? 'unknown',
        versionCode: int.tryParse(appBuildNumber ?? ''),
      );

  /// "1.0.0 (build 1)" — what the update sheet shows so a screenshot names the exact build.
  String get label =>
      versionCode == null ? versionName : '$versionName (build $versionCode)';

  @override
  String toString() => 'InstalledBuild($label)';
}

/// The published release, as `public.app_releases` holds it.
///
/// One row, keyed by channel. See db/migrations/2026-09-02-app-releases.sql for why it is a
/// row and not a JSON file on the web app.
final class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.sha256,
    required this.mandatory,
    required this.notes,
  });

  /// The columns to select. Named here so the query and the parser cannot drift.
  static const columns =
      'version_name,version_code,download_url,size_bytes,sha256,mandatory,notes';

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        versionName: json['version_name'] as String,
        versionCode: (json['version_code'] as num).toInt(),
        downloadUrl: json['download_url'] as String?,
        sizeBytes: (json['size_bytes'] as num?)?.toInt(),
        sha256: json['sha256'] as String?,
        mandatory: json['mandatory'] as bool? ?? false,
        notes: json['notes'] as String?,
      );

  final String versionName;
  final int versionCode;

  /// NULL until a binary has been uploaded. A release with no URL is announced to nobody —
  /// see [decideUpdate].
  final String? downloadUrl;
  final int? sizeBytes;
  final String? sha256;
  final bool mandatory;
  final String? notes;

  String get label => '$versionName (build $versionCode)';

  /// "63 MB" — for the line that tells somebody on a metered connection what this costs.
  String? get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// What the app should do about the published release.
///
/// FOUR OUTCOMES, THREE OF WHICH DRAW NOTHING. That is deliberate and it is not the "four
/// distinct states" rule being dodged: this is not a section of a screen that was asked to
/// show data, it is a notice that either has something to say or does not. An app that is up
/// to date must not put a bar across the top of every screen to say so.
enum UpdateStatus {
  /// This build is the published one, or newer than it (a tester running tomorrow's APK).
  upToDate,

  /// A newer build exists and can be downloaded. Dismissible banner.
  available,

  /// A newer build exists, is marked `mandatory`, and has somewhere to download from.
  /// Blocking banner — no dismiss.
  required,

  /// Nothing can be said. Either this build could not name its own version code, or the
  /// published release has no download URL yet, or the check has not answered. Draw nothing:
  /// "an update might exist, we cannot tell you where" is worse than silence.
  unknown,
}

/// THE WHOLE DECISION, in one pure function.
///
/// ═══ IT COMPARES versionCode, AND ONLY versionCode ═══
///
/// Not the version NAME. Android's package manager will only replace an installed APK with one
/// whose `android:versionCode` is strictly higher (and which carries the same signature — see
/// docs/app-distribution.md §5). So versionCode is the number the OPERATING SYSTEM is going to
/// check a minute after the person taps Install. Comparing a dotted name here — where "1.0.10"
/// sorts before "1.0.9" as a string, and where two builds can share a name — would let this
/// banner promise an update that the installer then refuses with "App not installed", which is
/// precisely the confusing error the owner asked us to avoid.
///
/// ═══ WHY A RELEASE WITH NO URL ANNOUNCES NOTHING ═══
///
/// The row can legitimately carry a bumped version_code before the binary is uploaded. Telling
/// somebody an update exists and then having no download to offer is a dead end with a badge
/// on it. [UpdateStatus.unknown] draws nothing, and the install page says "not published yet"
/// on the web side where there is room to explain.
UpdateStatus decideUpdate(InstalledBuild installed, AppRelease? release) {
  if (release == null) return UpdateStatus.unknown;

  final mine = installed.versionCode;
  // This build could not say what it is. Claiming anything about it would be a guess, and the
  // guess that costs something is the wrong one.
  if (mine == null) return UpdateStatus.unknown;

  if (release.versionCode <= mine) return UpdateStatus.upToDate;

  // Newer, but nowhere to get it.
  if (release.downloadUrl == null) return UpdateStatus.unknown;

  return release.mandatory ? UpdateStatus.required : UpdateStatus.available;
}
