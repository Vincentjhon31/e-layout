import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'profile_table.dart';
import 'settings.dart';

// The global (per-pixel) colour tools in pure Dart, in the order of
// docs/superpowers/notes/lightcraft-notes.md section 5.4:
//   white balance -> exposure -> highlights/shadows -> tone map (contrast,
//   whites, blacks) -> OkLab colour block (mixer, vibrance, saturation, B&W,
//   grading) -> gamut clamp -> sRGB encode -> curves (parametric, master,
//   R/G/B) -> profile table with Amount.
// Formulas are ported from LightCraft / craft-libs (MIT OR Apache-2.0), as
// restated in those notes, but in linear sRGB (Rec.709) instead of Rec.2020.
// Effects and detail settings are the shader's job and are ignored here.

/// The linear value the contrast S-curve leaves fixed: mid grey, 0.18
/// (notes 6.2: the pivot is `m = 0.18^(1/2.2)` in the gamma 2.2 tone domain).
const double kContrastPivot = 0.18;

const double _grey = 0.18; // CL develop/src/tone.rs:11

/// sRGB decode (LC crates/color/src/transfer.rs:5-13).
double srgbToLinear(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

/// sRGB encode (inverse of [srgbToLinear]).
double linearToSrgb(double v) => v <= 0.0031308
    ? 12.92 * v
    : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;

/// HSV hue in degrees (0 to 360) of an RGB colour; 0 for greys.
double hueOf(double r, double g, double b) {
  final mx = math.max(r, math.max(g, b));
  final mn = math.min(r, math.min(g, b));
  final d = mx - mn;
  if (d <= 0) return 0;
  double h;
  if (mx == r) {
    h = ((g - b) / d) % 6;
  } else if (mx == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  h *= 60;
  return h < 0 ? h + 360 : h;
}

const double _twoPi = 2 * math.pi;

/// CL develop/src/colorops.rs:71-73.
double _wrap(double a) => ((a + math.pi) % _twoPi) - math.pi;

double _smooth(double e0, double e1, double x) {
  var t = (x - e0) / (e1 - e0);
  t = t < 0 ? 0 : (t > 1 ? 1 : t);
  return t * t * (3 - 2 * t);
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

// ---------------------------------------------------------------------------
// OkLab (CL crates/color-transform/src/oklab.rs), linear sRGB direct matrices.

double _cbrt(double x) => x <= 0 ? 0 : math.pow(x, 1 / 3).toDouble();

(double, double, double) _linearToOkLab(double r, double g, double b) {
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return (
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  );
}

/// CL develop/src/colorops.rs:56-62: HSV hue to OkLCh hue (radians).
double _oklchHueOfHsv(double deg) {
  final h = deg / 60;
  final x = 1 - (h % 2 - 1).abs();
  double r, g, b;
  if (h < 1) {
    (r, g, b) = (1.0, x, 0.0);
  } else if (h < 2) {
    (r, g, b) = (x, 1.0, 0.0);
  } else if (h < 3) {
    (r, g, b) = (0.0, 1.0, x);
  } else if (h < 4) {
    (r, g, b) = (0.0, x, 1.0);
  } else if (h < 5) {
    (r, g, b) = (x, 0.0, 1.0);
  } else {
    (r, g, b) = (1.0, 0.0, x);
  }
  final lab = _linearToOkLab(srgbToLinear(r), srgbToLinear(g), srgbToLinear(b));
  return math.atan2(lab.$3, lab.$2);
}

/// Mixer band centres as OkLCh hues, computed at first use the way the Rust
/// does at start-up (colorops.rs:65-68). Bands: red, orange, yellow, green,
/// aqua, blue, purple, magenta.
final List<double> _bandHues = [
  for (final d in const [0, 30, 60, 120, 180, 225, 270, 315])
    _oklchHueOfHsv(d.toDouble()),
];

/// Arc from band i to band i+1 (colorops.rs:75-94).
final List<double> _bandSpans = [
  for (var i = 0; i < 8; i++)
    _wrap(_bandHues[(i + 1) % 8] - _bandHues[i]) % _twoPi,
];

/// Skin hue for vibrance (colorops.rs:224): HSV 25 degrees.
final double _skinHue = _oklchHueOfHsv(25);

@visibleForTesting
List<double> debugBandHues() => List.of(_bandHues);

/// The eight band weights for a hue (radians), for tests.
@visibleForTesting
List<double> debugBandWeights(double h) {
  final w = List<double>.filled(8, 0);
  final i = _bandIndex(h);
  final s = _bandS;
  w[i] += 1 - s;
  w[(i + 1) % 8] += s;
  return w;
}

// Scratch result of _bandIndex: the blend toward the next band.
double _bandS = 0;

/// Finds the segment holding hue [h] (colorops.rs:75-94): band i gets weight
/// `1 - _bandS`, band i+1 gets `_bandS`.
int _bandIndex(double h) {
  for (var i = 0; i < 8; i++) {
    final span = _bandSpans[i];
    final d = _wrap(h - _bandHues[i]) % _twoPi;
    if (d <= span) {
      final t = span > 0 ? d / span : 0.0;
      _bandS = 0.5 - 0.5 * math.cos(math.pi * t);
      return i;
    }
  }
  _bandS = 0;
  return 0;
}

// ---------------------------------------------------------------------------
// White balance (CL local.rs:66-91, color-transform/src/cct.rs:26-94).

typedef _M3 = List<double>; // row-major 3x3

_M3 _mul3(_M3 a, _M3 b) {
  final o = List<double>.filled(9, 0);
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      o[r * 3 + c] =
          a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c];
    }
  }
  return o;
}

_M3 _inv3(_M3 m) {
  final a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5];
  final g = m[6], h = m[7], i = m[8];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  final k = 1 / det;
  return [
    (e * i - f * h) * k,
    (c * h - b * i) * k,
    (b * f - c * e) * k,
    (f * g - d * i) * k,
    (a * i - c * g) * k,
    (c * d - a * f) * k,
    (d * h - e * g) * k,
    (b * g - a * h) * k,
    (a * e - b * d) * k,
  ];
}

const _M3 _srgbToXyz = [
  0.4123907993, 0.3575843394, 0.1804807884, //
  0.2126390059, 0.7151686788, 0.0721923154,
  0.0193308187, 0.1191947798, 0.9505321522,
];

const _M3 _bradford = [
  0.8951, 0.2664, -0.1614, //
  -0.7502, 1.7135, 0.0367,
  0.0389, -0.0685, 1.0296,
];

/// Kim et al. CCT locus (cct.rs:26-60), T clamped to 1667..25000 K.
(double, double) _kimXy(double t0) {
  final t = t0.clamp(1667.0, 25000.0).toDouble();
  final t2 = t * t, t3 = t2 * t;
  final x = t <= 4000
      ? -0.2661239e9 / t3 - 0.2343589e6 / t2 + 0.8776956e3 / t + 0.179910
      : -3.0258469e9 / t3 + 2.1070379e6 / t2 + 0.2226347e3 / t + 0.240390;
  final y = t <= 2222
      ? -1.1063814 * x * x * x -
            1.34811020 * x * x +
            2.18555832 * x -
            0.20219683
      : t <= 4000
      ? -0.9549476 * x * x * x -
            1.37418593 * x * x +
            2.09137015 * x -
            0.16748867
      : 3.0817580 * x * x * x -
            5.87338670 * x * x +
            3.75112997 * x -
            0.37001483;
  return (x, y);
}

(double, double) _locusUv(double t) {
  final (x, y) = _kimXy(t);
  final d = -2 * x + 12 * y + 3;
  return (4 * x / d, 6 * y / d);
}

/// Chromaticity of the assumed illuminant for (kelvin, tint) (cct.rs:62-94).
(double, double) _tempTintToXy(double kelvin, double tint) {
  final (u, v) = _locusUv(kelvin);
  final mired = 1e6 / kelvin;
  final (u1, v1) = _locusUv(1e6 / (mired - 1));
  final (u2, v2) = _locusUv(1e6 / (mired + 1));
  var nu = -(v2 - v1), nv = u2 - u1;
  final len = math.sqrt(nu * nu + nv * nv);
  nu /= len;
  nv /= len;
  if (nv < 0) {
    nu = -nu;
    nv = -nv;
  }
  final duv = tint / 3000;
  final up = u + nu * duv, vp = v + nv * duv;
  final d = 2 * up - 8 * vp + 4;
  return (3 * up / d, 2 * vp / d);
}

List<double> _xyzOfXy(double x, double y) => [x / y, 1.0, (1 - x - y) / y];

/// Bradford adaptation src white -> dst white (CL cms/src/math.rs:117);
/// identity when a source cone response is not positive.
_M3 _bradfordAdapt(List<double> src, List<double> dst) {
  List<double> cone(List<double> w) => [
    _bradford[0] * w[0] + _bradford[1] * w[1] + _bradford[2] * w[2],
    _bradford[3] * w[0] + _bradford[4] * w[1] + _bradford[5] * w[2],
    _bradford[6] * w[0] + _bradford[7] * w[1] + _bradford[8] * w[2],
  ];
  final cs = cone(src), cd = cone(dst);
  if (cs[0] <= 0 || cs[1] <= 0 || cs[2] <= 0) {
    return const [1.0, 0, 0, 0, 1, 0, 0, 0, 1];
  }
  final scale = <double>[
    cd[0] / cs[0],
    0,
    0,
    0,
    cd[1] / cs[1],
    0,
    0,
    0,
    cd[2] / cs[2],
  ];
  return _mul3(_inv3(_bradford), _mul3(scale, _bradford));
}

/// Linear-RGB matrix mapping an assumed white to neutral.
_M3 _wbOf((double, double) xy) {
  final d65 = _xyzOfXy(0.3127, 0.3290);
  final adapt = _bradfordAdapt(_xyzOfXy(xy.$1, xy.$2), d65);
  return _mul3(_inv3(_srgbToXyz), _mul3(adapt, _srgbToXyz));
}

/// The white-balance matrix for the relative temperature/tint sliders
/// (-100..100), as-shot 6500 K / tint 0, luminance preserved.
_M3 _whiteBalanceMatrix(double temp, double tint) {
  // CL develop-model/src/crs.rs:154-158: relative slider to kelvin.
  final r = temp.clamp(-100.0, 100.0);
  final kelvin = 1e6 / (1e6 / 6500 - 0.8 * r);
  final white = _wbOf(_tempTintToXy(kelvin, tint));
  final shot = _wbOf(_tempTintToXy(6500, 0));
  final m = _mul3(white, _inv3(shot));
  final gy =
      0.2126 * (m[0] + m[1] + m[2]) +
      0.7152 * (m[3] + m[4] + m[5]) +
      0.0722 * (m[6] + m[7] + m[8]);
  return [for (final v in m) v / gy];
}

// ---------------------------------------------------------------------------
// Curves (CL develop/src/curve.rs, color-transform/src/curve.rs).

/// Parametric curve LUT, 1024 entries (curve.rs:33-64).
Float64List _parametricLut(
  List<double> amounts, // shadows, darks, lights, highlights
  double split0,
  double split1,
  double split2,
) {
  final s0 = (split0 / 100).clamp(0.0, 1.0).toDouble();
  final s1 = (split1 / 100).clamp(s0, 1.0).toDouble();
  final s2 = (split2 / 100).clamp(s1, 1.0).toDouble();
  final bounds = [0.0, s0, s1, s2, 1.0];
  final lut = Float64List(1024);
  var prev = 0.0;
  for (var i = 0; i < 1024; i++) {
    final x = i / 1023;
    var d = 0.0;
    for (var k = 0; k < 4; k++) {
      final amt = amounts[k];
      if (amt == 0) continue;
      final lo = bounds[k], hi = bounds[k + 1];
      final ctr = (lo + hi) / 2;
      final half = (hi - lo) * 0.75 + 0.05;
      final t = ((x - ctr) / half).clamp(-1.0, 1.0);
      d += (amt / 100) * 0.22 * (0.5 + 0.5 * math.cos(math.pi * t));
    }
    final y = _clamp01(x + d * 4 * x * (1 - x));
    prev = math.max(prev, y);
    lut[i] = prev;
  }
  return lut;
}

/// Monotone cubic Hermite spline, Fritsch-Carlson (curve.rs:65-135).
class _Spline {
  _Spline._(this.xs, this.ys, this.ms);

  final List<double> xs, ys, ms;

  /// Null when the points make an identity curve. Points are sorted by x,
  /// clamped to 0..255, and fewer than two distinct x values is the identity.
  static _Spline? from(List<CurvePoint> pts) {
    final sorted = [
      for (final p in pts)
        (p.x.clamp(0, 255) / 255.0, p.y.clamp(0, 255) / 255.0),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final xs = <double>[], ys = <double>[];
    for (final p in sorted) {
      if (xs.isNotEmpty && p.$1 - xs.last < 1e-9) {
        ys[ys.length - 1] = p.$2; // merge duplicates, last wins
      } else {
        xs.add(p.$1);
        ys.add(p.$2);
      }
    }
    if (xs.length < 2) return null;
    var identity = true;
    for (var i = 0; i < xs.length; i++) {
      if ((xs[i] - ys[i]).abs() > 1e-9) identity = false;
    }
    if (identity) return null;
    final n = xs.length;
    final d = [
      for (var i = 0; i < n - 1; i++) (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]),
    ];
    final m = List<double>.filled(n, 0);
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (var i = 1; i < n - 1; i++) {
      m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    }
    for (var i = 0; i < n - 1; i++) {
      if (d[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
      } else {
        final r = math.sqrt(m[i] * m[i] + m[i + 1] * m[i + 1]);
        final lim = 3 * d[i].abs();
        if (r > lim) {
          m[i] *= lim / r;
          m[i + 1] *= lim / r;
        }
      }
    }
    return _Spline._(xs, ys, m);
  }

  double eval(double x) {
    final n = xs.length;
    if (x <= xs[0]) return ys[0];
    if (x >= xs[n - 1]) return ys[n - 1];
    var i = 0;
    while (i < n - 2 && x > xs[i + 1]) {
      i++;
    }
    final h = xs[i + 1] - xs[i];
    final t = (x - xs[i]) / h;
    final t2 = t * t, t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * ys[i] +
        (t3 - 2 * t2 + t) * h * ms[i] +
        (-2 * t3 + 3 * t2) * ys[i + 1] +
        (t3 - t2) * h * ms[i + 1];
  }
}

double _lutEval(Float64List lut, double x) {
  final f = _clamp01(x) * 1023;
  var i = f.floor();
  if (i >= 1023) i = 1022;
  final t = f - i;
  return lut[i] + (lut[i + 1] - lut[i]) * t;
}

// ---------------------------------------------------------------------------

/// How hard Highlights and Shadows act, in stops at +-100. LightCraft uses 1.7
/// with a blurred base layer (notes 6.3); with the per-pixel base proposal the
/// weights are harsher, so the strength is lowered, not the curve shape.
/// Phase 1 approximation; Phase 4 revisits it.
const double _hsStrength = 1.0;

/// The global colour tools as one pure function of an sRGB pixel.
///
/// All per-settings work is done in the constructor so [apply] allocates
/// nothing but the returned record.
class ColorPipeline {
  ColorPipeline(EditSettings s, {ProfileTable? profile}) {
    // White balance and exposure as one linear matrix (notes 6.9, 6.1).
    final temp = s[Setting.temperature], tint = s[Setting.tint];
    final ev = s[Setting.exposure];
    _hasMatrix = temp != 0 || tint != 0 || ev != 0;
    if (_hasMatrix) {
      final m = (temp != 0 || tint != 0)
          ? _whiteBalanceMatrix(temp, tint)
          : const <double>[1.0, 0, 0, 0, 1, 0, 0, 0, 1];
      final gain = math.pow(2, ev).toDouble(); // LC finish.rs:250-251
      for (var i = 0; i < 9; i++) {
        _m[i] = m[i] * gain;
      }
    }

    // Highlights and shadows (notes 6.3, per-pixel proposal).
    _hl = s[Setting.highlights] / 100;
    _sh = s[Setting.shadows] / 100;
    _hasHs = _hl != 0 || _sh != 0;

    // Tone map (notes 6.2).
    _c = s[Setting.contrast] / 100;
    _w = s[Setting.whites] / 100;
    _b = s[Setting.blacks] / 100;
    _hasTone = _c != 0 || _w != 0 || _b != 0;

    // Colour block (notes 6.4 to 6.7).
    const hueS = [
      Setting.hueRed,
      Setting.hueOrange,
      Setting.hueYellow,
      Setting.hueGreen,
      Setting.hueAqua,
      Setting.hueBlue,
      Setting.huePurple,
      Setting.hueMagenta,
    ];
    const satS = [
      Setting.satRed,
      Setting.satOrange,
      Setting.satYellow,
      Setting.satGreen,
      Setting.satAqua,
      Setting.satBlue,
      Setting.satPurple,
      Setting.satMagenta,
    ];
    const lumS = [
      Setting.lumRed,
      Setting.lumOrange,
      Setting.lumYellow,
      Setting.lumGreen,
      Setting.lumAqua,
      Setting.lumBlue,
      Setting.lumPurple,
      Setting.lumMagenta,
    ];
    const grayS = [
      Setting.grayRed,
      Setting.grayOrange,
      Setting.grayYellow,
      Setting.grayGreen,
      Setting.grayAqua,
      Setting.grayBlue,
      Setting.grayPurple,
      Setting.grayMagenta,
    ];
    var mixer = false;
    for (var i = 0; i < 8; i++) {
      final h = s[hueS[i]], sa = s[satS[i]], l = s[lumS[i]];
      _hueShift[i] = h / 100 * 0.5; // colorops.rs:207-209
      _satScale[i] = sa / 100;
      _lumShift[i] = l / 100 * 0.18;
      _bwMix[i] = s[grayS[i]] / 100;
      if (h != 0 || sa != 0 || l != 0) mixer = true;
    }
    _hasMixer = mixer;
    _vib = s[Setting.vibrance] / 100;
    _sat = s[Setting.saturation] / 100;
    _bw = s.grayscale;

    // Grading wheels (notes 6.7): shadows, midtones, highlights, global.
    final hs = [
      s[Setting.gradeShadowHue],
      s[Setting.gradeMidHue],
      s[Setting.gradeHighHue],
      s[Setting.gradeGlobalHue],
    ];
    final ss = [
      s[Setting.gradeShadowSat],
      s[Setting.gradeMidSat],
      s[Setting.gradeHighSat],
      s[Setting.gradeGlobalSat],
    ];
    final ls = [
      s[Setting.gradeShadowLum],
      s[Setting.gradeMidLum],
      s[Setting.gradeHighLum],
      s[Setting.gradeGlobalLum],
    ];
    var grade = false;
    for (var i = 0; i < 4; i++) {
      final hOk = _oklchHueOfHsv(hs[i]);
      final sc = ss[i] / 100 * 0.09;
      _wheelA[i] = sc * math.cos(hOk);
      _wheelB[i] = sc * math.sin(hOk);
      _wheelL[i] = ls[i] / 100 * 0.12;
      if (ss[i] != 0 || ls[i] != 0) grade = true;
    }
    _hasGrade = grade;
    _balanceM = 0.5 - s[Setting.gradeBalance] / 100 * 0.25;
    _blendW = 0.15 + s[Setting.gradeBlending] / 100 * 0.5;
    _hasBlock = _hasMixer || _vib != 0 || _sat != 0 || _bw || _hasGrade;

    _hasLinear = _hasMatrix || _hasHs || _hasTone || _hasBlock;

    // Curves (notes 7.1 to 7.3), built as three 1024-entry LUTs.
    final amounts = [
      s[Setting.curveShadows],
      s[Setting.curveDarks],
      s[Setting.curveLights],
      s[Setting.curveHighlights],
    ];
    final parametric = amounts.any((a) => a != 0);
    final master = _Spline.from(s.curve(CurveChannel.master));
    final chans = [
      _Spline.from(s.curve(CurveChannel.red)),
      _Spline.from(s.curve(CurveChannel.green)),
      _Spline.from(s.curve(CurveChannel.blue)),
    ];
    _hasCurves = parametric || master != null || chans.any((c) => c != null);
    if (_hasCurves) {
      final base = _parametricLut(
        amounts,
        s[Setting.curveShadowSplit],
        s[Setting.curveMidtoneSplit],
        s[Setting.curveHighlightSplit],
      );
      for (var c = 0; c < 3; c++) {
        final lut = Float64List(1024);
        for (var i = 0; i < 1024; i++) {
          var y = base[i];
          if (master != null) y = master.eval(y);
          final ch = chans[c];
          if (ch != null) y = ch.eval(y);
          lut[i] = _clamp01(y);
        }
        _lut[c] = lut;
      }
    }

    // Profile (notes 9).
    _table = profile;
    _amount = s.profile.amount;
    _hasProfile = profile != null && _amount != 0;
  }

  final Float64List _m = Float64List(9);
  late final bool _hasMatrix;
  late final double _hl, _sh, _c, _w, _b;
  late final bool _hasHs, _hasTone;
  final Float64List _hueShift = Float64List(8);
  final Float64List _satScale = Float64List(8);
  final Float64List _lumShift = Float64List(8);
  final Float64List _bwMix = Float64List(8);
  late final bool _hasMixer, _bw, _hasGrade, _hasBlock, _hasLinear;
  late final double _vib, _sat;
  final Float64List _wheelA = Float64List(4);
  final Float64List _wheelB = Float64List(4);
  final Float64List _wheelL = Float64List(4);
  late final double _balanceM, _blendW;
  late final bool _hasCurves;
  final List<Float64List> _lut = List.filled(3, Float64List(0));
  late final ProfileTable? _table;
  late final double _amount;
  late final bool _hasProfile;

  // Scratch for the linear-light stages (single isolate, no re-entrancy).
  double _r = 0, _g = 0, _bb = 0;

  /// True when [apply] returns its input (nothing in the settings, curves or
  /// profile acts; effects and detail settings do not count).
  bool get isIdentity => !_hasLinear && !_hasCurves && !_hasProfile;

  /// sRGB-encoded 0..1 in and out, clamped.
  (double, double, double) apply(double r, double g, double b) {
    r = _clamp01(r);
    g = _clamp01(g);
    b = _clamp01(b);

    if (_hasLinear) {
      _r = srgbToLinear(r);
      _g = srgbToLinear(g);
      _bb = srgbToLinear(b);
      if (_hasMatrix) {
        final m = _m;
        final lr = _r, lg = _g, lb = _bb;
        _r = math.max(m[0] * lr + m[1] * lg + m[2] * lb, 0);
        _g = math.max(m[3] * lr + m[4] * lg + m[5] * lb, 0);
        _bb = math.max(m[6] * lr + m[7] * lg + m[8] * lb, 0);
      }
      if (_hasHs) _highlightsShadows();
      if (_hasTone) _toneMap();
      if (_hasBlock) _colourBlock();
      // Gamut map: plain clamp, then encode.
      r = linearToSrgb(_clamp01(_r));
      g = linearToSrgb(_clamp01(_g));
      b = linearToSrgb(_clamp01(_bb));
    }

    if (_hasCurves) {
      r = _lutEval(_lut[0], r);
      g = _lutEval(_lut[1], g);
      b = _lutEval(_lut[2], b);
    }

    if (_hasProfile) {
      // LC finish.rs:613-625: out = e + (table(e) - e) * amount.
      final m = _table!.sample(r, g, b);
      final k = _amount;
      r = _clamp01(r + (m.$1 - r) * k);
      g = _clamp01(g + (m.$2 - g) * k);
      b = _clamp01(b + (m.$3 - b) * k);
    }
    return (r, g, b);
  }

  /// Notes 6.3 proposal: base is the pixel's own log-luminance.
  void _highlightsShadows() {
    final y = 0.2126 * _r + 0.7152 * _g + 0.0722 * _bb;
    final base = math.log(math.max(y, 1e-7) / _grey) / math.ln2;
    final sw = 1 - _smooth(-4.8, 0.3, base); // LC finish.rs:729-737
    final hw = _smooth(-1.0, 2.8, base);
    final delta =
        _sh * _hsStrength * sw * math.sqrt(sw) + _hl * _hsStrength * hw;
    if (delta == 0) return;
    final k = math.pow(2, delta).toDouble();
    _r *= k;
    _g *= k;
    _bb *= k;
  }

  /// Notes 6.2: tone(y) in the gamma 2.2 domain; CL develop/src/tone.rs:284-330.
  double _tone(double y) {
    const m = 0.4586564; // 0.18^(1/2.2)
    var p = math.pow(y, 1 / 2.2).toDouble();
    if (p <= 1) {
      p += _c * 0.35 * (p - m) * (1 - (2 * p - 1) * (2 * p - 1));
      final up = _smooth(0.45, 1.0, p);
      p += _w * 0.12 * up * (1 - 0.5 * p);
      final lo = 1 - _smooth(0.0, 0.45, p);
      p += _b * 0.07 * lo * math.min(2 * p, 1);
    } else {
      p += _w * 0.12 * 0.5;
    }
    var o = math.pow(math.max(p, 0), 2.2).toDouble();
    if (o > 0.95) {
      final d = math.min(o - 0.95, 0.1);
      o = 0.95 + d - d * d / 0.2;
    }
    return _clamp01(o);
  }

  /// LC finish.rs:477-489: replace luminance, keep colour ratios.
  void _toneMap() {
    final yl = 0.2126 * _r + 0.7152 * _g + 0.0722 * _bb;
    if (yl <= 1e-9) {
      _r = _g = _bb = 0;
      return;
    }
    final o = _tone(yl);
    final k = o / yl;
    var dr = _r * k, dg = _g * k, db = _bb * k;
    final mx = math.max(dr, math.max(dg, db));
    if (mx > 1) {
      final t = _clamp01((mx - 1) / math.max(mx - o, 1e-6));
      dr += (o - dr) * t;
      dg += (o - dg) * t;
      db += (o - db) * t;
    }
    _r = dr;
    _g = dg;
    _bb = db;
  }

  /// Notes 6.4 to 6.7: mixer, vibrance, saturation, B&W, grading in OkLCh.
  void _colourBlock() {
    final lab = _linearToOkLab(_r, _g, _bb);
    var l = lab.$1;
    final a0 = lab.$2, b0 = lab.$3;
    var c = math.sqrt(a0 * a0 + b0 * b0);
    var h = math.atan2(b0, a0);

    if (_hasMixer) {
      // colorops.rs:261-273
      final i = _bandIndex(h), j = (i + 1) % 8, s = _bandS, w0 = 1 - s;
      final dh = w0 * _hueShift[i] + s * _hueShift[j];
      final ds = w0 * _satScale[i] + s * _satScale[j];
      final dl = w0 * _lumShift[i] + s * _lumShift[j];
      final cw = math.min(c / 0.12, 1.0);
      h += dh * cw;
      c *= math.max(1 + ds, 0);
      l += dl * cw * math.sqrt(math.max(l, 0.05));
    }
    if (_vib != 0) {
      // colorops.rs:245-252
      final low = 1 - _clamp01(c / 0.22);
      var skin = 1.0;
      if (_vib > 0) {
        final z = _wrap(h - _skinHue) / 0.35;
        skin = 1 - 0.6 * math.exp(-z * z);
      }
      c *= math.max(1 + _vib * low * low * skin * 1.2, 0);
    }
    if (_sat != 0) c *= math.max(1 + _sat, 0); // colorops.rs:277-284
    if (_bw) {
      // colorops.rs:286-291
      final i = _bandIndex(h), j = (i + 1) % 8, s = _bandS;
      final mix = (1 - s) * _bwMix[i] + s * _bwMix[j];
      l = math.max(l + mix * math.min(c / 0.2, 1.0) * 0.25, 0);
      c = 0;
    }

    var a = c * math.cos(h), b = c * math.sin(h);
    if (_hasGrade) {
      // colorops.rs:296-311
      final m = _balanceM, width = _blendW;
      final ws = 1 - _smooth(m - width, m + width * 0.25, l);
      final wh = _smooth(m - width * 0.25, m + width, l);
      final wm = math.max(1 - ws - wh, 0.0);
      a += _wheelA[0] * ws + _wheelA[1] * wm + _wheelA[2] * wh + _wheelA[3];
      b += _wheelB[0] * ws + _wheelB[1] * wm + _wheelB[2] * wh + _wheelB[3];
      l += _wheelL[0] * ws + _wheelL[1] * wm + _wheelL[2] * wh + _wheelL[3];
    }

    final lp = l + 0.3963377774 * a + 0.2158037573 * b;
    final mp = l - 0.1055613458 * a - 0.0638541728 * b;
    final sp = l - 0.0894841775 * a - 1.2914855480 * b;
    final lc = lp * lp * lp, mc = mp * mp * mp, sc = sp * sp * sp;
    _r = 4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc;
    _g = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc;
    _bb = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc;
  }
}
