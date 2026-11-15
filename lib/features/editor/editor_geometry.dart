import 'dart:math' as math;
import 'dart:ui';

import '../../core/model/layout_doc.dart';
import '../../core/model/layout_ops.dart' as ops;
import '../../core/render/layout_painter.dart';

/// Distance of the turn handle from the box, in screen points (editor.js turnGap on touch).
const double kTurnGap = 34;

/// How far from a handle a finger still grabs it, in screen points.
const double kHandleReach = 22;

/// Snapping distance for edges and centres, in screen points.
const double kSnapDistance = 6;

/// Turning snaps to a multiple of [kAngleStep] when within [kAngleMagnet] degrees of it.
const double kAngleStep = 15;
const double kAngleMagnet = 4;

/// The four corners of a piece as drawn (rotation, tilt and flips included).
List<Offset> cornersOf(LayoutElement el, double frameH) {
  final b = ops.boxOf(el, frameH);
  final m = matrixOf(el, b);
  return [
    m.apply(Offset.zero),
    m.apply(Offset(b.width, 0)),
    m.apply(Offset(b.width, b.height)),
    m.apply(Offset(0, b.height)),
  ];
}

Rect _bounds(Iterable<Offset> pts) {
  var l = double.infinity, t = double.infinity, r = double.negativeInfinity, b = double.negativeInfinity;
  for (final p in pts) {
    l = math.min(l, p.dx);
    t = math.min(t, p.dy);
    r = math.max(r, p.dx);
    b = math.max(b, p.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}

/// The upright box around a piece as drawn.
Rect bboxOf(LayoutElement el, double frameH) => _bounds(cornersOf(el, frameH));

/// The upright box around several pieces as drawn.
Rect bboxOfAll(Iterable<LayoutElement> list, double frameH) =>
    _bounds([for (final el in list) ...cornersOf(el, frameH)]);

enum HandleKind { resize, rotate }

/// A handle on the selection. [at] is in design units; [hx]/[hy] are 0, 0.5 or 1
/// across the piece (or the box around several pieces).
class Handle {
  const Handle(this.kind, this.at, {this.hx = 0, this.hy = 0, this.from, this.multi = false});
  final HandleKind kind;
  final Offset at;
  final double hx, hy;

  /// Where the turn handle's stem starts.
  final Offset? from;
  final bool multi;
}

/// editor.js handlesOf(): corner (and edge) handles and a turn handle, here
/// below the box so a finger does not cover the piece.
List<Handle> handlesOf(LayoutElement el, double frameH, double zoom) {
  final b = ops.boxOf(el, frameH);
  final m = matrixOf(el, b);
  Offset at(double x, double y) => m.apply(Offset(x, y));
  final list = <Handle>[];
  const corners = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)];
  const edges = [(0.5, 0.0), (1.0, 0.5), (0.5, 1.0), (0.0, 0.5)];
  // Small pieces get corner handles only; long thin ones (lines) get handles on their ends.
  final wide = b.width * zoom >= 44;
  final tall = b.height * zoom >= 44;
  void add((double, double) h) =>
      list.add(Handle(HandleKind.resize, at(h.$1 * b.width, h.$2 * b.height), hx: h.$1, hy: h.$2));
  if (el.type == ElementType.text || wide == tall) corners.forEach(add);
  if (el.type != ElementType.text) {
    if (wide && tall) {
      edges.forEach(add);
    } else if (wide) {
      [(1.0, 0.5), (0.0, 0.5)].forEach(add);
    } else if (tall) {
      [(0.5, 0.0), (0.5, 1.0)].forEach(add);
    }
  }
  final bottom = at(b.width / 2, b.height);
  final centre = at(b.width / 2, b.height / 2);
  final v = bottom - centre;
  final len = v.distance == 0 ? 1.0 : v.distance;
  final gap = kTurnGap / zoom;
  list.add(Handle(HandleKind.rotate, bottom + v / len * gap, from: bottom));
  return list;
}

/// Several pieces (or a group): corners of the box around them and a turn handle below it.
List<Handle> multiHandles(List<LayoutElement> list, double frameH, double zoom) {
  final bb = bboxOfAll(list, frameH);
  final out = [
    Handle(HandleKind.resize, bb.topLeft, hx: 0, hy: 0, multi: true),
    Handle(HandleKind.resize, bb.topRight, hx: 1, hy: 0, multi: true),
    Handle(HandleKind.resize, bb.bottomRight, hx: 1, hy: 1, multi: true),
    Handle(HandleKind.resize, bb.bottomLeft, hx: 0, hy: 1, multi: true),
  ];
  final bottom = bb.bottomCenter;
  out.add(Handle(HandleKind.rotate, bottom + Offset(0, kTurnGap / zoom), from: bottom, multi: true));
  return out;
}

/// The handle under a finger at [p] (design units), if any.
Handle? handleAt(List<Handle> handles, Offset p, double zoom, {double reach = kHandleReach}) {
  Handle? best;
  var bestD = double.infinity;
  for (final h in handles) {
    final d = (h.at - p).distance * zoom;
    if (d <= reach && d < bestD) {
      best = h;
      bestD = d;
    }
  }
  return best;
}

/// editor.js elementAt(): the topmost piece under [p]. Hidden and locked
/// pieces are skipped (locked ones are picked from Layers).
LayoutElement? elementAtIn(LayoutDoc doc, Offset p, double frameH, double zoom, {double slop = 12}) {
  for (var i = doc.elements.length - 1; i >= 0; i--) {
    final el = doc.elements[i];
    if (!el.visible || el.locked) continue;
    final b = ops.boxOf(el, frameH);
    final inv = matrixOf(el, b).inverted();
    if (inv == null) continue;
    final q = inv.apply(p);
    final pad = slop / zoom;
    if (q.dx >= -pad && q.dx <= b.width + pad && q.dy >= -pad && q.dy <= b.height + pad) return el;
  }
  return null;
}

/// A thin guide line drawn while snapping: vertical at [x] or horizontal at [y].
class Guide {
  const Guide({this.x, this.y});
  final double? x, y;
}

/// editor.js moveDrag snapping: the shift that brings an edge or centre of
/// [bb] onto the frame's edges or centre, or onto another piece's.
({double dx, double dy, List<Guide> guides}) snapMove(
  Rect bb,
  Iterable<Rect> others,
  double frameW,
  double frameH,
  double zoom,
) {
  final xs = [0.0, frameW / 2, frameW];
  final ys = [0.0, frameH / 2, frameH];
  for (final o in others) {
    xs.addAll([o.left, o.center.dx, o.right]);
    ys.addAll([o.top, o.center.dy, o.bottom]);
  }
  final thr = kSnapDistance / zoom;
  (double, double)? best(List<double> vals, List<double> targets) {
    (double, double)? pick;
    for (final v in vals) {
      for (final t in targets) {
        if ((t - v).abs() <= thr && (pick == null || (t - v).abs() < pick.$1.abs())) pick = (t - v, t);
      }
    }
    return pick;
  }

  final sx = best([bb.left, bb.center.dx, bb.right], xs);
  final sy = best([bb.top, bb.center.dy, bb.bottom], ys);
  return (
    dx: sx?.$1 ?? 0,
    dy: sy?.$1 ?? 0,
    guides: [
      if (sx != null) Guide(x: sx.$2),
      if (sy != null) Guide(y: sy.$2),
    ],
  );
}

/// Angles in -180..180.
double wrapDeg(double r) => (((r + 180) % 360) + 360) % 360 - 180;

/// Pulls an angle onto the nearest multiple of 15 degrees when it is close.
double snapAngle(double deg) {
  final near = (deg / kAngleStep).roundToDouble() * kAngleStep;
  return (deg - near).abs() <= kAngleMagnet ? near : deg;
}

double round1(double v) => (v * 10).roundToDouble() / 10;
