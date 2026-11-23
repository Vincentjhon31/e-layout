import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/features/editor/editor_controller.dart';
import 'package:pio_photo_layout/features/editor/editor_screen.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart' show PhotoItem, PhotoStatus;
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';

import '../../ui/golden_helpers.dart';
import 'editor_screen_test.dart' show buildScene, newEditor, samplePng;

ShapePreset shapeP(String label) => kShapePresets.firstWhere((p) => p.label == label);

Future<void> pump(WidgetTester tester, EditorController c,
    {Brightness b = Brightness.light,
    Size size = const Size(390, 844),
    GallerySaver? gallery,
    List<PhotoItem> photos = const [],
    VoidCallback? onMoreFonts}) async {
  setPhone(tester, size: size);
  await tester.pumpWidget(themed(
      EditorScreen(controller: c, picker: FakePhotoPicker(), gallery: gallery, photos: photos, onMoreFonts: onMoreFonts ?? () {}), b));
  await tester.pump();
}

/// Taps a tile of the tool strip, scrolling the strip to it first.
Future<void> tapTile(WidgetTester tester, String name) async {
  final strip = find.descendant(of: find.byKey(const ValueKey('tool-strip')), matching: find.byType(Scrollable)).first;
  final f = find.text(name);
  for (var i = 0; i < 20; i++) {
    var dir = -100.0;
    if (f.evaluate().isNotEmpty) {
      final x = tester.getCenter(f).dx;
      if (x > 30 && x < tester.view.physicalSize.width / 2 - 30) break;
      if (x <= 30) dir = 100;
    }
    await tester.drag(strip, Offset(dir, 0));
    await tester.pumpAndSettle();
  }
  await tester.tap(f);
}

/// A tab of the panel's segmented control (the same word may also be a tile or a title).
Finder tab(String name) => find.descendant(
    of: find.byWidgetPredicate((w) => w is CupertinoSlidingSegmentedControl<String>), matching: find.text(name));

/// How far the open panel can still scroll: zero means every control is in view.
double panelOverflow(WidgetTester tester) {
  final st = tester.state<ScrollableState>(find
      .descendant(of: find.byKey(const ValueKey('panel-scroll')), matching: find.byType(Scrollable))
      .first);
  return st.position.maxScrollExtent;
}

/// A widget test that closes the controllers it made, so no autosave timer is left.
void ptest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await tester.runAsync(loadAppFonts);
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      for (final c in madeControllers) {
        await c.close();
      }
    });
    madeControllers.clear();
  });
}

final List<EditorController> madeControllers = [];

EditorController editor() {
  final c = newEditor();
  madeControllers.add(c);
  return c;
}

void main() {
  group('controller', () {
    test('reordering moves a piece and keeps a group together', () {
      final c = newEditor();
      final a = c.addShape(shapeP('Rectangle'));
      final b = c.addShape(shapeP('Circle'));
      final d = c.addShape(shapeP('Triangle'));
      // Display (top first): d, b, a. Drop d at the bottom.
      c.reorderUnit(0, 2);
      expect([for (final e in c.doc.elements) e.id], [d.id, a.id, b.id]);
      c.undo();
      expect([for (final e in c.doc.elements) e.id], [a.id, b.id, d.id]);
      // Group b and d, then put a on top of the group.
      c.select([b.id, d.id]);
      c.groupSelected();
      c.select([]);
      c.reorderUnit(1, 0);
      final order = [for (final e in c.doc.elements) e.id];
      expect(order.last, a.id);
      expect(order.sublist(0, 2).toSet(), {b.id, d.id});
      c.close();
    });

    test('renaming a piece to nothing keeps the old name', () {
      final c = newEditor();
      final el = c.addShape(shapeP('Rectangle'));
      c.renamePiece(el.id, '   ');
      expect(c.byId(el.id)!.name, 'Rectangle');
      c.renamePiece(el.id, 'Banner');
      expect(c.byId(el.id)!.name, 'Banner');
      c.close();
    });

    test('hiding and locking are undoable steps', () {
      final c = newEditor();
      final el = c.addShape(shapeP('Rectangle'));
      c.toggleVisible(el.id);
      expect(c.byId(el.id)!.visible, isFalse);
      c.toggleLocked(el.id);
      expect(c.byId(el.id)!.locked, isTrue);
      c.undo();
      expect(c.byId(el.id)!.locked, isFalse);
      c.close();
    });

    test('crop to a ratio sets the fit and the ratio', () {
      final c = newEditor();
      c.setFit(DocFit.crop, ratio: 1);
      expect(c.doc.fit, DocFit.crop);
      expect(c.frameH, c.doc.width);
      c.close();
    });
  });

  group('panels', () {
    ptest('a slider drag is one undo step', (tester) async {
      final c = editor();
      c.addShape(shapeP('Rectangle'));
      await pump(tester, c);
      await tapTile(tester, 'Opacity');
      await tester.pumpAndSettle();
      final before = c.historyLength;
      final slider = find.byType(CupertinoSlider);
      // The thumb sits at the right end (opacity 100%): grab it and pull left.
      final r = tester.getRect(slider);
      final g = await tester.startGesture(Offset(r.right - 18, r.center.dy));
      for (var i = 1; i <= 12; i++) {
        await g.moveBy(const Offset(-12, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pump();
      expect(c.single!.opacity, lessThan(0.9));
      expect(c.historyLength, before + 1);
      c.undo();
      expect(c.single!.opacity, 1);
    });

    ptest('Fill: a swatch changes the colour; None removes the fill', (tester) async {
      final c = editor();
      c.addShape(shapeP('Rectangle'));
      await pump(tester, c);
      await tapTile(tester, 'Fill');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Colour #B42B25'));
      await tester.pump();
      expect(c.single!.fill.color, '#B42B25');
      await tester.tap(find.text('None'));
      await tester.pump();
      expect(c.single!.fill.type, FillType.none);
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      expect(find.text('Fill'), findsOneWidget);
      expect(find.byKey(const ValueKey('panel-scroll')), findsNothing);
    });

    ptest('Font: choosing a family and Bold changes the text and re-measures it', (tester) async {
      final c = editor();
      final el = c.addText(kTextPresets.firstWhere((p) => p.label == 'Body text'));
      final w0 = c.boxOfEl(el).width;
      await pump(tester, c);
      await tapTile(tester, 'Font');
      await tester.pumpAndSettle();
      await tester.tap(tab('Style'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bold'));
      await tester.pump();
      expect(c.single!.weight, 700);
      expect(c.boxOfEl(c.single!).width, greaterThan(w0));
      await tester.tap(tab('Font'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Barlow'));
      await tester.pump();
      expect(c.single!.font, 'Barlow');
    });

    ptest('Layout settings: crop to one shape', (tester) async {
      final c = editor();
      await pump(tester, c);
      await tapTile(tester, 'Layout');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crop to one shape'));
      await tester.pumpAndSettle();
      expect(c.doc.fit, DocFit.crop);
      await tester.tap(find.text('1:1 square'));
      await tester.pumpAndSettle();
      expect(c.doc.ratio, 1);
    });

    ptest('Layers: tap selects, eye hides', (tester) async {
      final c = editor();
      final a = c.addShape(shapeP('Rectangle'));
      c.addShape(shapeP('Circle'));
      await pump(tester, c);
      await tapTile(tester, 'Layers');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rectangle').last);
      await tester.pump();
      expect(c.sel, [a.id]);
      await tester.tap(find.bySemanticsLabel('Hide').last);
      await tester.pump();
      expect(c.byId(a.id)!.visible, isFalse);
    });
  });

  group('tools', () {
    ptest('Font panel: the last row of the list is More fonts', (tester) async {
      final c = editor();
      c.addText(kTextPresets.firstWhere((p) => p.label == 'Body text'));
      var opened = 0;
      await pump(tester, c, onMoreFonts: () => opened++);
      await tapTile(tester, 'Font');
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const ValueKey('font-list')), const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More fonts'));
      expect(opened, 1);
    });

    for (final size in const [Size(390, 844), Size(320, 568)]) {
      ptest('Font panel: every control is in view on ${size.width.toInt()} x ${size.height.toInt()}', (tester) async {
        final c = editor();
        c.addText(kTextPresets.firstWhere((p) => p.label == 'Body text'));
        await pump(tester, c, size: size);
        await tapTile(tester, 'Font');
        await tester.pumpAndSettle();
        final panel = tester.getRect(find.byKey(const ValueKey('panel-scroll')));
        for (final t in ['Font', 'Style', 'Size']) {
          await tester.tap(tab(t));
          await tester.pumpAndSettle();
          expect(panelOverflow(tester), 0, reason: 'the $t page needs no scrolling');
        }
        // The first three fonts are whole rows.
        await tester.tap(tab('Font'));
        await tester.pumpAndSettle();
        for (final f in ['Barlow', 'Barlow Condensed', 'Montserrat']) {
          final r = tester.getRect(find.text(f));
          expect(r.bottom, lessThanOrEqualTo(panel.bottom), reason: '$f is fully visible');
        }
      });
    }

    ptest('Gradient: 2 to 8 stops through the buttons', (tester) async {
      final c = editor();
      final el = c.addShape(shapeP('Rectangle'));
      await pump(tester, c);
      await tapTile(tester, 'Fill');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gradient'));
      await tester.pumpAndSettle();
      expect(c.single!.fill.type, FillType.linear);
      expect(c.single!.fill.stops.length, 2);
      expect(find.text('Remove stop'), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.text('Add a stop'));
        await tester.pump();
      }
      expect(c.byId(el.id)!.fill.stops.length, 8);
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.text('Remove stop'));
        await tester.pump();
      }
      expect(c.byId(el.id)!.fill.stops.length, 2);
      await tester.tap(find.text('Radial'));
      await tester.pump();
      expect(c.single!.fill.type, FillType.radial);
    });

    ptest('Position: Stays at Bottom, flip and align', (tester) async {
      final c = editor();
      final el = c.addShape(shapeP('Rectangle'));
      await pump(tester, c);
      await tapTile(tester, 'Position');
      await tester.pumpAndSettle();
      await tester.tap(tab('Stays'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bottom'));
      await tester.pump();
      expect(c.single!.pin, Pin.bottom);
      expect(c.single!.pinAuto, isFalse);
      await tester.tap(tab('Align'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Left'));
      await tester.pump();
      expect(c.boxOfEl(c.single!).left, closeTo(0, 0.01));
      await tester.tap(tab('Turn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flip left-right'));
      await tester.pump();
      expect(c.byId(el.id)!.flipX, isTrue);
    });

    ptest('Effects, Blending and Shadow colour change the piece', (tester) async {
      final c = editor();
      c.addShape(shapeP('Rectangle'));
      await pump(tester, c);
      await tapTile(tester, 'Opacity');
      await tester.pumpAndSettle();
      await tester.tap(tab('Blending'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Multiply'));
      await tester.pump();
      expect(c.single!.blend, 'multiply');
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      await tapTile(tester, 'Effects');
      await tester.pumpAndSettle();
      expect(find.text('Blur'), findsWidgets);
      await tester.tap(tab('Light'));
      await tester.pumpAndSettle();
      expect(find.text('Brightness'), findsOneWidget);
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      await tapTile(tester, 'Shadow');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      await tester.tap(tab('Colour'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Colour #B42B25'));
      await tester.pump();
      expect(c.single!.shadow.color, '#B42B25');
    });

    ptest('Shape and Icon tools change the piece', (tester) async {
      final c = editor();
      final sh = c.addShape(shapeP('Rectangle'));
      await pump(tester, c);
      await tapTile(tester, 'Shape');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Star'));
      await tester.pump();
      expect(c.byId(sh.id)!.shape, ShapeKind.star);
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      final ic = c.addIcon('phone');
      await tester.pump();
      await tapTile(tester, 'Badge');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Square').last);
      await tester.pump();
      expect(c.byId(ic.id)!.iconBg.shape, IconBgShape.square);
    });

    ptest('several pieces: Align and Space evenly tiles', (tester) async {
      final c = editor();
      final a = c.addShape(shapeP('Rectangle'));
      final b = c.addShape(shapeP('Circle'));
      c.addShape(shapeP('Triangle'));
      c.select([for (final e in c.doc.elements) e.id]);
      await pump(tester, c);
      await tapTile(tester, 'Align');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Left'));
      await tester.pump();
      expect(c.boxOfEl(c.byId(a.id)!).left, closeTo(c.boxOfEl(c.byId(b.id)!).left, 0.01));
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      final lefts = [for (final e in c.doc.elements) c.boxOfEl(e).left];
      await tapTile(tester, 'Space');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Across'));
      await tester.pump();
      expect(lefts, isNotEmpty);
    });

    ptest('Save layout as PNG goes to the gallery, 3000 wide', (tester) async {
      final c = editor();
      c.addShape(shapeP('Footer band'));
      final gallery = FakeGallerySaver();
      await pump(tester, c, gallery: gallery);
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save layout as PNG'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pump(const Duration(seconds: 1));
      expect(gallery.names, ['PIO footer.png']);
      expect(gallery.files.single.length, greaterThan(100));
      await tester.pump(const Duration(seconds: 5));
    });

    ptest('Preview on one of the added photos', (tester) async {
      final c = editor();
      c.addShape(shapeP('Footer band'));
      late ui.Image img;
      await tester.runAsync(() async {
        final rec = ui.PictureRecorder();
        ui.Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 40, 60), ui.Paint()..color = const Color(0xFF336699));
        img = await rec.endRecording().toImage(40, 60);
      });
      final item = PhotoItem(1, PickedPhoto(name: 'sample.jpg', readBytes: () async => Uint8List(0)))
        ..status = PhotoStatus.ready
        ..preview = img;
      await pump(tester, c, photos: [item]);
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview on'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sample.jpg'));
      await tester.pumpAndSettle();
      expect(c.preview, PreviewKind.photo);
      expect(c.photo, same(img));
      expect(c.ratioValue, closeTo(40 / 60, 0.001));
    });

    ptest('the strip offers each type its own tools', (tester) async {
      final c = editor();
      c.addIcon('phone');
      await pump(tester, c);
      final strip = find.descendant(of: find.byKey(const ValueKey('tool-strip')), matching: find.byType(Scrollable)).first;
      Future<void> seen(List<String> names) async {
        await tester.drag(strip, const Offset(2000, 0));
        await tester.pumpAndSettle();
        for (final t in names) {
          await tester.scrollUntilVisible(find.text(t), 80, scrollable: strip);
          expect(find.text(t), findsOneWidget, reason: t);
        }
      }

      await seen(['Icon', 'Colour', 'Badge', 'Border', 'Shadow', 'Opacity', 'Position', 'Effects', 'Layers']);
      c.select([c.addShape(shapeP('Circle')).id]);
      await tester.pump();
      await seen(['Shape', 'Fill', 'Border', 'Shadow', 'Opacity', 'Position', 'Effects', 'Layers']);
    });

    ptest('Layers: Select mode picks several and groups them', (tester) async {
      final c = editor();
      final a = c.addShape(shapeP('Rectangle'));
      final b = c.addShape(shapeP('Circle'));
      c.select([]);
      await pump(tester, c);
      await tapTile(tester, 'Layers');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rectangle').last);
      await tester.pump();
      await tester.tap(find.text('Circle').last);
      await tester.pump();
      expect(c.sel.toSet(), {a.id, b.id});
      await tester.tap(find.text('Group').last);
      await tester.pump();
      expect(c.byId(a.id)!.group, isNotNull);
      expect(c.byId(a.id)!.group, c.byId(b.id)!.group);
      await tester.pump(const Duration(seconds: 5)); // the toast's timer
    });
  });

  group('goldens', () {
    ptest('text panel', (tester) async {
      final c = editor();
      buildScene(c);
      c.select([c.doc.elements.firstWhere((e) => e.type == ElementType.text).id]);
      await pump(tester, c);
      await tapTile(tester, 'Font');
      await tester.pumpAndSettle();
      await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/panel_font.png'));
    });

    for (final b in [Brightness.light, Brightness.dark]) {
      ptest('fill panel ${b.name}', (tester) async {
        final c = editor();
        buildScene(c);
        c.select([c.doc.elements.first.id]);
        await pump(tester, c, b: b);
        await tapTile(tester, 'Fill');
        await tester.pumpAndSettle();
        await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/panel_fill_${b.name}.png'));
      });
    }

    ptest('position panel', (tester) async {
      final c = editor();
      buildScene(c);
      c.select([c.doc.elements.firstWhere((e) => e.type == ElementType.icon).id]);
      await pump(tester, c);
      await tapTile(tester, 'Position');
      await tester.pumpAndSettle();
      await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/panel_position.png'));
    });

    ptest('shadow panel small phone', (tester) async {
      final c = editor();
      buildScene(c);
      c.select([c.doc.elements.last.id]);
      await pump(tester, c, size: const Size(320, 568));
      await tapTile(tester, 'Shadow');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/panel_shadow_small.png'));
    });

    ptest('layers sheet with a group', (tester) async {
      final c = editor();
      buildScene(c);
      c.select([c.doc.elements[1].id, c.doc.elements[2].id]);
      c.groupSelected();
      c.select([c.doc.elements.first.id]);
      await pump(tester, c);
      await tapTile(tester, 'Layers');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Group of'));
      await tester.pumpAndSettle();
      await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/layers_sheet.png'));
    });

    ptest('layout settings sheet', (tester) async {
      final c = editor();
      c.setFit(DocFit.crop, ratio: 4 / 5);
      await pump(tester, c);
      await tapTile(tester, 'Layout');
      await tester.pumpAndSettle();
      await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/layout_settings.png'));
    });

    ptest('nothing selected strip', (tester) async {
      final c = editor();
      buildScene(c);
      await pump(tester, c, size: const Size(320, 568));
      await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/strip_small.png'));
    });
  });

  group('goldens 2', () {
    Future<void> shot(WidgetTester tester, String name) =>
        expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/$name.png'));

    for (final size in const [Size(390, 844), Size(320, 568)]) {
      for (final t in ['Font', 'Style', 'Size']) {
        ptest('font ${t.toLowerCase()} ${size.width.toInt()}', (tester) async {
          final c = editor();
          buildScene(c);
          c.select([c.doc.elements.firstWhere((e) => e.type == ElementType.text).id]);
          await pump(tester, c, size: size);
          await tapTile(tester, 'Font');
          await tester.pumpAndSettle();
          await tester.tap(tab(t));
          await tester.pumpAndSettle();
          await shot(tester, 'font_${t.toLowerCase()}_${size.width.toInt()}');
        });
      }
    }

    ptest('gradient fill', (tester) async {
      final c = editor();
      buildScene(c);
      final band = c.doc.elements.first;
      c.select([band.id]);
      await pump(tester, c);
      await tapTile(tester, 'Fill');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gradient'));
      await tester.pumpAndSettle();
      await shot(tester, 'gradient_stops');
      await tester.tap(tab('Colour'));
      await tester.pumpAndSettle();
      await shot(tester, 'gradient_colour');
    });

    ptest('position stays', (tester) async {
      final c = editor();
      buildScene(c);
      c.select([c.doc.elements.firstWhere((e) => e.type == ElementType.icon).id]);
      await pump(tester, c);
      await tapTile(tester, 'Position');
      await tester.pumpAndSettle();
      await tester.tap(tab('Stays'));
      await tester.pumpAndSettle();
      await shot(tester, 'position_stays');
    });

    ptest('turn and flip small phone', (tester) async {
      final c = editor();
      buildScene(c);
      c.select([c.doc.elements.firstWhere((e) => e.type == ElementType.icon).id]);
      await pump(tester, c, size: const Size(320, 568));
      await tapTile(tester, 'Position');
      await tester.pumpAndSettle();
      await tester.tap(tab('Turn'));
      await tester.pumpAndSettle();
      await shot(tester, 'position_turn_small');
    });

    ptest('effects and blending', (tester) async {
      final c = editor();
      buildScene(c);
      c.select([c.doc.elements.first.id]);
      await pump(tester, c, b: Brightness.dark);
      await tapTile(tester, 'Opacity');
      await tester.pumpAndSettle();
      await tester.tap(tab('Blending'));
      await tester.pumpAndSettle();
      await shot(tester, 'blending_dark');
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      await tapTile(tester, 'Effects');
      await tester.pumpAndSettle();
      await shot(tester, 'effects_dark');
    });

    ptest('shadow colour', (tester) async {
      final c = editor();
      buildScene(c);
      c.select([c.doc.elements.firstWhere((e) => e.type == ElementType.text).id]);
      await pump(tester, c);
      await tapTile(tester, 'Shadow');
      await tester.pumpAndSettle();
      await tester.tap(tab('Colour'));
      await tester.pumpAndSettle();
      await shot(tester, 'shadow_colour');
    });

    ptest('shape, icon and badge panels', (tester) async {
      final c = editor();
      buildScene(c);
      c.select([c.doc.elements.first.id]);
      await pump(tester, c);
      await tapTile(tester, 'Shape');
      await tester.pumpAndSettle();
      await shot(tester, 'shape_kind');
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      c.select([c.doc.elements.firstWhere((e) => e.type == ElementType.icon).id]);
      await tester.pump();
      await tapTile(tester, 'Icon');
      await tester.pumpAndSettle();
      await shot(tester, 'icon_grid');
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      await tapTile(tester, 'Badge');
      await tester.pumpAndSettle();
      await shot(tester, 'badge');
    });

    ptest('picture tools', (tester) async {
      final c = editor();
      await tester.runAsync(() async {
        await c.addPicture('crest.png', await samplePng());
      });
      await pump(tester, c);
      await tapTile(tester, 'See-through');
      await tester.pumpAndSettle();
      await shot(tester, 'picture_seethrough');
      await tester.tap(tab('Whole frame'));
      await tester.pumpAndSettle();
      await shot(tester, 'picture_wholeframe');
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      await tapTile(tester, 'Fit');
      await tester.pumpAndSettle();
      // Let the "Saving" to "All changes saved" cross-fade finish first. The save runs real
      // file work, so wait (up to about 10 s) until "Saving" is gone, not a fixed time.
      for (var i = 0; i < 50 && find.textContaining('Saving').evaluate().isNotEmpty; i++) {
        await tester.runAsync(() async {
          await c.flushSave();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saving'), findsNothing);
      await shot(tester, 'picture_fit');
    });

    ptest('several pieces: strip and align', (tester) async {
      final c = editor();
      buildScene(c);
      c.select([for (final e in c.doc.elements) e.id]);
      await pump(tester, c);
      await shot(tester, 'multi_strip');
      await tapTile(tester, 'Space');
      await tester.pumpAndSettle();
      await shot(tester, 'multi_space');
    });

    ptest('layers select mode', (tester) async {
      final c = editor();
      buildScene(c);
      c.select([]);
      await pump(tester, c);
      await tapTile(tester, 'Layers');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a heading').last);
      await tester.pump();
      await shot(tester, 'layers_select');
    });

    ptest('menu', (tester) async {
      final c = editor();
      buildScene(c);
      await pump(tester, c, gallery: FakeGallerySaver());
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      await shot(tester, 'editor_menu');
    });
  });
}
