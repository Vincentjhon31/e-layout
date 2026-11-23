import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/features/develop/panels/curve_editor.dart';
import 'package:pio_photo_layout/features/develop/panels/develop_slider.dart';
import 'package:pio_photo_layout/features/develop/photo_editor_controller.dart';

import '../editor/editor_screen_test.dart' show etest;
import 'photo_editor_test.dart' show editorOn, homeWith, pumpEditor, settle;

/// The tabs of each tool, in order.
const Map<ToolPanel, List<String>> kTabs = {
  ToolPanel.light: ['Basic', 'Tone', 'Curve', 'Zones', 'Splits'],
  ToolPanel.colour: ['Basic', 'Look', 'Mixer', 'Grade', 'Blend'],
  ToolPanel.effects: ['Basic', 'Vignette', 'Grain'],
  ToolPanel.detail: ['Sharpening', 'Noise', 'Colour noise'],
};

Future<PhotoEditorController> open(
  WidgetTester tester,
  ToolPanel panel, {
  Size size = const Size(390, 844),
  Brightness b = Brightness.light,
}) async {
  final home = await homeWith(tester, n: 3);
  final e = editorOn(home, 0);
  e.setPanel(panel);
  await pumpEditor(tester, e, size: size, b: b);
  return e;
}

/// A tab of the open panel's segmented control.
Finder tab(String name) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is CupertinoSlidingSegmentedControl<String>,
  ),
  matching: find.text(name),
);

Future<void> openTab(WidgetTester tester, String name) async {
  await tester.tap(tab(name));
  await tester.pumpAndSettle();
}

double overflow(WidgetTester tester) {
  final st = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byKey(const ValueKey('develop-panel-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  return st.position.maxScrollExtent;
}

Finder sliderOf(Setting s) => find.descendant(
  of: find.byKey(ValueKey('slider-${s.name}')),
  matching: find.byType(CupertinoSlider),
);

/// Takes the slider's thumb and drags it to [fraction] of the track.
Future<void> dragTo(WidgetTester tester, Finder slider, double fraction) async {
  final r = tester.getRect(slider);
  final w = tester.widget<CupertinoSlider>(slider);
  final cur = (w.value - w.min) / (w.max - w.min);
  double xAt(double f) => r.left + 14 + f * (r.width - 28);
  final g = await tester.startGesture(Offset(xAt(cur), r.center.dy));
  const steps = 8;
  for (var i = 1; i <= steps; i++) {
    await g.moveTo(
      Offset(xAt(cur + (fraction - cur) * i / steps), r.center.dy),
    );
    await tester.pump();
  }
  await g.up();
  await tester.pump();
  await settle(tester);
}

Offset curveAt(WidgetTester tester, int x, int y) {
  final r = tester.getRect(find.byKey(const ValueKey('curve-editor')));
  const pad = 14.0;
  final span = r.width - 2 * pad;
  return Offset(
    r.left + pad + x / 255 * span,
    r.top + pad + (1 - y / 255) * span,
  );
}

Future<void> doubleTapAt(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> tapAt(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('value text', () {
    test('signs, decimals and degrees', () {
      expect(formatSetting(Setting.contrast, 20), '+20');
      expect(formatSetting(Setting.contrast, 0), '0');
      expect(formatSetting(Setting.contrast, -15), '-15');
      expect(formatSetting(Setting.exposure, 0.7), '+0.70');
      expect(formatSetting(Setting.exposure, -1.25), '-1.25');
      expect(formatSetting(Setting.exposure, 0), '0.00');
      expect(formatSetting(Setting.sharpenRadius, 1.5), '1.5');
      expect(formatSetting(Setting.gradeShadowHue, 240), '240°');
      expect(formatSetting(Setting.grainAmount, 30), '30');
      expect(formatSetting(Setting.sharpenAmount, 40), '40');
    });
  });

  group('sliders', () {
    etest('a drag writes the setting as one undo step', (tester) async {
      final e = await open(tester, ToolPanel.light);
      expect(find.text('Exposure'), findsOneWidget);
      await dragTo(tester, sliderOf(Setting.exposure), 0.8);
      expect(e.settings[Setting.exposure], closeTo(2.5, 0.8));
      expect(
        find.text(
          formatSetting(Setting.exposure, e.settings[Setting.exposure]),
        ),
        findsOneWidget,
      );
      await e.undo();
      await tester.pump();
      expect(e.settings[Setting.exposure], 0);
      expect(e.canUndo, isFalse, reason: 'the whole drag was one step');
    });

    etest('a double-tap on the row puts the neutral value back', (
      tester,
    ) async {
      final e = await open(tester, ToolPanel.light);
      await tester.runAsync(() => e.setValue(Setting.contrast, 40));
      await tester.pump();
      expect(find.text('+40'), findsOneWidget);
      await doubleTapAt(tester, tester.getCenter(find.text('Contrast')));
      await settle(tester);
      expect(e.settings[Setting.contrast], 0);
    });

    etest('every light, effects and detail slider writes its setting', (
      tester,
    ) async {
      final e = await open(tester, ToolPanel.light);
      await dragTo(tester, sliderOf(Setting.highlights), 0.25);
      expect(e.settings[Setting.highlights], lessThan(-30));
      await openTab(tester, 'Tone');
      await dragTo(tester, sliderOf(Setting.blacks), 0.75);
      expect(e.settings[Setting.blacks], greaterThan(30));
      await openTab(tester, 'Zones');
      await dragTo(tester, sliderOf(Setting.curveLights), 0.75);
      expect(e.settings[Setting.curveLights], greaterThan(10));
      e.setPanel(ToolPanel.detail);
      await tester.pump();
      await dragTo(tester, sliderOf(Setting.sharpenAmount), 0.5);
      expect(e.settings[Setting.sharpenAmount], closeTo(75, 15));
      e.setPanel(ToolPanel.effects);
      await tester.pump();
      await openTab(tester, 'Grain');
      await dragTo(tester, sliderOf(Setting.grainSize), 0.8);
      expect(e.settings[Setting.grainSize], closeTo(80, 15));
    });
  });

  group('undo steps', () {
    etest('a double-tap reset is one undo step', (tester) async {
      final e = await open(tester, ToolPanel.light);
      await tester.runAsync(() => e.setValue(Setting.contrast, 40));
      await tester.pump();
      await doubleTapAt(tester, tester.getCenter(find.text('Contrast')));
      await settle(tester);
      expect(e.settings[Setting.contrast], 0);
      await e.undo();
      await tester.pump();
      expect(
        e.settings[Setting.contrast],
        40,
        reason: 'one undo undoes the reset',
      );
    });

    etest('a reset on a neutral value adds no step', (tester) async {
      final e = await open(tester, ToolPanel.light);
      await doubleTapAt(tester, tester.getCenter(find.text('Contrast')));
      await settle(tester);
      expect(e.canUndo, isFalse);
    });
  });

  group('splits', () {
    etest('shadow < midtone < highlight with gaps of at least 5', (
      tester,
    ) async {
      final e = await open(tester, ToolPanel.light);
      await openTab(tester, 'Splits');
      // The shadow split is pulled past the midtone split (50).
      await dragTo(tester, sliderOf(Setting.curveShadowSplit), 1.0);
      expect(e.settings[Setting.curveShadowSplit], 45);
      // The highlight split is pulled below the midtone split.
      await dragTo(tester, sliderOf(Setting.curveHighlightSplit), 0.0);
      expect(e.settings[Setting.curveHighlightSplit], 55);
      // The midtone split stays between its neighbours.
      await dragTo(tester, sliderOf(Setting.curveMidtoneSplit), 1.0);
      expect(e.settings[Setting.curveMidtoneSplit], 50);
    });

    etest('a clamped split drag is one undo step', (tester) async {
      final e = await open(tester, ToolPanel.light);
      await openTab(tester, 'Splits');
      await dragTo(tester, sliderOf(Setting.curveShadowSplit), 1.0);
      expect(e.settings[Setting.curveShadowSplit], 45);
      await e.undo();
      await tester.pump();
      expect(e.settings[Setting.curveShadowSplit], 25);
      expect(e.canUndo, isFalse);
    });

    etest('splits that are already close do not break the sliders', (
      tester,
    ) async {
      final e = await open(tester, ToolPanel.light);
      await tester.runAsync(
        () => e.home.setLook(
          e.home.look.withPhotoPatch(
            e.photo.id,
            SettingsPatch(
              values: {
                Setting.curveShadowSplit: 90,
                Setting.curveMidtoneSplit: 92,
                Setting.curveHighlightSplit: 95,
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await openTab(tester, 'Splits');
      await dragTo(tester, sliderOf(Setting.curveMidtoneSplit), 0.0);
      await dragTo(tester, sliderOf(Setting.curveHighlightSplit), 0.0);
      await dragTo(tester, sliderOf(Setting.curveShadowSplit), 1.0);
      for (final s in [
        Setting.curveShadowSplit,
        Setting.curveMidtoneSplit,
        Setting.curveHighlightSplit,
      ]) {
        expect(e.settings[s], inInclusiveRange(s.min, s.max));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('curve', () {
    List<CurvePoint> pts(
      PhotoEditorController e, [
      CurveChannel c = CurveChannel.master,
    ]) => e.settings.curve(c);

    etest('tap adds, drag moves, double-tap removes; the ends stay', (
      tester,
    ) async {
      final e = await open(tester, ToolPanel.light);
      await openTab(tester, 'Curve');
      expect(find.text('RGB'), findsOneWidget);
      expect(find.text('Red'), findsOneWidget);
      expect(find.byType(CurveEditor), findsOneWidget);

      await tapAt(tester, curveAt(tester, 128, 128));
      await settle(tester);
      expect(pts(e).length, 3);
      expect(pts(e)[1].x, closeTo(128, 3));
      expect(
        pts(e)[1].y,
        closeTo(128, 3),
        reason: 'on the curve, so the look does not jump',
      );

      // Drag it up and to the right.
      final g = await tester.startGesture(
        curveAt(tester, pts(e)[1].x, pts(e)[1].y),
      );
      await g.moveTo(curveAt(tester, 150, 170));
      await tester.pump();
      await g.moveTo(curveAt(tester, 160, 200));
      await tester.pump();
      await g.up();
      await settle(tester);
      expect(pts(e).length, 3);
      expect(pts(e)[1].x, closeTo(160, 3));
      expect(pts(e)[1].y, closeTo(200, 3));
      // Add, move and the drag were three steps, so undo goes back to the add.
      await e.undo();
      await tester.pump();
      expect(pts(e)[1].y, closeTo(128, 3));
      await e.redo();
      await tester.pump();

      // The first end point moves up only; the x of 0 holds.
      final g2 = await tester.startGesture(curveAt(tester, 0, 0));
      await g2.moveTo(curveAt(tester, 40, 30));
      await tester.pump();
      await g2.up();
      await settle(tester);
      expect(pts(e).first.x, 0);
      expect(pts(e).first.y, closeTo(30, 3));

      // A point cannot cross its neighbour.
      final mid = pts(e)[1];
      final g3 = await tester.startGesture(curveAt(tester, mid.x, mid.y));
      await g3.moveTo(curveAt(tester, 255, mid.y));
      await tester.pump();
      await g3.up();
      await settle(tester);
      expect(pts(e)[1].x, lessThan(255));
      expect(pts(e)[1].x, greaterThanOrEqualTo(pts(e).first.x + 1));
      expect(pts(e).last.x, 255);

      // Double-tap removes the middle point.
      final m = pts(e)[1];
      await doubleTapAt(tester, curveAt(tester, m.x, m.y));
      await settle(tester);
      expect(pts(e).length, 2);

      // The end points cannot be removed.
      await doubleTapAt(tester, curveAt(tester, 255, pts(e).last.y));
      await settle(tester);
      expect(pts(e).length, 2);
      expect(pts(e).last.x, 255);
    });

    etest('points stay sorted and keep a gap', (tester) async {
      final e = await open(tester, ToolPanel.light);
      await openTab(tester, 'Curve');
      await tapAt(tester, curveAt(tester, 200, 200));
      await tapAt(tester, curveAt(tester, 60, 60));
      await settle(tester);
      final xs = [for (final p in pts(e)) p.x];
      expect([...xs]..sort(), xs);
      expect(xs.length, 4);
      // Pull the 200 point onto the 60 point.
      final p = pts(e)[2];
      final g = await tester.startGesture(curveAt(tester, p.x, p.y));
      await g.moveTo(curveAt(tester, 20, p.y));
      await tester.pump();
      await g.up();
      await settle(tester);
      final after = [for (final q in pts(e)) q.x];
      expect(after[2], greaterThan(after[1]));
      expect(after[1], greaterThan(after[0]));
    });

    etest('a tap 20 pt from a point takes it; 30 pt away adds one', (
      tester,
    ) async {
      final e = await open(tester, ToolPanel.light);
      await openTab(tester, 'Curve');
      await tapAt(tester, curveAt(tester, 128, 128));
      await settle(tester);
      expect(pts(e).length, 3);
      final at = curveAt(tester, pts(e)[1].x, pts(e)[1].y);
      await tapAt(tester, at + const Offset(20, 0));
      await settle(tester);
      expect(pts(e).length, 3, reason: '20 pt is on the handle');
      await tapAt(tester, at + const Offset(30, 0));
      await settle(tester);
      expect(pts(e).length, 4, reason: '30 pt is empty space');
    });

    etest('a middle point stays between close neighbours', (tester) async {
      final e = await open(tester, ToolPanel.light);
      await tester.runAsync(
        () => e.setCurve(CurveChannel.master, const [
          CurvePoint(0, 0),
          CurvePoint(100, 100),
          CurvePoint(103, 103),
          CurvePoint(255, 255),
        ]),
      );
      await tester.pump();
      await openTab(tester, 'Curve');
      final g = await tester.startGesture(curveAt(tester, 100, 100));
      await g.moveTo(curveAt(tester, 200, 120));
      await tester.pump();
      await g.moveTo(curveAt(tester, 230, 120));
      await tester.pump();
      await g.up();
      await settle(tester);
      expect(pts(e)[1].x, 102, reason: 'one short of its right neighbour');
      expect(pts(e)[2].x, 103);
      expect(pts(e)[1].y, closeTo(120, 3));
    });

    etest('a colour chip edits that channel only', (tester) async {
      final e = await open(tester, ToolPanel.light);
      await openTab(tester, 'Curve');
      await tester.tap(find.text('Red'));
      await tester.pump();
      await tapAt(tester, curveAt(tester, 128, 128));
      await settle(tester);
      expect(pts(e, CurveChannel.red).length, 3);
      expect(pts(e).length, 2);
    });
  });

  group('colour', () {
    etest('the mixer shows the grey mix in black and white', (tester) async {
      final e = await open(tester, ToolPanel.colour);
      await openTab(tester, 'Mixer');
      expect(find.text('Hue'), findsOneWidget);
      expect(find.text('Black & white mix'), findsNothing);
      for (final n in [
        'Red',
        'Orange',
        'Yellow',
        'Green',
        'Aqua',
        'Blue',
        'Purple',
        'Magenta',
      ]) {
        expect(find.byKey(ValueKey('mixer-$n')), findsOneWidget);
      }
      await dragTo(tester, sliderOf(Setting.hueRed), 0.75);
      expect(e.settings[Setting.hueRed], greaterThan(10));
      await tester.tap(find.byKey(const ValueKey('mixer-Blue')));
      await tester.pump();
      await dragTo(tester, sliderOf(Setting.satBlue), 0.25);
      expect(e.settings[Setting.satBlue], lessThan(-10));

      await tester.runAsync(() => e.setGrayscale(true));
      await tester.pump();
      expect(find.text('Black & white mix'), findsOneWidget);
      expect(find.text('Hue'), findsNothing);
      await dragTo(tester, sliderOf(Setting.grayBlue), 0.75);
      expect(e.settings[Setting.grayBlue], greaterThan(10));
    });

    etest('the black and white switch writes grayscale', (tester) async {
      final e = await open(tester, ToolPanel.colour);
      await openTab(tester, 'Look');
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pump();
      await settle(tester);
      expect(e.settings.grayscale, isTrue);
    });

    etest('Amount shows only with a profile and writes the profile', (
      tester,
    ) async {
      final e = await open(tester, ToolPanel.colour);
      await openTab(tester, 'Look');
      expect(find.text('Amount'), findsNothing);
      expect(find.text('Profile'), findsNothing);
      await tester.runAsync(
        () => e.home.setLook(
          e.home.look.withPhotoPatch(
            e.photo.id,
            SettingsPatch(profile: const ProfileRef('p1', 'Soft film', 1)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Soft film'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      final slider = find.byKey(const ValueKey('slider-profile-amount'));
      await dragTo(
        tester,
        find.descendant(of: slider, matching: find.byType(CupertinoSlider)),
        0.25,
      );
      expect(e.settings.profile.amount, closeTo(0.5, 0.2));
      expect(e.settings.profile.name, 'Soft film');
      expect(
        find.text('${(e.settings.profile.amount * 100).round()}%'),
        findsOneWidget,
      );
    });

    etest('grading has four chips with their own sliders', (tester) async {
      final e = await open(tester, ToolPanel.colour);
      await openTab(tester, 'Grade');
      for (final n in ['Shadows', 'Midtones', 'Highlights', 'Global']) {
        expect(find.text(n), findsOneWidget);
      }
      await dragTo(tester, sliderOf(Setting.gradeShadowHue), 0.5);
      expect(e.settings[Setting.gradeShadowHue], closeTo(180, 30));
      expect(
        find.text('${e.settings[Setting.gradeShadowHue].round()}°'),
        findsOneWidget,
      );
      await tester.tap(find.text('Global'));
      await tester.pump();
      await dragTo(tester, sliderOf(Setting.gradeGlobalSat), 0.5);
      expect(e.settings[Setting.gradeGlobalSat], closeTo(50, 25));
      await openTab(tester, 'Blend');
      expect(find.text('Blending'), findsOneWidget);
      expect(find.text('Balance'), findsOneWidget);
    });
  });

  group('mixer dots', () {
    for (final size in const [Size(390, 844), Size(320, 568)]) {
      etest('every dot is 44 x 44 at ${size.width.toInt()}', (tester) async {
        await open(tester, ToolPanel.colour, size: size);
        await openTab(tester, 'Mixer');
        for (final n in [
          'Red',
          'Orange',
          'Yellow',
          'Green',
          'Aqua',
          'Blue',
          'Purple',
          'Magenta',
        ]) {
          final r = tester.getSize(find.byKey(ValueKey('mixer-$n')));
          expect(r.width, greaterThanOrEqualTo(44), reason: n);
          expect(r.height, greaterThanOrEqualTo(44), reason: n);
        }
      });
    }

    etest('at 320 the strip scrolls and a chosen dot comes into view', (
      tester,
    ) async {
      await open(tester, ToolPanel.colour, size: const Size(320, 568));
      await openTab(tester, 'Mixer');
      final strip = find.byKey(const ValueKey('mixer-Magenta'));
      expect(
        tester.getRect(strip).right,
        greaterThan(320 - 16),
        reason: 'off the end at first',
      );
      await tester.drag(
        find.byKey(const ValueKey('mixer-strip')),
        const Offset(-200, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(strip);
      await tester.pumpAndSettle();
      expect(tester.getRect(strip).right, lessThanOrEqualTo(320));
      expect(tester.getRect(strip).left, greaterThanOrEqualTo(0));
    });
  });

  group('every control is in view', () {
    for (final size in const [Size(390, 844), Size(320, 568)]) {
      for (final entry in kTabs.entries) {
        etest('${entry.key.name} at ${size.width.toInt()}', (tester) async {
          final e = await open(tester, entry.key, size: size);
          for (final t in entry.value) {
            await openTab(tester, t);
            expect(overflow(tester), 0, reason: '${entry.key.name} / $t');
          }
          // The black and white mixer and a profile add rows too.
          if (entry.key == ToolPanel.colour) {
            await tester.runAsync(() async {
              await e.setGrayscale(true);
              await e.home.setLook(
                e.home.look.withPhotoPatch(
                  e.photo.id,
                  SettingsPatch(
                    profile: const ProfileRef('p1', 'A long profile name', 1),
                  ),
                ),
              );
            });
            await tester.pump();
            for (final t in ['Look', 'Mixer']) {
              await openTab(tester, t);
              expect(
                overflow(tester),
                0,
                reason: 'colour / $t in black and white',
              );
            }
          }
        });
      }
    }
  });

  group('goldens', () {
    String slug(String s) => s.toLowerCase().replaceAll(' ', '_');

    Future<void> shoot(
      WidgetTester tester,
      ToolPanel p,
      String t, {
      Size size = const Size(390, 844),
      Brightness b = Brightness.light,
      String suffix = '',
    }) async {
      await open(tester, p, size: size, b: b);
      await openTab(tester, t);
      await expectLater(
        find
            .ancestor(
              of: find.byType(DevelopPanelShell),
              matching: find.byType(Container),
            )
            .first,
        matchesGoldenFile('goldens/panel_${p.name}_${slug(t)}$suffix.png'),
      );
    }

    for (final entry in kTabs.entries) {
      for (final t in entry.value) {
        etest('${entry.key.name} $t light', (tester) async {
          await shoot(tester, entry.key, t);
        });
      }
    }
    etest('light curve at 320', (tester) async {
      await shoot(
        tester,
        ToolPanel.light,
        'Curve',
        size: const Size(320, 568),
        suffix: '_320',
      );
    });
    etest('colour mixer at 320', (tester) async {
      await shoot(
        tester,
        ToolPanel.colour,
        'Mixer',
        size: const Size(320, 568),
        suffix: '_320',
      );
    });
    etest('light curve dark', (tester) async {
      await shoot(
        tester,
        ToolPanel.light,
        'Curve',
        b: Brightness.dark,
        suffix: '_dark',
      );
    });
    etest('colour grade dark', (tester) async {
      await shoot(
        tester,
        ToolPanel.colour,
        'Grade',
        b: Brightness.dark,
        suffix: '_dark',
      );
    });
  });
}
