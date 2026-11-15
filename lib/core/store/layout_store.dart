import '../model/layout_doc.dart';
import 'layout_store_memory.dart'
    if (dart.library.js_interop) 'layout_store_web.dart'
    if (dart.library.io) 'layout_store_io.dart' as impl;

/// Where the layouts people made are kept between visits.
abstract class LayoutStore {
  /// Every stored layout, oldest first. Unreadable entries are skipped.
  Future<List<LayoutDoc>> loadAll();
  Future<void> save(LayoutDoc doc);
  Future<void> remove(String id);
}

/// Files under the app support folder `layouts/` on devices; memory on the web.
LayoutStore createLayoutStore() => impl.createStore();
