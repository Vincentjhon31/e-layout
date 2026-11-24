import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/masks.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';

Map<String, dynamic> _rt(Map<String, dynamic> j) =>
    jsonDecode(jsonEncode(j)) as Map<String, dynamic>;

void main() {
  test('every shape survives a JSON round trip', () {
    final mask = Mask(
      id: 'm1',
      name: 'All shapes',
      components: [
        MaskComponent(
          BrushShape([
            BrushStroke(
              [(0.1, 0.2), (0.3, 0.4), (0.5, 0.6)],
              size: 0.08,
              feather: 30,
              flow: 70,
              erase: true,
            ),
          ]),
        ),
        MaskComponent(LinearShape(0.1, 0.2, 0.3, 0.9), op: MaskOp.subtract),
        MaskComponent(
          RadialShape(
            cx: 0.4,
            cy: 0.6,
            rx: 0.3,
            ry: 0.2,
            angle: 45,
            feather: 10,
            invert: true,
          ),
          op: MaskOp.intersect,
        ),
        MaskComponent(LuminanceRangeShape(low: 0.2, high: 0.8, smooth: 30)),
      ],
      adjust: {Setting.exposure: 1.5, Setting.clarity: -20},
      visible: false,
    );
    expect(Mask.fromJson(_rt(mask.toJson())), mask);

    final others = Mask(
      id: 'm2',
      components: [
        MaskComponent(
          ColourRangeShape([(0.1, 0.2, 0.3), (0.9, 0.8, 0.7)], refine: 20),
        ),
        const MaskComponent(SubjectShape()),
        const MaskComponent(SkyShape()),
        const MaskComponent(BackgroundShape()),
      ],
    );
    expect(Mask.fromJson(_rt(others.toJson())), others);

    final lens = LensBlur(
      amount: 40,
      focus: LensFocus.mask,
      fx: 0.3,
      fy: 0.7,
      maskId: 'm1',
      transition: 20,
      boost: 10,
    );
    expect(LensBlur.fromJson(_rt(lens.toJson())), lens);
    expect(LensBlur().isOn, false);
    expect(lens.isOn, true);
  });

  test('brush points are a flat list rounded to 4 decimals', () {
    final s = BrushStroke([(0.123456, 0.654321), (1, 0)]);
    expect(s.toJson()['points'], [0.1235, 0.6543, 1.0, 0.0]);
  });

  test('limits clamp: masks, components, strokes, points, samples', () {
    final comp = MaskComponent(LinearShape(0, 0, 1, 1));
    final mask = Mask(id: 'a', components: List.filled(6, comp));
    expect(mask.components.length, 4);
    expect(
      Mask.fromJson({
        'id': 'a',
        'components': List.filled(6, comp.toJson()),
      }).components.length,
      4,
    );

    final strokes = [
      for (var i = 0; i < 70; i++) BrushStroke([(0.5, 0.5)]),
    ];
    expect(BrushShape(strokes).strokes.length, 64);
    final shapeJson = {
      'type': 'brush',
      'strokes': [for (final s in strokes) s.toJson()],
    };
    expect((MaskShape.fromJson(shapeJson) as BrushShape).strokes.length, 64);

    final pts = [for (var i = 0; i < 2500; i++) (0.5, 0.5)];
    expect(BrushStroke(pts).points.length, 2000);
    final strokeJson = {
      'points': [
        for (var i = 0; i < 2500; i++) ...[0.5, 0.5],
      ],
    };
    expect(BrushStroke.fromJson(strokeJson).points.length, 2000);

    final samples = [for (var i = 0; i < 7; i++) (0.5, 0.5, 0.5)];
    expect(ColourRangeShape(samples).samples.length, 5);
    expect(
      (MaskShape.fromJson({
                'type': 'colour',
                'samples': [
                  for (final s in samples) [s.$1, s.$2, s.$3],
                ],
              })
              as ColourRangeShape)
          .samples
          .length,
      5,
    );

    final nine = [for (var i = 0; i < 9; i++) Mask(id: 'm$i')];
    expect(SettingsPatch(masks: nine).masks!.length, 8);
    expect(
      SettingsPatch.fromJson({
        'masks': [for (final m in nine) m.toJson()],
      }).masks!.length,
      8,
    );
  });

  test('values clamp on construction and in fromJson', () {
    expect(RadialShape(cx: 5, feather: 500).cx, 1);
    expect(RadialShape(feather: 500).feather, 100);
    expect(LensBlur(amount: 300).amount, 100);
    expect(LensBlur.fromJson({'amount': -5}).amount, 0);
    expect(
      Mask(id: 'a', adjust: {Setting.exposure: 9}).adjust[Setting.exposure],
      5,
    );
  });

  test('a non-local setting in adjust is dropped', () {
    final m = Mask(
      id: 'a',
      adjust: {Setting.exposure: 1, Setting.grainAmount: 30, Setting.hueRed: 5},
    );
    expect(m.adjust.keys, [Setting.exposure]);
    final fromJson = Mask.fromJson({
      'id': 'a',
      'adjust': {'exposure': 1, 'grainAmount': 30},
    });
    expect(fromJson.adjust.keys, [Setting.exposure]);
  });

  test('over/only/without carry masks and lens blur in ToolGroup.masks', () {
    final m1 = Mask(id: 'a', adjust: {Setting.exposure: 1});
    final m2 = Mask(id: 'b', adjust: {Setting.contrast: 10});
    final base = SettingsPatch(masks: [m1], lensBlur: LensBlur(amount: 10));
    final top = SettingsPatch(masks: [m2]);
    final merged = base.over(top);
    expect(merged.masks, [m2]);
    expect(merged.lensBlur, LensBlur(amount: 10));
    expect(base.over(SettingsPatch(lensBlur: LensBlur(amount: 50))).masks, [
      m1,
    ]);

    final p = SettingsPatch(
      values: {Setting.exposure: 1},
      masks: [m1],
      lensBlur: LensBlur(amount: 10),
    );
    final only = p.only({ToolGroup.masks});
    expect(only.masks, [m1]);
    expect(only.lensBlur, LensBlur(amount: 10));
    expect(only.values, isEmpty);
    expect(p.only({ToolGroup.light}).masks, isNull);
    final without = p.without({ToolGroup.masks});
    expect(without.masks, isNull);
    expect(without.lensBlur, isNull);
    expect(without.values.keys, [Setting.exposure]);
    expect(p.without({ToolGroup.light}).masks, [m1]);

    expect(SettingsPatch(masks: const []).isEmpty, false);
    expect(SettingsPatch(lensBlur: LensBlur()).isEmpty, false);
    expect(SettingsPatch().isEmpty, true);
  });

  test('EditSettings key changes when a brush point moves', () {
    EditSettings withPoint(double x) => EditSettings.resolve([
      SettingsPatch(
        masks: [
          Mask(
            id: 'a',
            components: [
              MaskComponent(
                BrushShape([
                  BrushStroke([(x, 0.5)]),
                ]),
              ),
            ],
            adjust: {Setting.exposure: 1},
          ),
        ],
      ),
    ]);
    expect(withPoint(0.2).key, isNot(withPoint(0.3).key));
    expect(withPoint(0.2).key, withPoint(0.2).key);
    final lensA = EditSettings.resolve([
      SettingsPatch(lensBlur: LensBlur(amount: 5)),
    ]);
    expect(lensA.key, isNot(EditSettings.resolve([]).key));
  });

  test('isNeutral considers visible masks with adjustments and lens blur', () {
    expect(EditSettings.resolve([]).isNeutral, true);
    EditSettings s(Mask m) => EditSettings.resolve([
      SettingsPatch(masks: [m]),
    ]);
    expect(s(Mask(id: 'a', adjust: {Setting.exposure: 1})).isNeutral, false);
    expect(
      s(Mask(id: 'a', adjust: {Setting.exposure: 1}, visible: false)).isNeutral,
      true,
    );
    expect(s(Mask(id: 'a')).isNeutral, true);
    expect(
      EditSettings.resolve([
        SettingsPatch(lensBlur: LensBlur(amount: 1)),
      ]).isNeutral,
      false,
    );
    expect(
      EditSettings.resolve([SettingsPatch(lensBlur: LensBlur())]).isNeutral,
      true,
    );
  });

  test('old JSON with no masks or lens blur loads', () {
    final p = SettingsPatch.fromJson({
      'values': {'exposure': 1},
    });
    expect(p.masks, isNull);
    expect(p.lensBlur, isNull);
    final s = EditSettings.resolve([p]);
    expect(s.masks, isEmpty);
    expect(s.lensBlur.isOn, false);
  });

  test('a patch JSON round trip keeps masks and lens blur', () {
    final p = SettingsPatch(
      masks: [
        Mask(
          id: 'a',
          components: [MaskComponent(SkyShape())],
          adjust: {Setting.exposure: -1},
        ),
      ],
      lensBlur: LensBlur(amount: 30, focus: LensFocus.point),
    );
    final back = SettingsPatch.fromJson(_rt(p.toJson()));
    expect(back.masks, p.masks);
    expect(back.lensBlur, p.lensBlur);
  });

  test('brush size clamps to 0.5 to 50 percent of the long edge', () {
    expect(BrushStroke([], size: 0.0001).size, 0.005);
    expect(BrushStroke([], size: 3).size, 0.5);
    expect(BrushStroke.fromJson({'size': 0.0001}).size, 0.005);
    expect(BrushStroke.fromJson({'size': 3}).size, 0.5);
  });

  test('an in-memory stroke equals its reloaded copy', () {
    final s = BrushStroke([(0.123456, 0.654321)]);
    expect(s.points.first, (0.1235, 0.6543));
    expect(BrushStroke.fromJson(_rt(s.toJson())), s);
  });

  test('ids and names are capped', () {
    final long = 'x' * 100;
    final m = Mask(id: long, name: long);
    expect(m.id.length, 64);
    expect(m.name.length, 40);
    final back = Mask.fromJson({'id': long, 'name': long});
    expect(back.id.length, 64);
    expect(back.name.length, 40);
    expect(LensBlur(maskId: long).maskId!.length, 64);
    expect(LensBlur.fromJson({'maskId': long}).maskId!.length, 64);
  });
}
