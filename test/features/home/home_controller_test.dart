import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/store/batch_store_memory.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/core/store/preset_store_memory.dart';
import 'package:pio_photo_layout/core/codec/png_encoder.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/platform/file_sharer.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/platform/temp_files_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List png(int w, int h) {
  final b = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    b[i * 4] = (i * 7) & 255;
    b[i * 4 + 1] = 120;
    b[i * 4 + 2] = 200;
    b[i * 4 + 3] = 255;
  }
  return encodePng(b, w, h);
}

PickedPhoto picked(String name, Uint8List bytes, {int day = 1}) => PickedPhoto(
    name: name, readBytes: () async => bytes, size: bytes.length, modified: DateTime(2026, 1, day));

class Rig {
  Rig() {
    controller = HomeController(
      layoutStore: MemoryLayoutStore(),
      settingsStore: SettingsStore(),
      picker: FakePhotoPicker(),
      saver: saver,
      sharer: sharer,
      temp: MemoryTempFiles(),
      presetStore: MemoryPresetStore(),
      batchStore: MemoryBatchStore(),
      developer: CpuDeveloper(),
      fontStore: MemoryFontStore(),
      bundled: () async => [
        LayoutDoc.blank('Plain')..id = 'office:plain',
        LayoutDoc.blank('Second')..id = 'office:second',
      ],
    );
  }
  final saver = FakeGallerySaver();
  final sharer = FakeFileSharer();
  late final HomeController controller;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('three generated photos become three ready items with their sizes', (tester) async {
    await tester.runAsync(() async {
      final r = Rig();
      await r.controller.init();
      await r.controller.addPhotos([picked('a.jpg', png(60, 40)), picked('b.jpg', png(40, 60)), picked('c.jpg', png(50, 50))]);
      await r.controller.whenIdle();
      final p = r.controller.photos;
      expect(p.map((e) => e.status), everyElement(PhotoStatus.ready));
      expect([for (final e in p) '${e.name} ${e.width}x${e.height}'], ['a.jpg 60x40', 'b.jpg 40x60', 'c.jpg 50x50']);
      expect(p.every((e) => e.preview != null), isTrue);
      r.controller.dispose();
    });
  });

  testWidgets('the same file twice is added once; a broken file is an error item', (tester) async {
    await tester.runAsync(() async {
      final r = Rig();
      await r.controller.init();
      final bytes = png(30, 20);
      await r.controller.addPhotos([picked('a.jpg', bytes)]);
      await r.controller.addPhotos([picked('a.jpg', bytes), picked('bad.jpg', Uint8List.fromList([1, 2, 3, 4]))]);
      await r.controller.whenIdle();
      expect(r.controller.photos.length, 2);
      final bad = r.controller.photos.firstWhere((p) => p.name == 'bad.jpg');
      expect(bad.status, PhotoStatus.error);
      expect(bad.error, "Can't open this file.");
      r.controller.dispose();
    });
  });

  testWidgets('a sideways phone photo reports its upright size', (tester) async {
    await tester.runAsync(() async {
      final r = Rig();
      await r.controller.init();
      final bytes = File('test/assets/exif_rotated_6.jpg').readAsBytesSync();
      await r.controller.addPhotos([picked('turned.jpg', bytes)]);
      await r.controller.whenIdle();
      final p = r.controller.photos.single;
      expect([p.width, p.height], [80, 120]);
      expect(p.preview!.width < p.preview!.height, isTrue);
      r.controller.dispose();
    });
  });

  testWidgets('saveAll names files like the web app and reports the result', (tester) async {
    await tester.runAsync(() async {
      final r = Rig();
      await r.controller.init();
      await r.controller.addPhotos([picked('b.png', png(30, 20)), picked('a.jpg', png(30, 20)), picked('b.jpg', png(30, 20))]);
      await r.controller.whenIdle();
      await r.controller.saveAll();
      expect(r.saver.names, ['a_PIO.jpg', 'b_PIO.jpg', 'b_PIO (2).jpg']);
      expect(r.controller.message, startsWith('Saved 3 photos to Photos, album e-Layout ('));
      expect(r.controller.job, isNull);
      await r.controller.shareLast();
      expect(r.sharer.shared.single.length, 3);
      r.controller.dispose();
    });
  });

  testWidgets('cancel after the first save stops the rest and says so', (tester) async {
    await tester.runAsync(() async {
      final r = Rig();
      await r.controller.init();
      await r.controller.addPhotos([picked('a.jpg', png(30, 20)), picked('b.jpg', png(30, 20)), picked('c.jpg', png(30, 20))]);
      await r.controller.whenIdle();
      r.saver.before = (_) => r.controller.cancelSave();
      await r.controller.saveAll();
      expect(r.saver.names, ['a_PIO.jpg']);
      expect(r.controller.message, 'Cancelled. 1 photo was already saved to Photos, album e-Layout.');
      r.controller.dispose();
    });
  });

  testWidgets('the selected layout is remembered through SettingsStore', (tester) async {
    await tester.runAsync(() async {
      final r = Rig();
      await r.controller.init();
      expect(r.controller.selectedId, 'office:plain');
      await r.controller.selectLayout('office:second');
      expect((await SettingsStore().load()).layoutId, 'office:second');
      final again = Rig();
      await again.controller.init();
      expect(again.controller.selectedId, 'office:second');
      r.controller.dispose();
      again.controller.dispose();
    });
  });
}
