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
  /// [maskSettings] and mixed back by the mask's coverage.
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
  /// texture and clarity reach a fraction of its long edge.
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

/// Global colour only, through [ColorPipeline] per pixel on the CPU, then
/// each mask's tone and colour deltas mixed in by its coverage
/// ([MaskRasterizer]). Effects and detail settings, global or in a mask, are
/// ignored. For tests and as a fake in later tasks.
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
    return imageFromRgba(px, src.width, src.height);
  }

  @override
  int margin(EditSettings s, double scale, {required ui.Size fullSize}) => 0;

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
