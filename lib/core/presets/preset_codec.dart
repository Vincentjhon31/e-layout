// JSON for presets and profiles, for the stores and for share files.

import 'dart:convert';
import 'dart:typed_data';

import '../develop/profile_table.dart';
import '../develop/settings.dart';
import 'preset.dart';

Map<String, dynamic> writePreset(Preset p) => {
  'id': p.id,
  'name': p.name,
  'kind': p.kind.name,
  'created': p.created.toUtc().toIso8601String(),
  'patch': p.patch.toJson(),
};

/// Throws if the map is not a preset.
Preset readPreset(Map<String, dynamic> json) {
  final id = json['id'];
  final name = json['name'];
  if (id is! String || id.isEmpty || name is! String) {
    throw const FormatException('Not a preset.');
  }
  final kind = PresetKind.values.firstWhere(
    (k) => k.name == json['kind'],
    orElse: () => PresetKind.user,
  );
  final created = DateTime.parse(json['created'] as String);
  final patch = SettingsPatch.fromJson(
    Map<String, dynamic>.from(json['patch'] as Map),
  );
  return Preset(id: id, name: name, kind: kind, created: created, patch: patch);
}

Map<String, dynamic> writeProfile(Profile p) {
  final t = p.table;
  final data = ByteData(t.rgb.length * 2);
  for (var i = 0; i < t.rgb.length; i++) {
    final v = (t.rgb[i] * 65535).round().clamp(0, 65535);
    data.setUint16(i * 2, v, Endian.little);
  }
  return {
    'id': p.id,
    'name': p.name,
    'size': t.size,
    'table': base64Encode(data.buffer.asUint8List()),
  };
}

/// Throws if the map is not a readable profile.
Profile readProfile(Map<String, dynamic> json) {
  final id = json['id'];
  final name = json['name'];
  final size = json['size'];
  final text = json['table'];
  if (id is! String || id.isEmpty || name is! String) {
    throw const FormatException('Not a profile.');
  }
  if (size is! int || size < 2 || size > 64 || text is! String) {
    throw const FormatException('Bad profile table.');
  }
  final bytes = base64Decode(text);
  final count = size * size * size * 3;
  if (bytes.length != count * 2) {
    throw const FormatException('Bad profile table length.');
  }
  final data = ByteData.sublistView(bytes);
  final rgb = Float32List(count);
  for (var i = 0; i < count; i++) {
    final v = data.getUint16(i * 2, Endian.little) / 65535;
    if (!(v >= 0 && v <= 1)) throw const FormatException('Bad value.');
    rgb[i] = v;
  }
  return Profile(id: id, name: name, table: ProfileTable(size, rgb));
}

const _cantRead = "This preset file can't be read.";

/// The `.preset.json` content for sharing a preset (and its profile).
Uint8List encodePresetFile(Preset p, Profile? profile) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'type': 'e-layout-preset',
      'version': 1,
      'preset': writePreset(p),
      'profile': profile == null ? null : writeProfile(profile),
    }),
  ),
);

/// Throws [FormatException] if [bytes] is not an e-Layout preset file.
(Preset, Profile?) decodePresetFile(Uint8List bytes) {
  try {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map ||
        json['type'] != 'e-layout-preset' ||
        json['version'] is! int ||
        (json['version'] as int) > 1) {
      throw const FormatException(_cantRead);
    }
    final preset = readPreset(Map<String, dynamic>.from(json['preset'] as Map));
    final pj = json['profile'];
    final profile = pj == null
        ? null
        : readProfile(Map<String, dynamic>.from(pj as Map));
    return (preset, profile);
  } catch (_) {
    throw const FormatException(_cantRead);
  }
}
