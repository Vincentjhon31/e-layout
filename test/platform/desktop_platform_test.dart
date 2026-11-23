import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/store/batch_store_memory.dart';
import 'package:pio_photo_layout/core/store/preset_store_memory.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/platform/desktop_photo_picker_io.dart';
import 'package:pio_photo_layout/platform/file_sharer.dart';
import 'package:pio_photo_layout/platform/folder_saver_io.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/platform/temp_files_memory.dart';
import 'package:pio_photo_layout/platform/zip_saver.dart';
import 'package:pio_photo_layout/platform/zip_writer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/home/home_controller_test.dart' show png, picked;

Uint8List bytesOf(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  late Directory tmp;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('pio_platform_');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('FolderSaver', () {
    test('writes every photo and never overwrites a file that is already there', () async {
      File(p.join(tmp.path, 'a_PIO.jpg')).writeAsStringSync('old');
      final saver = FolderSaver(pickFolder: () async => tmp.path);
      expect(await saver.beginBatch(3), isTrue);
      final p1 = await saver.saveImage(bytesOf('A'), 'a_PIO.jpg');
      await saver.saveImage(bytesOf('B'), 'b_PIO.jpg');
      await saver.saveImage(bytesOf('B2'), 'b_PIO (2).jpg');
      await saver.endBatch(keep: true);
      expect(p.basename(p1!), 'a_PIO (2).jpg');
      expect(File(p.join(tmp.path, 'a_PIO.jpg')).readAsStringSync(), 'old');
      expect(File(p.join(tmp.path, 'a_PIO (2).jpg')).readAsStringSync(), 'A');
      expect(File(p.join(tmp.path, 'b_PIO.jpg')).readAsStringSync(), 'B');
      expect(File(p.join(tmp.path, 'b_PIO (2).jpg')).readAsStringSync(), 'B2');
      expect(saver.destinationLabel, p.basename(tmp.path));
    });

    test('a later photo that wants a name already taken by a bumped file is bumped again', () async {
      final saver = FolderSaver(pickFolder: () async => tmp.path);
      File(p.join(tmp.path, 'x.jpg')).writeAsStringSync('old');
      await saver.beginBatch(2);
      await saver.saveImage(bytesOf('1'), 'x.jpg'); // becomes x (2).jpg
      await saver.saveImage(bytesOf('2'), 'x (2).jpg'); // becomes x (2) (2).jpg
      expect(tmp.listSync().length, 3);
      expect(File(p.join(tmp.path, 'x.jpg')).readAsStringSync(), 'old');
    });

    test('cancelling the folder dialog starts nothing', () async {
      final saver = FolderSaver(pickFolder: () async => null);
      expect(await saver.beginBatch(2), isFalse);
    });

    test('outside a batch one photo asks where to save it', () async {
      final target = p.join(tmp.path, 'chosen.jpg');
      String? asked;
      final saver = FolderSaver(
        pickFolder: () async => null,
        saveDialog: (name, bytes) async {
          asked = name;
          File(target).writeAsBytesSync(bytes);
          return target;
        },
      );
      final path = await saver.saveImage(bytesOf('Z'), 'one_PIO.jpg');
      expect(asked, 'one_PIO.jpg');
      expect(path, target);
      final cancel = FolderSaver(pickFolder: () async => null, saveDialog: (n, b) async => null);
      expect(() => cancel.saveImage(bytesOf('Z'), 'one.jpg'), throwsA(isA<SaveCancelledException>()));
    });
  });

  group('Add a folder', () {
    test('finds the photos in the folder and its subfolders in name order and skips other files', () async {
      File(p.join(tmp.path, 'x.jpg')).writeAsBytesSync(png(4, 4));
      Directory(p.join(tmp.path, 'sub')).createSync();
      File(p.join(tmp.path, 'sub', 'y.png')).writeAsBytesSync(png(4, 4));
      File(p.join(tmp.path, 'notes.txt')).writeAsStringSync('hi');
      final picker = DesktopPhotoPicker(pickFolderPath: () async => tmp.path);
      final found = await picker.pickFolder();
      expect(found.map((e) => e.name), ['x.jpg', 'y.png']);
      expect((await found.first.readBytes()).length, png(4, 4).length);
    });

    testWidgets('the home controller adds them', (tester) async {
      await tester.runAsync(() async {
      File(p.join(tmp.path, 'b.jpg')).writeAsBytesSync(png(30, 20));
      Directory(p.join(tmp.path, 'sub')).createSync();
      File(p.join(tmp.path, 'sub', 'a.png')).writeAsBytesSync(png(30, 20));
      final c = HomeController(
        layoutStore: MemoryLayoutStore(),
        settingsStore: SettingsStore(),
        picker: DesktopPhotoPicker(pickFolderPath: () async => tmp.path),
        saver: FakeGallerySaver(),
        sharer: FakeFileSharer(),
        temp: MemoryTempFiles(),
        presetStore: MemoryPresetStore(),
        batchStore: MemoryBatchStore(),
        developer: CpuDeveloper(),
        fontStore: MemoryFontStore(),
        bundled: () async => [LayoutDoc.blank('Plain')..id = 'office:plain'],
      );
      await c.addFolder();
      await c.whenIdle();
      expect(c.photos.map((e) => e.name), ['a.png', 'b.jpg']);
      c.dispose();
      });
    });
  });

  group('ZipWriter', () {
    test('makes a stored archive that package:archive reads back', () {
      final w = ZipWriter();
      w.add('a_PIO.jpg', bytesOf('first photo'), DateTime(2026, 11, 15, 10, 30));
      w.add('b_PIO.jpg', Uint8List.fromList(List.generate(5000, (i) => i & 255)), DateTime(2026, 11, 15));
      final data = w.finish();
      final archive = ZipDecoder().decodeBytes(data);
      expect(archive.files.map((f) => f.name), ['a_PIO.jpg', 'b_PIO.jpg']);
      expect(String.fromCharCodes(archive.files[0].content as List<int>), 'first photo');
      expect(archive.files[1].content, List.generate(5000, (i) => i & 255));
      // Stored, not deflated: compression method 0 in the central directory.
      final bd = ByteData.sublistView(data);
      var stored = 0;
      for (var i = 0; i + 4 < data.length; i++) {
        if (bd.getUint32(i, Endian.little) == 0x02014b50) {
          expect(bd.getUint16(i + 10, Endian.little), 0);
          stored++;
        }
      }
      expect(stored, 2);
    });

    test('refuses to grow past 4 GB', () {
      final w = ZipWriter(limit: 250);
      w.add('a', Uint8List(60), DateTime(2026));
      expect(() => w.add('b', Uint8List(60), DateTime(2026)), throwsA(isA<ZipTooLargeException>()));
    });
  });

  group('ZipSaver', () {
    test('collects the batch into one named download', () async {
      String? name;
      Uint8List? zip;
      final saver = ZipSaver(
        download: (n, parts) async {
          name = n;
          zip = (BytesBuilder(copy: false)..add(parts.expand((e) => e).toList())).takeBytes();
        },
        today: () => DateTime(2026, 11, 5),
      );
      await saver.beginBatch(2);
      await saver.saveImage(bytesOf('one'), 'a_PIO.jpg');
      await saver.saveImage(bytesOf('two'), 'b_PIO.jpg');
      await saver.endBatch(keep: true);
      expect(name, 'PIO-photos-2026-11-05.zip');
      expect(ZipDecoder().decodeBytes(zip!).files.map((f) => f.name), ['a_PIO.jpg', 'b_PIO.jpg']);
      expect(saver.resultLine(2, '48.2 MB'), 'Downloaded 2 photos in a ZIP (48.2 MB).');
    });

    test('a cancelled batch downloads nothing; one photo outside a batch downloads directly', () async {
      final downloads = <String>[];
      final saver = ZipSaver(download: (n, z) async => downloads.add(n));
      await saver.beginBatch(2);
      await saver.saveImage(bytesOf('one'), 'a.jpg');
      await saver.endBatch(keep: false);
      expect(downloads, isEmpty);
      await saver.saveImage(bytesOf('one'), 'solo.jpg');
      expect(downloads, ['solo.jpg']);
    });

    test('a batch past the ZIP limit stops with the web app wording', () async {
      final saver = ZipSaver(download: (n, z) async {}, limit: 200);
      await saver.beginBatch(2);
      await saver.saveImage(Uint8List(60), 'a.jpg');
      await expectLater(
        saver.saveImage(Uint8List(60), 'b.jpg'),
        throwsA(isA<SaveStoppedException>().having((e) => e.message, 'message', contains('over 4 GB'))),
      );
    });
  });

  testWidgets('a desktop save writes into the chosen folder and says so', (tester) async {
    await tester.runAsync(() async {
      final saver = FolderSaver(pickFolder: () async => tmp.path);
      final c = HomeController(
        layoutStore: MemoryLayoutStore(),
        settingsStore: SettingsStore(),
        picker: FakePhotoPicker(),
        saver: saver,
        sharer: FakeFileSharer(needsCopies: false),
        temp: MemoryTempFiles(),
        presetStore: MemoryPresetStore(),
        batchStore: MemoryBatchStore(),
        developer: CpuDeveloper(),
        fontStore: MemoryFontStore(),
        bundled: () async => [LayoutDoc.blank('Plain')..id = 'office:plain'],
      );
      await c.init();
      await c.addPhotos([picked('b.png', png(30, 20)), picked('a.jpg', png(30, 20)), picked('b.jpg', png(30, 20))]);
      await c.whenIdle();
      await c.saveAll();
      final name = p.basename(tmp.path);
      expect(c.message, startsWith('Saved 3 photos to $name ('));
      expect(c.message, endsWith(' MB).'));
      final files = tmp.listSync().map((e) => p.basename(e.path)).toList()..sort();
      expect(files, ['a_PIO.jpg', 'b_PIO (2).jpg', 'b_PIO.jpg']);
      // "Show in folder" gets the real paths, not temp copies.
      expect(c.lastSaved.map(p.basename), ['a_PIO.jpg', 'b_PIO.jpg', 'b_PIO (2).jpg']);
      c.dispose();
    });
  });

  testWidgets('a cancelled folder dialog saves nothing and shows no message', (tester) async {
    await tester.runAsync(() async {
      final c = HomeController(
        layoutStore: MemoryLayoutStore(),
        settingsStore: SettingsStore(),
        picker: FakePhotoPicker(),
        saver: FolderSaver(pickFolder: () async => null),
        sharer: FakeFileSharer(needsCopies: false),
        temp: MemoryTempFiles(),
        presetStore: MemoryPresetStore(),
        batchStore: MemoryBatchStore(),
        developer: CpuDeveloper(),
        fontStore: MemoryFontStore(),
        bundled: () async => [LayoutDoc.blank('Plain')..id = 'office:plain'],
      );
      await c.init();
      await c.addPhotos([picked('a.jpg', png(30, 20))]);
      await c.whenIdle();
      await c.saveAll();
      expect(c.message, '');
      expect(c.job, isNull);
      c.dispose();
    });
  });

  testWidgets('a ZIP batch that runs out of room stops and says how many were saved', (tester) async {
    await tester.runAsync(() async {
      final zips = <String>[];
      final c = HomeController(
        layoutStore: MemoryLayoutStore(),
        settingsStore: SettingsStore(),
        picker: FakePhotoPicker(),
        saver: ZipSaver(download: (n, z) async => zips.add(n), limit: 3000),
        sharer: FakeFileSharer(needsCopies: false),
        temp: MemoryTempFiles(),
        presetStore: MemoryPresetStore(),
        batchStore: MemoryBatchStore(),
        developer: CpuDeveloper(),
        fontStore: MemoryFontStore(),
        bundled: () async => [LayoutDoc.blank('Plain')..id = 'office:plain'],
      );
      await c.init();
      await c.addPhotos([for (final n in ['a', 'b', 'c']) picked('$n.jpg', png(40, 30))]);
      await c.whenIdle();
      await c.saveAll();
      expect(zips.length, 1, reason: 'what fitted is still downloaded');
      expect(c.message, startsWith('Downloaded '));
      expect(c.message, contains('in a ZIP'));
      expect(c.message, contains('over 4 GB'));
      c.dispose();
    });
  });
}
