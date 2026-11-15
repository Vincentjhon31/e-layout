import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/render/sample_scene.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/home/export_job.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/features/home/home_screen.dart';
import 'package:pio_photo_layout/features/home/home_wiring.dart';
import 'package:pio_photo_layout/features/home/options_sheet.dart';
import 'package:pio_photo_layout/platform/file_sharer.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/platform/temp_files_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/golden_helpers.dart';

/// Six made-up photos: the sample scene at different shapes and tints.
Future<List<PickedPhoto>> samplePhotos() async {
  const shapes = [(600, 400), (400, 600), (600, 400), (500, 500), (600, 400), (400, 600)];
  final out = <PickedPhoto>[];
  for (var i = 0; i < shapes.length; i++) {
    final (w, h) = shapes[i];
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    paintSampleScene(c, ui.Size(w.toDouble(), h.toDouble()));
    c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..color = HSVColor.fromAHSV(0.18, i * 55.0, 0.6, 0.9).toColor());
    final img = await rec.endRecording().toImage(w, h);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    img.dispose();
    out.add(PickedPhoto(
        name: 'IMG_${2041 + i}.jpg', readBytes: () async => Uint8List.fromList(bytes), size: bytes.length));
  }
  return out;
}

HomeController newController() => HomeController(
      layoutStore: MemoryLayoutStore(),
      settingsStore: SettingsStore(),
      picker: FakePhotoPicker(),
      saver: FakeGallerySaver(),
      sharer: FakeFileSharer(),
      temp: MemoryTempFiles(),
      fontStore: MemoryFontStore(),
    );

Future<HomeController> ready(WidgetTester tester, {bool withPhotos = false}) async {
  final c = newController();
  await tester.runAsync(() async {
    await loadAppFonts();
    await c.init();
    if (withPhotos) {
      await c.addPhotos(await samplePhotos());
      await c.whenIdle();
    }
  });
  addTearDown(c.dispose);
  return c;
}

Future<void> shoot(WidgetTester tester, HomeController c, Brightness b, String name,
    {Size size = const Size(390, 844)}) async {
  setPhone(tester, size: size);
  await tester.pumpWidget(themed(HomeScreen(controller: c, actions: homeActions(c)), b));
  await tester.pump();
  await expectLater(find.byType(HomeScreen), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final b in Brightness.values) {
    final tag = b == Brightness.dark ? 'dark' : 'light';
    testWidgets('home empty $tag', (tester) async {
      final c = await ready(tester);
      await shoot(tester, c, b, 'home_empty_$tag');
    });
    testWidgets('home with photos $tag', (tester) async {
      final c = await ready(tester, withPhotos: true);
      expect(c.current!.doc.name, 'PIO footer');
      await shoot(tester, c, b, 'home_photos_$tag');
    });
  }

  testWidgets('home saving', (tester) async {
    final c = await ready(tester, withPhotos: true);
    c.job = ExportJob(6)
      ..current = 3
      ..done = 2
      ..currentName = 'IMG_2043.jpg';
    await shoot(tester, c, Brightness.light, 'home_saving');
  });

  testWidgets('home saved', (tester) async {
    final c = await ready(tester, withPhotos: true);
    c.message = 'Saved 6 photos to Photos, album e-Layout (48.2 MB).';
    c.lastSaved = ['memory/saved/IMG_2041_PIO.jpg'];
    await shoot(tester, c, Brightness.light, 'home_saved');
  });

  testWidgets('home on a small phone', (tester) async {
    final c = await ready(tester, withPhotos: true);
    c.message = 'Saved 6 photos to Photos, album e-Layout (48.2 MB).';
    c.lastSaved = ['x'];
    await shoot(tester, c, Brightness.light, 'home_small', size: const Size(320, 568));
  });

  testWidgets('options sheet', (tester) async {
    final c = await ready(tester);
    setPhone(tester);
    await tester.pumpWidget(themed(
        CupertinoPageScaffold(
            child: Align(alignment: Alignment.bottomCenter, child: OptionsSheet(controller: c))),
        Brightness.light));
    await tester.pump();
    await expectLater(find.byType(CupertinoPageScaffold), matchesGoldenFile('goldens/options_sheet.png'));
  });
}
