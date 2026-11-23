import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'color_pipeline.dart';
import 'lut.dart';
import 'photo_developer.dart';
import 'profile_table.dart';
import 'settings.dart';

// Uniform layout of shaders/develop.frag, in the order they are set below.
// Keep this copy and the one at the top of the shader the same.
//   float index  name          meaning
//    0, 1        uSize         output (= source) size, render px
//    2, 3        uOrigin       source top-left in the whole photo, render px
//    4, 5        uFull         whole photo size, render px
//    6           uScale        render px per full-resolution px
//    7           uLutSize      colour table nodes per side
//    8           uLutOn        1 = apply the colour table, 0 = skip it
//    9           uEv           Exposure (stops), for clarity's midtone weight
//   10           uNrLum        luminance noise reduction strength k (0 = off)
//   11           uNrEps        luminance noise reduction epsilon (stops^2)
//   12           uNrCol        colour noise reduction blend t (0 = off)
//   13           uSharpAmt     Amount/150 x Nyquist gain (0 = off)
//   14           uSharpLimit   soft-clip limit (stops), from Detail
//   15           uSharpMask    Masking/100
//   16           uTexture      Texture/100
//   17           uClarity      Clarity/100
//   18           uDehaze       Dehaze/100
//   19           uAir          airlight (linear, whole photo)
//   20           uVigAmount    Vignette/100
//   21           uVigStart     0.15 + Midpoint/100 x 0.95
//   22           uVigWidth     0.05 + Feather/100 x 1.1
//   23           uVigMix       (Roundness/100 + 1) / 2
//   24           uVigPower     2, or 2 + 6 x -Roundness/100 below 0
//   25           uVigHigh      Highlights/100
//   26           uGrainAmt     Amount/100 x 0.13 (0 = off)
//   27           uGrainCell    grain cell, full-resolution px
//   28           uGrainRough   Roughness/100
// Samplers: 0 uSrc, 1 uBlurNrLum, 2 uBlurNrCol, 3 uBlurSharp, 4 uBlurTex,
// 5 uBlurClar, 6 uLut. An unused blur is bound to the source.

/// The blurred copies the shader reads.
enum _Blur { nrLum, nrCol, sharp, tex, clar }

/// Blur sigma (render px) and blend weight for a noise reduction radius
/// below one pixel (LightCraft `nr_radius`, notes 8.6).
(double, double) _nrRadius(double raw) {
  if (raw >= 1) return (raw, 1);
  const boxSigma1 = 0.8165;
  final w = raw / boxSigma1;
  return (1, math.min(w * w, 1));
}

/// Sharpening gain for a blur radius below one pixel: matches the continuous
/// Gaussian's Nyquist response (LightCraft `CL local.rs:819-833`, notes 8.5).
double sharpenGain(double raw) {
  if (!raw.isFinite || raw <= 0) return 0;
  if (raw >= 1) return 1;
  final sigma = raw.clamp(0.5, 64.0);
  final r = (3 * sigma).ceil();
  final k = -0.5 / (sigma * sigma);
  final taps = [for (var i = -r; i <= r; i++) math.exp(i * i * k)];
  final sum = taps.fold(0.0, (a, b) => a + b);
  var response = 0.0;
  for (var j = 0; j < taps.length; j++) {
    response += ((j + r).isEven ? 1 : -1) * taps[j] / sum;
  }
  final desired = 1 - math.exp(-0.5 * math.pi * math.pi * raw * raw);
  final ratio = desired / math.max(1 - response, 1e-6);
  final blend = ((1 - raw) / 0.5).clamp(0.0, 1.0);
  return 1 + (ratio - 1) * blend;
}

/// Everything the shader needs from the settings, for one render scale and
/// photo size. Sigmas are in render pixels.
class _Plan {
  _Plan(EditSettings s, double scale, ui.Size full) {
    final long = math.max(full.width, full.height);
    final sc = math.min(scale, 1.0);

    // Luminance noise reduction (notes 8.6). The radius is fixed per scale
    // (LightCraft's at Luminance 60) so dragging the slider reuses the blur.
    final lum = s[Setting.noiseLuminance] / 100;
    if (lum > 0) {
      final (sigma, w) = _nrRadius(2.5 * scale);
      if (w >= 0.01) {
        final detail = s[Setting.noiseDetail] / 100;
        sigmas[_Blur.nrLum] = sigma;
        nrLum = math.sqrt(lum) * w;
        nrEps = math.max(
          (0.002 + lum * lum * 0.25 * (1 - 0.7 * detail)) * sc * sc,
          1e-7,
        );
      }
    }

    // Colour noise reduction, legacy method (notes 8.7). Fixed radius as
    // above (LightCraft's at Colour 50, Smoothness 50 is 6.75 px); the
    // Smoothness slider scales the blend instead.
    final col = s[Setting.noiseColour] / 100;
    if (col > 0) {
      final (sigma, w) = _nrRadius(6 * scale);
      final detail = s[Setting.noiseColourDetail] / 100;
      final smooth = 1 + s[Setting.noiseColourSmoothness] / 100;
      final t = math.min(col * (1 - detail * 0.5) * w * smooth / 1.5, 1.0);
      if (t > 0) {
        sigmas[_Blur.nrCol] = sigma;
        nrCol = t;
      }
    }

    // Sharpening (notes 8.5): Radius in full-resolution px.
    final amount = s[Setting.sharpenAmount] / 150;
    if (amount > 0) {
      final raw = s[Setting.sharpenRadius] * scale;
      final gain = sharpenGain(raw);
      if (gain > 0) {
        sigmas[_Blur.sharp] = raw.clamp(0.5, 64.0);
        sharpAmt = amount * gain;
        sharpLimit =
            0.03 * math.pow(50, (s[Setting.sharpenDetail] / 100).clamp(0, 1));
        sharpMask = s[Setting.sharpenMasking] / 100;
      }
    }

    // Texture (notes 8.1, 8.2): 0.18 % of the long edge.
    texture = s[Setting.texture] / 100;
    if (texture != 0) sigmas[_Blur.tex] = math.max(0.0018 * long, 0.6);

    // Clarity (notes 8.1, 8.3) at 1.2 % of the long edge; dehaze reads its
    // dark channel from the same blur.
    clarity = s[Setting.clarity] / 100;
    dehaze = s[Setting.dehaze] / 100;
    if (clarity != 0 || dehaze != 0) {
      sigmas[_Blur.clar] = math.max(0.012 * long, 1);
    }

    // Vignette (notes 8.8).
    vigAmount = s[Setting.vignetteAmount] / 100;
    final round = s[Setting.vignetteRoundness] / 100;
    vigStart = 0.15 + s[Setting.vignetteMidpoint] / 100 * 0.95;
    vigWidth = 0.05 + s[Setting.vignetteFeather] / 100 * 1.1;
    vigMix = ((round + 1) / 2).clamp(0.0, 1.0);
    vigPower = round >= 0 ? 2 : 2 + (-round) * 6;
    vigHigh = s[Setting.vignetteHighlights] / 100;

    // Grain (notes 8.9): the cell is a fraction of the full-resolution long
    // edge, so the pattern is fixed to the photo, not to the render.
    grainAmt = s[Setting.grainAmount] / 100 * 0.13;
    final longFull = long / scale;
    grainCell = math.max(
      (0.0006 + s[Setting.grainSize] / 100 * 0.0024) * longFull,
      0.6,
    );
    grainRough = s[Setting.grainRoughness] / 100;
  }

  final Map<_Blur, double> sigmas = {};
  double nrLum = 0, nrEps = 1, nrCol = 0;
  double sharpAmt = 0, sharpLimit = 1, sharpMask = 0;
  late final double texture, clarity, dehaze;
  late final double vigAmount, vigStart, vigWidth, vigMix, vigPower, vigHigh;
  late final double grainAmt, grainCell, grainRough;

  /// True when any blur, the vignette or the grain is in use: the source
  /// cannot be returned as it is.
  bool get hasEffects => sigmas.isNotEmpty || vigAmount != 0 || grainAmt > 0;

  /// 3 sigma of the widest blur in use, plus 2 px for rounding and
  /// sampling; 0 when no blur is used (vignette and grain are positional).
  int get margin {
    var m = 0;
    for (final sigma in sigmas.values) {
      m = math.max(m, (3 * sigma).ceil() + 2);
    }
    return m;
  }
}

/// The blurred copies of one source image at one scale and photo size.
/// Each copy is keyed by its kind and sigma; only the sharpening blur's
/// sigma changes within a set (with Radius), and only its last one is kept.
class _BlurSet {
  _BlurSet(this.src, this.scale, this.long);

  final ui.Image src;
  final double scale, long;
  final Map<(_Blur, double), ui.Image> images = {};
  bool evicted = false;

  bool matches(ui.Image s, double sc, double l) =>
      identical(src, s) && scale == sc && long == l;

  /// Stores [img] for ([kind], [sigma]), dropping an older sharpening blur.
  void put(_Blur kind, double sigma, ui.Image img) {
    if (kind == _Blur.sharp) {
      images.removeWhere((k, v) {
        if (k.$1 != _Blur.sharp) return false;
        v.dispose();
        return true;
      });
    }
    images[(kind, sigma)] = img;
  }

  void dispose() {
    evicted = true;
    for (final i in images.values) {
      i.dispose();
    }
    images.clear();
  }
}

/// The GPU developer: one fragment shader pass over blurred copies of the
/// source and a baked colour table (shaders/develop.frag).
class ShaderDeveloper implements PhotoDeveloper {
  ShaderDeveloper._(this._program);

  static Future<ShaderDeveloper> load() async =>
      ShaderDeveloper._(await ui.FragmentProgram.fromAsset(_asset));

  static const String _asset = 'shaders/develop.frag';

  final ui.FragmentProgram _program;

  // Blurred inputs per (image identity, scale, photo size), the last two
  // entries, newest last. The sharpening blur is also keyed by its sigma.
  final List<_BlurSet> _blurSets = [];

  /// How many blurred copies this developer has made, for tests.
  @visibleForTesting
  int debugBlursMade = 0;

  // The last colour table, keyed by the global settings, profile and size.
  ui.Image? _lut;
  String? _lutKey;
  ProfileTable? _lutProfile;

  @override
  int margin(EditSettings s, double scale, {required ui.Size fullSize}) {
    assert(scale > 0);
    return _Plan(s, scale, fullSize).margin;
  }

  @override
  Future<ui.Image> develop(
    ui.Image src,
    EditSettings s, {
    ProfileTable? profile,
    double scale = 1,
    ui.Offset origin = ui.Offset.zero,
    ui.Size? fullSize,
    int lutSize = 33,
    DevelopStats? stats,
  }) async {
    assert(scale > 0);
    assert(lutSize >= 2);
    final w = src.width, h = src.height;
    final full = fullSize ?? ui.Size(w.toDouble(), h.toDouble());
    final plan = _Plan(s, scale, full);
    final pipeline = ColorPipeline(s, profile: profile);
    // A profile table acts even on neutral settings, so test the pipeline,
    // not EditSettings.isNeutral.
    if (pipeline.isIdentity && !plan.hasEffects) return copyImage(src);

    var air = 1.0;
    if (plan.dehaze != 0) air = (stats ?? await _measure(src)).airlight;

    // Images below are this call's own handles (clones), freed at the end.
    final blurs = <_Blur, ui.Image>{};
    ui.Image? lut;
    try {
      final set = _blurSetFor(src, scale, math.max(full.width, full.height));
      for (final e in plan.sigmas.entries) {
        blurs[e.key] = await _blur(set, e.key, e.value);
      }
      if (!pipeline.isIdentity) {
        lut = await _lutFor(s, profile, pipeline, lutSize);
      }

      final sh = _program.fragmentShader();
      try {
        var i = 0;
        void f(double v) => sh.setFloat(i++, v);
        f(w.toDouble());
        f(h.toDouble());
        f(origin.dx);
        f(origin.dy);
        f(full.width);
        f(full.height);
        f(scale);
        f(lutSize.toDouble());
        f(lut == null ? 0 : 1);
        f(s[Setting.exposure]);
        f(plan.nrLum);
        f(plan.nrEps);
        f(plan.nrCol);
        f(plan.sharpAmt);
        f(plan.sharpLimit);
        f(plan.sharpMask);
        f(plan.texture);
        f(plan.clarity);
        f(plan.dehaze);
        f(air);
        f(plan.vigAmount);
        f(plan.vigStart);
        f(plan.vigWidth);
        f(plan.vigMix);
        f(plan.vigPower);
        f(plan.vigHigh);
        f(plan.grainAmt);
        f(plan.grainCell);
        f(plan.grainRough);
        // Every read is at a texel centre: no filtering.
        void sampler(int index, ui.Image img) => sh.setImageSampler(
          index,
          img,
          filterQuality: ui.FilterQuality.none,
        );
        sampler(0, src);
        sampler(1, blurs[_Blur.nrLum] ?? src);
        sampler(2, blurs[_Blur.nrCol] ?? src);
        sampler(3, blurs[_Blur.sharp] ?? src);
        sampler(4, blurs[_Blur.tex] ?? src);
        sampler(5, blurs[_Blur.clar] ?? src);
        sampler(6, lut ?? src);
        return await recordImage(
          w,
          h,
          (c) => c.drawRect(
            ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
            ui.Paint()..shader = sh,
          ),
        );
      } finally {
        sh.dispose();
      }
    } finally {
      for (final b in blurs.values) {
        b.dispose();
      }
      lut?.dispose();
    }
  }

  @override
  void clearCache() {
    for (final b in _blurSets) {
      b.dispose();
    }
    _blurSets.clear();
  }

  @override
  void dispose() {
    clearCache();
    _lut?.dispose();
    _lut = null;
    _lutKey = null;
    _lutProfile = null;
  }

  /// Measures [src] itself, on a copy of at most 512 px.
  Future<DevelopStats> _measure(ui.Image src) async {
    final long = math.max(src.width, src.height);
    if (long <= 512) return measureStats(src);
    final k = 512 / long;
    final small = await scaleImage(
      src,
      math.max((src.width * k).round(), 1),
      math.max((src.height * k).round(), 1),
    );
    try {
      return await measureStats(small);
    } finally {
      small.dispose();
    }
  }

  _BlurSet _blurSetFor(ui.Image src, double scale, double long) {
    for (final b in _blurSets) {
      if (b.matches(src, scale, long)) {
        _blurSets
          ..remove(b)
          ..add(b);
        return b;
      }
    }
    final b = _BlurSet(src, scale, long);
    _blurSets.add(b);
    while (_blurSets.length > 2) {
      _blurSets.removeAt(0).dispose();
    }
    return b;
  }

  /// A handle the caller disposes: a clone of the cached blur, or the blur
  /// itself when its set was evicted while it was being made.
  Future<ui.Image> _blur(_BlurSet set, _Blur kind, double sigma) async {
    final cached = set.images[(kind, sigma)];
    if (cached != null) return cached.clone();
    final img = await blurImage(set.src, sigma);
    debugBlursMade++;
    if (set.evicted) return img;
    final again = set.images[(kind, sigma)];
    if (again != null) {
      img.dispose();
      return again.clone();
    }
    set.put(kind, sigma, img);
    return img.clone();
  }

  /// A handle the caller disposes to the colour table for these settings.
  Future<ui.Image> _lutFor(
    EditSettings s,
    ProfileTable? profile,
    ColorPipeline pipeline,
    int size,
  ) async {
    final key =
        '$size ${jsonEncode(s.toPatch().without({ToolGroup.effects, ToolGroup.detail}).toJson())}';
    final cached = _lut;
    if (cached != null && _lutKey == key && identical(_lutProfile, profile)) {
      return cached.clone();
    }
    final table = bakeLut(pipeline, size);
    final img = await imageFromRgba(table.rgba, size * size, size);
    _lut?.dispose();
    _lut = img;
    _lutKey = key;
    _lutProfile = profile;
    return img.clone();
  }
}
