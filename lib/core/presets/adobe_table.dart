// Reads the colour tables inside Lightroom creative-profile files
// (`crs:Table_<id>` text named by `crs:RGBTable`).
//
// The format (text alphabet, zlib framing, binary layout, header codes) and
// the way the table is applied (colour space, gamma curves, gamut option,
// tetrahedral lookup) follow Adobe's DNG SDK 1.7.1:
//   dng_big_table.cpp (dng_big_table::DecodeFromString, ASCIItoBinary,
//     DecodeFromBinary, dng_rgb_table::GetStream,
//     dng_rgb_to_rgb_table_data), dng_big_table.h (codes and limits),
//   dng_reference.cpp (RefRGBtoRGBTable3D / 1D),
//   dng_color_space.cpp/.h (space matrices and gamma functions).
// Copyright 2006-2023 Adobe Systems Incorporated. All Rights Reserved.
// Used under the DNG SDK License Agreement (Adobe's permissive licence: use,
// modify and distribute for any purpose, keeping Adobe's notices). This file
// is a Dart rewrite of that behaviour, not a copy of the C++ code.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../develop/profile_table.dart';

const _message = "This colour table can't be read.";

/// The 85 text digits in value order (digit 0 first).
const _digits =
    '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '.-:+=^!/*?`\'|()[]{}@%\$#';

final Int8List _digitValue = () {
  final t = Int8List(128)..fillRange(0, 128, -1);
  for (var i = 0; i < _digits.length; i++) {
    t[_digits.codeUnitAt(i)] = i;
  }
  return t;
}();

// Header codes and limits.
const _typeRgbTable = 1, _version = 1;
const _maxDivisions1d = 4096, _maxDivisions3d = 64;
const _primariesSrgb = 0, _primariesCount = 5;
const _gammaLinear = 0, _gammaSrgb = 1, _gamma18 = 2, _gamma22 = 3;
const _gammaCount = 5;
const _gamutExtend = 1, _gamutCount = 2;

/// The largest valid uncompressed table: a 64-division 3D table.
const _maxPayload =
    16 + _maxDivisions3d * _maxDivisions3d * _maxDivisions3d * 6 + 32;

/// The size a 1D table is turned into.
const _size1d = 33;

/// Decodes an Adobe colour table and returns it as a [ProfileTable] that maps
/// sRGB-encoded colours to sRGB-encoded colours, at the table's full strength.
///
/// [encoded] is the text of a `crs:Table_<id>` attribute. When [fingerprint]
/// (the `<id>`, 32 hex digits) is given, the decoded data must match it.
///
/// A table declared in another space or gamma is resampled at its own size
/// (1D tables at 33) through the same steps Adobe applies it with.
///
/// Throws a [FormatException] if the text is not a readable RGB table.
ProfileTable decodeAdobeTable(String encoded, {String? fingerprint}) {
  final _AdobeTable table;
  try {
    final payload = _inflate(_textToBytes(encoded));
    if (fingerprint != null &&
        md5.convert(payload).toString() != fingerprint.toLowerCase()) {
      throw const FormatException(_message);
    }
    table = _parse(payload);
  } catch (_) {
    throw const FormatException(_message);
  }
  return table.toProfileTable();
}

/// The text layer: every 5 digits (least significant first) make 4 bytes
/// (little-endian); a last group of k digits makes k - 1 bytes. Characters
/// outside the alphabet are skipped.
Uint8List _textToBytes(String s) {
  var valid = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 128 && _digitValue[c] >= 0) valid++;
  }
  final tail = valid % 5;
  final out = Uint8List(valid ~/ 5 * 4 + (tail > 1 ? tail - 1 : 0));
  var o = 0, phase = 0, value = 0, scale = 1;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final d = c < 128 ? _digitValue[c] : -1;
    if (d < 0) continue;
    value += d * scale;
    scale *= 85;
    if (++phase == 5) {
      out[o++] = value;
      out[o++] = value >> 8;
      out[o++] = value >> 16;
      out[o++] = value >> 24;
      phase = 0;
      value = 0;
      scale = 1;
    }
  }
  for (var k = 0; k < phase - 1; k++) {
    out[o++] = value >> (8 * k);
  }
  return out;
}

/// A 4-byte little-endian uncompressed size, then a zlib stream.
Uint8List _inflate(Uint8List packed) {
  if (packed.length < 5) throw const FormatException(_message);
  final size = ByteData.sublistView(packed).getUint32(0, Endian.little);
  if (size > _maxPayload) throw const FormatException(_message);
  final out = const ZLibDecoder().decodeBytes(
    Uint8List.sublistView(packed, 4),
    verify: true,
    maxOutputSize: size,
  );
  if (out.length != size) throw const FormatException(_message);
  return out;
}

class _Reader {
  _Reader(Uint8List bytes) : _d = ByteData.sublistView(bytes);
  final ByteData _d;
  int _o = 0;

  int get left => _d.lengthInBytes - _o;

  void _need(int n) {
    if (left < n) throw const FormatException(_message);
  }

  int u16() {
    _need(2);
    final v = _d.getUint16(_o, Endian.little);
    _o += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v = _d.getUint32(_o, Endian.little);
    _o += 4;
    return v;
  }

  double f64() {
    _need(8);
    final v = _d.getFloat64(_o, Endian.little);
    _o += 8;
    return v;
  }
}

/// The binary layout (all little-endian): type, version, dimensions (1 or 3),
/// divisions; then 3 uint16 per grid point (3D: red slowest, blue fastest),
/// each stored as its difference from the identity value of its own axis
/// index, modulo 2^16; then primaries, gamma, gamut (uint32), min and max
/// amount (float64), and optional flags (uint32).
_AdobeTable _parse(Uint8List payload) {
  final r = _Reader(payload);
  const bad = FormatException(_message);
  if (r.u32() != _typeRgbTable || r.u32() != _version) throw bad;
  final dimensions = r.u32();
  final divisions = r.u32();
  final maxDivisions = switch (dimensions) {
    1 => _maxDivisions1d,
    3 => _maxDivisions3d,
    _ => throw bad,
  };
  if (divisions < 2 || divisions > maxDivisions) throw bad;
  final nop = [
    for (var i = 0; i < divisions; i++)
      (i * 0xFFFF + (divisions >> 1)) ~/ (divisions - 1),
  ];
  final count = dimensions == 3 ? divisions * divisions * divisions : divisions;
  final samples = Uint16List(count * 3);
  for (var i = 0, o = 0; i < count; i++, o += 3) {
    final ri = dimensions == 3 ? i ~/ (divisions * divisions) : i;
    final gi = dimensions == 3 ? (i ~/ divisions) % divisions : i;
    final bi = dimensions == 3 ? i % divisions : i;
    samples[o] = r.u16() + nop[ri];
    samples[o + 1] = r.u16() + nop[gi];
    samples[o + 2] = r.u16() + nop[bi];
  }
  final primaries = r.u32();
  final gamma = r.u32();
  final gamut = r.u32();
  if (primaries >= _primariesCount ||
      gamma >= _gammaCount ||
      gamut >= _gamutCount) {
    throw bad;
  }
  final minAmount = r.f64();
  final maxAmount = r.f64();
  if (!minAmount.isFinite ||
      !maxAmount.isFinite ||
      minAmount < 0 ||
      minAmount > 1 ||
      maxAmount < 1) {
    throw bad;
  }
  return _AdobeTable(dimensions, divisions, samples, primaries, gamma, gamut);
}

class _AdobeTable {
  _AdobeTable(
    this.dimensions,
    this.divisions,
    this.samples,
    this.primaries,
    this.gamma,
    this.gamut,
  );

  final int dimensions, divisions, primaries, gamma, gamut;

  /// Values 0..65535, 3 per grid point, red slowest.
  final Uint16List samples;

  ProfileTable toProfileTable() {
    final n = divisions;
    if (dimensions == 3 && primaries == _primariesSrgb && gamma == _gammaSrgb) {
      // Already sRGB-encoded sRGB: copy, red fastest.
      final rgb = Float32List(n * n * n * 3);
      for (var r = 0; r < n; r++) {
        for (var g = 0; g < n; g++) {
          for (var b = 0; b < n; b++) {
            final s = ((r * n + g) * n + b) * 3;
            final d = ((b * n + g) * n + r) * 3;
            rgb[d] = samples[s] / 65535;
            rgb[d + 1] = samples[s + 1] / 65535;
            rgb[d + 2] = samples[s + 2] / 65535;
          }
        }
      }
      return ProfileTable(n, rgb);
    }
    return _resample(dimensions == 3 ? n : _size1d);
  }

  /// Applies the table to every grid point of an sRGB table of [size], the
  /// way Adobe applies it: into the table's primaries (clipped, the clipped
  /// part kept aside when the gamut option is "extend"), through its gamma,
  /// the lookup, back through the gamma, and back to sRGB.
  ProfileTable _resample(int size) {
    final toTable = _mul(_inverse(_toPcs(primaries)), _toPcs(_primariesSrgb));
    final toSrgb = _mul(_inverse(_toPcs(_primariesSrgb)), _toPcs(primaries));
    final extend = gamut == _gamutExtend;
    final rgb = Float32List(size * size * size * 3);
    final linear = [for (var i = 0; i < size; i++) _srgbDecode(i / (size - 1))];
    final v = Float64List(3), delta = Float64List(3), out = Float64List(3);
    var o = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          final lr = linear[r], lg = linear[g], lb = linear[b];
          for (var k = 0; k < 3; k++) {
            final x =
                toTable[k * 3] * lr +
                toTable[k * 3 + 1] * lg +
                toTable[k * 3 + 2] * lb;
            final p = _pin(x);
            delta[k] = extend ? x - p : 0;
            v[k] = _encode(gamma, p);
          }
          if (dimensions == 3) {
            _lookup3d(v, out);
          } else {
            _lookup1d(v, out);
          }
          for (var k = 0; k < 3; k++) {
            out[k] = _decode(gamma, _pin(out[k])) + delta[k];
          }
          for (var k = 0; k < 3; k++) {
            final x =
                toSrgb[k * 3] * out[0] +
                toSrgb[k * 3 + 1] * out[1] +
                toSrgb[k * 3 + 2] * out[2];
            rgb[o++] = _srgbEncode(_pin(x));
          }
        }
      }
    }
    return ProfileTable(size, rgb);
  }

  /// Tetrahedral interpolation (Adobe's lookup): split the cell along its
  /// fractions in decreasing order and blend the 4 corners on that path.
  void _lookup3d(Float64List v, Float64List out) {
    final n = divisions;
    final idx = Int32List(3);
    final frac = Float64List(3);
    for (var k = 0; k < 3; k++) {
      final s = v[k] * (n - 1);
      var i = s.floor();
      if (i < 0) i = 0;
      if (i > n - 2) i = n - 2;
      idx[k] = i;
      frac[k] = s - i;
    }
    // Strides in the sample array for a step along r, g, b.
    final stride = [n * n * 3, n * 3, 3];
    // Axis order by fraction, largest first; ties as Adobe breaks them.
    final List<int> order;
    final fr = frac[0], fg = frac[1], fb = frac[2];
    if (fg >= fr) {
      order = fb >= fg ? [2, 1, 0] : (fb >= fr ? [1, 2, 0] : [1, 0, 2]);
    } else {
      order = fb >= fr ? [2, 0, 1] : (fb >= fg ? [0, 2, 1] : [0, 1, 2]);
    }
    final f1 = frac[order[0]], f2 = frac[order[1]], f3 = frac[order[2]];
    final c0 = idx[0] * stride[0] + idx[1] * stride[1] + idx[2] * stride[2];
    final c1 = c0 + stride[order[0]];
    final c2 = c1 + stride[order[1]];
    final c3 = c2 + stride[order[2]];
    final w0 = 1 - f1, w1 = f1 - f2, w2 = f2 - f3, w3 = f3;
    for (var k = 0; k < 3; k++) {
      out[k] =
          (w0 * samples[c0 + k] +
              w1 * samples[c1 + k] +
              w2 * samples[c2 + k] +
              w3 * samples[c3 + k]) /
          65535;
    }
  }

  /// A 1D table: each channel through its own curve.
  void _lookup1d(Float64List v, Float64List out) {
    final n = divisions;
    for (var k = 0; k < 3; k++) {
      final s = v[k] * (n - 1);
      var i = s.floor();
      if (i < 0) i = 0;
      if (i > n - 2) i = n - 2;
      final f = s - i;
      out[k] =
          ((1 - f) * samples[i * 3 + k] + f * samples[(i + 1) * 3 + k]) / 65535;
    }
  }
}

double _pin(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

// --- Colour spaces --------------------------------------------------------

/// Each space's RGB to the D50 connection space, rows scaled so that RGB
/// white lands exactly on D50 white (as the SDK does). Order: sRGB, Adobe RGB,
/// ProPhoto, Display P3, Rec. 2020.
const _spaceMatrices = <List<double>>[
  [0.4361, 0.3851, 0.1431, 0.2225, 0.7169, 0.0606, 0.0139, 0.0971, 0.7141],
  [0.6097, 0.2053, 0.1492, 0.3111, 0.6257, 0.0632, 0.0195, 0.0609, 0.7446],
  [0.7977, 0.1352, 0.0313, 0.2880, 0.7119, 0.0001, 0.0000, 0.0000, 0.8249],
  [0.5151, 0.2920, 0.1571, 0.2412, 0.6922, 0.0666, -0.0010, 0.0419, 0.7843],
  [0.6735, 0.1657, 0.1251, 0.2791, 0.6753, 0.0456, -0.0019, 0.0300, 0.7971],
];

List<double> _toPcs(int primaries) {
  final m = _spaceMatrices[primaries];
  // D50 white from its chromaticity (0.3457, 0.3585).
  const x = 0.3457, y = 0.3585;
  const white = [x / y, 1.0, (1 - x - y) / y];
  return [
    for (var row = 0; row < 3; row++)
      for (var col = 0; col < 3; col++)
        m[row * 3 + col] *
            white[row] /
            (m[row * 3] + m[row * 3 + 1] + m[row * 3 + 2]),
  ];
}

List<double> _mul(List<double> a, List<double> b) => [
  for (var i = 0; i < 3; i++)
    for (var j = 0; j < 3; j++)
      a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j],
];

List<double> _inverse(List<double> m) {
  final a = m[0], b = m[1], c = m[2];
  final d = m[3], e = m[4], f = m[5];
  final g = m[6], h = m[7], i = m[8];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  return [
    (e * i - f * h) / det,
    (c * h - b * i) / det,
    (b * f - c * e) / det,
    (f * g - d * i) / det,
    (a * i - c * g) / det,
    (c * d - a * f) / det,
    (d * h - e * g) / det,
    (b * g - a * h) / det,
    (a * e - b * d) / det,
  ];
}

// --- Gamma curves ---------------------------------------------------------

double _srgbEncode(double x) =>
    x <= 0.0031308 ? x * 12.92 : 1.055 * math.pow(x, 1 / 2.4) - 0.055;

double _srgbDecode(double y) => y <= 0.0031308 * 12.92
    ? y / 12.92
    : math.pow((y + 0.055) / 1.055, 2.4).toDouble();

/// A power curve with a cubic toe of slope 32 at black (gamma 1.8 and 2.2).
class _ToeGamma {
  const _ToeGamma(this.gamma, this.x1, this.y1, this.slope1);
  final double gamma, x1, y1, slope1;

  double encode(double x) {
    if (x > x1) return math.pow(x, 1 / gamma).toDouble();
    // Hermite segment from (0, 0) with slope 32 to (x1, y1) with slope1.
    final t = x / x1, u = 1 - t;
    return (32.0 * x1 * t) * u * u +
        (y1 * (3 - 2 * t) - slope1 * x1 * u) * t * t;
  }

  double decode(double y) {
    if (y >= y1) return math.pow(y, gamma).toDouble();
    if (y <= 0) return 0;
    var lo = 0.0, hi = x1;
    for (var k = 0; k < 50; k++) {
      final mid = (lo + hi) / 2;
      if (encode(mid) < y) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }
}

const _toe18 = _ToeGamma(1.8, 8.2118790552e-4, 0.019310851, 13.064306598);
const _toe22 = _ToeGamma(2.2, 0.0034800731, 0.0763027458, 9.9661890075);

// Rec. 709 / 2020 curve.
const _recAlpha = 1.0992968268094429, _recBeta = 0.0180539685108078;

double _encode(int gamma, double x) => switch (gamma) {
  _gammaLinear => x,
  _gammaSrgb => _srgbEncode(x),
  _gamma18 => _toe18.encode(x),
  _gamma22 => _toe22.encode(x),
  _ =>
    x <= _recBeta ? 4.5 * x : _recAlpha * math.pow(x, 0.45) - (_recAlpha - 1),
};

double _decode(int gamma, double y) => switch (gamma) {
  _gammaLinear => y,
  _gammaSrgb => _srgbDecode(y),
  _gamma18 => _toe18.decode(y),
  _gamma22 => _toe22.decode(y),
  _ =>
    y <= 4.5 * _recBeta
        ? y / 4.5
        : math.pow((y + (_recAlpha - 1)) / _recAlpha, 1 / 0.45).toDouble(),
};
