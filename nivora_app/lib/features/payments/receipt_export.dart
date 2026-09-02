/// Turning the receipt on screen into a file the resident can keep.
///
/// ═══ WHAT THIS DOES, LITERALLY ═══
/// It captures the [RepaintBoundary] the paper is wrapped in, encodes it as a PNG at three
/// times the screen's density, writes it into the app's own temporary directory, and hands
/// that file to the platform's share sheet. The image is the same sheet the resident is
/// looking at — not a re-rendering, not a template filled in a second time — so it cannot
/// disagree with what was on screen.
///
/// ═══ NO BROWSER, AND NOTHING LEAVES THE DEVICE ═══
/// The share sheet is an Android/iOS system chooser, not a web page: no WebView, no
/// `url_launcher`, no upload. The file is written locally and the OS passes a content URI to
/// whichever app the resident picks. "Save to Files" and "Save to Drive" appear in that same
/// chooser, which is how a receipt gets saved rather than sent.
///
/// ═══ WHY THERE IS AN INTERFACE IN FRONT OF IT ═══
/// The same reason [DocumentCapture] has one. `share_plus` and `path_provider` are
/// MethodChannel plugins and a widget test has no platform to answer them, so the export goes
/// through [receiptExporterProvider] and a test can substitute a fake and still drive the whole
/// receipt screen — including the failure branches, which are the ones worth pinning down.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'receipt.dart';

/// What became of an export. Three outcomes, because they are three different things to say.
sealed class ReceiptExportResult {
  const ReceiptExportResult();
}

/// The sheet opened and the resident sent or saved the receipt.
final class ReceiptShared extends ReceiptExportResult {
  const ReceiptShared();
}

/// The sheet opened and they closed it without choosing anything. Nothing went wrong and they
/// must not be told it did.
final class ReceiptShareDismissed extends ReceiptExportResult {
  const ReceiptShareDismissed();
}

/// The file could not be made or the sheet could not be opened.
final class ReceiptExportFailed extends ReceiptExportResult {
  const ReceiptExportFailed(this.message);

  /// Written for the resident, and specific about what to do next.
  final String message;
}

/// Captures a receipt and offers it to the platform.
abstract interface class ReceiptExporter {
  /// Capture the boundary [paperKey] is attached to and open the share sheet.
  ///
  /// [origin] anchors the sheet to the button that opened it, which iPads require and every
  /// other platform ignores.
  Future<ReceiptExportResult> share({
    required GlobalKey paperKey,
    required Receipt receipt,
    Rect? origin,
  });
}

/// The real one.
final class ImageReceiptExporter implements ReceiptExporter {
  const ImageReceiptExporter();

  /// Three times the logical size. A receipt is read at arm's length and sometimes printed;
  /// 1x produces something that looks soft the moment anyone zooms in, and beyond 3x the file
  /// grows faster than the legibility does.
  static const pixelRatio = 3.0;

  @override
  Future<ReceiptExportResult> share({
    required GlobalKey paperKey,
    required Receipt receipt,
    Rect? origin,
  }) async {
    final Uint8List png;
    try {
      png = await _capture(paperKey);
    } on _CaptureFailure catch (failure) {
      return ReceiptExportFailed(failure.message);
    }

    final String path;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, '${receipt.fileStem}.png'));
      await file.writeAsBytes(png, flush: true);
      path = file.path;
    } catch (_) {
      return const ReceiptExportFailed(
        'Nivora could not save the receipt to this phone. Free up some storage and try again.',
      );
    }

    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'image/png', name: '${receipt.fileStem}.png')],
          fileNameOverrides: ['${receipt.fileStem}.png'],
          subject: 'Rent receipt · ${receiptMonth(receipt.periodMonth)}',
          sharePositionOrigin: origin,
        ),
      );
      return switch (result.status) {
        ShareResultStatus.dismissed => const ReceiptShareDismissed(),
        // `unavailable` means the platform shared it but could not report where to. That is a
        // success the plugin cannot confirm, and calling it a failure would be a lie in the
        // more alarming direction.
        ShareResultStatus.success || ShareResultStatus.unavailable => const ReceiptShared(),
      };
    } catch (_) {
      return const ReceiptExportFailed(
        'This phone would not open the share sheet. The receipt is still on your rent screen.',
      );
    }
  }

  /// The pixels behind [paperKey].
  static Future<Uint8List> _capture(GlobalKey paperKey) async {
    final object = paperKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) {
      throw const _CaptureFailure(
        'The receipt is not on screen yet. Wait for it to finish printing and try again.',
      );
    }

    // In debug builds `toImage` asserts if the boundary still needs painting — which it does
    // for one frame after any rebuild. Waiting for the frame to end is the fix; retrying blind
    // is not.
    if (object.debugNeedsPaint) {
      await WidgetsBinding.instance.endOfFrame;
    }

    final image = await object.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const _CaptureFailure(
          'Nivora could not turn this receipt into an image. Try again in a moment.',
        );
      }
      return data.buffer.asUint8List();
    } finally {
      // The image holds native memory until it is disposed, and a receipt at 3x is several
      // megabytes of it.
      image.dispose();
    }
  }
}

class _CaptureFailure implements Exception {
  const _CaptureFailure(this.message);
  final String message;
}

/// Replaceable, so the receipt screen can be driven in a test with no platform channels.
final receiptExporterProvider =
    Provider<ReceiptExporter>((ref) => const ImageReceiptExporter());
