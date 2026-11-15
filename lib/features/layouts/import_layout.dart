import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/analysis/frame_split.dart';
import '../../core/fonts/font_registry.dart';
import '../../core/model/layout_codec.dart';
import '../../core/model/layout_doc.dart';
import '../../core/model/layout_ops.dart';
import '../../core/render/layout_prep.dart';
import '../../core/store/font_store.dart';
import '../../ui/widgets/note_box.dart';
import '../home/home_controller.dart' show Notice, ratioText;

/// Thrown with the web app's wording; shown after the file name.
class ImportProblem implements Exception {
  const ImportProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

final RegExp _jsonName = RegExp(r'\.json$', caseSensitive: false);
final RegExp _pictureName = RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false);

bool isLayoutFileName(String name) => _jsonName.hasMatch(name);
bool isPictureFileName(String name) => _pictureName.hasMatch(name);

String _mimeOf(String name) {
  final ext = name.split('.').last.toLowerCase();
  return ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
}

/// app.js safeFileName().
String safeFileName(String name) {
  final s = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  return s.isEmpty ? 'layout' : s;
}

/// A layout file's bytes to a layout (fresh id, pins upgraded).
LayoutDoc readLayoutBytes(Uint8List bytes) {
  Object? raw;
  try {
    raw = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    throw const ImportProblem("this file isn't a layout from this tool.");
  }
  try {
    final doc = readLayout(raw);
    upgradePins(doc);
    return doc;
  } on LayoutFormatException {
    throw const ImportProblem("this file isn't a layout from this tool.");
  }
}

/// Whether Flutter can load these font bytes on a phone (TTF or OTF).
bool isLoadableFont(Uint8List b) {
  if (b.length < 4) return false;
  final tag = String.fromCharCodes(b.sublist(0, 4));
  return tag == 'OTTO' || tag == 'true' || (b[0] == 0 && b[1] == 1 && b[2] == 0 && b[3] == 0);
}

/// Converts font bytes into something a phone can load, or null (WOFF2).
typedef FontConverter = Uint8List? Function(Uint8List bytes);

/// app.js adoptDocFonts(): fonts packed in a layout file join this phone's
/// fonts. Faces that cannot be loaded here are skipped, so their families
/// show up as missing fonts.
Future<void> adoptDocFonts(LayoutDoc doc, FontStore store, {FontConverter? convert}) async {
  for (final e in doc.fonts.entries) {
    for (final f in e.value) {
      try {
        var bytes = f.bytes;
        if (!isLoadableFont(bytes)) {
          final converted = convert?.call(bytes);
          if (converted == null) continue;
          bytes = converted;
        }
        await FontRegistry.instance.register(e.key, f.weight, f.style, bytes, variable: f.variable);
        await store.save(StoredFont(
            family: e.key, weight: f.weight, style: f.style, bytes: bytes, variable: f.variable));
      } catch (err) {
        debugPrint('Font ${e.key} in the layout file could not be used: $err');
      }
    }
  }
  doc.fonts = {};
}

/// app.js describeParts().
String describeParts(List<FramePartRect> parts) {
  const names = {'top': 'a top part', 'bottom': 'a bottom part', 'left': 'a left border', 'right': 'a right border'};
  final list = [for (final p in parts) names[p.edge]!];
  if (list.length < 2) return list.first;
  return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
}

/// A layout made from a picture, with the web app's notes (app.js importFiles).
Future<(LayoutDoc, List<Notice>)> layoutFromPicture(String fileName, Uint8List bytes) async {
  final notes = <Notice>[];
  final bmp = await decodeImageBytes(bytes);
  try {
    final guess = await analyseAlpha(bmp);
    final stem = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final name = stem.isEmpty ? 'Imported layout' : stem;
    final split = guess.placement == 'frame' && guess.hasAlpha ? await splitFrame(bmp) : null;
    LayoutDoc doc;
    if (split != null) {
      doc = fromParts(name, await cutParts(bmp, split), split.W, split.H);
      notes.add(Notice(NoteKind.info,
          '"$name" covers the whole photo, so it was cut into ${describeParts(split.parts)}. Each part stays on its own edge, so photos of any shape keep their full size.'));
    } else {
      doc = fromImage(
          name,
          LayoutAsset(name: name, mime: _mimeOf(fileName), bytes: bytes, w: bmp.width, h: bmp.height),
          guess.placement);
      if (guess.placement == 'frame') {
        notes.add(Notice(NoteKind.warning,
            '"$name" covers the middle of the photo, so photos are cropped to its shape (${ratioText(bmp.width / bmp.height)}). A PNG with a see-through middle fits photos of any shape.'));
      }
    }
    if (!guess.hasAlpha) {
      notes.add(Notice(NoteKind.warning,
          '$fileName has no transparent areas, so it covers the photo wherever it sits. A PNG with a transparent background works better.'));
    }
    return (doc, notes);
  } finally {
    bmp.dispose();
  }
}
