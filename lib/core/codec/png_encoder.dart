import 'dart:typed_data';

import 'package:archive/archive.dart';

const int _m32 = 0xFFFFFFFF;

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) & _m32 : (c >> 1) & _m32;
    }
    t[n] = c;
  }
  return t;
}();

int _crc32(Uint8List type, Uint8List data) {
  var c = _m32;
  for (final b in type) {
    c = (_crcTable[(c ^ b) & 0xFF] ^ (c >> 8)) & _m32;
  }
  for (final b in data) {
    c = (_crcTable[(c ^ b) & 0xFF] ^ (c >> 8)) & _m32;
  }
  return (c ^ _m32) & _m32;
}

void _u32(BytesBuilder out, int v) {
  out.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final t = Uint8List.fromList(type.codeUnits);
  _u32(out, data.length);
  out.add(t);
  out.add(data);
  _u32(out, _crc32(t, data));
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

/// 8-bit RGB or RGBA PNG with per-row adaptive filtering (None, Sub, Up, Paeth,
/// chosen by the smallest sum of absolute values).
Uint8List encodePng(Uint8List rgba, int width, int height,
    {bool alpha = true, int level = 6}) {
  final bpp = alpha ? 4 : 3;
  final rowLen = width * bpp;
  final raw = Uint8List((rowLen + 1) * height);
  var cur = Uint8List(rowLen);
  var prev = Uint8List(rowLen);
  final cand = [Uint8List(rowLen), Uint8List(rowLen), Uint8List(rowLen), Uint8List(rowLen)];
  for (var y = 0; y < height; y++) {
    final base = y * width * 4;
    if (alpha) {
      for (var i = 0; i < rowLen; i++) {
        cur[i] = rgba[base + i];
      }
    } else {
      for (var x = 0; x < width; x++) {
        cur[x * 3] = rgba[base + x * 4];
        cur[x * 3 + 1] = rgba[base + x * 4 + 1];
        cur[x * 3 + 2] = rgba[base + x * 4 + 2];
      }
    }
    final sums = [0, 0, 0, 0];
    for (var i = 0; i < rowLen; i++) {
      final a = i >= bpp ? cur[i - bpp] : 0;
      final b = prev[i];
      final c = i >= bpp ? prev[i - bpp] : 0;
      final x = cur[i];
      final f0 = x;
      final f1 = (x - a) & 0xFF;
      final f2 = (x - b) & 0xFF;
      final f3 = (x - _paeth(a, b, c)) & 0xFF;
      cand[0][i] = f0;
      cand[1][i] = f1;
      cand[2][i] = f2;
      cand[3][i] = f3;
      sums[0] += f0 < 128 ? f0 : 256 - f0;
      sums[1] += f1 < 128 ? f1 : 256 - f1;
      sums[2] += f2 < 128 ? f2 : 256 - f2;
      sums[3] += f3 < 128 ? f3 : 256 - f3;
    }
    var best = 0;
    for (var f = 1; f < 4; f++) {
      if (sums[f] < sums[best]) best = f;
    }
    // filter types: 0 None, 1 Sub, 2 Up, 4 Paeth
    raw[y * (rowLen + 1)] = best == 3 ? 4 : best;
    raw.setRange(y * (rowLen + 1) + 1, (y + 1) * (rowLen + 1), cand[best]);
    final t = prev;
    prev = cur;
    cur = t;
  }

  final out = BytesBuilder(copy: false);
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = BytesBuilder();
  _u32(ihdr, width);
  _u32(ihdr, height);
  ihdr.add([8, alpha ? 6 : 2, 0, 0, 0]);
  _chunk(out, 'IHDR', ihdr.toBytes());
  final z = ZLibEncoder().encodeBytes(raw, level: level);
  _chunk(out, 'IDAT', Uint8List.fromList(z));
  _chunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}
