import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/features/home/home_screen.dart';
import 'package:pio_photo_layout/features/home/home_wiring.dart';
import 'package:pio_photo_layout/features/home/options_sheet.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/ui/widgets/sheet_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/golden_helpers.dart';
import 'editor/editor_screen_test.dart' show buildScene, newEditor, pumpEditor;
import 'home/home_golden_test.dart' show newController, samplePhotos;

/// Goldens for a 1280x800 window at device pixel ratio 1.
void window(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('wide: home with 12 photos', (tester) async {
    final c = newController();
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      await loadAppFonts();
      await c.init();
      final six = await samplePhotos();
      final twelve = [
        ...six,
        for (var i = 0; i < six.length; i++)
          PickedPhoto(name: 'IMG_${2100 + i}.jpg', readBytes: six[i].readBytes, size: six[i].size),
      ];
      await c.addPhotos(twelve);
      await c.whenIdle();
    });
    window(tester);
    await tester.pumpWidget(themed(HomeScreen(controller: c, actions: homeActions(c)), Brightness.light));
    await tester.pump();
    await expectLater(find.byType(HomeScreen), matchesGoldenFile('goldens/wide_home.png'));
  });

  testWidgets('wide: editor with a piece selected', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = newEditor();
    buildScene(c);
    c.select([c.doc.elements[1].id]);
    window(tester);
    await pumpEditor(tester, c, size: const Size(1280, 800));
    window(tester);
    await tester.pump();
    await expectLater(find.byType(CupertinoPageScaffold), matchesGoldenFile('goldens/wide_editor.png'));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('wide: options sheet', (tester) async {
    final c = newController();
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      await loadAppFonts();
      await c.init();
    });
    window(tester);
    late BuildContext ctx;
    await tester.pumpWidget(themed(
      CupertinoPageScaffold(
        child: Builder(builder: (context) {
          ctx = context;
          return HomeScreen(controller: c, actions: homeActions(c));
        }),
      ),
      Brightness.light,
    ));
    await tester.pump();
    showAppSheet<void>(ctx, (_) => OptionsSheet(controller: c));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/wide_options.png'));
  });
}
