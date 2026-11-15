@Tags(['slow'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/codec/jpeg_encoder.dart';

void main() {
  test('encodeJpeg on a 12-megapixel picture (prints the time)', () {
    const w = 4000, h = 3000;
    final rgba = Uint8List(w * h * 4);
    var seed = 12345;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        final n = (seed >> 16) & 15;
        final i = (y * w + x) * 4;
        rgba[i] = (x * 255 ~/ w + n) & 255;
        rgba[i + 1] = (y * 255 ~/ h + n) & 255;
        rgba[i + 2] = ((x + y) * 255 ~/ (w + h)) & 255;
        rgba[i + 3] = 255;
      }
    }
    encodeJpeg(rgba, 64, 64); // warm up
    final sw = Stopwatch()..start();
    final out = encodeJpeg(rgba, w, h, quality: 92);
    sw.stop();
    // ignore: avoid_print
    print('encodeJpeg 4000x3000 q92: ${sw.elapsedMilliseconds} ms, ${out.length} bytes');
    expect(out[0], 0xFF);
    expect(out[out.length - 1], 0xD9);
    expect(sw.elapsedMilliseconds, lessThan(2500));
  });
}
