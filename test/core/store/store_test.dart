import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/export/photo_exporter.dart';
import 'package:pio_photo_layout/core/model/layout_codec.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/model/layout_ops.dart';
import 'package:pio_photo_layout/core/store/bundled_layouts.dart';
import 'package:pio_photo_layout/core/store/layout_store_io.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('file store: save, reload in created order, remove, skip corrupt', () async {
    final dir = Directory.systemTemp.createTempSync('pio_store_');
    try {
      final store = FileLayoutStore.inDirectory(dir);
      final a = LayoutDoc.blank('First')..created = 2000;
      final b = fromImage(
          'Second',
          LayoutAsset(
              name: 'x',
              mime: 'image/png',
              bytes: base64Decode(_onePixelPng),
              w: 1,
              h: 1),
          'footer')
        ..created = 1000;
      await store.save(a);
      await store.save(b);
      File('${dir.path}/broken.layout.json').writeAsStringSync('{not json');
      File('${dir.path}/other.txt').writeAsStringSync('x');
      final back = await store.loadAll();
      expect(back.map((d) => d.name).toList(), ['Second', 'First']);
      expect(jsonEncode(writeLayout(back[0])), jsonEncode(writeLayout(b)));
      expect(jsonEncode(writeLayout(back[1])), jsonEncode(writeLayout(a)));
      expect(dir.listSync().any((f) => f.path.endsWith('.tmp')), isFalse);
      await store.remove(a.id);
      expect((await store.loadAll()).length, 1);
      expect(dir.listSync().where((f) => f.path.contains(a.id)), isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('memory store round trip', () async {
    final s = MemoryLayoutStore();
    final a = LayoutDoc.blank('M');
    await s.save(a);
    expect((await s.loadAll()).single.id, a.id);
    await s.remove(a.id);
    expect(await s.loadAll(), isEmpty);
  });

  test('bundled layouts', () async {
    final list = await loadBundledLayouts();
    expect(list.length, 1);
    expect(list.single.id, 'office:pio-footer');
    expect(list.single.pinsVersion, 2);
    expect(list.single.elements.every((e) => e.pinAuto == true), isTrue);
  });

  test('settings round trip and defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    final d = await store.load();
    expect([d.layoutId, d.format, d.quality, d.suffix],
        [null, OutputFormat.jpeg, 92, '_PIO']);
    await store.save(AppSettings(
        layoutId: 'office:pio-footer',
        format: OutputFormat.png,
        quality: 80,
        suffix: '_X'));
    final r = await store.load();
    expect([r.layoutId, r.format, r.quality, r.suffix],
        ['office:pio-footer', OutputFormat.png, 80, '_X']);
  });
}
