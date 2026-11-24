import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/auto_masks.dart';
import 'package:pio_photo_layout/core/develop/mask_raster.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';

import 'develop_images.dart';

class Alpha {
  Alpha(this.w, this.h, this.rgba);
  final int w, h;
  final Uint8List rgba;
  double at(int x, int y) => rgba[(y * w + x) * 4 + 3] / 255;

  /// Mean over the box [x0, x1) x [y0, y1), as fractions of the size.
  double mean(double x0, double y0, double x1, double y1) {
    var sum = 0.0, n = 0;
    for (var y = (y0 * h).floor(); y < (y1 * h).ceil(); y++) {
      for (var x = (x0 * w).floor(); x < (x1 * w).ceil(); x++) {
        sum += at(x, y);
        n++;
      }
    }
    return sum / n;
  }
}

void main() {
  Future<Alpha> read(ui.Image i) async =>
      Alpha(i.width, i.height, await readRgba(i));

  Future<void> checkFinite(AutoMaps m) async {
    for (final img in [m.subject, m.sky]) {
      final a = await read(img);
      for (var i = 0; i < a.w * a.h; i++) {
        final v = a.rgba[i * 4 + 3] / 255;
        expect(v.isFinite && v >= 0 && v <= 1, isTrue);
      }
    }
    expect(m.subjectPoint.$1.isFinite && m.subjectPoint.$2.isFinite, isTrue);
    expect(m.subjectPoint.$1, inInclusiveRange(0, 1));
    expect(m.subjectPoint.$2, inInclusiveRange(0, 1));
  }

  testWidgets('sky: blue top half is sky, green bottom half is not', (t) async {
    await t.runAsync(() async {
      final photo = await imageFromRgba(
        fillRgba(200, 200, (x, y) {
          if (y < 100) return (90 + y ~/ 4, 150 + y ~/ 4, 255);
          return (30, 140 - (y - 100) ~/ 4, 40);
        }),
        200,
        200,
      );
      final m = await computeAutoMaps(photo);
      final sky = await read(m.sky);
      expect(sky.mean(0, 0, 1, 0.25), greaterThan(0.6));
      expect(sky.mean(0, 0.75, 1, 1), lessThan(0.1));
      m.dispose();
      photo.dispose();
    });
  });

  testWidgets('subject: textured centre beats the corners; point is central', (
    t,
  ) async {
    await t.runAsync(() async {
      final rnd = math.Random(3);
      final photo = await imageFromRgba(
        fillRgba(240, 240, (x, y) {
          final inside = x >= 90 && x < 150 && y >= 90 && y < 150;
          final v = inside ? 40 + rnd.nextInt(180) : 128;
          return (v, v, v);
        }),
        240,
        240,
      );
      final m = await computeAutoMaps(photo);
      final s = await read(m.subject);
      final centre = s.mean(0.4, 0.4, 0.6, 0.6);
      final corners =
          [
            s.mean(0, 0, 0.1, 0.1),
            s.mean(0.9, 0, 1, 0.1),
            s.mean(0, 0.9, 0.1, 1),
            s.mean(0.9, 0.9, 1, 1),
          ].reduce((a, b) => a + b) /
          4;
      expect(centre, greaterThan(2 * corners));
      expect((m.subjectPoint.$1 - 0.5).abs(), lessThan(0.15));
      expect((m.subjectPoint.$2 - 0.5).abs(), lessThan(0.15));
      m.dispose();
      photo.dispose();
    });
  });

  testWidgets('large photos are mapped at 384 px or less', (t) async {
    await t.runAsync(() async {
      final photo = await imageFromRgba(
        fillRgba(900, 450, (x, y) => (x % 256, y % 256, 90)),
        900,
        450,
      );
      final m = await computeAutoMaps(photo);
      expect(m.subject.width, 384);
      expect(m.subject.height, 192);
      expect(m.sky.width, 384);
      m.dispose();
      photo.dispose();
    });
  });

  testWidgets('1x1, white and black photos give finite maps', (t) async {
    await t.runAsync(() async {
      for (final c in [(128, 128, 128), (255, 255, 255), (0, 0, 0)]) {
        for (final (w, h) in [(1, 1), (32, 20)]) {
          final photo = await imageFromRgba(fillRgba(w, h, (x, y) => c), w, h);
          final m = await computeAutoMaps(photo);
          await checkFinite(m);
          m.dispose();
          photo.dispose();
        }
      }
    });
  });

  testWidgets('AutoMaps is an AutoMapsSource', (t) async {
    await t.runAsync(() async {
      final photo = await imageFromRgba(
        fillRgba(8, 8, (x, y) => (10, 20, 30)),
        8,
        8,
      );
      final AutoMapsSource m = await computeAutoMaps(photo);
      expect(m.subject.width, 8);
      (m as AutoMaps).dispose();
      photo.dispose();
    });
  });
}
