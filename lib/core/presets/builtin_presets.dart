import 'dart:convert';

import 'package:flutter/services.dart';

import '../develop/settings.dart';
import 'preset.dart';

/// The looks shipped with the app (assets/presets/builtin.json). Ids are
/// `builtin:<slug>`, the kind is [PresetKind.builtin] and `created` is the
/// epoch. They are never stored: they are read from the asset at start.
/// A look that cannot be read is skipped, so one bad entry keeps the rest.
Future<List<Preset>> loadBuiltinPresets() async {
  final out = <Preset>[];
  final root = jsonDecode(
    await rootBundle.loadString('assets/presets/builtin.json'),
  );
  final list = root is Map ? root['presets'] : null;
  if (list is! List) return out;
  for (final e in list) {
    try {
      final m = Map<String, dynamic>.from(e as Map);
      final id = m['id'];
      final name = m['name'];
      if (id is! String || !id.startsWith('builtin:') || name is! String) {
        continue;
      }
      // Presets never carry a profile or masks.
      final patch = SettingsPatch.fromJson(
        Map<String, dynamic>.from(m['patch'] as Map),
      );
      out.add(
        Preset(
          id: id,
          name: name,
          kind: PresetKind.builtin,
          created: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          patch: SettingsPatch(
            values: patch.values,
            curves: patch.curves,
            grayscale: patch.grayscale,
          ),
        ),
      );
    } catch (_) {
      continue;
    }
  }
  return out;
}
