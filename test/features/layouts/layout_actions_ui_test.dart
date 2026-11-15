import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/features/home/home_screen.dart';
import 'package:pio_photo_layout/features/home/home_wiring.dart';
import 'package:pio_photo_layout/features/home/layout_strip.dart';
import 'package:pio_photo_layout/features/layouts/layout_actions.dart';
import 'package:pio_photo_layout/platform/file_sharer.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/platform/temp_files_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/golden_helpers.dart';

const _shot = Key('shot');

Future<HomeController> _ready(WidgetTester tester, {bool mine = false}) async {
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
    if (mine) {
      final item = await c.addLayout(LayoutDoc.blank('Mine'));
      await c.selectLayout(item.id);
    }
  });
  addTearDown(c.dispose);
  return c;
}

Future<BuildContext> _home(WidgetTester tester, HomeController c, Brightness b) async {
  setPhone(tester);
  await tester.pumpWidget(
      RepaintBoundary(key: _shot, child: themed(HomeScreen(controller: c, actions: homeActions(c)), b)));
  await tester.pump();
  return tester.element(find.byType(LayoutStrip));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a layout made on this phone offers every action and removes after a confirmation', (tester) async {
    final c = await _ready(tester, mine: true);
    final ctx = await _home(tester, c, Brightness.light);
    final mine = c.current!;
    showLayoutActions(ctx, c, mine, openEditor: (_, _) async {});
    await tester.pumpAndSettle();
    for (final label in ['Edit layout', 'Rename', 'Duplicate', 'Share layout file', 'Remove', 'Cancel']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove "Mine"?'), findsOneWidget);
    expect(c.layouts.contains(mine), isTrue, reason: 'nothing is removed before the confirmation');
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(c.layouts.contains(mine), isFalse);
  });

  testWidgets('rename goes through a text prompt; office layouts have no Remove', (tester) async {
    final c = await _ready(tester, mine: true);
    final ctx = await _home(tester, c, Brightness.light);
    final mine = c.current!;
    showLayoutActions(ctx, c, mine);
    await tester.pumpAndSettle();
    expect(find.text('Edit layout'), findsNothing, reason: 'no editor given');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'Street fair');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(mine.doc.name, 'Street fair');

    showLayoutActions(ctx, c, c.layouts.first);
    await tester.pumpAndSettle();
    expect(find.text('Office layout. Changes are made to a copy.'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
  });

  testWidgets('the add card offers a new layout, a layout file or a picture', (tester) async {
    final c = await _ready(tester);
    final ctx = await _home(tester, c, Brightness.light);
    var opened = 0;
    showAddLayout(ctx, c, openEditor: (_, _) async => opened++);
    await tester.pumpAndSettle();
    for (final label in ['New layout', 'Import a layout file', 'Use a picture', 'Cancel']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.runAsync(() async {
      await tester.tap(find.text('New layout'));
      await tester.pump();
      for (var i = 0; i < 20 && opened == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(c.current!.doc.name, 'New layout');
    expect(c.current!.builtin, isFalse);
  });

  testWidgets('layout actions golden', (tester) async {
    final c = await _ready(tester);
    final ctx = await _home(tester, c, Brightness.light);
    showLayoutActions(ctx, c, c.current!, openEditor: (_, _) async {});
    await tester.pumpAndSettle();
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/layout_actions_light.png'));
  });

  testWidgets('add layout golden, dark', (tester) async {
    final c = await _ready(tester);
    final ctx = await _home(tester, c, Brightness.dark);
    showAddLayout(ctx, c, openEditor: (_, _) async {});
    await tester.pumpAndSettle();
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/add_layout_dark.png'));
  });

  testWidgets('remove confirmation golden, dark', (tester) async {
    final c = await _ready(tester, mine: true);
    final ctx = await _home(tester, c, Brightness.dark);
    confirmRemoveLayout(ctx, c, c.current!);
    await tester.pumpAndSettle();
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/remove_layout_dark.png'));
  });
}
