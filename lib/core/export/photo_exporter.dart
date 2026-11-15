import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../codec/jpeg_encoder.dart';
import '../codec/png_encoder.dart';
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
  PhotoExporter({this.tileSize = 2048, @visibleForTesting this.forcePixelPath = false});
  final int tileSize;

  /// Test hook: always take the route used when the engine clamps big pictures.
  final bool forcePixelPath;

  Future<RenderedPhoto> render(Uint8List photoBytes, LayoutDoc? doc, LayoutPrep? prep,
      ExportSettings settings) async {
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
      final clamped = src.width * src.height < desc.width * desc.height;
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
      if (decoded == null) throw const FormatException('This photo could not be read.');
      pixels = img.bakeOrientation(decoded).convert(numChannels: 4);
      pw = pixels.width;
      ph = pixels.height;
    }

    final fullBytes = pixels?.getBytes(order: img.ChannelOrder.rgba);
    final g = photoGeometry(pw, ph, doc);
    final out = Uint8List(g.w * g.h * 4);
    try {
      for (var ty = 0; ty < g.h; ty += tileSize) {
        for (var tx = 0; tx < g.w; tx += tileSize) {
          final tw = math.min(tileSize, g.w - tx);
          final th = math.min(tileSize, g.h - ty);
          final rec = ui.PictureRecorder();
          final canvas = ui.Canvas(rec);
          ui.Image? tileSrc;
          if (src != null) {
            canvas.translate(-tx.toDouble(), -ty.toDouble());
            if (jpeg) {
              // transparent photos would otherwise turn black
              canvas.drawRect(ui.Rect.fromLTWH(0, 0, g.w.toDouble(), g.h.toDouble()),
                  ui.Paint()..color = const ui.Color(0xFFFFFFFF));
            }
            paintComposite(canvas, src, 1, g, doc, prep, 1);
          } else {
            // The picture region of this tile, 1:1 (output is at photo scale).
            tileSrc = await _tileImage(
                fullBytes!, pw * 4, g.cropX + tx, g.cropY + ty, tw, th);
            if (jpeg) {
              canvas.drawRect(ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
                  ui.Paint()..color = const ui.Color(0xFFFFFFFF));
            }
            canvas.drawImage(tileSrc, ui.Offset.zero, ui.Paint());
            if (doc != null) {
              canvas.translate(-tx.toDouble(), -ty.toDouble());
              canvas.scale(g.s, g.s);
              drawLayout(canvas, doc, prep, g.frameH);
            }
          }
          final pic = rec.endRecording();
          final tile = await pic.toImage(tw, th);
          final bd = await tile.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
          tile.dispose();
          pic.dispose();
          tileSrc?.dispose();
          final px = bd!.buffer.asUint8List();
          for (var y = 0; y < th; y++) {
            out.setRange(((ty + y) * g.w + tx) * 4, ((ty + y) * g.w + tx + tw) * 4, px,
                y * tw * 4);
          }
        }
      }
    } finally {
      src?.dispose();
    }

    final bytes = await compute(_encode, _EncodeJob(out, g.w, g.h, settings.format, settings.quality));
    return RenderedPhoto(bytes, g.w, g.h, jpeg ? 'jpg' : 'png');
  }

  Future<ui.Image> _tileImage(
      Uint8List full, int stride, int x, int y, int w, int h) {
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
