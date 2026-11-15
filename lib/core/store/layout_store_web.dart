import 'dart:convert';
import 'dart:js_interop';

import '../model/layout_codec.dart';
import '../model/layout_doc.dart';
import 'idb_web.dart';
import 'layout_store.dart';

/// Layouts in the browser's IndexedDB, so they are still there after a reload.
/// Each value is the layout's JSON text.
class IdbLayoutStore implements LayoutStore {
  IdbLayoutStore([String name = 'e-layout-layouts']) : _box = IdbBox(name);

  final IdbBox _box;

  @override
  Future<List<LayoutDoc>> loadAll() async {
    final out = <LayoutDoc>[];
    for (final v in await _box.values()) {
      try {
        out.add(readLayout(jsonDecode((v as JSString).toDart), keepIdentity: true));
      } catch (_) {
        // A damaged entry is skipped; the others still load.
      }
    }
    out.sort((a, b) => a.created.compareTo(b.created));
    return out;
  }

  @override
  Future<void> save(LayoutDoc doc) => _box.put(doc.id, jsonEncode(writeLayout(doc)).toJS);

  @override
  Future<void> remove(String id) => _box.delete(id);
}

LayoutStore createStore() => IdbLayoutStore();
