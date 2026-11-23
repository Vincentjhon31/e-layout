import 'dart:convert';
import 'dart:typed_data';

import 'batch_store.dart';

/// Keeps the batch for this visit only (tests, and platforms without storage).
class MemoryBatchStore implements BatchStore {
  final Map<String, Uint8List> _photos = {};
  String? _manifest;

  @override
  Future<BatchManifest?> load() async {
    final m = _manifest;
    return m == null ? null : BatchManifest.tryDecode(m);
  }

  @override
  Future<void> saveManifest(BatchManifest m) async => _manifest = m.encode();

  @override
  Future<String> putPhoto(String name, Uint8List bytes) async {
    final key = newPhotoKey(name);
    _photos[key] = Uint8List.fromList(bytes);
    return key;
  }

  @override
  Future<Uint8List> readPhoto(String key) async {
    final b = _photos[key];
    if (b == null) throw StateError('This photo is no longer kept.');
    return Uint8List.fromList(b);
  }

  @override
  Future<void> removePhoto(String key) async => _photos.remove(key);

  @override
  Future<void> clear() async {
    _photos.clear();
    _manifest = null;
  }

  @override
  Future<int> usedBytes() async {
    var n = _manifest == null ? 0 : utf8.encode(_manifest!).length;
    for (final b in _photos.values) {
      n += b.length;
    }
    return n;
  }
}

BatchStore createStore() => MemoryBatchStore();
