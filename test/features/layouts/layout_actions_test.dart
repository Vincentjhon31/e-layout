import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/store/batch_store_memory.dart';
import 'package:pio_photo_layout/core/store/preset_store_memory.dart';
import 'package:pio_photo_layout/core/codec/png_encoder.dart';
import 'package:pio_photo_layout/core/fonts/font_registry.dart';
import 'package:pio_photo_layout/core/model/layout_codec.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/model/layout_ops.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/platform/file_sharer.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/platform/temp_files_memory.dart';
import 'package:pio_photo_layout/ui/widgets/note_box.dart';
import 'package:shared_preferences/shared_preferences.dart';

PickedPhoto file(String name, Uint8List bytes) =>
    PickedPhoto(name: name, readBytes: () async => bytes, size: bytes.length);

/// RGBA picture where [opaque] decides which pixels are solid blue.
Uint8List picture(int w, int h, bool Function(int x, int y) opaque) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!opaque(x, y)) continue;
      final i = (y * w + x) * 4;
      b[i] = 30;
      b[i + 1] = 110;
      b[i + 2] = 190;
      b[i + 3] = 255;
    }
  }
  return encodePng(b, w, h);
}

class Rig {
  final store = MemoryLayoutStore();
  final fonts = MemoryFontStore();
  final temp = MemoryTempFiles();
  final sharer = FakeFileSharer();
  late final HomeController c = HomeController(
    layoutStore: store,
    settingsStore: SettingsStore(),
    picker: FakePhotoPicker(),
    saver: FakeGallerySaver(),
    sharer: sharer,
    temp: temp,
    presetStore: MemoryPresetStore(),
    batchStore: MemoryBatchStore(),
    developer: CpuDeveloper(),
    fontStore: fonts,
  );
}

Future<Rig> rig() async {
  final r = Rig();
  await r.c.init();
  return r;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('importing a layout file: fresh id, pins upgraded, fonts adopted', (tester) async {
    await tester.runAsync(() async {
      final r = await rig();
      final raw = jsonDecode(File('assets/layouts/pio-footer.layout.json').readAsStringSync()) as Map<String, dynamic>;
      final layout = (raw['layout'] ?? raw) as Map<String, dynamic>;
      final ttf = File('assets/fonts/barlow-700.ttf').readAsBytesSync();
      layout['name'] = 'Shared footer';
      (layout['elements'] as List).addAll([
        {'type': 'text', 'text': 'A', 'font': 'Test Sans', 'weight': 700, 'pin': 'top'},
        {'type': 'text', 'text': 'B', 'font': 'Woff Two', 'weight': 400, 'pin': 'top'},
      ]);
      layout['fonts'] = {
        'Test Sans': [
          {'weight': 700, 'style': 'normal', 'mime': 'font/ttf', 'data': base64Encode(ttf)},
        ],
        'Woff Two': [
          {'weight': 400, 'style': 'normal', 'mime': 'font/woff2', 'data': base64Encode(utf8.encode('wOF2 not really'))},
        ],
      };
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(raw)));
      await r.c.importFiles([file('shared.layout.json', bytes)]);
      final item = r.c.current!;
      expect(item.doc.name, 'Shared footer');
      expect(item.builtin, isFalse);
      expect(item.doc.id, isNot(layout['id']));
      expect(item.doc.pinsVersion, 2);
      expect(item.doc.elements.every((e) => e.pinAuto == true), isTrue);
      expect(FontRegistry.instance.kind('Test Sans'), 'uploaded');
      expect((await r.fonts.loadAll()).map((f) => f.family), ['Test Sans']);
      expect(FontRegistry.instance.missing(item.doc), ['Woff Two']);
      expect(item.doc.fonts, isEmpty);
      expect(r.c.layoutNotes.first.kind, NoteKind.info);
      expect(r.c.layoutNotes.first.text, 'Added "Shared footer". Use Edit layout to adjust it.');
      expect((await r.store.loadAll()).map((d) => d.name), ['Shared footer']);
      r.c.dispose();
    });
  });

  testWidgets('a broken or newer layout file shows the web app\'s error line', (tester) async {
    await tester.runAsync(() async {
      final r = await rig();
      await r.c.importFiles([
        file('new.layout.json', Uint8List.fromList(utf8.encode('{"format":"pio-photo-layout","version":3}'))),
        file('torn.json', Uint8List.fromList(utf8.encode('{"version":2,'))),
        file('notes.txt', Uint8List.fromList([65])),
      ]);
      expect(r.c.layoutNotes.map((n) => '${n.kind.name}: ${n.text}'), [
        "error: new.layout.json: this file isn't a layout from this tool.",
        "error: torn.json: this file isn't a layout from this tool.",
        'error: notes.txt: use a layout file (.json) or a PNG, JPG or WebP picture.',
      ]);
      expect(r.c.layouts.length, 1);
      r.c.dispose();
    });
  });

  testWidgets('importing pictures: footer, frame cut into parts, opaque picture', (tester) async {
    await tester.runAsync(() async {
      final r = await rig();
      final footer = picture(600, 200, (x, y) => y >= 150);
      final frame = picture(400, 300, (x, y) => y < 40 || y >= 250 || x < 20 || x >= 380);
      final solid = picture(300, 200, (x, y) => true);
      await r.c.importFiles([file('band.png', footer)]);
      expect(r.c.current!.doc.name, 'band');
      expect(r.c.current!.doc.elements.single.pin, Pin.bottom);
      expect(r.c.layoutNotes.map((n) => n.kind), [NoteKind.info]);

      await r.c.importFiles([file('frame.png', frame)]);
      final parts = r.c.current!.doc.elements;
      expect(parts.length, 4);
      expect(r.c.current!.doc.fit, DocFit.keep);
      expect(r.c.layoutNotes[1].text,
          '"frame" covers the whole photo, so it was cut into a top part, a bottom part, a left border and a right border. Each part stays on its own edge, so photos of any shape keep their full size.');

      await r.c.importFiles([file('solid.png', solid)]);
      expect(r.c.current!.doc.fit, DocFit.crop);
      expect(r.c.layoutNotes.map((n) => n.kind), [NoteKind.info, NoteKind.warning, NoteKind.warning]);
      expect(r.c.layoutNotes[1].text,
          '"solid" covers the middle of the photo, so photos are cropped to its shape (3:2). A PNG with a see-through middle fits photos of any shape.');
      expect(r.c.layoutNotes[2].text,
          'solid.png has no transparent areas, so it covers the photo wherever it sits. A PNG with a transparent background works better.');
      r.c.dispose();
    });
  });

  testWidgets('duplicate, rename, export and remove', (tester) async {
    await tester.runAsync(() async {
      final r = await rig();
      final office = r.c.layouts.first;
      final copy = await r.c.duplicateLayout(office);
      expect(copy.doc.name, 'PIO footer (copy)');
      expect(r.c.selectedId, copy.id);

      // Renaming an office layout works on a copy; an empty name keeps the old one.
      await r.c.renameLayout(office, 'Mine');
      expect(office.doc.name, 'PIO footer');
      expect(r.c.current!.doc.name, 'Mine');
      await r.c.renameLayout(r.c.current!, '   ');
      expect(r.c.current!.doc.name, 'Mine');

      await r.c.exportLayout(r.c.current!);
      final path = r.sharer.shared.single.single;
      expect(path, endsWith('Mine.layout.json'));
      final written = r.temp.groups['export']!['Mine.layout.json']!;
      final json = jsonDecode(utf8.decode(written)) as Map<String, dynamic>;
      expect(json['format'], 'pio-photo-layout');
      expect(readLayout(json).name, 'Mine');

      final mine = r.c.current!;
      await r.c.removeLayout(mine);
      expect(r.c.layouts.contains(mine), isFalse);
      expect((await r.store.loadAll()).map((d) => d.name), ['PIO footer (copy)']);
      expect(r.c.selectedId, office.id);
      await r.c.removeLayout(office); // office layouts stay
      expect(r.c.layouts.contains(office), isTrue);
      r.c.dispose();
    });
  });

  testWidgets('"Fit every photo shape" cuts a frame picture into edge parts', (tester) async {
    await tester.runAsync(() async {
      final r = await rig();
      final frame = picture(400, 300, (x, y) => y < 40 || y >= 250 || x < 20 || x >= 380);
      final doc = fromImage('Frame', LayoutAsset(name: 'Frame', mime: 'image/png', bytes: frame, w: 400, h: 300), 'frame');
      final item = await r.c.addLayout(doc);
      await r.c.selectLayout(item.id);
      final notice = r.c.notices.singleWhere((n) => n.actionLabel == 'Fit every photo shape');
      await notice.action!();
      expect(item.doc.fit, DocFit.keep);
      expect(item.doc.elements.length, 4);
      expect(item.doc.assets.length, lessThanOrEqualTo(4));
      expect(r.c.notices.any((n) => n.actionLabel != null), isFalse);
      r.c.dispose();
    });
  });
}
