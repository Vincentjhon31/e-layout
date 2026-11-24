import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../codec/jpeg_encoder.dart';
import '../codec/png_encoder.dart';
import '../develop/photo_developer.dart';
import '../develop/profile_table.dart';
import '../develop/settings.dart';
import '../model/layout_doc.dart';
import '../render/layout_painter.dart';
import '../render/layout_prep.dart';
import '../render/photo_geometry.dart';

enum OutputFormat { jpeg, png }

class ExportSettings {
  const ExportSettings({
    this.format = OutputFormat.jpeg,
    this.quality = 92,
    this.suffix = '_PIO',
  });
  final OutputFormat format;
  final int quality;
  final String suffix;
}

class RenderedPhoto {
  const RenderedPhoto(this.bytes, this.width, this.height, this.ext);
  final Uint8List bytes;
  final int width, height;

  /// 'jpg' or 'png'.
  final String ext;
}

final RegExp _badChars = RegExp(r'[\\/:*?"<>|\u0000-\u001f]');
final RegExp _trailing = RegExp(r'[. ]+$');
final RegExp _extension = RegExp(r'\.[^.]+$');

String cleanSuffix(String text) =>
    text.replaceAll(_badChars, '').replaceAll(_trailing, '');

/// app.js stem(): the file name without its extension, plus the cleaned suffix.
String outputStem(String fileName, String suffix) =>
    fileName.replaceFirst(_extension, '') + cleanSuffix(suffix);

/// app.js uniqueName(): `a.jpg`, then `a (2).jpg`, and so on. Records the result.
String uniqueName(String stem, String ext, Set<String> usedLowercase) {
  var name = '$stem.$ext';
  for (var n = 2; usedLowercase.contains(name.toLowerCase()); n++) {
    name = '$stem ($n).$ext';
  }
  usedLowercase.add(name.toLowerCase());
  return name;
}

class _EncodeJob {
  const _EncodeJob(this.rgba, this.w, this.h, this.format, this.quality);
  final Uint8List rgba;
  final int w, h;
  final OutputFormat format;
  final int quality;
}

Uint8List _encode(_EncodeJob j) => j.format == OutputFormat.jpeg
    ? encodeJpeg(j.rgba, j.w, j.h, quality: j.quality)
    : encodePng(j.rgba, j.w, j.h);

/// Renders one photo with the layout on top at the photo's full pixel size, in
/// tiles so that a photo larger than the GPU's maximum texture is never shrunk.
class PhotoExporter {
  PhotoExporter({
    this.tileSize = 2048,
    @visibleForTesting this.forcePixelPath = false,
    this.developer,
  });
  final int tileSize;

  /// Test hook: always take the route used when the engine clamps big pictures.
  final bool forcePixelPath;

  /// Applies photo edits; null when editing is not available here.
  final PhotoDeveloper? developer;

  /// Renders [photoBytes] with the layout on top. With [edit] (and not
  /// neutral), each tile is cut from the upright photo with the developer's
  /// margin on every side, developed in whole-photo coordinates, cropped back
  /// and the layout drawn on top. Null or neutral edits give today's bytes.
  Future<RenderedPhoto> render(
    Uint8List photoBytes,
    LayoutDoc? doc,
    LayoutPrep? prep,
    ExportSettings settings, {
    EditSettings? edit,
    ProfileTable? profile,
  }) async {
    final e = edit == null || edit.isNeutral ? null : edit;
    final dev = developer;
    if (e != null && dev == null) {
      throw StateError('Photo editing is not available.');
    }
    final jpeg = settings.format == OutputFormat.jpeg;
    ui.Image? src;
    img.Image? pixels; // set when the engine could not decode at full size
    int pw, ph;

    final buffer = await ui.ImmutableBuffer.fromUint8List(photoBytes);
    try {
      final desc = await ui.ImageDescriptor.encoded(buffer);
      final codec = await desc.instantiateCodec();
      final frame = await codec.getNextFrame();
      src = frame.image;
      var clamped = false;
      try {
        clamped = src.width * src.height < desc.width * desc.height;
      } on UnsupportedError {
        // The website's engine cannot report the file's own size; its browser
        // decodes the picture at full size, so there is nothing to compare.
      }
      codec.dispose();
      desc.dispose();
      if (clamped || forcePixelPath) {
        src.dispose();
        src = null;
      }
    } finally {
      buffer.dispose();
    }
    if (src != null) {
      pw = src.width;
      ph = src.height;
    } else {
      final decoded = img.decodeImage(photoBytes);
      if (decoded == null) {
        throw const FormatException('This photo could not be read.');
      }
      pixels = img.bakeOrientation(decoded).convert(numChannels: 4);
      pw = pixels.width;
      ph = pixels.height;
    }

    final fullBytes = pixels?.getBytes(order: img.ChannelOrder.rgba);
    final g = photoGeometry(pw, ph, doc);
    final out = Uint8List(g.w * g.h * 4);
    try {
      // Edits are computed on the whole upright photo: scale 1, its full size,
      // and whole-photo values measured once on a small copy.
      final fullSize = ui.Size(pw.toDouble(), ph.toDouble());
      final margin = e == null ? 0 : dev!.margin(e, 1, fullSize: fullSize);
      final stats = e != null && e[Setting.dehaze] != 0
          ? await _measure(src, pixels)
          : null;
      // An edited tile is sent to the developer with its margin on every side,
      // so it steps by less than [tileSize] to keep the whole piece within it.
      // Phones on Impeller's OpenGL ES backend gave back empty (white) tiles
      // when a piece was over 2048 px on both sides. The step goes down to
      // 64 px, so a margin up to the developer's cap (960 px, kMaxMarginPx)
      // still fits a 2048 px tile.
      final step = e == null
          ? tileSize
          : math.max(math.min(64, tileSize ~/ 4), tileSize - 2 * margin);
      for (var ty = 0; ty < g.h; ty += step) {
        for (var tx = 0; tx < g.w; tx += step) {
          final tw = math.min(step, g.w - tx);
          final th = math.min(step, g.h - ty);
          final rec = ui.PictureRecorder();
          final canvas = ui.Canvas(rec);
          ui.Image? tileSrc;
          ui.Picture? pic;
          ui.Image? tile;
          try {
            if (e != null) {
              // The tile in the upright photo, with the margin, inside the photo.
              final px = g.cropX + tx, py = g.cropY + ty;
              final x0 = math.max(px - margin, 0),
                  y0 = math.max(py - margin, 0);
              final x1 = math.min(px + tw + margin, pw),
                  y1 = math.min(py + th + margin, ph);
              assert(
                x1 - x0 <= tileSize && y1 - y0 <= tileSize,
                'piece ${x1 - x0} x ${y1 - y0} is over the $tileSize px tile '
                '(margin $margin)',
              );
              final cut = src != null
                  ? await _cutImage(src, x0, y0, x1 - x0, y1 - y0)
                  : await _tileImage(
                      fullBytes!,
                      pw * 4,
                      x0,
                      y0,
                      x1 - x0,
                      y1 - y0,
                    );
              try {
                tileSrc = await dev!.develop(
                  cut,
                  e,
                  profile: profile,
                  origin: ui.Offset(x0.toDouble(), y0.toDouble()),
                  fullSize: fullSize,
                  stats: stats,
                );
              } finally {
                cut.dispose();
                // Tiles never share blurs; free them before the next one.
                dev!.clearCache();
              }
              if (jpeg) {
                canvas.drawRect(
                  ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
                  ui.Paint()..color = const ui.Color(0xFFFFFFFF),
                );
              }
              canvas.drawImage(
                tileSrc,
                ui.Offset((x0 - px).toDouble(), (y0 - py).toDouble()),
                ui.Paint(),
              );
              if (doc != null) {
                canvas.translate(-tx.toDouble(), -ty.toDouble());
                canvas.scale(g.s, g.s);
                drawLayout(canvas, doc, prep, g.frameH);
              }
            } else if (src != null) {
              canvas.translate(-tx.toDouble(), -ty.toDouble());
              if (jpeg) {
                // transparent photos would otherwise turn black
                canvas.drawRect(
                  ui.Rect.fromLTWH(0, 0, g.w.toDouble(), g.h.toDouble()),
                  ui.Paint()..color = const ui.Color(0xFFFFFFFF),
                );
              }
              paintComposite(canvas, src, 1, g, doc, prep, 1);
            } else {
              // The picture region of this tile, 1:1 (output is at photo scale).
              tileSrc = await _tileImage(
                fullBytes!,
                pw * 4,
                g.cropX + tx,
                g.cropY + ty,
                tw,
                th,
              );
              if (jpeg) {
                canvas.drawRect(
                  ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
                  ui.Paint()..color = const ui.Color(0xFFFFFFFF),
                );
              }
              canvas.drawImage(tileSrc, ui.Offset.zero, ui.Paint());
              if (doc != null) {
                canvas.translate(-tx.toDouble(), -ty.toDouble());
                canvas.scale(g.s, g.s);
                drawLayout(canvas, doc, prep, g.frameH);
              }
            }
            pic = rec.endRecording();
            tile = await pic.toImage(tw, th);
            final bd = await tile.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba,
            );
            final px = bd!.buffer.asUint8List();
            for (var y = 0; y < th; y++) {
              out.setRange(
                ((ty + y) * g.w + tx) * 4,
                ((ty + y) * g.w + tx + tw) * 4,
                px,
                y * tw * 4,
              );
            }
          } finally {
            tile?.dispose();
            pic?.dispose();
            tileSrc?.dispose();
          }
        }
      }
    } finally {
      src?.dispose();
      if (e != null) dev!.clearCache();
    }

    final bytes = await compute(
      _encode,
      _EncodeJob(out, g.w, g.h, settings.format, settings.quality),
    );
    return RenderedPhoto(bytes, g.w, g.h, jpeg ? 'jpg' : 'png');
  }

  /// A 1:1 copy of the region (x, y, w, h) of [src].
  Future<ui.Image> _cutImage(ui.Image src, int x, int y, int w, int h) =>
      recordImage(
        w,
        h,
        (c) => c.drawImageRect(
          src,
          ui.Rect.fromLTWH(
            x.toDouble(),
            y.toDouble(),
            w.toDouble(),
            h.toDouble(),
          ),
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint(),
        ),
      );

  /// Whole-photo values, measured on a copy of about 512 px on the long edge
  /// of the upright photo ([src], or [pixels] on the pixel path).
  Future<DevelopStats> _measure(ui.Image? src, img.Image? pixels) async {
    final w = src?.width ?? pixels!.width, h = src?.height ?? pixels!.height;
    final k = math.min(512 / math.max(w, h), 1.0);
    final sw = math.max((w * k).round(), 1), sh = math.max((h * k).round(), 1);
    final ui.Image small;
    if (src != null) {
      small = await scaleImage(src, sw, sh);
    } else {
      final resized = img.copyResize(
        pixels!,
        width: sw,
        height: sh,
        interpolation: img.Interpolation.average,
      );
      small = await imageFromRgba(
        resized.getBytes(order: img.ChannelOrder.rgba),
        sw,
        sh,
      );
    }
    try {
      return await measureStats(small);
    } finally {
      small.dispose();
    }
  }

  Future<ui.Image> _tileImage(
    Uint8List full,
    int stride,
    int x,
    int y,
    int w,
    int h,
  ) {
    final bytes = Uint8List(w * h * 4);
    for (var row = 0; row < h; row++) {
      final s = (y + row) * stride + x * 4;
      bytes.setRange(row * w * 4, (row + 1) * w * 4, full, s);
    }
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }
}
