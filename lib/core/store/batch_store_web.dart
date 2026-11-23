import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'batch_store.dart';
import 'idb_web.dart';

/// The batch in the browser's IndexedDB. Keys are `manifest` (JSON text) and
/// `photo:<key>` (the bytes as a `Uint8Array`), with a
/// `size:<key>` record of its length.
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
    await _box.put('size:$key', bytes.length.toJS);
    return key;
  }

  @override
  Future<Uint8List> readPhoto(String key) async {
    final v = await _box.get('photo:$key');
    if (v == null) throw StateError('This photo is no longer kept.');
    return (v as JSUint8Array).toDart;
  }

  @override
  Future<void> removePhoto(String key) async {
    await _box.delete('photo:$key');
    await _box.delete('size:$key');
  }

  @override
  Future<void> clear() async {
    for (final k in await _box.keys()) {
      await _box.delete(k);
    }
  }

  /// Sums the size records, so no photo bytes are loaded. A photo kept
  /// before size records existed is read once and gets one.
  @override
  Future<int> usedBytes() async {
    final keys = await _box.keys();
    final have = keys.toSet();
    var n = 0;
    for (final k in keys) {
      if (k.startsWith('size:')) {
        final v = await _box.get(k);
        if (v != null) n += (v as JSNumber).toDartInt;
      } else if (k == 'manifest') {
        final v = await _box.get(k);
        if (v != null) n += utf8.encode((v as JSString).toDart).length;
      } else if (k.startsWith('photo:') && !have.contains('size:${k.substring(6)}')) {
        final v = await _box.get(k);
        if (v != null) {
          final len = (v as JSUint8Array).toDart.length;
          await _box.put('size:${k.substring(6)}', len.toJS);
          n += len;
        }
      }
    }
    return n;
  }
}

BatchStore createStore() => IdbBatchStore();
