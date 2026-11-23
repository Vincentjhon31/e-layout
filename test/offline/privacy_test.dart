import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/store/batch_store_memory.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/core/store/preset_store_memory.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/platform/file_sharer.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/platform/temp_files_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/home/home_controller_test.dart' show picked;

void main() {
  testWidgets('a saved photo carries no camera details (no Exif block)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      final saver = FakeGallerySaver();
      final c = HomeController(
        layoutStore: MemoryLayoutStore(),
        settingsStore: SettingsStore(),
        picker: FakePhotoPicker(),
        saver: saver,
        sharer: FakeFileSharer(),
        temp: MemoryTempFiles(),
        presetStore: MemoryPresetStore(),
        batchStore: MemoryBatchStore(),
        developer: CpuDeveloper(),
        fontStore: MemoryFontStore(),
      );
      await c.init();
      final source = File('test/assets/exif_rotated_6.jpg').readAsBytesSync();
      expect(String.fromCharCodes(source).contains('Exif'), isTrue, reason: 'the sample photo must have Exif to prove anything');
      await c.addPhotos([picked('turned.jpg', source)]);
      await c.whenIdle();
      await c.saveAll();
      expect(saver.files, hasLength(1));
      final out = saver.files.single;
      expect(out[0], 0xFF);
      expect(out[1], 0xD8); // a JPEG
      // An Exif block is an APP1 segment (FF E1) that starts with "Exif\0\0".
      final text = String.fromCharCodes(out);
      expect(text.contains('Exif\u0000\u0000'), isFalse);
      c.dispose();
    });
  });
}
