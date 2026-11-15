import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../model/layout_codec.dart';
import '../model/layout_doc.dart';
import 'layout_store.dart';

/// One `<id>.layout.json` file per layout.
class FileLayoutStore implements LayoutStore {
  FileLayoutStore(this._dir);

  /// A store in a fixed folder (tests).
  FileLayoutStore.inDirectory(Directory dir) : this(() async => dir);

  final Future<Directory> Function() _dir;

  static String fileSafe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<Directory> _folder() async {
    final d = await _dir();
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  File _file(Directory d, String id) =>
      File(p.join(d.path, '${fileSafe(id)}.layout.json'));

  @override
  Future<List<LayoutDoc>> loadAll() async {
    final d = await _folder();
    final out = <LayoutDoc>[];
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.layout.json')) continue;
      try {
        out.add(readLayout(jsonDecode(await e.readAsString()), keepIdentity: true));
      } catch (_) {
        // A damaged file is skipped; the others still load.
      }
    }
    out.sort((a, b) => a.created.compareTo(b.created));
    return out;
  }

  @override
  Future<void> save(LayoutDoc doc) async {
    final d = await _folder();
    final target = _file(d, doc.id);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(jsonEncode(writeLayout(doc)), flush: true);
    await tmp.rename(target.path);
  }

  @override
  Future<void> remove(String id) async {
    final f = _file(await _folder(), id);
    if (await f.exists()) await f.delete();
  }
}

LayoutStore createStore() => FileLayoutStore(() async {
      final base = await getApplicationSupportDirectory();
      return Directory(p.join(base.path, 'layouts'));
    });
