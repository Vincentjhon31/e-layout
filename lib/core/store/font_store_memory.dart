import 'font_store.dart';

/// Keeps fonts for this visit only (web and tests).
class MemoryFontStore implements FontStore {
  final Map<String, StoredFont> _items = {};

  @override
  Future<List<StoredFont>> loadAll() async => _items.values.toList();

  @override
  Future<void> save(StoredFont font) async => _items[font.id] = font;

  @override
  Future<void> removeFamily(String family) async => _items.removeWhere((_, f) => f.family == family);
}

FontStore createFontStore() => MemoryFontStore();
