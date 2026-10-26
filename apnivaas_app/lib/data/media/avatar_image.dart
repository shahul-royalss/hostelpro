/// Turns a picked photo into what the `avatars` bucket accepts: a square JPEG of at most
/// 512 px and at most 1 MB (docs/self-signup-api.md §3).
///
/// The crop is drawn with dart:ui (centre square, scaled down); the JPEG is encoded by
/// [JpegEncoder] on a background isolate. image_picker has already shrunk and recompressed the
/// file it hands over, so the decode here is of a ~1000 px image, not a 12 MP one.
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'jpeg_encoder.dart';

const avatarMaxSide = 512;
const avatarMaxBytes = 1024 * 1024;

/// The centre square of an image of [width] × [height], as (left, top, side).
({double left, double top, double side}) centreSquare(int width, int height) {
  final side = math.min(width, height).toDouble();
  return (left: (width - side) / 2, top: (height - side) / 2, side: side);
}

/// The output edge for a square of [side] px: never upscaled, never above [avatarMaxSide].
int avatarEdgeFor(int side) => math.max(1, math.min(side, avatarMaxSide));

/// Decode [source], crop the centre square, scale to at most 512 px and encode as JPEG.
///
/// Throws [FormatException] when the bytes are not an image this phone can decode.
Future<Uint8List> squareAvatarJpeg(Uint8List source, {int quality = 82}) async {
  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(source);
  } catch (_) {
    throw const FormatException('That photo could not be read. Try another one.');
  }
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final crop = centreSquare(image.width, image.height);
  final edge = avatarEdgeFor(crop.side.round());

  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    ui.Rect.fromLTWH(crop.left, crop.top, crop.side, crop.side),
    ui.Rect.fromLTWH(0, 0, edge.toDouble(), edge.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final squared = await recorder.endRecording().toImage(edge, edge);
  final raw = await squared.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  squared.dispose();
  codec.dispose();
  if (raw == null) throw const FormatException('That photo could not be read. Try another one.');

  final rgba = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
  var q = quality;
  var jpeg = await Isolate.run(() => JpegEncoder.encode(rgba, edge, edge, quality: q));
  // 512² at q82 is ~60–120 KB, so this loop is a guard, not a path anyone takes.
  while (jpeg.length > avatarMaxBytes && q > 40) {
    q -= 15;
    final next = q;
    jpeg = await Isolate.run(() => JpegEncoder.encode(rgba, edge, edge, quality: next));
  }
  return jpeg;
}
