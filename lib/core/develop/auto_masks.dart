import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;

import 'mask_raster.dart';
import 'photo_developer.dart';

// The automatic Subject and Sky maps. Ported from LightCraft (MIT OR
// Apache-2.0), crates/pipeline/src/masks.rs (the Sky and Subject heuristics,
// `smooth`, `smooth_plane`, the guided filter) and lens_blur.rs
// (`subject_point`). No model and nothing online: classical heuristics only.

/// The long edge, in px, the maps are computed at.
const int kAutoMapEdge = 384;

/// The automatic coverage maps of one photo.
///
/// Each map is a drawn image at most [kAutoMapEdge] px on its long edge,
/// white with coverage 0 to 1 in its alpha. The masks stretch it over the
/// photo. [subjectPoint] is the likely subject, normalised to the photo.
class AutoMaps implements AutoMapsSource {
  AutoMaps({
    required this.subject,
    required this.sky,
    required this.subjectPoint,
  });

  @override
  final ui.Image subject;
  @override
  final ui.Image sky;
  final (double, double) subjectPoint;

  void dispose() {
    subject.dispose();
    sky.dispose();
  }
}

/// Computes the maps of [photo] (not disposed). The heavy maths runs in a
/// background isolate.
Future<AutoMaps> computeAutoMaps(ui.Image photo) async {
  final long = math.max(photo.width, photo.height);
  ui.Image? small;
  try {
    if (long > kAutoMapEdge) {
      final k = kAutoMapEdge / long;
      small = await scaleImage(
        photo,
        math.max(1, (photo.width * k).round()),
        math.max(1, (photo.height * k).round()),
      );
    }
    final src = small ?? photo;
    final w = src.width, h = src.height;
    final rgba = await readRgba(src);
    final r = await compute(_planesJob, (rgba, w, h));
    final subject = await _upload(r.$1, w, h);
    try {
      final sky = await _upload(r.$2, w, h);
      return AutoMaps(subject: subject, sky: sky, subjectPoint: (r.$3, r.$4));
    } catch (_) {
      subject.dispose();
      rethrow;
    }
  } finally {
    small?.dispose();
  }
}

/// A white image with [alpha] as its alpha, as a drawn image (the GLES rule:
/// shaders and canvases read drawn images, not uploaded ones).
Future<ui.Image> _upload(Uint8List alpha, int w, int h) async {
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    rgba[i * 4] = 255;
    rgba[i * 4 + 1] = 255;
    rgba[i * 4 + 2] = 255;
    rgba[i * 4 + 3] = alpha[i];
  }
  final up = await imageFromRgba(rgba, w, h);
  try {
    return await copyImage(up);
  } finally {
    up.dispose();
  }
}

(Uint8List, Uint8List, double, double) _planesJob((Uint8List, int, int) a) {
  final p = autoMapPlanes(a.$1, a.$2, a.$3);
  return (p.subject, p.sky, p.point.$1, p.point.$2);
}

/// The result of [autoMapPlanes]: alpha planes (0..255) and the subject point.
class AutoMapPlanes {
  AutoMapPlanes(this.subject, this.sky, this.point);
  final Uint8List subject, sky;
  final (double, double) point;
}

/// The pure maths behind [computeAutoMaps], on [rgba] (straight, [w] x [h]).
/// Works on Float32List planes; every value is finite and in 0..1.
AutoMapPlanes autoMapPlanes(Uint8List rgba, int w, int h) {
  final n = w * h;
  final lin = Float32List(256);
  for (var i = 0; i < 256; i++) {
    final v = i / 255;
    lin[i] = (v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4))
        .toDouble();
  }
  final logL = Float32List(n); // log2 of linear Rec.709 luminance
  final blue = Float32List(n); // (b - r)+ / (b + 1e-4), linear
  final guide = Float32List(n); // Rec.709 luma of the encoded values, 0..1
  for (var i = 0; i < n; i++) {
    final er = rgba[i * 4], eg = rgba[i * 4 + 1], eb = rgba[i * 4 + 2];
    final r = lin[er], g = lin[eg], b = lin[eb];
    final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    logL[i] = (math.log(math.max(l, 1e-4)) / math.ln2).toDouble();
    blue[i] = math.max(b - r, 0) / (b + 1e-4);
    guide[i] = (0.2126 * er + 0.7152 * eg + 0.0722 * eb) / 255;
  }
  final long = math.max(w, h).toDouble();

  // Sky: bright, smooth, blue-ish or unsaturated, near the top (masks.rs).
  final sky = Float32List(n);
  for (var i = 0; i < n; i++) {
    final y = (i ~/ w + 0.5) / h;
    final top = 1 - _smooth(0.25, 0.7, y);
    final l = logL[i];
    sky[i] =
        top *
        _smooth(-3.5, -1.0, l) *
        (0.4 + 0.6 * math.max(_smooth(0, 0.3, blue[i]), _smooth(0, 1.5, l)));
  }
  var skyOut = _gaussian(sky, w, h, 0.01 * long);

  // Subject: centre-weighted local contrast (masks.rs).
  final blur = _gaussian(logL, w, h, 0.03 * long);
  final subject = Float32List(n);
  for (var i = 0; i < n; i++) {
    final x = (i % w + 0.5) / w, y = (i ~/ w + 0.5) / h;
    final d = math.sqrt(
      math.pow((x - 0.5) / 0.35, 2) + math.pow((y - 0.55) / 0.4, 2),
    );
    final contrast = (logL[i] - blur[i]).abs();
    subject[i] =
        (1 - _smooth(0.6, 1.0, d)) * (0.5 + 0.5 * _smooth(0.05, 0.6, contrast));
  }
  var subjectOut = _gaussian(subject, w, h, 0.015 * long);

  // Guided filter, guide = luminance, window 2 % of the long edge, eps 1e-3.
  final g = _Guide(guide, w, h, 0.02 * long, 1e-3);
  skyOut = g.filter(skyOut);
  subjectOut = g.filter(subjectOut);

  return AutoMapPlanes(
    _toBytes(subjectOut),
    _toBytes(skyOut),
    _topCentroid(subjectOut, w, h),
  );
}

double _smooth(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

Uint8List _toBytes(Float32List p) {
  final out = Uint8List(p.length);
  for (var i = 0; i < p.length; i++) {
    final v = p[i];
    out[i] = v.isFinite ? (v.clamp(0.0, 1.0) * 255).round() : 0;
  }
  return out;
}

/// The normalised centroid of the map's top 10 % of pixels (at least one);
/// the middle of the photo when the map holds nothing.
(double, double) _topCentroid(Float32List p, int w, int h) {
  final n = p.length;
  final vals = Float32List.fromList(p)..sort();
  final k = math.max(1, (n * 0.1).round());
  final cut = vals[n - k];
  var sx = 0.0, sy = 0.0, cnt = 0;
  for (var i = 0; i < n; i++) {
    if (p[i].isFinite && p[i] >= cut) {
      sx += (i % w + 0.5) / w;
      sy += (i ~/ w + 0.5) / h;
      cnt++;
    }
  }
  if (cnt == 0) return (0.5, 0.5);
  return ((sx / cnt).clamp(0.0, 1.0), (sy / cnt).clamp(0.0, 1.0));
}

/// A separable Gaussian of [src] at [sigma] px, edges clamped.
Float32List _gaussian(Float32List src, int w, int h, double sigma) {
  final s = math.max(sigma, 0.5);
  final r = (3 * s).ceil();
  final k = Float32List(2 * r + 1);
  var sum = 0.0;
  for (var i = -r; i <= r; i++) {
    final v = math.exp(-(i * i) / (2 * s * s));
    k[i + r] = v;
    sum += v;
  }
  for (var i = 0; i < k.length; i++) {
    k[i] /= sum;
  }
  final tmp = Float32List(src.length);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      var acc = 0.0;
      for (var i = -r; i <= r; i++) {
        acc += k[i + r] * src[row + (x + i).clamp(0, w - 1)];
      }
      tmp[row + x] = acc;
    }
  }
  final out = Float32List(src.length);
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      var acc = 0.0;
      for (var i = -r; i <= r; i++) {
        acc += k[i + r] * tmp[(y + i).clamp(0, h - 1) * w + x];
      }
      out[y * w + x] = acc;
    }
  }
  return out;
}

/// Guided filter (He, Sun and Tang) steered by one guide; the guide's
/// statistics are computed once and reused for each plane (LightCraft
/// `guided_coeffs` / `guided_cross`).
class _Guide {
  _Guide(this.guide, this.w, this.h, this.sigma, this.eps)
    : mi = _gaussian(guide, w, h, sigma),
      cii = _gaussian(_squares(guide), w, h, sigma);

  final Float32List guide;
  final int w, h;
  final double sigma, eps;
  final Float32List mi, cii;

  static Float32List _squares(Float32List g) {
    final sq = Float32List(g.length);
    for (var i = 0; i < sq.length; i++) {
      sq[i] = g[i] * g[i];
    }
    return sq;
  }

  Float32List filter(Float32List p) {
    final n = p.length;
    final ip = Float32List(n);
    for (var i = 0; i < n; i++) {
      ip[i] = guide[i] * p[i];
    }
    final mp = _gaussian(p, w, h, sigma);
    final cip = _gaussian(ip, w, h, sigma);
    final a = Float32List(n), b = Float32List(n);
    for (var i = 0; i < n; i++) {
      final v = math.max(cii[i] - mi[i] * mi[i], 0.0);
      final k = (cip[i] - mi[i] * mp[i]) / (v + eps);
      a[i] = k;
      b[i] = mp[i] - k * mi[i];
    }
    final ma = _gaussian(a, w, h, sigma), mb = _gaussian(b, w, h, sigma);
    final q = Float32List(n);
    for (var i = 0; i < n; i++) {
      final v = ma[i] * guide[i] + mb[i];
      q[i] = v.isFinite ? v.clamp(0.0, 1.0) : 0.0;
    }
    return q;
  }
}
