import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'font_store.dart';

/// One `<key>.font` file per face plus a `<key>.json` with its details.
class FileFontStore implements FontStore {
  FileFontStore() : _fixed = null;

  /// For tests: keep the fonts in [dir].
  FileFontStore.inDirectory(Directory dir) : _fixed = dir;

  final Directory? _fixed;

  Future<Directory> _dir() async =>
      _fixed ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'fonts'));

  static String _key(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  @override
  Future<List<StoredFont>> loadAll() async {
    final dir = await _dir();
    if (!await dir.exists()) return [];
    final out = <StoredFont>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final meta = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
        final bytes = await File('${e.path.substring(0, e.path.length - 5)}.font').readAsBytes();
        final f = StoredFont.fromMeta(meta, bytes);
        if (f != null) out.add(f);
      } catch (_) {
        // An unreadable entry is skipped.
      }
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  @override
  Future<void> save(StoredFont font) async {
    final dir = await _dir();
    await dir.create(recursive: true);
    final base = p.join(dir.path, _key(font.id));
    await File('$base.font.tmp').writeAsBytes(font.bytes, flush: true);
    await File('$base.font.tmp').rename('$base.font');
    await File('$base.json').writeAsString(jsonEncode(font.meta()), flush: true);
  }

  @override
  Future<void> removeFamily(String family) async {
    final dir = await _dir();
    if (!await dir.exists()) return;
    for (final f in await loadAll()) {
      if (f.family != family) continue;
      final base = p.join(dir.path, _key(f.id));
      for (final path in ['$base.json', '$base.font']) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }
}

FontStore createFontStore() => FileFontStore();
