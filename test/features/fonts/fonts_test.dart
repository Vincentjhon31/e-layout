import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/fonts/font_registry.dart';
import 'package:pio_photo_layout/core/store/font_store.dart';
import 'package:pio_photo_layout/core/store/font_store_io.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/features/fonts/font_library.dart';
import 'package:pio_photo_layout/features/fonts/fonts_controller.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';

/// A small canned answer of the Fontsource list (no network in tests).
const String cannedCatalog = '''[
  {"id":"roboto","family":"Roboto","subsets":["latin","greek"],"weights":[400,700],"styles":["normal","italic"],"category":"sans-serif","license":"Apache-2.0"},
  {"id":"abeezee","family":"ABeeZee","subsets":["latin"],"weights":[400],"styles":["normal"],"category":"sans-serif","license":"OFL-1.1"},
  {"id":"material-icons","family":"Material Icons","subsets":["latin"],"weights":[400],"styles":["normal"],"category":"icons","license":"Apache-2.0"},
  {"id":"noto-sans-thai","family":"Noto Sans Thai","subsets":["thai"],"weights":[400],"styles":["normal"],"category":"sans-serif","license":"OFL-1.1"},
  {"id":"bad id!","family":"Bad","subsets":["latin"],"weights":[400],"styles":["normal"],"category":"serif","license":"OFL-1.1"},
  {"id":"lobster","family":"Lobster","subsets":["latin"],"weights":[400],"styles":["normal"],"category":"display","license":"OFL-1.1"},
  {"id":"zeta","family":"Zeta Sans","subsets":["latin"],"weights":[300,900],"styles":["normal"],"category":"strange","license":"OFL-1.1"},
  {"id":"noweights","family":"No Weights","subsets":["latin"],"weights":[],"styles":["normal"],"category":"serif","license":"OFL-1.1"}
]''';

class FakeFontSource implements FontSource {
  FakeFontSource({this.fail = false});
  final bool fail;
  final List<String> asked = [];
  late final Uint8List ttf = File('assets/fonts/barlow-700.ttf').readAsBytesSync();

  @override
  Future<List<LibraryFont>> catalog() async {
    if (fail) throw Exception('offline');
    return parseCatalog(cannedCatalog);
  }

  @override
  Future<Uint8List> face(LibraryFont font, int weight, String style) async {
    if (fail) throw Exception('offline');
    asked.add('${font.id}-$weight-$style');
    return ttf;
  }
}

void main() {
  group('library list', () {
    test('drops icon fonts, fonts without a latin subset, odd ids and fonts without weights', () {
      final list = parseCatalog(cannedCatalog);
      expect([for (final f in list) f.id], ['roboto', 'abeezee', 'lobster', 'zeta']);
      expect(list.last.category, 'other', reason: 'an unknown category becomes Other');
    });

    test('popular fonts come first; a search puts names that start with it first', () {
      final list = parseCatalog(cannedCatalog);
      expect([for (final f in filterCatalog(list)) f.family], ['Roboto', 'Lobster', 'ABeeZee', 'Zeta Sans']);
      expect([for (final f in filterCatalog(list, query: 'o')) f.family], ['Lobster', 'Roboto']);
      expect([for (final f in filterCatalog(list, query: 'r')) f.family].first, 'Roboto', reason: 'starts with r');
      expect([for (final f in filterCatalog(list, query: 'zee')) f.family], ['ABeeZee']);
      expect([for (final f in filterCatalog(list, category: 'display')) f.family], ['Lobster']);
      expect(filterCatalog(list, query: 'nothing here'), isEmpty);
    });

    test('faces: every weight, plus italic for 400 and 700', () {
      final roboto = parseCatalog(cannedCatalog).first;
      expect(roboto.faces, [(400, 'normal'), (400, 'italic'), (700, 'normal'), (700, 'italic')]);
    });

    test('the download address is a TTF on the Fontsource CDN', () {
      expect(FontsourceSource.faceUrl('roboto', 700, 'italic'),
          'https://cdn.jsdelivr.net/fontsource/fonts/roboto@latest/latin-700-italic.ttf');
    });
  });

  group('font store', () {
    test('survives a missing folder and round-trips', () async {
      final dir = Directory('${Directory.systemTemp.path}/pio_fonts_${DateTime.now().microsecondsSinceEpoch}/none');
      final store = FileFontStore.inDirectory(dir);
      expect(await store.loadAll(), isEmpty);
      await store.removeFamily('Nothing');
      final bytes = File('assets/fonts/barlow-700.ttf').readAsBytesSync();
      await store.save(StoredFont(family: 'Barlow Test', weight: 700, style: 'normal', bytes: bytes, source: 'library'));
      final back = await store.loadAll();
      expect(back.single.family, 'Barlow Test');
      expect(back.single.source, 'library');
      expect(back.single.bytes.length, bytes.length);
      await store.removeFamily('Barlow Test');
      expect(await store.loadAll(), isEmpty);
      if (await dir.parent.exists()) await dir.parent.delete(recursive: true);
    });
  });

  group('fonts controller', () {
    FontsController make(FakeFontSource source, FontStore store, {PhotoPicker? picker, void Function(String)? onAdded}) =>
        FontsController(source: source, store: store, picker: picker ?? FakePhotoPicker(), onAdded: onAdded);

    test('adding from the library registers every face, keeps them, and tells the caller', () async {
      final source = FakeFontSource();
      final store = MemoryFontStore();
      final added = <String>[];
      final c = make(source, store, onAdded: added.add);
      await c.loadLibrary();
      expect(c.libraryState, LibraryState.ready);
      final roboto = c.visible.firstWhere((f) => f.id == 'roboto');
      expect(c.isAdded(roboto), isFalse);
      await c.addFromLibrary(roboto);
      expect(source.asked.length, 4);
      expect((await store.loadAll()).length, 4);
      expect(c.isAdded(roboto), isTrue);
      expect(added, ['Roboto']);
      expect(c.libraryMessage, "Added Roboto. It's now in the Font list of every text.");
      expect(c.mine.single.family, 'Roboto');
      expect(c.mine.single.source, 'library');
      await c.remove('Roboto');
      expect(c.mine, isEmpty);
      expect(await store.loadAll(), isEmpty);
      c.dispose();
    });

    test('no internet: the library says so in plain words and nothing is added', () async {
      final c = make(FakeFontSource(fail: true), MemoryFontStore());
      await c.loadLibrary();
      expect(c.libraryState, LibraryState.failed);
      expect(c.libraryError, "Can't reach the font library. Check the internet connection, or add a font file instead.");
      c.dispose();
      final c2 = make(FakeFontSource(), MemoryFontStore());
      await c2.loadLibrary();
      final bad = make(FakeFontSource(fail: true), MemoryFontStore());
      await bad.addFromLibrary(c2.visible.first);
      expect(bad.libraryMessageBad, isTrue);
      expect(bad.libraryMessage, startsWith("Couldn't add Roboto: offline."));
      expect(bad.mine, isEmpty);
      bad.dispose();
      c2.dispose();
    });

    test('font files: a TTF is added, a WOFF2 and a text file are explained', () async {
      final store = MemoryFontStore();
      final added = <String>[];
      final c = make(FakeFontSource(), store, onAdded: added.add);
      final ttf = File('assets/fonts/barlow-700.ttf').readAsBytesSync();
      PickedPhoto file(String name, Uint8List bytes) => PickedPhoto(name: name, readBytes: () async => bytes);
      await c.addFiles([
        file('MyFont-Bold.ttf', ttf),
        file('Other.woff2', Uint8List.fromList('wOF2'.codeUnits + List.filled(30, 0))),
        file('notes.txt', Uint8List(4)),
      ]);
      expect(c.mine.map((a) => a.family), contains('Barlow'));
      expect(added, ['Barlow']);
      expect(c.fileMessage, contains("Added Barlow. It's now in the Font list of every text."));
      expect(c.fileMessage, contains("WOFF2 font files can't be used on this phone"));
      expect(c.fileMessage, contains("notes.txt isn't a font file"));
      expect(c.fileMessageBad, isFalse);
      expect((await store.loadAll()).single.source, 'file');
      await c.remove('Barlow');
      c.dispose();
    });

    test('a list of files with nothing usable is an error line', () async {
      final c = make(FakeFontSource(), MemoryFontStore());
      await c.addFiles([PickedPhoto(name: 'a.txt', readBytes: () async => Uint8List(2))]);
      expect(c.fileMessageBad, isTrue);
      c.dispose();
    });

    test('the list shows 60 at a time', () async {
      final many = [
        for (var i = 0; i < 130; i++)
          {'id': 'f$i', 'family': 'Font $i', 'subsets': ['latin'], 'weights': [400], 'styles': ['normal'], 'category': 'serif'},
      ];
      final parsed = parseCatalog(jsonEncode(many));
      expect(parsed.length, 130);
      final src = _ListSource(parsed);
      final c = FontsController(source: src, store: MemoryFontStore(), picker: FakePhotoPicker());
      await c.loadLibrary();
      expect(c.visible.length, 60);
      c.showMore();
      expect(c.visible.length, 120);
      expect(c.libraryCountLine, '130 free fonts. Popular ones first; type to search.');
      c.dispose();
    });
  });

  test('the registry lists added fonts and forgets removed ones', () async {
    final r = FontRegistry.instance;
    final ttf = File('assets/fonts/barlow-700.ttf').readAsBytesSync();
    await r.register('Registry Test', 700, 'normal', ttf, source: 'file');
    expect(r.added().any((a) => a.family == 'Registry Test' && a.source == 'file'), isTrue);
    expect(r.kind('Registry Test'), 'uploaded');
    r.unregister('Registry Test');
    expect(r.kind('Registry Test'), 'unknown');
  });
}

class _ListSource implements FontSource {
  _ListSource(this.list);
  final List<LibraryFont> list;
  @override
  Future<List<LibraryFont>> catalog() async => list;
  @override
  Future<Uint8List> face(LibraryFont font, int weight, String style) async => Uint8List(0);
}
