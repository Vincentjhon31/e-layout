import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/mask_raster.dart';
import 'package:pio_photo_layout/core/develop/masks.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';

import 'develop_images.dart';

const int kW = 64, kH = 64;

/// Alpha plane (0..1) of a coverage image, row-major.
class Cov {
  Cov(this.w, this.h, this.rgba);
  final int w, h;
  final Uint8List rgba;
  double at(int x, int y) => rgba[(y * w + x) * 4 + 3] / 255;
}

Mask mask(List<MaskComponent> c) => Mask(id: 'm', components: c);

class FakeAuto implements AutoMapsSource {
  FakeAuto(this.subject, this.sky);
  @override
  final ui.Image subject;
  @override
  final ui.Image sky;
}

void main() {
  late MaskRasterizer r;
  late ui.Image grey; // 64 x 64, grey ramp left to right

  Future<void> withR(WidgetTester t, Future<void> Function() body) =>
      t.runAsync(() async {
        r = await MaskRasterizer.load();
        grey = await imageFromRgba(
          fillRgba(kW, kH, (x, y) {
            final v = (x * 255 / (kW - 1)).round();
            return (v, v, v);
          }),
          kW,
          kH,
        );
        try {
          await body();
        } finally {
          grey.dispose();
        }
      });

  Future<Cov> cov(
    Mask m, {
    ui.Image? src,
    ui.Offset origin = ui.Offset.zero,
    ui.Size fullSize = const ui.Size(64, 64),
    AutoMapsSource? auto,
  }) async {
    final s = src ?? grey;
    final img = await r.coverage(
      m,
      src: s,
      origin: origin,
      fullSize: fullSize,
      scale: 1,
      auto: auto,
    );
    expect(img.width, s.width);
    expect(img.height, s.height);
    final px = await readRgba(img);
    img.dispose();
    // White RGB wherever there is coverage.
    for (var i = 0; i < px.length; i += 4) {
      if (px[i + 3] > 8) {
        expect(px[i], greaterThanOrEqualTo(250));
      }
    }
    return Cov(s.width, s.height, px);
  }

  Future<Cov> one(MaskShape s) => cov(mask([MaskComponent(s)]));

  testWidgets('radial, feather 0: centre covered, corner not', (t) async {
    await withR(t, () async {
      final c = await one(RadialShape(feather: 0));
      expect(c.at(32, 32), greaterThan(0.99));
      expect(c.at(0, 0), lessThan(0.01));
      expect(c.at(63, 63), lessThan(0.01));
    });
  });

  testWidgets('radial, feather 50: the middle of the feather is partial', (
    t,
  ) async {
    await withR(t, () async {
      // Radius 16 px from (32, 32); full inside 8 px, none past 16 px.
      // Pixel centre (44.5, 32.5) is 12.5 px out: in the middle of the band.
      final c = await one(RadialShape(feather: 50));
      expect(c.at(44, 32), inInclusiveRange(0.2, 0.8));
      expect(c.at(32, 32), greaterThan(0.99));
      expect(c.at(60, 32), lessThan(0.01));
    });
  });

  testWidgets('radial invert flips the coverage', (t) async {
    await withR(t, () async {
      final c = await one(RadialShape(feather: 0, invert: true));
      expect(c.at(32, 32), lessThan(0.01));
      expect(c.at(0, 0), greaterThan(0.99));
    });
  });

  testWidgets('linear: full at (x0, y0), none at (x1, y1)', (t) async {
    await withR(t, () async {
      final c = await one(LinearShape(0.25, 0.5, 0.75, 0.5));
      expect(c.at(4, 32), greaterThan(0.99));
      expect(c.at(16, 10), greaterThan(0.97));
      expect(c.at(32, 32), inInclusiveRange(0.3, 0.7));
      expect(c.at(50, 32), lessThan(0.03));
      expect(c.at(60, 50), lessThan(0.01));
    });
  });

  testWidgets('brush paints its path, not far away; erase clears', (t) async {
    await withR(t, () async {
      final stroke = BrushStroke([(0.2, 0.5), (0.8, 0.5)], feather: 0);
      final c = await one(BrushShape([stroke]));
      expect(c.at(32, 32), greaterThan(0.95));
      expect(c.at(20, 32), greaterThan(0.95));
      expect(c.at(32, 10), lessThan(0.01));
      expect(c.at(2, 32), lessThan(0.01));

      final erased = await one(
        BrushShape([
          stroke,
          BrushStroke([(0.5, 0.3), (0.5, 0.7)], feather: 0, erase: true),
        ]),
      );
      expect(erased.at(32, 32), lessThan(0.05));
      expect(erased.at(20, 32), greaterThan(0.95));
    });
  });

  testWidgets('brush flow is the stroke alpha, not built up by dabs', (
    t,
  ) async {
    await withR(t, () async {
      final c = await one(
        BrushShape([
          BrushStroke([(0.2, 0.5), (0.8, 0.5)], feather: 0, flow: 50),
        ]),
      );
      expect(c.at(32, 32), closeTo(0.5, 0.02));
    });
  });

  test('brush dabs are spaced a quarter radius apart and capped', () {
    final d = brushDabs(const [ui.Offset(0, 0), ui.Offset(40, 0)], 8, 1000);
    expect(d.length, 21);
    expect(d.first, ui.Offset.zero);
    expect(d.last, const ui.Offset(40, 0));
    final zigzag = [
      for (var i = 0; i < 2000; i++) ui.Offset(i.isEven ? 0 : 4000, 0),
    ];
    expect(brushDabs(zigzag, 0.5, 500).length, 500);
    // A held point lays one dab; non-finite points lay none.
    expect(
      brushDabs(const [ui.Offset(1, 1), ui.Offset(1, 1)], 4, 10).length,
      1,
    );
    expect(
      brushDabs(const [ui.Offset(double.nan, 1), ui.Offset(2, 2)], 4, 10),
      [const ui.Offset(2, 2)],
    );
  });

  testWidgets('add is the max, subtract a(1-c), intersect a*c', (t) async {
    await withR(t, () async {
      final a = RadialShape(rx: 0.4, ry: 0.4, feather: 60);
      final b = LinearShape(0.1, 0.2, 0.9, 0.8);
      final ca = await one(a);
      final cb = await one(b);
      final add = await cov(mask([MaskComponent(a), MaskComponent(b)]));
      final sub = await cov(
        mask([MaskComponent(a), MaskComponent(b, op: MaskOp.subtract)]),
      );
      final inter = await cov(
        mask([MaskComponent(a), MaskComponent(b, op: MaskOp.intersect)]),
      );
      var worstAdd = 0.0, worstSub = 0.0, worstInt = 0.0;
      for (var y = 0; y < kH; y++) {
        for (var x = 0; x < kW; x++) {
          final va = ca.at(x, y), vb = cb.at(x, y);
          worstAdd = math.max(
            worstAdd,
            (add.at(x, y) - math.max(va, vb)).abs(),
          );
          worstSub = math.max(worstSub, (sub.at(x, y) - va * (1 - vb)).abs());
          worstInt = math.max(worstInt, (inter.at(x, y) - va * vb).abs());
        }
      }
      expect(worstAdd, lessThanOrEqualTo(3 / 255));
      expect(worstSub, lessThanOrEqualTo(3 / 255));
      expect(worstInt, lessThanOrEqualTo(3 / 255));
      // And the shapes are really partial somewhere, so the test means something.
      expect(sub.at(32, 32), inInclusiveRange(0.2, 0.8));
    });
  });

  testWidgets('a first component that subtracts acts as add', (t) async {
    await withR(t, () async {
      final c = await cov(
        mask([MaskComponent(RadialShape(feather: 0), op: MaskOp.subtract)]),
      );
      expect(c.at(32, 32), greaterThan(0.99));
    });
  });

  testWidgets('luminance range covers only its band of a grey ramp', (t) async {
    await withR(t, () async {
      final c = await one(LuminanceRangeShape(low: 0.4, high: 0.6, smooth: 5));
      // x = 32 is 0.508; x = 8 is 0.127; x = 56 is 0.889.
      expect(c.at(32, 20), greaterThan(0.99));
      expect(c.at(8, 20), lessThan(0.01));
      expect(c.at(56, 20), lessThan(0.01));
      expect(c.at(0, 20), lessThan(0.01));
      expect(c.at(63, 20), lessThan(0.01));
    });
  });

  testWidgets('colour range picks the sampled red, not blue', (t) async {
    await withR(t, () async {
      final src = await imageFromRgba(
        fillRgba(kW, kH, (x, y) => x < 32 ? (230, 20, 20) : (20, 30, 220)),
        kW,
        kH,
      );
      try {
        final c = await cov(
          mask([
            MaskComponent(ColourRangeShape([(0.9, 0.08, 0.08)])),
          ]),
          src: src,
        );
        expect(c.at(10, 10), greaterThan(0.99));
        expect(c.at(50, 10), lessThan(0.01));
        final none = await cov(
          mask([MaskComponent(ColourRangeShape(const []))]),
          src: src,
        );
        expect(none.at(10, 10), lessThan(0.01));
      } finally {
        src.dispose();
      }
    });
  });

  testWidgets('subject, sky and background read the auto maps', (t) async {
    await withR(t, () async {
      // Auto maps at a different size from the photo: they are stretched.
      final left = await recordImage(
        16,
        16,
        (c) => c.drawRect(
          const ui.Rect.fromLTWH(0, 0, 8, 16),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        ),
      );
      final top = await recordImage(
        16,
        16,
        (c) => c.drawRect(
          const ui.Rect.fromLTWH(0, 0, 16, 8),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        ),
      );
      final auto = FakeAuto(left, top);
      try {
        final s = await cov(
          mask([const MaskComponent(SubjectShape())]),
          auto: auto,
        );
        expect(s.at(5, 32), greaterThan(0.99));
        expect(s.at(58, 32), lessThan(0.01));
        final b = await cov(
          mask([const MaskComponent(BackgroundShape())]),
          auto: auto,
        );
        expect(b.at(5, 32), lessThan(0.01));
        expect(b.at(58, 32), greaterThan(0.99));
        final k = await cov(
          mask([const MaskComponent(SkyShape())]),
          auto: auto,
        );
        expect(k.at(32, 5), greaterThan(0.99));
        expect(k.at(32, 58), lessThan(0.01));
        // Without auto maps every one of them covers nothing.
        for (final shape in const [
          SubjectShape(),
          SkyShape(),
          BackgroundShape(),
        ]) {
          final none = await cov(mask([MaskComponent(shape)]));
          expect(none.at(5, 32), lessThan(0.01));
          expect(none.at(58, 32), lessThan(0.01));
        }
      } finally {
        left.dispose();
        top.dispose();
      }
    });
  });

  testWidgets('coverage depends only on the photo position, not the region', (
    t,
  ) async {
    await withR(t, () async {
      final m = mask([
        MaskComponent(
          RadialShape(
            cx: 0.45,
            cy: 0.55,
            rx: 0.3,
            ry: 0.2,
            angle: 30,
            feather: 70,
          ),
        ),
        MaskComponent(
          BrushShape([
            BrushStroke([(0.3, 0.2), (0.55, 0.35), (0.7, 0.8)], feather: 60),
            BrushStroke(
              [(0.48, 0.1), (0.52, 0.9)],
              size: 0.03,
              feather: 80,
              flow: 60,
              erase: true,
            ),
          ]),
        ),
        MaskComponent(LinearShape(0.1, 0.9, 0.8, 0.3), op: MaskOp.subtract),
        MaskComponent(
          LuminanceRangeShape(low: 0.2, high: 0.8, smooth: 30),
          op: MaskOp.intersect,
        ),
      ]);
      final whole = await cov(m);
      Future<ui.Image> half(int x0) => recordImage(
        32,
        kH,
        (c) => c.drawImage(grey, ui.Offset(-x0.toDouble(), 0), ui.Paint()),
      );
      var worst = 0.0;
      for (final x0 in [0, 32]) {
        final src = await half(x0);
        try {
          final part = await cov(
            m,
            src: src,
            origin: ui.Offset(x0.toDouble(), 0),
          );
          for (var y = 0; y < kH; y++) {
            for (var x = 0; x < 32; x++) {
              worst = math.max(
                worst,
                (part.at(x, y) - whole.at(x0 + x, y)).abs(),
              );
            }
          }
        } finally {
          src.dispose();
        }
      }
      expect(worst, lessThanOrEqualTo(2 / 255));
      // The mask is not empty, so the comparison means something.
      var sum = 0.0;
      for (var i = 3; i < whole.rgba.length; i += 4) {
        sum += whole.rgba[i];
      }
      expect(sum, greaterThan(0));
    });
  });

  testWidgets('a tiny brush is clamped and out-of-range points stay inside', (
    t,
  ) async {
    await withR(t, () async {
      final tiny = BrushStroke([(0.5, 0.5)], size: 0.0001);
      expect(tiny.size, greaterThan(0.0001));
      await one(BrushShape([tiny]));

      final far = BrushStroke([(-5, 7)], feather: 0);
      final c = await one(BrushShape([far]));
      // (-5, 7) is clamped to the bottom-left corner (0, 1).
      expect(c.at(32, 32), lessThan(0.01));
      expect(c.at(0, 0), lessThan(0.01));
      expect(c.at(63, 0), lessThan(0.01));
      expect(c.at(63, 63), lessThan(0.01));
      expect(c.at(0, 63), greaterThan(0.5));
    });
  });

  testWidgets('an empty mask covers nothing', (t) async {
    await withR(t, () async {
      final c = await cov(mask(const []));
      expect(c.at(32, 32), lessThan(0.01));
    });
  });
}
