import '../model/layout_codec.dart';
import '../model/layout_doc.dart';
import 'layout_store.dart';

/// Keeps layouts for this visit only (used on the web and in tests).
class MemoryLayoutStore implements LayoutStore {
  final Map<String, Map<String, dynamic>> _items = {};

  @override
  Future<List<LayoutDoc>> loadAll() async {
    final out = <LayoutDoc>[];
    for (final j in _items.values) {
      try {
        out.add(readLayout(j, keepIdentity: true));
      } catch (_) {}
    }
    out.sort((a, b) => a.created.compareTo(b.created));
    return out;
  }

  @override
  Future<void> save(LayoutDoc doc) async => _items[doc.id] = writeLayout(doc);

  @override
  Future<void> remove(String id) async => _items.remove(id);
}

LayoutStore createStore() => MemoryLayoutStore();
