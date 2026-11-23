import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/color_pipeline.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';

import 'develop_images.dart';

EditSettings edit(Map<Setting, double> v) =>
    EditSettings.resolve([SettingsPatch(values: v)]);

void main() {
  testWidgets('CpuDeveloper equals ColorPipeline exactly on global tools', (
    t,
  ) async {
    await t.runAsync(() async {
      final s = edit({
        Setting.exposure: 0.7,
        Setting.contrast: 30,
        Setting.hueRed: 40,
        // Effects and detail are ignored by the CPU fake.
        Setting.clarity: 50,
        Setting.grainAmount: 40,
      });
      final rgba = colourfulRgba();
      final src = await image(rgba);
      final dev = CpuDeveloper();
      final out = await dev.develop(src, s);
      expect(identical(out, src), false);
      expect(out.width, kSide);
      expect(out.height, kSide);
      final px = await readRgba(out);
      out.dispose();
      src.dispose();
      final p = ColorPipeline(s);
      var mismatches = 0;
      for (var i = 0; i < rgba.length; i += 4) {
        final c = p.apply(rgba[i] / 255, rgba[i + 1] / 255, rgba[i + 2] / 255);
        if (px[i] != (c.$1 * 255).round() ||
            px[i + 1] != (c.$2 * 255).round() ||
            px[i + 2] != (c.$3 * 255).round() ||
            px[i + 3] != 255) {
          mismatches++;
        }
      }
      expect(mismatches, 0);
      expect(dev.margin(s, 1, fullSize: const ui.Size(256, 256)), 0);
      expect(dev.margin(s, 4, fullSize: const ui.Size(100, 100)), 0);
    });
  });

  testWidgets('CpuDeveloper returns a new image for neutral settings', (
    t,
  ) async {
    await t.runAsync(() async {
      final rgba = colourfulRgba();
      final src = await image(rgba);
      final out = await CpuDeveloper().develop(src, edit({}));
      expect(identical(out, src), false);
      final px = await readRgba(out);
      out.dispose();
      src.dispose();
      expect(px, rgba);
    });
  });
}
