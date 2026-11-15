import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pio_photo_layout/features/about/update_controller.dart';
import 'package:pio_photo_layout/features/editor/editor_screen.dart';
import 'package:pio_photo_layout/features/editor/open_editor.dart';
import 'package:pio_photo_layout/features/home/home_screen.dart';
import 'package:pio_photo_layout/features/home/home_wiring.dart';
import 'package:pio_photo_layout/online/net.dart';
import 'package:pio_photo_layout/platform/app_updater_io.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/home/home_controller_test.dart' show picked, png;
import '../features/home/home_golden_test.dart' show newController;
import '../ui/golden_helpers.dart';

/// Records every attempt to open a connection and fails like a missing network.
class _ThrowingHttpOverrides extends HttpOverrides {
  _ThrowingHttpOverrides(this.attempts);
  final List<String> attempts;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _ThrowingClient(attempts);
}

class _ThrowingClient implements HttpClient {
  _ThrowingClient(this.attempts);
  final List<String> attempts;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (name.contains('open') || name.contains('get') || name.contains('post') || name.contains('head')) {
      attempts.add('HttpClient $name');
      return Future<Never>.error(const SocketException('Failed host lookup'));
    }
    return null;
  }
}

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('add photos, edit a layout and save with no network: nothing tries to connect', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final attempts = <String>[];
    HttpOverrides.global = _ThrowingHttpOverrides(attempts);
    addTearDown(() => HttpOverrides.global = null);
    final mock = MockClient((r) async {
      attempts.add('MockClient ${r.url}');
      throw http.ClientException('offline');
    });

    final c = newController();
    final saver = c.saver as FakeGallerySaver;
    await tester.runAsync(() async {
      await loadAppFonts();
      await c.init();
    });
    addTearDown(c.dispose);
    setPhone(tester);
    await tester.pumpWidget(themed(
        HomeScreen(controller: c, actions: homeActions(c, openEditor: openEditorFor(c, FakePhotoPicker()))), Brightness.light));
    await tester.pump();

    // Three photos.
    await tester.runAsync(() async {
      await c.addPhotos([picked('a.jpg', png(60, 40)), picked('b.jpg', png(40, 60)), picked('c.jpg', png(50, 50))]);
      await c.whenIdle();
    });
    await tester.pump();

    // A new layout in the editor, with a text on it.
    await tester.tap(find.text('New or from a file'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('New layout'));
      for (var i = 0; i < 30 && find.byType(EditorScreen).evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heading'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Done').first);
      for (var i = 0; i < 30 && find.byType(EditorScreen).evaluate().isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();

    // Save the three photos.
    await tester.runAsync(() async {
      await c.saveAll();
    });
    expect(saver.names.length, 3);
    expect(c.message, startsWith('Saved 3 photos'));
    expect(attempts, isEmpty, reason: 'No network attempt may happen while adding, editing or saving.');
    mock.close();
  });

  testWidgets('with the update check wired to a dead network the same flow still works, with one request at most', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final attempts = <String>[];
    HttpOverrides.global = _ThrowingHttpOverrides(attempts);
    addTearDown(() => HttpOverrides.global = null);
    final net = Net(client: MockClient((r) async {
      attempts.add('MockClient ${r.url.path}');
      throw http.ClientException('offline');
    }));
    final updates = UpdateController(
      updater: DownloadPageUpdater(net: net, platformKey: 'android', downloadDirectory: Directory.systemTemp),
      settings: SettingsStore(),
    );
    final c = newController();
    final saver = c.saver as FakeGallerySaver;
    await tester.runAsync(() async {
      await loadAppFonts();
      await c.init();
    });
    addTearDown(c.dispose);
    setPhone(tester);
    await tester.pumpWidget(themed(
        HomeScreen(controller: c, updates: updates, actions: homeActions(c, updates: updates)), Brightness.light));
    await tester.pump();
    await tester.runAsync(() async {
      await c.addPhotos([picked('a.jpg', png(60, 40)), picked('b.jpg', png(40, 60)), picked('c.jpg', png(50, 50))]);
      await c.whenIdle();
    });
    // Let the start-up check (3 seconds after the first frame) run and fail.
    await tester.pump(const Duration(seconds: 4));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await c.saveAll();
    });
    expect(c.message, startsWith('Saved 3 photos'));
    expect(saver.names.length, 3);
    expect(attempts.length, lessThanOrEqualTo(1));
    expect(attempts.where((a) => !a.contains('latest.json')), isEmpty);
    // No box, no toast: offline is quiet.
    expect(find.text('Update available'), findsNothing);
    expect(find.textContaining("You're offline"), findsNothing);
    expect(updates.state, isA<UpdateOffline>());
    await tester.pumpWidget(const SizedBox());
  });
}
