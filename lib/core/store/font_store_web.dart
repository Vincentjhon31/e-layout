import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'font_store.dart';
import 'idb_web.dart';

/// Added fonts in the browser's IndexedDB: one `{meta, bytes}` object per face.
class IdbFontStore implements FontStore {
  IdbFontStore([String name = 'e-layout-fonts']) : _box = IdbBox(name);

  final IdbBox _box;

  @override
  Future<List<StoredFont>> loadAll() async {
    final out = <StoredFont>[];
    for (final v in await _box.values()) {
      try {
        final o = v as JSObject;
        final meta = jsonDecode((o.getProperty('meta'.toJS) as JSString).toDart) as Map<String, dynamic>;
        final bytes = (o.getProperty('bytes'.toJS) as JSUint8Array).toDart;
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
  Future<void> save(StoredFont font) {
    final o = JSObject()
      ..setProperty('meta'.toJS, jsonEncode(font.meta()).toJS)
      ..setProperty('bytes'.toJS, font.bytes.toJS);
    return _box.put(font.id, o);
  }

  @override
  Future<void> removeFamily(String family) async {
    for (final f in await loadAll()) {
      if (f.family == family) await _box.delete(f.id);
    }
  }
}

FontStore createFontStore() => IdbFontStore();
