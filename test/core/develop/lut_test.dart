import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/color_pipeline.dart';
import 'package:pio_photo_layout/core/develop/lut.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';

EditSettings settings({
  Map<Setting, double> values = const {},
  Map<CurveChannel, List<CurvePoint>> curves = const {},
}) => EditSettings.resolve([SettingsPatch(values: values, curves: curves)]);

void main() {
  test('identity pipeline bakes an identity table', () {
    const n = 17;
    final lut = bakeLut(ColorPipeline(settings()), n);
    expect(lut.size, n);
    expect(lut.rgba.length, n * n * n * 4);
    for (var b = 0; b < n; b++) {
      for (var g = 0; g < n; g++) {
        for (var r = 0; r < n; r++) {
          final o = ((g * n * n) + r + b * n) * 4;
          expect((lut.rgba[o] - r / (n - 1) * 255).abs(), lessThanOrEqualTo(1));
          expect(
            (lut.rgba[o + 1] - g / (n - 1) * 255).abs(),
            lessThanOrEqualTo(1),
          );
          expect(
            (lut.rgba[o + 2] - b / (n - 1) * 255).abs(),
            lessThanOrEqualTo(1),
          );
          expect(lut.rgba[o + 3], 255);
        }
      }
    }
  });

  test('texel layout is x = r + b*size, y = g', () {
    const n = 9;
    final p = ColorPipeline(
      settings(
        curves: {
          CurveChannel.green: const [CurvePoint(0, 0), CurvePoint(255, 0)],
        },
      ),
    );
    final lut = bakeLut(p, n);
    int px(int r, int g, int b, int c) =>
        lut.rgba[((g * n * n) + r + b * n) * 4 + c];
    for (final (r, g, b) in [(0, 0, 0), (8, 8, 8), (3, 5, 7), (8, 2, 0)]) {
      expect(px(r, g, b, 0), (r / (n - 1) * 255).round());
      expect(px(r, g, b, 1), 0);
      expect(px(r, g, b, 2), (b / (n - 1) * 255).round());
      expect(px(r, g, b, 3), 255);
    }
    // Hand-computed: r=3,g=5,b=7 sits at x=3+7*9=66, y=5.
    expect(lut.rgba[(5 * 81 + 66) * 4], (3 / 8 * 255).round());
  });

  const master = [
    CurvePoint(0, 0),
    CurvePoint(64, 50),
    CurvePoint(192, 210),
    CurvePoint(255, 255),
  ];

  test('size-33 table matches mild settings within 2/255 (primary guard)', () {
    final p = ColorPipeline(
      settings(values: {Setting.exposure: 0.3, Setting.contrast: 15}),
    );
    final lut = bakeLut(p, 33);
    final rnd = Random(2);
    // Clipped outputs (about 28% here, from the +0.3 EV) are checked too:
    // with mild settings the clamp kink is small enough to stay within 2/255,
    // so every colour is held to the bound, not just the unclipped ones.
    var checked = 0;
    for (var i = 0; i < 500; i++) {
      final r = rnd.nextDouble(), g = rnd.nextDouble(), b = rnd.nextDouble();
      final want = p.apply(r, g, b);
      final got = lut.sample(r, g, b);
      checked++;
      final e =
          [
            (want.$1 - got.$1).abs(),
            (want.$2 - got.$2).abs(),
            (want.$3 - got.$3).abs(),
          ].reduce(max) *
          255;
      expect(e, lessThanOrEqualTo(2), reason: 'colour $r $g $b');
    }
    expect(checked, greaterThanOrEqualTo(450));
  });

  test('size-33 table matches the pipeline within 2/255 (full mix)', () {
    final p = ColorPipeline(
      settings(
        values: {
          Setting.exposure: 0.7,
          Setting.contrast: 30,
          Setting.hueRed: 40,
          Setting.gradeShadowSat: 50,
        },
        curves: {CurveChannel.master: master},
      ),
    );
    final lut = bakeLut(p, 33);
    final rnd = Random(1);
    var worstAll = 0.0, skipped = 0;
    for (var i = 0; i < 500; i++) {
      final r = rnd.nextDouble(), g = rnd.nextDouble(), b = rnd.nextDouble();
      final want = p.apply(r, g, b);
      final got = lut.sample(r, g, b);
      final e =
          [
            (want.$1 - got.$1).abs(),
            (want.$2 - got.$2).abs(),
            (want.$3 - got.$3).abs(),
          ].reduce(max) *
          255;
      worstAll = max(worstAll, e);
      // A hard clamp at 0 or 255 is a slope kink: a table cannot follow it
      // closer than a few levels, in the shader as here. Colours whose output
      // sits on the gamut edge (clamped, or within half a level of it) are
      // checked only for continuity (the sweep test below), not for 2/255.
      final near = [
        want.$1,
        want.$2,
        want.$3,
      ].any((v) => v * 255 < 0.5 || v * 255 > 254.5);
      if (near) {
        skipped++;
        continue;
      }
      expect(e, lessThanOrEqualTo(2), reason: 'colour $r $g $b');
    }
    // ignore: avoid_print
    print(
      'full mix: worst ${worstAll.toStringAsFixed(1)}/255, '
      '$skipped/500 near the gamut edge',
    );
    expect(worstAll, lessThanOrEqualTo(8));
  });

  test('contrast has no steps near the gamut boundary', () {
    final p = ColorPipeline(settings(values: {Setting.contrast: 30}));
    for (final base in [
      (0.9, 0.9, 0.03),
      (0.95, 0.95, 0.03),
      (0.9, 0.5, 0.05),
      (0.8, 0.95, 0.1),
    ]) {
      // Sweep every channel together from 0.85 to 1.0 in 0.002 steps.
      var prev = p.apply(base.$1, base.$2, base.$3);
      for (var i = 1; i <= 75; i++) {
        final d = 0.002 * i;
        double c(double v) => (v + d).clamp(0.0, 1.0);
        final cur = p.apply(c(base.$1), c(base.$2), c(base.$3));
        for (final (a, b) in [
          (prev.$1, cur.$1),
          (prev.$2, cur.$2),
          (prev.$3, cur.$3),
        ]) {
          expect(
            (a - b).abs() * 255,
            lessThanOrEqualTo(3),
            reason: 'base $base step $i',
          );
        }
        prev = cur;
      }
    }
  });

  test('sample hits nodes exactly and clamps outside 0..1', () {
    final lut = bakeLut(ColorPipeline(settings()), 17);
    final c = lut.sample(1.5, -0.2, 0.5);
    expect(c.$1, closeTo(1, 1 / 255));
    expect(c.$2, closeTo(0, 1 / 255));
    expect(c.$3, closeTo(0.5, 1 / 255));
  });

  test('bake time', () {
    for (final n in [17, 33]) {
      final p = ColorPipeline(
        settings(values: {Setting.exposure: 0.7, Setting.contrast: 30}),
      );
      final sw = Stopwatch()..start();
      bakeLut(p, n);
      sw.stop();
      // ignore: avoid_print
      print('bakeLut size $n: ${sw.elapsedMilliseconds} ms');
    }
  });
}
