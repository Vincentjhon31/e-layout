import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'color_pipeline.dart';
import 'lut.dart';
import 'mask_raster.dart';
import 'masks.dart';
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
//
// Uniform layout of shaders/mask_apply.frag:
//   float index  name    meaning
//    0, 1        uSize   output (= base) size, px
// Samplers: 0 uBase, 1 uLocal, 2 uCov. All three are drawn images.

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
  // Not final: [narrow] turns them off for a mask with no blur budget left.
  late double texture, clarity, dehaze;
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

  /// The widest blur sigma in use, 0 without blurs.
  double get maxSigma => sigmas.values.fold(0.0, math.max);

  /// Narrows every blur by [k] (0 to 1). At 0 the blurs and the effects that
  /// read them (texture, clarity, dehaze) are off.
  void narrow(double k) {
    if (k >= 1) return;
    if (k <= 0) {
      sigmas.clear();
      texture = 0;
      clarity = 0;
      dehaze = 0;
      return;
    }
    for (final e in sigmas.keys.toList()) {
      sigmas[e] = sigmas[e]! * k;
    }
  }
}

/// The largest total blur reach, in render px, that masks may bring the
/// margin up to: with it, an exported piece (a 64 px step plus the margin on
/// both sides) stays within 2048 px.
const int kMaxMarginPx = 960;

/// The main pass's plan, and the plan of each mask with an effect, in order.
///
/// A mask's pass blurs the image so far, so the reaches add. When the main
/// reach plus the masks' would pass [kMaxMarginPx], every mask's blurs
/// (texture, clarity, dehaze) are narrowed by one factor so the total fits.
/// The main pass's blurs are never narrowed. This is a rare-case
/// approximation: it only binds with several clarity masks on very large
/// photos at full size. [ShaderDeveloper.margin] and
/// [ShaderDeveloper.develop] both use it, so tiles still match whole renders.
(_Plan, List<(Mask, _Plan)>) _plans(
  EditSettings s,
  double scale,
  ui.Size full, {
  int cap = kMaxMarginPx,
}) {
  final main = _Plan(s, scale, full);
  final masks = [
    for (final m in s.masks)
      if (m.hasEffect) (m, _Plan(maskSettings(m), scale, full)),
  ];
  var total = main.margin;
  for (final e in masks) {
    total += e.$2.margin;
  }
  if (total > cap) {
    final blurred = [
      for (final e in masks)
        if (e.$2.sigmas.isNotEmpty) e.$2,
    ];
    // Each narrowed reach is ceil(3 sigma k) + 2 <= 3 sigma k + 3.
    final room = cap - main.margin - 3 * blurred.length;
    var need = 0.0;
    for (final p in blurred) {
      need += 3 * p.maxSigma;
    }
    final k = room > 0 && need > 0 ? math.min(room / need, 1.0) : 0.0;
    for (final p in blurred) {
      p.narrow(k);
    }
  }
  return (main, masks);
}

/// The blurred copies of one source image at one scale and photo size.
/// Each copy is keyed by its kind and sigma; only the sharpening blur's
/// sigma changes within a set (with Radius), and only its last one is kept.
class _BlurSet {
  _BlurSet(this.src, this.scale, this.long);

  final ui.Image src;
  final double scale, long;
  final Map<(_Blur, double), ui.Image> images = {};

  /// [src] drawn into a new image, so the shader samples the same kind of
  /// texture as the blurs (see [ShaderDeveloper._drawnSource]).
  ui.Image? drawn;
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
    drawn?.dispose();
    drawn = null;
  }
}

/// The GPU developer: one fragment shader pass over blurred copies of the
/// source and a baked colour table (shaders/develop.frag).
///
/// Masks follow the main pass, each in order (see [PhotoDeveloper.develop]):
/// the image so far is developed again through develop.frag with the mask's
/// [maskSettings] (its own colour table and blurs of that image, so its
/// texture, clarity and dehaze use the main pass's maths), then
/// shaders/mask_apply.frag mixes the two by the mask's coverage.
class ShaderDeveloper implements PhotoDeveloper {
  ShaderDeveloper._(this._program, this._applyProgram, this._raster);

  static Future<ShaderDeveloper> load() async => ShaderDeveloper._(
    await ui.FragmentProgram.fromAsset(_asset),
    await ui.FragmentProgram.fromAsset(_applyAsset),
    await MaskRasterizer.load(),
  );

  static const String _asset = 'shaders/develop.frag';
  static const String _applyAsset = 'shaders/mask_apply.frag';

  final ui.FragmentProgram _program;
  final ui.FragmentProgram _applyProgram;
  final MaskRasterizer _raster;

  // Mask coverage per (components, region, photo size, scale, and the auto
  // maps or source they read), the last [_maxCoverages], newest last.
  final List<_Coverage> _coverages = [];
  static const int _maxCoverages = 8;
  // Bumped by clearCache, so a coverage drawn across it is not kept.
  int _coverageGen = 0;

  /// The total reach the masks may bring the margin up to; tests lower it
  /// to see the cap at work on small photos.
  @visibleForTesting
  int debugMaxMarginPx = kMaxMarginPx;

  /// How many mask coverages this developer has drawn, for tests.
  @visibleForTesting
  int debugCoveragesDrawn = 0;

  // Masks' colour tables by key, the last [_maxLocalLuts], newest last.
  final List<(String, ui.Image)> _localLuts = [];
  static const int _maxLocalLuts = 8;

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

  /// The main pass's blur reach plus each mask's: a mask's pass blurs the
  /// main pass's output (and the masks before it), so the reaches add. The
  /// masks' share is capped so the total stays within [kMaxMarginPx] (see
  /// [_plans]); the main pass's own reach is never cut.
  @override
  int margin(EditSettings s, double scale, {required ui.Size fullSize}) {
    assert(scale > 0);
    final (main, masks) = _plans(s, scale, fullSize, cap: debugMaxMarginPx);
    var m = main.margin;
    for (final e in masks) {
      m += e.$2.margin;
    }
    return m;
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
    AutoMapsSource? auto,
  }) async {
    assert(scale > 0);
    assert(lutSize >= 2);
    final full =
        fullSize ?? ui.Size(src.width.toDouble(), src.height.toDouble());
    final (main, masks) = _plans(s, scale, full, cap: debugMaxMarginPx);
    var cur = await _developMain(
      src,
      s,
      main,
      profile: profile,
      scale: scale,
      origin: origin,
      full: full,
      lutSize: lutSize,
      stats: stats,
    );
    var done = false;
    try {
      for (final (m, plan) in masks) {
        final next = await _applyMask(
          m,
          plan,
          src: src,
          cur: cur,
          scale: scale,
          origin: origin,
          full: full,
          lutSize: lutSize,
          stats: stats,
          auto: auto,
        );
        cur.dispose();
        cur = next;
      }
      done = true;
      return cur;
    } finally {
      if (!done) cur.dispose();
    }
  }

  /// The global edits: a new drawn image the caller owns.
  Future<ui.Image> _developMain(
    ui.Image src,
    EditSettings s,
    _Plan plan, {
    required ProfileTable? profile,
    required double scale,
    required ui.Offset origin,
    required ui.Size full,
    required int lutSize,
    required DevelopStats? stats,
  }) async {
    final pipeline = ColorPipeline(s, profile: profile);
    // A profile table acts even on neutral settings, so test the pipeline,
    // not EditSettings.isNeutral.
    if (pipeline.isIdentity && !plan.hasEffects) return copyImage(src);

    var air = 1.0;
    if (plan.dehaze != 0) air = (stats ?? await _measure(src)).airlight;

    // Images below are this call's own handles (clones), freed at the end.
    final blurs = <_Blur, ui.Image>{};
    ui.Image? lut;
    ui.Image? tex;
    try {
      final set = _blurSetFor(src, scale, math.max(full.width, full.height));
      tex = await _drawnSource(set);
      for (final e in plan.sigmas.entries) {
        blurs[e.key] = await _blur(set, e.key, e.value);
      }
      if (!pipeline.isIdentity) {
        lut = await _lutFor(s, profile, pipeline, lutSize);
      }

      return await _pass(
        tex,
        blurs,
        lut,
        plan,
        ev: s[Setting.exposure],
        air: air,
        origin: origin,
        full: full,
        scale: scale,
        lutSize: lutSize,
      );
    } finally {
      for (final b in blurs.values) {
        b.dispose();
      }
      lut?.dispose();
      tex?.dispose();
    }
  }

  /// One develop.frag pass over [tex] (a drawn image) with [blurs] of it and
  /// the colour table [lut]; a new image of [tex]'s size.
  Future<ui.Image> _pass(
    ui.Image tex,
    Map<_Blur, ui.Image> blurs,
    ui.Image? lut,
    _Plan plan, {
    required double ev,
    required double air,
    required ui.Offset origin,
    required ui.Size full,
    required double scale,
    required int lutSize,
  }) async {
    final w = tex.width, h = tex.height;
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
      f(ev);
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
      void sampler(int index, ui.Image img) =>
          sh.setImageSampler(index, img, filterQuality: ui.FilterQuality.none);
      sampler(0, tex);
      sampler(1, blurs[_Blur.nrLum] ?? tex);
      sampler(2, blurs[_Blur.nrCol] ?? tex);
      sampler(3, blurs[_Blur.sharp] ?? tex);
      sampler(4, blurs[_Blur.tex] ?? tex);
      sampler(5, blurs[_Blur.clar] ?? tex);
      sampler(6, lut ?? tex);
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
  }

  /// Applies [m] to [cur], the image so far (a drawn image of [src]'s
  /// region): [cur] developed with the mask's settings, mixed back by the
  /// mask's coverage, with the mask's [plan] from [_plans]. A new image;
  /// [cur] stays the caller's.
  Future<ui.Image> _applyMask(
    Mask m,
    _Plan plan, {
    required ui.Image src,
    required ui.Image cur,
    required double scale,
    required ui.Offset origin,
    required ui.Size full,
    required int lutSize,
    required DevelopStats? stats,
    required AutoMapsSource? auto,
  }) async {
    final ms = maskSettings(m);
    final pipeline = ColorPipeline(ms);
    final blurs = <_Blur, ui.Image>{};
    ui.Image? cov, lut, local;
    try {
      cov = await _coverageFor(m, src, origin, full, scale, auto);
      var air = 1.0;
      if (plan.dehaze != 0) air = (stats ?? await _measure(cur)).airlight;
      // Blurs of the image so far: new on every call, so not cached.
      for (final e in plan.sigmas.entries) {
        blurs[e.key] = await blurImage(cur, e.value);
      }
      if (!pipeline.isIdentity) {
        lut = await _localLutFor(ms, pipeline, lutSize);
      }
      local = await _pass(
        cur,
        blurs,
        lut,
        plan,
        ev: ms[Setting.exposure],
        air: air,
        origin: origin,
        full: full,
        scale: scale,
        lutSize: lutSize,
      );
      return await _mix(cur, local, cov);
    } finally {
      for (final b in blurs.values) {
        b.dispose();
      }
      cov?.dispose();
      lut?.dispose();
      local?.dispose();
    }
  }

  /// mask_apply.frag: `mix(base, local, coverage)`, a new image.
  Future<ui.Image> _mix(ui.Image base, ui.Image local, ui.Image cov) async {
    final w = base.width, h = base.height;
    final sh = _applyProgram.fragmentShader();
    try {
      sh.setFloat(0, w.toDouble());
      sh.setFloat(1, h.toDouble());
      sh.setImageSampler(0, base, filterQuality: ui.FilterQuality.none);
      sh.setImageSampler(1, local, filterQuality: ui.FilterQuality.none);
      sh.setImageSampler(2, cov, filterQuality: ui.FilterQuality.none);
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
  }

  /// A handle the caller disposes to [m]'s coverage of [src]'s region,
  /// drawn once per (components, region, photo size, scale, inputs).
  Future<ui.Image> _coverageFor(
    Mask m,
    ui.Image src,
    ui.Offset origin,
    ui.Size full,
    double scale,
    AutoMapsSource? auto,
  ) async {
    final key = _Coverage.keyOf(m, src, origin, full, scale);
    // Only what the coverage reads is part of its identity.
    final shapes = [for (final c in m.components) c.shape];
    final readsAuto = shapes.any(
      (s) => s is SubjectShape || s is SkyShape || s is BackgroundShape,
    );
    final readsSrc = shapes.any(
      (s) => s is LuminanceRangeShape || s is ColourRangeShape,
    );
    final a = readsAuto ? auto : null;
    final r = readsSrc ? src : null;
    for (final c in _coverages) {
      if (c.matches(key, a, r)) {
        _coverages
          ..remove(c)
          ..add(c);
        return c.image.clone();
      }
    }
    final gen = _coverageGen;
    final img = await _raster.coverage(
      m,
      src: src,
      origin: origin,
      fullSize: full,
      scale: scale,
      auto: auto,
    );
    debugCoveragesDrawn++;
    if (gen != _coverageGen) return img;
    for (final c in _coverages) {
      if (c.matches(key, a, r)) {
        img.dispose();
        return c.image.clone();
      }
    }
    _coverages.add(_Coverage(key, a, r, img));
    while (_coverages.length > _maxCoverages) {
      _coverages.removeAt(0).image.dispose();
    }
    return img.clone();
  }

  /// A handle the caller disposes to the colour table of a mask's settings.
  Future<ui.Image> _localLutFor(
    EditSettings ms,
    ColorPipeline pipeline,
    int size,
  ) async {
    final key = _lutKeyOf(ms, size);
    for (final e in _localLuts) {
      if (e.$1 == key) {
        _localLuts
          ..remove(e)
          ..add(e);
        return e.$2.clone();
      }
    }
    debugLutsBaked++;
    final table = bakeLut(pipeline, size);
    final img = await imageFromRgba(table.rgba, size * size, size);
    for (final e in _localLuts) {
      if (e.$1 == key) {
        img.dispose();
        return e.$2.clone();
      }
    }
    _localLuts.add((key, img));
    while (_localLuts.length > _maxLocalLuts) {
      _localLuts.removeAt(0).$2.dispose();
    }
    return img.clone();
  }

  @override
  void clearCache() {
    for (final b in _blurSets) {
      b.dispose();
    }
    _blurSets.clear();
    _coverageGen++;
    for (final c in _coverages) {
      c.image.dispose();
    }
    _coverages.clear();
  }

  @override
  void dispose() {
    clearCache();
    _lut?.dispose();
    _lut = null;
    _lutKey = null;
    _lutProfile = null;
    for (final e in _localLuts) {
      e.$2.dispose();
    }
    _localLuts.clear();
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

  /// How many colour tables this developer has baked, for tests.
  @visibleForTesting
  int debugLutsBaked = 0;

  /// How many drawn copies of a source this developer has made, for tests.
  @visibleForTesting
  int debugDrawnCopies = 0;

  /// A handle the caller disposes to [set]'s source drawn into a new image.
  ///
  /// Impeller's OpenGL ES backend stores images it drew (blurs, copies) bottom
  /// up, unlike images uploaded from a decoder, and only its own drawing code
  /// corrects for that. The shader flips its reads on GLES, so every photo
  /// texture it samples must be a drawn one: the blurs already are, and this
  /// makes the source one too, whatever the caller passed.
  Future<ui.Image> _drawnSource(_BlurSet set) async {
    final cached = set.drawn;
    if (cached != null) return cached.clone();
    final img = await copyImage(set.src);
    debugDrawnCopies++;
    if (set.evicted) return img;
    final again = set.drawn;
    if (again != null) {
      img.dispose();
      return again.clone();
    }
    set.drawn = img;
    return img.clone();
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
    final key = _lutKeyOf(s, size);
    final cached = _lut;
    if (cached != null && _lutKey == key && identical(_lutProfile, profile)) {
      return cached.clone();
    }
    debugLutsBaked++;
    final table = bakeLut(pipeline, size);
    final img = await imageFromRgba(table.rgba, size * size, size);
    _lut?.dispose();
    _lut = img;
    _lutKey = key;
    _lutProfile = profile;
    return img.clone();
  }
}

/// The colour table's cache key: what the table depends on, at [size].
String _lutKeyOf(EditSettings s, int size) =>
    '$size ${jsonEncode(s.toPatch().without({ToolGroup.effects, ToolGroup.detail, ToolGroup.masks}).toJson())}';

/// One cached mask coverage.
class _Coverage {
  _Coverage(this.key, this.auto, this.src, this.image);

  /// The components, region, photo size and scale.
  final String key;

  /// The auto maps and the source the coverage read, by identity (null when
  /// it read none).
  final AutoMapsSource? auto;
  final ui.Image? src;
  final ui.Image image;

  static String keyOf(
    Mask m,
    ui.Image src,
    ui.Offset origin,
    ui.Size full,
    double scale,
  ) => jsonEncode([
    [for (final c in m.components) c.toJson()],
    origin.dx,
    origin.dy,
    src.width,
    src.height,
    full.width,
    full.height,
    scale,
  ]);

  bool matches(String k, AutoMapsSource? a, ui.Image? s) =>
      key == k && identical(auto, a) && identical(src, s);
}
