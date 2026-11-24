import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/presets/preset.dart';
import 'package:pio_photo_layout/features/develop/copy_sheet.dart';
import 'package:pio_photo_layout/features/develop/panels/panel_presets.dart';
import 'package:pio_photo_layout/features/develop/photo_editor_controller.dart';
import 'package:pio_photo_layout/features/develop/save_preset_sheet.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/ui/widgets/app_button.dart';
import 'package:pio_photo_layout/ui/widgets/toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/presets/fixtures.dart';
import '../editor/editor_screen_test.dart' show etest;
import '../home/home_controller_test.dart' show picked;
import 'photo_editor_test.dart'
    show editorOn, exposure, homeWith, pumpEditor, settle;

Future<Preset> addPreset(
  WidgetTester tester,
  HomeController c,
  String name,
) async => (await tester.runAsync(
  () => c.savePreset(
    name,
    EditSettings.resolve([
      SettingsPatch(values: {Setting.exposure: 0.8}),
    ]),
  ),
))!;

Future<PhotoEditorController> open(
  WidgetTester tester, {
  int n = 3,
  Size size = const Size(390, 844),
  Brightness b = Brightness.light,
  bool panel = true,
}) async {
  final home = await homeWith(tester, n: n);
  final e = editorOn(home, 0);
  if (panel) e.setPanel(ToolPanel.presets);
  await pumpEditor(tester, e, size: size, b: b);
  return e;
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(CupertinoIcons.ellipsis_circle));
  await tester.pumpAndSettle();
}

Finder inSheet(Type t, Finder f) =>
    find.descendant(of: find.byType(t), matching: f);

Future<void> waitFor(WidgetTester tester, bool Function() ok) =>
    settle(tester, until: ok);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('presets panel', () {
    etest('with no presets it shows Import and a caption', (tester) async {
      await open(tester);
      expect(find.text('No presets of your own yet.'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    });

    etest('cards: yours, then imported, then Import', (tester) async {
      final e = await open(tester, panel: false);
      await addPreset(tester, e.home, 'Brisk');
      await tester.runAsync(
        () => e.home.importPresets([
          picked('Soft.xmp', Uint8List.fromList(utf8.encode(presetXmp()))),
        ]),
      );
      e.setPanel(ToolPanel.presets);
      await tester.pump();
      await settle(tester);
      expect(find.text('No presets of your own yet.'), findsNothing);
      double x(String t) => tester.getTopLeft(find.text(t)).dx;
      expect(x('Import'), lessThan(x('Brisk')));
      expect(x('Brisk'), lessThan(x('Soft Test')));
    });

    etest('Import comes first, then your presets, then the built-in looks', (
      tester,
    ) async {
      final e = await open(tester, panel: false);
      await addPreset(tester, e.home, 'Brisk');
      e.setPanel(ToolPanel.presets);
      await tester.pump();
      await settle(tester);
      expect(find.text('Built-in'), findsOneWidget);
      expect(find.text('Your presets'), findsOneWidget);
      double x(String t) => tester.getTopLeft(find.text(t)).dx;
      expect(x('Import'), lessThan(x('Your presets')));
      expect(x('Your presets'), lessThanOrEqualTo(x('Brisk')));
      expect(x('Brisk'), lessThan(x('Built-in')));
      expect(x('Built-in'), lessThanOrEqualTo(x('Warm')));
      expect(x('Warm'), lessThan(x('Cool')));
      expect(x('Cool'), lessThan(x('Sepia')));
    });

    etest('with none of your own, Import is followed by the built-ins', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Your presets'), findsNothing);
      double x(String t) => tester.getTopLeft(find.text(t)).dx;
      expect(x('Import'), lessThan(x('Built-in')));
      expect(x('Built-in'), lessThanOrEqualTo(x('Warm')));
    });

    etest('a built-in card applies its look to this photo only', (
      tester,
    ) async {
      final e = await open(tester);
      final [a, b, _] = e.home.readyPhotos;
      await tester.tap(find.text('Warm'));
      await tester.pump();
      await waitFor(
        tester,
        () => e.home.settingsFor(a)[Setting.temperature] > 0,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('"Warm" is on this photo.'), findsOneWidget);
      hideToast();
      expect(e.home.settingsFor(b)[Setting.temperature], 0);
    });

    etest('a card applies to this photo only, with its toast', (tester) async {
      final e = await open(tester, panel: false);
      await addPreset(tester, e.home, 'Brisk');
      e.setPanel(ToolPanel.presets);
      await tester.pump();
      await settle(tester);
      final [a, b, _] = e.home.readyPhotos;
      await tester.ensureVisible(find.text('Brisk'));
      await tester.tap(find.text('Brisk'));
      await tester.pump();
      await waitFor(
        tester,
        () => e.home.settingsFor(a)[Setting.exposure] == 0.8,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('"Brisk" is on this photo.'), findsOneWidget);
      hideToast();
      expect(e.home.settingsFor(b)[Setting.exposure], 0);
      expect(e.home.hasOwnChanges(a), isTrue);
      expect(e.home.hasOwnChanges(b), isFalse);
      // one undo step
      await tester.tap(find.byIcon(CupertinoIcons.arrow_uturn_left));
      await tester.pump();
      await waitFor(tester, () => e.home.settingsFor(a)[Setting.exposure] == 0);
      expect(e.canUndo, isFalse);
    });

    etest('Import toasts the line it gets back', (tester) async {
      final e = await open(tester);
      (e.home.picker as FakePhotoPicker).nextFiles = [
        picked('Soft.xmp', Uint8List.fromList(utf8.encode(presetXmp()))),
      ];
      await tester.ensureVisible(find.text('Import'));
      await tester.tap(find.text('Import'));
      await tester.pump();
      await waitFor(tester, () => e.home.presets.isNotEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ToastView), findsOneWidget);
      expect(find.text('Soft Test'), findsOneWidget);
      hideToast();
    });

    etest('Import cancelled shows nothing', (tester) async {
      await open(tester);
      await tester.ensureVisible(find.text('Import'));
      await tester.tap(find.text('Import'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ToastView), findsNothing);
    });
  });

  group('copy to all', () {
    Future<PhotoEditorController> sheet(
      WidgetTester tester, {
      int n = 3,
    }) async {
      final e = await open(tester, n: n, panel: false);
      await tester.runAsync(() => e.setValue(Setting.exposure, 1));
      await settle(tester);
      await openMenu(tester);
      await tester.tap(find.text('Copy to all'));
      await tester.pumpAndSettle();
      return e;
    }

    etest('the sheet has the groups, the switch and the button', (
      tester,
    ) async {
      await sheet(tester);
      expect(find.text('Copy to all photos'), findsOneWidget);
      for (final t in ['Light', 'Colour', 'Effects', 'Detail']) {
        expect(inSheet(CopyToAllSheet, find.text(t)), findsOneWidget);
      }
      expect(find.text('Keep changes made on single photos'), findsOneWidget);
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isTrue,
      );
      expect(find.text('Copy to 2 photos'), findsOneWidget);
    });

    etest('one other photo reads singular', (tester) async {
      await sheet(tester, n: 2);
      expect(find.text('Copy to 1 photo'), findsOneWidget);
    });

    etest('no group checked disables the button', (tester) async {
      await sheet(tester);
      for (final t in ['Light', 'Colour', 'Effects', 'Detail']) {
        await tester.tap(inSheet(CopyToAllSheet, find.text(t)));
        await tester.pump();
      }
      final b = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Copy to 2 photos'),
      );
      expect(b.onPressed, isNull);
      await tester.tap(inSheet(CopyToAllSheet, find.text('Light')));
      await tester.pump();
      final b2 = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Copy to 2 photos'),
      );
      expect(b2.onPressed, isNotNull);
    });

    etest('only the checked groups are copied', (tester) async {
      final e = await open(tester, panel: false);
      await tester.runAsync(() async {
        await e.setValue(Setting.exposure, 1);
        await e.setValue(Setting.saturation, 40);
      });
      await settle(tester);
      await openMenu(tester);
      await tester.tap(find.text('Copy to all'));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(CopyToAllSheet, find.text('Colour')));
      await tester.pump();
      await tester.tap(find.text('Copy to 2 photos'));
      await tester.pump();
      final b = e.home.readyPhotos[1];
      await waitFor(tester, () => e.home.settingsFor(b)[Setting.exposure] == 1);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Copied to 2 photos.'), findsOneWidget);
      hideToast();
      expect(e.home.settingsFor(b)[Setting.saturation], 0);
      // one undo step
      await tester.tap(find.byIcon(CupertinoIcons.arrow_uturn_left));
      await tester.pump();
      await waitFor(tester, () => e.home.settingsFor(b)[Setting.exposure] == 0);
    });

    etest('the switch decides if single changes stay', (tester) async {
      final home = await homeWith(tester, n: 3);
      final [a, b, d] = home.readyPhotos;
      await tester.runAsync(
        () => home.setLook(home.look.withPhotoPatch(d.id, exposure(-0.5))),
      );
      final e = editorOn(home, 0);
      await pumpEditor(tester, e);
      await tester.runAsync(() => e.setValue(Setting.exposure, 1));
      await settle(tester);
      await openMenu(tester);
      await tester.tap(find.text('Copy to all'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pump();
      await tester.tap(find.text('Copy to 2 photos'));
      await tester.pump();
      await waitFor(tester, () => home.settingsFor(d)[Setting.exposure] == 1);
      expect(
        [
          for (final p in [a, b, d]) home.settingsFor(p)[Setting.exposure],
        ],
        [1, 1, 1],
      );
      await tester.pump(const Duration(seconds: 1));
      hideToast();
    });

    etest('a single photo disables the button', (tester) async {
      await sheet(tester, n: 1);
      final b = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Copy to 0 photos'),
      );
      expect(b.onPressed, isNull);
    });
  });

  group('save as preset', () {
    Future<PhotoEditorController> sheet(WidgetTester tester) async {
      final e = await open(tester, panel: false);
      await tester.runAsync(() => e.setValue(Setting.exposure, 1));
      await settle(tester);
      await openMenu(tester);
      await tester.tap(find.text('Save as preset'));
      await tester.pumpAndSettle();
      return e;
    }

    AppButton save(WidgetTester tester) =>
        tester.widget<AppButton>(find.widgetWithText(AppButton, 'Save'));

    etest('an empty or blank name keeps Save disabled', (tester) async {
      await sheet(tester);
      expect(find.text('Preset name'), findsOneWidget);
      expect(save(tester).onPressed, isNull);
      await tester.enterText(find.byType(CupertinoTextField), '   ');
      await tester.pump();
      expect(save(tester).onPressed, isNull);
    });

    etest('the name stops at 80 characters', (tester) async {
      await sheet(tester);
      await tester.enterText(find.byType(CupertinoTextField), 'x' * 100);
      await tester.pump();
      final f = tester.widget<EditableText>(find.byType(EditableText));
      expect(f.controller.text.length, 80);
    });

    etest('Save keeps the preset, trimmed, with its toast', (tester) async {
      final e = await sheet(tester);
      await tester.enterText(find.byType(CupertinoTextField), '  Sunny  ');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pump();
      await waitFor(tester, () => e.home.presets.isNotEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Saved "Sunny".'), findsOneWidget);
      hideToast();
      expect(e.home.presets.single.name, 'Sunny');
      expect(e.home.presets.single.kind, PresetKind.user);
      // and it shows in "Your presets"
      e.setPanel(ToolPanel.presets);
      await tester.pump();
      await settle(tester);
      expect(find.text('Sunny'), findsOneWidget);
    });
  });

  group('reset', () {
    etest('is disabled without changes of its own', (tester) async {
      await open(tester, panel: false);
      await openMenu(tester);
      final row = find.widgetWithText(Semantics, 'Reset this photo');
      expect(row, findsWidgets);
      await tester.tap(find.text('Reset this photo'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // The menu stays open and nothing is shown.
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byType(ToastView), findsNothing);
    });

    etest('is one undo step and toasts', (tester) async {
      final e = await open(tester, panel: false);
      await tester.runAsync(() => e.setValue(Setting.exposure, 1));
      await settle(tester);
      await openMenu(tester);
      await tester.tap(find.text('Reset this photo'));
      await tester.pump();
      await waitFor(tester, () => !e.hasOwnChanges);
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('This photo is back to the shared preset.'),
        findsOneWidget,
      );
      hideToast();
      await tester.tap(find.byIcon(CupertinoIcons.arrow_uturn_left));
      await tester.pump();
      await waitFor(tester, () => e.hasOwnChanges);
    });
  });

  group('goldens', () {
    for (final b in Brightness.values) {
      final tag = b == Brightness.dark ? 'dark' : 'light';
      etest('copy sheet $tag', (tester) async {
        final e = await open(tester, b: b, panel: false);
        await tester.runAsync(() => e.setValue(Setting.exposure, 1));
        await settle(tester);
        await openMenu(tester);
        await tester.tap(find.text('Copy to all'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(CopyToAllSheet),
          matchesGoldenFile('goldens/copy_sheet_$tag.png'),
        );
      });
    }

    for (final end in [false, true]) {
      etest('presets panel${end ? ' your presets' : ''}', (tester) async {
        final e = await open(tester, panel: false);
        for (final n in ['Brisk', 'Cool fade', 'Soft glow']) {
          await addPreset(tester, e.home, n);
        }
        await tester.runAsync(
          () => e.home.importPresets([
            picked('Soft.xmp', Uint8List.fromList(utf8.encode(presetXmp()))),
          ]),
        );
        e.setPanel(ToolPanel.presets);
        await tester.pump();
        await settle(tester);
        if (end) {
          Scrollable.ensureVisible(
            tester.element(find.text('Your presets')),
            alignment: 0,
          );
          await tester.pump();
        }
        for (var i = 0; i < (end ? 70 : 25); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          await tester.pump();
        }
        await expectLater(
          find.byType(PresetsPanel),
          matchesGoldenFile(
            end
                ? 'goldens/presets_panel_yours.png'
                : 'goldens/presets_panel.png',
          ),
        );
      });
    }

    for (final b in Brightness.values) {
      final tag = b == Brightness.dark ? '_dark' : '';
      etest('save preset sheet$tag', (tester) async {
        await open(tester, b: b, panel: false);
        await openMenu(tester);
        await tester.tap(find.text('Save as preset'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(CupertinoTextField), 'Sunny day');
        await tester.pump();
        await expectLater(
          find.byType(SavePresetSheet),
          matchesGoldenFile('goldens/save_preset_sheet$tag.png'),
        );
      });
    }
  });
}
