// Imports Lightroom presets (.xmp, .lrtemplate, .dng, and zips of them) and
// colour profiles (.xmp files of type "Look"). Pure Dart: the caller supplies
// the file names and bytes. A file that cannot be read is skipped, never thrown.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../develop/settings.dart';
import 'adobe_table.dart';
import 'crs_map.dart';
import 'dng_xmp.dart';
import 'lrtemplate_preset.dart';
import 'preset.dart';
import 'xmp_preset.dart';

class _Found {
  _Found(this.fileName, this.parsed);
  final String fileName;
  final ParsedFile parsed;
}

String _baseName(String path) {
  final p = path.replaceAll('\\', '/');
  return p.substring(p.lastIndexOf('/') + 1);
}

String _stem(String file) {
  final dot = file.lastIndexOf('.');
  return dot > 0 ? file.substring(0, dot) : file;
}

bool _isMacLeftover(String path) {
  final p = path.replaceAll('\\', '/');
  return p.startsWith('__MACOSX/') ||
      p.contains('/__MACOSX/') ||
      _baseName(p) == '.DS_Store' ||
      _baseName(p).startsWith('._');
}

String _randomId() {
  final r = Random.secure();
  return [
    for (var i = 0; i < 16; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

void _read(String name, Uint8List bytes, List<_Found> out, int depth) {
  if (_isMacLeftover(name)) return;
  final base = _baseName(name);
  final lower = base.toLowerCase();
  try {
    if (lower.endsWith('.zip')) {
      if (depth >= 2) return;
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (_) {
        return;
      }
      for (final f in archive.files) {
        if (!f.isFile || _isMacLeftover(f.name)) continue;
        try {
          final data = f.readBytes();
          if (data == null || data.isEmpty) continue;
          _read(f.name, Uint8List.fromList(data), out, depth + 1);
        } catch (_) {
          continue; // one bad file must not stop the rest
        }
      }
    } else if (lower.endsWith('.xmp')) {
      final p = parseXmp(utf8.decode(bytes, allowMalformed: true));
      if (p != null && (p.isLook || isTrue(p.fields['HasSettings']))) {
        out.add(_Found(base, p));
      }
    } else if (lower.endsWith('.dng')) {
      final packet = extractXmpPacket(bytes);
      final p = packet == null ? null : parseXmp(packet);
      if (p != null &&
          (isTrue(p.fields['HasSettings']) ||
              !patchFromFields(p.fields).isEmpty)) {
        out.add(_Found(base, p));
      }
    } else if (lower.endsWith('.lrtemplate')) {
      final p = parseLrtemplate(utf8.decode(bytes, allowMalformed: true));
      if (p != null) out.add(_Found(base, p));
    }
  } catch (_) {
    return;
  }
}

String _key(String id) => id.trim().toUpperCase();

Profile? _profileFrom({
  required String id,
  required String name,
  required String? tableId,
  required String? tableText,
}) {
  if (tableId == null || tableText == null) return null;
  try {
    final table = decodeAdobeTable(tableText, fingerprint: tableId);
    return Profile(id: id.isEmpty ? tableId : id, name: name, table: table);
  } on FormatException {
    return null;
  }
}

/// Reads [files] and returns the presets and profiles in them, and the
/// sentence to show. Profiles in [known] (by id) are used to link presets
/// whose profile is not in these files.
ImportResult importPresetFiles(
  List<(String name, Uint8List bytes)> files, {
  Map<String, Profile> known = const {},
}) {
  final found = <_Found>[];
  for (final (name, bytes) in files) {
    _read(name, bytes, found, 0);
  }

  // Profiles first, so presets can link to them whatever the file order.
  final profiles = <String, Profile>{};
  void addProfile(Profile? p) {
    if (p != null) profiles.putIfAbsent(_key(p.id), () => p);
  }

  for (final f in found) {
    final p = f.parsed;
    if (p.isLook) {
      final id = p.fields['RGBTable'];
      addProfile(
        _profileFrom(
          id: p.id ?? '',
          name: (p.name ?? '').isEmpty ? _stem(f.fileName) : p.name!,
          tableId: id,
          tableText: id == null ? null : p.fields['Table_$id'],
        ),
      );
    } else if (p.look != null && !p.look!.stubbed) {
      final l = p.look!;
      addProfile(
        _profileFrom(
          id: l.id,
          name: l.name,
          tableId: l.tableId,
          tableText: l.tableText,
        ),
      );
    }
  }

  final candidates = [...profiles.values, ...known.values];
  Profile? find(LookInfo l) {
    if (l.id.isNotEmpty) {
      for (final c in candidates) {
        if (_key(c.id) == _key(l.id)) return c;
      }
    }
    final n = l.name.trim().toLowerCase();
    if (n.isNotEmpty) {
      for (final c in candidates) {
        if (c.name.trim().toLowerCase() == n) return c;
      }
    }
    return null;
  }

  final presets = <Preset>[];
  final seen = <String>{};
  final notCarried = <String>{};
  final needs = <(String, String)>[];
  var older = false;
  final now = DateTime.now();

  for (final f in found) {
    final p = f.parsed;
    if (p.isLook) continue;
    final given = p.id?.trim() ?? '';
    final id = given.isEmpty ? _randomId() : given;
    if (!seen.add(_key(id))) continue; // same UUID twice: one preset

    var patch = patchFromFields(p.fields);
    final look = p.look;
    if (look != null && (look.id.isNotEmpty || look.name.isNotEmpty)) {
      final match = find(look);
      final ref = match == null
          ? ProfileRef(look.id, look.name, look.amount)
          : ProfileRef(match.id, match.name, look.amount);
      patch = SettingsPatch(
        values: patch.values,
        curves: patch.curves,
        profile: ref,
        grayscale: patch.grayscale,
        extras: patch.extras,
      );
      if (match == null) {
        needs.add((
          (p.name ?? '').isEmpty ? _stem(f.fileName) : p.name!,
          look.name.isEmpty ? look.id : look.name,
        ));
      }
    }
    notCarried.addAll(notCarriedOver(p.fields));
    final v = processVersion(p.fields);
    if (v != null && v < 10) older = true;

    presets.add(
      Preset(
        id: id,
        name: (p.name ?? '').isEmpty ? _stem(f.fileName) : p.name!,
        kind: PresetKind.imported,
        created: now,
        patch: patch,
      ),
    );
  }

  const order = [
    'masks',
    'lens corrections',
    'perspective',
    'calibration',
    'point colour',
    'camera profile',
    'crop',
  ];
  final profileList = profiles.values.toList();
  final b = StringBuffer();
  if (presets.isEmpty && profileList.isEmpty) {
    b.write('No Lightroom presets found in these files.');
  } else {
    final parts = <String>[];
    if (presets.length == 1) {
      parts.add('Imported "${presets.single.name}".');
    } else if (presets.length > 1) {
      parts.add('Imported ${presets.length} presets.');
    }
    if (profileList.length == 1) {
      parts.add('Imported the profile "${profileList.single.name}".');
    } else if (profileList.length > 1) {
      parts.add('Imported ${profileList.length} profiles.');
    }
    b.write(parts.join(' '));
    final list = [
      for (final n in order)
        if (notCarried.contains(n)) n,
    ];
    if (list.isNotEmpty) b.write(' Not carried over: ${list.join(', ')}.');
    for (final (preset, profile) in needs) {
      b.write(
        ' "$preset" needs the profile "$profile". Import that file too, and '
        'it will be picked up.',
      );
    }
    if (older) {
      b.write(
        ' Made for an older Lightroom, so it may look a little different.',
      );
    }
  }
  return ImportResult(
    presets: List.unmodifiable(presets),
    profiles: List.unmodifiable(profileList),
    line: b.toString(),
  );
}
