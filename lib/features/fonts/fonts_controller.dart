import 'package:flutter/foundation.dart';

import '../../core/fonts/font_files.dart';
import '../../core/fonts/font_registry.dart';
import '../../core/store/font_store.dart';
import '../../platform/photo_picker.dart';
import 'font_library.dart';

enum LibraryState { idle, loading, ready, failed }

/// The three tabs of the fonts screen: the free library, font files, and the
/// fonts added so far (js/fontlib.js).
class FontsController extends ChangeNotifier {
  FontsController({required this.source, required this.store, required this.picker, this.onAdded});

  final FontSource source;
  final FontStore store;
  final PhotoPicker picker;

  /// Called with the family of a font that was just added (the editor uses it
  /// to give it to the selected text).
  final void Function(String family)? onAdded;

  LibraryState libraryState = LibraryState.idle;
  String libraryError = '';
  List<LibraryFont> _all = [];
  String query = '';
  String category = '';
  int shown = kFontPage;

  /// Library fonts being downloaded: family to "2/5".
  final Map<String, String> adding = {};

  /// A line under the library list and under the file button.
  String libraryMessage = '';
  bool libraryMessageBad = false;
  String fileMessage = '';
  bool fileMessageBad = false;
  bool readingFiles = false;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  FontRegistry get registry => FontRegistry.instance;

  // ---------- the library ----------

  Future<void> loadLibrary() async {
    if (libraryState == LibraryState.loading || libraryState == LibraryState.ready) return;
    libraryState = LibraryState.loading;
    _changed();
    try {
      _all = await source.catalog();
      libraryState = LibraryState.ready;
    } catch (e) {
      libraryState = LibraryState.failed;
      libraryError = "Can't reach the font library. Check the internet connection, or add a font file instead.";
      debugPrint('Font library: $e');
    }
    _changed();
  }

  void retryLibrary() {
    libraryState = LibraryState.idle;
    loadLibrary();
  }

  List<LibraryFont> get found => filterCatalog(_all, query: query, category: category.isEmpty ? null : category);

  List<LibraryFont> get visible => found.take(shown).toList();

  int get total => _all.length;

  void setQuery(String text) {
    query = text;
    shown = kFontPage;
    _changed();
  }

  void setCategory(String key) {
    category = key;
    shown = kFontPage;
    _changed();
  }

  void showMore() {
    shown += kFontPage;
    _changed();
  }

  /// A line about the list: how many fonts, or none found.
  String get libraryCountLine {
    final n = found.length;
    if (n == 0) return 'No free fonts match "${query.trim()}".';
    if (query.trim().isNotEmpty || category.isNotEmpty) return n == 1 ? '1 font found.' : '${_n(n)} fonts found.';
    return '${_n(_all.length)} free fonts. Popular ones first; type to search.';
  }

  static String _n(int n) => n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  bool isBuiltIn(LibraryFont f) => registry.kind(f.family) == 'built-in';

  bool isAdded(LibraryFont f) => isBuiltIn(f) || registry.added().any((a) => a.family == f.family);

  Future<void> addFromLibrary(LibraryFont f) async {
    if (adding.containsKey(f.family)) return;
    final jobs = f.faces;
    var done = 0;
    adding[f.family] = '0/${jobs.length}';
    libraryMessage = '';
    _changed();
    try {
      final queue = List.of(jobs);
      // A few at a time; each style is a small file.
      await Future.wait([
        for (var i = 0; i < 4; i++)
          () async {
            while (queue.isNotEmpty) {
              final (w, style) = queue.removeAt(0);
              final bytes = await source.face(f, w, style);
              await registry.register(f.family, w, style, bytes, source: 'library');
              await store
                  .save(StoredFont(family: f.family, weight: w, style: style, bytes: bytes, source: 'library'))
                  .catchError((Object _) {});
              adding[f.family] = '${++done}/${jobs.length}';
              _changed();
            }
          }(),
      ]);
      libraryMessage = "Added ${f.family}. It's now in the Font list of every text.";
      libraryMessageBad = false;
      onAdded?.call(f.family);
    } catch (e) {
      libraryMessage = "Couldn't add ${f.family}: ${_why(e)}. Check the internet connection and try again.";
      libraryMessageBad = true;
    }
    adding.remove(f.family);
    _changed();
  }

  static String _why(Object e) => e.toString().replaceFirst('Exception: ', '');

  // ---------- font files ----------

  Future<void> chooseFiles() async {
    final files = await picker.pickFiles(extensions: ['ttf', 'otf', 'woff', 'woff2', 'zip']);
    await addFiles(files);
  }

  Future<void> addFiles(List<PickedPhoto> files) async {
    if (files.isEmpty) return;
    readingFiles = true;
    _changed();
    final problems = <String>[];
    final families = <String>[];
    for (final file in files) {
      try {
        for (final face in facesFromFile(file.name, await file.readBytes(), problems)) {
          try {
            await registry.register(
              face.family,
              face.weight,
              face.style,
              face.bytes,
              variable: face.variable,
              source: 'file',
            );
            await store
                .save(
                  StoredFont(
                    family: face.family,
                    weight: face.weight,
                    style: face.style,
                    bytes: face.bytes,
                    variable: face.variable,
                    mime: face.mime,
                  ),
                )
                .catchError((Object _) {});
            if (!families.contains(face.family)) families.add(face.family);
          } catch (_) {
            problems.add("${file.name} couldn't be read as a font");
          }
        }
      } catch (e) {
        problems.add('${file.name}: ${_why(e)}');
      }
    }
    final parts = <String>[];
    if (families.isNotEmpty) {
      final shown = families.take(5).join(', ');
      parts.add(
        "Added $shown${families.length > 5 ? ' and ${families.length - 5} more' : ''}. It's now in the Font list of every text.",
      );
    }
    if (problems.isNotEmpty) {
      final list = problems.take(4).join('; ');
      parts.add('Not added: $list${problems.length > 4 ? '...' : (list.endsWith('.') ? '' : '.')}');
    }
    fileMessage = parts.isEmpty ? 'No fonts were found.' : parts.join(' ');
    fileMessageBad = families.isEmpty;
    readingFiles = false;
    _changed();
    if (families.isNotEmpty) onAdded?.call(families.first);
  }

  // ---------- your fonts ----------

  List<AddedFont> get mine => registry.added();

  Future<void> remove(String family) async {
    registry.unregister(family);
    try {
      await store.removeFamily(family);
    } catch (e) {
      debugPrint('Font $family could not be removed from the phone: $e');
    }
    _changed();
  }
}
