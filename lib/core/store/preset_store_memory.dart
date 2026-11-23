import '../presets/preset.dart';
import '../presets/preset_codec.dart';
import 'preset_store.dart';

/// Keeps presets for this visit only (tests, and platforms without storage).
class MemoryPresetStore implements PresetStore {
  final Map<String, Map<String, dynamic>> _presets = {};
  final Map<String, Map<String, dynamic>> _profiles = {};

  @override
  Future<List<Preset>> loadPresets() async {
    final out = <Preset>[];
    for (final j in _presets.values) {
      try {
        out.add(readPreset(j));
      } catch (_) {}
    }
    out.sort((a, b) => a.created.compareTo(b.created));
    return out;
  }

  @override
  Future<void> savePreset(Preset p) async => _presets[p.id] = writePreset(p);

  @override
  Future<void> removePreset(String id) async => _presets.remove(id);

  @override
  Future<List<Profile>> loadProfiles() async {
    final out = <Profile>[];
    for (final j in _profiles.values) {
      try {
        out.add(readProfile(j));
      } catch (_) {}
    }
    return out;
  }

  @override
  Future<void> saveProfile(Profile p) async =>
      _profiles[p.id] = writeProfile(p);
}

PresetStore createStore() => MemoryPresetStore();
