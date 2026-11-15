import 'dart:typed_data';

import 'package:archive/archive.dart';

/// What a font file says about itself (js/fontlib.js `fontInfo`).
class FontInfo {
  const FontInfo({this.family, this.weight, this.italic, this.variable = false});

  final String? family;

  /// 100 to 900, from the OS/2 table.
  final int? weight;
  final bool? italic;
  final bool variable;
}

/// A face read from a file: family, weight and style, with the bytes a phone can load.
class FontFileFace {
  const FontFileFace(this.family, this.weight, this.style, this.variable, this.bytes, this.mime);
  final String family;
  final int weight;
  final String style;
  final bool variable;
  final Uint8List bytes;
  final String mime;
}

const String kWoff2Refusal = "WOFF2 font files can't be used on this phone. Use the TTF or OTF file instead.";

bool isWoff(Uint8List b) => b.length >= 4 && b[0] == 0x77 && b[1] == 0x4F && b[2] == 0x46 && b[3] == 0x46;
bool isWoff2(Uint8List b) => b.length >= 4 && b[0] == 0x77 && b[1] == 0x4F && b[2] == 0x46 && b[3] == 0x32;

bool _isSfnt(Uint8List b) {
  if (b.length < 4) return false;
  final sig = ByteData.sublistView(b).getUint32(0);
  return sig == 0x00010000 || sig == 0x4F54544F || sig == 0x74727565;
}

String _tag(ByteData d, int p) => String.fromCharCodes([for (var i = 0; i < 4; i++) d.getUint8(p + i)]);

/// The tables of a TTF, OTF or WOFF file, read on demand.
class _Tables {
  _Tables(this._bytes, this._entries, this._woff);
  final Uint8List _bytes;

  /// tag -> (offset, stored length, original length)
  final Map<String, (int, int, int)> _entries;
  final bool _woff;

  bool has(String tag) => _entries.containsKey(tag);
  Iterable<String> get tags => _entries.keys;

  Uint8List? read(String tag) {
    final e = _entries[tag];
    if (e == null) return null;
    final (offset, stored, original) = e;
    if (offset < 0 || offset > _bytes.length) return null;
    final end = offset + stored > _bytes.length ? _bytes.length : offset + stored;
    final raw = Uint8List.sublistView(_bytes, offset, end);
    if (_woff && stored < original) return ZLibDecoder().decodeBytes(raw);
    return raw;
  }

  static _Tables? parse(Uint8List b) {
    if (b.length < 12) return null;
    final d = ByteData.sublistView(b);
    final entries = <String, (int, int, int)>{};
    if (_isSfnt(b)) {
      final n = d.getUint16(4);
      for (var i = 0; i < n && 12 + i * 16 + 16 <= b.length; i++) {
        final p = 12 + i * 16;
        final len = d.getUint32(p + 12);
        entries[_tag(d, p)] = (d.getUint32(p + 8), len, len);
      }
      return _Tables(b, entries, false);
    }
    if (isWoff(b)) {
      final n = d.getUint16(12);
      for (var i = 0; i < n && 44 + i * 20 + 20 <= b.length; i++) {
        final p = 44 + i * 20;
        entries[_tag(d, p)] = (d.getUint32(p + 4), d.getUint32(p + 8), d.getUint32(p + 12));
      }
      return _Tables(b, entries, true);
    }
    return null;
  }
}

/// Family, weight and italic from the font's own name and OS/2 tables (TTF,
/// OTF, WOFF). Null when the bytes are not one of those; WOFF2 gives null.
FontInfo? fontInfo(Uint8List bytes) {
  final t = _Tables.parse(bytes);
  if (t == null) return null;
  String? family;
  int? weight;
  bool? italic;
  try {
    final name = t.read('name');
    if (name != null) family = familyName(ByteData.sublistView(name));
    final os2 = t.read('OS/2');
    if (os2 != null && os2.length >= 6) {
      final d = ByteData.sublistView(os2);
      var w = d.getUint16(4);
      if (w > 0 && w < 10) w *= 100;
      final rounded = (w / 100).round() * 100;
      weight = (rounded == 0 ? 400 : rounded).clamp(100, 900);
      if (os2.length >= 64) italic = (d.getUint16(62) & 1) != 0;
    }
  } catch (_) {
    // A damaged table: the caller falls back to the file name.
  }
  return FontInfo(family: family, weight: weight, italic: italic, variable: t.has('fvar'));
}

/// The family name from a `name` table, preferring the typographic family.
String? familyName(ByteData d) {
  if (d.lengthInBytes < 6) return null;
  final count = d.getUint16(2);
  final base = d.getUint16(4);
  String? best;
  var bestScore = -1;
  for (var i = 0; i < count && 6 + i * 12 + 12 <= d.lengthInBytes; i++) {
    final p = 6 + i * 12;
    final platform = d.getUint16(p);
    final encoding = d.getUint16(p + 2);
    final lang = d.getUint16(p + 4);
    final id = d.getUint16(p + 6);
    final len = d.getUint16(p + 8);
    final start = base + d.getUint16(p + 10);
    if ((id != 16 && id != 1) || start + len > d.lengthInBytes) continue;
    final codes = <int>[];
    if (platform == 3 || platform == 0) {
      for (var j = 0; j + 1 < len; j += 2) {
        codes.add(d.getUint16(start + j));
      }
    } else if (platform == 1 && encoding == 0) {
      for (var j = 0; j < len; j++) {
        codes.add(d.getUint8(start + j));
      }
    } else {
      continue;
    }
    final text = String.fromCharCodes(codes).replaceAll(RegExp(r'[\u0000-\u001f"\\]'), '').trim();
    final score = (id == 16 ? 4 : 0) + (platform == 3 ? 2 : 0) + (platform != 3 || lang == 0x409 ? 1 : 0);
    if (text.isNotEmpty && score > bestScore) {
      best = text;
      bestScore = score;
    }
  }
  if (best == null) return null;
  return best.length > 80 ? best.substring(0, 80) : best;
}

/// "Montserrat-BoldItalic.ttf" to Montserrat, 700, italic (js/fonts.js `describeFile`).
({String family, int weight, String style}) describeFile(String fileName) {
  final stem = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final lower = stem.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  const weights = [
    ('extrablack', 900), ('black', 900), ('heavy', 900), ('extrabold', 800), ('ultrabold', 800),
    ('semibold', 600), ('demibold', 600), ('bold', 700), ('medium', 500), ('extralight', 200),
    ('ultralight', 200), ('light', 300), ('thin', 100), ('hairline', 100), ('regular', 400),
    ('book', 400), ('normal', 400), //
  ];
  var weight = 400;
  for (final (word, w) in weights) {
    if (lower.contains(word)) {
      weight = w;
      break;
    }
  }
  final style = RegExp(r'italic|oblique', caseSensitive: false).hasMatch(stem) ? 'italic' : 'normal';
  var family = stem
      .replaceFirst(
        RegExp(
          r'[-_]?(extra|ultra|semi|demi)?(black|heavy|bold|medium|light|thin|hairline|regular|book|normal)?(italic|oblique)?$',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .trim();
  if (family.isEmpty) family = stem;
  return (family: family, weight: weight, style: style);
}

/// A WOFF file rebuilt as a TTF or OTF that Flutter can load (each table
/// inflated, the table directory written again). Null when [woff] is not a
/// readable WOFF.
Uint8List? woffToSfnt(Uint8List woff) {
  if (!isWoff(woff) || woff.length < 44) return null;
  try {
    final d = ByteData.sublistView(woff);
    final flavor = d.getUint32(4);
    final n = d.getUint16(12);
    final tables = <(String tag, int checksum, Uint8List data)>[];
    for (var i = 0; i < n; i++) {
      final p = 44 + i * 20;
      if (p + 20 > woff.length) return null;
      final offset = d.getUint32(p + 4);
      final stored = d.getUint32(p + 8);
      final original = d.getUint32(p + 12);
      if (offset + stored > woff.length) return null;
      final raw = Uint8List.sublistView(woff, offset, offset + stored);
      final data = stored < original ? ZLibDecoder().decodeBytes(raw) : raw;
      if (data.length != original) return null;
      tables.add((_tag(d, p), d.getUint32(p + 16), Uint8List.fromList(data)));
    }
    tables.sort((a, b) => a.$1.compareTo(b.$1));
    var entrySelector = 0;
    while ((1 << (entrySelector + 1)) <= n) {
      entrySelector++;
    }
    final searchRange = 16 * (1 << entrySelector);
    var size = 12 + 16 * n;
    final offsets = <int>[];
    for (final t in tables) {
      offsets.add(size);
      size += (t.$3.length + 3) & ~3;
    }
    final out = Uint8List(size);
    final o = ByteData.sublistView(out);
    o.setUint32(0, flavor);
    o.setUint16(4, n);
    o.setUint16(6, searchRange);
    o.setUint16(8, entrySelector);
    o.setUint16(10, n * 16 - searchRange);
    for (var i = 0; i < n; i++) {
      final p = 12 + i * 16;
      final (tag, checksum, data) = tables[i];
      for (var k = 0; k < 4; k++) {
        out[p + k] = tag.codeUnitAt(k);
      }
      o.setUint32(p + 4, checksum);
      o.setUint32(p + 8, offsets[i]);
      o.setUint32(p + 12, data.length);
      out.setRange(offsets[i], offsets[i] + data.length, data);
    }
    return out;
  } catch (_) {
    return null;
  }
}

/// A font file inside a ZIP.
class ZipFont {
  const ZipFont(this.name, this.bytes, this.variableName);
  final String name;
  final Uint8List bytes;

  /// The file name says it is a variable font (Google Fonts ZIPs hold both kinds).
  final bool variableName;
}

final RegExp _fontFile = RegExp(r'\.(ttf|otf|woff2?)$', caseSensitive: false);

/// Font files inside a ZIP (what Google Fonts, DaFont and most font sites hand out).
/// Throws a [FormatException] with the web app's wording when it cannot be read.
List<ZipFont> readFontZip(Uint8List zip) {
  if (zip.length < 22 || zip[0] != 0x50 || zip[1] != 0x4B) {
    throw const FormatException("this ZIP file can't be read");
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zip);
  } catch (_) {
    throw const FormatException("this ZIP file can't be read");
  }
  final out = <ZipFont>[];
  var total = 0;
  for (final f in archive.files) {
    if (!f.isFile || !_fontFile.hasMatch(f.name)) continue;
    if (RegExp(r'(^|/)(__MACOSX|\._)').hasMatch(f.name)) continue;
    if (f.size > 30e6 || total + f.size > 150e6) continue;
    final bytes = f.readBytes();
    if (bytes == null || bytes.isEmpty) continue;
    total += bytes.length;
    out.add(
      ZipFont(
        f.name.split('/').last,
        Uint8List.fromList(bytes),
        RegExp(r'variable|\[w(gh|ght)', caseSensitive: false).hasMatch(f.name),
      ),
    );
  }
  return out;
}

/// Reads one font file (or the fonts in a ZIP) into faces a phone can load.
/// [problems] collects what could not be used, in the web app's words.
List<FontFileFace> facesFromFile(String fileName, Uint8List bytes, List<String> problems) {
  final items = <(String, Uint8List, bool)>[];
  if (RegExp(r'\.zip$', caseSensitive: false).hasMatch(fileName)) {
    try {
      final inside = readFontZip(bytes);
      final fixed = inside.where((f) => !f.variableName).toList();
      final use = fixed.isNotEmpty ? fixed : inside;
      if (use.isEmpty) problems.add('$fileName has no font files inside');
      for (final f in use) {
        items.add((f.name, f.bytes, f.variableName));
      }
    } on FormatException catch (e) {
      problems.add('$fileName: ${e.message}');
    }
  } else if (_fontFile.hasMatch(fileName)) {
    if (bytes.length > 30e6) {
      problems.add('$fileName is too large');
    } else {
      items.add((fileName, bytes, false));
    }
  } else {
    problems.add("$fileName isn't a font file");
  }

  final out = <FontFileFace>[];
  for (final (name, data, variableName) in items) {
    if (isWoff2(data)) {
      problems.add('$name: $kWoff2Refusal');
      continue;
    }
    var usable = data;
    var mime = name.toLowerCase().endsWith('.otf') ? 'font/otf' : 'font/ttf';
    if (isWoff(data)) {
      final converted = woffToSfnt(data);
      if (converted == null) {
        problems.add("$name couldn't be read as a font");
        continue;
      }
      usable = converted;
      mime = ByteData.sublistView(converted).getUint32(0) == 0x4F54544F ? 'font/otf' : 'font/ttf';
    }
    final info = fontInfo(usable);
    if (info == null) {
      problems.add("$name couldn't be read as a font");
      continue;
    }
    final guess = describeFile(name);
    out.add(
      FontFileFace(
        info.family ?? guess.family,
        info.weight ?? guess.weight,
        (info.italic ?? guess.style == 'italic') ? 'italic' : 'normal',
        info.variable || variableName,
        usable,
        mime,
      ),
    );
  }
  return out;
}
