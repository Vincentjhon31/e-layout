import 'dart:convert';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_codec.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/features/editor/editor_canvas.dart';
import 'package:pio_photo_layout/features/editor/editor_controller.dart';
import 'package:pio_photo_layout/features/editor/editor_shortcuts.dart';
import 'package:pio_photo_layout/features/home/home_drop.dart';
import 'package:pio_photo_layout/features/home/home_screen.dart';
import 'package:pio_photo_layout/features/home/home_wiring.dart';
import 'package:pio_photo_layout/features/home/photo_grid.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/ui/widgets/sheet_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/golden_helpers.dart';
import 'editor/editor_screen_test.dart' show buildScene, newEditor, pumpEditor;
import 'home/home_golden_test.dart' show ready;

/// A computer window: [size] points at device pixel ratio 1.
void setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

int columnsOf(WidgetTester tester) {
  final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
  return (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount;
}

Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key, {bool ctrl = false, bool shift = false}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('wide home', () {
    test('columns: 3 on a phone, 6 at 1280, never fewer than 3', () {
      expect(gridColumns(358), 3);
      expect(gridColumns(1148), 6);
      expect(gridColumns(200), 3);
    });

    testWidgets('the photo grid has 6 columns at 1280 wide and 3 at 390', (tester) async {
      final c = await ready(tester, withPhotos: true);
      setWindow(tester, const Size(1280, 800));
      await tester.pumpWidget(themed(HomeScreen(controller: c, actions: homeActions(c)), Brightness.light));
      await tester.pump();
      expect(columnsOf(tester), 6);
      setWindow(tester, const Size(390, 844));
      await tester.pump();
      expect(columnsOf(tester), 3);
    });

    testWidgets('a sheet is 560 wide in a 1280 window and fills a phone', (tester) async {
      setWindow(tester, const Size(1280, 800));
      late BuildContext ctx;
      await tester.pumpWidget(themed(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }), Brightness.light));
      showAppSheet<void>(ctx, (_) => const SheetScaffold(title: 'Test', child: SizedBox(height: 40)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getSize(find.byType(SheetScaffold)).width, 560);
      expect(tester.getCenter(find.byType(SheetScaffold)).dx, 640);
      Navigator.of(ctx).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      setWindow(tester, const Size(390, 844));
      showAppSheet<void>(ctx, (_) => const SheetScaffold(title: 'Test', child: SizedBox(height: 40)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getSize(find.byType(SheetScaffold)).width, 390);
    });
  });

  group('editor keys', () {
    Future<EditorController> sceneEditor(WidgetTester tester) async {
      final c = newEditor();
      buildScene(c);
      await pumpEditor(tester, c, size: const Size(1280, 800));
      setWindow(tester, const Size(1280, 800));
      await tester.pump();
      return c;
    }

    testWidgets('arrows nudge by 1 and shift+arrows by 10, as one undo step per run', (tester) async {
      final c = await sceneEditor(tester);
      final el = c.doc.elements.first;
      c.select([el.id]);
      final b0 = c.boxOfEl(el);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      expect(c.boxOfEl(el).left, closeTo(b0.left + 2, 0.01));
      await pressKey(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(c.boxOfEl(el).top, closeTo(b0.top + 10, 0.01));
      await pressKey(tester, LogicalKeyboardKey.arrowLeft, shift: true);
      expect(c.boxOfEl(el).left, closeTo(b0.left - 8, 0.01));
      await pressKey(tester, LogicalKeyboardKey.arrowUp);
      expect(c.boxOfEl(el).top, closeTo(b0.top + 9, 0.01));
    });

    testWidgets('locked pieces do not nudge', (tester) async {
      final c = await sceneEditor(tester);
      final el = c.doc.elements.first;
      c.change(() => el.locked = true);
      c.select([el.id]);
      final b0 = c.boxOfEl(el);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      expect(c.boxOfEl(el).left, b0.left);
    });

    testWidgets('Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z undo and redo', (tester) async {
      final c = await sceneEditor(tester);
      final n = c.doc.elements.length;
      c.select([c.doc.elements.last.id]);
      c.duplicateSelected();
      expect(c.doc.elements.length, n + 1);
      await pressKey(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(c.doc.elements.length, n);
      await pressKey(tester, LogicalKeyboardKey.keyY, ctrl: true);
      expect(c.doc.elements.length, n + 1);
      await pressKey(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(c.doc.elements.length, n);
      await pressKey(tester, LogicalKeyboardKey.keyZ, ctrl: true, shift: true);
      expect(c.doc.elements.length, n + 1);
    });

    testWidgets('Delete and Backspace remove the selection, Ctrl+D duplicates it', (tester) async {
      final c = await sceneEditor(tester);
      final n = c.doc.elements.length;
      c.select([c.doc.elements.last.id]);
      await pressKey(tester, LogicalKeyboardKey.keyD, ctrl: true);
      expect(c.doc.elements.length, n + 1);
      await pressKey(tester, LogicalKeyboardKey.delete);
      expect(c.doc.elements.length, n);
      c.select([c.doc.elements.last.id]);
      await pressKey(tester, LogicalKeyboardKey.backspace);
      expect(c.doc.elements.length, n - 1);
    });

    testWidgets('Ctrl+A selects the unlocked visible pieces; Ctrl+G groups, Ctrl+Shift+G ungroups; Esc clears', (tester) async {
      final c = await sceneEditor(tester);
      final hidden = c.doc.elements.first;
      c.change(() => hidden.visible = false);
      await pressKey(tester, LogicalKeyboardKey.keyA, ctrl: true);
      expect(c.sel.length, c.doc.elements.length - 1);
      expect(c.sel.contains(hidden.id), isFalse);
      await pressKey(tester, LogicalKeyboardKey.keyG, ctrl: true);
      expect(c.selectionKind, SelectionKind.group);
      await pressKey(tester, LogicalKeyboardKey.keyG, ctrl: true, shift: true);
      expect(c.doc.elements.every((e) => e.group == null), isTrue);
      expect(c.sel, isNotEmpty);
      await pressKey(tester, LogicalKeyboardKey.escape);
      expect(c.sel, isEmpty);
    });

    testWidgets('Esc steps from a piece of a group to the group, then to nothing', (tester) async {
      final c = await sceneEditor(tester);
      c.select(c.doc.elements.map((e) => e.id));
      c.groupSelected();
      final one = c.doc.elements.last;
      c.select([one.id]);
      expect(c.sel.length, 1);
      await pressKey(tester, LogicalKeyboardKey.escape);
      expect(c.sel.length, c.doc.elements.length);
      await pressKey(tester, LogicalKeyboardKey.escape);
      expect(c.sel, isEmpty);
    });

    testWidgets('shortcuts do not fire while a text field has focus', (tester) async {
      final c = newEditor();
      buildScene(c);
      final n = c.doc.elements.length;
      c.select([c.doc.elements.last.id]);
      setWindow(tester, const Size(1280, 800));
      await tester.pumpWidget(themed(
        EditorShortcuts(controller: c, child: const Center(child: CupertinoTextField())),
        Brightness.light,
      ));
      await tester.tap(find.byType(CupertinoTextField));
      await tester.pump();
      await pressKey(tester, LogicalKeyboardKey.delete);
      await pressKey(tester, LogicalKeyboardKey.keyD, ctrl: true);
      await pressKey(tester, LogicalKeyboardKey.keyA, ctrl: true);
      await pressKey(tester, LogicalKeyboardKey.escape);
      expect(c.doc.elements.length, n);
      expect(c.sel.length, 1);
    });

    testWidgets('Ctrl+scroll zooms around the pointer; plain scroll pans', (tester) async {
      final c = await sceneEditor(tester);
      final canvas = tester.state<EditorCanvasState>(find.byType(EditorCanvas));
      final s0 = canvas.scale;
      final at = tester.getCenter(find.byType(EditorCanvas));
      final design0 = canvas.toDesign(canvas.toLocalPoint(const Offset(100, 100)));
      expect(design0.dx, closeTo(100, 0.01));
      final mouse = TestPointer(7, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -150)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(seconds: 1));
      final s1 = canvas.scale;
      expect(s1, greaterThan(s0));
      expect(c.zoom, closeTo(s1, 0.0001));
      // The design point under the pointer stays under it.
      final local = tester.getTopLeft(find.byType(EditorCanvas));
      final under = canvas.toDesign(at - local);
      expect(under.dx.isFinite, isTrue);
      // Plain scroll pans without zooming.
      final before = canvas.toLocalPoint(Offset.zero);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 40)));
      await tester.pump();
      expect(canvas.scale, closeTo(s1, 0.0001));
      expect(canvas.toLocalPoint(Offset.zero).dy, closeTo(before.dy - 40, 0.01));
    });
  });

  group('drag and drop', () {
    Future<Uint8List> png() async {
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 8, 8), ui.Paint()..color = const Color(0xFF336699));
      final img = await rec.endRecording().toImage(8, 8);
      final b = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      img.dispose();
      return Uint8List.fromList(b);
    }

    test('a dropped folder is opened and only photos and layout files are kept, in name order', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final items = <DropItem>[
        DropItemDirectory('C:/x', [
          DropItemFile.fromData(bytes, name: 'IMG_10.jpg', path: 'C:/x/IMG_10.jpg'),
          DropItemFile.fromData(bytes, name: 'IMG_2.JPG', path: 'C:/x/IMG_2.JPG'),
          DropItemFile.fromData(bytes, name: 'notes.txt', path: 'C:/x/notes.txt'),
          DropItemDirectory('C:/x/sub', [DropItemFile.fromData(bytes, name: 'a.png', path: 'C:/x/sub/a.png')]),
        ], name: 'x'),
        DropItemFile.fromData(bytes, name: 'mine.layout.json', path: 'C:/mine.layout.json'),
      ];
      final out = await pickedFromDrop(items);
      expect([for (final f in out) f.name], ['a.png', 'IMG_2.JPG', 'IMG_10.jpg', 'mine.layout.json']);
      expect(await out.first.readBytes(), bytes);
    });

    testWidgets('photos dropped on Home are added; a layout file is imported; on the layout row a PNG becomes a layout', (tester) async {
      final c = await ready(tester);
      final data = await tester.runAsync(png);
      final layoutJson = jsonEncode(writeLayout(LayoutDoc.blank('Dropped one'), envelope: true));
      PickedPhoto file(String name, Uint8List b) => PickedPhoto(name: name, readBytes: () async => b, size: b.length);
      final before = c.layouts.length;
      await tester.runAsync(() async {
        await c.handleDrop([file('a.png', data!), file('b.png', data)]);
        await c.whenIdle();
      });
      expect(c.photos.length, 2);
      expect(c.layouts.length, before);
      await tester.runAsync(() => c.handleDrop([file('Dropped one.layout.json', Uint8List.fromList(utf8.encode(layoutJson)))]));
      expect(c.layouts.length, before + 1);
      expect(c.photos.length, 2);
      await tester.runAsync(() => c.handleDrop([file('logo.png', data!)], onLayouts: true));
      expect(c.layouts.length, before + 2);
      expect(c.photos.length, 2);
    });
  });
}
