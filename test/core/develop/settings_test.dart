import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';

void main() {
  test('84 settings, every neutral inside its range, crs names unique', () {
    expect(Setting.values.length, 84);
    for (final s in Setting.values) {
      expect(s.neutral, inInclusiveRange(s.min, s.max));
    }
    expect(Setting.values.map((s) => s.crs).toSet().length, 84);
  });

  test('resolve: neutral, then layers in order, top wins', () {
    final a = SettingsPatch(
      values: {Setting.exposure: 1, Setting.contrast: 20},
    );
    final b = SettingsPatch(values: {Setting.exposure: -0.5});
    final s = EditSettings.resolve([a, b]);
    expect(s[Setting.exposure], -0.5);
    expect(s[Setting.contrast], 20);
    expect(s[Setting.gradeBlending], 50);
  });

  test('over: top wins per key, curves and profile too', () {
    final a = SettingsPatch(
      values: {Setting.exposure: 1},
      curves: {
        CurveChannel.red: [CurvePoint(0, 0), CurvePoint(255, 250)],
      },
      profile: ProfileRef('u1', 'Look', 0.5),
    );
    final b = SettingsPatch(
      values: {Setting.contrast: 5},
      profile: ProfileRef.none,
      grayscale: true,
    );
    final m = a.over(b);
    expect(m.values, {Setting.exposure: 1, Setting.contrast: 5});
    expect(m.curves.keys, [CurveChannel.red]);
    expect(m.profile, ProfileRef.none);
    expect(m.grayscale, true);
  });

  test(
    'only/without split by group; curves are light, profile and grayscale are colour',
    () {
      final p = SettingsPatch(
        values: {Setting.exposure: 1, Setting.vibrance: 10},
        curves: {
          CurveChannel.red: [CurvePoint(0, 0), CurvePoint(255, 250)],
        },
        profile: ProfileRef('u1', 'Look', 0.5),
        grayscale: true,
      );
      final light = p.only({ToolGroup.light});
      expect(light.values.keys, [Setting.exposure]);
      expect(light.curves.keys, [CurveChannel.red]);
      expect(light.profile, isNull);
      expect(p.without({ToolGroup.light}).grayscale, true);
      final rest = p.without({ToolGroup.light});
      expect(rest.values.keys, [Setting.vibrance]);
      expect(rest.curves, isEmpty);
      expect(rest.profile, ProfileRef('u1', 'Look', 0.5));
      expect(SettingsPatch().isEmpty, true);
      expect(p.isEmpty, false);
      expect(p.only({ToolGroup.detail}).isEmpty, true);
    },
  );

  test(
    'JSON round trip keeps everything, including extras and ProfileRef.none',
    () {
      final p = SettingsPatch(
        values: {Setting.exposure: 1.5, Setting.sharpenRadius: 2},
        curves: {
          CurveChannel.master: [
            CurvePoint(0, 0),
            CurvePoint(128, 140),
            CurvePoint(255, 255),
          ],
        },
        profile: ProfileRef.none,
        grayscale: false,
        extras: {'Temperature': '5500', 'Tint': '+3'},
      );
      final back = SettingsPatch.fromJson(p.toJson());
      expect(back.toJson(), p.toJson());
      expect(back.profile, ProfileRef.none);
      expect(back.extras, {'Temperature': '5500', 'Tint': '+3'});
      expect(back.curves[CurveChannel.master]![1], CurvePoint(128, 140));
      expect(p.toJson()['curves'], {
        'master': [
          [0, 0],
          [128, 140],
          [255, 255],
        ],
      });
      final q = SettingsPatch(
        profile: ProfileRef('id', 'N', 0.5),
        grayscale: true,
      );
      expect(q.toJson()['profile'], {'id': 'id', 'name': 'N', 'amount': 0.5});
      expect(SettingsPatch.fromJson(q.toJson()).toJson(), q.toJson());
      expect(SettingsPatch().toJson()['profile'], isNull);
    },
  );

  test(
    'unknown setting names in JSON are skipped, values are clamped to range',
    () {
      final p = SettingsPatch.fromJson({
        'values': {
          'exposure': 99,
          'contrast': -500,
          'nonsense': 3,
          'sharpenRadius': 0,
        },
        'curves': {
          'red': [
            [0, 0],
            [255, 255],
          ],
          'purple': [
            [0, 0],
          ],
        },
      });
      expect(p.values, {
        Setting.exposure: 5.0,
        Setting.contrast: -100.0,
        Setting.sharpenRadius: 0.5,
      });
      expect(p.curves.keys, [CurveChannel.red]);
    },
  );

  test('isNeutral and key', () {
    expect(EditSettings.resolve([]).isNeutral, true);
    expect(
      EditSettings.resolve([
        SettingsPatch(values: {Setting.exposure: 0.1}),
      ]).key,
      isNot(EditSettings.resolve([]).key),
    );
    expect(
      EditSettings.resolve([
        SettingsPatch(values: {Setting.exposure: 0.1}),
      ]).isNeutral,
      false,
    );
    expect(
      EditSettings.resolve([
        SettingsPatch(values: {Setting.exposure: 0}),
      ]).isNeutral,
      true,
    );
  });

  test('curve, profile, grayscale defaults and key sensitivity', () {
    final n = EditSettings.resolve([]);
    expect(n.curve(CurveChannel.blue), [
      CurvePoint(0, 0),
      CurvePoint(255, 255),
    ]);
    expect(n.profile, ProfileRef.none);
    expect(n.grayscale, false);
    final keys = {
      n.key,
      EditSettings.resolve([SettingsPatch(grayscale: true)]).key,
      EditSettings.resolve([
        SettingsPatch(profile: ProfileRef('a', 'A', 1)),
      ]).key,
      EditSettings.resolve([
        SettingsPatch(profile: ProfileRef('a', 'A', 0.9)),
      ]).key,
      EditSettings.resolve([
        SettingsPatch(
          curves: {
            CurveChannel.green: [CurvePoint(0, 0), CurvePoint(255, 254)],
          },
        ),
      ]).key,
    };
    expect(keys.length, 5);
    expect(EditSettings.resolve([]).key, n.key);
    expect(
      EditSettings.resolve([
        SettingsPatch(
          curves: {
            CurveChannel.green: [CurvePoint(0, 0), CurvePoint(255, 255)],
          },
        ),
      ]).isNeutral,
      true,
    );
    expect(
      EditSettings.resolve([SettingsPatch(grayscale: true)]).isNeutral,
      false,
    );
  });

  test(
    'toPatch makes everything explicit and resolves back to the same settings',
    () {
      final s = EditSettings.resolve([
        SettingsPatch(
          values: {Setting.exposure: 1},
          grayscale: true,
          extras: {'Temperature': '1'},
        ),
      ]);
      final p = s.toPatch();
      expect(p.values.length, 84);
      expect(p.curves.length, 4);
      expect(p.profile, ProfileRef.none);
      expect(p.grayscale, true);
      expect(p.extras, isEmpty);
      expect(EditSettings.resolve([p]).key, s.key);
    },
  );

  test('patch collections are unmodifiable', () {
    final p = SettingsPatch(values: {Setting.exposure: 1});
    expect(() => p.values[Setting.contrast] = 1, throwsUnsupportedError);
  });
}
