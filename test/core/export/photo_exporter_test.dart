import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pio_photo_layout/core/codec/jpeg_encoder.dart';
import 'package:pio_photo_layout/core/codec/png_encoder.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/develop/profile_table.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/develop/shader_developer.dart';
import 'package:pio_photo_layout/core/export/photo_exporter.dart';
import 'package:pio_photo_layout/core/model/layout_codec.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/model/layout_ops.dart';
import 'package:pio_photo_layout/core/render/layout_prep.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart' show isMemoryFailure;

import '../render/render_helpers.dart';

Uint8List photoPng(int w, int h, {bool transparent = false}) {
  final b = Uint8List(w * h * 4);
  if (!transparent) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        b[i] = x * 255 ~/ w;
        b[i + 1] = y * 255 ~/ h;
        b[i + 2] = 120;
        b[i + 3] = 255;
      }
    }
  }
  return encodePng(b, w, h);
}

double meanDiff(Uint8List a, Uint8List b) {
  final ia = img.decodeJpg(a)!, ib = img.decodeJpg(b)!;
  expect([ia.width, ia.height], [ib.width, ib.height]);
  final pa = ia.convert(numChannels: 3).getBytes(), pb = ib.convert(numChannels: 3).getBytes();
  var s = 0;
  for (var i = 0; i < pa.length; i++) {
    s += (pa[i] - pb[i]).abs();
  }
  return s / pa.length;
}

Future<LayoutDoc> footerDoc() async => readLayout(
    jsonDecode(File('assets/layouts/pio-footer.layout.json').readAsStringSync()),
    keepIdentity: true)
  ..elements.length;

EditSettings edits(Map<Setting, double> v) =>
    EditSettings.resolve([SettingsPatch(values: v)]);

/// A smooth generated photo (gradients and soft waves, no fine detail that
/// would alias when scaled down), straight RGBA.
Uint8List smoothRgba(int w, int h) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      b[i] = 30 + x * 190 ~/ w;
      b[i + 1] = 40 + y * 170 ~/ h;
      b[i + 2] = (128 + 90 * math.sin(x * 12 / w) * math.cos(y * 9 / h)).round();
      b[i + 3] = 255;
    }
  }
  return b;
}

/// Straight RGBA of a saved PNG.
Uint8List pngRgba(Uint8List png) =>
    img.decodePng(png)!.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);

/// Mean absolute difference per colour channel, in levels.
double rgbMeanDiff(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var s = 0;
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      s += (a[i + c] - b[i + c]).abs();
    }
    n += 3;
  }
  return s / n;
}

/// Rec. 709 luma of the pixel at (x, y).
double luma(Uint8List rgba, int w, int x, int y) {
  final i = (y * w + x) * 4;
  return 0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2];
}

/// Fails the test if the exporter calls it.
class UnusedDeveloper implements PhotoDeveloper {
  @override
  Future<ui.Image> develop(ui.Image src, EditSettings s,
      {ProfileTable? profile,
      double scale = 1,
      ui.Offset origin = ui.Offset.zero,
      ui.Size? fullSize,
      int lutSize = 33,
      DevelopStats? stats}) {
    throw TestFailure('the developer was used for neutral edits');
  }

  @override
  int margin(EditSettings s, double scale, {required ui.Size fullSize}) =>
      throw TestFailure('the developer was asked for a margin');

  @override
  void clearCache() {}

  @override
  void dispose() {}
}

/// Runs out of memory on the first tile.
class OutOfMemoryDeveloper implements PhotoDeveloper {
  int cleared = 0;

  @override
  Future<ui.Image> develop(ui.Image src, EditSettings s,
          {ProfileTable? profile,
          double scale = 1,
          ui.Offset origin = ui.Offset.zero,
          ui.Size? fullSize,
          int lutSize = 33,
          DevelopStats? stats}) async =>
      throw const OutOfMemoryError();

  @override
  int margin(EditSettings s, double scale, {required ui.Size fullSize}) => 8;

  @override
  void clearCache() => cleared++;

  @override
  void dispose() {}
}

/// Colour through [CpuDeveloper]; records what each tile was given.
class RecordingDeveloper extends CpuDeveloper {
  final calls = <(ui.Offset, ui.Size?, double, DevelopStats?, int, int)>[];
  int cleared = 0;

  @override
  Future<ui.Image> develop(ui.Image src, EditSettings s,
      {ProfileTable? profile,
      double scale = 1,
      ui.Offset origin = ui.Offset.zero,
      ui.Size? fullSize,
      int lutSize = 33,
      DevelopStats? stats}) {
    calls.add((origin, fullSize, scale, stats, src.width, src.height));
    return super.develop(src, s, profile: profile, scale: scale, origin: origin,
        fullSize: fullSize, lutSize: lutSize, stats: stats);
  }

  @override
  int margin(EditSettings s, double scale, {required ui.Size fullSize}) => 10;

  @override
  void clearCache() => cleared++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('names', () {
    final used = <String>{};
    expect(uniqueName('a', 'jpg', used), 'a.jpg');
    expect(uniqueName('a', 'jpg', used), 'a (2).jpg');
    expect(uniqueName('A', 'JPG', used), 'A (3).JPG');
    expect(outputStem('IMG 1.JPG', '_PIO?'), 'IMG 1_PIO');
    expect(outputStem('noext', ''), 'noext');
  });

  testWidgets('footer on a 300x200 photo; tiles agree; seams hold', (tester) async {
    await tester.runAsync(() async {
      await loadBundledFonts();
      final doc = await footerDoc();
      upgradePins(doc);
      // a blurred, shadowed shape lying across the tile seams (x = 64, 128)
      doc.elements.add(LayoutElement.create(ElementType.shape)
        ..pin = Pin.top
        ..x = 150
        ..top = 100
        ..w = 600
        ..h = 300
        ..fill = Fill(type: FillType.solid, color: '#CC2222')
        ..effects = Effects(blur: 6)
        ..shadow = ShadowSpec(on: true, color: '#000000', alpha: 0.6, blur: 60, x: 30, y: 30));
      final prep = await prepareLayout(doc);
      final photo = photoPng(300, 200);
      const s = ExportSettings();
      final big = await PhotoExporter(tileSize: 4096).render(photo, doc, prep, s);
      expect([big.width, big.height, big.ext], [300, 200, 'jpg']);
      expect(img.decodeJpg(big.bytes)!.width, 300);
      final small = await PhotoExporter(tileSize: 64).render(photo, doc, prep, s);
      final d = meanDiff(big.bytes, small.bytes);
      expect(d < 1.0, isTrue, reason: 'mean diff $d');
      final px = await PhotoExporter(tileSize: 64, forcePixelPath: true).render(photo, doc, prep, s);
      final d2 = meanDiff(big.bytes, px.bytes);
      expect(d2 < 1.0, isTrue, reason: 'pixel path diff $d2');
      prep.dispose();
    });
  });

  testWidgets('transparent photo as JPEG is white; PNG keeps alpha', (tester) async {
    await tester.runAsync(() async {
      final photo = photoPng(64, 64, transparent: true);
      final r = await PhotoExporter().render(photo, null, null, const ExportSettings());
      final px = img.decodeJpg(r.bytes)!.getPixel(32, 32);
      expect([px.r, px.g, px.b].every((v) => v >= 252), isTrue, reason: '$px');
      final p = await PhotoExporter()
          .render(photo, null, null, const ExportSettings(format: OutputFormat.png));
      expect(p.ext, 'png');
      expect(img.decodePng(p.bytes)!.getPixel(32, 32).a, 0);
    });
  });

  testWidgets('crop layout of ratio 1 gives 200x200', (tester) async {
    await tester.runAsync(() async {
      final doc = LayoutDoc.blank()
        ..fit = DocFit.crop
        ..ratio = 1;
      final r = await PhotoExporter().render(photoPng(300, 200), doc, null, const ExportSettings());
      expect([r.width, r.height], [200, 200]);
      final px = await PhotoExporter(forcePixelPath: true)
          .render(photoPng(300, 200), doc, null, const ExportSettings());
      expect([px.width, px.height], [200, 200]);
      expect(meanDiff(r.bytes, px.bytes) < 1.0, isTrue);
    });
  });

  group('edits', () {
    testWidgets('no edits and neutral edits save the same bytes as before', (tester) async {
      await tester.runAsync(() async {
        await loadBundledFonts();
        final doc = await footerDoc();
        upgradePins(doc);
        final prep = await prepareLayout(doc);
        final photo = photoPng(300, 200);
        for (final force in [false, true]) {
          for (final s in const [ExportSettings(), ExportSettings(format: OutputFormat.png)]) {
            // Today's exporter: no developer, no edit argument.
            final before =
                await PhotoExporter(tileSize: 64, forcePixelPath: force).render(photo, doc, prep, s);
            final withDev =
                PhotoExporter(tileSize: 64, forcePixelPath: force, developer: UnusedDeveloper());
            final none = await withDev.render(photo, doc, prep, s);
            final nul = await withDev.render(photo, doc, prep, s, edit: null);
            final neutral = await withDev.render(photo, doc, prep, s, edit: edits({}));
            final noDev = await PhotoExporter(tileSize: 64, forcePixelPath: force)
                .render(photo, doc, prep, s, edit: edits({}));
            for (final r in [none, nul, neutral, noDev]) {
              expect(r.bytes, before.bytes, reason: 'pixel path $force, ${s.format}');
            }
          }
        }
        prep.dispose();
        // Without a layout, a PNG save on the pixel path is exactly the
        // photo's own pixels. (The engine path draws with cubic filtering,
        // which moves some values by a level; that is today's output too.)
        final rgba = smoothRgba(97, 61);
        final r = await PhotoExporter(
                tileSize: 32, forcePixelPath: true, developer: UnusedDeveloper())
            .render(encodePng(rgba, 97, 61), null, null,
                const ExportSettings(format: OutputFormat.png), edit: edits({}));
        expect(pngRgba(r.bytes), rgba);
      });
    });

    testWidgets('edits without a developer are refused', (tester) async {
      await tester.runAsync(() async {
        await expectLater(
            PhotoExporter().render(photoPng(40, 30), null, null, const ExportSettings(),
                edit: edits({Setting.exposure: 1})),
            throwsA(isA<StateError>()
                .having((e) => e.message, 'message', 'Photo editing is not available.')));
      });
    });

    testWidgets('exposure +1 brightens the saved centre pixel', (tester) async {
      await tester.runAsync(() async {
        final photo = photoPng(300, 200);
        const s = ExportSettings(format: OutputFormat.png);
        for (final force in [false, true]) {
          final ex = PhotoExporter(tileSize: 128, forcePixelPath: force, developer: CpuDeveloper());
          final plain = pngRgba((await ex.render(photo, null, null, s)).bytes);
          final bright = pngRgba(
              (await ex.render(photo, null, null, s, edit: edits({Setting.exposure: 1}))).bytes);
          final a = luma(plain, 300, 150, 100), b = luma(bright, 300, 150, 100);
          expect(b, greaterThan(a + 20), reason: 'pixel path $force: $a -> $b');
        }
      });
    });

    testWidgets('tiles are developed in whole-photo coordinates, stats measured once',
        (tester) async {
      await tester.runAsync(() async {
        // 300 x 200 cropped to the middle 200 x 200, in 64 px tiles.
        final doc = LayoutDoc.blank()
          ..fit = DocFit.crop
          ..ratio = 1;
        final s = edits({Setting.dehaze: 40, Setting.exposure: 0.5});
        for (final force in [false, true]) {
          final dev = RecordingDeveloper();
          final r = await PhotoExporter(tileSize: 64, forcePixelPath: force, developer: dev)
              .render(photoPng(300, 200), doc, null, const ExportSettings(), edit: s);
          expect([r.width, r.height], [200, 200]);
          expect(dev.calls, hasLength(16), reason: '4 x 4 tiles');
          final stats = dev.calls.first.$4;
          expect(stats, isNotNull, reason: 'dehaze needs the whole-photo airlight');
          for (final c in dev.calls) {
            expect(identical(c.$4, stats), isTrue, reason: 'measured once per photo');
            expect(c.$2, const ui.Size(300, 200), reason: 'the whole upright photo');
            expect(c.$3, 1);
          }
          // First tile: photo x 50..114 (crop 50 + tile 0), 10 px margin each side.
          expect(dev.calls.first.$1, const ui.Offset(40, 0));
          expect([dev.calls.first.$5, dev.calls.first.$6], [84, 74]);
          // Last tile: photo x 242..250, y 192..200, the margin stops at the photo.
          expect(dev.calls.last.$1, const ui.Offset(232, 182));
          expect([dev.calls.last.$5, dev.calls.last.$6], [28, 18]);
          expect(dev.cleared, greaterThanOrEqualTo(1));
          // Without Dehaze nothing is measured.
          final dev2 = RecordingDeveloper();
          await PhotoExporter(tileSize: 64, forcePixelPath: force, developer: dev2).render(
              photoPng(300, 200), doc, null, const ExportSettings(),
              edit: edits({Setting.exposure: 0.5}));
          expect(dev2.calls.every((c) => c.$4 == null), isTrue);
        }
      });
    });

    testWidgets('WYSIWYG: the save matches the developed preview', (tester) async {
      await tester.runAsync(() async {
        final dev = await ShaderDeveloper.load();
        try {
          const w = 960, h = 640, pvW = 480, pvH = 320;
          final rgba = smoothRgba(w, h);
          final photo = encodePng(rgba, w, h);
          final s = edits({
            Setting.exposure: 0.4,
            Setting.contrast: 25,
            Setting.clarity: 30,
            Setting.vignetteAmount: -40,
          });
          // The editor's preview: the whole photo at 480 px, developed at its scale.
          final full = await imageFromRgba(rgba, w, h);
          final preview = await scaleImage(full, pvW, pvH);
          full.dispose();
          final devPreview = await dev.develop(preview, s,
              scale: pvW / w, fullSize: const ui.Size(pvW + 0.0, pvH + 0.0));
          final expected = await readRgba(devPreview);
          devPreview.dispose();
          preview.dispose();

          Future<Uint8List> savedAt(Uint8List png, int sw, int sh, int dw, int dh) async {
            final saved = await imageFromRgba(pngRgba(png), sw, sh);
            final small = await scaleImage(saved, dw, dh);
            saved.dispose();
            final px = await readRgba(small);
            small.dispose();
            return px;
          }

          const png = ExportSettings(format: OutputFormat.png);
          final crop = LayoutDoc.blank()
            ..fit = DocFit.crop
            ..ratio = 1;
          // The square crop is the middle 320 x 320 of the preview.
          final expectedCrop = Uint8List(320 * 320 * 4);
          for (var y = 0; y < 320; y++) {
            expectedCrop.setRange(
                y * 320 * 4, (y + 1) * 320 * 4, expected, (y * pvW + 80) * 4);
          }
          for (final force in [false, true]) {
            final ex = PhotoExporter(tileSize: 256, forcePixelPath: force, developer: dev);
            final r = await ex.render(photo, null, null, png, edit: s);
            expect([r.width, r.height], [w, h]);
            final d = rgbMeanDiff(await savedAt(r.bytes, w, h, pvW, pvH), expected);
            // ignore: avoid_print
            print('WYSIWYG mean diff, pixel path $force: ${d.toStringAsFixed(3)} levels');
            expect(d, lessThan(3), reason: 'pixel path $force');

            final c = await ex.render(photo, crop, null, png, edit: s);
            expect([c.width, c.height], [640, 640]);
            final dc = rgbMeanDiff(await savedAt(c.bytes, 640, 640, 320, 320), expectedCrop);
            // ignore: avoid_print
            print('WYSIWYG crop mean diff, pixel path $force: ${dc.toStringAsFixed(3)} levels');
            expect(dc, lessThan(3), reason: 'crop, pixel path $force');
          }
        } finally {
          dev.dispose();
        }
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('EXIF 6 photo: the vignette darkens the upright corners', (tester) async {
      await tester.runAsync(() async {
        final dev = await ShaderDeveloper.load();
        try {
          final bytes = File('test/assets/exif_rotated_6.jpg').readAsBytesSync();
          final s = edits({Setting.vignetteAmount: -80});
          const png = ExportSettings(format: OutputFormat.png);
          // The preview: the engine's upright decode, developed whole (it is
          // smaller than 480 px, so the preview is the photo itself).
          final codec = await ui.instantiateImageCodec(bytes);
          final upright = (await codec.getNextFrame()).image;
          codec.dispose();
          expect([upright.width, upright.height], [80, 120]);
          final plainPreview = await readRgba(upright);
          final devPreview = await dev.develop(upright, s);
          final preview = await readRgba(devPreview);
          devPreview.dispose();
          upright.dispose();

          void darkerCorners(Uint8List plain, Uint8List edited, String what) {
            double ratio(int x, int y) => luma(edited, 80, x, y) / luma(plain, 80, x, y);
            for (final (x, y) in [(2, 2), (77, 2), (2, 117), (77, 117)]) {
              expect(ratio(x, y), lessThan(0.75), reason: '$what corner ($x, $y)');
            }
            expect(ratio(40, 60), greaterThan(0.9), reason: '$what centre');
          }

          darkerCorners(plainPreview, preview, 'preview');
          for (final force in [false, true]) {
            final ex = PhotoExporter(tileSize: 32, forcePixelPath: force, developer: dev);
            final plain = pngRgba((await ex.render(bytes, null, null, png)).bytes);
            final saved = pngRgba((await ex.render(bytes, null, null, png, edit: s)).bytes);
            darkerCorners(plain, saved, 'save, pixel path $force');
            final d = rgbMeanDiff(saved, preview);
            expect(d, lessThan(3), reason: 'save vs preview, pixel path $force: $d');
          }
        } finally {
          dev.dispose();
        }
      });
    });

    testWidgets('an out-of-memory error from the developer reaches isMemoryFailure',
        (tester) async {
      await tester.runAsync(() async {
        for (final force in [false, true]) {
          final dev = OutOfMemoryDeveloper();
          Object? error;
          try {
            await PhotoExporter(tileSize: 32, forcePixelPath: force, developer: dev).render(
                photoPng(100, 80), null, null, const ExportSettings(),
                edit: edits({Setting.clarity: 50}));
          } catch (e) {
            error = e;
          }
          expect(error, isNotNull, reason: 'pixel path $force');
          expect(isMemoryFailure(error!), isTrue, reason: '$error');
          expect(dev.cleared, greaterThan(0), reason: 'the blur cache is freed');
        }
      });
    });

    testWidgets('big photo on the pixel path with heavy edits', (tester) async {
      await tester.runAsync(() async {
        const w = kBigW, h = kBigH;
        final sw = Stopwatch()..start();
        final jpeg = encodeJpeg(smoothRgba(w, h), w, h, quality: 85);
        final made = sw.elapsedMilliseconds;
        final dev = await ShaderDeveloper.load();
        try {
          sw.reset();
          final r = await PhotoExporter(forcePixelPath: true, developer: dev).render(
              jpeg, null, null, const ExportSettings(),
              edit: edits({
                Setting.clarity: 50,
                Setting.noiseLuminance: 40,
                Setting.grainAmount: 30,
              }));
          // ignore: avoid_print
          print('big photo ${w}x$h: JPEG made in $made ms, saved in '
              '${sw.elapsedMilliseconds} ms, ${r.bytes.length} bytes');
          expect([r.width, r.height], [w, h]);
          expect(r.bytes.length, greaterThan(1000));
        } finally {
          dev.dispose();
        }
      });
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}

const int kBigW = 7200, kBigH = 4800;
