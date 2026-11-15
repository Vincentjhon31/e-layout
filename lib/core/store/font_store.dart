import 'dart:typed_data';

import 'font_store_memory.dart'
    if (dart.library.js_interop) 'font_store_web.dart'
    if (dart.library.io) 'font_store_io.dart' as impl;

/// One font face the person added (from a file, a layout file or the library).
class StoredFont {
  StoredFont({
    required this.family,
    required this.weight,
    required this.style,
    required this.bytes,
    this.variable = false,
    this.source = 'file',
    this.mime = 'font/ttf',
  });

  final String family;
  final int weight;

  /// 'normal' or 'italic'.
  final String style;
  final Uint8List bytes;
  final bool variable;

  /// 'file' or 'library'.
  final String source;
  final String mime;

  /// app.js: `${family}|${weight}|${style}|${variable ? 'v' : ''}`.
  String get id => '$family|$weight|$style|${variable ? 'v' : ''}';

  Map<String, dynamic> meta() => {
        'family': family,
        'weight': weight,
        'style': style,
        'variable': variable,
        'source': source,
        'mime': mime,
      };

  static StoredFont? fromMeta(Map<String, dynamic> m, Uint8List bytes) {
    final family = m['family'];
    if (family is! String || family.isEmpty) return null;
    return StoredFont(
      family: family,
      weight: m['weight'] is int ? m['weight'] as int : 400,
      style: m['style'] == 'italic' ? 'italic' : 'normal',
      variable: m['variable'] == true,
      source: m['source'] == 'library' ? 'library' : 'file',
      mime: m['mime'] is String ? m['mime'] as String : 'font/ttf',
      bytes: bytes,
    );
  }
}

/// Fonts kept on this phone between visits.
abstract class FontStore {
  /// Every stored face. A missing folder or unreadable entry gives fewer faces, never an error.
  Future<List<StoredFont>> loadAll();

  /// Adds or replaces the face with the same [StoredFont.id].
  Future<void> save(StoredFont font);

  /// Removes every face of [family].
  Future<void> removeFamily(String family);
}

/// Files under the app support folder `fonts/` on devices; memory on the web.
FontStore createFontStore() => impl.createFontStore();
