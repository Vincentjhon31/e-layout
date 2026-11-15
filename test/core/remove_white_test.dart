import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/analysis/remove_white.dart';

/// 40x40 white picture with a navy square ring (outer 10..30, 4 px thick):
/// the white outside the ring touches the edges, the white inside does not.
Uint8List ringPicture() {
  const n = 40;
  final px = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final i = (y * n + x) * 4;
      final outer = x >= 10 && x < 30 && y >= 10 && y < 30;
      final inner = x >= 14 && x < 26 && y >= 14 && y < 26;
      final navy = outer && !inner;
      px[i] = navy ? 20 : 255;
      px[i + 1] = navy ? 33 : 255;
      px[i + 2] = navy ? 46 : 255;
      px[i + 3] = 255;
    }
  }
  return px;
}

int alphaAt(Uint8List px, int x, int y) => px[(y * 40 + x) * 4 + 3];

void main() {
  test('removeWhite clears the white border and keeps an enclosed white area', () {
    final px = ringPicture();
    final cleared = removeWhitePixels(px, 40, 40, 20);
    expect(cleared, greaterThan(1000));
    expect(alphaAt(px, 0, 0), 0);
    expect(alphaAt(px, 5, 20), 0);
    expect(alphaAt(px, 39, 39), 0);
    // The ring itself stays.
    expect(alphaAt(px, 11, 20), 255);
    expect(alphaAt(px, 28, 28), 255);
    // White inside the ring stays.
    expect(alphaAt(px, 20, 20), 255);
    expect(alphaAt(px, 15, 25), 255);
  });

  test('a picture with no white at the edges is left alone', () {
    final px = Uint8List(10 * 10 * 4);
    for (var i = 0; i < px.length; i += 4) {
      px[i] = 10;
      px[i + 1] = 20;
      px[i + 2] = 30;
      px[i + 3] = 255;
    }
    expect(removeWhitePixels(px, 10, 10, 20), 0);
    expect(px[3], 255);
  });

  test('a higher tolerance also removes near-white greys', () {
    Uint8List grey() {
      final px = Uint8List(8 * 8 * 4);
      for (var i = 0; i < px.length; i += 4) {
        px[i] = px[i + 1] = px[i + 2] = 240;
        px[i + 3] = 255;
      }
      return px;
    }

    final low = grey();
    expect(removeWhitePixels(low, 8, 8, 5), 0);
    final high = grey();
    expect(removeWhitePixels(high, 8, 8, 30), 64);
  });
}
