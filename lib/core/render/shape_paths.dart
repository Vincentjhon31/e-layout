import 'dart:math' as math;
import 'dart:ui' as ui;

import '../model/layout_doc.dart';
import 'paint_utils.dart';

const double _rad = math.pi / 180;

ui.Path _poly(List<ui.Offset> pts) {
  final p = ui.Path();
  for (var i = 0; i < pts.length; i++) {
    if (i == 0) {
      p.moveTo(pts[i].dx, pts[i].dy);
    } else {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
  }
  p.close();
  return p;
}

/// Rounded rectangle path; the radius is clamped to half the shorter side.
ui.Path roundRectPath(double x, double y, double w, double h, double r) {
  final rr = math.max(0.0, math.min(r, math.min(w / 2, h / 2)));
  final p = ui.Path();
  if (rr == 0) {
    p.addRect(ui.Rect.fromLTWH(x, y, w, h));
  } else {
    p.addRRect(ui.RRect.fromRectXY(ui.Rect.fromLTWH(x, y, w, h), rr, rr));
  }
  return p;
}

/// Outline of a shape piece in its own 0..w / 0..h space.
ui.Path shapePath(LayoutElement el, double w, double h) {
  ui.Path ring(int n, double Function(int) radiusAt) {
    final pts = <ui.Offset>[];
    for (var i = 0; i < n; i++) {
      final a = (-90 + (i * 360) / n) * _rad;
      final r = radiusAt(i);
      pts.add(ui.Offset(
          w / 2 + (w / 2) * r * math.cos(a), h / 2 + (h / 2) * r * math.sin(a)));
    }
    return _poly(pts);
  }

  switch (el.shape) {
    case ShapeKind.ellipse:
      return ui.Path()..addOval(ui.Rect.fromLTWH(0, 0, w, h));
    case ShapeKind.triangle:
      return _poly([ui.Offset(w / 2, 0), ui.Offset(w, h), ui.Offset(0, h)]);
    case ShapeKind.diamond:
      return _poly([
        ui.Offset(w / 2, 0),
        ui.Offset(w, h / 2),
        ui.Offset(w / 2, h),
        ui.Offset(0, h / 2),
      ]);
    case ShapeKind.polygon:
      return ring(el.sides == 0 ? 6 : el.sides, (_) => 1);
    case ShapeKind.star:
      final inner = el.inner == 0 ? 0.45 : el.inner;
      return ring((el.points == 0 ? 5 : el.points) * 2, (i) => i.isOdd ? inner : 1);
    case ShapeKind.arrow:
      return _poly([
        ui.Offset(0, h * 0.32),
        ui.Offset(w * 0.62, h * 0.32),
        ui.Offset(w * 0.62, 0),
        ui.Offset(w, h / 2),
        ui.Offset(w * 0.62, h),
        ui.Offset(w * 0.62, h * 0.68),
        ui.Offset(0, h * 0.68),
      ]);
    case ShapeKind.torn:
      // A band with a ragged top edge, like torn paper.
      final rand = mulberry32(el.seed == 0 ? 7 : el.seed);
      final amp = el.rough * math.min(h * 0.45, 70);
      final steps = math.max(12, (w / 16).round());
      final p = ui.Path()..moveTo(0, amp * rand());
      for (var i = 1; i <= steps; i++) {
        final v = i.isOdd ? 0.55 + 0.45 * rand() : 0.35 * rand();
        p.lineTo(w * i / steps, amp * v);
      }
      p
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      return p;
    case ShapeKind.rect:
      return roundRectPath(0, 0, w, h, el.radius);
  }
}
