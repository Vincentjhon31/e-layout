import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/profile_table.dart';
import 'package:pio_photo_layout/core/presets/adobe_table.dart';

import 'adobe_table_encoder.dart';

const _message = "This colour table can't be read.";

final _unreadable = throwsA(
  isA<FormatException>().having((e) => e.message, 'message', _message),
);

ProfileTable _map(
  int n,
  (double, double, double) Function(double, double, double) f,
) {
  final data = Float32List(n * n * n * 3);
  final d = 1.0 / (n - 1);
  var i = 0;
  for (var b = 0; b < n; b++) {
    for (var g = 0; g < n; g++) {
      for (var r = 0; r < n; r++) {
        final (x, y, z) = f(r * d, g * d, b * d);
        data[i++] = x;
        data[i++] = y;
        data[i++] = z;
      }
    }
  }
  return ProfileTable(n, data);
}

void _expectClose(ProfileTable got, ProfileTable want, double tolerance) {
  expect(got.size, want.size);
  expect(got.rgb.length, want.rgb.length);
  var worst = 0.0;
  for (var i = 0; i < want.rgb.length; i++) {
    worst = max(worst, (got.rgb[i] - want.rgb[i]).abs());
  }
  expect(worst, lessThanOrEqualTo(tolerance));
}

double _srgbEncode(double x) =>
    x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055;

void main() {
  // Quantising to 16 bits is off by at most half a step; float32 storage adds
  // a little more.
  const step = 1 / 65535;

  test('an identity table of size 32 comes back unchanged', () {
    final table = ProfileTable.identity(32);
    final decoded = decodeAdobeTable(encodeAdobeTable(table).text);
    expect(decoded.size, 32);
    _expectClose(decoded, table, step);
  });

  test('a "red +0.1" table of size 32 comes back unchanged', () {
    final table = _map(32, (r, g, b) => (min(1.0, r + 0.1), g, b));
    final decoded = decodeAdobeTable(encodeAdobeTable(table).text);
    expect(decoded.size, 32);
    _expectClose(decoded, table, step);
    // Spot check one grid point: r = 0.5 (index 15.5 is not a node, use 16).
    final o = ((3 * 32 + 7) * 32 + 16) * 3;
    expect(decoded.rgb[o], closeTo(16 / 31 + 0.1, step));
    expect(decoded.rgb[o + 1], closeTo(7 / 31, step));
    expect(decoded.rgb[o + 2], closeTo(3 / 31, step));
  });

  test('keeps the grid order: red changes fastest in the result', () {
    // A table whose output names its own grid point in a distinct way.
    final table = _map(5, (r, g, b) => (b, r, g));
    _expectClose(decodeAdobeTable(encodeAdobeTable(table).text), table, step);
  });

  test('other sizes decode (2 and 17)', () {
    for (final n in [2, 17]) {
      final table = _map(n, (r, g, b) => (1 - r, g * g, sqrt(b)));
      _expectClose(decodeAdobeTable(encodeAdobeTable(table).text), table, step);
    }
  });

  test('the id check passes for the right id and fails for a wrong one', () {
    final encoded = encodeAdobeTable(ProfileTable.identity(4));
    expect(decodeAdobeTable(encoded.text, fingerprint: encoded.id).size, 4);
    expect(
      decodeAdobeTable(
        encoded.text,
        fingerprint: encoded.id.toLowerCase(),
      ).size,
      4,
    );
    expect(
      () => decodeAdobeTable(
        encoded.text,
        fingerprint: '0123456789ABCDEF0123456789ABCDEF',
      ),
      _unreadable,
    );
  });

  test('characters outside the alphabet are skipped, as Adobe does', () {
    final table = ProfileTable.identity(3);
    final text = encodeAdobeTable(table).text;
    final spaced = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      spaced.write(text[i]);
      if (i % 64 == 63) spaced.write('\n  ');
    }
    _expectClose(decodeAdobeTable(spaced.toString()), table, step);
  });

  group('tables in another space are converted to sRGB in and out', () {
    test('an identity in linear ProPhoto stays an identity', () {
      final text = encodeAdobeTable(
        ProfileTable.identity(32),
        primaries: primariesProPhoto,
        gamma: gammaLinear,
      ).text;
      final decoded = decodeAdobeTable(text);
      expect(decoded.size, 32);
      // Linear interpolation of an identity is exact; what is left is the
      // 16-bit rounding seen through the sRGB curve (steep near black).
      _expectClose(decoded, ProfileTable.identity(32), 0.002);
    });

    test('identities in every declared space stay identities', () {
      for (final p in [
        primariesSrgb,
        primariesAdobe,
        primariesProPhoto,
        primariesP3,
        primariesRec2020,
      ]) {
        for (final g in [gammaSrgb, gamma18, gamma22, gammaRec2020]) {
          final text = encodeAdobeTable(
            ProfileTable.identity(9),
            primaries: p,
            gamma: g,
          ).text;
          _expectClose(decodeAdobeTable(text), ProfileTable.identity(9), 0.002);
        }
      }
    });

    test('a flat grey in gamma 1.8 ProPhoto becomes the same grey in sRGB', () {
      final text = encodeAdobeTable(
        _map(8, (r, g, b) => (0.5, 0.5, 0.5)),
        primaries: primariesProPhoto,
        gamma: gamma18,
      ).text;
      final decoded = decodeAdobeTable(text);
      final want = _srgbEncode(pow(0.5, 1.8).toDouble());
      for (final v in decoded.rgb) {
        expect(v, closeTo(want, 0.001));
      }
    });

    test('a channel swap in ProPhoto is applied in ProPhoto', () {
      // ProPhoto red is outside sRGB: swapping ProPhoto red and green turns
      // sRGB red into a green that sRGB clips. The point is that the result
      // differs from swapping sRGB channels, so the space was honoured.
      final text = encodeAdobeTable(
        _map(9, (r, g, b) => (g, r, b)),
        primaries: primariesProPhoto,
        gamma: gamma18,
      ).text;
      final decoded = decodeAdobeTable(text);
      // White and black stay put.
      final (wr, wg, wb) = decoded.sample(1, 1, 1);
      expect([wr, wg, wb], everyElement(closeTo(1, 0.002)));
      final (kr, kg, kb) = decoded.sample(0, 0, 0);
      expect([kr, kg, kb], everyElement(closeTo(0, 0.002)));
      // Pure sRGB red: no longer equal to a plain sRGB swap (0, 1, 0).
      final (rr, rg, rb) = decoded.sample(1, 0, 0);
      expect(rg, greaterThan(rr));
      expect((rr - 0).abs() + (rg - 1).abs() + rb, greaterThan(0.05));
    });
  });

  test('a 1D table becomes a 3D table that applies the curves', () {
    const n = 64;
    final text = encodeAdobeTable1D([
      for (var i = 0; i < n; i++)
        (i / (n - 1), pow(i / (n - 1), 2).toDouble(), 1 - i / (n - 1)),
    ]);
    final decoded = decodeAdobeTable(text);
    final (r, g, b) = decoded.sample(0.5, 0.5, 0.5);
    expect(r, closeTo(0.5, 0.002));
    expect(g, closeTo(0.25, 0.01));
    expect(b, closeTo(0.5, 0.002));
    final (r2, g2, b2) = decoded.sample(0.25, 1, 0);
    expect(r2, closeTo(0.25, 0.002));
    expect(g2, closeTo(1, 0.002));
    expect(b2, closeTo(1, 0.002));
  });

  group('bad input throws a FormatException', () {
    test('empty text', () {
      expect(() => decodeAdobeTable(''), _unreadable);
    });

    test('garbage text', () {
      expect(() => decodeAdobeTable('hello world, not a table'), _unreadable);
      expect(() => decodeAdobeTable('"<>&;,_\\'), _unreadable);
      expect(() => decodeAdobeTable('0' * 500), _unreadable);
    });

    test('truncated text', () {
      final text = encodeAdobeTable(_map(16, (r, g, b) => (r, b, g))).text;
      for (final cut in [1, 7, text.length ~/ 2, text.length - 9]) {
        expect(() => decodeAdobeTable(text.substring(0, cut)), _unreadable);
      }
    });

    test('a changed character', () {
      final text = encodeAdobeTable(ProfileTable.identity(8)).text;
      final i = text.length ~/ 2;
      final c = text[i] == '0' ? '1' : '0';
      final changed = '${text.substring(0, i)}$c${text.substring(i + 1)}';
      expect(() => decodeAdobeTable(changed), _unreadable);
    });

    Uint8List identityPayload({
      int type = 1,
      int version = 1,
      int dimensions = 3,
      int divisions = 3,
      int primaries = 0,
      int gamma = 1,
      int gamut = 0,
      double minAmount = 0,
      double maxAmount = 2,
    }) {
      final count = dimensions == 3
          ? divisions * divisions * divisions
          : divisions;
      return adobeTablePayload(
        type: type,
        version: version,
        dimensions: dimensions,
        divisions: divisions,
        samples: List.filled(count * 3, 0),
        primaries: primaries,
        gamma: gamma,
        gamut: gamut,
        minAmount: minAmount,
        maxAmount: maxAmount,
      );
    }

    test('the reference payload itself decodes', () {
      expect(decodeAdobeTable(encodeAdobeBinary(identityPayload())).size, 3);
    });

    test('a header that is not an RGB table', () {
      for (final p in [
        identityPayload(type: 0),
        identityPayload(type: 3),
        identityPayload(version: 2),
        identityPayload(dimensions: 2),
        identityPayload(divisions: 1),
        identityPayload(divisions: 65),
        identityPayload(primaries: 5),
        identityPayload(gamma: 5),
        identityPayload(gamut: 2),
        identityPayload(minAmount: -0.5),
        identityPayload(minAmount: 1.5, maxAmount: 2),
        identityPayload(maxAmount: 0.5),
        identityPayload(maxAmount: double.infinity),
      ]) {
        expect(() => decodeAdobeTable(encodeAdobeBinary(p)), _unreadable);
      }
    });

    test('a payload cut short', () {
      final p = identityPayload();
      final cut = Uint8List.sublistView(p, 0, p.length - 3);
      expect(() => decodeAdobeTable(encodeAdobeBinary(cut)), _unreadable);
    });

    test('a wrong uncompressed size', () {
      final good = encodeAdobeBinary(identityPayload());
      // Re-encode the same bytes with a size one larger than the data.
      final bytes = _decodeText(good);
      ByteData.sublistView(bytes).setUint32(
        0,
        ByteData.sublistView(bytes).getUint32(0, Endian.little) + 1,
        Endian.little,
      );
      expect(() => decodeAdobeTable(encodeAdobeText(bytes)), _unreadable);
    });

    test('a huge declared size is refused before inflating', () {
      final bytes = Uint8List.fromList([
        0xFF,
        0xFF,
        0xFF,
        0x7F,
        0x78,
        0x9C,
        3,
        0,
      ]);
      expect(() => decodeAdobeTable(encodeAdobeText(bytes)), _unreadable);
    });
  });
}

/// The text layer decoded by hand, to build a damaged input in a test.
Uint8List _decodeText(String text) {
  final out = <int>[];
  var value = 0, phase = 0, scale = 1;
  for (final c in text.codeUnits) {
    final d = adobeTableDigits.indexOf(String.fromCharCode(c));
    value += d * scale;
    scale *= 85;
    if (++phase == 5) {
      out.addAll([for (var k = 0; k < 4; k++) (value >> (8 * k)) & 0xFF]);
      value = 0;
      phase = 0;
      scale = 1;
    }
  }
  for (var k = 0; k < phase - 1; k++) {
    out.add((value >> (8 * k)) & 0xFF);
  }
  return Uint8List.fromList(out);
}
