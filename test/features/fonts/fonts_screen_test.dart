import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/store/batch_store_memory.dart';
import 'package:pio_photo_layout/core/store/preset_store_memory.dart';
import 'package:pio_photo_layout/core/fonts/font_registry.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/features/home/home_screen.dart';
import 'package:pio_photo_layout/features/home/home_wiring.dart';
import 'package:pio_photo_layout/platform/file_sharer.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/temp_files_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pio_photo_layout/features/fonts/fonts_controller.dart';
import 'package:pio_photo_layout/features/fonts/fonts_screen.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';

import '../../ui/golden_helpers.dart';
import 'fonts_test.dart' show FakeFontSource;

FontsController make(FakeFontSource source, {FakePhotoPicker? picker}) =>
    FontsController(source: source, store: MemoryFontStore(), picker: picker ?? FakePhotoPicker());

Future<void> pump(WidgetTester tester, FontsController c,
    {FontsTab tab = FontsTab.library, Brightness b = Brightness.light, Size size = const Size(390, 844)}) async {
  setPhone(tester, size: size);
  await tester.pumpWidget(themed(FontsScreen(controller: c, initialTab: tab), b));
  await tester.pump();
  // The list loads, then each visible row loads its own preview face.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pump();
}

Finder tab(String name) => find.descendant(
    of: find.byWidgetPredicate((w) => w is CupertinoSlidingSegmentedControl<FontsTab>), matching: find.text(name));

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  Future<void> shot(WidgetTester tester, String name) =>
      expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/$name.png'));

  Future<void> done(WidgetTester tester, FontsController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  testWidgets('free library: the list, then Add puts the font under Your fonts', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = make(FakeFontSource());
    await pump(tester, c);
    expect(find.text('Search free fonts'), findsOneWidget);
    expect(find.text('Roboto'), findsOneWidget);
    expect(find.text('Sans serif, 2 weights'), findsOneWidget);
    expect(find.text('4 free fonts. Popular ones first; type to search.'), findsOneWidget);
    await shot(tester, 'fonts_library_light');
    await tester.tap(find.text('Add').first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    expect(find.text("Added Roboto. It's now in the Font list of every text."), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    await tester.tap(tab('Your fonts'));
    await tester.pump();
    expect(find.text('From the free library, 2 weights'), findsOneWidget);
    await shot(tester, 'fonts_mine_light');
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Roboto?'), findsOneWidget);
    await tester.tap(find.text('Remove').last);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('No fonts added yet. Add one from the free library or from a file.'), findsOneWidget);
    await done(tester, c);
  });

  testWidgets('search narrows the list', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = make(FakeFontSource());
    await pump(tester, c);
    await tester.enterText(find.byType(CupertinoTextField), 'lob');
    await tester.pump();
    expect(find.text('Lobster'), findsOneWidget);
    expect(find.text('Roboto'), findsNothing);
    expect(find.text('1 font found.'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoTextField), 'zzzz');
    await tester.pump();
    expect(find.text('No free fonts match "zzzz".'), findsOneWidget);
    await done(tester, c);
  });

  testWidgets('no internet: the library says so, the other tabs still work', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = make(FakeFontSource(fail: true));
    await pump(tester, c, b: Brightness.dark);
    expect(find.text("Can't reach the font library. Check the internet connection, or add a font file instead."),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await shot(tester, 'fonts_offline_dark');
    await tester.tap(tab('From a file'));
    await tester.pump();
    expect(find.text('Choose font files'), findsOneWidget);
    await done(tester, c);
  });

  testWidgets('from a file: a TTF is added and the result is a line under the button', (tester) async {
    await tester.runAsync(loadAppFonts);
    final ttf = File('assets/fonts/barlow-700.ttf').readAsBytesSync();
    final picker = FakePhotoPicker()
      ..nextFiles = [
        PickedPhoto(name: 'Barlow-Bold.ttf', readBytes: () async => ttf),
        PickedPhoto(name: 'Other.woff2', readBytes: () async => Uint8List.fromList('wOF2'.codeUnits + List.filled(30, 0))),
      ];
    final c = make(FakeFontSource(), picker: picker);
    await pump(tester, c, tab: FontsTab.file);
    await shot(tester, 'fonts_file_empty');
    await tester.tap(find.text('Choose font files'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.textContaining("Added Barlow. It's now in the Font list of every text."), findsOneWidget);
    expect(find.textContaining("WOFF2 font files can't be used on this phone"), findsOneWidget);
    await shot(tester, 'fonts_file_added');
    await tester.tap(tab('Your fonts'));
    await tester.pump();
    expect(find.text('From a file, 1 weight'), findsOneWidget);
    FontRegistry.instance.unregister('Barlow');
    await done(tester, c);
  });

  testWidgets('small phone, library', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = make(FakeFontSource());
    await pump(tester, c, size: const Size(320, 568));
    await shot(tester, 'fonts_library_small');
    await done(tester, c);
  });

  testWidgets('Home: the ... menu opens Fonts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final home = HomeController(
      layoutStore: MemoryLayoutStore(),
      settingsStore: SettingsStore(),
      picker: FakePhotoPicker(),
      saver: FakeGallerySaver(),
      sharer: FakeFileSharer(),
      temp: MemoryTempFiles(),
      presetStore: MemoryPresetStore(),
      batchStore: MemoryBatchStore(),
      developer: CpuDeveloper(),
      fontStore: MemoryFontStore(),
    );
    await tester.runAsync(() async {
      await loadAppFonts();
      await home.init();
    });
    addTearDown(home.dispose);
    setPhone(tester);
    await tester.pumpWidget(themed(
        HomeScreen(controller: home, actions: homeActions(home, fontSource: FakeFontSource())), Brightness.light));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    expect(find.text('Fonts'), findsOneWidget);
    await tester.tap(find.text('Fonts'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.text('Search free fonts'), findsOneWidget);
    expect(find.text('Free library'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
