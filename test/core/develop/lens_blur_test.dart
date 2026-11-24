import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/mask_raster.dart';
import 'package:pio_photo_layout/core/develop/masks.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/develop/shader_developer.dart';

import 'develop_images.dart';

class _FakeAuto implements AutoMapsSource {
  _FakeAuto(this.subject, this.sky);
  @override
  final ui.Image subject;
  @override
  final ui.Image sky;
}

EditSettings lensOn(
  LensBlur lens, {
  Map<Setting, double> values = const {},
  List<Mask>? masks,
}) => EditSettings.resolve([
  SettingsPatch(values: values, masks: masks, lensBlur: lens),
]);

/// Develops [rgba] (w wide) and returns the output bytes.
Future<Uint8List> run(
  PhotoDeveloper dev,
  Uint8List rgba,
  EditSettings s, {
  int w = kSide,
  ui.Offset origin = ui.Offset.zero,
  ui.Size? fullSize,
  AutoMapsSource? auto,
}) async {
  final src = await image(rgba, w, rgba.length ~/ 4 ~/ w);
  final out = await dev.develop(
    src,
    s,
    origin: origin,
    fullSize: fullSize,
    auto: auto,
  );
  final px = await readRgba(out);
  out.dispose();
  src.dispose();
  return px;
}

int worstDiff(Uint8List a, Uint8List b) {
  var worst = 0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 == 3) continue;
    worst = math.max(worst, (a[i] - b[i]).abs());
  }
  return worst;
}

/// Luma variance over the box.
double variance(Uint8List px, int x0, int y0, int x1, int y1) =>
    stats(x0, y0, x1, y1, (x, y) => lumaAt(px, kSide, x, y)).$2;

/// Mean luma over the box.
double mean(Uint8List px, int x0, int y0, int x1, int y1) =>
    stats(x0, y0, x1, y1, (x, y) => lumaAt(px, kSide, x, y)).$1;

/// The four 24 px corner boxes, as (x0, y0, x1, y1).
const corners = [
  (0, 0, 24, 24),
  (232, 0, 256, 24),
  (0, 232, 24, 256),
  (232, 232, 256, 256),
];

void main() {
  late ShaderDeveloper dev;

  Future<void> withDev(WidgetTester t, Future<void> Function() body) =>
      t.runAsync(() async {
        dev = await ShaderDeveloper.load();
        try {
          await body();
        } finally {
          dev.dispose();
        }
      });

  testWidgets('amount 0 changes nothing', (t) async {
    await withDev(t, () async {
      final src = richRgba(1);
      const values = {Setting.exposure: 0.3};
      final plain = await run(
        dev,
        src,
        EditSettings.resolve([SettingsPatch(values: values)]),
      );
      final zero = await run(
        dev,
        src,
        lensOn(
          LensBlur(amount: 0, focus: LensFocus.point, boost: 100),
          values: values,
        ),
      );
      expect(worstDiff(zero, plain), 0);
      const full = ui.Size(256, 256);
      expect(
        dev.margin(lensOn(LensBlur(focus: LensFocus.point)), 1, fullSize: full),
        0,
      );
    });
  });

  testWidgets('point focus keeps the centre and blurs the corners', (t) async {
    await withDev(t, () async {
      final src = noiseRgba(40, 3);
      final out = await run(
        dev,
        src,
        lensOn(LensBlur(amount: 100, focus: LensFocus.point)),
      );
      final vIn = variance(src, 112, 112, 144, 144);
      final vOut = variance(out, 112, 112, 144, 144);
      expect(vOut, closeTo(vIn, vIn * 0.02), reason: 'the centre stays sharp');
      for (final (x0, y0, x1, y1) in corners) {
        final a = variance(src, x0, y0, x1, y1);
        final b = variance(out, x0, y0, x1, y1);
        // ignore: avoid_print
        print('corner ($x0, $y0): variance $a -> $b');
        expect(b, lessThan(0.4 * a), reason: 'corner ($x0, $y0)');
      }
    });
  });

  testWidgets('boost spreads a bright dot brighter', (t) async {
    await withDev(t, () async {
      // Grey 60 with a white 3 x 3 dot at (24, 24), far out of focus.
      final src = fillRgba(kSide, kSide, (x, y) {
        final dot = (x - 24).abs() <= 1 && (y - 24).abs() <= 1;
        return dot ? (255, 255, 255) : (60, 60, 60);
      });
      Future<Uint8List> at(double boost) => run(
        dev,
        src,
        lensOn(LensBlur(amount: 100, focus: LensFocus.point, boost: boost)),
      );
      final plain = await at(0);
      final boosted = await at(100);
      final mPlain = mean(plain, 18, 18, 31, 31);
      final mBoost = mean(boosted, 18, 18, 31, 31);
      // ignore: avoid_print
      print('dot spread: boost 0 $mPlain, boost 100 $mBoost');
      expect(mBoost, greaterThan(mPlain + 10));
      // Away from highlights, boost changes nothing.
      expect(mean(boosted, 200, 200, 230, 230), closeTo(60, 1));
    });
  });

  testWidgets('a bright spot spreads into a filled disc at a large radius', (
    t,
  ) async {
    await withDev(t, () async {
      // A 256 px region at the centre of a 4000 px photo: the radius is
      // 2 % of 4000 = 80 px. Focus on the far corner, so the region is all
      // out of focus. The spot is 6 px in radius, not one pixel: an 8-bit
      // prefilter spreads a single pixel below one level.
      const full = ui.Size(4000, 4000);
      const origin = ui.Offset(1872, 1872);
      final src = fillRgba(kSide, kSide, (x, y) {
        final d = math.sqrt(
          math.pow(x + 0.5 - 128, 2) + math.pow(y + 0.5 - 128, 2),
        );
        return d <= 6 ? (255, 255, 255) : (0, 0, 0);
      });
      final s = lensOn(
        LensBlur(amount: 100, focus: LensFocus.point, fx: 0, fy: 0, boost: 100),
      );
      // Luma mean and coefficient of variation inside 0.7 x the radius.
      Future<(double, double)> disc() async {
        final out = await run(dev, src, s, origin: origin, fullSize: full);
        var sum = 0.0, sum2 = 0.0, n = 0;
        for (var y = 0; y < kSide; y++) {
          for (var x = 0; x < kSide; x++) {
            final d = math.sqrt(
              math.pow(x + 0.5 - 128, 2) + math.pow(y + 0.5 - 128, 2),
            );
            if (d > 56) continue;
            final l = lumaAt(out, kSide, x, y);
            sum += l;
            sum2 += l * l;
            n++;
          }
        }
        final mean = sum / n;
        return (mean, math.sqrt(math.max(sum2 / n - mean * mean, 0)) / mean);
      }

      final (mean, cv) = await disc();
      dev.debugLensPrefilter = false;
      final (rawMean, rawCv) = await disc();
      // ignore: avoid_print
      print(
        'spot at R 80: prefilter mean $mean cv $cv; '
        'taps only mean $rawMean cv $rawCv',
      );
      expect(
        mean,
        greaterThan(rawMean / 2),
        reason: 'the disc keeps its light',
      );
      expect(cv, lessThan(0.35), reason: 'the disc is filled');
      expect(cv, lessThan(rawCv / 4), reason: 'the taps alone leave dots');
    });
  });

  testWidgets('two tiles with margin() match one whole render', (t) async {
    await withDev(t, () async {
      final s = lensOn(
        LensBlur(amount: 100, focus: LensFocus.point, fx: .25, boost: 50),
        values: {Setting.clarity: 30},
      );
      const full = ui.Size(256, 256);
      final m = dev.margin(s, 1, fullSize: full);
      final clarityOnly = dev.margin(
        EditSettings.resolve([
          SettingsPatch(values: {Setting.clarity: 30}),
        ]),
        1,
        fullSize: full,
      );
      // The lens reach: the radius (2 % of 256 px) plus 3 prefilter sigmas
      // (0.13 x radius each), rounded up, plus 2 px.
      expect(m, clarityOnly + (0.02 * 256 * 1.39).ceil() + 2);
      final src = richRgba(4);
      final whole = await run(dev, src, s);

      Future<Uint8List> tile(int x0, int w) => run(
        dev,
        cropRgba(src, kSide, x0, 0, w, kSide),
        s,
        w: w,
        origin: ui.Offset(x0.toDouble(), 0),
        fullSize: full,
      );

      Future<int> seamDiff(int mm) async {
        final a = await tile(0, 128 + mm);
        final b = await tile(128 - mm, 128 + mm);
        var worst = 0;
        for (var y = 0; y < kSide; y++) {
          for (var x = 0; x < kSide; x++) {
            final w = (y * kSide + x) * 4;
            final i = x < 128
                ? (y * (128 + mm) + x) * 4
                : (y * (128 + mm) + x - (128 - mm)) * 4;
            final tl = x < 128 ? a : b;
            for (var k = 0; k < 3; k++) {
              worst = math.max(worst, (tl[i + k] - whole[w + k]).abs());
            }
          }
        }
        return worst;
      }

      final worst = await seamDiff(m);
      final thin = await seamDiff(1);
      // ignore: avoid_print
      print('lens tiles: margin $m, max diff $worst levels; 1 px: $thin');
      expect(worst, lessThanOrEqualTo(2));
      expect(thin, greaterThan(worst + 3));
    });
  });

  testWidgets('mask focus keeps the mask sharp; a missing mask falls back', (
    t,
  ) async {
    await withDev(t, () async {
      final src = noiseRgba(40, 7);
      final focusMask = Mask(
        id: 'f',
        components: [
          MaskComponent(
            RadialShape(cx: .5, cy: .5, rx: .25, ry: .25, feather: 0),
          ),
        ],
      );
      final out = await run(
        dev,
        src,
        lensOn(
          LensBlur(amount: 100, focus: LensFocus.mask, maskId: 'f'),
          masks: [focusMask],
        ),
      );
      final vIn = variance(src, 112, 112, 144, 144);
      expect(variance(out, 112, 112, 144, 144), closeTo(vIn, vIn * 0.02));
      for (final (x0, y0, x1, y1) in corners) {
        expect(
          variance(out, x0, y0, x1, y1),
          lessThan(0.4 * variance(src, x0, y0, x1, y1)),
        );
      }

      // A missing mask means the subject; without automatic maps the
      // subject is everything, so nothing is blurred.
      final none = await run(
        dev,
        src,
        lensOn(LensBlur(amount: 100, focus: LensFocus.mask, maskId: 'gone')),
      );
      expect(worstDiff(none, src), 0);
    });
  });

  testWidgets('subject focus reads the automatic subject', (t) async {
    await withDev(t, () async {
      final src = noiseRgba(40, 9);
      // Subject: the left half of the photo (a 16 x 16 map, stretched).
      final map = await image(_halfAlpha(), 16, 16);
      final auto = _FakeAuto(map, map);
      try {
        final out = await run(
          dev,
          src,
          lensOn(LensBlur(amount: 100)),
          auto: auto,
        );
        final left = variance(src, 16, 100, 80, 156);
        expect(variance(out, 16, 100, 80, 156), closeTo(left, left * 0.02));
        final right = variance(src, 176, 100, 240, 156);
        expect(variance(out, 176, 100, 240, 156), lessThan(0.4 * right));
      } finally {
        map.dispose();
      }
    });
  });

  testWidgets('the focus map is drawn once and freed by clearCache', (t) async {
    await withDev(t, () async {
      final src = await image(noiseRgba(20, 2));
      final s = lensOn(LensBlur(amount: 60, focus: LensFocus.point));
      for (var i = 0; i < 2; i++) {
        (await dev.develop(src, s)).dispose();
      }
      expect(dev.debugFocusMapsDrawn, 1);
      dev.clearCache();
      (await dev.develop(src, s)).dispose();
      expect(dev.debugFocusMapsDrawn, 2);
      // Another transition is another map.
      (await dev.develop(
        src,
        lensOn(LensBlur(amount: 60, focus: LensFocus.point, transition: 10)),
      )).dispose();
      expect(dev.debugFocusMapsDrawn, 3);
      src.dispose();
    });
  });

  testWidgets('the lens reach fits kMaxMarginPx: masks shrink first', (
    t,
  ) async {
    await withDev(t, () async {
      const full = ui.Size(8000, 6000);
      final lens = LensBlur(amount: 100);
      final masks = [
        for (var i = 0; i < 8; i++)
          Mask(
            id: 'm$i',
            components: [MaskComponent(RadialShape())],
            adjust: {Setting.clarity: 100},
          ),
      ];
      const global = {Setting.clarity: 100.0};
      final g = dev.margin(
        EditSettings.resolve([SettingsPatch(values: global)]),
        1,
        fullSize: full,
      );
      final lensOnly = dev.margin(lensOn(lens), 1, fullSize: full);
      // 2 % of 8000 px, plus 3 prefilter sigmas of 0.13 x that.
      expect(lensOnly, (160 * 1.39).ceil() + 2);
      final all = dev.margin(
        lensOn(lens, values: global, masks: masks),
        1,
        fullSize: full,
      );
      // ignore: avoid_print
      print('8000 px: global $g, lens $lensOnly, all $all');
      expect(all, lessThanOrEqualTo(kMaxMarginPx));
      expect(all, greaterThan(g + lensOnly), reason: 'masks keep some reach');

      // When the global blur and the lens alone pass the cap, the lens
      // radius is cut to the room left.
      dev.debugMaxMarginPx = g + 50;
      expect(
        dev.margin(lensOn(lens, values: global), 1, fullSize: full),
        g + 50,
      );
    });
  });

  testWidgets('tiles match a whole render when the cap cuts the lens', (
    t,
  ) async {
    await withDev(t, () async {
      final s = lensOn(
        LensBlur(amount: 100, focus: LensFocus.point, fx: .2),
        values: {Setting.clarity: 30},
      );
      const full = ui.Size(256, 256);
      final uncapped = dev.margin(s, 1, fullSize: full);
      dev.debugMaxMarginPx = uncapped - 3;
      final m = dev.margin(s, 1, fullSize: full);
      expect(m, uncapped - 3);
      final src = richRgba(6);
      final whole = await run(dev, src, s);
      Future<Uint8List> tile(int x0, int w) => run(
        dev,
        cropRgba(src, kSide, x0, 0, w, kSide),
        s,
        w: w,
        origin: ui.Offset(x0.toDouble(), 0),
        fullSize: full,
      );
      final a = await tile(0, 128 + m);
      final b = await tile(128 - m, 128 + m);
      var worst = 0;
      for (var y = 0; y < kSide; y++) {
        for (var x = 0; x < kSide; x++) {
          final w = (y * kSide + x) * 4;
          final i = x < 128
              ? (y * (128 + m) + x) * 4
              : (y * (128 + m) + x - (128 - m)) * 4;
          final tl = x < 128 ? a : b;
          for (var k = 0; k < 3; k++) {
            worst = math.max(worst, (tl[i + k] - whole[w + k]).abs());
          }
        }
      }
      expect(worst, lessThanOrEqualTo(2));
    });
  });

  testWidgets('the CPU fake blurs out of focus too', (t) async {
    await t.runAsync(() async {
      final cpu = CpuDeveloper();
      final src = noiseRgba(40, 5);
      final out = await run(
        cpu,
        src,
        lensOn(LensBlur(amount: 100, focus: LensFocus.point)),
      );
      final vIn = variance(src, 112, 112, 144, 144);
      expect(variance(out, 112, 112, 144, 144), closeTo(vIn, vIn * 0.02));
      final (x0, y0, x1, y1) = corners.first;
      expect(
        variance(out, x0, y0, x1, y1),
        lessThan(0.4 * variance(src, x0, y0, x1, y1)),
      );
      expect(
        cpu.margin(
          lensOn(LensBlur(amount: 100)),
          1,
          fullSize: const ui.Size(256, 256),
        ),
        greaterThan(0),
      );
    });
  });
}

/// Alpha 255 on the left half of a 16 x 16 white RGBA map, 0 on the right.
Uint8List _halfAlpha() {
  final out = Uint8List(16 * 16 * 4);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      final i = (y * 16 + x) * 4;
      final a = x < 8 ? 255 : 0;
      out[i] = 255;
      out[i + 1] = 255;
      out[i + 2] = 255;
      out[i + 3] = a;
    }
  }
  return out;
}
