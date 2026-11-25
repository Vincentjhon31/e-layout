import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/masks.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/features/develop/panels/develop_slider.dart';
import 'package:pio_photo_layout/features/develop/panels/panel_masks.dart';
import 'package:pio_photo_layout/features/develop/photo_editor_controller.dart';
import 'package:pio_photo_layout/features/develop/photo_editor_screen.dart';
import 'package:pio_photo_layout/ui/widgets/action_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../editor/editor_screen_test.dart' show etest;
import 'panels_test.dart' show dragTo, open, openTab, overflow, sliderOf;
import 'photo_editor_test.dart' show editorOn, homeWith, pumpEditor, settle;

List<Mask> masksOf(PhotoEditorController e) => e.settings.masks;

Mask maskOf(PhotoEditorController e) => masksOf(e).single;

/// Scrolls the panel until [f] is in view.
Future<void> reveal(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

Future<void> run(WidgetTester tester, Future<void> Function() f) async {
  await tester.runAsync(f);
  await tester.pump();
}

/// Opens the add sheet from the list and picks [kind].
Future<void> addFromList(WidgetTester tester, String kind) async {
  await tester.tap(find.byKey(const ValueKey('mask-add')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(AppActionSheet), matching: find.text(kind)),
  );
  await tester.pumpAndSettle();
  await settle(tester);
}

Future<void> openMaskMenu(WidgetTester tester, String action) async {
  await tester.tap(find.byKey(const ValueKey('mask-menu')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(AppActionSheet),
      matching: find.text(action),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('shapes', () {
    test('the add sheet lists every kind with its starting shape', () {
      expect(kMaskKinds.keys.toList(), [
        'Subject',
        'Sky',
        'Background',
        'Brush',
        'Linear gradient',
        'Radial gradient',
        'Brightness range',
        'Colour range',
      ]);
      expect(kMaskKinds['Subject']!(), const SubjectShape());
      expect(kMaskKinds['Sky']!(), const SkyShape());
      expect(kMaskKinds['Background']!(), const BackgroundShape());
      expect(kMaskKinds['Brush']!(), BrushShape(const []));
      expect(kMaskKinds['Linear gradient']!(), LinearShape(.5, .25, .5, .75));
      final r = kMaskKinds['Radial gradient']!() as RadialShape;
      expect((r.cx, r.cy, r.rx, r.ry, r.feather), (.5, .5, .25, .25, 50.0));
      final l = kMaskKinds['Brightness range']!() as LuminanceRangeShape;
      expect((l.low, l.high, l.smooth), (.5, 1.0, 20.0));
      expect(kMaskKinds['Colour range']!(), ColourRangeShape(const []));
    });
  });

  group('tool strip', () {
    test('Masking comes after Detail', () {
      expect(ToolPanel.values.last, ToolPanel.masks);
      expect(ToolPanel.values.indexOf(ToolPanel.masks), 5);
    });

    etest('the Masking tile opens the panel', (tester) async {
      final home = await homeWith(tester, n: 2);
      final e = editorOn(home, 0);
      await pumpEditor(tester, e);
      expect(find.byIcon(CupertinoIcons.circle_lefthalf_fill), findsOneWidget);
      await tester.tap(find.text('Masking'));
      await tester.pump();
      expect(e.panel, ToolPanel.masks);
      expect(find.text('No masks yet.'), findsOneWidget);
    });

    etest('every tool fits a 320 pt phone without scrolling', (tester) async {
      final home = await homeWith(tester, n: 2);
      final e = editorOn(home, 0);
      await pumpEditor(tester, e, size: const Size(320, 568));
      final strip = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('tool-strip')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(strip.position.maxScrollExtent, 0);
      for (final p in ToolPanel.values) {
        final r = tester.getRect(find.byIcon(toolIcon(p)));
        expect(r.left, greaterThanOrEqualTo(0), reason: p.name);
        expect(r.right, lessThanOrEqualTo(320), reason: p.name);
      }
    });
  });

  group('masks panel', () {
    etest('adding Radial gradient makes Mask 1 and selects it', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await addFromList(tester, 'Radial gradient');
      final m = maskOf(e);
      expect(m.name, 'Mask 1');
      expect(m.components.single.shape, RadialShape());
      expect(m.components.single.op, MaskOp.add);
      expect(e.selectedMaskId, m.id);
      expect(find.text('Light'), findsOneWidget, reason: 'the first tab');
      expect(find.text('Mask 1'), findsOneWidget);
      expect(e.hasOwnChanges, isTrue, reason: 'masks live in the overrides');

      await tester.tap(find.byKey(const ValueKey('mask-back')));
      await tester.pump();
      expect(e.selectedMaskId, isNull);
      await addFromList(tester, 'Brush');
      expect(masksOf(e).map((m) => m.name), ['Mask 1', 'Mask 2']);
      expect(e.selectedMaskId, masksOf(e).last.id);
    });

    etest('an Adjust slider drag is one undo step', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await addFromList(tester, 'Radial gradient');
      await dragTo(tester, sliderOf(Setting.exposure), 0.8);
      expect(maskOf(e).adjust[Setting.exposure], greaterThan(1));
      expect(
        e.settings[Setting.exposure],
        0,
        reason: 'the photo keeps its own exposure',
      );
      expect(
        find.text(
          formatSetting(Setting.exposure, maskOf(e).adjust.values.first),
        ),
        findsOneWidget,
      );
      await run(tester, e.undo);
      expect(maskOf(e).adjust, isEmpty);
      await run(tester, e.undo);
      expect(masksOf(e), isEmpty);
      expect(e.canUndo, isFalse, reason: 'the add and the drag were one each');
    });

    etest('every local slider is in a tab', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(RadialShape()));
      final seen = <Setting>{};
      for (final t in kAdjustTabs.entries) {
        await openTab(tester, t.key);
        for (final s in t.value) {
          expect(find.byKey(ValueKey('slider-${s.name}')), findsOneWidget);
        }
        seen.addAll(t.value);
      }
      expect(seen, kLocalSettings);
      await openTab(tester, 'Colour');
      await dragTo(tester, sliderOf(Setting.saturation), 0.25);
      expect(maskOf(e).adjust[Setting.saturation], lessThan(-10));
    });

    etest('hide works and undoes', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(RadialShape()));
      e.selectMask(null);
      await tester.pump();
      final id = maskOf(e).id;
      await tester.tap(find.byKey(ValueKey('mask-eye-$id')));
      await settle(tester);
      expect(maskOf(e).visible, isFalse);
      expect(find.byIcon(CupertinoIcons.eye_slash), findsOneWidget);
      await run(tester, e.undo);
      expect(maskOf(e).visible, isTrue);
    });

    etest('rename works and undoes', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(RadialShape()));
      await openMaskMenu(tester, 'Rename');
      await tester.enterText(find.byType(CupertinoTextField), 'Sky fix');
      await tester.tap(find.text('Rename').last);
      await tester.pumpAndSettle();
      await settle(tester);
      expect(maskOf(e).name, 'Sky fix');
      expect(find.text('Sky fix'), findsOneWidget);
      await run(tester, e.undo);
      expect(maskOf(e).name, 'Mask 1');
    });

    etest('names are at most 40 characters; a blank one is ignored', (
      tester,
    ) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(RadialShape()));
      final id = e.selectedMaskId!;
      await openMaskMenu(tester, 'Rename');
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .maxLength,
        kMaxMaskName,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await run(tester, () => e.renameMask(id, 'A' * 45));
      expect(maskOf(e).name, 'A' * 40);
      await run(tester, () => e.renameMask(id, '   '));
      expect(maskOf(e).name, 'A' * 40);
      await run(tester, e.undo);
      expect(maskOf(e).name, 'Mask 1', reason: 'the blank name added no step');
    });

    etest('delete works and undoes', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(RadialShape()));
      await openMaskMenu(tester, 'Delete mask');
      await settle(tester);
      expect(masksOf(e), isEmpty);
      expect(e.selectedMaskId, isNull);
      expect(find.text('No masks yet.'), findsOneWidget);
      expect(
        e.hasOwnChanges,
        isFalse,
        reason: 'no masks left is the same as none',
      );
      await run(tester, e.undo);
      expect(maskOf(e).name, 'Mask 1');
    });

    etest('undoing a delete brings back the same mask', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () async {
        await e.addMask(RadialShape());
        await e.setMaskValue(e.selectedMaskId!, Setting.exposure, 1);
      });
      final before = maskOf(e);
      await run(tester, () => e.deleteMask(before.id));
      expect(masksOf(e), isEmpty);
      await run(tester, e.undo);
      expect(maskOf(e).id, before.id);
      expect(maskOf(e), before);
    });

    etest('the ninth mask is refused', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () async {
        for (var i = 0; i < kMaxMasks; i++) {
          await e.addMask(RadialShape());
        }
      });
      expect(masksOf(e).length, 8);
      expect(masksOf(e).last.name, 'Mask 8');
      await run(tester, () => e.addMask(const SkyShape()));
      expect(masksOf(e).length, 8);
      e.selectMask(null);
      await tester.pump();
      expect(find.text('8 masks is the most for one photo.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mask-add')));
      await tester.pumpAndSettle();
      expect(find.byType(AppActionSheet), findsNothing);
    });

    etest('Subtract adds a component that subtracts', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(RadialShape()));
      await openTab(tester, 'Mask');
      await tester.tap(find.byKey(const ValueKey('mask-op-subtract')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppActionSheet),
          matching: find.text('Brightness range'),
        ),
      );
      await tester.pumpAndSettle();
      await settle(tester);
      final comps = maskOf(e).components;
      expect(comps.length, 2);
      expect(comps[1].op, MaskOp.subtract);
      expect(comps[1].shape, LuminanceRangeShape());
      expect(e.selectedComponent, 1, reason: 'the new shape is shown');
      expect(find.text('Low'), findsOneWidget);
      await tester.tap(find.text('Shape 1'));
      await tester.pump();
      expect(find.text('Feather'), findsOneWidget);
      expect(find.text('Low'), findsNothing, reason: 'one shape at a time');
      await tester.tap(find.text('Shape 2'));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('mask-remove')));
      await settle(tester);
      expect(maskOf(e).components.single.shape, RadialShape());
      expect(e.selectedComponent, 0);
      await run(tester, e.undo);
      expect(maskOf(e).components.length, 2);
    });

    etest('a Feather drag is one undo step and Invert is one more', (
      tester,
    ) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(RadialShape()));
      await openTab(tester, 'Mask');
      final feather = find.descendant(
        of: find.byKey(const ValueKey('mask-feather-0')),
        matching: find.byType(CupertinoSlider),
      );
      await dragTo(tester, feather, 0.9);
      final r = maskOf(e).components.single.shape as RadialShape;
      expect(r.feather, greaterThan(75));
      await reveal(tester, find.byType(CupertinoSwitch));
      await tester.tap(find.byType(CupertinoSwitch));
      await settle(tester);
      expect((maskOf(e).components.single.shape as RadialShape).invert, isTrue);
      await run(tester, e.undo);
      await run(tester, e.undo);
      expect(maskOf(e).components.single.shape, RadialShape());
    });

    etest('Show mask is the controller switch', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(const SubjectShape()));
      expect(e.showOverlay, isFalse);
      await tester.tap(find.text('Show mask'));
      await tester.pump();
      expect(e.showOverlay, isTrue);
      await tester.tap(find.text('Show mask'));
      await tester.pump();
      expect(e.showOverlay, isFalse);
      await tester.tap(find.text('Show mask'));
      await tester.pump();
      await run(tester, e.undo);
      expect(masksOf(e), isEmpty);
      expect(e.canUndo, isFalse, reason: 'Show mask adds no undo step');
      expect(e.showOverlay, isTrue);
      await run(tester, () => e.addMask(const SubjectShape()));
      await openTab(tester, 'Mask');
      expect(
        find.text('Found automatically. Brush or subtract to fix it.'),
        findsOneWidget,
      );
    });

    etest('brush settings are kept for new strokes', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(BrushShape(const [])));
      await openTab(tester, 'Mask');
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Flow'), findsOneWidget);
      await tester.tap(find.text('Erase'));
      await tester.pump();
      expect(e.brushErase, isTrue);
      final flow = find.descendant(
        of: find.byKey(const ValueKey('mask-brush-flow')),
        matching: find.byType(CupertinoSlider),
      );
      await dragTo(tester, flow, 0.5);
      expect(e.brushFlow, lessThan(90));
      expect(
        maskOf(e).components.single.shape,
        BrushShape(const []),
        reason: 'brush settings are not part of the look',
      );
    });
  });

  group('every control is in view', () {
    for (final size in const [Size(390, 844), Size(320, 568)]) {
      final w = size.width.toInt();
      etest('adjust tabs at $w', (tester) async {
        final e = await open(tester, ToolPanel.masks, size: size);
        await run(tester, () => e.addMask(RadialShape()));
        for (final t in kAdjustTabs.keys) {
          await openTab(tester, t);
          expect(overflow(tester), 0, reason: t);
        }
      });
      etest('each shape, alone and four of a kind, at $w', (tester) async {
        final e = await open(tester, ToolPanel.masks, size: size);
        for (final k in kMaskKinds.entries) {
          await run(tester, () => e.addMask(k.value()));
          if (k.key == 'Subject') await openTab(tester, 'Mask');
          expect(overflow(tester), 0, reason: '${k.key} alone');
          await run(tester, () async {
            final id = e.selectedMaskId!;
            await e.addComponent(id, k.value(), MaskOp.add);
            await e.addComponent(id, k.value(), MaskOp.subtract);
            await e.addComponent(id, k.value(), MaskOp.intersect);
          });
          for (final i in [3, 1]) {
            e.selectComponent(i);
            await tester.pump();
            expect(overflow(tester), 0, reason: '${k.key} shape ${i + 1}');
          }
        }
      });
    }
  });

  group('developed photo', () {
    etest('a hidden mask leaves the photo as it was', (tester) async {
      final out = await tester.runAsync(() async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        for (var x = 0; x < 64; x += 8) {
          canvas.drawRect(
            ui.Rect.fromLTWH(x.toDouble(), 0, 8, 64),
            ui.Paint()..color = ui.Color.fromARGB(255, 40 + x, 90, 160 - x),
          );
        }
        final src = await rec.endRecording().toImage(64, 64);
        Mask mask({required bool visible}) => Mask(
          id: 'm1',
          name: 'Mask 1',
          components: [MaskComponent(RadialShape())],
          adjust: const {Setting.exposure: 1.5},
          visible: visible,
        );
        Future<Uint8List> dev(List<Mask> masks) async {
          final img = await CpuDeveloper().develop(
            src,
            EditSettings.resolve([SettingsPatch(masks: masks)]),
          );
          final bd = await img.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          );
          return bd!.buffer.asUint8List();
        }

        return [
          await dev(const []),
          await dev([mask(visible: false)]),
          await dev([mask(visible: true)]),
        ];
      });
      final [none, hidden, shown] = out!;
      expect(hidden, none);
      expect(shown, isNot(none), reason: 'the shown mask brightens the middle');
    });
  });

  group('controller', () {
    etest('previewMaskValue then endChange is one step', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(RadialShape()));
      final id = e.selectedMaskId!;
      e.previewMaskValue(id, Setting.clarity, 20);
      e.previewMaskValue(id, Setting.clarity, 40);
      expect(maskOf(e).adjust[Setting.clarity], 40);
      await run(tester, e.endChange);
      await run(tester, () => e.setMaskValue(id, Setting.dehaze, 10));
      await run(tester, e.undo);
      expect(maskOf(e).adjust, {Setting.clarity: 40.0});
      await run(tester, e.undo);
      expect(maskOf(e).adjust, isEmpty);
    });

    etest('updateShape drags are one step; switching photos drops the '
        'selection', (tester) async {
      final e = await open(tester, ToolPanel.masks);
      await run(tester, () => e.addMask(LinearShape(.5, .25, .5, .75)));
      final id = e.selectedMaskId!;
      e.beginChange();
      e.previewShape(id, 0, LinearShape(.5, .3, .5, .8));
      e.previewShape(id, 0, LinearShape(.5, .4, .5, .9));
      await run(tester, e.endChange);
      expect(maskOf(e).components.single.shape, LinearShape(.5, .4, .5, .9));
      await run(
        tester,
        () => e.updateShape(id, 0, LinearShape(.1, .1, .9, .9)),
      );
      await run(tester, e.undo);
      expect(maskOf(e).components.single.shape, LinearShape(.5, .4, .5, .9));
      await run(tester, () => e.showPhoto(1));
      expect(e.selectedMaskId, isNull);
      expect(masksOf(e), isEmpty, reason: 'masks belong to one photo');
    });
  });

  group('goldens', () {
    Future<PhotoEditorController> scene(
      WidgetTester tester, {
      Size size = const Size(390, 844),
      Brightness b = Brightness.light,
    }) async {
      final e = await open(tester, ToolPanel.masks, size: size, b: b);
      await run(tester, () async {
        await e.addMask(RadialShape());
        await e.setMaskValue(e.selectedMaskId!, Setting.exposure, 0.6);
        await e.setMaskValue(e.selectedMaskId!, Setting.clarity, 25);
        await e.addComponent(
          e.selectedMaskId!,
          LuminanceRangeShape(),
          MaskOp.subtract,
        );
        await e.addMask(LinearShape(.5, .25, .5, .75));
        await e.setMaskVisible(e.selectedMaskId!, false);
        await e.addMask(BrushShape(const []));
        await e.renameMask(e.selectedMaskId!, 'Warm the path');
      });
      await settle(tester);
      return e;
    }

    Finder panel() => find
        .ancestor(
          of: find.byType(DevelopPanelShell),
          matching: find.byType(Container),
        )
        .first;

    const cases = {
      '': (Size(390, 844), Brightness.light),
      '_dark': (Size(390, 844), Brightness.dark),
      '_320': (Size(320, 568), Brightness.light),
    };

    for (final c in cases.entries) {
      final (size, b) = c.value;
      etest('mask list${c.key}', (tester) async {
        final e = await scene(tester, size: size, b: b);
        e.selectMask(null);
        await tester.pump();
        await expectLater(
          panel(),
          matchesGoldenFile('goldens/masks_list${c.key}.png'),
        );
      });
      etest('mask adjust${c.key}', (tester) async {
        final e = await scene(tester, size: size, b: b);
        e.selectMask(masksOf(e).first.id);
        e.setShowOverlay(true);
        await tester.pump();
        await expectLater(
          panel(),
          matchesGoldenFile('goldens/masks_adjust${c.key}.png'),
        );
      });
      etest('mask shapes${c.key}', (tester) async {
        final e = await scene(tester, size: size, b: b);
        e.selectMask(masksOf(e).first.id);
        await tester.pump();
        await openTab(tester, 'Mask');
        await expectLater(
          panel(),
          matchesGoldenFile('goldens/masks_shapes${c.key}.png'),
        );
      });
      etest('mask add sheet${c.key}', (tester) async {
        final e = await scene(tester, size: size, b: b);
        e.selectMask(null);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('mask-add')));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(AppActionSheet),
          matchesGoldenFile('goldens/masks_add_sheet${c.key}.png'),
        );
      });
    }
  });
}
