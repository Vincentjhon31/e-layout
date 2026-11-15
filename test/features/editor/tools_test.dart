import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/features/editor/editor_controller.dart';

import 'editor_screen_test.dart' show newEditor;

ShapePreset shapeP(String label) => kShapePresets.firstWhere((p) => p.label == label);

/// A picture with a solid yellow frame 100 px wide and a see-through middle.
Future<Uint8List> framePng(int w, int h) async {
  final rec = ui.PictureRecorder();
  final cv = ui.Canvas(rec);
  final yellow = ui.Paint()..color = const Color(0xFFF2C230);
  cv.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), 100), yellow);
  cv.drawRect(ui.Rect.fromLTWH(0, h - 100.0, w.toDouble(), 100), yellow);
  cv.drawRect(ui.Rect.fromLTWH(0, 0, 100, h.toDouble()), yellow);
  cv.drawRect(ui.Rect.fromLTWH(w - 100.0, 0, 100, h.toDouble()), yellow);
  final img = await rec.endRecording().toImage(w, h);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  img.dispose();
  return Uint8List.fromList(bytes);
}

/// White paper with a navy ring, like a logo saved as JPG.
Future<Uint8List> logoPng() async {
  final rec = ui.PictureRecorder();
  final cv = ui.Canvas(rec);
  cv.drawRect(const ui.Rect.fromLTWH(0, 0, 80, 80), ui.Paint()..color = const Color(0xFFFFFFFF));
  cv.drawCircle(const ui.Offset(40, 40), 30, ui.Paint()..color = const Color(0xFF14212E));
  cv.drawCircle(const ui.Offset(40, 40), 18, ui.Paint()..color = const Color(0xFFFFFFFF));
  final img = await rec.endRecording().toImage(80, 80);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  img.dispose();
  return Uint8List.fromList(bytes);
}

Future<int> alphaOfAsset(EditorController c, String id, int x, int y) async {
  final img = c.prep.bitmaps[id]!;
  final d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return d.getUint8((y * img.width + x) * 4 + 3);
}

void main() {
  group('gradient stops', () {
    test('never fewer than 2 or more than 8', () {
      final c = newEditor();
      final el = c.addShape(shapeP('Rectangle'));
      c.setFillType(FillType.linear);
      expect(el.fill.stops.length, 2);
      expect(c.removeGradientStop(el, 0), isFalse, reason: 'two stops stay');
      expect(el.fill.stops.length, 2);
      for (var i = 0; i < 12; i++) {
        c.addGradientStop(el);
      }
      expect(el.fill.stops.length, 8);
      for (var i = 0; i < 12; i++) {
        c.removeGradientStop(el, 0);
      }
      expect(el.fill.stops.length, 2);
      c.close();
    });

    test('a new stop sits between the last two and copies the last colour', () {
      final c = newEditor();
      final el = c.addShape(shapeP('Rectangle'));
      c.setFillType(FillType.linear);
      el.fill.stops
        ..clear()
        ..addAll([GradientStop(0, '#FF0000', 1), GradientStop(1, '#0000FF', 1)]);
      c.addGradientStop(el);
      expect(el.fill.stops.length, 3);
      final added = el.fill.stops.last;
      expect(added.at, closeTo(0.5, 0.001));
      expect(added.color, '#0000FF');
      c.undo();
      expect(c.single!.fill.stops.length, 2);
      c.close();
    });
  });

  group('fonts', () {
    test('setFont gives the selected text the family and the nearest weight, one undo step', () {
      final c = newEditor();
      final el = c.addText(kTextPresets.firstWhere((p) => p.label == 'Heading')); // Montserrat 800
      final n = c.historyLength;
      c.setFont('Anton'); // only 400
      expect(el.font, 'Anton');
      expect(el.weight, 400);
      expect(c.historyLength, n + 1);
      c.undo();
      expect(c.single!.font, 'Montserrat');
      c.close();
    });
  });

  group('position', () {
    test('Stays at: a fixed choice turns Auto off, Auto turns it back on', () {
      final c = newEditor();
      final el = c.addShape(shapeP('Rectangle'));
      final box = c.boxOfEl(el);
      c.setPinChoice('bottom');
      expect(el.pin, Pin.bottom);
      expect(el.pinAuto, isFalse);
      expect(c.boxOfEl(el).top, closeTo(box.top, 0.01), reason: 'the piece does not jump');
      c.setPinChoice('auto');
      expect(el.pinAuto, isTrue);
      c.close();
    });

    test('flip is one undo step per press', () {
      final c = newEditor();
      final el = c.addShape(shapeP('Rectangle'));
      final n = c.historyLength;
      c.flip(horizontal: true);
      c.flip(horizontal: false);
      expect(el.flipX, isTrue);
      expect(el.flipY, isTrue);
      expect(c.historyLength, n + 2);
      c.undo();
      expect(c.single!.flipY, isFalse);
      c.close();
    });

    test('align to the photo puts one piece at the left edge', () {
      final c = newEditor();
      final el = c.addShape(shapeP('Rectangle'));
      c.align('left');
      expect(c.boxOfEl(el).left, closeTo(0, 0.01));
      c.close();
    });
  });

  group('pictures', () {
    testWidgets('Make it see-through clears the border in one undo step', (tester) async {
      await tester.runAsync(() async {
        final c = newEditor();
        final el = await c.addPicture('logo.png', await logoPng());
        final old = el.asset!;
        final n = c.historyLength;
        final ok = await c.makeSeeThrough(c.byId(el.id)!, 20);
        expect(ok, isTrue);
        final now = c.byId(el.id)!;
        expect(now.asset, isNot(old));
        expect(c.doc.assets[now.asset]!.name, 'logo (clear background)');
        expect(c.historyLength, n + 1);
        expect(await alphaOfAsset(c, now.asset!, 1, 1), 0, reason: 'white corner cleared');
        expect(await alphaOfAsset(c, now.asset!, 40, 40), 255, reason: 'white inside the ring stays');
        expect(await alphaOfAsset(c, now.asset!, 40, 15), 255, reason: 'ring stays');
        c.undo();
        expect(c.single!.asset, old);
        await c.close();
      });
    });

    testWidgets('Replace keeps the box and fits the new picture inside it', (tester) async {
      await tester.runAsync(() async {
        final c = newEditor();
        final el = await c.addPicture('a.png', await logoPng());
        final box = c.boxOfEl(el);
        await c.replacePicture(c.byId(el.id)!, 'wide.png', await framePng(400, 200));
        final now = c.byId(el.id)!;
        final b = c.boxOfEl(now);
        expect(now.name, 'wide');
        expect(b.width / b.height, closeTo(2, 0.02));
        expect(b.width, lessThanOrEqualTo(box.width + 0.5));
        expect(b.center.dx, closeTo(box.center.dx, 0.5));
        await c.close();
      });
    });

    testWidgets('Fit any photo shape splits a full-frame picture and undo brings it back', (tester) async {
      await tester.runAsync(() async {
        final c = newEditor();
        final el = await c.addPicture('frame.png', await framePng(900, 600));
        c.change(() {
          el.fit = ImageFit.stretch;
          final id = el.id;
          final e = c.byId(id)!;
          e.x = 0;
          e.w = c.doc.width;
          e.h = c.frameH;
          e.pin = Pin.top;
          e.top = 0;
        });
        expect(c.doc.elements.length, 1);
        await c.splitPicture(c.byId(el.id)!);
        expect(c.doc.elements.length, greaterThan(1));
        expect(c.sel, isEmpty);
        c.undo();
        expect(c.doc.elements.length, 1);
        await c.close();
      });
    });

    testWidgets('Fit any photo shape asks for a full-frame picture first', (tester) async {
      await tester.runAsync(() async {
        final c = newEditor();
        final el = await c.addPicture('frame.png', await framePng(900, 600));
        final n = c.historyLength;
        await c.splitPicture(el);
        expect(c.doc.elements.length, 1);
        expect(c.historyLength, n);
        expect(c.notice.value, contains('cover the whole photo'));
        await c.close();
      });
    });
  });

  group('save as PNG', () {
    testWidgets('is as wide as asked and as tall as the frame', (tester) async {
      await tester.runAsync(() async {
        final c = newEditor();
        c.addShape(shapeP('Footer band'));
        final bytes = await c.layoutPng(3000);
        final img = await decodeForTest(bytes);
        expect(img.width, 3000);
        expect(img.height, 2000, reason: 'landscape 3:2');
        img.dispose();
        await c.close();
      });
    });
  });
}

Future<ui.Image> decodeForTest(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final f = await codec.getNextFrame();
  codec.dispose();
  return f.image;
}
