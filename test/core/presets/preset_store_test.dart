import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pio_photo_layout/core/develop/profile_table.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/presets/preset.dart';
import 'package:pio_photo_layout/core/presets/preset_codec.dart';
import 'package:pio_photo_layout/core/presets/preset_import.dart';
import 'package:pio_photo_layout/core/store/preset_store.dart';
import 'package:pio_photo_layout/core/store/preset_store_io.dart';
import 'package:pio_photo_layout/core/store/preset_store_memory.dart';

Preset preset(String id, String name, DateTime created) => Preset(
  id: id,
  name: name,
  kind: PresetKind.user,
  created: created,
  patch: SettingsPatch(
    values: {Setting.exposure: 0.5, Setting.contrast: -10},
    curves: {
      CurveChannel.master: const [CurvePoint(0, 0), CurvePoint(128, 140)],
    },
    profile: ProfileRef('P1', 'Warm', 1.5),
  ),
);

Profile profile(String id) {
  final t = ProfileTable.identity(3);
  t.rgb[5] = 0.25;
  return Profile(id: id, name: 'Warm', table: t);
}

void checkRoundTrip(Profile a, Profile b) {
  expect(b.id, a.id);
  expect(b.name, a.name);
  expect(b.table.size, a.table.size);
  for (var i = 0; i < a.table.rgb.length; i++) {
    expect(b.table.rgb[i], closeTo(a.table.rgb[i], 1 / 65535));
  }
}

void storeTests(Future<PresetStore> Function() make) {
  test('presets and profiles round trip, oldest first', () async {
    final s = await make();
    final t = DateTime.utc(2026, 1, 1);
    await s.savePreset(preset('b', 'Second', t.add(const Duration(days: 1))));
    await s.savePreset(preset('a', 'First', t));
    await s.saveProfile(profile('P1'));
    final presets = await s.loadPresets();
    expect(presets.map((e) => e.name), ['First', 'Second']);
    expect(presets.first.patch.values[Setting.exposure], 0.5);
    expect(presets.first.patch.profile!.id, 'P1');
    expect(presets.first.created, t);
    final profiles = await s.loadProfiles();
    expect(profiles, hasLength(1));
    checkRoundTrip(profile('P1'), profiles.single);
  });

  test('saving again replaces, and remove deletes', () async {
    final s = await make();
    final t = DateTime.utc(2026, 1, 1);
    await s.savePreset(preset('a', 'One', t));
    await s.savePreset(preset('a', 'Renamed', t));
    expect((await s.loadPresets()).single.name, 'Renamed');
    await s.removePreset('a');
    expect(await s.loadPresets(), isEmpty);
    await s.removePreset('missing');
  });
}

void main() {
  group('memory store', () {
    storeTests(() async => MemoryPresetStore());
  });

  group('file store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('presets_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    storeTests(() async => FilePresetStore.inDirectory(dir));

    test('uses the documented paths and leaves no temp files', () async {
      final s = FilePresetStore.inDirectory(dir);
      await s.savePreset(preset('a', 'One', DateTime.utc(2026)));
      await s.saveProfile(profile('P1'));
      expect(File(p.join(dir.path, 'a.preset.json')).existsSync(), isTrue);
      expect(
        File(p.join(dir.path, 'profiles', 'P1.profile.json')).existsSync(),
        isTrue,
      );
      final all = dir.listSync(recursive: true).map((e) => e.path);
      expect(all.where((e) => e.endsWith('.tmp')), isEmpty);
    });

    test('damaged files are skipped', () async {
      final s = FilePresetStore.inDirectory(dir);
      await s.savePreset(preset('a', 'Good', DateTime.utc(2026)));
      await s.saveProfile(profile('P1'));
      File(p.join(dir.path, 'bad.preset.json')).writeAsStringSync('{nope');
      File(p.join(dir.path, 'empty.preset.json')).writeAsStringSync('{}');
      File(
        p.join(dir.path, 'profiles', 'bad.profile.json'),
      ).writeAsStringSync('{"id":"x","name":"x","size":3,"table":"AAAA"}');
      expect((await s.loadPresets()).map((e) => e.name), ['Good']);
      expect(await s.loadProfiles(), hasLength(1));
    });
  });

  test('createPresetStore gives a store', () {
    expect(createPresetStore, isA<Function>());
  });

  group('codec', () {
    test('profile round trip and table JSON shape', () {
      final j = writeProfile(profile('P1'));
      expect(j['size'], 3);
      final raw = base64Decode(j['table'] as String);
      expect(raw.length, 3 * 3 * 3 * 3 * 2);
      checkRoundTrip(profile('P1'), readProfile(j));
    });

    test('bad profile tables are refused', () {
      final j = writeProfile(profile('P1'));
      expect(() => readProfile({...j, 'size': 4}), throwsFormatException);
      expect(() => readProfile({...j, 'size': 1}), throwsFormatException);
      expect(() => readProfile({...j, 'table': 'AAAA'}), throwsFormatException);
      final big = ProfileTable.identity(65);
      expect(
        () =>
            readProfile(writeProfile(Profile(id: 'i', name: 'n', table: big))),
        throwsFormatException,
      );
    });

    test('share file round trips', () {
      final src = preset('a', 'One', DateTime.utc(2026));
      final (pr, pf) = decodePresetFile(encodePresetFile(src, profile('P1')));
      expect(pr.id, 'a');
      expect(pr.patch.toJson(), src.patch.toJson());
      checkRoundTrip(profile('P1'), pf!);
      final (_, none) = decodePresetFile(encodePresetFile(src, null));
      expect(none, isNull);
    });

    test('share file refuses anything wrong', () {
      Uint8List j(Object o) => Uint8List.fromList(utf8.encode(jsonEncode(o)));
      final good =
          jsonDecode(
                utf8.decode(
                  encodePresetFile(
                    preset('a', 'One', DateTime.utc(2026)),
                    null,
                  ),
                ),
              )
              as Map<String, dynamic>;
      for (final bad in [
        Uint8List.fromList(utf8.encode('not json')),
        j({...good, 'type': 'other'}),
        j({...good, 'version': 2}),
        j({...good, 'preset': 5}),
        j([1]),
      ]) {
        expect(
          () => decodePresetFile(bad),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              "This preset file can't be read.",
            ),
          ),
        );
      }
    });
  });

  group('import of share files', () {
    final src = preset('keep-me', 'Shared Look', DateTime.utc(2026));
    final file = encodePresetFile(src, profile('P1'));

    test('a .preset.json is imported with its own id and profile', () {
      final r = importPresetFiles([('a.preset.json', file)]);
      expect(r.line, 'Imported "Shared Look".');
      expect(r.presets.single.id, 'keep-me');
      expect(r.presets.single.kind, PresetKind.imported);
      expect(r.profiles.single.id, 'P1');
      // Importing again gives the same id, so a store replaces it.
      expect(
        importPresetFiles([('b.json', file)]).presets.single.id,
        'keep-me',
      );
    });

    test('works inside a zip; other .json files are skipped silently', () {
      final z = Archive()
        ..addFile(ArchiveFile('x/a.preset.json', file.length, file))
        ..addFile(ArchiveFile('x/other.json', 2, utf8.encode('{}')));
      final r = importPresetFiles([
        ('pack.zip', Uint8List.fromList(ZipEncoder().encode(z))),
      ]);
      expect(r.presets.single.name, 'Shared Look');
      final none = importPresetFiles([
        ('other.json', Uint8List.fromList(utf8.encode('{"a":1}'))),
      ]);
      expect(none.presets, isEmpty);
      expect(none.line, 'No Lightroom presets found in these files.');
    });
  });
}
