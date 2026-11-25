import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/masks.dart';
import 'package:pio_photo_layout/features/develop/photo_editor_controller.dart';
import 'package:pio_photo_layout/features/develop/photo_editor_screen.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../editor/editor_screen_test.dart' show etest;
import 'mask_handles_test.dart' show quadPng, screenAt;
import 'masks_panel_test.dart' show run;
import 'panels_test.dart' show dragTo, open, overflow;
import 'photo_editor_test.dart'
    show canvasState, editorOn, homeWith, pumpEditor, settle;

Finder _slider(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(CupertinoSlider),
);

/// The editor on one 2000 x 1500 quadrant photo, Lens blur panel open.
Future<PhotoEditorController> openBlurQuad(
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
  e.setPanel(ToolPanel.blur);
  await pumpEditor(tester, e, size: size);
  return e;
}

Future<void> tapAt(WidgetTester tester, Offset p) async {
  await tester.tapAt(p);
  await tester.pump();
  await settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('tool strip', () {
    test('Lens blur comes after Masking', () {
      expect(ToolPanel.values.last, ToolPanel.blur);
      expect(ToolPanel.values.indexOf(ToolPanel.blur), 6);
      expect(toolTitle(ToolPanel.blur), 'Lens blur');
      expect(toolIcon(ToolPanel.blur), CupertinoIcons.camera_viewfinder);
    });

    etest('the tile opens the panel', (tester) async {
      final home = await homeWith(tester, n: 2);
      final e = editorOn(home, 0);
      await pumpEditor(tester, e);
      await tester.tap(find.text('Lens blur'));
      await tester.pump();
      expect(e.panel, ToolPanel.blur);
      expect(find.text('Amount'), findsOneWidget);
    });
  });

  group('panel', () {
    etest('an Amount drag is one undo step', (tester) async {
      final e = await open(tester, ToolPanel.blur);
      await dragTo(tester, _slider('slider-lens-amount'), 0.6);
      expect(e.settings.lensBlur.amount, closeTo(60, 12));
      expect(e.canUndo, isTrue);
      await e.undo();
      await tester.pump();
      expect(e.settings.lensBlur.amount, 0);
      expect(e.canUndo, isFalse, reason: 'the whole drag was one step');
    });

    etest('Transition and Bokeh highlights set their values', (tester) async {
      final e = await open(tester, ToolPanel.blur);
      await dragTo(tester, _slider('slider-lens-transition'), 0.9);
      expect(e.settings.lensBlur.transition, greaterThan(70));
      await dragTo(tester, _slider('slider-lens-boost'), 0.5);
      expect(e.settings.lensBlur.boost, closeTo(50, 15));
      expect(find.text('Bokeh highlights'), findsOneWidget);
      await e.undo();
      await e.undo();
      await tester.pump();
      expect(e.settings.lensBlur, LensBlur.off);
    });

    etest('the hint shows while Amount is 0', (tester) async {
      final e = await open(tester, ToolPanel.blur);
      const hint = 'Raise Amount to blur the background.';
      expect(find.text(hint), findsOneWidget);
      await run(tester, () => e.setLens(LensBlur(amount: 40)));
      expect(find.text(hint), findsNothing);
    });

    etest('Focus switches between Subject, Point and Mask', (tester) async {
      final e = await open(tester, ToolPanel.blur);
      expect(e.settings.lensBlur.focus, LensFocus.subject);
      await tester.tap(find.text('Point'));
      await tester.pumpAndSettle();
      expect(e.settings.lensBlur.focus, LensFocus.point);
      await tester.tap(find.text('Subject'));
      await tester.pumpAndSettle();
      expect(e.settings.lensBlur.focus, LensFocus.subject);
    });

    etest('Mask is off without masks, and sets maskId with one', (
      tester,
    ) async {
      final e = await open(tester, ToolPanel.blur);
      await tester.tap(find.text('Mask'));
      await tester.pumpAndSettle();
      expect(e.settings.lensBlur.focus, LensFocus.subject, reason: 'disabled');

      await run(tester, () => e.addMask(RadialShape()));
      await tester.pumpAndSettle();
      final id = e.masks.single.id;
      await tester.tap(find.text('Mask'));
      await tester.pumpAndSettle();
      expect(e.settings.lensBlur.focus, LensFocus.mask);
      expect(e.settings.lensBlur.maskId, id);
      expect(find.text('Mask 1'), findsOneWidget, reason: 'the picker');
    });

    etest('the picker lists the masks by name and picks one', (tester) async {
      final e = await open(tester, ToolPanel.blur);
      await run(tester, () => e.addMask(RadialShape()));
      await run(tester, () => e.addMask(BackgroundShape()));
      final first = e.masks.first.id;
      await run(tester, () => e.setLens(LensBlur(focus: LensFocus.mask)));
      await tester.pumpAndSettle();
      expect(find.text('Choose a mask'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lens-mask-picker')));
      await tester.pumpAndSettle();
      expect(find.text('Mask 2'), findsOneWidget);
      await tester.tap(find.text('Mask 1'));
      await tester.pumpAndSettle();
      expect(e.settings.lensBlur.maskId, first);
      expect(find.text('Choose a mask'), findsNothing);
    });

    etest('a removed mask shows "Choose a mask" and does not crash', (
      tester,
    ) async {
      final e = await open(tester, ToolPanel.blur);
      await run(tester, () => e.addMask(RadialShape()));
      final id = e.masks.single.id;
      await run(
        tester,
        () =>
            e.setLens(LensBlur(amount: 50, focus: LensFocus.mask, maskId: id)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mask 1'), findsOneWidget);
      await run(tester, () => e.deleteMask(id));
      await tester.pumpAndSettle();
      expect(find.text('Choose a mask'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    etest('Show focus is view state, not part of the look', (tester) async {
      final e = await open(tester, ToolPanel.blur);
      expect(e.showFocus, isFalse);
      await tester.tap(find.byKey(const ValueKey('lens-show-focus')));
      await tester.pumpAndSettle();
      expect(e.showFocus, isTrue);
      expect(e.hasOwnChanges, isFalse);
      expect(e.canUndo, isFalse);
    });

    for (final size in const [Size(390, 844), Size(320, 568)]) {
      etest('every control is in view at ${size.width.toInt()}', (
        tester,
      ) async {
        final e = await open(tester, ToolPanel.blur, size: size);
        expect(overflow(tester), 0, reason: 'amount 0');
        await run(tester, () => e.setLens(LensBlur(amount: 50)));
        expect(overflow(tester), 0, reason: 'subject');
        await run(
          tester,
          () => e.setLens(LensBlur(amount: 50, focus: LensFocus.point)),
        );
        expect(overflow(tester), 0, reason: 'point');
        await run(tester, () => e.addMask(RadialShape()));
        final id = e.masks.single.id;
        await run(
          tester,
          () => e.setLens(
            LensBlur(amount: 50, focus: LensFocus.mask, maskId: id),
          ),
        );
        await tester.pumpAndSettle();
        expect(overflow(tester), 0, reason: 'mask');
      });
    }
  });

  group('canvas', () {
    etest('a tap sets the focus point, fitted and at 2x', (tester) async {
      final e = await openBlurQuad(tester);
      await run(
        tester,
        () => e.setLens(LensBlur(amount: 50, focus: LensFocus.point)),
      );
      await tester.pump();
      await tapAt(tester, screenAt(tester, .5, .5));
      var l = e.settings.lensBlur;
      expect(l.fx, closeTo(.5, 0.01));
      expect(l.fy, closeTo(.5, 0.01));

      await tapAt(tester, screenAt(tester, .25, .75));
      l = e.settings.lensBlur;
      expect(l.fx, closeTo(.25, 0.01));
      expect(l.fy, closeTo(.75, 0.01));
      expect(l.amount, 50, reason: 'only the point changes');
      await run(tester, e.undo);
      expect(e.settings.lensBlur.fx, closeTo(.5, 0.01), reason: 'one step');

      canvasState(tester).zoomTo(2);
      await tester.pump();
      await settle(tester);
      await tapAt(tester, screenAt(tester, .5, .5));
      l = e.settings.lensBlur;
      expect(l.fx, closeTo(.5, 0.01));
      expect(l.fy, closeTo(.5, 0.01));
      final off = screenAt(tester, .45, .55);
      await tapAt(tester, off);
      l = e.settings.lensBlur;
      expect(l.fx, closeTo(.45, 0.01), reason: 'correct under zoom');
      expect(l.fy, closeTo(.55, 0.01));
    });

    etest('a tap outside the photo, or with another focus, does nothing', (
      tester,
    ) async {
      final e = await openBlurQuad(tester);
      await run(tester, () => e.setLens(LensBlur(amount: 50)));
      await tapAt(tester, screenAt(tester, .3, .3));
      expect(e.settings.lensBlur.fx, .5, reason: 'focus is Subject');

      await run(
        tester,
        () => e.setLens(LensBlur(amount: 50, focus: LensFocus.point)),
      );
      final left = screenAt(tester, 0, .5) - const Offset(6, 0);
      await tapAt(tester, left);
      expect(e.settings.lensBlur.fx, .5);
      expect(e.settings.lensBlur.fy, .5);
      await run(tester, e.undo);
      expect(
        e.settings.lensBlur,
        LensBlur(amount: 50),
        reason: 'the taps added no step: undo goes back to Subject',
      );
    });

    etest('a pinch still zooms and does not move the focus', (tester) async {
      final e = await openBlurQuad(tester);
      await run(
        tester,
        () => e.setLens(LensBlur(amount: 50, focus: LensFocus.point)),
      );
      final canvas = canvasState(tester);
      final before = canvas.zoomPercent;
      final c = screenAt(tester, .3, .6);
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
      expect(e.settings.lensBlur.fx, .5);
      expect(e.settings.lensBlur.fy, .5);
      await run(tester, e.undo);
      expect(e.settings.lensBlur.amount, 0, reason: 'only the setup step');
      expect(e.canUndo, isFalse);
    });

    etest('press and hold still shows the original', (tester) async {
      final e = await openBlurQuad(tester);
      await run(
        tester,
        () => e.setLens(LensBlur(amount: 50, focus: LensFocus.point)),
      );
      final g = await tester.startGesture(screenAt(tester, .5, .5));
      await tester.pump(const Duration(milliseconds: 700));
      expect(e.comparing, isTrue);
      await g.up();
      await tester.pump();
      expect(e.comparing, isFalse);
      expect(e.settings.lensBlur.fx, .5);
      await settle(tester);
    });

    etest('Show focus draws for a mask and for a point', (tester) async {
      final e = await openBlurQuad(tester);
      final canvas = canvasState(tester);
      await run(tester, () => e.addMask(RadialShape()));
      final id = e.masks.single.id;
      await run(
        tester,
        () =>
            e.setLens(LensBlur(amount: 60, focus: LensFocus.mask, maskId: id)),
      );
      expect(canvas.showsFocusOverlay, isFalse);
      e.setShowFocus(true);
      await tester.pump();
      await settle(tester, until: () => canvas.showsFocusOverlay);
      expect(canvas.showsMaskOverlay, isTrue);

      await run(
        tester,
        () => e.setLens(LensBlur(amount: 60, focus: LensFocus.point)),
      );
      await tester.pump();
      await settle(tester, until: () => canvas.showsFocusOverlay);
      expect(canvas.showsMaskOverlay, isFalse, reason: 'a point is a disc');

      e.setShowFocus(false);
      await tester.pump();
      expect(canvas.showsFocusOverlay, isFalse);
    });
  });

  group('goldens', () {
    Finder screen() => find.byType(PhotoEditorScreen);

    etest('panel light at 320', (tester) async {
      final e = await open(tester, ToolPanel.blur, size: const Size(320, 568));
      await run(
        tester,
        () => e.setLens(LensBlur(amount: 60, focus: LensFocus.point)),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      await expectLater(screen(), matchesGoldenFile('goldens/blur_panel.png'));
    });

    etest('panel dark at 320, Mask focus', (tester) async {
      final e = await open(
        tester,
        ToolPanel.blur,
        size: const Size(320, 568),
        b: Brightness.dark,
      );
      await run(tester, () => e.addMask(RadialShape()));
      final id = e.masks.single.id;
      await run(
        tester,
        () =>
            e.setLens(LensBlur(amount: 60, focus: LensFocus.mask, maskId: id)),
      );
      e.setPanel(ToolPanel.blur);
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.pumpAndSettle();
      await expectLater(
        screen(),
        matchesGoldenFile('goldens/blur_panel_dark.png'),
      );
    });

    etest('panel with Amount 0 shows the hint', (tester) async {
      await open(tester, ToolPanel.blur, size: const Size(320, 568));
      await settle(tester);
      await tester.pumpAndSettle();
      await expectLater(
        screen(),
        matchesGoldenFile('goldens/blur_panel_hint.png'),
      );
    });

    etest('focus overlay of a mask', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(
        tester,
        () => e.addMask(RadialShape(cx: .4, rx: .3, ry: .2, feather: 40)),
      );
      final id = e.masks.single.id;
      await run(
        tester,
        () =>
            e.setLens(LensBlur(amount: 60, focus: LensFocus.mask, maskId: id)),
      );
      e.setPanel(ToolPanel.blur);
      e.setShowFocus(true);
      await tester.pump();
      await settle(tester, until: () => canvasState(tester).showsFocusOverlay);
      await tester.pumpAndSettle();
      await expectLater(
        screen(),
        matchesGoldenFile('goldens/blur_focus_mask.png'),
      );
    });

    etest('focus overlay of a point', (tester) async {
      final e = await open(tester, ToolPanel.blur);
      await run(
        tester,
        () => e.setLens(
          LensBlur(
            amount: 60,
            focus: LensFocus.point,
            fx: .35,
            fy: .6,
            transition: 40,
          ),
        ),
      );
      e.setShowFocus(true);
      await tester.pump();
      await settle(tester);
      await tester.pumpAndSettle();
      await expectLater(
        screen(),
        matchesGoldenFile('goldens/blur_focus_point.png'),
      );
    });
  });
}
