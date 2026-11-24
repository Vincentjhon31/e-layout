import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/presets/builtin_presets.dart';
import 'package:pio_photo_layout/core/presets/preset.dart';
import 'package:pio_photo_layout/core/render/sample_scene.dart';

import '../../ui/golden_helpers.dart';

const _names = [
  'Warm',
  'Cool',
  'Vivid',
  'Soft',
  'Matte',
  'Fade',
  'Film',
  'Vintage',
  'Teal & orange',
  'Golden hour',
  'Moody',
  'Bright & airy',
  'Crisp',
  'Black & white',
  'B&W contrast',
  'Sepia',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Preset> presets;
  setUpAll(() async {
    presets = await loadBuiltinPresets();
  });

  test('there are 16 looks, in order, with unique ids and names', () {
    expect([for (final p in presets) p.name], _names);
    expect({for (final p in presets) p.id}.length, 16);
    for (final p in presets) {
      expect(p.id, startsWith('builtin:'));
      expect(p.kind, PresetKind.builtin);
      expect(p.created, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    }
    expect(presets.first.id, 'builtin:warm');
    expect(presets[8].id, 'builtin:teal-orange');
  });

  test('every look changes something', () {
    for (final p in presets) {
      expect(
        EditSettings.resolve([p.patch]).isNeutral,
        isFalse,
        reason: p.name,
      );
    }
  });

  test('exactly the three black and white looks are grayscale', () {
    expect(
      [
        for (final p in presets)
          if (p.patch.grayscale == true) p.name,
      ],
      ['Black & white', 'B&W contrast', 'Sepia'],
    );
  });

  test('no look has a profile, masks or unread extras', () {
    for (final p in presets) {
      expect(p.patch.profile, isNull, reason: p.name);
      expect(p.patch.extras, isEmpty, reason: p.name);
      expect(p.patch.toJson().containsKey('masks'), isFalse, reason: p.name);
    }
  });

  test('every value and curve point is inside its range', () {
    for (final p in presets) {
      for (final e in p.patch.values.entries) {
        expect(e.value, inInclusiveRange(e.key.min, e.key.max), reason: p.name);
      }
      for (final pts in p.patch.curves.values) {
        for (final pt in pts) {
          expect(pt.x, inInclusiveRange(0, 255), reason: p.name);
          expect(pt.y, inInclusiveRange(0, 255), reason: p.name);
        }
        expect(pts.length, greaterThanOrEqualTo(2), reason: p.name);
      }
    }
  });

  testWidgets('golden: the 16 looks on the sample scene', (tester) async {
    tester.view.physicalSize = const Size(1000, 1140);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final images = <ui.Image>[];
    await tester.runAsync(() async {
      await loadAppFonts();
      final src = await sampleSceneImage(240, 240);
      final dev = CpuDeveloper();
      for (final p in presets) {
        images.add(await dev.develop(src, EditSettings.resolve([p.patch])));
      }
      src.dispose();
    });
    addTearDown(() {
      for (final i in images) {
        i.dispose();
      }
    });
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: const ValueKey('sheet'),
          child: Container(
            color: const Color(0xFFFFFFFF),
            width: 1000,
            height: 1140,
            padding: const EdgeInsets.all(8),
            child: Wrap(
              children: [
                for (var i = 0; i < 16; i++)
                  SizedBox(
                    width: 246,
                    height: 280,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 240,
                            height: 240,
                            child: RawImage(image: images[i]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            presets[i].name,
                            style: const TextStyle(
                              fontFamily: 'Barlow',
                              fontSize: 18,
                              color: Color(0xFF000000),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byKey(const ValueKey('sheet')),
      matchesGoldenFile('goldens/builtin_grid.png'),
    );
  });
}
