import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/batch_look.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/presets/preset.dart';
import 'package:pio_photo_layout/core/render/sample_scene.dart';
import 'package:pio_photo_layout/core/store/batch_store_memory.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/preset_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/features/home/home_screen.dart';
import 'package:pio_photo_layout/features/home/home_wiring.dart';
import 'package:pio_photo_layout/features/home/preset_picker.dart';
import 'package:pio_photo_layout/platform/device_noun.dart';
import 'package:pio_photo_layout/platform/file_sharer.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/platform/temp_files_memory.dart';
import 'package:pio_photo_layout/ui/widgets/action_sheet.dart';
import 'package:pio_photo_layout/ui/widgets/toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/presets/fixtures.dart';
import '../../ui/golden_helpers.dart';
import 'home_controller_test.dart' show picked;
import 'home_golden_test.dart' show newController, ready;

SettingsPatch exposure(double v) =>
    SettingsPatch(values: {Setting.exposure: v});

Future<Preset> addPreset(HomeController c, String name, double ev) =>
    c.savePreset(name, EditSettings.resolve([exposure(ev)]));

HomeController noDeveloper() => HomeController(
  layoutStore: MemoryLayoutStore(),
  settingsStore: SettingsStore(),
  picker: FakePhotoPicker(),
  saver: FakeGallerySaver(),
  sharer: FakeFileSharer(),
  temp: MemoryTempFiles(),
  presetStore: MemoryPresetStore(),
  batchStore: MemoryBatchStore(),
  fontStore: MemoryFontStore(),
);

/// A widget test that ends with no toast or timer left behind.
void ptest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    hideToast();
    await tester.pumpWidget(const SizedBox());
  });
}

void setView(WidgetTester tester, Size size, double dpr) {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
}

Future<void> pumpHome(
  WidgetTester tester,
  HomeController c, {
  Brightness b = Brightness.light,
  Size size = const Size(390, 844),
  double dpr = 2,
}) async {
  setView(tester, size, dpr);
  await tester.pumpWidget(
    themed(HomeScreen(controller: c, actions: homeActions(c)), b),
  );
  await tester.pump();
}

/// Waits (real time) for picker thumbnails, then draws them.
Future<void> settleThumbs(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
  }
}

Future<void> openPicker(WidgetTester tester) async {
  await tester.tap(find.text('Preset'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'developPreview applies a preset to an image, and is null without a developer',
    () async {
      final c = newController();
      await c.init();
      final src = await sampleSceneImage(48, 48);
      final p = await addPreset(c, 'Bright', 1.5);
      final out = (await c.developPreview(src, 96, p))!;
      expect((out.width, out.height), (48, 48));
      final a = (await src.toByteData())!.buffer.asUint8List();
      final b = (await out.toByteData())!.buffer.asUint8List();
      expect(b, isNot(equals(a)));
      out.dispose();
      src.dispose();
      c.dispose();

      final bare = noDeveloper();
      final s2 = await sampleSceneImage(8, 8);
      expect(await bare.developPreview(s2, 8, p), isNull);
      s2.dispose();
      bare.dispose();
    },
  );

  ptest('the preset row shows None, a name, then Custom', (tester) async {
    final c = await ready(tester);
    await pumpHome(tester, c);
    expect(find.text('Preset'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    final warm = (await tester.runAsync(() => addPreset(c, 'Warm', 0.3)))!;
    await tester.runAsync(() => c.choosePresetForAll(warm));
    await tester.pump();
    expect(find.text('Warm'), findsOneWidget);
    await tester.runAsync(
      () => c.setLook(const BatchLook().withPresetForAll(exposure(0.2), null)),
    );
    await tester.pump();
    expect(find.text('Custom'), findsOneWidget);
  });

  ptest('the preset row is hidden when editing is not available', (
    tester,
  ) async {
    final c = noDeveloper();
    await tester.runAsync(() async {
      await loadAppFonts();
      await c.init();
    });
    addTearDown(c.dispose);
    await pumpHome(tester, c);
    expect(find.text('Preset'), findsNothing);
  });

  ptest('choosing in the picker sets the shared preset', (tester) async {
    final c = await ready(tester);
    await tester.runAsync(() => addPreset(c, 'Warm', 0.3));
    await pumpHome(tester, c);
    await openPicker(tester);
    expect(find.text('Presets'), findsOneWidget);
    expect(find.text('YOUR PRESETS'), findsOneWidget);
    await tester.tap(find.text('Warm'));
    await tester.pumpAndSettle();
    expect(c.look.sharedName, 'Warm');
    expect(find.text('Presets'), findsNothing);
  });

  ptest('the picker shows the empty note and the import button', (
    tester,
  ) async {
    final c = await ready(tester);
    await pumpHome(tester, c);
    await openPicker(tester);
    expect(
      find.text(
        'No presets yet. Import a Lightroom preset, or make one in the photo editor with Save as preset.',
      ),
      findsOneWidget,
    );
    expect(find.text('Import a Lightroom preset'), findsOneWidget);
    expect(find.byKey(const Key('preset-check-none')), findsOneWidget);
  });

  ptest('long-press opens Share and Delete, and Delete removes the preset', (
    tester,
  ) async {
    final c = await ready(tester);
    await tester.runAsync(() => addPreset(c, 'Warm', 0.3));
    await pumpHome(tester, c);
    await openPicker(tester);
    await tester.longPress(find.text('Warm'));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(c.presets, isEmpty);
  });

  ptest('Import shows the returned line as a toast', (tester) async {
    final c = await ready(tester);
    (c.picker as FakePhotoPicker).nextFiles = [
      picked('Soft.xmp', Uint8List.fromList(utf8.encode(presetXmp()))),
    ];
    await pumpHome(tester, c);
    await openPicker(tester);
    await tester.tap(find.text('Import a Lightroom preset'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.presets, isNotEmpty);
    expect(find.byType(ToastView), findsOneWidget);
    expect(
      tester.widget<ToastView>(find.byType(ToastView)).message,
      isNotEmpty,
    );
  });

  ptest('the dot shows only on the photo with its own changes', (tester) async {
    final c = await ready(tester, withPhotos: true);
    await pumpHome(tester, c);
    expect(find.byKey(const Key('own-changes-dot')), findsNothing);
    await tester.runAsync(
      () => c.setLook(c.look.withPhotoPatch(c.photos[1].id, exposure(0.5))),
    );
    await tester.pump();
    expect(find.byKey(const Key('own-changes-dot')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('own-changes-dot'))),
      const Size(8, 8),
    );
  });

  ptest('the kept caption sits under the Photos title', (tester) async {
    final c = await ready(tester, withPhotos: true);
    await pumpHome(tester, c);
    expect(find.textContaining('Kept on this $deviceNoun: '), findsOneWidget);
  });

  ptest('Clear asks first, then empties', (tester) async {
    final c = await ready(tester, withPhotos: true);
    await pumpHome(tester, c);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all photos?'), findsOneWidget);
    expect(
      find.text(
        'The photos and their edits are removed from e-Layout. Your original photos are not touched.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.photos, isNotEmpty);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AppDialog), matching: find.text('Clear')),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(c.photos, isEmpty);
  });

  // ---- goldens ----
  Future<HomeController> withLook(WidgetTester tester) async {
    final c = await ready(tester, withPhotos: true);
    final warm = (await tester.runAsync(() => addPreset(c, 'Warm', 0.4)))!;
    await tester.runAsync(() async {
      await c.choosePresetForAll(warm);
      await c.setLook(c.look.withPhotoPatch(c.photos[1].id, exposure(-0.6)));
      await c.whenIdle();
    });
    return c;
  }

  Future<void> shootHome(
    WidgetTester tester,
    HomeController c,
    Brightness b,
    String name, {
    Size size = const Size(390, 844),
    double dpr = 2,
  }) async {
    await pumpHome(tester, c, b: b, size: size, dpr: dpr);
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  for (final b in Brightness.values) {
    final tag = b == Brightness.dark ? 'dark' : 'light';
    ptest('golden home preset $tag', (tester) async {
      final c = await withLook(tester);
      await shootHome(tester, c, b, 'home_preset_$tag');
    });
  }

  ptest('golden home preset wide', (tester) async {
    final c = await withLook(tester);
    await shootHome(
      tester,
      c,
      Brightness.light,
      'home_preset_wide',
      size: const Size(1280, 800),
      dpr: 1,
    );
  });

  Future<void> shootPicker(
    WidgetTester tester,
    HomeController c,
    Brightness b,
    String name,
  ) async {
    setView(tester, const Size(390, 844), 2);
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                onPressed: () => showPresetPicker(context, c),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        b,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await settleThumbs(tester);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  ptest('golden picker light', (tester) async {
    final c = await ready(tester, withPhotos: true);
    await tester.runAsync(() async {
      await addPreset(c, 'Warm', 0.4);
      await addPreset(c, 'Moody', -0.5);
      await c.importPresets([
        picked('Soft.xmp', Uint8List.fromList(utf8.encode(presetXmp()))),
      ]);
      await c.choosePresetForAll(c.presets.first);
    });
    await shootPicker(tester, c, Brightness.light, 'preset_picker_light');
  });

  ptest('golden picker empty dark', (tester) async {
    final c = await ready(tester);
    await shootPicker(tester, c, Brightness.dark, 'preset_picker_empty_dark');
  });
}
