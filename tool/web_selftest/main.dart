// A small web page that checks the browser storage and times saving one big
// photo. Build and run it with tool/web_selftest/run.py (see the README); the
// answer is written into the page as a line starting with "RESULT", which is
// also the page title. Not part of the app.
//
//   ?phase=save   saves a layout and a font in IndexedDB, then reads them back,
//                 then times one 4000x3000 photo with the PIO footer.
//   ?phase=load   (a second run with the same --user-data-dir) reads them back.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pio_photo_layout/core/export/photo_exporter.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/render/layout_prep.dart';
import 'package:pio_photo_layout/core/render/sample_scene.dart';
import 'package:pio_photo_layout/core/store/bundled_layouts.dart';
import 'package:pio_photo_layout/core/store/font_store.dart';
import 'package:pio_photo_layout/core/store/layout_store.dart';
import 'package:web/web.dart' as web;

const String _fontFamily = 'SelfTestFont';

Uint8List _fontBytes() => Uint8List.fromList([for (var i = 0; i < 2000; i++) (i * 7) & 255]);

void _say(String line) {
  var pre = web.document.getElementById('result') as web.HTMLElement?;
  if (pre == null) {
    pre = web.document.createElement('pre') as web.HTMLElement;
    pre.id = 'result';
    web.document.body!.append(pre);
  }
  pre.textContent = line;
  web.document.title = line; // also readable from Chrome's page list (see tool/web_selftest/run.py)
}

Future<String> _check(LayoutStore layouts, FontStore fonts) async {
  final out = <String>[];
  final all = await layouts.loadAll();
  final mine = all.where((d) => d.name == 'Selftest layout').toList();
  out.add('layouts=${all.length} selftest=${mine.length}');
  final faces = (await fonts.loadAll()).where((f) => f.family == _fontFamily).toList();
  final bytesOk = faces.length == 1 && _same(faces.first.bytes, _fontBytes());
  out.add('fonts=${faces.length} bytesOk=$bytesOk');
  final good = mine.length == 1 && bytesOk;
  return '${good ? 'OK' : 'FAIL'} ${out.join(' ')}';
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final phase = Uri.base.queryParameters['phase'] ?? 'save';
  try {
    final layouts = createLayoutStore();
    final fonts = createFontStore();
    if (phase == 'save') {
      await layouts.save(LayoutDoc.blank('Selftest layout'));
      await fonts.save(StoredFont(family: _fontFamily, weight: 400, style: 'normal', bytes: _fontBytes()));
      final stored = await _check(layouts, fonts);
      _say('RESULT phase=save $stored (timing the photo...)');

      // One 4000x3000 photo with the PIO footer.
      const w = 4000, h = 3000;
      final rec = ui.PictureRecorder();
      paintSampleScene(ui.Canvas(rec), const ui.Size(w * 1.0, h * 1.0));
      final image = await rec.endRecording().toImage(w, h);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      image.dispose();
      _say('RESULT phase=save $stored (photo made, loading the layout...)');
      final doc = (await loadBundledLayouts()).first;
      final prep = await prepareLayout(doc);
      final watch = Stopwatch()..start();
      final photo = await PhotoExporter().render(png, doc, prep, const ExportSettings());
      watch.stop();
      _say('RESULT phase=save $stored render_ms=${watch.elapsedMilliseconds} out=${photo.width}x${photo.height} bytes=${photo.bytes.length}');
    } else {
      final checked = await _check(layouts, fonts);
      _say('RESULT phase=load $checked');
    }
  } catch (e, st) {
    _say('RESULT FAIL phase=$phase error=$e ${st.toString().split('\n').take(3).join(' | ')}');
  }
}
