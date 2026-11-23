import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart' show ZLibEncoder, getCrc32;
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/develop/profile_table.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/store/batch_store.dart';
import 'package:pio_photo_layout/core/store/batch_store_memory.dart';
import 'package:pio_photo_layout/core/store/font_store_memory.dart';
import 'package:pio_photo_layout/core/store/layout_store_memory.dart';
import 'package:pio_photo_layout/core/store/preset_store_memory.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/develop/develop_canvas.dart';
import 'package:pio_photo_layout/features/develop/photo_editor_controller.dart';
import 'package:pio_photo_layout/features/develop/photo_editor_screen.dart';
import 'package:pio_photo_layout/features/home/home_controller.dart';
import 'package:pio_photo_layout/features/home/home_screen.dart';
import 'package:pio_photo_layout/features/home/home_wiring.dart';
import 'package:pio_photo_layout/features/viewer/photo_viewer.dart';
import 'package:pio_photo_layout/platform/file_sharer.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';
import 'package:pio_photo_layout/platform/photo_picker.dart';
import 'package:pio_photo_layout/platform/temp_files_memory.dart';
import 'package:pio_photo_layout/ui/previews.dart';
import 'package:pio_photo_layout/ui/widgets/toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/golden_helpers.dart';
import '../editor/editor_screen_test.dart' show etest;
import '../home/home_golden_test.dart' show samplePhotos;

/// Counts manifest writes (one per saved look).
class CountingBatchStore extends MemoryBatchStore {
  int saves = 0;

  @override
  Future<void> saveManifest(BatchManifest m) {
    saves++;
    return super.saveManifest(m);
  }
}

/// Remembers the colour table size of every render.
class LutLog extends CpuDeveloper {
  final luts = <int>[];

  @override
  Future<ui.Image> develop(
    ui.Image src,
    EditSettings s, {
    ProfileTable? profile,
    double scale = 1,
    ui.Offset origin = ui.Offset.zero,
    ui.Size? fullSize,
    int lutSize = 33,
    DevelopStats? stats,
  }) {
    luts.add(lutSize);
    return super.develop(
      src,
      s,
      profile: profile,
      scale: scale,
      origin: origin,
      fullSize: fullSize,
      lutSize: lutSize,
      stats: stats,
    );
  }
}

SettingsPatch exposure(double v) =>
    SettingsPatch(values: {Setting.exposure: v});

HomeController newHome({BatchStore? batch, bool editing = true}) =>
    HomeController(
      layoutStore: MemoryLayoutStore(),
      settingsStore: SettingsStore(),
      picker: FakePhotoPicker(),
      saver: FakeGallerySaver(),
      sharer: FakeFileSharer(),
      temp: MemoryTempFiles(),
      presetStore: MemoryPresetStore(),
      batchStore: batch ?? MemoryBatchStore(),
      developer: editing ? CpuDeveloper() : null,
      fontStore: MemoryFontStore(),
    );

/// Home with [n] of the sample photos (or [photos]), ready.
Future<HomeController> homeWith(
  WidgetTester tester, {
  int n = 3,
  List<PickedPhoto>? photos,
  BatchStore? batch,
  bool editing = true,
}) async {
  final c = newHome(batch: batch, editing: editing);
  await tester.runAsync(() async {
    await loadAppFonts();
    await c.init();
    await c.addPhotos(photos ?? (await samplePhotos()).take(n).toList());
    await c.whenIdle();
  });
  addTearDown(c.dispose);
  return c;
}

PhotoEditorController editorOn(
  HomeController home,
  int index, {
  PhotoDeveloper? developer,
}) {
  final e = PhotoEditorController(
    home: home,
    photoId: home.readyPhotos[index].id,
    developer: developer ?? home.developer!,
  );
  addTearDown(e.dispose);
  return e;
}

void setView(WidgetTester tester, Size size, double dpr) {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
}

Future<void> pumpEditor(
  WidgetTester tester,
  PhotoEditorController e, {
  Brightness b = Brightness.light,
  Size size = const Size(390, 844),
  double dpr = 2,
}) async {
  setView(tester, size, dpr);
  await tester.pumpWidget(themed(PhotoEditorScreen(controller: e), b));
  await tester.pump();
  await settle(tester);
}

DevelopCanvasState canvasState(WidgetTester tester) =>
    tester.state<DevelopCanvasState>(find.byType(DevelopCanvas));

/// Lets real time pass (decodes, renders) until the canvas has nothing left to do.
Future<void> settle(WidgetTester tester, {bool Function()? until}) async {
  var calm = 0;
  for (var i = 0; i < 400; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    final canvas = find.byType(DevelopCanvas);
    final idle = canvas.evaluate().isEmpty || canvasState(tester).idle;
    if (until != null) {
      if (until() && idle) return;
      continue;
    }
    calm = idle ? calm + 1 : 0;
    if (calm >= 3) return;
  }
  if (until != null) expect(until(), isTrue, reason: 'timed out waiting');
}

/// The canvas as it is on screen, in device pixels.
Future<ui.Image> shot(WidgetTester tester) async {
  final box = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byType(DevelopCanvas),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  return (await tester.runAsync(
    () => box.toImage(pixelRatio: tester.view.devicePixelRatio),
  ))!;
}

Future<Uint8List> rgbaOf(WidgetTester tester, ui.Image img) async {
  final bd = await tester.runAsync(
    () => img.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
  );
  return bd!.buffer.asUint8List();
}

/// Mean level of the middle of the canvas (inside the photo).
Future<double> meanOf(WidgetTester tester) async {
  final img = await shot(tester);
  final px = await rgbaOf(tester, img);
  final w = img.width, h = img.height;
  var sum = 0.0, n = 0;
  for (var y = h * 45 ~/ 100; y < h * 55 ~/ 100; y++) {
    for (var x = w ~/ 4; x < w * 3 ~/ 4; x++) {
      final i = (y * w + x) * 4;
      sum += px[i] + px[i + 1] + px[i + 2];
      n += 3;
    }
  }
  img.dispose();
  return sum / n;
}

/// A 1-bit grey PNG of a one-pixel checkerboard.
Uint8List checkerPng(int w, int h) {
  final stride = (w + 7) ~/ 8;
  final raw = Uint8List((stride + 1) * h);
  for (var y = 0; y < h; y++) {
    final row = y * (stride + 1);
    raw[row] = 0; // no filter
    raw.fillRange(row + 1, row + 1 + stride, y.isEven ? 0xAA : 0x55);
  }
  final out = BytesBuilder();
  void chunk(String type, List<int> data) {
    final len = ByteData(4)..setUint32(0, data.length);
    out.add(len.buffer.asUint8List());
    final body = [...type.codeUnits, ...data];
    out.add(body);
    final crc = ByteData(4)..setUint32(0, getCrc32(body));
    out.add(crc.buffer.asUint8List());
  }

  out.add([137, 80, 78, 71, 13, 10, 26, 10]);
  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 1) // bit depth
    ..setUint8(9, 0) // grey
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', const ZLibEncoder().encodeBytes(raw));
  chunk('IEND', const []);
  return out.toBytes();
}

/// Share of neighbouring pixels along the middle row that differ strongly.
Future<double> contrastOf(WidgetTester tester) async {
  final img = await shot(tester);
  final px = await rgbaOf(tester, img);
  final w = img.width, y = img.height ~/ 2;
  var strong = 0, n = 0;
  for (var x = w ~/ 4; x < w * 3 ~/ 4 - 1; x++) {
    final a = px[(y * w + x) * 4], b = px[(y * w + x + 1) * 4];
    if ((a - b).abs() > 120) strong++;
    n++;
  }
  img.dispose();
  return strong / n;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  etest('Edit in the viewer opens the editor on that photo', (tester) async {
    final c = await homeWith(tester);
    setView(tester, const Size(390, 844), 2);
    await tester.pumpWidget(
      themed(PhotoViewer(controller: c, initialIndex: 1), Brightness.dark),
    );
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final screen = tester.widget<PhotoEditorScreen>(
      find.byType(PhotoEditorScreen),
    );
    expect(screen.controller.photo.id, c.readyPhotos[1].id);
    // The editor takes the viewer's place, so Done goes back to Home.
    expect(find.byType(PhotoViewer, skipOffstage: false), findsNothing);
    await settle(tester);
  });

  etest('the viewer has no Edit when editing is not available', (tester) async {
    final c = await homeWith(tester, n: 1, editing: false);
    setView(tester, const Size(390, 844), 2);
    await tester.pumpWidget(
      themed(PhotoViewer(controller: c, initialIndex: 0), Brightness.dark),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.text('Save this photo'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
  });

  etest('a slider drag is one undo step and saves once at the end', (
    tester,
  ) async {
    final store = CountingBatchStore();
    final c = await homeWith(tester, n: 2, batch: store);
    final log = LutLog();
    final e = editorOn(c, 0, developer: log);
    final p = e.photo;
    await pumpEditor(tester, e);
    final look0 = c.look;
    final saves0 = store.saves;
    log.luts.clear();

    e.beginChange();
    for (final v in [0.3, 0.6, 1.0]) {
      e.preview(Setting.exposure, v);
      await settle(tester);
    }
    expect(
      identical(c.look, look0),
      isTrue,
      reason: 'Home keeps its look while dragging',
    );
    expect(e.settings[Setting.exposure], 1.0);
    expect(store.saves, saves0);
    expect(log.luts, isNotEmpty);
    expect(log.luts, everyElement(17), reason: 'quick tables while dragging');
    expect(e.canUndo, isFalse);

    log.luts.clear();
    await tester.runAsync(e.endChange);
    await settle(tester);
    expect(store.saves, saves0 + 1);
    expect(c.settingsFor(p)[Setting.exposure], 1.0);
    expect(log.luts, [33], reason: 'one fine render after the drag');
    expect(e.canUndo, isTrue);

    await tester.runAsync(e.undo);
    expect(c.settingsFor(p)[Setting.exposure], 0);
    expect(e.canUndo, isFalse);
    expect(e.canRedo, isTrue);
    await tester.runAsync(e.redo);
    expect(c.settingsFor(p)[Setting.exposure], 1.0);
    expect(e.canRedo, isFalse);
    await settle(tester);
  });

  etest('undo after copy to all restores every photo', (tester) async {
    final c = await homeWith(tester);
    final [a, b, d] = c.readyPhotos;
    await tester.runAsync(
      () => c.setLook(c.look.withPhotoPatch(d.id, exposure(-0.5))),
    );
    final e = editorOn(c, 0);
    await pumpEditor(tester, e);
    await tester.runAsync(() => e.setValue(Setting.exposure, 1));
    await settle(tester);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis_circle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy to all'));
    await tester.pumpAndSettle();
    expect(find.text('Copy to all photos'), findsOneWidget);
    await tester.tap(find.text('Copy to 2 photos'));
    await tester.pump();
    await settle(tester, until: () => c.settingsFor(b)[Setting.exposure] == 1);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Copied to 2 photos.'), findsOneWidget);
    hideToast();
    expect(
      [
        for (final p in [a, b, d]) c.settingsFor(p)[Setting.exposure],
      ],
      [1, 1, -0.5],
    );

    await tester.tap(find.byIcon(CupertinoIcons.arrow_uturn_left));
    await tester.pump();
    await settle(tester, until: () => c.settingsFor(b)[Setting.exposure] == 0);
    expect(
      [
        for (final p in [a, b, d]) c.settingsFor(p)[Setting.exposure],
      ],
      [1, 0, -0.5],
    );
    expect(c.hasOwnChanges(a), isTrue);
    expect(c.look.shared.isEmpty, isTrue);
    await settle(tester);
  });

  etest('hold shows the original and the "Original" label', (tester) async {
    final c = await homeWith(tester, n: 1);
    await tester.runAsync(
      () => c.setLook(c.look.withPhotoPatch(c.photos.first.id, exposure(1.5))),
    );
    final e = editorOn(c, 0);
    await pumpEditor(tester, e);
    final edited = await meanOf(tester);
    expect(find.text('Original'), findsNothing);

    final g = await tester.startGesture(
      tester.getCenter(find.byType(DevelopCanvas)),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(e.comparing, isTrue);
    expect(find.text('Original'), findsOneWidget);
    await settle(tester);
    final original = await meanOf(tester);
    expect(
      original,
      lessThan(edited - 20),
      reason: 'the undeveloped photo is darker',
    );

    await g.up();
    await tester.pump();
    expect(e.comparing, isFalse);
    expect(find.text('Original'), findsNothing);
    await settle(tester);
    expect(await meanOf(tester), closeTo(edited, 2));
  });

  etest('filmstrip switches photos and keeps the open panel', (tester) async {
    final c = await homeWith(tester);
    final e = editorOn(c, 0);
    await pumpEditor(tester, e);
    await tester.tap(find.text('Light'));
    await tester.pump();
    expect(e.panel, ToolPanel.light);
    expect(
      find.text('Presets'),
      findsNothing,
      reason: 'the panel replaces the tool strip',
    );

    final third = c.readyPhotos[2];
    await tester.tap(find.byKey(ValueKey('film-${third.id}')));
    await tester.pump();
    expect(e.photo.id, third.id);
    expect(e.panel, ToolPanel.light);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('3 of 3'), findsOneWidget);
    await settle(tester);

    await tester.tap(find.text('Done').last);
    await tester.pump();
    expect(e.panel, isNull);
    expect(find.text('Presets'), findsOneWidget);
  });

  etest('zoom to 100 % shows full-resolution pixels', (tester) async {
    final bytes = checkerPng(4000, 3000);
    final c = await homeWith(
      tester,
      photos: [
        PickedPhoto(
          name: 'checker.png',
          readBytes: () async => bytes,
          size: bytes.length,
        ),
      ],
    );
    final e = editorOn(c, 0);
    await pumpEditor(tester, e);
    expect(
      await contrastOf(tester),
      lessThan(0.2),
      reason: 'fitted, the checker is grey',
    );

    final at = tester.getCenter(find.byType(DevelopCanvas));
    final mouse = TestPointer(7, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(at));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    for (var i = 0; i < 12; i++) {
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -300)));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 200));
    final canvas = canvasState(tester);
    expect(canvas.zoomPercent, 100);
    await settle(tester, until: () => canvas.showsFullSize);
    expect(
      await contrastOf(tester),
      greaterThan(0.9),
      reason: 'every screen pixel is one photo pixel',
    );
  });

  etest('Done returns to Home and the grid cell shows the edit', (
    tester,
  ) async {
    final c = await homeWith(tester, n: 2);
    final p = c.readyPhotos[1];
    setView(tester, const Size(390, 844), 2);
    await tester.pumpWidget(
      themed(
        HomeScreen(controller: c, actions: homeActions(c)),
        Brightness.light,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(p.id)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final e = tester
        .widget<PhotoEditorScreen>(find.byType(PhotoEditorScreen))
        .controller;
    expect(e.photo.id, p.id);
    await tester.runAsync(() => e.setValue(Setting.exposure, 1.5));
    await settle(tester);

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PhotoEditorScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    await settle(tester, until: () => p.developed != null);
    await tester.pump();
    final painters = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byKey(ValueKey(p.id)),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((w) => w.painter)
        .whereType<CompositePainter>();
    expect(painters.map((x) => x.image), contains(same(p.developed)));
  });

  group('goldens', () {
    Future<PhotoEditorController> scene(WidgetTester tester) async {
      final c = await homeWith(tester, n: 6);
      final first = c.readyPhotos.first;
      await tester.runAsync(
        () => c.setLook(
          c.look.withPhotoPatch(
            first.id,
            SettingsPatch(
              values: {
                Setting.exposure: 0.4,
                Setting.saturation: 30,
                Setting.contrast: 15,
              },
            ),
          ),
        ),
      );
      return editorOn(c, 0);
    }

    for (final b in Brightness.values) {
      final tag = b == Brightness.dark ? 'dark' : 'light';
      etest('photo editor $tag', (tester) async {
        final e = await scene(tester);
        await pumpEditor(tester, e, b: b);
        await expectLater(
          find.byType(PhotoEditorScreen),
          matchesGoldenFile('goldens/photo_editor_$tag.png'),
        );
      });
    }

    etest('photo editor wide', (tester) async {
      final e = await scene(tester);
      await pumpEditor(tester, e, size: const Size(1280, 800), dpr: 1);
      expect(
        find.text('Presets'),
        findsOneWidget,
        reason: 'the tools are a row at the top of the side panel',
      );
      await expectLater(
        find.byType(PhotoEditorScreen),
        matchesGoldenFile('goldens/photo_editor_wide.png'),
      );
    });

    etest('photo editor compare', (tester) async {
      final e = await scene(tester);
      await pumpEditor(tester, e);
      final g = await tester.startGesture(
        tester.getCenter(find.byType(DevelopCanvas)),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await settle(tester);
      await expectLater(
        find.byType(PhotoEditorScreen),
        matchesGoldenFile('goldens/photo_editor_compare.png'),
      );
      await g.up();
      await tester.pump();
    });
  });
}
