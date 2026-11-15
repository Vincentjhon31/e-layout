import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/features/editor/editor_screen.dart';
import 'package:pio_photo_layout/features/editor/open_editor.dart';
import 'package:pio_photo_layout/features/home/home_screen.dart';
import 'package:pio_photo_layout/features/home/home_wiring.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/golden_helpers.dart';
import '../home/home_golden_test.dart' show newController;

void main() {
  testWidgets('New layout opens the editor; changes are kept after Done', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = newController();
    await tester.runAsync(() async {
      await loadAppFonts();
      await c.init();
    });
    addTearDown(c.dispose);
    final before = c.layouts.length;
    setPhone(tester);
    await tester.pumpWidget(themed(
        HomeScreen(controller: c, actions: homeActions(c, openEditor: openEditorFor(c, FakePhotoPicker()))),
        Brightness.light));
    await tester.pump();

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
    expect(c.layouts.length, before + 1);

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
    expect(find.byType(EditorScreen), findsNothing);
    final stored = c.layouts.last.doc;
    expect(stored.elements.length, 1);
    expect(await c.layoutStore.loadAll().then((l) => l.any((d) => d.id == stored.id && d.elements.length == 1)), isTrue);
  });
}
