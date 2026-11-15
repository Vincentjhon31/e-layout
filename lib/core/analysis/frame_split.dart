import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/layout_doc.dart';
import '../model/layout_ops.dart';
import '../render/layout_prep.dart';

/// Straight RGBA pixels of [image] drawn scaled to w x h.
Future<Uint8List> _pixels(ui.Image image, int w, int h) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.low
        ..isAntiAlias = true);
  final pic = rec.endRecording();
  final scaled = await pic.toImage(w, h);
  final bd = await scaled.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  scaled.dispose();
  pic.dispose();
  return bd!.buffer.asUint8List();
}

class AlphaGuess {
  const AlphaGuess(this.hasAlpha, this.placement);
  final bool hasAlpha;

  /// 'frame', 'footer', 'header' or 'center'.
  final String placement;
}

/// Checks a picture for transparency and guesses where it belongs (imports).
Future<AlphaGuess> analyseAlpha(ui.Image image) async {
  final w = math.min(200, image.width);
  final h = math.max(2, (image.height * w / image.width).round());
  final px = await _pixels(image, w, h);
  var hasAlpha = false, topClear = true, bottomClear = true;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final a = px[(y * w + x) * 4 + 3];
      if (a < 250) hasAlpha = true;
      if (a > 8) {
        if (y < h * 0.45) {
          topClear = false;
        } else if (y >= h * 0.55) {
          bottomClear = false;
        }
      }
    }
  }
  var placement = 'frame';
  if (image.width / image.height >= 2.2 || (topClear && !bottomClear)) {
    placement = 'footer';
  } else if (bottomClear && !topClear) {
    placement = 'header';
  } else if (topClear && bottomClear) {
    placement = 'center';
  }
  return AlphaGuess(hasAlpha, placement);
}

class FramePartRect {
  const FramePartRect(this.edge, this.x, this.y, this.w, this.h);
  final String edge;
  final int x, y, w, h;
}

class FrameSplit {
  const FrameSplit(this.W, this.H, this.parts);
  final int W, H;
  final List<FramePartRect> parts;
}

/// Cuts a full-frame picture along its see-through middle into parts that can be
/// pinned to their own edges. Null when the middle is not see-through.
Future<FrameSplit?> splitFrame(ui.Image image) async {
  final W = image.width, H = image.height;
  final k = math.min(1.0, 640 / W);
  final w = math.max(1, (W * k).round());
  final h = math.max(1, (H * k).round());
  final px = await _pixels(image, w, h);
  bool on(int x, int y) => px[(y * w + x) * 4 + 3] > 12;
  final side = math.max(1, (w * 0.15).round());

  // The longest run of rows with nothing in the middle 70% of the width.
  ({int start, int end})? best;
  var start = -1;
  for (var y = 0; y <= h; y++) {
    var empty = y < h;
    for (var x = side; empty && x < w - side; x++) {
      if (on(x, y)) empty = false;
    }
    if (empty && start < 0) start = y;
    if (!empty && start >= 0) {
      if (best == null || y - start > best.end - best.start) {
        best = (start: start, end: y);
      }
      start = -1;
    }
  }
  if (best == null || best.end - best.start < h * 0.2) return null;
  var r0 = best.start, r1 = best.end;

  int reach(int y, bool left) {
    for (var i = side - 1; i >= 0; i--) {
      if (on(left ? i : w - 1 - i, y)) return i;
    }
    return -1;
  }

  var borderLeft = -1, borderRight = -1;
  for (var pass = 0; pass < 4; pass++) {
    var n0 = r0, n1 = r1;
    for (final left in [true, false]) {
      final ext = [for (var y = r0; y < r1; y++) reach(y, left)];
      final hits = ext.where((e) => e >= 0).toList()..sort();
      final border = hits.length >= ext.length * 0.8
          ? hits[(hits.length * 0.2).floor()]
          : -1;
      if (left) {
        borderLeft = border;
      } else {
        borderRight = border;
      }
      final middle = (r0 + r1) / 2;
      for (var i = 0; i < ext.length; i++) {
        if (ext[i] <= border + 1) continue;
        final y = r0 + i;
        if (y < middle) {
          n0 = math.max(n0, y + 1);
        } else {
          n1 = math.min(n1, y);
        }
      }
    }
    if (n0 == r0 && n1 == r1) break;
    r0 = n0;
    r1 = n1;
    if (r1 - r0 < h * 0.2) return null;
  }

  final y0 = math.min(H, (r0 / k).floor());
  final y1 = math.max(y0, math.min(H, (r1 / k).ceil()));
  final parts = <FramePartRect>[];
  if (y0 > 0) parts.add(FramePartRect('top', 0, 0, W, y0));
  if (y1 < H) parts.add(FramePartRect('bottom', 0, y1, W, H - y1));
  if (borderLeft >= 0) {
    parts.add(FramePartRect(
        'left', 0, y0, math.min(W, ((borderLeft + 1) / k).ceil()), y1 - y0));
  }
  if (borderRight >= 0) {
    final bw = math.min(W, ((borderRight + 1) / k).ceil());
    parts.add(FramePartRect('right', W - bw, y0, bw, y1 - y0));
  }
  return parts.isEmpty ? null : FrameSplit(W, H, parts);
}

/// Cuts the parts out of the picture as PNG bytes.
Future<List<FramePart>> cutParts(ui.Image image, FrameSplit split) async {
  final out = <FramePart>[];
  for (final p in split.parts) {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.drawImageRect(
        image,
        ui.Rect.fromLTWH(p.x.toDouble(), p.y.toDouble(), p.w.toDouble(), p.h.toDouble()),
        ui.Rect.fromLTWH(0, 0, p.w.toDouble(), p.h.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.none);
    final pic = rec.endRecording();
    final img = await pic.toImage(p.w, p.h);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    pic.dispose();
    out.add(FramePart(p.edge, p.x, p.y, p.w, p.h, bd!.buffer.asUint8List()));
  }
  return out;
}

class SoftPicture {
  const SoftPicture(this.name, this.natural, this.shown);
  final String name;
  final int natural;
  final int shown;
}

/// Pictures stretched past [limit] times their real size on a photo [photoW] pixels wide.
List<SoftPicture> softPictures(LayoutDoc doc, LayoutPrep prep, int photoW, double limit) {
  final s = photoW / doc.width;
  final out = <SoftPicture>[];
  for (final el in doc.elements) {
    if (!el.visible || el.type != ElementType.image) continue;
    final bmp = prep.bitmaps[el.asset];
    if (bmp == null) continue;
    final bw = bmp.width.toDouble(), bh = bmp.height.toDouble();
    final k = el.fit == ImageFit.cover
        ? math.max(el.w / bw, el.h / bh)
        : math.min(el.w / bw, el.h / bh);
    final shown = bw * k * s;
    if (shown / bw > limit) {
      out.add(SoftPicture(el.name.isEmpty ? 'Picture' : el.name, bmp.width, shown.round()));
    }
  }
  return out;
}

/// Whether a layout crops photos only because of a full-frame picture.
bool hasFramePicture(LayoutDoc doc) {
  final fh = frameHeight(doc);
  return doc.elements.any((el) {
    if (el.type != ElementType.image) return false;
    final b = boxOf(el, fh);
    return b.width >= doc.width * 0.9 && b.height >= fh * 0.9;
  });
}

/// Where a picture actually shows inside its box, in design units.
ui.Rect shownRect(LayoutElement el, ui.Rect box, ui.Image bmp) {
  if (el.fit != ImageFit.contain) return box;
  final k = math.min(box.width / bmp.width, box.height / bmp.height);
  final w = bmp.width * k, h = bmp.height * k;
  return ui.Rect.fromLTWH(
      box.left + (box.width - w) / 2, box.top + (box.height - h) / 2, w, h);
}

class FitResult {
  const FitResult(this.split, this.failed);

  /// Number of pictures split.
  final int split;

  /// The first picture that could not be split.
  final LayoutElement? failed;
}

/// Splits full-frame pictures into parts pinned to their edges. With [ids], only
/// those pictures; otherwise every picture that covers the frame.
Future<FitResult> fitAnyShape(LayoutDoc doc, LayoutPrep prep, double frameH,
    [List<String>? ids]) async {
  var split = 0;
  for (final el in List<LayoutElement>.of(doc.elements)) {
    if (el.type != ElementType.image || (ids != null && !ids.contains(el.id))) {
      continue;
    }
    final box = boxOf(el, frameH);
    if (ids == null && !(box.width >= doc.width * 0.9 && box.height >= frameH * 0.9)) {
      continue;
    }
    final bmp = prep.bitmaps[el.asset];
    final s = bmp != null &&
            el.fit != ImageFit.cover &&
            el.rotation == 0 &&
            el.skewX == 0 &&
            el.skewY == 0
        ? await splitFrame(bmp)
        : null;
    if (s == null) return FitResult(split, el);
    final parts = await cutParts(bmp!, s);
    final pieces =
        partsToElements(doc, el.name, parts, s.W, s.H, shownRect(el, box, bmp), frameH);
    for (final p in pieces) {
      p
        ..opacity = el.opacity
        ..blend = el.blend
        ..visible = el.visible
        ..effects = el.effects.clone();
    }
    for (final p in pieces) {
      // Equal parts share one asset (addAsset), so decode each only once.
      if (prep.bitmaps.containsKey(p.asset)) continue;
      prep.bitmaps[p.asset!] = await decodeImageBytes(doc.assets[p.asset]!.bytes);
    }
    doc.elements.replaceRange(doc.elements.indexOf(el), doc.elements.indexOf(el) + 1, pieces);
    split++;
  }
  return FitResult(split, null);
}
