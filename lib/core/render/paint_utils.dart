import 'dart:math' as math;
import 'dart:ui' as ui;

import '../model/layout_doc.dart';

/// `#RRGGBB` plus alpha to a [ui.Color]. A bad string gives black, like the JS.
ui.Color rgba(String hex, [double alpha = 1]) {
  final n = (hex.length > 1 ? int.tryParse(hex.substring(1), radix: 16) : null) ?? 0;
  return ui.Color.fromRGBO((n >> 16) & 255, (n >> 8) & 255, n & 255, alpha.clamp(0.0, 1.0));
}

/// Gradient shader for linear and radial fills, in the element's own space.
/// Null for `none` and `solid`.
ui.Shader? fillShader(Fill fill, double w, double h) {
  if (fill.type != FillType.linear && fill.type != FillType.radial) return null;
  final stops = [...fill.stops]..sort((a, b) => a.at.compareTo(b.at));
  final colors = [for (final s in stops) rgba(s.color, s.alpha)];
  final pos = [for (final s in stops) s.at.clamp(0.0, 1.0)];
  if (fill.type == FillType.radial) {
    return ui.Gradient.radial(ui.Offset(w / 2, h / 2), math.sqrt(w * w + h * h) / 2,
        colors, pos, ui.TileMode.clamp);
  }
  final a = fill.angle * math.pi / 180;
  final dx = math.cos(a), dy = math.sin(a);
  var half = ((w / 2) * dx).abs() + ((h / 2) * dy).abs();
  if (half == 0) half = 1;
  return ui.Gradient.linear(
    ui.Offset(w / 2 - dx * half, h / 2 - dy * half),
    ui.Offset(w / 2 + dx * half, h / 2 + dy * half),
    colors,
    pos,
    ui.TileMode.clamp,
  );
}

// 5x5 row-major affine colour matrices (rows R, G, B, A, 1).
List<double> _ident() => [
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
      0, 0, 0, 0, 1,
    ];

List<double> _mul(List<double> a, List<double> b) {
  // a * b: b applies first.
  final r = List<double>.filled(25, 0);
  for (var i = 0; i < 5; i++) {
    for (var j = 0; j < 5; j++) {
      var s = 0.0;
      for (var k = 0; k < 5; k++) {
        s += a[i * 5 + k] * b[k * 5 + j];
      }
      r[i * 5 + j] = s;
    }
  }
  return r;
}

bool _noColourFx(Effects fx) =>
    fx.brightness == 100 && fx.contrast == 100 && fx.saturate == 100 && fx.grayscale <= 0;

/// CSS filter colour steps as one 5x4 matrix for `ColorFilter.matrix`
/// (offsets in 0..255). Order: brightness, contrast, saturate, grayscale.
List<double> cssFilterMatrix(Effects fx) {
  var m = _ident();
  if (!_noColourFx(fx)) {
    final b = fx.brightness / 100;
    final c = fx.contrast / 100;
    final s = fx.saturate / 100;
    final g = (fx.grayscale / 100).clamp(0.0, 1.0);
    final bright = _ident()
      ..[0] = b
      ..[6] = b
      ..[12] = b;
    final cont = _ident()
      ..[0] = c
      ..[4] = 127.5 * (1 - c)
      ..[6] = c
      ..[9] = 127.5 * (1 - c)
      ..[12] = c
      ..[14] = 127.5 * (1 - c);
    final sat = _ident();
    final sv = [
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, //
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s,
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s,
    ];
    final i = 1 - g;
    final gv = [
      0.2126 + 0.7874 * i, 0.7152 - 0.7152 * i, 0.0722 - 0.0722 * i, //
      0.2126 - 0.2126 * i, 0.7152 + 0.2848 * i, 0.0722 - 0.0722 * i,
      0.2126 - 0.2126 * i, 0.7152 - 0.7152 * i, 0.0722 + 0.9278 * i,
    ];
    final gray = _ident();
    for (var r = 0; r < 3; r++) {
      for (var k = 0; k < 3; k++) {
        sat[r * 5 + k] = sv[r * 3 + k];
        gray[r * 5 + k] = gv[r * 3 + k];
      }
    }
    m = _mul(gray, _mul(sat, _mul(cont, bright)));
  }
  return [for (var r = 0; r < 4; r++) for (var k = 0; k < 5; k++) m[r * 5 + k]];
}

/// The CSS filter of an element: blur, then the colour steps. Null when nothing is set.
ui.ImageFilter? cssFilter(Effects fx) {
  final hasBlur = fx.blur > 0;
  final hasColour = !_noColourFx(fx);
  if (!hasBlur && !hasColour) return null;
  final blur = hasBlur
      ? ui.ImageFilter.blur(sigmaX: fx.blur, sigmaY: fx.blur, tileMode: ui.TileMode.decal)
      : null;
  final colour =
      hasColour ? ui.ColorFilter.matrix(cssFilterMatrix(fx)) : null;
  if (blur != null && colour != null) {
    return ui.ImageFilter.compose(outer: colour, inner: blur);
  }
  return blur ?? colour;
}

ui.BlendMode blendOf(String name) {
  switch (name) {
    case 'multiply':
      return ui.BlendMode.multiply;
    case 'screen':
      return ui.BlendMode.screen;
    case 'overlay':
      return ui.BlendMode.overlay;
    case 'darken':
      return ui.BlendMode.darken;
    case 'lighten':
      return ui.BlendMode.lighten;
    case 'color-dodge':
      return ui.BlendMode.colorDodge;
    case 'color-burn':
      return ui.BlendMode.colorBurn;
    case 'hard-light':
      return ui.BlendMode.hardLight;
    case 'soft-light':
      return ui.BlendMode.softLight;
    case 'difference':
      return ui.BlendMode.difference;
    case 'exclusion':
      return ui.BlendMode.exclusion;
    case 'hue':
      return ui.BlendMode.hue;
    case 'saturation':
      return ui.BlendMode.saturation;
    case 'color':
      return ui.BlendMode.color;
    case 'luminosity':
      return ui.BlendMode.luminosity;
    default:
      return ui.BlendMode.srcOver;
  }
}

const int _m32 = 0xFFFFFFFF;

/// 32-bit integer multiply that is exact on the web too (no product past 2^53).
int _imul(int a, int b) {
  final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
  final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
  return ((al * bl) + ((((ah * bl) + (al * bh)) & 0xFFFF) * 65536)) & _m32;
}

/// The seeded generator of render.js `mulberry`.
double Function() mulberry32(int seed) {
  var a = seed & _m32;
  return () {
    a = (a + 0x6D2B79F5) & _m32;
    var t = a;
    t = _imul(t ^ (t >> 15), t | 1);
    t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & _m32)) & _m32;
    return ((t ^ (t >> 14)) & _m32) / 4294967296.0;
  };
}
