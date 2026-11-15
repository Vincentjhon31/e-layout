import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/about/about_screen.dart';
import 'package:pio_photo_layout/features/about/update_controller.dart';
import 'package:pio_photo_layout/features/about/update_dialogs.dart';
import 'package:pio_photo_layout/features/about/whats_new.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/features/home/home_screen.dart';
import 'package:pio_photo_layout/features/home/home_wiring.dart';
import 'package:pio_photo_layout/online/net.dart';
import 'package:pio_photo_layout/platform/device_noun.dart';
import 'package:pio_photo_layout/platform/file_sharer.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/platform/temp_files_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/golden_helpers.dart';
import 'fakes.dart';

const notes = '''
# What's new

## 1.0.0

- PIO Photo Layout is now e-Layout, with a new icon. It runs on Android phones, on Windows computers and in the browser.
- Put your office's layout on a whole batch of photos at full size, with no internet needed.
- Make and change layouts by touch: words, shapes, icons, logos, groups and layers.

## 0.9.0

- The first version people could try.
''';

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    loadWhatsNewMarkdown = () async => notes;
    deviceNoun = 'phone';
  });
  tearDown(() => loadWhatsNewMarkdown = defaultLoadWhatsNew);

  UpdateController make({FakeUpdater? updater, FakeWeb? web}) =>
      UpdateController(updater: updater, web: web, settings: SettingsStore(), version: '1.0.0', build: 1);

  Future<void> show(WidgetTester tester, Widget page,
      {Brightness b = Brightness.light, Size size = const Size(390, 844)}) async {
    await tester.runAsync(() async {
      await loadAppFonts();
    });
    setPhone(tester, size: size);
    await tester.pumpWidget(themed(page, b));
    await tester.runAsync(() async {
      await precacheImage(const AssetImage('assets/img/app_icon.png'), tester.element(find.byType(CupertinoApp)));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> shot(String name) => expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/$name.png'));

  testWidgets('About: version, up to date, the 1.0.0 bullets', (tester) async {
    final u = make(updater: FakeUpdater(release: null));
    await show(tester, AboutScreen(updates: u));
    expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
    expect(find.text("You're up to date."), findsOneWidget);
    expect(find.text("WHAT'S NEW IN 1.0.0"), findsOneWidget);
    expect(find.textContaining("Put your office's layout"), findsOneWidget);
    expect(find.text('Public Information Office, Municipality of Bongabong'), findsOneWidget);
    expect(find.text('pio.bongabong.gov.ph'), findsOneWidget);
    await shot('about_light');
  });

  testWidgets('About in dark mode', (tester) async {
    await show(tester, AboutScreen(updates: make(updater: FakeUpdater(release: null))), b: Brightness.dark);
    await shot('about_dark');
  });

  testWidgets('About wide', (tester) async {
    await show(tester, AboutScreen(updates: make(updater: FakeUpdater(release: null))), size: const Size(1280, 800));
    await shot('about_wide');
  });

  testWidgets('About with an update available', (tester) async {
    final u = make(updater: FakeUpdater(release: release110()));
    await show(tester, AboutScreen(updates: u));
    expect(find.text('Version 1.1.0 is available.'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.text("WHAT'S NEW IN 1.1.0"), findsOneWidget);
    expect(find.text('Photos save faster.'), findsOneWidget);
    await shot('about_update_available');
  });

  testWidgets('About offline and failed', (tester) async {
    await show(tester, AboutScreen(updates: make(updater: FakeUpdater(error: offline))));
    expect(find.text("You're offline. Check for updates when you're connected."), findsOneWidget);
    await shot('about_offline');
    await tester.pumpWidget(const SizedBox());
    await show(tester, AboutScreen(updates: make(updater: FakeUpdater(error: const NetException(kServerTroubleMessage)))));
    expect(find.text("Can't check for updates right now. Try again later."), findsOneWidget);
  });

  testWidgets('About on the website and where there are no updates', (tester) async {
    await show(tester, AboutScreen(updates: make(web: FakeWeb({'version': '1.0.0', 'build_number': '1'}))));
    expect(find.text('The website version updates itself.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await show(tester, AboutScreen(updates: make(web: FakeWeb({'version': '1.0.3', 'build_number': '1'}))));
    expect(find.text('A newer version is on the website.'), findsOneWidget);
    expect(find.text('Reload'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await show(tester, AboutScreen(updates: make()));
    expect(find.text('New versions are on the download page.'), findsOneWidget);
    expect(find.text('Open the download page'), findsOneWidget);
  });

  testWidgets('Changelog opens a page listing every version', (tester) async {
    await show(tester, AboutScreen(updates: make(updater: FakeUpdater(release: null))));
    await tester.ensureVisible(find.text('Changelog'));
    await tester.pump();
    await tester.tap(find.text('Changelog'));
    // The first frame starts the page transition; the second shows the page.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Version 1.0.0'), findsOneWidget);
    expect(find.text('Version 0.9.0'), findsOneWidget);
    expect(find.text('The first version people could try.'), findsOneWidget);
    await shot('changelog_light');
  });

  testWidgets('the What\'s new sheet', (tester) async {
    await show(tester, const Center(child: Text('home')));
    unawaited(showWhatsNewSheet(tester.element(find.text('home')), parseWhatsNew(notes)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await shot('whats_new_sheet_light');
  });

  testWidgets('the Update available box', (tester) async {
    final u = make(updater: FakeUpdater(release: release110()));
    await show(tester, const Center(child: Text('home')));
    unawaited(showUpdateAvailable(tester.element(find.text('home')), u, release110()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await shot('update_available_dialog');
  });

  testWidgets('the update box leads to the download box, which shows 22.7 of 54.1 MB at 42%', (tester) async {
    final updater = FakeUpdater(release: release110());
    final u = make(updater: updater);
    await show(tester, const Center(child: Text('home')));
    unawaited(showUpdateAvailable(tester.element(find.text('home')), u, release110()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Update'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Updating to version 1.1.0'), findsOneWidget);
    expect(find.text('Downloading…'), findsOneWidget);
    updater.downloads!.add(0.42);
    await tester.pump();
    expect(find.text('Downloading… 22.7 of 54.1 MB'), findsOneWidget);
    expect(find.textContaining('allow installs from e-Layout'), findsOneWidget);
    await shot('update_download_42');
    updater.downloads!.add(1);
    await tester.pump();
    expect(find.text('Opening the installer…'), findsOneWidget);
    // Cancel stops the download and closes the box.
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Updating to version 1.1.0'), findsNothing);
  });

  testWidgets('a failed download shows the text and three buttons; Try again starts over', (tester) async {
    final updater = FakeUpdater(release: release110());
    await show(tester, const Center(child: Text('home')));
    unawaited(showUpdateDownload(tester.element(find.text('home')), updater, release110()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    updater.downloads!.addError(offline);
    await tester.pump();
    expect(find.text("The update couldn't be downloaded. Check your internet connection and try again."), findsOneWidget);
    expect(find.text('Download in browser'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await shot('update_download_failed');
    Uri? opened;
    openExternal = (uri) async => opened = uri;
    await tester.tap(find.text('Download in browser'));
    expect(opened.toString(), release110().downloadUrl);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(updater.downloadStarts, 2);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Home shows the reload notice when the website has a newer version', (tester) async {
    final c = HomeController(
      layoutStore: MemoryLayoutStore(),
      settingsStore: SettingsStore(),
      picker: FakePhotoPicker(),
      saver: FakeGallerySaver(),
      sharer: FakeFileSharer(),
      temp: MemoryTempFiles(),
      fontStore: MemoryFontStore(),
    );
    await tester.runAsync(() async {
      await loadAppFonts();
      await c.init();
    });
    final web = FakeWeb({'version': '1.0.1', 'build_number': '2'});
    final u = make(web: web);
    await tester.runAsync(u.check);
    setPhone(tester);
    await tester.pumpWidget(themed(HomeScreen(controller: c, updates: u, actions: homeActions(c, updates: u)), Brightness.light));
    // No start-up what's-new or update check ran a dialog (nothing was saved before).
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('e-Layout'), findsOneWidget); // Home's large title
    expect(find.text('A new version of e-Layout is ready. Reload to use it.'), findsOneWidget);
    await shot('home_web_reload_notice');
    await tester.tap(find.text('Reload'));
    expect(web.reloaded, isTrue);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
