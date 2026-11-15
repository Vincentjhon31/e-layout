import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Registers every bundled font family, like the app does at start-up.
Future<void> loadBundledFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final fam in manifest) {
    final name = (fam as Map)['family'] as String;
    if (name.startsWith('packages/')) continue;
    final loader = FontLoader(name);
    for (final f in fam['fonts'] as List) {
      loader.addFont(rootBundle.load((f as Map)['asset'] as String));
    }
    await loader.load();
  }
}

/// Draws into a w x h picture and returns straight RGBA bytes.
Future<Uint8List> rasterize(int w, int h, void Function(ui.Canvas) draw) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  draw(c);
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  img.dispose();
  pic.dispose();
  return bd!.buffer.asUint8List();
}

List<int> pixelAt(Uint8List rgba, int w, int x, int y) {
  final i = (y * w + x) * 4;
  return [rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]];
}
