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
import 'preset_codec.dart';
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

const _mb = 1024 * 1024;
const _maxText = 8 * _mb;
const _maxDng = 200 * _mb;
const _maxDngInZip = 64 * _mb;
const _maxEntries = 500;
const _maxTotal = 256 * _mb;

/// What a read has used so far, and whether anything was too big.
class _Budget {
  bool tooBig = false;
  int total = 0;

  /// e-Layout share files found (`.json`).
  final shared = <(Preset, Profile?)>[];
}

int _cap(String lower, {bool inZip = false}) =>
    lower.endsWith('.dng') ? (inZip ? _maxDngInZip : _maxDng) : _maxText;

const _readable = ['.xmp', '.dng', '.lrtemplate', '.json', '.zip'];

class _EntryTooBig implements Exception {
  const _EntryTooBig();
}

/// The content of a zip entry, inflated by us under a hard output [limit]
/// (the declared size in the zip is not trusted). Null if the entry uses a
/// method we do not read. Throws [_EntryTooBig] when over the limit.
Uint8List? _entryBytes(ArchiveFile f, int limit) {
  final raw = f.rawContent;
  if (raw == null) return null;
  final packed = raw.getStream(decompress: false).toUint8List();
  if (!raw.isCompressed) {
    // Stored: capped by its own length.
    if (packed.length > limit) throw const _EntryTooBig();
    return packed;
  }
  if (f.compression != CompressionType.deflate) return null;
  try {
    return const ZLibDecoder().decodeBytes(
      packed,
      raw: true,
      throwOnError: true,
      maxOutputSize: limit,
    );
  } on ArchiveLimitException {
    throw const _EntryTooBig();
  }
}

void _read(
  String name,
  Uint8List bytes,
  List<_Found> out,
  int depth,
  _Budget budget,
) {
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
      var entries = 0;
      for (final f in archive.files) {
        if (!f.isFile || _isMacLeftover(f.name)) continue;
        if (++entries > _maxEntries) {
          budget.tooBig = true;
          break;
        }
        final lowName = f.name.toLowerCase();
        if (!_readable.any(lowName.endsWith)) continue; // not worth inflating
        final cap = _cap(lowName, inZip: true);
        final limit = min(cap, _maxTotal - budget.total);
        try {
          final data = _entryBytes(f, limit);
          if (data == null || data.isEmpty) continue;
          budget.total += data.length; // counted after a successful decode
          _read(f.name, data, out, depth + 1, budget);
        } on _EntryTooBig {
          budget.tooBig = true;
        } catch (_) {
          continue; // one bad file must not stop the rest
        }
      }
      return;
    }
    final isXmp = lower.endsWith('.xmp');
    final isDng = lower.endsWith('.dng');
    final isTemplate = lower.endsWith('.lrtemplate');
    final isJson = lower.endsWith('.json');
    if (!isXmp && !isDng && !isTemplate && !isJson) return;
    if (bytes.length > _cap(lower)) {
      budget.tooBig = true;
      return;
    }
    if (isJson) {
      try {
        budget.shared.add(decodePresetFile(bytes));
      } on FormatException {
        // Some other .json file: skipped silently.
      }
    } else if (isXmp) {
      final p = parseXmp(utf8.decode(bytes, allowMalformed: true));
      if (p != null && (p.isLook || isTrue(p.fields['HasSettings']))) {
        out.add(_Found(base, p));
      }
    } else if (isDng) {
      final String? packet;
      try {
        packet = extractXmpPacket(bytes, maxBytes: 2 * _mb);
      } on XmpTooBig {
        budget.tooBig = true;
        return;
      }
      final p = packet == null ? null : parseXmp(packet);
      if (p != null &&
          (isTrue(p.fields['HasSettings']) ||
              !patchFromFields(p.fields).isEmpty)) {
        out.add(_Found(base, p));
      }
    } else {
      final p = parseLrtemplate(utf8.decode(bytes, allowMalformed: true));
      if (p != null) out.add(_Found(base, p));
    }
  } catch (_) {
    return;
  }
}

String _key(String id) => id.trim().toUpperCase();

/// A profile that was found but whose table could not be read.
class _Unreadable {
  _Unreadable(this.id, this.name);
  final String id;
  final String name;
}

Profile? _profileFrom({
  required List<_Unreadable> bad,
  required String id,
  required String name,
  required String? tableId,
  required String? tableText,
}) {
  final key = id.isEmpty ? (tableId ?? '') : id;
  if (tableId == null || tableText == null) {
    bad.add(_Unreadable(key, name));
    return null;
  }
  try {
    final table = decodeAdobeTable(tableText, fingerprint: tableId);
    return Profile(id: key, name: name, table: table);
  } on FormatException {
    bad.add(_Unreadable(key, name));
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
  final budget = _Budget();
  for (final (name, bytes) in files) {
    _read(name, bytes, found, 0, budget);
  }

  // Profiles first, so presets can link to them whatever the file order.
  final profiles = <String, Profile>{};
  final unreadable = <_Unreadable>[];
  void addProfile(Profile? p) {
    if (p != null) profiles.putIfAbsent(_key(p.id), () => p);
  }

  for (final f in found) {
    final p = f.parsed;
    if (p.isLook) {
      final id = p.fields['RGBTable'];
      addProfile(
        _profileFrom(
          bad: unreadable,
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
          bad: unreadable,
          id: l.id,
          name: l.name,
          tableId: l.tableId,
          tableText: l.tableText,
        ),
      );
    }
  }

  final sharedKeys = <String>{};
  for (final (_, pf) in budget.shared) {
    if (pf != null && !profiles.containsKey(_key(pf.id))) {
      profiles[_key(pf.id)] = pf;
      sharedKeys.add(_key(pf.id));
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

  bool isBad(LookInfo l) => unreadable.any(
    (u) =>
        (l.id.isNotEmpty && _key(u.id) == _key(l.id)) ||
        (l.name.isNotEmpty &&
            u.name.trim().toLowerCase() == l.name.trim().toLowerCase()),
  );
  String nameOf(_Found f) =>
      (f.parsed.name ?? '').isEmpty ? _stem(f.fileName) : f.parsed.name!;
  bool isTemplate(_Found f) => f.fileName.toLowerCase().endsWith('.lrtemplate');
  // The same preset in .xmp/.dng and .lrtemplate: keep the .xmp/.dng one.
  final modernNames = {
    for (final f in found)
      if (!f.parsed.isLook && !isTemplate(f)) nameOf(f).trim().toLowerCase(),
  };

  final presets = <Preset>[];
  final seen = <String>{};
  final notCarried = <String>{};
  final needs = <(String, String)>[];
  var older = false;
  final now = DateTime.now();

  for (final f in found) {
    final p = f.parsed;
    if (p.isLook) continue;
    if (isTemplate(f) && modernNames.contains(nameOf(f).trim().toLowerCase())) {
      continue;
    }
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
      if (match == null && !isBad(look)) {
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

  // A share file's preset keeps its own id, so importing it again replaces it.
  for (final (sp, _) in budget.shared) {
    if (!seen.add(_key(sp.id))) continue;
    presets.add(
      Preset(
        id: sp.id,
        name: sp.name,
        kind: PresetKind.imported,
        created: now,
        patch: sp.patch,
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
  // Profiles that came inside a share file are not counted in the sentence.
  final counted = [
    for (final p in profileList)
      if (!sharedKeys.contains(_key(p.id))) p,
  ];
  final b = StringBuffer();
  if (presets.isEmpty && profileList.isEmpty) {
    if (unreadable.isEmpty) {
      b.write('No Lightroom presets found in these files.');
    } else {
      b.write(_cantRead(unreadable).trimLeft());
    }
  } else {
    final parts = <String>[];
    if (presets.length == 1) {
      parts.add('Imported "${presets.single.name}".');
    } else if (presets.length > 1) {
      parts.add('Imported ${presets.length} presets.');
    }
    if (counted.length == 1) {
      parts.add('Imported the profile "${counted.single.name}".');
    } else if (counted.length > 1) {
      parts.add('Imported ${counted.length} profiles.');
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
    b.write(_cantRead(unreadable));
    if (older) {
      b.write(
        ' Made for an older Lightroom, so it may look a little different.',
      );
    }
  }
  if (budget.tooBig) b.write(' Some files were too big to read.');
  return ImportResult(
    presets: List.unmodifiable(presets),
    profiles: List.unmodifiable(profileList),
    line: b.toString(),
  );
}

String _cantRead(List<_Unreadable> bad) {
  final seen = <String>{};
  return [
    for (final u in bad)
      if (seen.add(_key(u.id))) " The profile \"${u.name}\" can't be read.",
  ].join();
}
