// Turns the `crs:` fields of a preset file into a [SettingsPatch], and finds
// what e-Layout cannot carry over. Both XMP and `.lrtemplate` files are read
// into [CrsFields] first, so the mapping is written once.
//
// Field names, number formats and ranges follow
// docs/superpowers/notes/lightcraft-notes.md section 11.

import '../develop/settings.dart';

/// A look reference found inside a preset (`<crs:Look>`).
class LookInfo {
  const LookInfo({
    required this.id,
    required this.name,
    required this.amount,
    required this.stubbed,
    this.tableId,
    this.tableText,
  });

  final String id;
  final String name;

  /// `crs:Amount`, 0 to 2 (0.5 is 50 %).
  final double amount;
  final bool stubbed;
  final String? tableId;
  final String? tableText;
}

/// The `crs:` values of one file: plain values by name, and lists
/// (`rdf:Seq` items, or the numbers of an `.lrtemplate` table) by name.
class CrsFields {
  final Map<String, String> scalars = {};
  final Map<String, List<String>> seqs = {};

  String? operator [](String name) => scalars[name];
}

/// One preset or profile file, read but not yet interpreted.
class ParsedFile {
  ParsedFile(this.fields, {this.id, this.name, this.look});

  final CrsFields fields;

  /// The file's own id, if it has one.
  final String? id;

  /// The file's own name, if it has one.
  final String? name;
  final LookInfo? look;

  bool get isLook => fields['PresetType'] == 'Look';
}

/// A number as Lightroom writes it: optional `+`, `-0`, or a fraction `a/b`.
double? parseCrsNumber(String? text) {
  if (text == null) return null;
  final t = text.trim();
  if (t.isEmpty) return null;
  double? v;
  final slash = t.indexOf('/');
  if (slash > 0) {
    final a = double.tryParse(t.substring(0, slash).trim());
    final b = double.tryParse(t.substring(slash + 1).trim());
    if (a != null && b != null && b != 0) v = a / b;
  } else {
    v = double.tryParse(t);
  }
  if (v == null || !v.isFinite) return null;
  return v + 0.0; // turns -0.0 into 0.0
}

/// `True`, `true` or `1`.
bool isTrue(String? text) {
  final t = text?.trim().toLowerCase();
  return t == 'true' || t == '1';
}

bool _nonZero(CrsFields f, String name) {
  final v = parseCrsNumber(f[name]);
  return v != null && v != 0;
}

List<CurvePoint>? _curve(List<String>? items) {
  if (items == null) return null;
  final byX = <int, int>{}; // last point for each x wins
  for (final item in items) {
    final parts = item.split(',');
    if (parts.length != 2) continue;
    final x = parseCrsNumber(parts[0]);
    final y = parseCrsNumber(parts[1]);
    if (x == null || y == null) continue;
    byX[x.round().clamp(0, 255)] = y.round().clamp(0, 255);
  }
  if (byX.length < 2) return null;
  return [for (final x in byX.keys.toList()..sort()) CurvePoint(x, byX[x]!)];
}

/// The settings, curves and grayscale switch in [f]. The profile is set by
/// the caller. Unknown fields are ignored; numbers are clamped to range.
SettingsPatch patchFromFields(CrsFields f) {
  final values = <Setting, double>{};
  for (final s in Setting.values) {
    final v = parseCrsNumber(f[s.crs]);
    if (v != null) values[s] = s.clamp(v) + 0.0;
  }
  final curves = <CurveChannel, List<CurvePoint>>{};
  for (final c in CurveChannel.values) {
    final pts = _curve(f.seqs[c.crs]);
    if (pts != null) curves[c] = pts;
  }
  final gray = f['ConvertToGrayscale'];
  return SettingsPatch(
    values: values,
    curves: curves,
    grayscale: gray == null ? null : isTrue(gray),
    extras: {
      for (final k in const ['Temperature', 'Tint', 'WhiteBalance'])
        if (f[k] != null) k: f[k]!,
    },
  );
}

/// `crs:ProcessVersion` as a number, or null.
double? processVersion(CrsFields f) => parseCrsNumber(f['ProcessVersion']);

/// What the preset asks for that e-Layout does not do, in the order they are
/// reported.
List<String> notCarriedOver(CrsFields f) {
  bool hasEntries(String n) => (f.seqs[n] ?? const []).isNotEmpty;
  bool anyNonZero(List<String> names) => names.any((n) => _nonZero(f, n));

  final out = <String>[];
  if (const [
    'MaskGroupBasedCorrections',
    'GradientBasedCorrections',
    'CircularGradientBasedCorrections',
    'PaintBasedCorrections',
  ].any(hasEntries)) {
    out.add('masks');
  }
  if (isTrue(f['LensProfileEnable']) ||
      isTrue(f['AutoLateralCA']) ||
      anyNonZero(const [
        'LensManualDistortionAmount',
        'VignetteAmount',
        'Defringe',
      ])) {
    out.add('lens corrections');
  }
  if (anyNonZero(const [
    'PerspectiveUpright',
    'PerspectiveVertical',
    'PerspectiveHorizontal',
    'PerspectiveRotate',
  ])) {
    out.add('perspective');
  }
  if (anyNonZero(const [
    'ShadowTint',
    'RedHue',
    'RedSaturation',
    'GreenHue',
    'GreenSaturation',
    'BlueHue',
    'BlueSaturation',
  ])) {
    out.add('calibration');
  }
  if ((f.seqs['PointColors'] ?? const []).any(_hasPointColour)) {
    out.add('point colour');
  }
  final cam = f['CameraProfile']?.trim();
  if (cam != null &&
      cam.isNotEmpty &&
      cam != 'Adobe Standard' &&
      cam != 'Adobe Color') {
    out.add('camera profile');
  }
  if (isTrue(f['HasCrop'])) out.add('crop');
  return out;
}

bool _hasPointColour(String item) {
  for (final part in item.split(',')) {
    if (part.trim().isEmpty) continue;
    final v = parseCrsNumber(part);
    if (v == null || (v + 1).abs() > 1e-6) return true;
  }
  return false;
}
