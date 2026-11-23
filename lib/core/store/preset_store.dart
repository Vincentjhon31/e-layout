import '../presets/preset.dart';
import 'preset_store_memory.dart'
    if (dart.library.js_interop) 'preset_store_web.dart'
    if (dart.library.io) 'preset_store_io.dart'
    as impl;

/// Where presets and colour profiles are kept between visits.
abstract class PresetStore {
  /// Every stored preset, oldest first. Unreadable entries are skipped.
  Future<List<Preset>> loadPresets();
  Future<void> savePreset(Preset p);
  Future<void> removePreset(String id);

  /// Every stored profile. Unreadable entries are skipped.
  Future<List<Profile>> loadProfiles();
  Future<void> saveProfile(Profile p);
}

/// Files under the app support folder `presets/` on devices; IndexedDB on the web.
PresetStore createPresetStore() => impl.createStore();
