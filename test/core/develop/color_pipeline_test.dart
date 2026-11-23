import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/color_pipeline.dart';
import 'package:pio_photo_layout/core/develop/profile_table.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';

const double t = 0.5 / 255;

EditSettings settings({
  Map<Setting, double> values = const {},
  Map<CurveChannel, List<CurvePoint>> curves = const {},
  ProfileRef? profile,
  bool? grayscale,
}) => EditSettings.resolve([
  SettingsPatch(
    values: values,
    curves: curves,
    profile: profile,
    grayscale: grayscale,
  ),
]);

(double, double, double) run(
  EditSettings s,
  double r,
  double g,
  double b, {
  ProfileTable? profile,
}) => ColorPipeline(s, profile: profile).apply(r, g, b);

double luma(double r, double g, double b) =>
    0.2126 * srgbToLinear(r) +
    0.7152 * srgbToLinear(g) +
    0.0722 * srgbToLinear(b);

/// A table that adds 0.1 to red (clamped), used by the amount tests.
ProfileTable redBoostTable() {
  const n = 5;
  final data = Float32List(n * n * n * 3);
  for (var b = 0; b < n; b++) {
    for (var g = 0; g < n; g++) {
      for (var r = 0; r < n; r++) {
        final i = ((b * n + g) * n + r) * 3;
        data[i] = min(r / (n - 1) + 0.1, 1.0);
        data[i + 1] = g / (n - 1);
        data[i + 2] = b / (n - 1);
      }
    }
  }
  return ProfileTable(n, data);
}

void main() {
  test('neutral changes nothing', () {
    final rng = Random(1);
    final p = ColorPipeline(settings());
    expect(p.isIdentity, isTrue);
    for (var i = 0; i < 1000; i++) {
      final r = rng.nextDouble(), g = rng.nextDouble(), b = rng.nextDouble();
      final o = p.apply(r, g, b);
      expect((o.$1 - r).abs(), lessThanOrEqualTo(t));
      expect((o.$2 - g).abs(), lessThanOrEqualTo(t));
      expect((o.$3 - b).abs(), lessThanOrEqualTo(t));
    }
  });

  test('effects and detail settings alone leave it an identity', () {
    final p = ColorPipeline(
      settings(
        values: {
          Setting.clarity: 50,
          Setting.vignetteAmount: -30,
          Setting.sharpenAmount: 80,
        },
      ),
    );
    expect(p.isIdentity, isTrue);
  });

  test('exposure +1 doubles linear light', () {
    final o = run(settings(values: {Setting.exposure: 1}), 0.4, 0.4, 0.4);
    expect(
      srgbToLinear(o.$1),
      closeTo(2 * srgbToLinear(0.4), 0.01 * 2 * srgbToLinear(0.4)),
    );
  });

  test('exposure -1 halves it', () {
    final o = run(settings(values: {Setting.exposure: -1}), 0.4, 0.4, 0.4);
    expect(
      srgbToLinear(o.$1),
      closeTo(0.5 * srgbToLinear(0.4), 0.01 * 0.5 * srgbToLinear(0.4)),
    );
  });

  test('contrast keeps the pivot', () {
    final pivot = linearToSrgb(kContrastPivot);
    for (final c in [-100.0, 100.0]) {
      final o = run(
        settings(values: {Setting.contrast: c}),
        pivot,
        pivot,
        pivot,
      );
      expect((o.$1 - pivot).abs(), lessThanOrEqualTo(1 / 255));
    }
  });

  test('contrast +100 darkens 0.2 and lifts 0.8', () {
    final s = settings(values: {Setting.contrast: 100});
    expect(run(s, 0.2, 0.2, 0.2).$1, lessThan(0.2));
    expect(run(s, 0.8, 0.8, 0.8).$1, greaterThan(0.8));
  });

  test('highlights -100 pulls 0.9 down more than 0.5', () {
    final s = settings(values: {Setting.highlights: -100});
    final hi = 0.9 - run(s, 0.9, 0.9, 0.9).$1;
    final mid = 0.5 - run(s, 0.5, 0.5, 0.5).$1;
    expect(hi, greaterThan(mid));
    expect(hi, greaterThan(0.05));
    expect(mid, greaterThanOrEqualTo(0));
  });

  test('shadows +100 lifts 0.1 more than 0.5', () {
    final s = settings(values: {Setting.shadows: 100});
    final lo = run(s, 0.1, 0.1, 0.1).$1 - 0.1;
    final mid = run(s, 0.5, 0.5, 0.5).$1 - 0.5;
    expect(lo, greaterThan(mid));
    expect(lo, greaterThan(0.02));
    expect(mid, greaterThanOrEqualTo(0));
  });

  test('whites -10 lowers white; blacks +25 lifts black', () {
    expect(
      run(settings(values: {Setting.whites: -10}), 1, 1, 1).$1,
      lessThan(1),
    );
    final lifted = run(settings(values: {Setting.blacks: 25}), 0, 0, 0);
    expect(lifted.$1, greaterThan(0));
    expect(lifted.$2, greaterThan(0));
    expect(lifted.$3, greaterThan(0));
    expect(lifted.$1, closeTo(0.0125, 0.003));
    expect(
      run(settings(values: {Setting.blacks: 25}), 0.05, 0.05, 0.05).$1,
      greaterThan(0.05),
    );
    expect(run(settings(values: {Setting.blacks: -25}), 0, 0, 0).$1, 0);
  });

  test('point curve passes through its points', () {
    final s = settings(
      curves: {
        CurveChannel.master: const [
          CurvePoint(0, 0),
          CurvePoint(115, 126),
          CurvePoint(255, 255),
        ],
      },
    );
    final o = run(s, 115 / 255, 115 / 255, 115 / 255);
    expect((o.$1 - 126 / 255).abs(), lessThanOrEqualTo(t));
    expect((o.$2 - 126 / 255).abs(), lessThanOrEqualTo(t));
  });

  test('unsorted, out-of-range or single-point curves are tolerated', () {
    final one = settings(
      curves: {
        CurveChannel.master: const [CurvePoint(10, 200)],
      },
    );
    expect(ColorPipeline(one).isIdentity, isTrue);
    final messy = settings(
      curves: {
        CurveChannel.master: const [
          CurvePoint(255, 255),
          CurvePoint(115, 126),
          CurvePoint(0, 0),
        ],
      },
    );
    final o = run(messy, 115 / 255, 115 / 255, 115 / 255);
    expect((o.$1 - 126 / 255).abs(), lessThanOrEqualTo(t));
  });

  test('red curve moves only red', () {
    final s = settings(
      curves: {
        CurveChannel.red: const [
          CurvePoint(0, 0),
          CurvePoint(128, 160),
          CurvePoint(255, 255),
        ],
      },
    );
    final o = run(s, 0.5, 0.5, 0.5);
    expect(o.$1, greaterThan(0.5 + 0.05));
    expect((o.$2 - 0.5).abs(), lessThanOrEqualTo(t));
    expect((o.$3 - 0.5).abs(), lessThanOrEqualTo(t));
  });

  test('parametric shadows -41 darkens 0.15 and leaves 1.0', () {
    final s = settings(values: {Setting.curveShadows: -41});
    expect(run(s, 0.15, 0.15, 0.15).$1, lessThan(0.15 - 0.01));
    expect((run(s, 1, 1, 1).$1 - 1).abs(), lessThanOrEqualTo(t));
  });

  test('parametric curve matches the notes vectors', () {
    // lightcraft-notes.md 7.1 (transliteration, not run against the Rust).
    final a = settings(values: {Setting.curveShadows: 50});
    expect(run(a, 0.1, 0.1, 0.1).$1, closeTo(0.13853, 0.001));
    expect(run(a, 0.25, 0.25, 0.25).$1, closeTo(0.28784, 0.001));
    final b = settings(
      values: {Setting.curveDarks: 30, Setting.curveLights: -50},
    );
    expect(run(b, 0.25, 0.25, 0.25).$1, closeTo(0.27271, 0.001));
    // The notes give 0.47982 at 0.5, the raw formula before the forced
    // monotone step. That curve peaks near 0.485 and dips, so the algorithm's
    // `prev = max(prev, y)` holds the LUT at the peak: 0.4837.
    expect(run(b, 0.5, 0.5, 0.5).$1, closeTo(0.4837, 0.001));
    expect(run(b, 0.5, 0.5, 0.5).$1, greaterThanOrEqualTo(0.47982));
  });

  test('temperature +50 warms grey; tint +50 turns grey magenta', () {
    final w = run(settings(values: {Setting.temperature: 50}), 0.5, 0.5, 0.5);
    expect(w.$1, greaterThan(0.5));
    expect(w.$3, lessThan(0.5));
    final m = run(settings(values: {Setting.tint: 50}), 0.5, 0.5, 0.5);
    expect(m.$2, lessThan(m.$1));
    expect(m.$2, lessThan(m.$3));
  });

  test('temperature keeps neutral luminance', () {
    final w = run(settings(values: {Setting.temperature: 50}), 0.5, 0.5, 0.5);
    expect(luma(w.$1, w.$2, w.$3), closeTo(luma(0.5, 0.5, 0.5), 0.005));
  });

  test('saturation -100 and grayscale give grey', () {
    final a = run(settings(values: {Setting.saturation: -100}), 0.8, 0.3, 0.2);
    expect((a.$1 - a.$2).abs(), lessThanOrEqualTo(t));
    expect((a.$2 - a.$3).abs(), lessThanOrEqualTo(t));
    final b = run(settings(grayscale: true), 0.8, 0.3, 0.2);
    expect((b.$1 - b.$2).abs(), lessThanOrEqualTo(t));
    expect((b.$2 - b.$3).abs(), lessThanOrEqualTo(t));
  });

  test('vibrance +100 boosts a dull colour more than a vivid one', () {
    double chroma((double, double, double) c) =>
        max(c.$1, max(c.$2, c.$3)) - min(c.$1, min(c.$2, c.$3));
    final s = settings(values: {Setting.vibrance: 100});
    const dull = (0.55, 0.5, 0.45);
    const vivid = (0.9, 0.1, 0.1);
    final d = run(s, dull.$1, dull.$2, dull.$3);
    final v = run(s, vivid.$1, vivid.$2, vivid.$3);
    expect(chroma(d) - chroma(dull), greaterThan(0.01));
    expect(chroma(d) / chroma(dull), greaterThan(chroma(v) / chroma(vivid)));
  });

  test('mixer: red hue +100 turns red toward orange, blue untouched', () {
    final s = settings(values: {Setting.hueRed: 100});
    final r = run(s, 1, 0, 0);
    final h = hueOf(r.$1, r.$2, r.$3);
    expect(h, inExclusiveRange(5, 40));
    final b = run(s, 0, 0, 1);
    expect((b.$1 - 0).abs(), lessThanOrEqualTo(t));
    expect((b.$2 - 0).abs(), lessThanOrEqualTo(t));
    expect((b.$3 - 1).abs(), lessThanOrEqualTo(t));
  });

  test('mixer: green saturation -100 greys green only', () {
    final s = settings(values: {Setting.satGreen: -100});
    final g = run(s, 0, 1, 0);
    expect((g.$1 - g.$2).abs(), lessThanOrEqualTo(t));
    expect((g.$2 - g.$3).abs(), lessThanOrEqualTo(t));
    final r = run(s, 1, 0, 0);
    expect((r.$1 - 1).abs(), lessThanOrEqualTo(t));
    expect((r.$2 - 0).abs(), lessThanOrEqualTo(t));
    expect((r.$3 - 0).abs(), lessThanOrEqualTo(t));
  });

  test('mixer: blue luminance +100 brightens blue', () {
    final o = run(settings(values: {Setting.lumBlue: 100}), 0.2, 0.2, 0.8);
    expect(luma(o.$1, o.$2, o.$3), greaterThan(luma(0.2, 0.2, 0.8)));
  });

  test('mixer bands match the notes vectors', () {
    // lightcraft-notes.md 6.4 (my transliteration, not run against the Rust).
    final hues = debugBandHues();
    const expected = [
      0.5102,
      0.9211,
      1.9158,
      2.4870,
      -2.8838,
      -1.6785,
      -1.1559,
      -0.2838,
    ];
    for (var i = 0; i < 8; i++) {
      expect(hues[i], closeTo(expected[i], 0.005), reason: 'band $i');
    }
    final w1 = debugBandWeights(1.2);
    expect(w1[1], closeTo(0.8182, 0.01));
    expect(w1[2], closeTo(0.1818, 0.01));
    final w2 = debugBandWeights(-2.0);
    expect(w2[4], closeTo(0.1655, 0.01));
    expect(w2[5], closeTo(0.8345, 0.01));
    expect(w2.reduce((a, b) => a + b), closeTo(1, 1e-9));
  });

  test(
    'grading: shadows hue 240 sat 100 tints 0.1 grey blue, leaves 0.95 grey nearly neutral',
    () {
      final s = settings(
        values: {Setting.gradeShadowHue: 240, Setting.gradeShadowSat: 100},
      );
      final dark = run(s, 0.1, 0.1, 0.1);
      expect(dark.$3 - dark.$1, greaterThan(0.02));
      final light = run(s, 0.95, 0.95, 0.95);
      expect((light.$3 - light.$1).abs(), lessThanOrEqualTo(t));
      expect((light.$2 - light.$1).abs(), lessThanOrEqualTo(t));
    },
  );

  test('profile: identity table at any amount changes nothing', () {
    final rng = Random(1);
    for (final amount in [0.0, 1.0, 2.0]) {
      final s = settings(profile: ProfileRef('x', 'X', amount));
      final p = ColorPipeline(s, profile: ProfileTable.identity(9));
      for (var i = 0; i < 200; i++) {
        final r = rng.nextDouble(), g = rng.nextDouble(), b = rng.nextDouble();
        final o = p.apply(r, g, b);
        expect((o.$1 - r).abs(), lessThanOrEqualTo(t));
        expect((o.$2 - g).abs(), lessThanOrEqualTo(t));
        expect((o.$3 - b).abs(), lessThanOrEqualTo(t));
      }
    }
  });

  test(
    'profile: amount 0 changes nothing; amount 1 equals the table; amount 2 doubles the change',
    () {
      final table = redBoostTable();
      (double, double, double) at(double amount) => run(
        settings(profile: ProfileRef('x', 'X', amount)),
        0.3,
        0.4,
        0.5,
        profile: table,
      );
      final a0 = at(0), a1 = at(1), a2 = at(2);
      expect((a0.$1 - 0.3).abs(), lessThanOrEqualTo(t));
      expect((a1.$1 - 0.4).abs(), lessThanOrEqualTo(t));
      expect((a1.$2 - 0.4).abs(), lessThanOrEqualTo(t));
      expect((a2.$1 - 0.5).abs(), lessThanOrEqualTo(t));
      final s = table.sample(0.3, 0.4, 0.5);
      expect(s.$1, closeTo(0.4, 1e-6));
    },
  );

  test('profile table identity samples back its input', () {
    final id = ProfileTable.identity(5);
    final s = id.sample(0.13, 0.57, 0.91);
    expect(s.$1, closeTo(0.13, 1e-6));
    expect(s.$2, closeTo(0.57, 1e-6));
    expect(s.$3, closeTo(0.91, 1e-6));
  });

  test('NaN input gives finite output', () {
    final p = ColorPipeline(settings(values: {Setting.exposure: 1}));
    final o = p.apply(double.nan, 0.5, 0.5);
    expect(o.$1.isFinite && o.$2.isFinite && o.$3.isFinite, isTrue);
  });

  test('helpers round trip', () {
    for (final v in [0.0, 0.01, 0.2, 0.5, 1.0]) {
      expect(linearToSrgb(srgbToLinear(v)), closeTo(v, 1e-9));
    }
    expect(hueOf(1, 0, 0), closeTo(0, 1e-9));
    expect(hueOf(0, 1, 0), closeTo(120, 1e-9));
    expect(hueOf(0, 0, 1), closeTo(240, 1e-9));
  });

  test('apply is fast enough for a 36,000-sample bake', () {
    final p = ColorPipeline(
      settings(
        values: {
          Setting.exposure: 0.5,
          Setting.contrast: 20,
          Setting.highlights: -30,
          Setting.shadows: 30,
          Setting.vibrance: 20,
          Setting.hueRed: 20,
          Setting.gradeShadowSat: 30,
          Setting.temperature: 10,
        },
      ),
    );
    final sw = Stopwatch()..start();
    var acc = 0.0;
    for (var i = 0; i < 36000; i++) {
      acc += p.apply(i / 36000, 0.5, 1 - i / 36000).$1;
    }
    sw.stop();
    expect(acc, isNonZero);
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });
}
