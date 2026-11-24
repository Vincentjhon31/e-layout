import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/masks.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/develop/shader_developer.dart';

import 'develop_images.dart';

/// A hard-edged circle of radius 64 px at the centre of a 256 px photo.
Mask radial(
  Map<Setting, double> adjust, {
  bool visible = true,
  String id = 'r',
}) => Mask(
  id: id,
  components: [
    MaskComponent(RadialShape(cx: .5, cy: .5, rx: .25, ry: .25, feather: 0)),
  ],
  adjust: adjust,
  visible: visible,
);

/// Covers the whole photo.
Mask everywhere(Map<Setting, double> adjust, {String id = 'all'}) => Mask(
  id: id,
  components: [
    MaskComponent(RadialShape(cx: .5, cy: .5, rx: 1, ry: 1, feather: 0)),
  ],
  adjust: adjust,
);

EditSettings withMasks(
  List<Mask> masks, [
  Map<Setting, double> values = const {},
]) => EditSettings.resolve([SettingsPatch(values: values, masks: masks)]);

/// Develops [rgba] (256 x 256) and returns the output bytes.
Future<Uint8List> run(
  PhotoDeveloper dev,
  Uint8List rgba,
  EditSettings s, {
  int w = kSide,
  ui.Offset origin = ui.Offset.zero,
  ui.Size? fullSize,
}) async {
  final src = await image(rgba, w, rgba.length ~/ 4 ~/ w);
  final out = await dev.develop(src, s, origin: origin, fullSize: fullSize);
  expect(identical(out, src), false);
  final px = await readRgba(out);
  out.dispose();
  src.dispose();
  return px;
}

double distFromCentre(int x, int y) =>
    math.sqrt(math.pow(x + 0.5 - 128, 2) + math.pow(y + 0.5 - 128, 2));

/// Largest per-channel difference between two RGBA buffers.
int worstDiff(Uint8List a, Uint8List b) {
  var worst = 0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 == 3) continue;
    worst = math.max(worst, (a[i] - b[i]).abs());
  }
  return worst;
}

/// Mean absolute per-channel difference between two RGBA buffers.
double meanDiff(Uint8List a, Uint8List b) {
  var sum = 0, n = 0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 == 3) continue;
    sum += (a[i] - b[i]).abs();
    n++;
  }
  return sum / n;
}

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

  testWidgets('a radial mask with exposure +1 brightens only inside', (
    t,
  ) async {
    await withDev(t, () async {
      final src = colourfulRgba();
      final out = await run(
        dev,
        src,
        withMasks([
          radial({Setting.exposure: 1}),
        ]),
      );
      var outsideWorst = 0;
      var gain = 0.0, n = 0;
      for (var y = 0; y < kSide; y++) {
        for (var x = 0; x < kSide; x++) {
          final d = distFromCentre(x, y);
          final i = (y * kSide + x) * 4;
          if (d > 66) {
            for (var k = 0; k < 3; k++) {
              outsideWorst = math.max(
                outsideWorst,
                (out[i + k] - src[i + k]).abs(),
              );
            }
          } else if (d < 60) {
            final lo = lumaAt(out, kSide, x, y), li = lumaAt(src, kSide, x, y);
            expect(lo, greaterThanOrEqualTo(li - 1), reason: 'at ($x, $y)');
            gain += lo - li;
            n++;
          }
        }
      }
      expect(outsideWorst, lessThanOrEqualTo(1));
      expect(gain / n, greaterThan(20));
    });
  });

  testWidgets('a mask with no adjust changes nothing', (t) async {
    await withDev(t, () async {
      final src = richRgba(1);
      const global = <Setting, double>{
        Setting.exposure: 0.4,
        Setting.contrast: 20,
      };
      final plain = await run(dev, src, withMasks([], global));
      final empty = await run(dev, src, withMasks([radial({})], global));
      final zero = await run(
        dev,
        src,
        withMasks([
          radial({Setting.exposure: 0, Setting.clarity: 0}),
        ], global),
      );
      expect(worstDiff(empty, plain), lessThanOrEqualTo(1));
      expect(worstDiff(zero, plain), lessThanOrEqualTo(1));
      const full = ui.Size(256, 256);
      expect(
        dev.margin(withMasks([radial({})]), 1, fullSize: full),
        dev.margin(withMasks([]), 1, fullSize: full),
      );
    });
  });

  testWidgets('a hidden mask does nothing', (t) async {
    await withDev(t, () async {
      final src = richRgba(2);
      const global = <Setting, double>{Setting.saturation: 20};
      final plain = await run(dev, src, withMasks([], global));
      final hidden = await run(
        dev,
        src,
        withMasks([
          radial({Setting.exposure: 1, Setting.clarity: 60}, visible: false),
        ], global),
      );
      expect(worstDiff(hidden, plain), lessThanOrEqualTo(1));
      const full = ui.Size(256, 256);
      expect(
        dev.margin(
          withMasks([
            radial({Setting.clarity: 60}, visible: false),
          ]),
          1,
          fullSize: full,
        ),
        0,
      );
    });
  });

  testWidgets('two masks apply in order', (t) async {
    await withDev(t, () async {
      final src = colourfulRgba();
      final a = everywhere({Setting.exposure: 2}, id: 'a');
      final b = radial({Setting.exposure: -2}, id: 'b');
      final ab = await run(dev, src, withMasks([a, b]));
      final ba = await run(dev, src, withMasks([b, a]));
      final onlyA = await run(dev, src, withMasks([a]));
      final thenB = await run(dev, onlyA, withMasks([b]));
      // [a, b] is a, then b on a's result.
      expect(worstDiff(ab, thenB), lessThanOrEqualTo(1));
      // The order matters: a's clipped highlights stay dark under b.
      expect(meanDiff(ab, ba), greaterThan(3));
    });
  });

  testWidgets('shader and CpuDeveloper agree on tone and colour deltas', (
    t,
  ) async {
    await withDev(t, () async {
      final src = colourfulRgba();
      final s = withMasks(
        [
          Mask(
            id: 'r',
            components: [
              MaskComponent(
                RadialShape(cx: .4, cy: .6, rx: .35, ry: .25, feather: 60),
              ),
            ],
            adjust: {
              Setting.exposure: 0.8,
              Setting.contrast: 30,
              Setting.shadows: 25,
              Setting.temperature: 25,
              Setting.saturation: -40,
            },
          ),
          everywhere({Setting.tint: 15, Setting.vibrance: 30}),
        ],
        {Setting.exposure: 0.3, Setting.highlights: -20},
      );
      final gpu = await run(dev, src, s);
      final cpu = await run(CpuDeveloper(), src, s);
      final mean = meanDiff(gpu, cpu);
      // ignore: avoid_print
      print(
        'mask parity: mean ${mean.toStringAsFixed(3)}, '
        'max ${worstDiff(gpu, cpu)} levels',
      );
      expect(mean, lessThanOrEqualTo(2));
      // And the masks did something.
      final plain = await run(
        CpuDeveloper(),
        src,
        withMasks([], {Setting.exposure: 0.3, Setting.highlights: -20}),
      );
      expect(meanDiff(cpu, plain), greaterThan(3));
    });
  });

  testWidgets('coverage is drawn once while only the adjust changes', (
    t,
  ) async {
    await withDev(t, () async {
      final src = await image(richRgba(3));
      Future<void> go(double ev) async {
        final out = await dev.develop(
          src,
          withMasks([
            radial({Setting.exposure: ev}),
          ]),
        );
        out.dispose();
      }

      await go(0.5);
      await go(0.6);
      await go(0.7);
      expect(dev.debugCoveragesDrawn, 1);
      dev.clearCache();
      await go(0.7);
      expect(dev.debugCoveragesDrawn, 2);
      src.dispose();
    });
  });

  testWidgets('margin adds the local clarity and texture reach', (t) async {
    await withDev(t, () async {
      const full = ui.Size(1000, 500);
      final global = withMasks([], {Setting.clarity: 20});
      final local = withMasks([
        radial({Setting.clarity: 20}),
      ]);
      final both = withMasks(
        [
          radial({Setting.clarity: 20}),
        ],
        {Setting.clarity: 20},
      );
      final g = dev.margin(global, 1, fullSize: full);
      expect(g, greaterThan(0));
      expect(dev.margin(local, 1, fullSize: full), g);
      // The local pass reads the main pass's output: the reaches add.
      expect(dev.margin(both, 1, fullSize: full), 2 * g);
      final tex = withMasks([
        radial({Setting.texture: 50}),
      ]);
      expect(dev.margin(tex, 1, fullSize: full), greaterThan(0));
      // Tone only: no reach.
      expect(
        dev.margin(
          withMasks([
            radial({Setting.exposure: 1}),
          ]),
          1,
          fullSize: full,
        ),
        0,
      );
    });
  });

  testWidgets('two tiles with a clarity mask match one whole render', (
    t,
  ) async {
    await withDev(t, () async {
      final s = withMasks(
        [
          radial({Setting.clarity: 80, Setting.exposure: 0.5}),
          everywhere({Setting.texture: 60}),
        ],
        {Setting.clarity: 40},
      );
      const full = ui.Size(256, 256);
      final m = dev.margin(s, 1, fullSize: full);
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

      // Largest difference from the whole render when the photo is cut at
      // x = 128 with [mm] px of overlap.
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
      // Control: a 1 px overlap is not enough.
      final thin = await seamDiff(1);
      // ignore: avoid_print
      print('mask tiles: margin $m, max diff $worst levels; 1 px: $thin');
      expect(worst, lessThanOrEqualTo(2));
      expect(thin, greaterThan(worst + 3));
    });
  });
}
