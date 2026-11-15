import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/about/update_controller.dart';
import 'package:pio_photo_layout/online/net.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/golden_helpers.dart';
import 'fakes.dart';

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  UpdateController make({FakeUpdater? updater, FakeWeb? web}) =>
      UpdateController(updater: updater, web: web, settings: SettingsStore(), version: '1.0.0', build: 1);

  Future<BuildContext> host(WidgetTester tester) async {
    await tester.runAsync(loadAppFonts);
    await tester.pumpWidget(themed(const Center(child: Text('home')), Brightness.light));
    return tester.element(find.text('home'));
  }

  test('offline gives UpdateOffline with the offline message', () async {
    final c = make(updater: FakeUpdater(error: offline));
    await c.check();
    expect(c.state, isA<UpdateOffline>());
    expect((c.state as UpdateOffline).message, kOfflineMessage);
  });

  test('another failure gives UpdateFailed', () async {
    final c = make(updater: FakeUpdater(error: const NetException(kServerTroubleMessage, status: 500)));
    await c.check();
    expect(c.state, isA<UpdateFailed>());
  });

  test('a newer release is UpdateAvailable; the same or older is UpToDate', () async {
    final c = make(updater: FakeUpdater(release: release110()));
    await c.check();
    expect(c.state, isA<UpdateAvailable>());
    expect((c.state as UpdateAvailable).release.version, '1.1.0');
    final same = UpdateController(updater: FakeUpdater(release: release110()), settings: SettingsStore(), version: '1.1.0', build: 2);
    await same.check();
    expect(same.state, isA<UpToDate>());
    final none = make(updater: FakeUpdater(release: null));
    await none.check();
    expect(none.state, isA<UpToDate>());
  });

  test('a web watcher with a newer deployment gives WebReloadReady', () async {
    final c = make(web: FakeWeb({'version': '1.0.1', 'build_number': '2'}));
    await c.check();
    expect(c.state, isA<WebReloadReady>());
    expect((c.state as WebReloadReady).version, '1.0.1');
    final same = make(web: FakeWeb({'version': '1.0.0', 'build_number': '1'}));
    await same.check();
    expect(same.state, isA<UpToDate>());
  });

  test('with neither the state is UpdatesNotOffered', () async {
    final c = make();
    await c.check();
    expect(c.state, isA<UpdatesNotOffered>());
  });

  testWidgets('checkAtStart offline shows nothing', (tester) async {
    final ctx = await host(tester);
    final c = make(updater: FakeUpdater(error: offline));
    await tester.runAsync(() => c.checkAtStart(ctx));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('a newer release asks once per version', (tester) async {
    final ctx = await host(tester);
    final u = FakeUpdater(release: release110());
    final c = make(updater: u);
    await tester.runAsync(() async {
      // The dialog stays open until it is answered, so do not await it.
      c.checkAtStart(ctx);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Version 1.1.0 is ready. It installs over this one, and your layouts, fonts and settings stay.'), findsOneWidget);
    expect(find.textContaining('Share your layouts with other offices.'), findsOneWidget);
    expect(await tester.runAsync(() => SettingsStore().readValue('update_prompted')), '1.1.0+2');
    await tester.tap(find.text('Later'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Update available'), findsNothing);
    // A second start with the same release shows nothing.
    final c2 = make(updater: FakeUpdater(release: release110()));
    await tester.runAsync(() => c2.checkAtStart(ctx));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Update available'), findsNothing);
  });
}
