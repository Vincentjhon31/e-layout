import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/masks.dart';
import 'package:pio_photo_layout/features/develop/develop_canvas.dart';
import 'package:pio_photo_layout/features/develop/mask_handles.dart';
import 'package:pio_photo_layout/features/develop/photo_editor_controller.dart';
import 'package:pio_photo_layout/features/develop/photo_editor_screen.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/ui/widgets/toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../editor/editor_screen_test.dart' show etest;
import 'masks_panel_test.dart' show maskOf, masksOf, run;
import 'panels_test.dart' show open;
import 'photo_editor_test.dart'
    show canvasState, editorOn, homeWith, pumpEditor, settle;

/// The four flat colours of [quadPng], top-left, top-right, bottom-left,
/// bottom-right, as 0-255 RGB.
const List<(int, int, int)> kQuad = [
  (200, 40, 40),
  (40, 160, 60),
  (40, 60, 200),
  (230, 200, 40),
];

/// A [w] x [h] PNG of four flat quadrants ([kQuad]).
Future<Uint8List> quadPng(int w, int h) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  final hw = w / 2, hh = h / 2;
  for (var i = 0; i < 4; i++) {
    final (r, g, b) = kQuad[i];
    c.drawRect(
      ui.Rect.fromLTWH(i.isOdd ? hw : 0, i >= 2 ? hh : 0, hw, hh),
      ui.Paint()..color = ui.Color.fromARGB(255, r, g, b),
    );
  }
  final img = await rec.endRecording().toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bd!.buffer.asUint8List();
}

/// The editor on one 2000 x 1500 quadrant photo (big enough to zoom 2x on
/// a phone), with the Masking panel open.
Future<PhotoEditorController> openQuad(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  final bytes = (await tester.runAsync(() => quadPng(2000, 1500)))!;
  final home = await homeWith(
    tester,
    photos: [
      PickedPhoto(
        name: 'quad.png',
        readBytes: () async => bytes,
        size: bytes.length,
      ),
    ],
  );
  final e = editorOn(home, 0);
  e.setPanel(ToolPanel.masks);
  await pumpEditor(tester, e, size: size);
  return e;
}

/// Where normalised photo point ([x], [y]) is on screen.
Offset screenAt(WidgetTester tester, double x, double y) =>
    tester.getTopLeft(find.byType(DevelopCanvas)) +
    canvasState(tester).maskView.toScreen(x, y);

/// Screen points per normalised unit, across and down.
(double, double) unitsOf(WidgetTester tester) {
  final v = canvasState(tester).maskView;
  final o = v.toScreen(0, 0);
  return (v.toScreen(1, 0).dx - o.dx, v.toScreen(0, 1).dy - o.dy);
}

/// One finger from [from], moved by [by] in [steps] even steps.
Future<void> drag(
  WidgetTester tester,
  Offset from,
  Offset by, {
  int steps = 8,
}) async {
  final g = await tester.startGesture(from);
  for (var i = 0; i < steps; i++) {
    await g.moveBy(by / steps.toDouble());
    await tester.pump();
  }
  await g.up();
  await tester.pump();
  await settle(tester);
}

MaskShape shapeOf(PhotoEditorController e) =>
    maskOf(e).components[e.selectedComponent].shape;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('strokes', () {
    test('points closer than 0.002 are dropped', () {
      final r = StrokeRecorder();
      for (var i = 0; i <= 100; i++) {
        r.add(i * 0.0005, .5);
      }
      expect(r.points, hasLength(26), reason: '0, 0.002, ... 0.05');
      expect(r.points.last.$1, closeTo(.05, 1e-9));
    });

    test('a stroke keeps at most 2000 points', () {
      final r = StrokeRecorder();
      for (var i = 0; i < 2500; i++) {
        r.add((i % 2) * .5, i / 2500);
      }
      expect(r.points, hasLength(kMaxPoints));
    });
  });

  group('handle places', () {
    const v = MaskView(
      photo: Size(400, 300),
      frame: Rect.fromLTWH(0, 0, 400, 300),
      scale: 1,
      origin: Offset(0, 60),
      reach: Rect.fromLTRB(0, 52, 400, 400),
    );

    test('the rotation dot is above the oval when there is room', () {
      final p = handlePoints(RadialShape(cy: .7, ry: .2), v);
      expect(p[MaskHandle.rotate], const Offset(200, 60 + 150 - kRotateGap));
    });

    test('it goes below when the top is under the labels', () {
      final p = handlePoints(RadialShape(cy: .3, ry: .2), v);
      expect(p[MaskHandle.rotate], const Offset(200, 60 + 150 + kRotateGap));
      expect(
        hitHandle(RadialShape(cy: .3, ry: .2), v, p[MaskHandle.rotate]!),
        MaskHandle.rotate,
      );
    });

    test('on a short canvas it goes to the side', () {
      const short = MaskView(
        photo: Size(400, 300),
        frame: Rect.fromLTWH(0, 0, 400, 300),
        scale: 1,
        origin: Offset(0, 60),
        reach: Rect.fromLTRB(0, 52, 400, 260),
      );
      final p = handlePoints(RadialShape(cy: .3, ry: .2), short);
      expect(p[MaskHandle.rotate], const Offset(200 + 100 + kRotateGap, 150));
    });
  });

  group('radial', () {
    etest('dragging the centre by (+40, +20) moves it, fitted and at 2x', (
      tester,
    ) async {
      final e = await openQuad(tester);
      await run(tester, () => e.addMask(RadialShape()));
      final (ux, uy) = unitsOf(tester);
      await drag(tester, screenAt(tester, .5, .5), const Offset(40, 20));
      var r = shapeOf(e) as RadialShape;
      expect(r.cx, closeTo(.5 + 40 / ux, 1e-6));
      expect(r.cy, closeTo(.5 + 20 / uy, 1e-6));
      expect((r.rx, r.ry), (.25, .25), reason: 'only the centre moves');

      await run(tester, e.undo);
      expect(shapeOf(e), RadialShape(), reason: 'one drag, one step');

      canvasState(tester).zoomTo(2);
      await tester.pump();
      await settle(tester);
      final (zx, zy) = unitsOf(tester);
      expect(zx, closeTo(2 * ux, 0.01), reason: 'zoomed in 2x');
      final view = canvasState(tester).maskView.toScreen(0, 0);
      await drag(tester, screenAt(tester, .5, .5), const Offset(40, 20));
      r = shapeOf(e) as RadialShape;
      expect(r.cx, closeTo(.5 + 40 / zx, 1e-6));
      expect(r.cy, closeTo(.5 + 20 / zy, 1e-6));
      expect(
        canvasState(tester).maskView.toScreen(0, 0),
        view,
        reason: 'a handle drag does not pan',
      );
    });

    etest('the edge dots resize, the top dot rotates, targets are 44 pt', (
      tester,
    ) async {
      final e = await openQuad(tester);
      await run(tester, () => e.addMask(RadialShape()));
      final (ux, uy) = unitsOf(tester);
      // The right dot, grabbed 15 pt off (inside its 22 pt radius).
      await drag(
        tester,
        screenAt(tester, .75, .5) + const Offset(0, 15),
        const Offset(30, 0),
      );
      var r = shapeOf(e) as RadialShape;
      expect(r.rx, closeTo(.25 + 30 / ux, 1e-6));
      expect((r.cx, r.cy, r.ry), (.5, .5, .25));
      // The bottom dot.
      await drag(tester, screenAt(tester, .5, .75), const Offset(0, -24));
      r = shapeOf(e) as RadialShape;
      expect(r.ry, closeTo(.25 - 24 / uy, 1e-6));
      // The rotation dot sits above the top dot; a quarter turn clockwise.
      final c = screenAt(tester, .5, .5);
      final top = screenAt(tester, .5, .5 - r.ry);
      final rot = top - Offset(0, kRotateGap);
      final d = (rot - c).distance;
      await drag(tester, rot, Offset(d, d), steps: 12);
      r = shapeOf(e) as RadialShape;
      expect(r.angle, closeTo(90, 0.5));
      expect(e.showOverlay, isFalse, reason: 'Show mask stays as it was');
    });

    etest('no handles without the Masking panel', (tester) async {
      final e = await openQuad(tester);
      await run(tester, () => e.addMask(RadialShape()));
      e.setPanel(null);
      await tester.pump();
      await drag(tester, screenAt(tester, .5, .5), const Offset(40, 20));
      expect(shapeOf(e), RadialShape());
    });
  });

  group('linear', () {
    etest('either end line moves its end; the middle moves both', (
      tester,
    ) async {
      final e = await openQuad(tester);
      await run(tester, () => e.addMask(LinearShape(.5, .25, .5, .75)));
      final (ux, uy) = unitsOf(tester);
      // The start line, grabbed away from its dot.
      await drag(tester, screenAt(tester, .2, .25), const Offset(0, 30));
      var l = shapeOf(e) as LinearShape;
      expect(l.x0, closeTo(.5, 1e-6));
      expect(l.y0, closeTo(.25 + 30 / uy, 1e-6));
      expect((l.x1, l.y1), (.5, .75));
      await drag(tester, screenAt(tester, .5, .75), const Offset(20, -10));
      l = shapeOf(e) as LinearShape;
      expect(l.x1, closeTo(.5 + 20 / ux, 1e-6));
      expect(l.y1, closeTo(.75 - 10 / uy, 1e-6));
      final before = l;
      final mid = screenAt(tester, (l.x0 + l.x1) / 2, (l.y0 + l.y1) / 2);
      await drag(tester, mid, const Offset(-16, 12));
      l = shapeOf(e) as LinearShape;
      expect(l.x0 - before.x0, closeTo(-16 / ux, 1e-6));
      expect(l.x1 - before.x1, closeTo(-16 / ux, 1e-6));
      expect(l.y0 - before.y0, closeTo(12 / uy, 1e-6));
      expect(l.y1 - before.y1, closeTo(12 / uy, 1e-6));
    });
  });

  group('brush', () {
    double dist((double, double) a, (double, double) b) =>
        math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

    etest('a drag is one thinned stroke and one undo step', (tester) async {
      final e = await openQuad(tester);
      await run(tester, () => e.addMask(BrushShape(const [])));
      final from = screenAt(tester, .4, .4);
      await drag(tester, from, const Offset(120, 60), steps: 40);
      final b = shapeOf(e) as BrushShape;
      final st = b.strokes.single;
      expect(st.erase, isFalse);
      expect(st.size, e.brushSize);
      expect(st.flow, e.brushFlow);
      expect(st.feather, e.brushFeather);
      expect(st.points.length, greaterThan(5));
      expect(st.points.first.$1, closeTo(.4, 1e-3));
      expect(st.points.first.$2, closeTo(.4, 1e-3));
      for (final p in st.points) {
        expect(p.$1, inInclusiveRange(0, 1));
        expect(p.$2, inInclusiveRange(0, 1));
      }
      for (var i = 1; i < st.points.length; i++) {
        expect(
          dist(st.points[i - 1], st.points[i]),
          greaterThanOrEqualTo(0.002 - 1e-9),
        );
      }
      await run(tester, e.undo);
      expect(shapeOf(e), BrushShape(const []), reason: 'one step');
      expect(masksOf(e), hasLength(1));
    });

    etest('erase records erase: true', (tester) async {
      final e = await openQuad(tester);
      await run(tester, () => e.addMask(BrushShape(const [])));
      e.setBrush(erase: true, size: .1);
      await drag(tester, screenAt(tester, .3, .6), const Offset(80, 0));
      final st = (shapeOf(e) as BrushShape).strokes.single;
      expect(st.erase, isTrue);
      expect(st.size, .1);
    });

    etest('a full brush shows a toast and adds nothing', (tester) async {
      final e = await openQuad(tester);
      final full = BrushShape([
        for (var i = 0; i < kMaxStrokes; i++)
          BrushStroke([(i / kMaxStrokes, .5)]),
      ]);
      await run(tester, () => e.addMask(full));
      await drag(tester, screenAt(tester, .3, .3), const Offset(80, 40));
      expect(shapeOf(e), full);
      expect(
        find.text('This mask has the most strokes it can hold.'),
        findsOneWidget,
      );
      hideToast();
    });

    etest('a pinch still zooms and draws nothing', (tester) async {
      final e = await openQuad(tester);
      await run(tester, () => e.addMask(BrushShape(const [])));
      final canvas = canvasState(tester);
      final before = canvas.zoomPercent;
      final c = screenAt(tester, .5, .5);
      final a = await tester.startGesture(c - const Offset(20, 0));
      final b = await tester.startGesture(c + const Offset(20, 0));
      for (var i = 0; i < 10; i++) {
        await a.moveBy(const Offset(-8, 0));
        await b.moveBy(const Offset(8, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pump();
      await settle(tester);
      expect(canvas.zoomPercent, greaterThan(before));
      expect(shapeOf(e), BrushShape(const []));
      expect(e.changing, isFalse);
      await run(tester, e.undo);
      expect(masksOf(e), isEmpty, reason: 'the pinch added no step');
    });
  });

  group('colour range', () {
    etest('a tap adds the tapped colour', (tester) async {
      final e = await openQuad(tester);
      await run(tester, () => e.addMask(ColourRangeShape(const [])));
      await tester.tapAt(screenAt(tester, .25, .25));
      await settle(
        tester,
        until: () => (shapeOf(e) as ColourRangeShape).samples.isNotEmpty,
      );
      var s = (shapeOf(e) as ColourRangeShape).samples;
      final (r, g, b) = kQuad[0];
      expect(s.single.$1, closeTo(r / 255, 2 / 255));
      expect(s.single.$2, closeTo(g / 255, 2 / 255));
      expect(s.single.$3, closeTo(b / 255, 2 / 255));

      await tester.tapAt(screenAt(tester, .75, .75));
      await settle(
        tester,
        until: () => (shapeOf(e) as ColourRangeShape).samples.length == 2,
      );
      s = (shapeOf(e) as ColourRangeShape).samples;
      final (r2, g2, b2) = kQuad[3];
      expect(s.last.$1, closeTo(r2 / 255, 2 / 255));
      expect(s.last.$2, closeTo(g2 / 255, 2 / 255));
      expect(s.last.$3, closeTo(b2 / 255, 2 / 255));
      await run(tester, e.undo);
      expect((shapeOf(e) as ColourRangeShape).samples, hasLength(1));
    });

    etest('a sixth colour is refused with a toast', (tester) async {
      final e = await openQuad(tester);
      final full = ColourRangeShape([
        for (var i = 0; i < kMaxColourSamples; i++) (i / 5, .5, .5),
      ]);
      await run(tester, () => e.addMask(full));
      await tester.tapAt(screenAt(tester, .25, .25));
      await settle(tester);
      expect(shapeOf(e), full);
      expect(
        find.text('A colour range holds at most 5 colours.'),
        findsOneWidget,
      );
      hideToast();
    });
  });

  group('overlay', () {
    etest('Show mask draws the coverage; a drag shows it too', (tester) async {
      final e = await openQuad(tester);
      await run(tester, () => e.addMask(RadialShape()));
      final canvas = canvasState(tester);
      expect(canvas.showsMaskOverlay, isFalse);
      e.setShowOverlay(true);
      await tester.pump();
      await settle(tester, until: () => canvas.showsMaskOverlay);
      e.setShowOverlay(false);
      await tester.pump();
      expect(canvas.showsMaskOverlay, isFalse);

      final g = await tester.startGesture(screenAt(tester, .5, .5));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(8, 0));
        await tester.pump();
      }
      await settle(tester, until: () => canvas.showsMaskOverlay);
      await g.up();
      await tester.pump();
      await settle(tester);
      expect(canvas.showsMaskOverlay, isFalse, reason: 'off after the drag');
    });
  });

  group('goldens', () {
    Finder screen() => find.byType(PhotoEditorScreen);

    etest('radial handles', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(
        tester,
        () => e.addMask(RadialShape(rx: .3, ry: .2, angle: 20, feather: 40)),
      );
      await settle(tester);
      await expectLater(
        screen(),
        matchesGoldenFile('goldens/mask_handles_radial.png'),
      );
    });

    etest('radial handles dark with the mask shown', (tester) async {
      final e = await open(tester, ToolPanel.masks, b: Brightness.dark);
      await run(
        tester,
        () => e.addMask(RadialShape(rx: .3, ry: .2, angle: 20, feather: 40)),
      );
      e.setShowOverlay(true);
      await tester.pump();
      await settle(tester, until: () => canvasState(tester).showsMaskOverlay);
      await expectLater(
        screen(),
        matchesGoldenFile('goldens/mask_handles_radial_dark.png'),
      );
    });

    etest('radial handles wide', (tester) async {
      final home = await homeWith(tester, n: 3);
      final e = editorOn(home, 0);
      e.setPanel(ToolPanel.masks);
      await pumpEditor(tester, e, size: const Size(1280, 800), dpr: 1);
      await run(tester, () => e.addMask(RadialShape(rx: .3, ry: .2)));
      await settle(tester);
      await expectLater(
        screen(),
        matchesGoldenFile('goldens/mask_handles_radial_wide.png'),
      );
    });

    etest('linear handles', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(LinearShape(.35, .2, .6, .7)));
      await settle(tester);
      await expectLater(
        screen(),
        matchesGoldenFile('goldens/mask_handles_linear.png'),
      );
    });

    etest('brush overlay', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      final pts = [
        for (var i = 0; i <= 40; i++)
          (.2 + .6 * i / 40, .5 + .2 * math.sin(i / 40 * 2 * math.pi)),
      ];
      await run(
        tester,
        () => e.addMask(
          BrushShape([
            BrushStroke(pts, size: .06),
            BrushStroke([(.5, .2), (.5, .8)], size: .03, erase: true),
          ]),
        ),
      );
      e.setShowOverlay(true);
      await tester.pump();
      await settle(tester, until: () => canvasState(tester).showsMaskOverlay);
      await expectLater(
        screen(),
        matchesGoldenFile('goldens/mask_handles_brush.png'),
      );
    });
  });
}
