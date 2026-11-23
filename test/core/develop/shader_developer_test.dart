import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/color_pipeline.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/develop/profile_table.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/develop/shader_developer.dart';

import 'develop_images.dart';

EditSettings edit(Map<Setting, double> v) =>
    EditSettings.resolve([SettingsPatch(values: v)]);

/// Develops [src] and returns the output bytes; [src] stays the caller's.
Future<Uint8List> develop(
  PhotoDeveloper dev,
  ui.Image src,
  EditSettings s, {
  ProfileTable? profile,
  double scale = 1,
  ui.Offset origin = ui.Offset.zero,
  ui.Size? fullSize,
}) async {
  final out = await dev.develop(
    src,
    s,
    profile: profile,
    scale: scale,
    origin: origin,
    fullSize: fullSize,
  );
  expect(identical(out, src), false);
  final px = await readRgba(out);
  out.dispose();
  return px;
}

/// Develops [rgba] (256 x 256) and returns the output bytes.
Future<Uint8List> run(
  ShaderDeveloper dev,
  Uint8List rgba,
  EditSettings s, {
  int lutSize = 33,
}) async {
  final src = await image(rgba);
  final out = await dev.develop(src, s, lutSize: lutSize);
  expect(identical(out, src), false);
  final px = await readRgba(out);
  out.dispose();
  src.dispose();
  return px;
}

void main() {
  late ShaderDeveloper dev;

  // Each test loads the program (cached by the engine) and drops its caches.
  Future<void> withDev(WidgetTester t, Future<void> Function() body) =>
      t.runAsync(() async {
        dev = await ShaderDeveloper.load();
        try {
          await body();
        } finally {
          dev.dispose();
        }
      });

  testWidgets('neutral settings return the input', (t) async {
    await withDev(t, () async {
      final src = colourfulRgba();
      final out = await run(dev, src, edit({}));
      var worst = 0;
      for (var i = 0; i < src.length; i++) {
        worst = math.max(worst, (out[i] - src[i]).abs());
      }
      expect(worst, lessThanOrEqualTo(1));
    });
  });

  testWidgets('global tools match ColorPipeline', (t) async {
    await withDev(t, () async {
      final s = edit({
        Setting.exposure: 0.7,
        Setting.contrast: 30,
        Setting.hueRed: 40,
      });
      final src = colourfulRgba();
      final out = await run(dev, src, s);
      final p = ColorPipeline(s);
      var sum = 0.0;
      var worst = 0.0;
      for (var i = 0; i < src.length; i += 4) {
        final c = p.apply(src[i] / 255, src[i + 1] / 255, src[i + 2] / 255);
        for (final (k, v) in [(0, c.$1), (1, c.$2), (2, c.$3)]) {
          final d = (out[i + k] - v * 255).abs();
          sum += d;
          worst = math.max(worst, d);
        }
      }
      final mean = sum / (src.length / 4 * 3);
      // ignore: avoid_print
      print('global: mean ${mean.toStringAsFixed(3)}, max $worst levels');
      expect(mean, lessThanOrEqualTo(1.5));
    });
  });

  testWidgets('clarity +100 raises local contrast at a soft edge', (t) async {
    await withDev(t, () async {
      final src = softEdgeRgba(70, 180, 6);
      final out = await run(dev, src, edit({Setting.clarity: 100}));
      double sd(Uint8List px) => math.sqrt(
        stats(112, 0, 144, kSide, (x, y) => lumaAt(px, kSide, x, y)).$2,
      );
      final before = sd(src), after = sd(out);
      // ignore: avoid_print
      print('clarity: band std-dev $before -> $after');
      expect(after, greaterThan(before * 1.05));
    });
  });

  testWidgets('sharpening raises the edge gradient', (t) async {
    await withDev(t, () async {
      final src = softEdgeRgba(70, 180, 4);
      final out = await run(dev, src, edit({Setting.sharpenAmount: 100}));
      double grad(Uint8List px) {
        var g = 0.0;
        for (var x = 100; x < 156; x++) {
          g = math.max(
            g,
            lumaAt(px, kSide, x + 1, 128) - lumaAt(px, kSide, x, 128),
          );
        }
        return g;
      }

      final before = grad(src), after = grad(out);
      // ignore: avoid_print
      print('sharpen: max gradient $before -> $after');
      expect(after, greaterThan(before * 1.1));
    });
  });

  testWidgets('noise reduction lowers variance on a noise patch', (t) async {
    await withDev(t, () async {
      final src = noiseRgba(20, 7);
      final out = await run(
        dev,
        src,
        edit({Setting.noiseLuminance: 80, Setting.noiseColour: 80}),
      );
      double lumVar(Uint8List px) =>
          stats(32, 32, 224, 224, (x, y) => lumaAt(px, kSide, x, y)).$2;
      double chromaVar(Uint8List px) => stats(32, 32, 224, 224, (x, y) {
        final i = (y * kSide + x) * 4;
        return (px[i] - px[i + 2]).toDouble();
      }).$2;
      final lb = lumVar(src), la = lumVar(out);
      final cb = chromaVar(src), ca = chromaVar(out);
      // ignore: avoid_print
      print('nr: luma var $lb -> $la, chroma var $cb -> $ca');
      expect(la, lessThan(lb * 0.7));
      expect(ca, lessThan(cb * 0.7));
    });
  });

  testWidgets('vignette -100 darkens corners, not the centre', (t) async {
    await withDev(t, () async {
      final src = flatRgba(128);
      final out = await run(dev, src, edit({Setting.vignetteAmount: -100}));
      for (final (x, y) in [(0, 0), (255, 0), (0, 255), (255, 255)]) {
        expect(lumaAt(out, kSide, x, y), lessThan(10), reason: 'corner $x,$y');
      }
      expect((lumaAt(out, kSide, 128, 128) - 128).abs(), lessThanOrEqualTo(1));
      expect(lumaAt(out, kSide, 255, 128), lessThan(120));
    });
  });

  testWidgets('grain changes pixels but keeps the mean within 2/255', (
    t,
  ) async {
    await withDev(t, () async {
      final src = flatRgba(128);
      final out = await run(dev, src, edit({Setting.grainAmount: 50}));
      var changed = 0;
      var sum = 0.0;
      for (var i = 0; i < out.length; i += 4) {
        if ((out[i] - 128).abs() > 2) changed++;
        sum += out[i] + out[i + 1] + out[i + 2];
      }
      final n = out.length ~/ 4;
      final mean = sum / (3 * n);
      // ignore: avoid_print
      print('grain: changed ${changed / n}, mean $mean');
      expect(changed / n, greaterThan(0.25));
      expect((mean - 128).abs(), lessThanOrEqualTo(2));
      // Monochrome: the same offset on every channel.
      expect(out[400], out[401]);
      expect(out[400], out[402]);
    });
  });

  testWidgets('grain is the same for the same settings and position', (
    t,
  ) async {
    await withDev(t, () async {
      final src = flatRgba(128);
      final s = edit({Setting.grainAmount: 50});
      final a = await run(dev, src, s);
      final b = await run(dev, src, s);
      expect(a, b);
    });
  });

  testWidgets('two tiles with margin() overlap equal one whole render', (
    t,
  ) async {
    await withDev(t, () async {
      final s = edit({
        Setting.clarity: 60,
        Setting.noiseLuminance: 40,
        Setting.grainAmount: 30,
        Setting.vignetteAmount: -40,
      });
      const full = ui.Size(256, 256);
      final m = dev.margin(s, 1, fullSize: full);
      expect(m, greaterThan(0));
      final src = richRgba(3);
      final whole = await run(dev, src, s);

      Future<Uint8List> tile(int x0, int w) async {
        final img = await image(cropRgba(src, kSide, x0, 0, w, kSide), w);
        final out = await dev.develop(
          img,
          s,
          origin: ui.Offset(x0.toDouble(), 0),
          fullSize: full,
        );
        final px = await readRgba(out);
        out.dispose();
        img.dispose();
        return px;
      }

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
            final t = x < 128 ? a : b;
            for (var k = 0; k < 3; k++) {
              worst = math.max(worst, (t[i + k] - whole[w + k]).abs());
            }
          }
        }
        return worst;
      }

      final worst = await seamDiff(m);
      // Control: a 1 px overlap is not enough, so the margin is what makes
      // the tiles agree.
      final thin = await seamDiff(1);
      // ignore: avoid_print
      print('tiles: margin $m, max diff $worst levels; 1 px overlap: $thin');
      expect(worst, lessThanOrEqualTo(2));
      expect(thin, greaterThan(worst + 3));
    });
  });

  testWidgets('margin covers 3 sigma of the blurs in use, 0 without them', (
    t,
  ) async {
    await withDev(t, () async {
      const full = ui.Size(256, 256);
      expect(dev.margin(edit({}), 1, fullSize: full), 0);
      expect(
        dev.margin(
          edit({
            Setting.exposure: 1,
            Setting.vignetteAmount: -50,
            Setting.grainAmount: 40,
          }),
          1,
          fullSize: full,
        ),
        0,
      );
      // Clarity: sigma = 1.2 % of the long edge.
      expect(
        dev.margin(edit({Setting.clarity: 20}), 1, fullSize: full),
        greaterThanOrEqualTo((3 * 0.012 * 256).ceil()),
      );
      // Sharpening radius 3 at scale 2: sigma 6 render px.
      expect(
        dev.margin(
          edit({Setting.sharpenAmount: 40, Setting.sharpenRadius: 3}),
          2,
          fullSize: const ui.Size(512, 512),
        ),
        greaterThanOrEqualTo(18),
      );
    });
  });

  testWidgets('dehaze +100 deepens a hazy image', (t) async {
    await withDev(t, () async {
      final src = fillRgba(kSide, kSide, (x, y) {
        final v = 160 + (x * 60) ~/ 255;
        return (v, v + 5, v + 10);
      });
      final img = await image(src);
      final st = await measureStats(img);
      img.dispose();
      expect(st.airlight, inInclusiveRange(0.05, 1.0));
      final out = await run(dev, src, edit({Setting.dehaze: 100}));
      final before = stats(
        0,
        0,
        kSide,
        kSide,
        (x, y) => lumaAt(src, kSide, x, y),
      );
      final after = stats(
        0,
        0,
        kSide,
        kSide,
        (x, y) => lumaAt(out, kSide, x, y),
      );
      // ignore: avoid_print
      print(
        'dehaze: mean ${before.$1} -> ${after.$1}, var ${before.$2} -> ${after.$2}',
      );
      expect(after.$1, lessThan(before.$1 - 10));
      expect(after.$2, greaterThan(before.$2 * 1.2));
    });
  });

  testWidgets('neutral settings with a profile table apply the profile', (
    t,
  ) async {
    await withDev(t, () async {
      // An inverting table, nodes in the order ProfileTable.identity uses.
      const n = 5;
      final rgb = Float32List(n * n * n * 3);
      var o = 0;
      for (var b = 0; b < n; b++) {
        for (var g = 0; g < n; g++) {
          for (var r = 0; r < n; r++) {
            rgb[o++] = 1 - r / (n - 1);
            rgb[o++] = 1 - g / (n - 1);
            rgb[o++] = 1 - b / (n - 1);
          }
        }
      }
      final table = ProfileTable(n, rgb);
      final s = edit({});
      expect(s.isNeutral, true);
      final rgba = colourfulRgba();
      final src = await image(rgba);
      final out = await develop(dev, src, s, profile: table);
      src.dispose();
      final p = ColorPipeline(s, profile: table);
      expect(p.isIdentity, false);
      var sum = 0.0;
      for (var i = 0; i < rgba.length; i += 4) {
        final c = p.apply(rgba[i] / 255, rgba[i + 1] / 255, rgba[i + 2] / 255);
        sum +=
            (out[i] - c.$1 * 255).abs() +
            (out[i + 1] - c.$2 * 255).abs() +
            (out[i + 2] - c.$3 * 255).abs();
      }
      final mean = sum / (rgba.length / 4 * 3);
      // ignore: avoid_print
      print('profile on neutral settings: mean ${mean.toStringAsFixed(3)}');
      expect(mean, lessThanOrEqualTo(1.5));
      // Black in, white out: the table really acted.
      expect(out[1], greaterThan(240));
    });
  });

  testWidgets('tiles cut along x and y at scale 0.5 match a whole render', (
    t,
  ) async {
    await withDev(t, () async {
      final s = edit({
        Setting.clarity: 40,
        Setting.vignetteAmount: -40,
        Setting.grainAmount: 40,
      });
      const scale = 0.5;
      const full = ui.Size(256, 256); // a 512 px photo rendered at half size
      final m = dev.margin(s, scale, fullSize: full);
      expect(m, greaterThan(0));
      final rgba = richRgba(5);
      final src = await image(rgba);
      final whole = await develop(dev, src, s, scale: scale, fullSize: full);
      src.dispose();

      var worst = 0;
      for (final (tx, ty) in [(0, 0), (1, 0), (0, 1), (1, 1)]) {
        // The quadrant plus the margin toward the cuts.
        final x0 = tx == 0 ? 0 : 128 - m, y0 = ty == 0 ? 0 : 128 - m;
        final w = 128 + m, h = 128 + m;
        final img = await image(cropRgba(rgba, kSide, x0, y0, w, h), w, h);
        final px = await develop(
          dev,
          img,
          s,
          scale: scale,
          origin: ui.Offset(x0.toDouble(), y0.toDouble()),
          fullSize: full,
        );
        img.dispose();
        for (var y = ty * 128; y < ty * 128 + 128; y++) {
          for (var x = tx * 128; x < tx * 128 + 128; x++) {
            final i = ((y - y0) * w + x - x0) * 4;
            final j = (y * kSide + x) * 4;
            for (var k = 0; k < 3; k++) {
              worst = math.max(worst, (px[i + k] - whole[j + k]).abs());
            }
          }
        }
      }
      // ignore: avoid_print
      print('2-D tiles at scale 0.5: margin $m, max diff $worst levels');
      expect(worst, lessThanOrEqualTo(2));
    });
  });

  testWidgets('two images of the same size through one developer', (t) async {
    await withDev(t, () async {
      final s = edit({
        Setting.exposure: 0.5,
        Setting.clarity: 30,
        Setting.sharpenAmount: 60,
        Setting.noiseLuminance: 30,
      });
      final a = await image(richRgba(11));
      final b = await image(softEdgeRgba(40, 200, 8));
      final outA = await develop(dev, a, s);
      final outB = await develop(dev, b, s);
      final freshA = await ShaderDeveloper.load();
      final freshB = await ShaderDeveloper.load();
      try {
        expect(outB, await develop(freshB, b, s));
        expect(outA, await develop(freshA, a, s));
      } finally {
        freshA.dispose();
        freshB.dispose();
        a.dispose();
        b.dispose();
      }
      expect(outA, isNot(outB));
    });
  });

  testWidgets('changing exposure after a render re-bakes the colour table', (
    t,
  ) async {
    await withDev(t, () async {
      final src = await image(colourfulRgba());
      final s1 = edit({Setting.exposure: 0.5, Setting.clarity: 20});
      final s2 = edit({Setting.exposure: 1.0, Setting.clarity: 20});
      final first = await develop(dev, src, s1);
      final second = await develop(dev, src, s2);
      final fresh = await ShaderDeveloper.load();
      try {
        expect(second, await develop(fresh, src, s2));
      } finally {
        fresh.dispose();
        src.dispose();
      }
      var brighter = 0;
      for (var i = 0; i < first.length; i += 4) {
        if (second[i + 1] > first[i + 1]) brighter++;
      }
      expect(brighter, greaterThan(first.length ~/ 4 ~/ 2));
    });
  });

  testWidgets('changing only Radius re-blurs only the sharpening copy', (
    t,
  ) async {
    await withDev(t, () async {
      final src = await image(richRgba(2));
      Map<Setting, double> v(double radius) => {
        Setting.clarity: 30,
        Setting.texture: 30,
        Setting.noiseLuminance: 30,
        Setting.sharpenAmount: 50,
        Setting.sharpenRadius: radius,
      };
      await develop(dev, src, edit(v(1)));
      expect(dev.debugBlursMade, 4);
      await develop(dev, src, edit(v(2)));
      expect(dev.debugBlursMade, 5);
      await develop(dev, src, edit({...v(2), Setting.clarity: 60}));
      expect(dev.debugBlursMade, 5);
      dev.clearCache();
      await develop(dev, src, edit(v(2)));
      expect(dev.debugBlursMade, 9);
      src.dispose();
    });
  });
}
