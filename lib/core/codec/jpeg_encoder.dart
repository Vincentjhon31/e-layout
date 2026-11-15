import 'dart:math' as math;
import 'dart:typed_data';

// Annex K tables (natural order).
const List<int> _lumQ = [
  16, 11, 10, 16, 24, 40, 51, 61, //
  12, 12, 14, 19, 26, 58, 60, 55,
  14, 13, 16, 24, 40, 57, 69, 56,
  14, 17, 22, 29, 51, 87, 80, 62,
  18, 22, 37, 56, 68, 109, 103, 77,
  24, 35, 55, 64, 81, 104, 113, 92,
  49, 64, 78, 87, 103, 121, 120, 101,
  72, 92, 95, 98, 112, 100, 103, 99,
];
const List<int> _chrQ = [
  17, 18, 24, 47, 99, 99, 99, 99, //
  18, 21, 26, 66, 99, 99, 99, 99,
  24, 26, 56, 99, 99, 99, 99, 99,
  47, 66, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
];
const List<int> _zigzag = [
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, //
  12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
];

// Standard Huffman tables (Annex K.3): code counts per length, then symbols.
const List<int> kDcLumBits = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0];
const List<int> kDcChrBits = [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0];
const List<int> kDcVals = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
const List<int> kAcLumBits = [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d];
const List<int> kAcLumVals = [
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
const List<int> kAcChrBits = [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77];
const List<int> kAcChrVals = [
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

/// Canonical Huffman codes: [code, length] per symbol.
class _Huff {
  _Huff(List<int> bits, List<int> vals)
      : code = Int32List(256),
        len = Uint8List(256) {
    var c = 0, k = 0;
    for (var l = 1; l <= 16; l++) {
      for (var i = 0; i < bits[l - 1]; i++) {
        code[vals[k]] = c;
        len[vals[k]] = l;
        c++;
        k++;
      }
      c <<= 1;
    }
  }
  final Int32List code;
  final Uint8List len;
}

final _Huff _dcLum = _Huff(kDcLumBits, kDcVals);
final _Huff _dcChr = _Huff(kDcChrBits, kDcVals);
final _Huff _acLum = _Huff(kAcLumBits, kAcLumVals);
final _Huff _acChr = _Huff(kAcChrBits, kAcChrVals);

List<int> _scaledTable(List<int> base, int quality) {
  final q = quality.clamp(1, 100);
  final scale = q < 50 ? 5000 ~/ q : 200 - q * 2;
  return [for (final b in base) ((b * scale + 50) ~/ 100).clamp(1, 255)];
}

/// Baseline JPEG, YCbCr 4:2:0, standard Huffman tables, JFIF header, no EXIF.
/// Rows are fed top to bottom in bands, so a huge picture never needs to sit in
/// memory as RGBA all at once.
class JpegEncoder {
  JpegEncoder({required this.width, required this.height, int quality = 92})
      : _qLum = _scaledTable(_lumQ, quality),
        _qChr = _scaledTable(_chrQ, quality) {
    _dLum = _aanDivisors(_qLum);
    _dChr = _aanDivisors(_qChr);
    _writeHeader();
  }

  final int width;
  final int height;
  final List<int> _qLum;
  final List<int> _qChr;
  late final Float64List _dLum;
  late final Float64List _dChr;

  Uint8List _out = Uint8List(1 << 16);
  int _n = 0;
  int _bitBuf = 0;
  int _bitCnt = 0;
  int _predY = 0, _predCb = 0, _predCr = 0;
  bool _finished = false;

  final Float64List _y = Float64List(256);
  final Float64List _cb = Float64List(64);
  final Float64List _cr = Float64List(64);
  final Float64List _tmp = Float64List(64);
  final Int32List _q = Int32List(64);

  void _byte(int b) {
    if (_n == _out.length) {
      final bigger = Uint8List(_out.length * 2)..setRange(0, _n, _out);
      _out = bigger;
    }
    _out[_n++] = b;
  }

  void _word(int w) {
    _byte((w >> 8) & 0xFF);
    _byte(w & 0xFF);
  }

  void _writeHeader() {
    _word(0xFFD8);
    // JFIF APP0
    _word(0xFFE0);
    _word(16);
    for (final b in [0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0]) {
      _byte(b);
    }
    _word(1);
    _word(1);
    _byte(0);
    _byte(0);
    // DQT, in zigzag order
    for (var t = 0; t < 2; t++) {
      _word(0xFFDB);
      _word(67);
      _byte(t);
      final tab = t == 0 ? _qLum : _qChr;
      for (var i = 0; i < 64; i++) {
        _byte(tab[_zigzag[i]]);
      }
    }
    // SOF0: 8 bit, 3 components, Y at 2x2, Cb and Cr at 1x1
    _word(0xFFC0);
    _word(17);
    _byte(8);
    _word(height);
    _word(width);
    _byte(3);
    _byte(1);
    _byte(0x22);
    _byte(0);
    _byte(2);
    _byte(0x11);
    _byte(1);
    _byte(3);
    _byte(0x11);
    _byte(1);
    // DHT
    void dht(int cls, int id, List<int> bits, List<int> vals) {
      _word(0xFFC4);
      _word(19 + vals.length);
      _byte((cls << 4) | id);
      for (final b in bits) {
        _byte(b);
      }
      for (final v in vals) {
        _byte(v);
      }
    }

    dht(0, 0, kDcLumBits, kDcVals);
    dht(1, 0, kAcLumBits, kAcLumVals);
    dht(0, 1, kDcChrBits, kDcVals);
    dht(1, 1, kAcChrBits, kAcChrVals);
    // SOS
    _word(0xFFDA);
    _word(12);
    _byte(3);
    _byte(1);
    _byte(0x00);
    _byte(2);
    _byte(0x11);
    _byte(3);
    _byte(0x11);
    _byte(0);
    _byte(63);
    _byte(0);
  }

  void _bits(int value, int count) {
    if (count == 0) return;
    _bitBuf = (_bitBuf << count) | (value & ((1 << count) - 1));
    _bitCnt += count;
    while (_bitCnt >= 8) {
      final b = (_bitBuf >> (_bitCnt - 8)) & 0xFF;
      _byte(b);
      if (b == 0xFF) _byte(0);
      _bitCnt -= 8;
      _bitBuf &= (1 << _bitCnt) - 1;
    }
  }

  /// Forward DCT of an 8x8 block (already level shifted) at [src], quantised
  /// into [_q] in zigzag order. Arai-Agui-Nakajima float DCT (libjpeg
  /// jfdctflt.c); its output scale is folded into [div] (see [_aanDivisors]).
  void _fdctQuant(Float64List src, int offset, int stride, Float64List div) {
    final t = _tmp;
    for (var r = 0; r < 8; r++) {
      final o = offset + r * stride;
      final d0 = src[o], d1 = src[o + 1], d2 = src[o + 2], d3 = src[o + 3];
      final d4 = src[o + 4], d5 = src[o + 5], d6 = src[o + 6], d7 = src[o + 7];
      _aan(t, r * 8, 1, d0 + d7, d1 + d6, d2 + d5, d3 + d4, d3 - d4, d2 - d5, d1 - d6,
          d0 - d7);
    }
    for (var c = 0; c < 8; c++) {
      final d0 = t[c], d1 = t[8 + c], d2 = t[16 + c], d3 = t[24 + c];
      final d4 = t[32 + c], d5 = t[40 + c], d6 = t[48 + c], d7 = t[56 + c];
      _aan(t, c, 8, d0 + d7, d1 + d6, d2 + d5, d3 + d4, d3 - d4, d2 - d5, d1 - d6,
          d0 - d7);
    }
    for (var i = 0; i < 64; i++) {
      _q[_zigzagInv[i]] = (t[i] * div[i]).round();
    }
  }

  /// One 8-point AAN pass, written to [o] at [base] with step [step].
  static void _aan(Float64List o, int base, int step, double tmp0, double tmp1,
      double tmp2, double tmp3, double tmp4, double tmp5, double tmp6, double tmp7) {
    var tmp10 = tmp0 + tmp3;
    final tmp13 = tmp0 - tmp3;
    var tmp11 = tmp1 + tmp2;
    var tmp12 = tmp1 - tmp2;
    o[base] = tmp10 + tmp11;
    o[base + 4 * step] = tmp10 - tmp11;
    final z1 = (tmp12 + tmp13) * 0.707106781;
    o[base + 2 * step] = tmp13 + z1;
    o[base + 6 * step] = tmp13 - z1;
    tmp10 = tmp4 + tmp5;
    tmp11 = tmp5 + tmp6;
    tmp12 = tmp6 + tmp7;
    final z5 = (tmp10 - tmp12) * 0.382683433;
    final z2 = 0.541196100 * tmp10 + z5;
    final z4 = 1.306562965 * tmp12 + z5;
    final z3 = tmp11 * 0.707106781;
    final z11 = tmp7 + z3;
    final z13 = tmp7 - z3;
    o[base + 5 * step] = z13 + z2;
    o[base + 3 * step] = z13 - z2;
    o[base + step] = z11 + z4;
    o[base + 7 * step] = z11 - z4;
  }

  static const List<double> _aanScale = [
    1.0, 1.387039845, 1.306562965, 1.175875602, //
    1.0, 0.785694958, 0.541196100, 0.275899379,
  ];

  /// Multipliers that turn AAN output into quantised coefficients (natural order).
  static Float64List _aanDivisors(List<int> qt) {
    final d = Float64List(64);
    for (var v = 0; v < 8; v++) {
      for (var u = 0; u < 8; u++) {
        d[v * 8 + u] = 1 / (qt[v * 8 + u] * _aanScale[v] * _aanScale[u] * 8);
      }
    }
    return d;
  }

  static final Uint8List _zigzagInv = () {
    final inv = Uint8List(64);
    for (var i = 0; i < 64; i++) {
      inv[_zigzag[i]] = i;
    }
    return inv;
  }();

  void _writeBlock(int component) {
    final dc = component == 0 ? _dcLum : _dcChr;
    final ac = component == 0 ? _acLum : _acChr;
    final pred = component == 0 ? _predY : component == 1 ? _predCb : _predCr;
    final diff = _q[0] - pred;
    if (component == 0) {
      _predY = _q[0];
    } else if (component == 1) {
      _predCb = _q[0];
    } else {
      _predCr = _q[0];
    }
    var a = diff.abs();
    var cat = 0;
    while (a > 0) {
      cat++;
      a >>= 1;
    }
    _bits(dc.code[cat], dc.len[cat]);
    if (cat > 0) _bits(diff >= 0 ? diff : diff - 1, cat);
    var run = 0;
    for (var i = 1; i < 64; i++) {
      final v = _q[i];
      if (v == 0) {
        run++;
        continue;
      }
      while (run > 15) {
        _bits(ac.code[0xF0], ac.len[0xF0]);
        run -= 16;
      }
      var m = v.abs();
      var s = 0;
      while (m > 0) {
        s++;
        m >>= 1;
      }
      final sym = (run << 4) | s;
      _bits(ac.code[sym], ac.len[sym]);
      _bits(v >= 0 ? v : v - 1, s);
      run = 0;
    }
    if (run > 0) _bits(ac.code[0], ac.len[0]);
  }

  /// Adds [rowCount] rows of RGBA, top to bottom. Every call but the last must
  /// carry a multiple of 16 rows. Alpha is ignored.
  void addRows(Uint8List rgba, int rowCount) {
    if (_finished || rowCount <= 0) return;
    final stride = width * 4;
    final mcusX = (width + 15) ~/ 16;
    final cols = Int32List(16);
    final yv = _y, cbv = _cb, crv = _cr;
    for (var band = 0; band < rowCount; band += 16) {
      for (var mx = 0; mx < mcusX; mx++) {
        for (var px = 0; px < 16; px++) {
          cols[px] = math.min(mx * 16 + px, width - 1) * 4;
        }
        cbv.fillRange(0, 64, 0);
        crv.fillRange(0, 64, 0);
        for (var py = 0; py < 16; py++) {
          final row = math.min(band + py, rowCount - 1) * stride;
          final cRow = (py >> 1) * 8;
          for (var px = 0; px < 16; px++) {
            final i = row + cols[px];
            final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
            yv[py * 16 + px] = 0.299 * r + 0.587 * g + 0.114 * b - 128;
            // chroma, summed over each 2x2 group and averaged below
            final ci = cRow + (px >> 1);
            cbv[ci] += -0.168736 * r - 0.331264 * g + 0.5 * b;
            crv[ci] += 0.5 * r - 0.418688 * g - 0.081312 * b;
          }
        }
        for (var i = 0; i < 64; i++) {
          cbv[i] *= 0.25;
          crv[i] *= 0.25;
        }
        _fdctQuant(yv, 0, 16, _dLum);
        _writeBlock(0);
        _fdctQuant(yv, 8, 16, _dLum);
        _writeBlock(0);
        _fdctQuant(yv, 8 * 16, 16, _dLum);
        _writeBlock(0);
        _fdctQuant(yv, 8 * 16 + 8, 16, _dLum);
        _writeBlock(0);
        _fdctQuant(cbv, 0, 8, _dChr);
        _writeBlock(1);
        _fdctQuant(crv, 0, 8, _dChr);
        _writeBlock(2);
      }
    }
  }

  Uint8List finish() {
    if (!_finished) {
      _finished = true;
      if (_bitCnt > 0) _bits(0x7F, 8 - _bitCnt);
      _word(0xFFD9);
    }
    return Uint8List.sublistView(_out, 0, _n);
  }
}

Uint8List encodeJpeg(Uint8List rgba, int width, int height, {int quality = 92}) {
  final e = JpegEncoder(width: width, height: height, quality: quality);
  e.addRows(rgba, height);
  return e.finish();
}
