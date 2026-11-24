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

  test('brush dabs are spaced by arc length across segments', () {
    final d = brushDabs(const [ui.Offset(0, 0), ui.Offset(40, 0)], 2);
    expect(d.length, 21);
    expect(d.first, ui.Offset.zero);
    expect(d.last, const ui.Offset(40, 0));
    // 2000 dense points along the same line lay the same dabs.
    final dense = [for (var i = 0; i < 2000; i++) ui.Offset(i * 40 / 1999, 0)];
    expect(brushDabs(dense, 2).length, 21);
    expect(dabSpacing(8), 2);
    expect(dabSpacing(1), 0.5);
    // A held point lays one dab; non-finite points lay none.
    expect(brushDabs(const [ui.Offset(1, 1), ui.Offset(1, 1)], 4).length, 1);
    expect(brushDabs(const [ui.Offset(double.nan, 1), ui.Offset(2, 2)], 4), [
      const ui.Offset(2, 2),
    ]);
  });

  test(
    'past the dab cap, paint strokes thin evenly and erases keep theirs',
    () {
      // 63 scribbles of 2000 points across the whole photo at the smallest
      // size, then an erase: far past the cap.
      final strokes = [
        for (var k = 0; k < 63; k++)
          BrushStroke([
            for (var i = 0; i < kMaxPoints; i++)
              (i.isEven ? 0.0 : 1.0, (k + i / kMaxPoints) / 64),
          ], size: 0.005),
        BrushStroke(
          [for (var i = 0; i < kMaxPoints; i++) (0.5, i / (kMaxPoints - 1))],
          size: 0.005,
          erase: true,
        ),
      ];
      expect(strokes.length, kMaxStrokes);
      const full = ui.Size(4000, 3000);
      final plan = planBrushDabs(BrushShape(strokes), full);
      final total = plan.fold(0, (n, d) => n + d.length);
      expect(total, lessThanOrEqualTo(kMaxBrushDabs + 2 * kMaxStrokes));
      expect(total, greaterThan(kMaxBrushDabs * 0.9));
      // Every stroke keeps dabs, in proportion to its length.
      final counts = [for (final d in plan.take(63)) d.length];
      expect(
        counts.reduce(math.min),
        greaterThan(counts.reduce(math.max) * 0.9),
      );
      // The erase is not thinned.
      final erase = strokes.last;
      final pts = [
        for (final q in erase.points)
          ui.Offset(q.$1 * full.width, q.$2 * full.height),
      ];
      expect(
        plan.last.length,
        brushDabs(pts, dabSpacing(brushRadius(erase, 4000))).length,
      );
      // A small cap thins the paint strokes, never drops one.
      final small = planBrushDabs(BrushShape(strokes), full, cap: 1000);
      expect(small.every((d) => d.length >= 2), isTrue);
    },
  );

  testWidgets('at the limits, the last stroke still erases its area', (
    t,
  ) async {
    await withR(t, () async {
      // 63 realistic drags, 2000 points each, then an erase down the middle.
      final strokes = [
        for (var k = 0; k < 63; k++)
          BrushStroke([
            for (var i = 0; i < kMaxPoints; i++)
              (0.02 + 0.96 * i / (kMaxPoints - 1), (k + 0.5) / 63),
          ], size: 0.02),
        BrushStroke(
          [for (var i = 0; i < kMaxPoints; i++) (0.5, i / (kMaxPoints - 1))],
          size: 0.05,
          feather: 0,
          erase: true,
        ),
      ];
      final c = await one(BrushShape(strokes));
      for (var y = 4; y < 60; y++) {
        expect(c.at(32, y), lessThan(0.02), reason: 'erased at y $y');
        expect(c.at(12, y), greaterThan(0.9), reason: 'painted at y $y');
      }
    });
  });

  testWidgets('a mask far past the dab cap still draws and erases', (t) async {
    await withR(t, () async {
      final strokes = [
        for (var k = 0; k < 63; k++)
          BrushStroke([
            for (var i = 0; i < kMaxPoints; i++)
              (i.isEven ? 0.0 : 1.0, (k + i / kMaxPoints) / 64),
          ], size: 0.005),
        BrushStroke(
          [for (var i = 0; i < kMaxPoints; i++) (0.5, i / (kMaxPoints - 1))],
          size: 0.05,
          feather: 0,
          erase: true,
        ),
      ];
      final c = await one(BrushShape(strokes));
      for (var y = 4; y < 60; y++) {
        expect(c.at(32, y), lessThan(0.02), reason: 'erased at y $y');
      }
    });
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
      final src = await imageFromRgba(
        fillRgba(kW, kH, (x, y) => (x * 4, y * 4, 255 - x * 2 - y * 2)),
        kW,
        kH,
      );
      // A 16 x 12 gradient map: stretched with filtering over the photo.
      final map = await recordImage(
        16,
        12,
        (c) => c.drawRect(
          const ui.Rect.fromLTWH(0, 0, 16, 12),
          ui.Paint()
            ..shader = ui.Gradient.linear(
              ui.Offset.zero,
              const ui.Offset(16, 12),
              const [ui.Color(0x00FFFFFF), ui.Color(0xFFFFFFFF)],
            ),
        ),
      );
      final auto = FakeAuto(map, map);
      final masks = [
        mask([
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
        ]),
        mask([
          MaskComponent(
            ColourRangeShape([(0.5, 0.5, 0.5), (0.9, 0.2, 0.4)], refine: 80),
          ),
          const MaskComponent(SubjectShape()),
          const MaskComponent(SkyShape(), op: MaskOp.subtract),
          const MaskComponent(BackgroundShape()),
        ]),
      ];
      // Halves split across x, then across y.
      final parts = [
        const ui.Rect.fromLTWH(0, 0, 32, 64),
        const ui.Rect.fromLTWH(32, 0, 32, 64),
        const ui.Rect.fromLTWH(0, 0, 64, 32),
        const ui.Rect.fromLTWH(0, 32, 64, 32),
      ];
      try {
        for (final m in masks) {
          final whole = await cov(m, src: src, auto: auto);
          var worst = 0.0;
          for (final part in parts) {
            final pw = part.width.toInt(), ph = part.height.toInt();
            final x0 = part.left.toInt(), y0 = part.top.toInt();
            final psrc = await recordImage(
              pw,
              ph,
              (c) => c.drawImage(
                src,
                ui.Offset(-part.left, -part.top),
                ui.Paint(),
              ),
            );
            try {
              final p = await cov(
                m,
                src: psrc,
                origin: part.topLeft,
                auto: auto,
              );
              for (var y = 0; y < ph; y++) {
                for (var x = 0; x < pw; x++) {
                  worst = math.max(
                    worst,
                    (p.at(x, y) - whole.at(x0 + x, y0 + y)).abs(),
                  );
                }
              }
            } finally {
              psrc.dispose();
            }
          }
          // (2/255 exactly, with room for the float subtraction)
          expect(worst, lessThanOrEqualTo(2 / 255 + 1e-9));
          // The mask is partly covered, so the comparison means something.
          var lo = 1.0, hi = 0.0;
          for (var y = 0; y < kH; y++) {
            for (var x = 0; x < kW; x++) {
              lo = math.min(lo, whole.at(x, y));
              hi = math.max(hi, whole.at(x, y));
            }
          }
          expect(lo, lessThan(0.1));
          expect(hi, greaterThan(0.5));
        }
      } finally {
        map.dispose();
        src.dispose();
      }
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
