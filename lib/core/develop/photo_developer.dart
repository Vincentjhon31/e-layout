import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'color_pipeline.dart';
import 'mask_raster.dart';
import 'masks.dart';
import 'profile_table.dart';
import 'settings.dart';

/// Whole-photo values that a tile cannot measure on its own. The caller
/// measures them once with [measureStats] on a small copy (about 512 px) and
/// passes them to every [PhotoDeveloper.develop] call for that photo.
class DevelopStats {
  const DevelopStats({required this.airlight});

  /// Dehaze's atmospheric light: the 99.5th percentile of the blurred dark
  /// channel (linear, before exposure), at least 0.05
  /// (LightCraft `CL local.rs:870-886`).
  final double airlight;

  @override
  String toString() => 'DevelopStats(airlight: $airlight)';
}

/// Renders a photo (or a tile of it) with a set of edits.
abstract class PhotoDeveloper {
  /// Develops [src] with [s] and returns a new image the caller owns (never
  /// [src] itself, even for neutral settings).
  ///
  /// - [scale]: render pixels per full-resolution photo pixel.
  /// - [origin]: where [src]'s top-left sits in the whole photo, in render
  ///   pixels.
  /// - [fullSize]: the whole photo, in render pixels (defaults to [src]'s
  ///   size).
  /// - [lutSize]: colour table nodes per side (17 while dragging, 33 after).
  /// - [stats]: whole-photo values from [measureStats]. Tiles must pass them;
  ///   when null and Dehaze is on, [src] itself is measured.
  /// - [auto]: the photo's automatic maps, for Subject, Sky and Background
  ///   mask components (which cover nothing without them).
  ///
  /// After the global edits, each mask with an effect ([Mask.hasEffect]) is
  /// applied in order: the image so far is developed with the mask's
  /// [maskSettings] and mixed back by the mask's coverage. Last, when
  /// [EditSettings.lensBlur] is on, what is out of focus is blurred.
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
  });

  /// The tile overlap, in render pixels, so that tiles cut with this much
  /// extra on every side and cropped back match one whole render.
  /// [fullSize] is the whole photo in render pixels, as in [develop]:
  /// texture, clarity and the lens blur reach a fraction of its long edge.
  int margin(EditSettings s, double scale, {required ui.Size fullSize});

  /// Frees the cached blurred copies (they hold on to the last sources).
  /// Call it between photos. The developer can still be used afterwards.
  void clearCache();

  /// Frees every cached image. The developer can still be used afterwards.
  void dispose();
}

/// The settings a mask develops its area with: its deltas over neutral
/// settings. Applied to the image as developed so far, this is a Phase 1
/// approximation of local adjustments, not an exact match of Lightroom's.
EditSettings maskSettings(Mask m) =>
    EditSettings.resolve([SettingsPatch(values: m.adjust)]);

/// True when developing [s] reads the whole-photo [DevelopStats]: global
/// Dehaze, or Dehaze in a mask that has an effect. Callers that cut tiles
/// must then measure them once and pass them to every tile.
bool needsStats(EditSettings s) =>
    s[Setting.dehaze] != 0 ||
    s.masks.any((m) => m.hasEffect && (m.adjust[Setting.dehaze] ?? 0) != 0);

/// True when developing [s] reads the photo's automatic maps
/// ([AutoMapsSource]): a mask with an effect that has a Subject, Sky or
/// Background component, or a lens blur focused on the subject (directly,
/// through a focus mask with such a component, or through a focus mask that
/// is missing or empty, which means the subject). Callers compute the maps
/// only then.
bool needsAutoMaps(EditSettings s) {
  bool usesAuto(Mask m) => m.components.any(
    (c) =>
        c.shape is SubjectShape ||
        c.shape is SkyShape ||
        c.shape is BackgroundShape,
  );
  if (s.masks.any((m) => m.hasEffect && usesAuto(m))) return true;
  final l = s.lensBlur;
  if (!l.isOn) return false;
  switch (l.focus) {
    case LensFocus.point:
      return false;
    case LensFocus.subject:
      return true;
    case LensFocus.mask:
      // As ShaderDeveloper picks it: the first mask with that id and parts.
      for (final m in s.masks) {
        if (m.id == l.maskId && m.components.isNotEmpty) return usesAuto(m);
      }
      return true;
  }
}

/// Global colour only, through [ColorPipeline] per pixel on the CPU, then
/// each mask's tone and colour deltas mixed in by its coverage
/// ([MaskRasterizer]). Effects and detail settings, global or in a mask, are
/// ignored. For tests and as a fake in later tasks.
///
/// The lens blur is a rough stand-in, so tests and fakes see something
/// blurred: the same focus maps, radius and weights as ShaderDeveloper's
/// lens_blur.frag, but nearest-pixel taps averaged on the encoded values. It
/// does not match the GPU's output and is not meant to.
class CpuDeveloper implements PhotoDeveloper {
  MaskRasterizer? _raster;

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
    final px = await readRgba(src);
    final p = ColorPipeline(s, profile: profile);
    if (!p.isIdentity) {
      for (var i = 0; i < px.length; i += 4) {
        final c = p.apply(px[i] / 255, px[i + 1] / 255, px[i + 2] / 255);
        px[i] = (c.$1 * 255).round();
        px[i + 1] = (c.$2 * 255).round();
        px[i + 2] = (c.$3 * 255).round();
      }
    }
    final full =
        fullSize ?? ui.Size(src.width.toDouble(), src.height.toDouble());
    for (final m in s.masks) {
      if (!m.hasEffect) continue;
      final local = ColorPipeline(maskSettings(m));
      if (local.isIdentity) continue;
      final r = _raster ??= await MaskRasterizer.load();
      final cov = await r.coverage(
        m,
        src: src,
        origin: origin,
        fullSize: full,
        scale: scale,
        auto: auto,
      );
      final Uint8List a;
      try {
        a = await readRgba(cov);
      } finally {
        cov.dispose();
      }
      for (var i = 0; i < px.length; i += 4) {
        final k = a[i + 3] / 255;
        if (k == 0) continue;
        final c = local.apply(px[i] / 255, px[i + 1] / 255, px[i + 2] / 255);
        px[i] = (px[i] + (c.$1 * 255 - px[i]) * k).round().clamp(0, 255);
        px[i + 1] = (px[i + 1] + (c.$2 * 255 - px[i + 1]) * k).round().clamp(
          0,
          255,
        );
        px[i + 2] = (px[i + 2] + (c.$3 * 255 - px[i + 2]) * k).round().clamp(
          0,
          255,
        );
      }
    }
    final lens = s.lensBlur;
    if (lens.isOn) {
      final focus = await _cpuFocus(lens, s, src, origin, full, scale, auto);
      if (focus != null) {
        _cpuLensBlur(px, src.width, src.height, focus, lens, full);
      }
    }
    return imageFromRgba(px, src.width, src.height);
  }

  /// Focus 0 to 1 per pixel of [src]'s region, or null when all is in focus.
  Future<Float32List?> _cpuFocus(
    LensBlur l,
    EditSettings s,
    ui.Image src,
    ui.Offset origin,
    ui.Size full,
    double scale,
    AutoMapsSource? auto,
  ) async {
    final w = src.width, h = src.height;
    final out = Float32List(w * h);
    if (l.focus == LensFocus.point) {
      final long = math.max(full.width, full.height);
      final t = l.transition / 100;
      final inner = (0.08 + 0.3 * (1 - t)) * long;
      final band = (0.05 + 0.4 * t) * long;
      final cx = l.fx * full.width - origin.dx;
      final cy = l.fy * full.height - origin.dy;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final d = math.sqrt(
            math.pow(x + 0.5 - cx, 2) + math.pow(y + 0.5 - cy, 2),
          );
          final k = ((d - inner) / band).clamp(0.0, 1.0);
          out[y * w + x] = 1 - k * k * (3 - 2 * k);
        }
      }
      return out;
    }
    Mask? m;
    if (l.focus == LensFocus.mask) {
      for (final c in s.masks) {
        if (c.id == l.maskId && c.components.isNotEmpty) m = c;
      }
    }
    if (m == null) {
      if (auto == null) return null;
      m = Mask(
        id: 'lens subject',
        components: [MaskComponent(const SubjectShape())],
      );
    }
    final r = _raster ??= await MaskRasterizer.load();
    final cov = await r.coverage(
      m,
      src: src,
      origin: origin,
      fullSize: full,
      scale: scale,
      auto: auto,
    );
    final Uint8List a;
    try {
      a = await readRgba(cov);
    } finally {
      cov.dispose();
    }
    for (var i = 0; i < out.length; i++) {
      out[i] = a[i * 4 + 3] / 255;
    }
    return out;
  }

  /// 48 golden-angle taps per pixel, nearest pixel, weighted as in
  /// lens_blur.frag (focus down-weight and highlight boost).
  static void _cpuLensBlur(
    Uint8List px,
    int w,
    int h,
    Float32List focus,
    LensBlur l,
    ui.Size full,
  ) {
    final rMax = _lensRadius(l, full);
    final power = 1 + l.transition / 50;
    final boost = l.boost / 25;
    final src = Uint8List.fromList(px);
    const taps = 48, golden = 2.39996323;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final f0 = focus[y * w + x];
        if (f0 >= 1) continue;
        final r = rMax * math.pow(1 - f0, power);
        if (r <= 0) continue;
        var sr = 0.0, sg = 0.0, sb = 0.0, sw = 0.0;
        for (var i = 0; i < taps; i++) {
          final rr = r * math.sqrt((i + 0.5) / taps);
          final th = i * golden;
          final qx = (x + rr * math.cos(th)).round().clamp(0, w - 1);
          final qy = (y + rr * math.sin(th)).round().clamp(0, h - 1);
          final q = qy * w + qx;
          final o = q * 4;
          final lum =
              (0.2126 * src[o] + 0.7152 * src[o + 1] + 0.0722 * src[o + 2]) /
              255;
          final wt =
              (1 - math.max(0.0, focus[q] - f0)) *
              (1 + boost * math.max(0.0, lum - 0.75) * 4);
          sr += src[o] * wt;
          sg += src[o + 1] * wt;
          sb += src[o + 2] * wt;
          sw += wt;
        }
        if (sw <= 1e-5) continue;
        final o = (y * w + x) * 4;
        px[o] = (sr / sw).round().clamp(0, 255);
        px[o + 1] = (sg / sw).round().clamp(0, 255);
        px[o + 2] = (sb / sw).round().clamp(0, 255);
      }
    }
  }

  static double _lensRadius(LensBlur l, ui.Size full) =>
      l.isOn ? l.amount / 100 * 0.02 * math.max(full.width, full.height) : 0;

  /// Only the lens blur reaches past a pixel here.
  @override
  int margin(EditSettings s, double scale, {required ui.Size fullSize}) {
    final r = _lensRadius(s.lensBlur, fullSize);
    return r > 0 ? r.ceil() + 1 : 0;
  }

  @override
  void clearCache() {}

  @override
  void dispose() {}
}

/// Measures the whole-photo values on [smallCopy] (about 512 px on the long
/// edge). The caller keeps ownership of [smallCopy].
///
/// Airlight as LightCraft computes it (`CL local.rs:870-886`, notes 8.4): the
/// dark channel (darkest linear channel) of a blur at 2 % of the long edge,
/// every 7th value, the 99.5th percentile, at least 0.05; 1.0 if empty.
Future<DevelopStats> measureStats(ui.Image smallCopy) async {
  final long = math.max(smallCopy.width, smallCopy.height);
  final blurred = await blurImage(smallCopy, math.max(0.02 * long, 1));
  final Uint8List px;
  try {
    px = await readRgba(blurred);
  } finally {
    blurred.dispose();
  }
  final dark = <double>[];
  for (var i = 0; i < px.length; i += 4 * 7) {
    final m = math.min(px[i], math.min(px[i + 1], px[i + 2]));
    dark.add(srgbToLinear(m / 255));
  }
  if (dark.isEmpty) return const DevelopStats(airlight: 1);
  dark.sort();
  final k = ((dark.length - 1) * 0.995).round();
  return DevelopStats(airlight: math.max(dark[k], 0.05));
}

/// An image from straight (not premultiplied) RGBA bytes.
Future<ui.Image> imageFromRgba(Uint8List rgba, int w, int h) async {
  final buf = await ui.ImmutableBuffer.fromUint8List(rgba);
  try {
    final desc = ui.ImageDescriptor.raw(
      buf,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    try {
      final codec = await desc.instantiateCodec();
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      desc.dispose();
    }
  } finally {
    buf.dispose();
  }
}

/// Straight RGBA bytes of [image].
Future<Uint8List> readRgba(ui.Image image) async {
  final bd = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  return bd!.buffer.asUint8List();
}

/// Draws a picture into a new w x h image and frees the picture.
Future<ui.Image> recordImage(
  int w,
  int h,
  void Function(ui.Canvas c) draw,
) async {
  final rec = ui.PictureRecorder();
  draw(ui.Canvas(rec));
  final pic = rec.endRecording();
  try {
    return await pic.toImage(w, h);
  } finally {
    pic.dispose();
  }
}

/// A new image with the same pixels as [src].
Future<ui.Image> copyImage(ui.Image src) => recordImage(
  src.width,
  src.height,
  (c) => c.drawImage(src, ui.Offset.zero, ui.Paint()),
);

/// [src] scaled to [w] x [h].
Future<ui.Image> scaleImage(ui.Image src, int w, int h) => recordImage(
  w,
  h,
  (c) => c.drawImageRect(
    src,
    ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  ),
);

/// A Gaussian blur of [src] at [sigma] px with clamped edges, on the encoded
/// values, through `ui.ImageFilter.blur` (no downscale: develop spike).
Future<ui.Image> blurImage(ui.Image src, double sigma) {
  final w = src.width.toDouble(), h = src.height.toDouble();
  return recordImage(src.width, src.height, (c) {
    c.saveLayer(
      ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: ui.TileMode.clamp,
        ),
    );
    c.drawImage(src, ui.Offset.zero, ui.Paint());
    c.restore();
  });
}
