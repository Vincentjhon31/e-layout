import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../model/layout_doc.dart';

/// The decoded pictures of a layout, by asset id. An asset that could not be
/// decoded is left out; the piece that uses it then draws nothing.
class LayoutPrep {
  LayoutPrep([Map<String, ui.Image>? bitmaps]) : bitmaps = bitmaps ?? {};
  final Map<String, ui.Image> bitmaps;

  void dispose() {
    for (final i in bitmaps.values) {
      i.dispose();
    }
    bitmaps.clear();
  }
}

Future<ui.Image> decodeImageBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

Future<LayoutPrep> prepareLayout(LayoutDoc doc) async {
  final prep = LayoutPrep();
  for (final e in doc.assets.entries) {
    try {
      prep.bitmaps[e.key] = await decodeImageBytes(e.value.bytes);
    } catch (err) {
      debugPrint('Picture "${e.value.name}" could not be read: $err');
    }
  }
  return prep;
}
