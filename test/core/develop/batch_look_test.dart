import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/batch_look.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';

void main() {
  test('an override survives a later change of the shared preset', () {
    var look = const BatchLook().withPresetForAll(
      SettingsPatch(values: {Setting.exposure: 0}),
      'A',
    );
    look = look.withPhotoPatch(
      7,
      SettingsPatch(values: {Setting.exposure: 0.3}),
    );
    look = look.withPresetForAll(
      SettingsPatch(values: {Setting.exposure: 0.5}),
      'B',
    );
    expect(look.settingsFor(7)[Setting.exposure], 0.3);
    expect(look.settingsFor(8)[Setting.exposure], 0.5);
    expect(look.hasOwnChanges(7), true);
    expect(look.hasOwnChanges(8), false);
  });

  test('withPresetForAll(null, null) means None and keeps overrides', () {
    var look = const BatchLook()
        .withPresetForAll(SettingsPatch(values: {Setting.exposure: 1}), 'A')
        .withPhotoPatch(1, SettingsPatch(values: {Setting.contrast: 10}));
    look = look.withPresetForAll(null, null);
    expect(look.shared.isEmpty, true);
    expect(look.sharedName, isNull);
    expect(look.settingsFor(2)[Setting.exposure], 0);
    expect(look.settingsFor(1)[Setting.contrast], 10);
  });

  test('withPhotoPatch merges over the photo overrides', () {
    final look = const BatchLook()
        .withPhotoPatch(1, SettingsPatch(values: {Setting.exposure: 1}))
        .withPhotoPatch(1, SettingsPatch(values: {Setting.contrast: 5}));
    expect(look.photos[1]!.values, {Setting.exposure: 1, Setting.contrast: 5});
  });

  test('copy to all, keeping single-photo changes', () {
    var look = const BatchLook()
        .withPhotoPatch(
          1,
          SettingsPatch(
            values: {Setting.exposure: 1, Setting.sharpenAmount: 40},
          ),
        )
        .withPhotoPatch(2, SettingsPatch(values: {Setting.exposure: -1}));
    look = look.copyToAll(1, {ToolGroup.light}, keepSingle: true);
    expect(look.settingsFor(3)[Setting.exposure], 1);
    expect(look.settingsFor(3)[Setting.sharpenAmount], 0); // detail not copied
    expect(look.settingsFor(2)[Setting.exposure], -1);
    expect(look.settingsFor(1)[Setting.sharpenAmount], 40);
    expect(look.photos[1]!.values.containsKey(Setting.exposure), false);
    expect(look.sharedName, isNull);
  });

  test(
    'copy to all with the switch off clears other photos in the copied groups only',
    () {
      var look = const BatchLook()
          .withPhotoPatch(1, SettingsPatch(values: {Setting.exposure: 1}))
          .withPhotoPatch(
            2,
            SettingsPatch(
              values: {Setting.exposure: -1, Setting.sharpenAmount: 30},
            ),
          )
          .withPhotoPatch(4, SettingsPatch(values: {Setting.contrast: 9}));
      look = look.copyToAll(1, {ToolGroup.light}, keepSingle: false);
      expect(look.settingsFor(2)[Setting.exposure], 1);
      expect(look.settingsFor(2)[Setting.sharpenAmount], 30);
      expect(look.photos[2]!.values.containsKey(Setting.exposure), false);
      expect(look.photos.containsKey(1), false); // emptied, removed
      expect(look.photos.containsKey(4), false); // emptied, removed
      expect(look.settingsFor(4)[Setting.contrast], 0 + 0);
      expect(look.settingsFor(4)[Setting.exposure], 1);
    },
  );

  test('reset removes only that photo\'s overrides', () {
    final look = const BatchLook()
        .withPresetForAll(SettingsPatch(values: {Setting.exposure: 2}), 'A')
        .withPhotoPatch(1, SettingsPatch(values: {Setting.exposure: 1}))
        .withPhotoPatch(2, SettingsPatch(values: {Setting.exposure: -1}));
    final r = look.resetPhoto(1);
    expect(r.hasOwnChanges(1), false);
    expect(r.settingsFor(1)[Setting.exposure], 2);
    expect(r.settingsFor(2)[Setting.exposure], -1);
    expect(r.sharedName, 'A');
    expect(look.withoutPhoto(2).photos.containsKey(2), false);
    expect(look.withoutPhoto(2).photos.containsKey(1), true);
  });

  test('extras never make an override', () {
    final look = const BatchLook().withPhotoPatch(
      1,
      SettingsPatch(extras: {'Foo': 'bar'}),
    );
    expect(look.photos.containsKey(1), false);
    expect(look.hasOwnChanges(1), false);
  });

  test('maps are unmodifiable', () {
    final look = const BatchLook().withPhotoPatch(
      1,
      SettingsPatch(values: {Setting.exposure: 1}),
    );
    expect(() => look.photos[2] = SettingsPatch(), throwsUnsupportedError);
  });

  test('JSON round trip', () {
    final look = const BatchLook()
        .withPresetForAll(
          SettingsPatch(
            values: {Setting.exposure: 0.5},
            curves: {
              CurveChannel.master: [
                CurvePoint(0, 0),
                CurvePoint(128, 140),
                CurvePoint(255, 255),
              ],
            },
            profile: ProfileRef('p1', 'Warm', 0.8),
            grayscale: false,
          ),
          'Warm',
        )
        .withPhotoPatch(12, SettingsPatch(values: {Setting.contrast: -20}));
    final back = BatchLook.fromJson(look.toJson());
    expect(back.sharedName, 'Warm');
    expect(back.photos.keys, [12]);
    expect(back.toJson(), look.toJson());
    expect(back.settingsFor(12).key, look.settingsFor(12).key);
    expect(look.toJson()['photos'], contains('12'));

    final none = BatchLook.fromJson(const BatchLook().toJson());
    expect(none.sharedName, isNull);
    expect(none.shared.isEmpty, true);
    expect(none.photos, isEmpty);
  });
}
