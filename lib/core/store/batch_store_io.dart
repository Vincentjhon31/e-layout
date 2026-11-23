import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'batch_store.dart';

/// `manifest.json` (written atomically) and `photos/<key>` in one folder.
class FileBatchStore implements BatchStore {
  FileBatchStore(this._dir);

  /// A store in a fixed folder (tests).
  FileBatchStore.inDirectory(Directory dir) : this(() async => dir);

  final Future<Directory> Function() _dir;

  /// Keys are file-safe by construction; anything else is made safe anyway.
  static String fileSafe(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  Future<Directory> _make(Directory d) async {
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Directory> _root() async => _make(await _dir());
  Future<Directory> _photos() async =>
      _make(Directory(p.join((await _dir()).path, 'photos')));

  Future<File> _manifestFile() async =>
      File(p.join((await _root()).path, 'manifest.json'));

  @override
  Future<BatchManifest?> load() async {
    try {
      final f = await _manifestFile();
      if (!await f.exists()) return null;
      return BatchManifest.tryDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveManifest(BatchManifest m) async {
    final target = await _manifestFile();
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(m.encode(), flush: true);
    await tmp.rename(target.path);
  }

  @override
  Future<String> putPhoto(String name, Uint8List bytes) async {
    final key = newPhotoKey(name);
    final d = await _photos();
    final target = File(p.join(d.path, fileSafe(key)));
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
    return key;
  }

  @override
  Future<Uint8List> readPhoto(String key) async {
    final d = await _photos();
    final f = File(p.join(d.path, fileSafe(key)));
    if (!await f.exists()) throw StateError('This photo is no longer kept.');
    return f.readAsBytes();
  }

  @override
  Future<void> removePhoto(String key) async {
    final d = await _photos();
    final f = File(p.join(d.path, fileSafe(key)));
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> clear() async {
    final root = await _dir();
    final photos = Directory(p.join(root.path, 'photos'));
    if (await photos.exists()) await photos.delete(recursive: true);
    final m = File(p.join(root.path, 'manifest.json'));
    if (await m.exists()) await m.delete();
  }

  @override
  Future<int> usedBytes() async {
    final root = await _dir();
    var n = 0;
    final m = File(p.join(root.path, 'manifest.json'));
    if (await m.exists()) n += await m.length();
    final photos = Directory(p.join(root.path, 'photos'));
    if (await photos.exists()) {
      await for (final e in photos.list()) {
        if (e is File) n += await e.length();
      }
    }
    return n;
  }
}

BatchStore createStore() => FileBatchStore(() async {
  final base = await getApplicationSupportDirectory();
  return Directory(p.join(base.path, 'batch'));
});
