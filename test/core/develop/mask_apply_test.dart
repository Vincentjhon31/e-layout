import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/masks.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/develop/shader_developer.dart';

import 'develop_images.dart';

/// A hard-edged circle of radius 64 px at the centre of a 256 px photo.
Mask radial(
  Map<Setting, double> adjust, {
  bool visible = true,
  String id = 'r',
}) => Mask(
  id: id,
  components: [
    MaskComponent(RadialShape(cx: .5, cy: .5, rx: .25, ry: .25, feather: 0)),
  ],
  adjust: adjust,
  visible: visible,
);

/// Covers the whole photo.
Mask everywhere(Map<Setting, double> adjust, {String id = 'all'}) => Mask(
  id: id,
  components: [
    MaskComponent(RadialShape(cx: .5, cy: .5, rx: 1, ry: 1, feather: 0)),
  ],
  adjust: adjust,
);

EditSettings withMasks(
  List<Mask> masks, [
  Map<Setting, double> values = const {},
]) => EditSettings.resolve([SettingsPatch(values: values, masks: masks)]);

/// Develops [rgba] (256 x 256) and returns the output bytes.
Future<Uint8List> run(
  PhotoDeveloper dev,
  Uint8List rgba,
  EditSettings s, {
  int w = kSide,
  ui.Offset origin = ui.Offset.zero,
  ui.Size? fullSize,
}) async {
  final src = await image(rgba, w, rgba.length ~/ 4 ~/ w);
  final out = await dev.develop(src, s, origin: origin, fullSize: fullSize);
  expect(identical(out, src), false);
  final px = await readRgba(out);
  out.dispose();
  src.dispose();
  return px;
}

double distFromCentre(int x, int y) =>
    math.sqrt(math.pow(x + 0.5 - 128, 2) + math.pow(y + 0.5 - 128, 2));

/// Largest per-channel difference between two RGBA buffers.
int worstDiff(Uint8List a, Uint8List b) {
  var worst = 0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 == 3) continue;
    worst = math.max(worst, (a[i] - b[i]).abs());
  }
  return worst;
}

/// Mean absolute per-channel difference between two RGBA buffers.
double meanDiff(Uint8List a, Uint8List b) {
  var sum = 0, n = 0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 == 3) continue;
    sum += (a[i] - b[i]).abs();
    n++;
  }
  return sum / n;
}

void main() {
  late ShaderDeveloper dev;

  Future<void> withDev(WidgetTester t, Future<void> Function() body) =>
      t.runAsync(() async {
        dev = await ShaderDeveloper.load();
        try {
          await body();
        } finally {
          dev.dispose();
        }
      });

  testWidgets('a radial mask with exposure +1 brightens only inside', (
    t,
  ) async {
    await withDev(t, () async {
      final src = colourfulRgba();
      final out = await run(
        dev,
        src,
        withMasks([
          radial({Setting.exposure: 1}),
        ]),
      );
      var outsideWorst = 0;
      var gain = 0.0, n = 0;
      for (var y = 0; y < kSide; y++) {
        for (var x = 0; x < kSide; x++) {
          final d = distFromCentre(x, y);
          final i = (y * kSide + x) * 4;
          if (d > 66) {
            for (var k = 0; k < 3; k++) {
              outsideWorst = math.max(
                outsideWorst,
                (out[i + k] - src[i + k]).abs(),
              );
            }
          } else if (d < 60) {
            final lo = lumaAt(out, kSide, x, y), li = lumaAt(src, kSide, x, y);
            expect(lo, greaterThanOrEqualTo(li - 1), reason: 'at ($x, $y)');
            gain += lo - li;
            n++;
          }
        }
      }
      expect(outsideWorst, lessThanOrEqualTo(1));
      expect(gain / n, greaterThan(20));
    });
  });

  testWidgets('a mask with no adjust changes nothing', (t) async {
    await withDev(t, () async {
      final src = richRgba(1);
      const global = <Setting, double>{
        Setting.exposure: 0.4,
        Setting.contrast: 20,
      };
      final plain = await run(dev, src, withMasks([], global));
      final empty = await run(dev, src, withMasks([radial({})], global));
      final zero = await run(
        dev,
        src,
        withMasks([
          radial({Setting.exposure: 0, Setting.clarity: 0}),
        ], global),
      );
      expect(worstDiff(empty, plain), lessThanOrEqualTo(1));
      expect(worstDiff(zero, plain), lessThanOrEqualTo(1));
      const full = ui.Size(256, 256);
      expect(
        dev.margin(withMasks([radial({})]), 1, fullSize: full),
        dev.margin(withMasks([]), 1, fullSize: full),
      );
    });
  });

  testWidgets('a hidden mask does nothing', (t) async {
    await withDev(t, () async {
      final src = richRgba(2);
      const global = <Setting, double>{Setting.saturation: 20};
      final plain = await run(dev, src, withMasks([], global));
      final hidden = await run(
        dev,
        src,
        withMasks([
          radial({Setting.exposure: 1, Setting.clarity: 60}, visible: false),
        ], global),
      );
      expect(worstDiff(hidden, plain), lessThanOrEqualTo(1));
      const full = ui.Size(256, 256);
      expect(
        dev.margin(
          withMasks([
            radial({Setting.clarity: 60}, visible: false),
          ]),
          1,
          fullSize: full,
        ),
        0,
      );
    });
  });

  testWidgets('two masks apply in order', (t) async {
    await withDev(t, () async {
      final src = colourfulRgba();
      final a = everywhere({Setting.exposure: 2}, id: 'a');
      final b = radial({Setting.exposure: -2}, id: 'b');
      final ab = await run(dev, src, withMasks([a, b]));
      final ba = await run(dev, src, withMasks([b, a]));
      final onlyA = await run(dev, src, withMasks([a]));
      final thenB = await run(dev, onlyA, withMasks([b]));
      // [a, b] is a, then b on a's result.
      expect(worstDiff(ab, thenB), lessThanOrEqualTo(1));
      // The order matters: a's clipped highlights stay dark under b.
      expect(meanDiff(ab, ba), greaterThan(3));
    });
  });

  testWidgets('shader and CpuDeveloper agree on tone and colour deltas', (
    t,
  ) async {
    await withDev(t, () async {
      final src = colourfulRgba();
      final s = withMasks(
        [
          Mask(
            id: 'r',
            components: [
              MaskComponent(
                RadialShape(cx: .4, cy: .6, rx: .35, ry: .25, feather: 60),
              ),
            ],
            adjust: {
              Setting.exposure: 0.8,
              Setting.contrast: 30,
              Setting.shadows: 25,
              Setting.temperature: 25,
              Setting.saturation: -40,
            },
          ),
          everywhere({Setting.tint: 15, Setting.vibrance: 30}),
        ],
        {Setting.exposure: 0.3, Setting.highlights: -20},
      );
      final gpu = await run(dev, src, s);
      final cpu = await run(CpuDeveloper(), src, s);
      final mean = meanDiff(gpu, cpu);
      // ignore: avoid_print
      print(
        'mask parity: mean ${mean.toStringAsFixed(3)}, '
        'max ${worstDiff(gpu, cpu)} levels',
      );
      expect(mean, lessThanOrEqualTo(2));
      // And the masks did something.
      final plain = await run(
        CpuDeveloper(),
        src,
        withMasks([], {Setting.exposure: 0.3, Setting.highlights: -20}),
      );
      expect(meanDiff(cpu, plain), greaterThan(3));
    });
  });

  testWidgets('coverage is drawn once while only the adjust changes', (
    t,
  ) async {
    await withDev(t, () async {
      final src = await image(richRgba(3));
      Future<void> go(double ev) async {
        final out = await dev.develop(
          src,
          withMasks([
            radial({Setting.exposure: ev}),
          ]),
        );
        out.dispose();
      }

      await go(0.5);
      await go(0.6);
      await go(0.7);
      expect(dev.debugCoveragesDrawn, 1);
      dev.clearCache();
      await go(0.7);
      expect(dev.debugCoveragesDrawn, 2);
      src.dispose();
    });
  });

  testWidgets('margin adds the local clarity and texture reach', (t) async {
    await withDev(t, () async {
      const full = ui.Size(1000, 500);
      final global = withMasks([], {Setting.clarity: 20});
      final local = withMasks([
        radial({Setting.clarity: 20}),
      ]);
      final both = withMasks(
        [
          radial({Setting.clarity: 20}),
        ],
        {Setting.clarity: 20},
      );
      final g = dev.margin(global, 1, fullSize: full);
      expect(g, greaterThan(0));
      expect(dev.margin(local, 1, fullSize: full), g);
      // The local pass reads the main pass's output: the reaches add.
      expect(dev.margin(both, 1, fullSize: full), 2 * g);
      final tex = withMasks([
        radial({Setting.texture: 50}),
      ]);
      expect(dev.margin(tex, 1, fullSize: full), greaterThan(0));
      // Tone only: no reach.
      expect(
        dev.margin(
          withMasks([
            radial({Setting.exposure: 1}),
          ]),
          1,
          fullSize: full,
        ),
        0,
      );
    });
  });

  testWidgets('two tiles with a clarity mask match one whole render', (
    t,
  ) async {
    await withDev(t, () async {
      final s = withMasks(
        [
          radial({Setting.clarity: 80, Setting.exposure: 0.5}),
          everywhere({Setting.texture: 60}),
        ],
        {Setting.clarity: 40},
      );
      const full = ui.Size(256, 256);
      final m = dev.margin(s, 1, fullSize: full);
      final src = richRgba(4);
      final whole = await run(dev, src, s);

      Future<Uint8List> tile(int x0, int w) => run(
        dev,
        cropRgba(src, kSide, x0, 0, w, kSide),
        s,
        w: w,
        origin: ui.Offset(x0.toDouble(), 0),
        fullSize: full,
      );

      // Largest difference from the whole render when the photo is cut at
      // x = 128 with [mm] px of overlap.
      Future<int> seamDiff(int mm) async {
        final a = await tile(0, 128 + mm);
        final b = await tile(128 - mm, 128 + mm);
        var worst = 0;
        for (var y = 0; y < kSide; y++) {
          for (var x = 0; x < kSide; x++) {
            final w = (y * kSide + x) * 4;
            final i = x < 128
                ? (y * (128 + mm) + x) * 4
                : (y * (128 + mm) + x - (128 - mm)) * 4;
            final tl = x < 128 ? a : b;
            for (var k = 0; k < 3; k++) {
              worst = math.max(worst, (tl[i + k] - whole[w + k]).abs());
            }
          }
        }
        return worst;
      }

      final worst = await seamDiff(m);
      // Control: a 1 px overlap is not enough.
      final thin = await seamDiff(1);
      // ignore: avoid_print
      print('mask tiles: margin $m, max diff $worst levels; 1 px: $thin');
      expect(worst, lessThanOrEqualTo(2));
      expect(thin, greaterThan(worst + 3));
    });
  });

  testWidgets('margin stays within kMaxMarginPx with many clarity masks', (
    t,
  ) async {
    await withDev(t, () async {
      const full = ui.Size(8000, 6000);
      final global = withMasks([], {Setting.clarity: 100});
      final s = withMasks(
        [
          for (var i = 0; i < 8; i++) radial({Setting.clarity: 100}, id: 'm$i'),
        ],
        {Setting.clarity: 100},
      );
      final g = dev.margin(global, 1, fullSize: full);
      final m = dev.margin(s, 1, fullSize: full);
      // ignore: avoid_print
      print('8000 px, 8 clarity masks: global $g, capped total $m');
      expect(kMaxMarginPx, 960);
      expect(m, lessThanOrEqualTo(kMaxMarginPx));
      expect(m, greaterThan(g), reason: 'the masks keep some reach');
      // The global reach is never cut.
      expect(g, 3 * (0.012 * 8000).ceil() + 2);
    });
  });

  testWidgets('tiles still match a whole render when the cap narrows masks', (
    t,
  ) async {
    await withDev(t, () async {
      final s = withMasks(
        [
          radial({Setting.clarity: 80, Setting.exposure: 0.5}, id: 'a'),
          everywhere({Setting.clarity: -60}, id: 'b'),
          radial({Setting.clarity: 70, Setting.texture: 50}, id: 'c'),
        ],
        {Setting.clarity: 40},
      );
      const full = ui.Size(256, 256);
      final uncapped = dev.margin(s, 1, fullSize: full);
      dev.debugMaxMarginPx = 40;
      final m = dev.margin(s, 1, fullSize: full);
      expect(uncapped, greaterThan(40));
      expect(m, lessThanOrEqualTo(40));
      final src = richRgba(5);
      final whole = await run(dev, src, s);
      Future<Uint8List> tile(int x0, int w) => run(
        dev,
        cropRgba(src, kSide, x0, 0, w, kSide),
        s,
        w: w,
        origin: ui.Offset(x0.toDouble(), 0),
        fullSize: full,
      );
      final a = await tile(0, 128 + m);
      final b = await tile(128 - m, 128 + m);
      var worst = 0;
      for (var y = 0; y < kSide; y++) {
        for (var x = 0; x < kSide; x++) {
          final w = (y * kSide + x) * 4;
          final i = x < 128
              ? (y * (128 + m) + x) * 4
              : (y * (128 + m) + x - (128 - m)) * 4;
          final tl = x < 128 ? a : b;
          for (var k = 0; k < 3; k++) {
            worst = math.max(worst, (tl[i + k] - whole[w + k]).abs());
          }
        }
      }
      // ignore: avoid_print
      print('capped tiles: margin $m (uncapped $uncapped), max diff $worst');
      expect(worst, lessThanOrEqualTo(2));
    });
  });

  test('needsStats: global dehaze or a visible mask with dehaze', () {
    expect(needsStats(withMasks([])), isFalse);
    expect(needsStats(withMasks([], {Setting.dehaze: 20})), isTrue);
    expect(
      needsStats(
        withMasks([
          radial({Setting.dehaze: -30}),
        ]),
      ),
      isTrue,
    );
    expect(
      needsStats(
        withMasks([
          radial({Setting.dehaze: 30}, visible: false),
        ]),
      ),
      isFalse,
    );
    expect(
      needsStats(
        withMasks([
          radial({Setting.clarity: 30}),
        ]),
      ),
      isFalse,
    );
  });

  test(
    'needsAutoMaps: visible automatic masks, or lens blur on the subject',
    () {
      Mask auto(
        MaskShape shape, {
        Map<Setting, double> adjust = const {Setting.exposure: 0.5},
        bool visible = true,
        String id = 'a',
      }) => Mask(
        id: id,
        components: [MaskComponent(RadialShape()), MaskComponent(shape)],
        adjust: adjust,
        visible: visible,
      );
      EditSettings lens(LensFocus focus, {String? maskId, List<Mask>? masks}) =>
          EditSettings.resolve([
            SettingsPatch(
              masks: masks,
              lensBlur: LensBlur(amount: 50, focus: focus, maskId: maskId),
            ),
          ]);

      expect(needsAutoMaps(withMasks([])), isFalse);
      expect(
        needsAutoMaps(
          withMasks([
            radial({Setting.exposure: 1}),
          ]),
        ),
        isFalse,
      );
      for (final shape in const [
        SubjectShape(),
        SkyShape(),
        BackgroundShape(),
      ]) {
        expect(
          needsAutoMaps(withMasks([auto(shape)])),
          isTrue,
          reason: '$shape',
        );
        expect(
          needsAutoMaps(withMasks([auto(shape, visible: false)])),
          isFalse,
          reason: 'hidden $shape',
        );
        expect(
          needsAutoMaps(withMasks([auto(shape, adjust: const {})])),
          isFalse,
          reason: '$shape without an adjust',
        );
      }
      // Lens blur: off, subject, point, a mask with or without automatic parts,
      // and a missing mask (the subject).
      expect(
        needsAutoMaps(
          EditSettings.resolve([
            SettingsPatch(lensBlur: LensBlur(focus: LensFocus.subject)),
          ]),
        ),
        isFalse,
      );
      expect(needsAutoMaps(lens(LensFocus.subject)), isTrue);
      expect(needsAutoMaps(lens(LensFocus.point)), isFalse);
      final plain = radial({}, id: 'plain');
      final sky = auto(const SkyShape(), adjust: const {}, id: 'sky');
      expect(
        needsAutoMaps(
          lens(LensFocus.mask, maskId: 'plain', masks: [plain, sky]),
        ),
        isFalse,
      );
      expect(
        needsAutoMaps(lens(LensFocus.mask, maskId: 'sky', masks: [plain, sky])),
        isTrue,
        reason: 'the focus mask need not have an effect',
      );
      expect(
        needsAutoMaps(lens(LensFocus.mask, maskId: 'gone', masks: [plain])),
        isTrue,
      );
    },
  );

  testWidgets('clearCache frees the masks colour tables', (t) async {
    await withDev(t, () async {
      final src = await image(richRgba(6));
      final s = withMasks([
        radial({Setting.exposure: 0.5}),
      ]);
      Future<void> go() async => (await dev.develop(src, s)).dispose();
      await go();
      final baked = dev.debugLutsBaked;
      await go();
      expect(dev.debugLutsBaked, baked, reason: 'cached');
      dev.clearCache();
      await go();
      expect(dev.debugLutsBaked, baked + 1, reason: 'baked again');
      src.dispose();
    });
  });
}
