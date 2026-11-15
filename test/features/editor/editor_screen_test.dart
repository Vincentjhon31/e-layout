import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/model/layout_ops.dart' as ops;
import 'package:pio_photo_layout/core/render/layout_prep.dart';
import 'package:pio_photo_layout/features/editor/editor_canvas.dart';
import 'package:pio_photo_layout/features/editor/editor_controller.dart';
import 'package:pio_photo_layout/features/editor/editor_screen.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';

import '../../ui/golden_helpers.dart';

EditorController newEditor() {
  final c = EditorController(
    doc: LayoutDoc.blank('PIO footer'),
    prep: LayoutPrep(),
    onSave: (d) async {},
  );
  _made.add(c);
  return c;
}

/// A made-up scene: footer band, a heading and a seal icon.
void buildScene(EditorController c) {
  c.addShape(kShapePresets.firstWhere((p) => p.label == 'Footer band'));
  final t = c.addText(kTextPresets.firstWhere((p) => p.label == 'Heading'));
  c.change(() {
    t.text = 'Municipal Office';
    t.fill.color = '#FFFFFF';
  });
  c.fitText(c.byId(t.id)!);
  final icon = c.addIcon('shield');
  ops.place(icon, const Rect.fromLTWH(60, 90, 120, 120), c.frameH);
  c.select([]);
}

Future<Uint8List> samplePng() async {
  final rec = ui.PictureRecorder();
  final cv = ui.Canvas(rec);
  cv.drawCircle(const Offset(100, 100), 96, ui.Paint()..color = const Color(0xFFF2C230));
  cv.drawCircle(const Offset(100, 100), 60, ui.Paint()..color = const Color(0xFF165A8C));
  final img = await rec.endRecording().toImage(200, 200);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  img.dispose();
  return Uint8List.fromList(bytes);
}

Future<void> pumpEditor(WidgetTester tester, EditorController c,
    {Brightness brightness = Brightness.light, Size size = const Size(390, 844), PhotoPicker? picker}) async {
  setPhone(tester, size: size);
  await tester.pumpWidget(themed(EditorScreen(controller: c, picker: picker ?? FakePhotoPicker()), brightness));
  await tester.pump();
}

Finder strip() => find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.horizontal);

/// Scrolls the tool strip until the tile is wholly on screen, then taps it.
Future<void> tapStripTile(WidgetTester tester, String name) async {
  final f = find.text(name);
  for (var i = 0; i < 20; i++) {
    if (f.evaluate().isNotEmpty) {
      final x = tester.getCenter(f).dx;
      if (x > 30 && x < 350) break;
    }
    await tester.drag(strip(), const Offset(-100, 0));
    await tester.pumpAndSettle();
  }
  await tester.tap(f);
}

Offset screenOf(WidgetTester tester, Offset design) =>
    tester.state<EditorCanvasState>(find.byType(EditorCanvas)).toScreen(design);

/// A widget test that ends by writing any pending autosave (no timer left behind).
void etest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    // Controllers made by the test are flushed through this hook.
    for (final c in _made) {
      await tester.runAsync(() => c.close());
    }
    _made.clear();
  });
}

final List<EditorController> _made = [];

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  etest('a drag on a piece moves it', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = newEditor();
    addTearDown(c.dispose);
    final el = c.addShape(kShapePresets.firstWhere((p) => p.label == 'Rectangle'));
    c.select([]);
    await pumpEditor(tester, c);
    final b0 = c.boxOfEl(el);
    final from = screenOf(tester, b0.center);
    await tester.dragFrom(from, const Offset(60, 40));
    await tester.pump();
    final b1 = c.boxOfEl(c.byId(el.id)!);
    expect(b1.left, greaterThan(b0.left + 20));
    expect(b1.top, greaterThan(b0.top + 10));
    expect(c.sel, [el.id]);
    expect(c.canUndo, isTrue);
  });

  etest('a tap on empty space deselects', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = newEditor();
    addTearDown(c.dispose);
    final el = c.addShape(kShapePresets.firstWhere((p) => p.label == 'Rectangle'));
    await pumpEditor(tester, c);
    expect(c.sel, [el.id]);
    await tester.tapAt(screenOf(tester, const Offset(40, 40)));
    await tester.pump();
    expect(c.sel, isEmpty);
  });

  etest('the strip offers only working tools', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = newEditor();
    addTearDown(c.dispose);
    await pumpEditor(tester, c);
    for (final label in ['Text', 'Shape', 'Icon', 'Picture', 'Layers']) {
      expect(find.text(label, skipOffstage: false), findsOneWidget, reason: label);
    }
    expect(find.text('Duplicate', skipOffstage: false), findsNothing);
    c.addText(kTextPresets.first);
    await tester.pump();
    for (final label in ['Edit', 'Font', 'Colour', 'Duplicate', 'Delete']) {
      await tester.scrollUntilVisible(find.text(label), 100, scrollable: strip());
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Shape', skipOffstage: false), findsNothing);
  });

  etest('Duplicate and Delete work and undo brings the piece back', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = newEditor();
    addTearDown(c.dispose);
    c.addShape(kShapePresets.first);
    await pumpEditor(tester, c);
    await tapStripTile(tester, 'Duplicate');
    await tester.pump();
    expect(c.doc.elements.length, 2);
    await tapStripTile(tester, 'Delete');
    await tester.pump();
    expect(c.doc.elements.length, 1);
    await tester.tap(find.bySemanticsLabel('Undo'));
    await tester.pump();
    expect(c.doc.elements.length, 2);
    await tester.tap(find.bySemanticsLabel('Redo'));
    await tester.pump();
    expect(c.doc.elements.length, 1);
  });

  etest('double-tap on a text opens the edit sheet and typing changes the words', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = newEditor();
    addTearDown(c.dispose);
    final el = c.addText(kTextPresets.firstWhere((p) => p.label == 'Heading'));
    c.select([]);
    await pumpEditor(tester, c);
    final at = screenOf(tester, c.boxOfEl(el).center);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(find.text('Edit text'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoTextField), 'Hello office');
    await tester.pump();
    expect(c.byId(el.id)!.text, 'Hello office');
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(find.text('Edit text'), findsNothing);
  });

  etest('the shape buttons change the frame', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = newEditor();
    addTearDown(c.dispose);
    await pumpEditor(tester, c);
    expect(c.ratioName, 'landscape');
    await tester.tap(find.text('Portrait'));
    await tester.pumpAndSettle();
    expect(c.ratioName, 'portrait');
  });

  etest('adding a text from the sheet', (tester) async {
    await tester.runAsync(loadAppFonts);
    final c = newEditor();
    addTearDown(c.dispose);
    await pumpEditor(tester, c);
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heading'));
    await tester.pumpAndSettle();
    expect(c.doc.elements.length, 1);
    expect(c.doc.elements.single.type, ElementType.text);
  });

  group('goldens', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      etest('nothing selected ${b.name}', (tester) async {
        await tester.runAsync(loadAppFonts);
        final c = newEditor();
        addTearDown(c.dispose);
        buildScene(c);
        await pumpEditor(tester, c, brightness: b);
        await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/editor_none_${b.name}.png'));
      });
    }

    etest('text selected', (tester) async {
      await tester.runAsync(loadAppFonts);
      final c = newEditor();
      addTearDown(c.dispose);
      buildScene(c);
      c.select([c.doc.elements.firstWhere((e) => e.type == ElementType.text).id]);
      await pumpEditor(tester, c);
      await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/editor_text.png'));
    });

    etest('picture selected', (tester) async {
      await tester.runAsync(loadAppFonts);
      final c = newEditor();
      addTearDown(c.dispose);
      buildScene(c);
      await tester.runAsync(() async => c.addPicture('crest.png', await samplePng()));
      await pumpEditor(tester, c, brightness: Brightness.dark);
      await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/editor_picture.png'));
    });

    etest('small phone', (tester) async {
      await tester.runAsync(loadAppFonts);
      final c = newEditor();
      addTearDown(c.dispose);
      buildScene(c);
      c.select([c.doc.elements.firstWhere((e) => e.type == ElementType.text).id]);
      await pumpEditor(tester, c, size: const Size(320, 568));
      await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/editor_small.png'));
    });

    etest('text sheet', (tester) async {
      await tester.runAsync(loadAppFonts);
      final c = newEditor();
      addTearDown(c.dispose);
      buildScene(c);
      await pumpEditor(tester, c);
      await tester.tap(find.text('Shape'));
      await tester.pumpAndSettle();
      await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/editor_add_shape.png'));
    });
  });
}
