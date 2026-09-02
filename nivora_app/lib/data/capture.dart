library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// PICKING AN IMAGE, ONCE, FOR THE WHOLE APP.
///
/// This started life inside the warden's repository, next to the one flow that used it — the
/// registration sheet, which photographs an ID card and optionally the resident. A second flow
/// now needs exactly the same thing: a resident attaching a photo of the leaking tap to a
/// complaint. The ceiling, the compression settings and the "a cancelled pick is not a failure"
/// contract are the same in both, and two copies of them is how one flow ends up uploading
/// 4000px frames after somebody tunes the other.
///
/// So it lives in lib/data, where both features can reach it, and
/// features/warden/data/warden_repository.dart re-exports it so nothing that already imported
/// it from there had to change.
///
/// NOTHING HERE UPLOADS. This side collects bytes; the repositories post them. That split is
/// what lets [CapturedDocument] be constructed in a test with no platform underneath.

/// Where a document came from. Two entry points because a warden at the desk photographs the
/// card in front of them, a warden entering a record later already has the scan — and a
/// resident standing in front of a broken tap is the first case while a resident who
/// photographed it last night is the second.
enum CaptureSource { camera, gallery }

/// One file on its way to a private bucket, held as bytes because that is what has to be
/// base64-encoded into the request body.
///
/// NO PATH, DELIBERATELY. A `File` would tie this to dart:io and make every path that uses it
/// untestable off a device; bytes are what the wire needs and what a test can supply.
final class CapturedDocument {
  const CapturedDocument({required this.bytes, required this.name});

  final Uint8List bytes;

  /// The picker's own file name, for the "Aadhaar.jpg · 214 KB" line under the button. It is
  /// NOT sent: storage.ts chooses the object's path and sniffs its real type from the leading
  /// bytes, because a name and a declared MIME type are claims, not evidence.
  final String name;

  int get sizeBytes => bytes.length;

  /// The per-file ceiling storage.ts enforces after decoding. Checked here too so a warden
  /// learns their scan is too big before four megabytes crawl up a stairwell 3G connection.
  static const maxBytes = 3 * 1024 * 1024;

  bool get isTooLarge => sizeBytes > maxBytes;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).round()} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String toBase64() => base64Encode(bytes);
}

// ─────────────────────────────────────────────────────────────────────────────
// THE DOCUMENT CAPTURE
//
// BEHIND AN INTERFACE BECAUSE IT IS A MethodChannel. `image_picker` asks the platform for a
// camera or a photo picker, and a widget test has no platform on the other end of one:
// constructing the real thing in a test turns the flow that uses it into a hang rather than a
// mistake. Tests override `documentCaptureProvider`.
//
// AND NO BROWSER. The picker opens Android's own photo picker or the camera activity. There is
// no upload page, no signed-URL hand-off and no "finish this on the website" — the bytes go
// into the same JSON body as the rest of the form.
// ─────────────────────────────────────────────────────────────────────────────

/// Picks one image and hands back its bytes. One implementation for the device, one for tests.
abstract interface class DocumentCapture {
  /// Completes with null when the person backed out of the picker — which is not an error and
  /// must not be reported as one.
  Future<CapturedDocument?> pick(CaptureSource source);
}

/// The real one.
///
/// THE COMPRESSION IS NOT OPTIONAL. A modern phone camera produces 4–8 MB per frame and
/// storage.ts refuses anything over 3 MB after decoding, so an uncompressed capture would fail
/// at the server after the whole file had already been pushed up whatever connection a
/// stairwell offers. `maxWidth` and `imageQuality` are applied by the plugin natively, before
/// the bytes ever reach Dart — 1600px at quality 70 is a legible photograph of an ID card, and
/// of a leaking tap, at roughly 200–400 KB. docs/edge-functions.md §7 says to compress on the
/// device; this is that.
///
/// ONE SETTING FOR BOTH CALLERS. A complaint photo does not need a second, looser profile: a
/// warden looking at a dripping pipe on a 6" screen gains nothing from 4000px, and this project
/// is on Supabase's free tier, where every megabyte stored and every megabyte served is
/// somebody's actual bill.
final class PluginDocumentCapture implements DocumentCapture {
  PluginDocumentCapture([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<CapturedDocument?> pick(CaptureSource source) async {
    final file = await _picker.pickImage(
      source: source == CaptureSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 70,
    );
    if (file == null) return null;
    return CapturedDocument(bytes: await file.readAsBytes(), name: file.name);
  }
}
