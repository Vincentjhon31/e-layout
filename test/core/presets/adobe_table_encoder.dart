// Test-only encoder for Adobe colour tables (`crs:Table_<id>` text holding an
// RGB table). It is the exact inverse of `decodeAdobeTable`: the same binary
// layout, zlib framing and base-85 text, written from the format description
// in lib/core/presets/adobe_table.dart. e-Layout itself never writes these.

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:pio_photo_layout/core/develop/profile_table.dart';

/// The 85 text digits, digit value 0 first.
const adobeTableDigits =
    '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '.-:+=^!/*?`\'|()[]{}@%\$#';

/// Primaries codes in the table header.
const primariesSrgb = 0, primariesAdobe = 1, primariesProPhoto = 2;
const primariesP3 = 3, primariesRec2020 = 4;

/// Gamma codes in the table header.
const gammaLinear = 0, gammaSrgb = 1, gamma18 = 2, gamma22 = 3;
const gammaRec2020 = 4;

/// The uncompressed table bytes. [samples] holds 3 values (0..65535) per grid
/// point. For a 3D table red changes slowest and blue fastest; for a 1D table
/// there are [divisions] points.
Uint8List adobeTablePayload({
  required int dimensions,
  required int divisions,
  required List<int> samples,
  int primaries = primariesSrgb,
  int gamma = gammaSrgb,
  int gamut = 0,
  double minAmount = 0,
  double maxAmount = 2,
  int flags = 0,
  int type = 1,
  int version = 1,
}) {
  final count = dimensions == 3 ? divisions * divisions * divisions : divisions;
  final out = BytesBuilder();
  final word = ByteData(8);
  void u32(int v) {
    word.setUint32(0, v, Endian.little);
    out.add(word.buffer.asUint8List(0, 4));
  }

  void u16(int v) {
    word.setUint16(0, v & 0xFFFF, Endian.little);
    out.add(word.buffer.asUint8List(0, 2));
  }

  void f64(double v) {
    word.setFloat64(0, v, Endian.little);
    out.add(word.buffer.asUint8List(0, 8));
  }

  u32(type);
  u32(version);
  u32(dimensions);
  u32(divisions);
  // Each sample is stored as its difference from the identity value of its
  // own axis index, modulo 2^16.
  // (A 1-division table is invalid; it is written only to test rejection.)
  int nop(int i) =>
      divisions < 2 ? 0 : (i * 0xFFFF + (divisions >> 1)) ~/ (divisions - 1);
  for (var i = 0; i < count; i++) {
    final ri = dimensions == 3 ? i ~/ (divisions * divisions) : i;
    final gi = dimensions == 3 ? (i ~/ divisions) % divisions : i;
    final bi = dimensions == 3 ? i % divisions : i;
    u16(samples[i * 3] - nop(ri));
    u16(samples[i * 3 + 1] - nop(gi));
    u16(samples[i * 3 + 2] - nop(bi));
  }
  u32(primaries);
  u32(gamma);
  u32(gamut);
  f64(minAmount);
  f64(maxAmount);
  if (flags != 0) u32(flags);
  return out.toBytes();
}

/// The table's id: the MD5 of the uncompressed bytes, 32 uppercase hex digits.
String adobeTableId(Uint8List payload) =>
    md5.convert(payload).toString().toUpperCase();

/// Compresses [payload] (4-byte little-endian size, then zlib) and writes it
/// as text: each 4 bytes (little-endian) become 5 digits, least significant
/// first; a last group of k bytes becomes k + 1 digits.
String encodeAdobeBinary(Uint8List payload) {
  final z = ZLibEncoder().encodeBytes(payload);
  final data = Uint8List(z.length + 4);
  ByteData.sublistView(data).setUint32(0, payload.length, Endian.little);
  data.setRange(4, data.length, z);
  return encodeAdobeText(data);
}

/// The text layer alone (no compression).
String encodeAdobeText(Uint8List data) {
  final s = StringBuffer();
  for (var i = 0; i < data.length; i += 4) {
    final left = data.length - i < 4 ? data.length - i : 4;
    var x = 0;
    for (var k = 0; k < left; k++) {
      x += data[i + k] << (8 * k);
    }
    for (var k = 0; k < (left == 4 ? 5 : left + 1); k++) {
      s.writeCharCode(adobeTableDigits.codeUnitAt(x % 85));
      x ~/= 85;
    }
  }
  return s.toString();
}

int _q(double v) => (v.clamp(0.0, 1.0) * 65535).round();

/// Encodes a 3D [table] whose grid and values are in the declared
/// [primaries] and [gamma] (the defaults, sRGB primaries and sRGB gamma, are
/// the app's own space).
({String text, String id}) encodeAdobeTable(
  ProfileTable table, {
  int primaries = primariesSrgb,
  int gamma = gammaSrgb,
  int gamut = 0,
}) {
  final n = table.size;
  final samples = <int>[];
  for (var r = 0; r < n; r++) {
    for (var g = 0; g < n; g++) {
      for (var b = 0; b < n; b++) {
        final o = ((b * n + g) * n + r) * 3;
        samples
          ..add(_q(table.rgb[o]))
          ..add(_q(table.rgb[o + 1]))
          ..add(_q(table.rgb[o + 2]));
      }
    }
  }
  final payload = adobeTablePayload(
    dimensions: 3,
    divisions: n,
    samples: samples,
    primaries: primaries,
    gamma: gamma,
    gamut: gamut,
  );
  return (text: encodeAdobeBinary(payload), id: adobeTableId(payload));
}

/// Encodes a 1D table: one (r, g, b) output per input step.
String encodeAdobeTable1D(
  List<(double, double, double)> curve, {
  int primaries = primariesSrgb,
  int gamma = gammaSrgb,
}) {
  final samples = <int>[
    for (final (r, g, b) in curve) ...[_q(r), _q(g), _q(b)],
  ];
  return encodeAdobeBinary(
    adobeTablePayload(
      dimensions: 1,
      divisions: curve.length,
      samples: samples,
      primaries: primaries,
      gamma: gamma,
    ),
  );
}
