import 'dart:math' as math;
import 'dart:ui' as ui;

import '../geometry/affine.dart';
import '../icons/icon_set.dart';
import '../model/layout_doc.dart';
import '../model/layout_ops.dart';
import 'layout_prep.dart';
import 'paint_utils.dart';
import 'shape_paths.dart';
import 'text_layout.dart';

const double _rad = math.pi / 180;

/// The element's transform, from its own 0..w / 0..h space to design units.
Affine matrixOf(LayoutElement el, ui.Rect box) {
  var m = Affine.identity.translate(box.left + box.width / 2, box.top + box.height / 2);
  if (el.rotation != 0) m = m.rotateDeg(el.rotation);
  if (el.skewX != 0 || el.skewY != 0) {
    m = m.multiply(Affine(1, math.tan(el.skewY * _rad), math.tan(el.skewX * _rad), 1, 0, 0));
  }
  if (el.flipX || el.flipY) m = m.scale(el.flipX ? -1 : 1, el.flipY ? -1 : 1);
  return m.translate(-box.width / 2, -box.height / 2);
}

/// What every drawing call of one element shares.
class _ElState {
  _ElState(this.el, this.matrix)
      : blend = blendOf(el.blend),
        filter = cssFilter(el.effects);
  final LayoutElement el;
  final Affine matrix;
  final ui.BlendMode blend;
  final ui.ImageFilter? filter;
  bool get shadowOn => el.shadow.on && el.shadow.alpha > 0;
}

/// Canvas 2D applies alpha, blend mode, filter and shadow to each drawing call, so
/// every call of an element goes through here. [drawLocal] paints at full alpha in
/// the element's own space.
void _emit(ui.Canvas c, _ElState s, bool castShadow, void Function(ui.Canvas) drawLocal) {
  final el = s.el;
  if (castShadow && s.shadowOn) {
    final sh = el.shadow;
    final colour = ui.ColorFilter.mode(rgba(sh.color, sh.alpha), ui.BlendMode.srcIn);
    // Canvas 2D applies the piece's filter first and casts the shadow from the
    // filtered result, so a blurred piece has a blurred shadow.
    ui.ImageFilter shape = colour;
    if (sh.blur > 0) {
      shape = ui.ImageFilter.compose(
          outer: colour,
          inner: ui.ImageFilter.blur(
              sigmaX: sh.blur / 2, sigmaY: sh.blur / 2, tileMode: ui.TileMode.decal));
    }
    final paint = ui.Paint()
      ..blendMode = s.blend
      ..color = ui.Color.fromRGBO(0, 0, 0, el.opacity)
      ..imageFilter = s.filter == null
          ? shape
          : ui.ImageFilter.compose(outer: shape, inner: s.filter!);
    c.saveLayer(null, paint);
    c.translate(sh.x, sh.y);
    c.transform(s.matrix.toMatrix4());
    drawLocal(c);
    c.restore();
  }
  final needsLayer = el.opacity < 1 || s.blend != ui.BlendMode.srcOver || s.filter != null;
  if (needsLayer) {
    final p = ui.Paint()
      ..blendMode = s.blend
      ..color = ui.Color.fromRGBO(0, 0, 0, el.opacity);
    if (s.filter != null) p.imageFilter = s.filter;
    c.saveLayer(null, p);
  }
  c.save();
  c.transform(s.matrix.toMatrix4());
  drawLocal(c);
  c.restore();
  if (needsLayer) c.restore();
}

ui.Paint _fillPaint(Fill fill, double w, double h) {
  final p = ui.Paint()..style = ui.PaintingStyle.fill..isAntiAlias = true;
  final sh = fillShader(fill, w, h);
  if (sh != null) {
    p.shader = sh;
  } else {
    p.color = rgba(fill.color, fill.alpha);
  }
  return p;
}

bool _hasFill(Fill f) => f.type != FillType.none;

ui.Paint _strokePaint(double width, String color, double alpha,
    {ui.StrokeJoin join = ui.StrokeJoin.round, ui.StrokeCap cap = ui.StrokeCap.butt}) {
  return ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = join
    ..strokeCap = cap
    ..isAntiAlias = true
    ..color = rgba(color, alpha);
}

void _drawShape(ui.Canvas c, _ElState s, ui.Rect box) {
  final el = s.el;
  final path = shapePath(el, box.width, box.height);
  var shadow = true;
  if (_hasFill(el.fill)) {
    final paint = _fillPaint(el.fill, box.width, box.height);
    _emit(c, s, shadow, (cv) => cv.drawPath(path, paint));
    shadow = false;
  }
  if (el.stroke.width > 0) {
    final paint = _strokePaint(el.stroke.width, el.stroke.color, el.stroke.alpha);
    _emit(c, s, shadow, (cv) => cv.drawPath(path, paint));
  }
}

void _drawImage(ui.Canvas c, _ElState s, ui.Rect box, ui.Image? bmp) {
  if (bmp == null) return;
  final el = s.el;
  final w = box.width, h = box.height;
  final clip = roundRectPath(0, 0, w, h, el.radius);
  double dx = 0, dy = 0, dw = w, dh = h;
  var clipped = el.radius > 0;
  final bw = bmp.width.toDouble(), bh = bmp.height.toDouble();
  if (el.fit == ImageFit.contain) {
    final k = math.min(w / bw, h / bh);
    dw = bw * k;
    dh = bh * k;
    dx = (w - dw) / 2;
    dy = (h - dh) / 2;
  } else if (el.fit == ImageFit.cover) {
    final k = math.max(w / bw, h / bh);
    dw = bw * k;
    dh = bh * k;
    dx = (w - dw) / 2;
    dy = (h - dh) / 2;
    clipped = true;
  }
  // Smaller than its pixels: medium; larger: high.
  final paint = ui.Paint()
    ..filterQuality = dw < bw ? ui.FilterQuality.medium : ui.FilterQuality.high
    ..isAntiAlias = true;
  final src = ui.Rect.fromLTWH(0, 0, bw, bh);
  final dst = ui.Rect.fromLTWH(dx, dy, dw, dh);
  if (clipped) {
    if (s.shadowOn) {
      // Casts the shadow; the picture then covers it (kept from the web version).
      final black = ui.Paint()..color = const ui.Color(0xFF000000);
      _emit(c, s, true, (cv) => cv.drawPath(clip, black));
    }
    _emit(c, s, false, (cv) {
      cv.save();
      cv.clipPath(clip);
      cv.drawImageRect(bmp, src, dst, paint);
      cv.restore();
    });
  } else {
    _emit(c, s, true, (cv) => cv.drawImageRect(bmp, src, dst, paint));
  }
  if (el.stroke.width > 0) {
    final sp = _strokePaint(el.stroke.width, el.stroke.color, el.stroke.alpha,
        join: ui.StrokeJoin.miter);
    _emit(c, s, false, (cv) => cv.drawPath(clip, sp));
  }
}

void _drawIcon(ui.Canvas c, _ElState s, ui.Rect box) {
  final el = s.el;
  final w = box.width, h = box.height;
  final bg = el.iconBg.shape != IconBgShape.none ? el.iconBg : null;
  var shadow = true;
  if (bg != null) {
    final p = bg.shape == IconBgShape.circle
        ? (ui.Path()..addOval(ui.Rect.fromLTWH(0, 0, w, h)))
        : roundRectPath(0, 0, w, h, math.min(w, h) * 0.22);
    final paint = ui.Paint()
      ..style = ui.PaintingStyle.fill
      ..isAntiAlias = true
      ..color = rgba(bg.color, bg.alpha);
    _emit(c, s, true, (cv) => cv.drawPath(p, paint));
    shadow = false;
    if (el.stroke.width > 0) {
      final sp = _strokePaint(el.stroke.width, el.stroke.color, el.stroke.alpha);
      _emit(c, s, false, (cv) => cv.drawPath(p, sp));
    }
  }
  final k = math.min(w, h) * (bg != null ? 0.6 : 1) / 24;
  ui.Shader? shader = fillShader(el.fill, 24, 24);
  final solid = el.fill.type == FillType.solid ? rgba(el.fill.color, el.fill.alpha) : const ui.Color(0xFF000000);
  final lw = el.lineWidth == 0 ? 2.0 : el.lineWidth;
  for (final part in IconSet.parts(el.icon)) {
    final paint = ui.Paint()..isAntiAlias = true;
    if (shader != null) {
      paint.shader = shader;
    } else {
      paint.color = solid;
    }
    if (part.fill) {
      paint.style = ui.PaintingStyle.fill;
    } else {
      paint
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = lw
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round;
    }
    _emit(c, s, shadow, (cv) {
      cv.save();
      cv.translate(w / 2 - 12 * k, h / 2 - 12 * k);
      cv.scale(k, k);
      cv.drawPath(part.path, paint);
      cv.restore();
    });
  }
}

void _drawText(ui.Canvas c, _ElState s, ui.Rect box) {
  final el = s.el;
  final L = layoutText(el);
  final pos = <(String, double, double)>[];
  for (var i = 0; i < L.lines.length; i++) {
    final free = box.width - L.widths[i];
    final x = el.align == TextAlignH.center ? free / 2 : el.align == TextAlignH.right ? free : 0.0;
    pos.add((L.lines[i], x, i * L.lh + (L.lh - (L.asc + L.desc)) / 2 + L.asc));
  }
  void paintLines(ui.Canvas cv, ui.Paint fg) {
    for (final (line, x, y) in pos) {
      if (line.isEmpty) continue;
      final p = buildLine(el, line, foreground: fg);
      final base = p.computeLineMetrics().first.baseline;
      cv.drawParagraph(p, ui.Offset(x, y - base));
      p.dispose();
    }
  }

  var shadow = true;
  if (el.stroke.width > 0) {
    final fg = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = el.stroke.width * 2
      ..strokeJoin = ui.StrokeJoin.round
      ..color = rgba(el.stroke.color, el.stroke.alpha);
    _emit(c, s, shadow, (cv) => paintLines(cv, fg));
    shadow = false;
  }
  if (_hasFill(el.fill)) {
    final fg = _fillPaint(el.fill, box.width, box.height);
    _emit(c, s, shadow, (cv) => paintLines(cv, fg));
  }
}

void drawElement(ui.Canvas canvas, LayoutElement el, LayoutPrep? prep, double frameH) {
  final box = boxOf(el, frameH);
  if (box.width <= 0 || box.height <= 0) return;
  final s = _ElState(el, matrixOf(el, box));
  switch (el.type) {
    case ElementType.text:
      _drawText(canvas, s, box);
    case ElementType.shape:
      _drawShape(canvas, s, box);
    case ElementType.image:
      _drawImage(canvas, s, box, prep?.bitmaps[el.asset]);
    case ElementType.icon:
      _drawIcon(canvas, s, box);
  }
}

/// Draws every visible piece. The canvas must already be scaled so that 1 unit
/// is 1 design unit.
void drawLayout(ui.Canvas canvas, LayoutDoc doc, LayoutPrep? prep, double frameH) {
  for (final el in doc.elements) {
    if (el.visible) drawElement(canvas, el, prep, frameH);
  }
}
