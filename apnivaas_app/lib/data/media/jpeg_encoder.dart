/// A small baseline JPEG encoder (8-bit, 4:4:4, the standard Annex K tables).
///
/// WHY THIS EXISTS: the `avatars` bucket takes `image/jpeg` only (docs/self-signup-api.md §3),
/// the square crop is drawn with dart:ui, and dart:ui can encode PNG but not JPEG. Adding an
/// image package for one 512px square was the alternative; this is ~250 lines of well-known
/// arithmetic (the AAN forward DCT and the standard Huffman tables) with no dependency.
///
/// Pure Dart and synchronous: callers run it off the UI isolate (see avatar_image.dart).
library;

import 'dart:typed_data';

abstract final class JpegEncoder {
  /// Encodes [rgba] (width × height × 4 bytes, alpha ignored) at [quality] 1–100.
  static Uint8List encode(Uint8List rgba, int width, int height, {int quality = 82}) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      throw ArgumentError('rgba does not hold a ${width}x$height image');
    }
    return _Encoder(quality.clamp(1, 100)).run(rgba, width, height);
  }
}

const _zigzag = <int>[
  0, 1, 5, 6, 14, 15, 27, 28, 2, 4, 7, 13, 16, 26, 29, 42, 3, 8, 12, 17, 25, 30, 41, 43, 9, 11, //
  18, 24, 31, 40, 44, 53, 10, 19, 23, 32, 39, 45, 52, 54, 20, 22, 33, 38, 46, 51, 55, 60, 21, 34,
  37, 47, 50, 56, 59, 61, 35, 36, 48, 49, 57, 58, 62, 63,
];

const _yQuant = <int>[
  16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56, //
  14, 17, 22, 29, 51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113,
  92, 49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
];

const _uvQuant = <int>[
  17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99, //
  47, 66, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
];

const _dcLumCounts = <int>[0, 0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0];
const _dcValues = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
const _acLumCounts = <int>[0, 0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d];
const _acLumValues = <int>[
  0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, //
  0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
  0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
  0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
  0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
  0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
  0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
  0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
  0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
  0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
  0xf9, 0xfa,
];
const _dcChromCounts = <int>[0, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0];
const _acChromCounts = <int>[0, 0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77];
const _acChromValues = <int>[
  0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, //
  0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0,
  0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26,
  0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
  0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
  0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
  0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5,
  0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3,
  0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
  0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
  0xf9, 0xfa,
];

const _aasf = <double>[
  1.0, 1.387039845, 1.306562965, 1.175875602, 1.0, 0.785694958, 0.541196100, 0.275899379, //
];

/// A Huffman table: code and length per symbol.
class _Huff {
  _Huff(List<int> counts, List<int> values) {
    var code = 0;
    var pos = 0;
    for (var len = 1; len <= 16; len++) {
      for (var j = 0; j < counts[len]; j++) {
        codes[values[pos]] = code;
        lengths[values[pos]] = len;
        pos++;
        code++;
      }
      code <<= 1;
    }
  }

  final codes = List<int>.filled(256, 0);
  final lengths = List<int>.filled(256, 0);
}

class _Encoder {
  _Encoder(int quality) {
    final sf = quality < 50 ? 5000 ~/ quality : 200 - quality * 2;
    for (var i = 0; i < 64; i++) {
      _yTable[_zigzag[i]] = ((_yQuant[i] * sf + 50) ~/ 100).clamp(1, 255);
      _uvTable[_zigzag[i]] = ((_uvQuant[i] * sf + 50) ~/ 100).clamp(1, 255);
    }
    var k = 0;
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        _fdY[k] = 1.0 / (_yTable[_zigzag[k]] * _aasf[row] * _aasf[col] * 8.0);
        _fdUV[k] = 1.0 / (_uvTable[_zigzag[k]] * _aasf[row] * _aasf[col] * 8.0);
        k++;
      }
    }
  }

  final _yTable = List<int>.filled(64, 0);
  final _uvTable = List<int>.filled(64, 0);
  final _fdY = Float64List(64);
  final _fdUV = Float64List(64);
  final _dcY = _Huff(_dcLumCounts, _dcValues);
  final _acY = _Huff(_acLumCounts, _acLumValues);
  final _dcUV = _Huff(_dcChromCounts, _dcValues);
  final _acUV = _Huff(_acChromCounts, _acChromValues);

  final _out = BytesBuilder(copy: false);
  int _byte = 0;
  int _bitPos = 7;

  void _put(int b) => _out.addByte(b & 0xff);
  void _word(int w) {
    _put(w >> 8);
    _put(w);
  }

  void _bits(int value, int length) {
    for (var p = length - 1; p >= 0; p--) {
      if ((value >> p) & 1 == 1) _byte |= 1 << _bitPos;
      _bitPos--;
      if (_bitPos < 0) {
        _put(_byte);
        if (_byte == 0xff) _put(0); // byte stuffing
        _byte = 0;
        _bitPos = 7;
      }
    }
  }

  Uint8List run(Uint8List rgba, int width, int height) {
    _word(0xFFD8); // SOI
    // APP0 / JFIF
    _word(0xFFE0);
    _word(16);
    for (final c in 'JFIF'.codeUnits) {
      _put(c);
    }
    for (final b in const [0, 1, 1, 0, 0, 1, 0, 1, 0, 0]) {
      _put(b);
    }
    // DQT
    _word(0xFFDB);
    _word(132);
    _put(0);
    for (final v in _yTable) {
      _put(v);
    }
    _put(1);
    for (final v in _uvTable) {
      _put(v);
    }
    // SOF0
    _word(0xFFC0);
    _word(17);
    _put(8);
    _word(height);
    _word(width);
    _put(3);
    for (final c in const [
      [1, 0x11, 0],
      [2, 0x11, 1],
      [3, 0x11, 1],
    ]) {
      c.forEach(_put);
    }
    // DHT
    _word(0xFFC4);
    _word(0x01A2);
    void table(int id, List<int> counts, List<int> values) {
      _put(id);
      for (var i = 1; i <= 16; i++) {
        _put(counts[i]);
      }
      values.forEach(_put);
    }

    table(0x00, _dcLumCounts, _dcValues);
    table(0x10, _acLumCounts, _acLumValues);
    table(0x01, _dcChromCounts, _dcValues);
    table(0x11, _acChromCounts, _acChromValues);
    // SOS
    _word(0xFFDA);
    _word(12);
    for (final b in const [3, 1, 0x00, 2, 0x11, 3, 0x11, 0x00, 0x3f, 0x00]) {
      _put(b);
    }

    final yDu = Float64List(64);
    final uDu = Float64List(64);
    final vDu = Float64List(64);
    var dcY = 0, dcU = 0, dcV = 0;
    for (var by = 0; by < height; by += 8) {
      for (var bx = 0; bx < width; bx += 8) {
        for (var i = 0; i < 64; i++) {
          final x = (bx + (i & 7)).clamp(0, width - 1);
          final y = (by + (i >> 3)).clamp(0, height - 1);
          final p = (y * width + x) * 4;
          final r = rgba[p].toDouble(), g = rgba[p + 1].toDouble(), b = rgba[p + 2].toDouble();
          yDu[i] = 0.29900 * r + 0.58700 * g + 0.11400 * b - 128;
          uDu[i] = -0.16874 * r - 0.33126 * g + 0.50000 * b;
          vDu[i] = 0.50000 * r - 0.41869 * g - 0.08131 * b;
        }
        dcY = _block(yDu, _fdY, dcY, _dcY, _acY);
        dcU = _block(uDu, _fdUV, dcU, _dcUV, _acUV);
        dcV = _block(vDu, _fdUV, dcV, _dcUV, _acUV);
      }
    }
    if (_bitPos >= 0 && _bitPos < 7) _bits((1 << (_bitPos + 1)) - 1, _bitPos + 1);
    _word(0xFFD9); // EOI
    return _out.takeBytes();
  }

  /// The magnitude category of [v]: the number of bits in |v|.
  static int _category(int v) {
    var a = v.abs();
    var n = 0;
    while (a > 0) {
      n++;
      a >>= 1;
    }
    return n;
  }

  void _value(int v, int cat) => _bits(v >= 0 ? v : v + (1 << cat) - 1, cat);

  int _block(Float64List d, Float64List fd, int prevDc, _Huff dc, _Huff ac) {
    _fdct(d);
    final du = List<int>.filled(64, 0);
    for (var i = 0; i < 64; i++) {
      final q = d[i] * fd[i];
      du[_zigzag[i]] = q > 0 ? (q + 0.5).toInt() : (q - 0.5).toInt();
    }
    final diff = du[0] - prevDc;
    final dcCat = _category(diff);
    _bits(dc.codes[dcCat], dc.lengths[dcCat]);
    if (dcCat > 0) _value(diff, dcCat);

    var end = 63;
    while (end > 0 && du[end] == 0) {
      end--;
    }
    var i = 1;
    while (i <= end) {
      final start = i;
      while (du[i] == 0 && i <= end) {
        i++;
      }
      var zeros = i - start;
      while (zeros >= 16) {
        _bits(ac.codes[0xF0], ac.lengths[0xF0]);
        zeros -= 16;
      }
      final cat = _category(du[i]);
      final sym = (zeros << 4) + cat;
      _bits(ac.codes[sym], ac.lengths[sym]);
      _value(du[i], cat);
      i++;
    }
    if (end != 63) _bits(ac.codes[0x00], ac.lengths[0x00]);
    return du[0];
  }

  /// The AAN forward DCT, in place, rows then columns.
  static void _fdct(Float64List data) {
    for (var pass = 0; pass < 2; pass++) {
      final step = pass == 0 ? 1 : 8;
      for (var i = 0; i < 8; i++) {
        final o = pass == 0 ? i * 8 : i;
        final d0 = data[o], d1 = data[o + step], d2 = data[o + 2 * step];
        final d3 = data[o + 3 * step], d4 = data[o + 4 * step], d5 = data[o + 5 * step];
        final d6 = data[o + 6 * step], d7 = data[o + 7 * step];
        final t0 = d0 + d7, t7 = d0 - d7, t1 = d1 + d6, t6 = d1 - d6;
        final t2 = d2 + d5, t5 = d2 - d5, t3 = d3 + d4, t4 = d3 - d4;
        var t10 = t0 + t3;
        final t13 = t0 - t3;
        var t11 = t1 + t2;
        var t12 = t1 - t2;
        data[o] = t10 + t11;
        data[o + 4 * step] = t10 - t11;
        final z1 = (t12 + t13) * 0.707106781;
        data[o + 2 * step] = t13 + z1;
        data[o + 6 * step] = t13 - z1;
        t10 = t4 + t5;
        t11 = t5 + t6;
        t12 = t6 + t7;
        final z5 = (t10 - t12) * 0.382683433;
        final z2 = 0.541196100 * t10 + z5;
        final z4 = 1.306562965 * t12 + z5;
        final z3 = t11 * 0.707106781;
        final z11 = t7 + z3, z13 = t7 - z3;
        data[o + 5 * step] = z13 + z2;
        data[o + 3 * step] = z13 - z2;
        data[o + step] = z11 + z4;
        data[o + 7 * step] = z11 - z4;
      }
    }
  }
}
