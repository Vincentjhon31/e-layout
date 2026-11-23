import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'batch_store.dart';
import 'idb_web.dart';

/// The batch in the browser's IndexedDB. Keys are `manifest` (JSON text) and
/// `photo:<key>` (the bytes as a `Uint8Array`).
class IdbBatchStore implements BatchStore {
  IdbBatchStore([String name = 'e-layout-batch']) : _box = IdbBox(name);

  final IdbBox _box;

  @override
  Future<BatchManifest?> load() async {
    try {
      final v = await _box.get('manifest');
      return v == null ? null : BatchManifest.tryDecode((v as JSString).toDart);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveManifest(BatchManifest m) =>
      _box.put('manifest', m.encode().toJS);

  @override
  Future<String> putPhoto(String name, Uint8List bytes) async {
    final key = newPhotoKey(name);
    // Copy, so the stored data is not a view on the caller's buffer.
    await _box.put('photo:$key', Uint8List.fromList(bytes).toJS);
    return key;
  }

  @override
  Future<Uint8List> readPhoto(String key) async {
    final v = await _box.get('photo:$key');
    if (v == null) throw StateError('This photo is no longer kept.');
    return (v as JSUint8Array).toDart;
  }

  @override
  Future<void> removePhoto(String key) => _box.delete('photo:$key');

  @override
  Future<void> clear() async {
    for (final k in await _box.keys()) {
      await _box.delete(k);
    }
  }

  @override
  Future<int> usedBytes() async {
    final keys = await _box.keys();
    final values = await _box.values();
    var n = 0;
    for (var i = 0; i < keys.length && i < values.length; i++) {
      final v = values[i];
      if (keys[i].startsWith('photo:') && v != null) {
        n += (v as JSUint8Array).toDart.length;
      } else if (keys[i] == 'manifest' && v != null) {
        n += utf8.encode((v as JSString).toDart).length;
      }
    }
    return n;
  }
}

BatchStore createStore() => IdbBatchStore();
