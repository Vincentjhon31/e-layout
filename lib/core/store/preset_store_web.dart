import 'dart:convert';
import 'dart:js_interop';

import '../presets/preset.dart';
import '../presets/preset_codec.dart';
import 'idb_web.dart';
import 'preset_store.dart';

/// Presets in the browser's IndexedDB. Keys are `preset:<id>` and
/// `profile:<id>`; each value is the JSON text.
class IdbPresetStore implements PresetStore {
  IdbPresetStore([String name = 'e-layout-presets']) : _box = IdbBox(name);

  final IdbBox _box;

  /// The parsed values whose key starts with [prefix] (keys and values come
  /// back in the same key order).
  Future<List<Map<String, dynamic>>> _all(String prefix) async {
    final keys = await _box.keys();
    final values = await _box.values();
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < keys.length && i < values.length; i++) {
      if (!keys[i].startsWith(prefix)) continue;
      try {
        out.add(
          Map<String, dynamic>.from(
            jsonDecode((values[i] as JSString).toDart) as Map,
          ),
        );
      } catch (_) {
        // A damaged entry is skipped; the others still load.
      }
    }
    return out;
  }

  @override
  Future<List<Preset>> loadPresets() async {
    final out = <Preset>[];
    for (final j in await _all('preset:')) {
      try {
        out.add(readPreset(j));
      } catch (_) {}
    }
    out.sort((a, b) => a.created.compareTo(b.created));
    return out;
  }

  @override
  Future<void> savePreset(Preset p) =>
      _box.put('preset:${p.id}', jsonEncode(writePreset(p)).toJS);

  @override
  Future<void> removePreset(String id) => _box.delete('preset:$id');

  @override
  Future<List<Profile>> loadProfiles() async {
    final out = <Profile>[];
    for (final j in await _all('profile:')) {
      try {
        out.add(readProfile(j));
      } catch (_) {}
    }
    return out;
  }

  @override
  Future<void> saveProfile(Profile p) =>
      _box.put('profile:${p.id}', jsonEncode(writeProfile(p)).toJS);
}

PresetStore createStore() => IdbPresetStore();
