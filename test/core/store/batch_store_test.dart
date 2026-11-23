import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/batch_look.dart';
import 'package:pio_photo_layout/core/store/batch_store.dart';
import 'package:pio_photo_layout/core/store/batch_store_io.dart';
import 'package:pio_photo_layout/core/store/batch_store_memory.dart';

void contract(String label, BatchStore Function() make) {
  group(label, () {
    test('put, read and remove a photo', () async {
      final s = make();
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final key = await s.putPhoto('Holiday.JPG', bytes);
      expect(key, matches(RegExp(r'^[0-9a-f]{16}\.jpg$')));
      expect(await s.readPhoto(key), bytes);
      await s.removePhoto(key);
      expect(() => s.readPhoto(key), throwsStateError);
    });

    test('unusual extensions give a bare key', () async {
      final s = make();
      expect(
        await s.putPhoto('a.verylongext', Uint8List(1)),
        matches(RegExp(r'^[0-9a-f]{16}$')),
      );
      expect(
        await s.putPhoto('noext', Uint8List(1)),
        matches(RegExp(r'^[0-9a-f]{16}$')),
      );
      expect(
        await s.putPhoto('a.j-g', Uint8List(1)),
        matches(RegExp(r'^[0-9a-f]{16}$')),
      );
    });

    test('keys are fresh', () async {
      final s = make();
      final a = await s.putPhoto('a.png', Uint8List(1));
      final b = await s.putPhoto('a.png', Uint8List(1));
      expect(a, isNot(b));
    });

    test('manifest round trip', () async {
      final s = make();
      expect(await s.load(), isNull);
      final when = DateTime.utc(2026, 1, 2, 3);
      await s.saveManifest(
        BatchManifest(
          photos: [
            BatchPhoto(
              id: 1,
              name: 'a.jpg',
              key: 'k1.jpg',
              size: 4,
              modified: when,
            ),
            const BatchPhoto(id: 2, name: 'b.jpg', key: 'k2.jpg'),
          ],
          look: const BatchLook().withPresetForAll(null, null),
        ),
      );
      final m = (await s.load())!;
      expect(m.photos.length, 2);
      expect(m.photos[0].name, 'a.jpg');
      expect(m.photos[0].key, 'k1.jpg');
      expect(m.photos[0].size, 4);
      expect(m.photos[0].modified, when);
      expect(m.photos[1].size, isNull);
      expect(m.photos[1].modified, isNull);
    });

    test('a manifest naming a missing photo still loads', () async {
      final s = make();
      await s.saveManifest(
        BatchManifest(
          photos: const [BatchPhoto(id: 1, name: 'a', key: 'gone.jpg')],
          look: const BatchLook(),
        ),
      );
      expect((await s.load())!.photos.single.key, 'gone.jpg');
      expect(() => s.readPhoto('gone.jpg'), throwsStateError);
    });

    test('usedBytes follows puts and removes', () async {
      final s = make();
      final a = await s.putPhoto('a.jpg', Uint8List(100));
      final b = await s.putPhoto('b.jpg', Uint8List(40));
      expect(await s.usedBytes(), 140);
      await s.removePhoto(a);
      expect(await s.usedBytes(), 40);
      await s.removePhoto(b);
      expect(await s.usedBytes(), 0);
    });

    test('usedBytes counts photos and manifest; clear empties all', () async {
      final s = make();
      expect(await s.usedBytes(), 0);
      await s.putPhoto('a.jpg', Uint8List(100));
      final photosOnly = await s.usedBytes();
      expect(photosOnly, greaterThanOrEqualTo(100));
      await s.saveManifest(
        BatchManifest(photos: const [], look: const BatchLook()),
      );
      expect(await s.usedBytes(), greaterThan(photosOnly));
      await s.clear();
      expect(await s.usedBytes(), 0);
      expect(await s.load(), isNull);
    });
  });
}

void main() {
  contract('memory store', () => MemoryBatchStore());

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pio_batch_'));
  tearDown(() => dir.deleteSync(recursive: true));
  contract('file store', () {
    final d = Directory('${dir.path}/${DateTime.now().microsecondsSinceEpoch}');
    return FileBatchStore.inDirectory(d);
  });

  test('file store: damaged manifest loads as null', () async {
    final s = FileBatchStore.inDirectory(dir);
    await s.saveManifest(
      BatchManifest(photos: const [], look: const BatchLook()),
    );
    File('${dir.path}/manifest.json').writeAsStringSync('{ nope');
    expect(await s.load(), isNull);
  });

  test('memory store copies bytes in and out', () async {
    final s = MemoryBatchStore();
    final b = Uint8List.fromList([1, 2, 3]);
    final k = await s.putPhoto('a.jpg', b);
    b[0] = 9;
    final r = await s.readPhoto(k);
    expect(r[0], 1);
    r[1] = 9;
    expect((await s.readPhoto(k))[1], 2);
  });

  test('file store keeps photos under photos/', () async {
    final s = FileBatchStore.inDirectory(dir);
    final k = await s.putPhoto('a.png', Uint8List.fromList([5]));
    expect(File('${dir.path}/photos/$k').existsSync(), isTrue);
  });
}
