/// PG cover photos for the `pg-media` bucket: JPEG, longest side at most 1600 px, under 2 MB
/// (docs/round3-api.md §5.1). Always re-encoded, which also drops EXIF (a GPS tag must not
/// ride along on a photo other people see). Logos use [squareAvatarJpeg] (512 px square).
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'jpeg_encoder.dart';

const pgPhotoMaxSide = 1600;
const pgPhotoMaxBytes = 2 * 1024 * 1024;

/// The output size for an image of [width] × [height]: never upscaled, longest side ≤ [maxSide].
({int width, int height}) fitWithin(int width, int height, {int maxSide = pgPhotoMaxSide}) {
  final longest = math.max(width, height);
  if (longest <= maxSide) return (width: math.max(1, width), height: math.max(1, height));
  final scale = maxSide / longest;
  return (
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

/// Throws [FormatException] when the bytes are not an image this phone can decode.
Future<Uint8List> pgCoverJpeg(Uint8List source, {int quality = 80}) async {
  const unreadable = FormatException('That photo could not be read. Try another one.');
  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(source);
  } catch (_) {
    throw unreadable;
  }
  final image = (await codec.getNextFrame()).image;
  final out = fitWithin(image.width, image.height);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, out.width.toDouble(), out.height.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final scaled = await recorder.endRecording().toImage(out.width, out.height);
  final raw = await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  scaled.dispose();
  codec.dispose();
  if (raw == null) throw unreadable;

  final rgba = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
  final w = out.width, h = out.height;
  var q = quality;
  var jpeg = await Isolate.run(() => JpegEncoder.encode(rgba, w, h, quality: q));
  while (jpeg.length > pgPhotoMaxBytes && q > 40) {
    q -= 15;
    final next = q;
    jpeg = await Isolate.run(() => JpegEncoder.encode(rgba, w, h, quality: next));
  }
  if (jpeg.length > pgPhotoMaxBytes) {
    throw const FormatException('That photo is too large. Try another one.');
  }
  return jpeg;
}
