import 'dart:convert';

/// Which tool panel a setting belongs to. Curves are in [light]; the colour
/// profile and black-and-white switch are in [colour].
enum ToolGroup { light, colour, effects, detail }

/// One numeric adjustment: its group, allowed range, neutral value and the
/// `crs:` attribute name used by preset files.
enum Setting {
  exposure(ToolGroup.light, -5, 5, 0, 'Exposure2012'),
  contrast(ToolGroup.light, -100, 100, 0, 'Contrast2012'),
  highlights(ToolGroup.light, -100, 100, 0, 'Highlights2012'),
  shadows(ToolGroup.light, -100, 100, 0, 'Shadows2012'),
  whites(ToolGroup.light, -100, 100, 0, 'Whites2012'),
  blacks(ToolGroup.light, -100, 100, 0, 'Blacks2012'),
  curveHighlights(ToolGroup.light, -100, 100, 0, 'ParametricHighlights'),
  curveLights(ToolGroup.light, -100, 100, 0, 'ParametricLights'),
  curveDarks(ToolGroup.light, -100, 100, 0, 'ParametricDarks'),
  curveShadows(ToolGroup.light, -100, 100, 0, 'ParametricShadows'),
  curveShadowSplit(ToolGroup.light, 5, 95, 25, 'ParametricShadowSplit'),
  curveMidtoneSplit(ToolGroup.light, 5, 95, 50, 'ParametricMidtoneSplit'),
  curveHighlightSplit(ToolGroup.light, 5, 95, 75, 'ParametricHighlightSplit'),
  temperature(ToolGroup.colour, -100, 100, 0, 'IncrementalTemperature'),
  tint(ToolGroup.colour, -100, 100, 0, 'IncrementalTint'),
  vibrance(ToolGroup.colour, -100, 100, 0, 'Vibrance'),
  saturation(ToolGroup.colour, -100, 100, 0, 'Saturation'),
  hueRed(ToolGroup.colour, -100, 100, 0, 'HueAdjustmentRed'),
  satRed(ToolGroup.colour, -100, 100, 0, 'SaturationAdjustmentRed'),
  lumRed(ToolGroup.colour, -100, 100, 0, 'LuminanceAdjustmentRed'),
  grayRed(ToolGroup.colour, -100, 100, 0, 'GrayMixerRed'),
  hueOrange(ToolGroup.colour, -100, 100, 0, 'HueAdjustmentOrange'),
  satOrange(ToolGroup.colour, -100, 100, 0, 'SaturationAdjustmentOrange'),
  lumOrange(ToolGroup.colour, -100, 100, 0, 'LuminanceAdjustmentOrange'),
  grayOrange(ToolGroup.colour, -100, 100, 0, 'GrayMixerOrange'),
  hueYellow(ToolGroup.colour, -100, 100, 0, 'HueAdjustmentYellow'),
  satYellow(ToolGroup.colour, -100, 100, 0, 'SaturationAdjustmentYellow'),
  lumYellow(ToolGroup.colour, -100, 100, 0, 'LuminanceAdjustmentYellow'),
  grayYellow(ToolGroup.colour, -100, 100, 0, 'GrayMixerYellow'),
  hueGreen(ToolGroup.colour, -100, 100, 0, 'HueAdjustmentGreen'),
  satGreen(ToolGroup.colour, -100, 100, 0, 'SaturationAdjustmentGreen'),
  lumGreen(ToolGroup.colour, -100, 100, 0, 'LuminanceAdjustmentGreen'),
  grayGreen(ToolGroup.colour, -100, 100, 0, 'GrayMixerGreen'),
  hueAqua(ToolGroup.colour, -100, 100, 0, 'HueAdjustmentAqua'),
  satAqua(ToolGroup.colour, -100, 100, 0, 'SaturationAdjustmentAqua'),
  lumAqua(ToolGroup.colour, -100, 100, 0, 'LuminanceAdjustmentAqua'),
  grayAqua(ToolGroup.colour, -100, 100, 0, 'GrayMixerAqua'),
  hueBlue(ToolGroup.colour, -100, 100, 0, 'HueAdjustmentBlue'),
  satBlue(ToolGroup.colour, -100, 100, 0, 'SaturationAdjustmentBlue'),
  lumBlue(ToolGroup.colour, -100, 100, 0, 'LuminanceAdjustmentBlue'),
  grayBlue(ToolGroup.colour, -100, 100, 0, 'GrayMixerBlue'),
  huePurple(ToolGroup.colour, -100, 100, 0, 'HueAdjustmentPurple'),
  satPurple(ToolGroup.colour, -100, 100, 0, 'SaturationAdjustmentPurple'),
  lumPurple(ToolGroup.colour, -100, 100, 0, 'LuminanceAdjustmentPurple'),
  grayPurple(ToolGroup.colour, -100, 100, 0, 'GrayMixerPurple'),
  hueMagenta(ToolGroup.colour, -100, 100, 0, 'HueAdjustmentMagenta'),
  satMagenta(ToolGroup.colour, -100, 100, 0, 'SaturationAdjustmentMagenta'),
  lumMagenta(ToolGroup.colour, -100, 100, 0, 'LuminanceAdjustmentMagenta'),
  grayMagenta(ToolGroup.colour, -100, 100, 0, 'GrayMixerMagenta'),
  gradeShadowHue(ToolGroup.colour, 0, 360, 0, 'SplitToningShadowHue'),
  gradeShadowSat(ToolGroup.colour, 0, 100, 0, 'SplitToningShadowSaturation'),
  gradeShadowLum(ToolGroup.colour, -100, 100, 0, 'ColorGradeShadowLum'),
  gradeMidHue(ToolGroup.colour, 0, 360, 0, 'ColorGradeMidtoneHue'),
  gradeMidSat(ToolGroup.colour, 0, 100, 0, 'ColorGradeMidtoneSat'),
  gradeMidLum(ToolGroup.colour, -100, 100, 0, 'ColorGradeMidtoneLum'),
  gradeHighHue(ToolGroup.colour, 0, 360, 0, 'SplitToningHighlightHue'),
  gradeHighSat(ToolGroup.colour, 0, 100, 0, 'SplitToningHighlightSaturation'),
  gradeHighLum(ToolGroup.colour, -100, 100, 0, 'ColorGradeHighlightLum'),
  gradeGlobalHue(ToolGroup.colour, 0, 360, 0, 'ColorGradeGlobalHue'),
  gradeGlobalSat(ToolGroup.colour, 0, 100, 0, 'ColorGradeGlobalSat'),
  gradeGlobalLum(ToolGroup.colour, -100, 100, 0, 'ColorGradeGlobalLum'),
  gradeBlending(ToolGroup.colour, 0, 100, 50, 'ColorGradeBlending'),
  gradeBalance(ToolGroup.colour, -100, 100, 0, 'SplitToningBalance'),
  texture(ToolGroup.effects, -100, 100, 0, 'Texture'),
  clarity(ToolGroup.effects, -100, 100, 0, 'Clarity2012'),
  dehaze(ToolGroup.effects, -100, 100, 0, 'Dehaze'),
  vignetteAmount(ToolGroup.effects, -100, 100, 0, 'PostCropVignetteAmount'),
  vignetteMidpoint(ToolGroup.effects, 0, 100, 50, 'PostCropVignetteMidpoint'),
  vignetteRoundness(
    ToolGroup.effects,
    -100,
    100,
    0,
    'PostCropVignetteRoundness',
  ),
  vignetteFeather(ToolGroup.effects, 0, 100, 50, 'PostCropVignetteFeather'),
  vignetteHighlights(
    ToolGroup.effects,
    0,
    100,
    0,
    'PostCropVignetteHighlightContrast',
  ),
  grainAmount(ToolGroup.effects, 0, 100, 0, 'GrainAmount'),
  grainSize(ToolGroup.effects, 0, 100, 25, 'GrainSize'),
  grainRoughness(ToolGroup.effects, 0, 100, 50, 'GrainFrequency'),
  sharpenAmount(ToolGroup.detail, 0, 150, 0, 'Sharpness'),
  sharpenRadius(ToolGroup.detail, 0.5, 3, 1, 'SharpenRadius'),
  sharpenDetail(ToolGroup.detail, 0, 100, 25, 'SharpenDetail'),
  sharpenMasking(ToolGroup.detail, 0, 100, 0, 'SharpenEdgeMasking'),
  noiseLuminance(ToolGroup.detail, 0, 100, 0, 'LuminanceSmoothing'),
  noiseDetail(ToolGroup.detail, 0, 100, 50, 'LuminanceNoiseReductionDetail'),
  noiseContrast(ToolGroup.detail, 0, 100, 0, 'LuminanceNoiseReductionContrast'),
  noiseColour(ToolGroup.detail, 0, 100, 0, 'ColorNoiseReduction'),
  noiseColourDetail(ToolGroup.detail, 0, 100, 50, 'ColorNoiseReductionDetail'),
  noiseColourSmoothness(
    ToolGroup.detail,
    0,
    100,
    50,
    'ColorNoiseReductionSmoothness',
  );

  const Setting(this.group, this.min, this.max, this.neutral, this.crs);

  final ToolGroup group;
  final double min;
  final double max;
  final double neutral;
  final String crs;

  double clamp(double v) => v.clamp(min, max).toDouble();
}

enum CurveChannel {
  master('ToneCurvePV2012'),
  red('ToneCurvePV2012Red'),
  green('ToneCurvePV2012Green'),
  blue('ToneCurvePV2012Blue');

  const CurveChannel(this.crs);
  final String crs;
}

/// A point on a tone curve, both coordinates 0 to 255.
class CurvePoint {
  const CurvePoint(this.x, this.y);
  final int x, y;

  @override
  bool operator ==(Object other) =>
      other is CurvePoint && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => 'CurvePoint($x, $y)';
}

const List<CurvePoint> _defaultCurve = [CurvePoint(0, 0), CurvePoint(255, 255)];

/// A colour profile (look) applied at [amount] (0 to 2, 1 is 100 %).
class ProfileRef {
  const ProfileRef(this.id, this.name, this.amount);
  static const ProfileRef none = ProfileRef('', '', 1);

  final String id;
  final String name;
  final double amount;

  bool get isNone => id.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ProfileRef &&
      other.id == id &&
      other.name == name &&
      other.amount == amount;
  @override
  int get hashCode => Object.hash(id, name, amount);
  @override
  String toString() => 'ProfileRef($id, $name, $amount)';
}

/// A partial set of settings. Missing keys mean "leave as is".
class SettingsPatch {
  SettingsPatch({
    Map<Setting, double> values = const {},
    Map<CurveChannel, List<CurvePoint>> curves = const {},
    this.profile,
    this.grayscale,
    Map<String, String> extras = const {},
  }) : values = Map.unmodifiable(values),
       curves = Map<CurveChannel, List<CurvePoint>>.unmodifiable({
         for (final e in curves.entries)
           e.key: List<CurvePoint>.unmodifiable(e.value),
       }),
       extras = Map.unmodifiable(extras);

  final Map<Setting, double> values;
  final Map<CurveChannel, List<CurvePoint>> curves;
  final ProfileRef? profile;
  final bool? grayscale;

  /// Unparsed `crs:` values kept for later phases.
  final Map<String, String> extras;

  bool get isEmpty =>
      values.isEmpty &&
      curves.isEmpty &&
      profile == null &&
      grayscale == null &&
      extras.isEmpty;

  /// This patch with [top] applied over it: top wins per key.
  SettingsPatch over(SettingsPatch top) => SettingsPatch(
    values: {...values, ...top.values},
    curves: {...curves, ...top.curves},
    profile: top.profile ?? profile,
    grayscale: top.grayscale ?? grayscale,
    extras: {...extras, ...top.extras},
  );

  SettingsPatch only(Set<ToolGroup> g) => SettingsPatch(
    values: {
      for (final e in values.entries)
        if (g.contains(e.key.group)) e.key: e.value,
    },
    curves: g.contains(ToolGroup.light) ? curves : const {},
    profile: g.contains(ToolGroup.colour) ? profile : null,
    grayscale: g.contains(ToolGroup.colour) ? grayscale : null,
    extras: extras,
  );

  SettingsPatch without(Set<ToolGroup> g) => SettingsPatch(
    values: {
      for (final e in values.entries)
        if (!g.contains(e.key.group)) e.key: e.value,
    },
    curves: g.contains(ToolGroup.light) ? const {} : curves,
    profile: g.contains(ToolGroup.colour) ? null : profile,
    grayscale: g.contains(ToolGroup.colour) ? null : grayscale,
    extras: extras,
  );

  Map<String, dynamic> toJson() => {
    'values': {
      for (final s in Setting.values)
        if (values.containsKey(s)) s.name: values[s],
    },
    'curves': {
      for (final c in CurveChannel.values)
        if (curves.containsKey(c))
          c.name: [
            for (final p in curves[c]!) [p.x, p.y],
          ],
    },
    'profile': profile == null
        ? null
        : {'id': profile!.id, 'name': profile!.name, 'amount': profile!.amount},
    'grayscale': grayscale,
    'extras': {for (final k in extras.keys.toList()..sort()) k: extras[k]},
  };

  /// Reads a patch, clamping values to range and skipping unknown keys.
  factory SettingsPatch.fromJson(Map<String, dynamic> json) {
    final settingByName = {for (final s in Setting.values) s.name: s};
    final channelByName = {for (final c in CurveChannel.values) c.name: c};

    final values = <Setting, double>{};
    final rawValues = json['values'];
    if (rawValues is Map) {
      for (final e in rawValues.entries) {
        final s = settingByName[e.key];
        final v = e.value;
        if (s != null && v is num && v.isFinite) {
          values[s] = s.clamp(v.toDouble());
        }
      }
    }

    final curves = <CurveChannel, List<CurvePoint>>{};
    final rawCurves = json['curves'];
    if (rawCurves is Map) {
      for (final e in rawCurves.entries) {
        final c = channelByName[e.key];
        final pts = e.value;
        if (c == null || pts is! List) continue;
        final list = <CurvePoint>[];
        for (final p in pts) {
          if (p is List && p.length == 2 && p[0] is num && p[1] is num) {
            list.add(
              CurvePoint(
                (p[0] as num).round().clamp(0, 255),
                (p[1] as num).round().clamp(0, 255),
              ),
            );
          }
        }
        if (list.isNotEmpty) curves[c] = list;
      }
    }

    ProfileRef? profile;
    final rawProfile = json['profile'];
    if (rawProfile is Map) {
      final amount = rawProfile['amount'];
      profile = ProfileRef(
        '${rawProfile['id'] ?? ''}',
        '${rawProfile['name'] ?? ''}',
        amount is num && amount.isFinite
            ? amount.toDouble().clamp(0.0, 2.0)
            : 1.0,
      );
    }

    final rawGray = json['grayscale'];
    final rawExtras = json['extras'];
    return SettingsPatch(
      values: values,
      curves: curves,
      profile: profile,
      grayscale: rawGray is bool ? rawGray : null,
      extras: rawExtras is Map
          ? {for (final e in rawExtras.entries) '${e.key}': '${e.value}'}
          : const {},
    );
  }
}

/// A fully resolved set of settings: neutral, then each layer in order.
class EditSettings {
  EditSettings._(this._values, this._curves, this._profile, this._grayscale);

  factory EditSettings.resolve(List<SettingsPatch> layers) {
    final values = {for (final s in Setting.values) s: s.neutral};
    final curves = <CurveChannel, List<CurvePoint>>{};
    var profile = ProfileRef.none;
    var gray = false;
    for (final l in layers) {
      for (final e in l.values.entries) {
        values[e.key] = e.key.clamp(e.value);
      }
      curves.addAll(l.curves);
      if (l.profile != null) profile = l.profile!;
      if (l.grayscale != null) gray = l.grayscale!;
    }
    return EditSettings._(
      Map.unmodifiable(values),
      Map.unmodifiable(curves),
      profile,
      gray,
    );
  }

  final Map<Setting, double> _values;
  final Map<CurveChannel, List<CurvePoint>> _curves;
  final ProfileRef _profile;
  final bool _grayscale;

  double operator [](Setting s) => _values[s]!;

  List<CurvePoint> curve(CurveChannel c) => _curves[c] ?? _defaultCurve;

  ProfileRef get profile => _profile;
  bool get grayscale => _grayscale;

  bool get isNeutral {
    for (final s in Setting.values) {
      if (_values[s] != s.neutral) return false;
    }
    for (final c in CurveChannel.values) {
      final pts = curve(c);
      if (pts.length != 2 ||
          pts[0] != _defaultCurve[0] ||
          pts[1] != _defaultCurve[1]) {
        return false;
      }
    }
    return _profile.isNone && !_grayscale;
  }

  /// Every setting, curve, the profile and grayscale made explicit.
  SettingsPatch toPatch() => SettingsPatch(
    values: _values,
    curves: {for (final c in CurveChannel.values) c: curve(c)},
    profile: _profile,
    grayscale: _grayscale,
  );

  /// A canonical string for caches: equal settings give equal keys.
  String get key => jsonEncode(toPatch().toJson());
}
