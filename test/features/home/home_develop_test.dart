import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pio_photo_layout/core/codec/png_encoder.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/store/batch_store.dart';
import 'package:pio_photo_layout/core/store/batch_store_memory.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/preset_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/platform/file_sharer.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/platform/temp_files_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/presets/fixtures.dart';
import 'home_controller_test.dart' show picked, png;

/// Puts nothing: every write fails, as on a full or locked disk.
class FailingBatchStore extends MemoryBatchStore {
  @override
  Future<String> putPhoto(String name, Uint8List bytes) =>
      Future.error(StateError('The disk is full.'));

  @override
  Future<void> saveManifest(BatchManifest m) =>
      Future.error(StateError('The disk is full.'));
}

/// Each put waits until the test completes its entry in [waits].
class SlowBatchStore extends MemoryBatchStore {
  final waits = <Completer<void>>[];
  final keys = <String>[];

  @override
  Future<String> putPhoto(String name, Uint8List bytes) async {
    final c = Completer<void>();
    waits.add(c);
    await c.future;
    final k = await super.putPhoto(name, bytes);
    keys.add(k);
    return k;
  }

  /// Lets put number [i] (from 0) go once it has started.
  Future<void> release(int i) async {
    await until(() => waits.length > i);
    waits[i].complete();
  }
}

/// Puts and measurements fail while the flags say so.
class FlakyBatchStore extends MemoryBatchStore {
  bool failPut = false;
  bool failMeasure = false;

  @override
  Future<String> putPhoto(String name, Uint8List bytes) => failPut
      ? Future.error(StateError('The disk is full.'))
      : super.putPhoto(name, bytes);

  @override
  Future<int> usedBytes() => failMeasure
      ? Future.error(StateError('Cannot measure.'))
      : super.usedBytes();
}

/// Counts the measurements.
class CountingBatchStore extends MemoryBatchStore {
  int measures = 0;

  @override
  Future<int> usedBytes() {
    measures++;
    return super.usedBytes();
  }
}

/// Waits (real time, inside runAsync) until [ok] holds.
Future<void> until(bool Function() ok) async {
  for (var i = 0; i < 2000 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ok(), isTrue, reason: 'timed out waiting');
}

class Stores {
  final batch = MemoryBatchStore();
  final presets = MemoryPresetStore();
}

class Rig {
  Rig(
    this.stores, {
    PhotoDeveloper? developer,
    BatchStore? batch,
    Future<PhotoDeveloper?>? developerLoad,
  }) {
    controller = HomeController(
      layoutStore: MemoryLayoutStore(),
      settingsStore: SettingsStore(),
      picker: FakePhotoPicker(),
      saver: saver,
      sharer: sharer,
      temp: MemoryTempFiles(),
      fontStore: MemoryFontStore(),
      presetStore: stores.presets,
      batchStore: batch ?? stores.batch,
      developer: developer,
      developerLoad: developerLoad,
      bundled: () async => [LayoutDoc.blank('Plain')..id = 'office:plain'],
    );
  }
  final Stores stores;
  final saver = FakeGallerySaver();
  final sharer = FakeFileSharer();
  late final HomeController controller;
}

SettingsPatch exposure(double v) =>
    SettingsPatch(values: {Setting.exposure: v});

/// Mean of the RGB values of an encoded picture.
double meanLevel(Uint8List bytes) {
  final d = img.decodeImage(bytes)!;
  var sum = 0.0;
  for (final p in d) {
    sum += p.r + p.g + p.b;
  }
  return sum / (d.width * d.height * 3);
}

Uint8List grey(int w, int h, int v) {
  final b = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    b[i * 4] = v;
    b[i * 4 + 1] = v;
    b[i * 4 + 2] = v;
    b[i * 4 + 3] = 255;
  }
  return b;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('kept bytes are measured when photos change, not on a look', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = CountingBatchStore();
      final c = Rig(Stores(), developer: CpuDeveloper(), batch: store).controller;
      await c.init();
      await c.whenIdle();
      final afterInit = store.measures;
      await c.addPhotos([picked('a.jpg', png(40, 30))]);
      await c.whenIdle();
      expect(store.measures, greaterThan(afterInit), reason: 'a copy was kept');
      expect(c.keptBytes, await store.usedBytes());
      final before = store.measures;
      await c.setLook(c.look.withPhotoPatch(c.photos.first.id, exposure(1)));
      await c.whenIdle();
      expect(store.measures, before, reason: 'a look does not measure');
      c.dispose();
    });
  });

  testWidgets('photos and edits come back after a restart', (tester) async {
    await tester.runAsync(() async {
      final stores = Stores();
      final a = Rig(stores, developer: CpuDeveloper()).controller;
      await a.init();
      await a.addPhotos([
        picked('a.jpg', png(40, 30)),
        picked('b.jpg', png(30, 40)),
      ]);
      await a.whenIdle();
      final first = a.photos.first;
      await a.setLook(a.look.withPhotoPatch(first.id, exposure(1)));
      await a.whenIdle();
      expect(first.developed, isNotNull);
      expect(
        a.photos.last.developed,
        isNull,
        reason: 'a neutral photo keeps its preview',
      );
      // A look does not measure, so only the manifest's growth is missing.
      expect(
        a.keptBytes,
        closeTo(await stores.batch.usedBytes(), 2048),
      );
      expect(a.keptBytes, greaterThan(0));
      final look = a.look.toJson();
      final ids = [for (final p in a.photos) p.id];
      a.dispose();

      final b = Rig(stores, developer: CpuDeveloper()).controller;
      await b.init();
      await b.whenIdle();
      expect([for (final p in b.photos) p.name], ['a.jpg', 'b.jpg']);
      expect([for (final p in b.photos) p.id], ids);
      expect(b.photos.map((p) => p.status), everyElement(PhotoStatus.ready));
      expect(
        [for (final p in b.photos) '${p.width}x${p.height}'],
        ['40x30', '30x40'],
      );
      expect(b.look.toJson(), look);
      expect(b.hasOwnChanges(b.photos.first), isTrue);
      expect(b.settingsFor(b.photos.first)[Setting.exposure], 1);
      expect(b.photos.first.developed, isNotNull);
      expect(b.photos.first.key, isNotNull);

      // A photo added after the restart gets a new number.
      await b.addPhotos([picked('c.jpg', png(20, 20))]);
      await b.whenIdle();
      final all = [for (final p in b.photos) p.id];
      expect(all.toSet().length, 3);
      expect(all.last, greaterThan(ids.reduce((x, y) => x > y ? x : y)));
      b.dispose();
    });
  });

  testWidgets(
    'a kept photo whose bytes are gone shows the error, the rest restore',
    (tester) async {
      await tester.runAsync(() async {
        final stores = Stores();
        final a = Rig(stores).controller;
        await a.init();
        await a.addPhotos([
          picked('a.jpg', png(40, 30)),
          picked('b.jpg', png(30, 40)),
        ]);
        await a.whenIdle();
        await stores.batch.removePhoto(a.photos.first.key!);
        a.dispose();

        final b = Rig(stores).controller;
        await b.init();
        await b.whenIdle();
        expect(b.photos.length, 2);
        expect(b.photos.first.status, PhotoStatus.error);
        expect(b.photos.first.error, "Can't open this file.");
        expect(b.photos.last.status, PhotoStatus.ready);
        b.dispose();
      });
    },
  );

  testWidgets('clear empties the store and the look', (tester) async {
    await tester.runAsync(() async {
      final stores = Stores();
      final c = Rig(stores, developer: CpuDeveloper()).controller;
      await c.init();
      await c.addPhotos([
        picked('a.jpg', png(40, 30)),
        picked('b.jpg', png(30, 40)),
      ]);
      await c.whenIdle();
      final key = c.photos.first.key!;
      await c.choosePresetForAll(
        await c.savePreset('Bright', EditSettings.resolve([exposure(0.5)])),
      );
      await c.setLook(c.look.withPhotoPatch(c.photos.first.id, exposure(1)));
      await c.whenIdle();
      await c.clearPhotos();
      expect(c.photos, isEmpty);
      expect(c.look.photos, isEmpty);
      expect(c.look.shared.isEmpty, isTrue);
      expect(c.look.sharedName, isNull);
      expect((await stores.batch.load())?.photos ?? [], isEmpty);
      await expectLater(stores.batch.readPhoto(key), throwsStateError);
      expect(c.keptBytes, await stores.batch.usedBytes());
      expect(c.presets.length, 1, reason: 'presets are not part of the batch');
      c.dispose();

      final again = Rig(stores).controller;
      await again.init();
      await again.whenIdle();
      expect(again.photos, isEmpty);
      again.dispose();
    });
  });

  testWidgets('choosing a preset for all keeps single-photo changes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final stores = Stores();
      final c = Rig(stores, developer: CpuDeveloper()).controller;
      await c.init();
      await c.addPhotos([
        picked('a.jpg', png(40, 30)),
        picked('b.jpg', png(30, 40)),
      ]);
      await c.whenIdle();
      final [p1, p2] = c.photos;
      await c.setLook(c.look.withPhotoPatch(p1.id, exposure(1)));
      final preset = await c.savePreset(
        'Bright',
        EditSettings.resolve([
          SettingsPatch(values: {Setting.exposure: 0.5, Setting.contrast: 20}),
        ]),
      );
      expect(preset.name, 'Bright');
      expect(
        preset.patch.values.length,
        Setting.values.length,
        reason: 'the full settings',
      );
      expect((await stores.presets.loadPresets()).single.id, preset.id);

      await c.choosePresetForAll(preset);
      await c.whenIdle();
      expect(c.look.sharedName, 'Bright');
      expect(c.settingsFor(p1)[Setting.exposure], 1);
      expect(c.settingsFor(p1)[Setting.contrast], 20);
      expect(c.settingsFor(p2)[Setting.exposure], 0.5);
      expect(c.hasOwnChanges(p1), isTrue);
      expect(c.hasOwnChanges(p2), isFalse);
      expect(p2.developed, isNotNull);
      final saved = (await stores.batch.load())!;
      expect(saved.look.toJson(), c.look.toJson());

      await c.choosePresetForAll(null);
      expect(c.look.sharedName, isNull);
      expect(c.settingsFor(p2).isNeutral, isTrue);
      expect(c.settingsFor(p1)[Setting.exposure], 1);

      await c.removePreset(preset);
      expect(c.presets, isEmpty);
      expect(await stores.presets.loadPresets(), isEmpty);
      c.dispose();
    });
  });

  testWidgets('importing a profile after its preset links them', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final stores = Stores();
      final c = Rig(stores, developer: CpuDeveloper()).controller;
      await c.init();
      await c.addPhotos([picked('a.jpg', png(40, 30))]);
      await c.whenIdle();
      final p = c.photos.single;

      final first = await c.importPresets([
        picked('a.xmp', bytes(presetXmp())),
      ]);
      expect(first, contains('needs the profile'));
      expect(c.presets.single.name, 'Soft Test');
      await c.choosePresetForAll(c.presets.single);
      await c.whenIdle();
      expect(c.settingsFor(p).profile.id, lookUuid);
      expect(c.profileFor(c.settingsFor(p)), isNull);
      final before = p.developedKey;
      expect(before, isNotNull);

      final second = await c.importPresets([
        picked('look.xmp', bytes(lookXmp())),
      ]);
      expect(second, 'Imported the profile "Test Look".');
      expect(c.profiles.keys, [lookUuid]);
      expect(c.profileFor(c.settingsFor(p)), isNotNull);
      expect((await stores.presets.loadProfiles()).single.id, lookUuid);
      await c.whenIdle();
      expect(
        p.developedKey,
        isNot(before),
        reason: 'the thumbnail is made again with the profile',
      );
      expect(c.profileFor(EditSettings.resolve([])), isNull);
      c.dispose();

      // Presets and profiles are kept.
      final again = Rig(stores).controller;
      await again.init();
      expect(again.presets.single.name, 'Soft Test');
      expect(again.profiles.keys, [lookUuid]);
      again.dispose();
    });
  });

  testWidgets('a file over 300 MB is skipped without reading it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final c = Rig(Stores(), developer: CpuDeveloper()).controller;
      await c.init();
      var read = false;
      final huge = PickedPhoto(
        name: 'huge.xmp',
        size: 301 * 1024 * 1024,
        readBytes: () async {
          read = true;
          return Uint8List(0);
        },
      );
      final line = await c.importPresets([
        huge,
        picked('a.xmp', bytes(presetXmp())),
      ]);
      expect(read, isFalse);
      expect(line, endsWith(' Some files were too big to read.'));
      expect(' Some files were too big to read.'.allMatches(line).length, 1);
      expect(c.presets.single.name, 'Soft Test');
      c.dispose();
    });
  });

  testWidgets("saving uses each photo's own settings", (tester) async {
    await tester.runAsync(() async {
      final c = Rig(Stores(), developer: CpuDeveloper());
      await c.controller.init();
      final source = encodePng(grey(24, 16, 90), 24, 16);
      await c.controller.addPhotos([
        picked('a.png', source),
        picked('b.png', source),
      ]);
      await c.controller.whenIdle();
      final [p1, _] = c.controller.photos;
      await c.controller.setLook(
        c.controller.look.withPhotoPatch(p1.id, exposure(1)),
      );
      await c.controller.saveAll();
      expect(c.saver.names, ['a_PIO.jpg', 'b_PIO.jpg']);
      final a = meanLevel(c.saver.files[0]), b = meanLevel(c.saver.files[1]);
      expect(a, greaterThan(b + 20), reason: 'photo 1 is brighter ($a vs $b)');
      expect(b, closeTo(90, 4));

      final one = await c.controller.saveOne(p1);
      expect(one, isNotNull);
      expect(meanLevel(c.saver.files.last), closeTo(a, 2));
      c.controller.dispose();
    });
  });

  testWidgets('removing a photo drops its overrides', (tester) async {
    await tester.runAsync(() async {
      final stores = Stores();
      final c = Rig(stores, developer: CpuDeveloper()).controller;
      await c.init();
      await c.addPhotos([
        picked('a.jpg', png(40, 30)),
        picked('b.jpg', png(30, 40)),
      ]);
      await c.whenIdle();
      final [p1, p2] = c.photos;
      await c.setLook(
        c.look
            .withPhotoPatch(p1.id, exposure(1))
            .withPhotoPatch(p2.id, exposure(-1)),
      );
      await c.whenIdle();
      final key = p1.key!;
      await c.removePhoto(p1.id);
      expect(c.photos, [p2]);
      expect(c.hasOwnChanges(p2), isTrue);
      expect(c.look.hasOwnChanges(p1.id), isFalse);
      await expectLater(stores.batch.readPhoto(key), throwsStateError);
      final saved = (await stores.batch.load())!;
      expect([for (final p in saved.photos) p.name], ['b.jpg']);
      expect(saved.look.photos.keys, [p2.id]);
      expect(c.keptBytes, await stores.batch.usedBytes());
      c.dispose();
    });
  });

  testWidgets('batch store failure shows the note', (tester) async {
    await tester.runAsync(() async {
      final c = Rig(
        Stores(),
        developer: CpuDeveloper(),
        batch: FailingBatchStore(),
      ).controller;
      await c.init();
      expect(c.batchOk, isTrue);
      await c.addPhotos([picked('a.jpg', png(40, 30))]);
      await c.whenIdle();
      expect(c.batchOk, isFalse);
      final p = c.photos.single;
      expect(
        p.status,
        PhotoStatus.ready,
        reason: 'the photo stays for this visit',
      );
      expect(p.key, isNull);
      expect(
        c.notices.map((n) => n.text),
        contains(
          "Photos can't be kept on this phone, so they will be gone when the app closes.",
        ),
      );
      expect(c.editingAvailable, isTrue);
      c.dispose();
    });
  });

  testWidgets('without a developer editing is off and saving is as before', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final c = Rig(Stores());
      await c.controller.init();
      expect(c.controller.editingAvailable, isFalse);
      expect(
        c.controller.notices.map((n) => n.text),
        contains("Photo editing isn't available on this phone."),
      );
      await c.controller.addPhotos([picked('a.jpg', png(30, 20))]);
      await c.controller.whenIdle();
      await c.controller.setLook(
        c.controller.look.withPhotoPatch(
          c.controller.photos.single.id,
          exposure(1),
        ),
      );
      await c.controller.whenIdle();
      expect(c.controller.photos.single.developed, isNull);
      await c.controller.saveAll();
      expect(c.saver.names, ['a_PIO.jpg']);
      expect(c.controller.message, startsWith('Saved 1 photo'));
      c.controller.dispose();
    });
  });

  testWidgets(
    'clearing during an add leaves the list, manifest and store empty',
    (tester) async {
      await tester.runAsync(() async {
        final store = SlowBatchStore();
        final c = Rig(Stores(), batch: store).controller;
        await c.init();
        await c.addPhotos([
          picked('a.jpg', png(40, 30)),
          picked('b.jpg', png(30, 40)),
          picked('c.jpg', png(20, 20)),
        ]);
        await store.release(0); // a is copied
        await until(() => store.waits.length == 2); // b's copy is on its way
        expect(c.photos.first.key, isNotNull);
        final cleared = c.clearPhotos();
        store.waits[1].complete(); // b arrives after the clear started
        await cleared;
        await c.whenIdle();
        expect(c.photos, isEmpty);
        expect((await store.load())?.photos ?? [], isEmpty);
        expect(store.keys.length, 2);
        for (final k in store.keys) {
          await expectLater(store.readPhoto(k), throwsStateError);
        }
        expect(store.waits.length, 2, reason: 'c was never copied');
        expect(c.batchOk, isTrue);
        expect(c.keptBytes, closeTo(await store.usedBytes(), 2048));
        c.dispose();
      });
    },
  );

  testWidgets('five photos with a slow store appear at once, loading', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = SlowBatchStore();
      final c = Rig(Stores(), batch: store).controller;
      await c.init();
      await c.addPhotos([
        for (final n in ['a', 'b', 'c', 'd', 'e'])
          picked('$n.jpg', png(30, 20)),
      ]);
      expect(c.photos.length, 5);
      expect(c.photos.map((p) => p.status), everyElement(PhotoStatus.loading));
      expect(c.photos.map((p) => p.key), everyElement(isNull));
      for (var i = 0; i < 5; i++) {
        await store.release(i);
      }
      await c.whenIdle();
      expect(c.photos.map((p) => p.status), everyElement(PhotoStatus.ready));
      expect(c.photos.map((p) => p.key), everyElement(isNotNull));
      final saved = (await store.load())!;
      expect(
        [for (final p in saved.photos) p.name],
        ['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg', 'e.jpg'],
      );
      expect(store.waits.length, 5, reason: 'each photo is copied once');
      c.dispose();
    });
  });

  testWidgets('two quick adds of the same files add them once', (tester) async {
    await tester.runAsync(() async {
      final store = SlowBatchStore();
      final c = Rig(Stores(), batch: store).controller;
      await c.init();
      final files = [
        picked('a.jpg', png(30, 20)),
        picked('b.jpg', png(30, 20)),
        picked('c.jpg', png(30, 20)),
      ];
      final first = c.addPhotos(files);
      final second = c.addPhotos(files);
      await first;
      await second;
      expect(c.photos.length, 3);
      await store.release(0);
      await until(() => c.photos.first.key != null);
      await c.addPhotos(files); // one kept, two still waiting to be copied
      expect(c.photos.length, 3);
      await store.release(1);
      await store.release(2);
      await c.whenIdle();
      expect(store.waits.length, 3);
      expect((await store.load())!.photos.length, 3);
      c.dispose();
    });
  });

  testWidgets('batchOk follows puts and manifest saves, not measurements', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = FlakyBatchStore();
      final c = Rig(Stores(), batch: store).controller;
      await c.init();
      store
        ..failPut = true
        ..failMeasure = true;
      await c.addPhotos([picked('a.jpg', png(30, 20))]);
      await c.whenIdle();
      expect(c.batchOk, isFalse, reason: 'a could not be kept');
      expect(c.photos.single.status, PhotoStatus.ready);
      final before = c.keptBytes;

      store.failPut = false;
      await c.addPhotos([picked('b.jpg', png(30, 20))]);
      await c.whenIdle();
      expect(c.photos.last.key, isNotNull);
      expect(c.batchOk, isFalse, reason: 'a is still not kept');
      expect(
        c.keptBytes,
        before,
        reason: 'a failed measurement keeps the last value',
      );

      await c.removePhoto(c.photos.first.id);
      await c.whenIdle();
      expect(
        c.batchOk,
        isTrue,
        reason: 'a good manifest save with every photo kept',
      );

      store.failMeasure = false;
      await c.setLook(c.look.withPhotoPatch(c.photos.single.id, exposure(1)));
      expect(c.keptBytes, await store.usedBytes());
      expect(c.batchOk, isTrue);
      c.dispose();
    });
  });

  testWidgets('the developer can arrive after start-up', (tester) async {
    await tester.runAsync(() async {
      final load = Completer<PhotoDeveloper?>();
      final r = Rig(Stores(), developerLoad: load.future);
      final c = r.controller;
      await c.init();
      expect(c.editingAvailable, isFalse);
      expect(
        c.notices.map((n) => n.text),
        isNot(contains("Photo editing isn't available on this phone.")),
        reason: 'not while it loads',
      );
      await c.addPhotos([picked('a.png', encodePng(grey(24, 16, 90), 24, 16))]);
      await c.whenIdle();
      final p = c.photos.single;
      await c.setLook(c.look.withPhotoPatch(p.id, exposure(1)));
      await c.whenIdle();
      expect(p.developed, isNull);

      final saving = c.saveAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(r.saver.names, isEmpty, reason: 'saving waits for the developer');
      load.complete(CpuDeveloper());
      await saving;
      await c.whenIdle();
      expect(c.editingAvailable, isTrue);
      expect(p.developed, isNotNull);
      expect(
        meanLevel(r.saver.files.single),
        greaterThan(110),
        reason: 'saved with the edit',
      );
      c.dispose();

      final none = Rig(Stores(), developerLoad: Future.value(null)).controller;
      await none.init();
      await Future<void>.delayed(Duration.zero);
      expect(none.editingAvailable, isFalse);
      expect(
        none.notices.map((n) => n.text),
        contains("Photo editing isn't available on this phone."),
      );
      none.dispose();
    });
  });
}
