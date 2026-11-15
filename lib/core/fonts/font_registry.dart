import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/layout_doc.dart';

class FontFamilyInfo {
  const FontFamilyInfo(this.family, this.weights, this.group);
  final String family;
  final List<int> weights;
  final String group;
}

class _Face {
  _Face(this.weight, this.style, this.mime, this.bytes, this.variable, this.source);
  final int weight;
  final String style;
  final String mime;
  final Uint8List bytes;
  final bool variable;
  final String source;
}

/// A family the person added, for the "Your fonts" list.
class AddedFont {
  const AddedFont(this.family, this.source, this.styles, this.weights);
  final String family;

  /// 'library' or 'file'.
  final String source;
  final int styles;
  final List<int> weights;
}

/// Bundled families (js/fonts.js BUILT_IN), fonts the person added, and the
/// check for fonts a layout needs that this device does not have.
class FontRegistry {
  FontRegistry._();
  static final FontRegistry instance = FontRegistry._();

  static const List<FontFamilyInfo> _builtIn = [
    FontFamilyInfo('Barlow', [400, 500, 600, 700, 800], 'Sans serif'),
    FontFamilyInfo('Barlow Condensed', [400, 600, 800], 'Sans serif'),
    FontFamilyInfo('Montserrat', [400, 700, 800], 'Sans serif'),
    FontFamilyInfo('Poppins', [400, 600, 800], 'Sans serif'),
    FontFamilyInfo('Open Sans', [400, 700, 800], 'Sans serif'),
    FontFamilyInfo('Fira Sans Condensed', [400, 600, 800], 'Sans serif'),
    FontFamilyInfo('Nunito', [400, 800], 'Sans serif'),
    FontFamilyInfo('Oswald', [400, 600], 'Headline'),
    FontFamilyInfo('Anton', [400], 'Headline'),
    FontFamilyInfo('Bebas Neue', [400], 'Headline'),
    FontFamilyInfo('Playfair Display', [400, 700, 900], 'Serif'),
    FontFamilyInfo('Libre Baskerville', [400, 700], 'Serif'),
    FontFamilyInfo('Cinzel', [400, 700], 'Serif'),
    FontFamilyInfo('Dancing Script', [400, 700], 'Script'),
    FontFamilyInfo('Great Vibes', [400], 'Script'),
    FontFamilyInfo('Pacifico', [400], 'Script'),
  ];

  final Map<String, List<_Face>> _added = {};

  List<FontFamilyInfo> get builtIn => _builtIn;

  FontFamilyInfo? _builtInOf(String family) {
    for (final f in _builtIn) {
      if (f.family == family) return f;
    }
    return null;
  }

  /// 'built-in', 'uploaded' or 'unknown'.
  String kind(String family) {
    if (_builtInOf(family) != null) return 'built-in';
    if (_added.containsKey(family)) return 'uploaded';
    return 'unknown';
  }

  bool isVariable(String family) => (_added[family] ?? const <_Face>[]).any((f) => f.variable);

  List<int> weightsFor(String family) {
    final b = _builtInOf(family);
    final faces = _added[family] ?? const <_Face>[];
    final mine = faces.any((f) => f.variable)
        ? [100, 200, 300, 400, 500, 600, 700, 800, 900]
        : [for (final f in faces) f.weight];
    if (b == null && mine.isEmpty) return [400, 700];
    return {...?b?.weights, ...mine}.toList()..sort();
  }

  /// The available weight closest to [weight]; on a tie the lower one wins.
  int nearestWeight(String family, int weight) {
    final ws = weightsFor(family);
    return ws.reduce((best, w) => (w - weight).abs() < (best - weight).abs() ? w : best);
  }

  Future<void> register(
    String family,
    int weight,
    String style,
    Uint8List bytes, {
    bool variable = false,
    String source = 'file',
  }) async {
    await ui.loadFontFromList(bytes, fontFamily: family);
    final list = _added.putIfAbsent(family, () => []);
    list.removeWhere((f) => f.weight == weight && f.style == style && f.variable == variable);
    list.add(_Face(weight, style, _sniff(bytes), bytes, variable, source));
  }

  static String _sniff(Uint8List b) {
    if (b.length >= 4) {
      final s = String.fromCharCodes(b.sublist(0, 4));
      if (s == 'OTTO') return 'font/otf';
      if (s == 'wOFF') return 'font/woff';
      if (s == 'wOF2') return 'font/woff2';
    }
    return 'font/ttf';
  }

  /// Fonts the person added, A to Z (js/fonts.js `added`).
  List<AddedFont> added() {
    final out = [
      for (final e in _added.entries)
        AddedFont(e.key, e.value.any((f) => f.source == 'library') ? 'library' : 'file', e.value.length, [
          for (final w in weightsFor(e.key))
            if (e.value.any((f) => f.variable || f.weight == w)) w,
        ]),
    ];
    out.sort((a, b) => a.family.toLowerCase().compareTo(b.family.toLowerCase()));
    return out;
  }

  /// Forgets an added family. Flutter cannot unload a font that is already
  /// loaded, so text keeps drawing with it until the app restarts, but it
  /// no longer shows in lists and counts as missing for layouts.
  void unregister(String family) => _added.remove(family);

  /// Families used by text pieces that are neither built-in nor registered.
  List<String> missing(LayoutDoc doc) {
    final out = <String>{};
    for (final el in doc.elements) {
      if (el.type != ElementType.text) continue;
      if (kind(el.font) == 'unknown') out.add(el.font);
    }
    return out.toList();
  }

  /// Added fonts that the layout uses, packed for a layout file.
  Map<String, List<EmbeddedFont>> embedFor(LayoutDoc doc) {
    final out = <String, List<EmbeddedFont>>{};
    for (final el in doc.elements) {
      if (el.type != ElementType.text || !_added.containsKey(el.font) || out.containsKey(el.font)) {
        continue;
      }
      out[el.font] = [
        for (final f in _added[el.font]!)
          EmbeddedFont(weight: f.weight, style: f.style, mime: f.mime, variable: f.variable, bytes: f.bytes),
      ];
    }
    return out;
  }
}
