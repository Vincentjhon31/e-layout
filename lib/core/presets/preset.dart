import '../develop/profile_table.dart';
import '../develop/settings.dart';

/// Where a preset came from.
enum PresetKind { user, imported }

/// A named set of adjustments that can be applied to a photo.
class Preset {
  const Preset({
    required this.id,
    required this.name,
    required this.kind,
    required this.created,
    required this.patch,
  });

  final String id;
  final String name;
  final PresetKind kind;
  final DateTime created;
  final SettingsPatch patch;
}

/// A colour profile (a look): its id (the file's `crs:UUID`), name and table.
class Profile {
  const Profile({required this.id, required this.name, required this.table});

  final String id;
  final String name;
  final ProfileTable table;
}

/// What an import found, and the sentence to show about it.
class ImportResult {
  const ImportResult({
    required this.presets,
    required this.profiles,
    required this.line,
  });

  final List<Preset> presets;
  final List<Profile> profiles;
  final String line;
}
