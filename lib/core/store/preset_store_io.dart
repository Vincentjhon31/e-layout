import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../presets/preset.dart';
import '../presets/preset_codec.dart';
import 'preset_store.dart';

/// `<id>.preset.json` files, and `profiles/<id>.profile.json` beside them.
class FilePresetStore implements PresetStore {
  FilePresetStore(this._dir);

  /// A store in a fixed folder (tests).
  FilePresetStore.inDirectory(Directory dir) : this(() async => dir);

  final Future<Directory> Function() _dir;

  static String fileSafe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<Directory> _make(Directory d) async {
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Directory> _presets() async => _make(await _dir());
  Future<Directory> _profiles() async =>
      _make(Directory(p.join((await _dir()).path, 'profiles')));

  Future<void> _write(File target, Map<String, dynamic> json) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(target.path);
  }

  @override
  Future<List<Preset>> loadPresets() async {
    final d = await _presets();
    final out = <Preset>[];
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.preset.json')) continue;
      try {
        out.add(
          readPreset(
            Map<String, dynamic>.from(
              jsonDecode(await e.readAsString()) as Map,
            ),
          ),
        );
      } catch (_) {
        // A damaged file is skipped; the others still load.
      }
    }
    out.sort((a, b) => a.created.compareTo(b.created));
    return out;
  }

  @override
  Future<void> savePreset(Preset preset) async {
    final d = await _presets();
    await _write(
      File(p.join(d.path, '${fileSafe(preset.id)}.preset.json')),
      writePreset(preset),
    );
  }

  @override
  Future<void> removePreset(String id) async {
    final d = await _presets();
    final f = File(p.join(d.path, '${fileSafe(id)}.preset.json'));
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<Profile>> loadProfiles() async {
    final d = await _profiles();
    final out = <Profile>[];
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.profile.json')) continue;
      try {
        out.add(
          readProfile(
            Map<String, dynamic>.from(
              jsonDecode(await e.readAsString()) as Map,
            ),
          ),
        );
      } catch (_) {
        // A damaged file is skipped; the others still load.
      }
    }
    return out;
  }

  @override
  Future<void> saveProfile(Profile profile) async {
    final d = await _profiles();
    await _write(
      File(p.join(d.path, '${fileSafe(profile.id)}.profile.json')),
      writeProfile(profile),
    );
  }
}

PresetStore createStore() => FilePresetStore(() async {
  final base = await getApplicationSupportDirectory();
  return Directory(p.join(base.path, 'presets'));
});
