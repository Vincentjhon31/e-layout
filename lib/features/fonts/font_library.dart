import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// js/fontlib.js CATEGORIES (Fontsource category to the words shown).
const Map<String, String> kFontCategories = {
  'sans-serif': 'Sans serif',
  'serif': 'Serif',
  'display': 'Display',
  'handwriting': 'Handwriting',
  'monospace': 'Monospace',
  'other': 'Other',
};

/// Shown first when nothing is typed: fonts people tend to look for.
const List<String> kPopularFonts = [
  'Roboto', 'Open Sans', 'Montserrat', 'Lato', 'Poppins', 'Inter', 'Oswald', 'Raleway', 'Nunito',
  'Playfair Display', 'Merriweather', 'Rubik', 'Work Sans', 'Bebas Neue', 'Anton', 'Lobster', 'Pacifico',
  'Dancing Script', 'Great Vibes', 'Caveat', 'Kaushan Script', 'Satisfy', 'Righteous', 'Abril Fatface',
  'Alfa Slab One', 'Archivo Black', 'DM Sans', 'Manrope', 'Quicksand', 'Josefin Sans', 'Fredoka', 'Comfortaa',
  'Lora', 'EB Garamond', 'Cormorant Garamond', 'Teko', 'Permanent Marker', 'Amatic SC', 'Sacramento', 'Allura',
  'Parisienne', 'Alex Brush', 'League Spartan', 'Kanit', 'Prompt', 'Archivo', 'Roboto Slab', 'Bitter', 'Arvo',
  'Libre Franklin', //
];

/// How many fonts one page of the list shows.
const int kFontPage = 60;

/// One font of the free library.
class LibraryFont {
  const LibraryFont({
    required this.id,
    required this.family,
    required this.category,
    required this.weights,
    required this.italic,
    required this.license,
  });

  final String id;
  final String family;

  /// A key of [kFontCategories].
  final String category;
  final List<int> weights;
  final bool italic;
  final String license;

  String get categoryLabel => kFontCategories[category]!;

  /// The faces that get downloaded: every weight, plus italic for 400 and 700.
  List<(int weight, String style)> get faces => [
    for (final w in weights) ...[(w, 'normal'), if (italic && (w == 400 || w == 700)) (w, 'italic')],
  ];
}

/// js/fontlib.js loadCatalog(): keeps fonts with a latin subset and at least
/// one weight, drops icon fonts and anything with an odd id or name.
List<LibraryFont> parseCatalog(String json) {
  final data = jsonDecode(json);
  if (data is! List) return [];
  final out = <LibraryFont>[];
  for (final f in data) {
    if (f is! Map) continue;
    final id = f['id'];
    final family = f['family'];
    final subsets = f['subsets'];
    final weights = f['weights'];
    if (id is! String || !RegExp(r'^[a-z0-9-]{1,80}$').hasMatch(id)) continue;
    if (family is! String || family.length > 80) continue;
    if (subsets is! List || !subsets.contains('latin')) continue;
    if (weights is! List || weights.isEmpty || f['category'] == 'icons') continue;
    final ws = [
      for (final w in weights)
        if (w is int && w >= 100 && w <= 900) w,
    ];
    if (ws.isEmpty) continue;
    final category = kFontCategories.containsKey(f['category']) ? f['category'] as String : 'other';
    final styles = f['styles'];
    out.add(
      LibraryFont(
        id: id,
        family: family.replaceAll(RegExp(r'[\u0000-\u001f"\\]'), ''),
        category: category,
        weights: ws,
        italic: styles is List && styles.contains('italic'),
        license: '${f['license'] ?? ''}'.length > 40 ? '${f['license']}'.substring(0, 40) : '${f['license'] ?? ''}',
      ),
    );
  }
  return out;
}

/// The list as the person sees it: filtered by [query] and [category], searched
/// names starting with the query first, otherwise the popular fonts first.
List<LibraryFont> filterCatalog(List<LibraryFont> all, {String query = '', String? category}) {
  final q = query.trim().toLowerCase();
  final found = [
    for (final f in all)
      if ((category == null || category.isEmpty || f.category == category) &&
          (q.isEmpty || f.family.toLowerCase().contains(q)))
        f,
  ];
  if (q.isNotEmpty) {
    found.sort((a, b) {
      final sa = a.family.toLowerCase().startsWith(q) ? 0 : 1;
      final sb = b.family.toLowerCase().startsWith(q) ? 0 : 1;
      return sa != sb ? sa.compareTo(sb) : a.family.compareTo(b.family);
    });
  } else {
    int rank(LibraryFont f) {
      final i = kPopularFonts.indexOf(f.family);
      return i < 0 ? 999 : i;
    }

    found.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.family.compareTo(b.family);
    });
  }
  return found;
}

/// Where the free fonts come from. The real one asks Fontsource; tests use a fake.
abstract class FontSource {
  Future<List<LibraryFont>> catalog();

  /// One face as a TTF (Flutter cannot load WOFF2 on a phone).
  Future<Uint8List> face(LibraryFont font, int weight, String style);
}

class FontsourceSource implements FontSource {
  FontsourceSource([http.Client? client]) : _client = client ?? http.Client();
  final http.Client _client;

  static const String api = 'https://api.fontsource.org/v1/fonts';
  static const String cdn = 'https://cdn.jsdelivr.net/fontsource/fonts';

  static String faceUrl(String id, int weight, String style) => '$cdn/$id@latest/latin-$weight-$style.ttf';

  @override
  Future<List<LibraryFont>> catalog() async {
    final r = await _client.get(Uri.parse(api)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('the library answered ${r.statusCode}');
    return parseCatalog(utf8.decode(r.bodyBytes));
  }

  @override
  Future<Uint8List> face(LibraryFont font, int weight, String style) async {
    final r = await _client.get(Uri.parse(faceUrl(font.id, weight, style))).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw Exception('download failed (${r.statusCode})');
    if (r.bodyBytes.length > 5e6) throw Exception('the font file is unexpectedly large');
    return r.bodyBytes;
  }
}
