import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/develop/masks.dart';
import 'photo_editor_controller.dart';

/// A handle's grab radius: a 44 pt target.
const double kHandleHitRadius = 22;

/// How far the rotation dot sits outside the radial's top dot.
const double kRotateGap = 44;

/// Brush points closer than this (normalised) to the last one are dropped.
const double kStrokeSpacing = 0.002;

/// The selected mask's area on the photo: red at 50 %.
const Color kMaskOverlayColour = Color(0x80FF3B30);

const String kStrokesFullMessage =
    'This mask has the most strokes it can hold.';
const String kColoursFullMessage = 'A colour range holds at most 5 colours.';

/// How the canvas shows the photo: screen point = origin + (photo pixel −
/// frame's top-left) × scale. Mask positions are normalised to the whole
/// photo ([photo] pixels); [frame] is the part of it shown (a layout may
/// crop it).
@immutable
class MaskView {
  const MaskView({
    required this.photo,
    required this.frame,
    required this.scale,
    required this.origin,
    this.reach = Rect.largest,
  });

  final Size photo;
  final Rect frame;

  /// Points per photo pixel.
  final double scale;

  /// Where the frame's top-left corner is drawn.
  final Offset origin;

  /// Where a handle can be grabbed: the canvas under the labels at its top.
  final Rect reach;

  /// Screen points per normalised unit, across and down.
  double get unitX => photo.width * scale;
  double get unitY => photo.height * scale;

  /// Screen points per unit of brush size (a fraction of the long edge).
  double get unitLong => math.max(photo.width, photo.height) * scale;

  /// The shown part of the photo, on screen.
  Rect get photoRect => origin & (frame.size * scale);

  Offset toScreen(double x, double y) =>
      origin +
      (Offset(x * photo.width, y * photo.height) - frame.topLeft) * scale;

  (double, double) toNorm(Offset p) {
    final q = (p - origin) / scale + frame.topLeft;
    return (q.dx / photo.width, q.dy / photo.height);
  }

  @override
  bool operator ==(Object other) =>
      other is MaskView &&
      other.photo == photo &&
      other.frame == frame &&
      other.scale == scale &&
      other.origin == origin &&
      other.reach == reach;
  @override
  int get hashCode => Object.hash(photo, frame, scale, origin, reach);
}

/// The grab points of the radial and linear shapes.
enum MaskHandle { centre, right, left, bottom, top, rotate, start, end, middle }

/// True when one-finger gestures on the photo edit [s].
bool editsOnPhoto(MaskShape s) =>
    s is RadialShape ||
    s is LinearShape ||
    s is BrushShape ||
    s is ColourRangeShape;

/// The radial's axes on screen: centre, unit vectors along its turned x and
/// y axes, and the half-axes in points.
(Offset, Offset, Offset, double, double) _radialAxes(
  RadialShape r,
  MaskView v,
) {
  final t = r.angle * math.pi / 180;
  final u = Offset(math.cos(t), math.sin(t));
  final w = Offset(-math.sin(t), math.cos(t));
  return (v.toScreen(r.cx, r.cy), u, w, r.rx * v.unitX, r.ry * v.unitY);
}

/// The rotation dot: outside the top of the oval, or, when that is out of
/// reach (under the labels or off the canvas), outside its bottom, right or
/// left, the first that is in reach.
Offset _rotateDot(
  Offset c,
  Offset u,
  Offset w,
  double a,
  double b,
  MaskView v,
) {
  final top = c - w * (b + kRotateGap);
  final inside = v.reach.deflate(kHandleHitRadius / 2);
  for (final p in [
    top,
    c + w * (b + kRotateGap),
    c + u * (a + kRotateGap),
    c - u * (a + kRotateGap),
  ]) {
    if (inside.contains(p)) return p;
  }
  return top;
}

/// The dots drawn for [s], by handle.
Map<MaskHandle, Offset> handlePoints(MaskShape s, MaskView v) {
  switch (s) {
    case RadialShape():
      final (c, u, w, a, b) = _radialAxes(s, v);
      return {
        MaskHandle.centre: c,
        MaskHandle.right: c + u * a,
        MaskHandle.left: c - u * a,
        MaskHandle.bottom: c + w * b,
        MaskHandle.top: c - w * b,
        MaskHandle.rotate: _rotateDot(c, u, w, a, b, v),
      };
    case LinearShape():
      final a = v.toScreen(s.x0, s.y0), b = v.toScreen(s.x1, s.y1);
      return {
        MaskHandle.start: a,
        MaskHandle.end: b,
        MaskHandle.middle: (a + b) / 2,
      };
    default:
      return const {};
  }
}

/// The unit vector along a linear gradient's lines (across its direction).
Offset _across(Offset a, Offset b) {
  final d = b - a;
  final len = d.distance;
  if (len < 1e-6) return const Offset(1, 0);
  return Offset(-d.dy / len, d.dx / len);
}

/// The handle of [s] under [p], if any: the nearest dot within
/// [kHandleHitRadius]; for a linear gradient, then the nearer of its lines.
MaskHandle? hitHandle(MaskShape s, MaskView v, Offset p) {
  MaskHandle? best;
  var dist = kHandleHitRadius;
  for (final e in handlePoints(s, v).entries) {
    final d = (e.value - p).distance;
    if (d <= dist) {
      dist = d;
      best = e.key;
    }
  }
  if (best != null || s is! LinearShape) return best;
  if (!v.photoRect.inflate(kHandleHitRadius).contains(p)) return null;
  final a = v.toScreen(s.x0, s.y0), b = v.toScreen(s.x1, s.y1);
  final along = b - a;
  final len = along.distance;
  if (len < 1e-6) return null;
  final n = along / len;
  // Distance from each line, measured along the direction.
  double off(Offset q) => ((p - q).dx * n.dx + (p - q).dy * n.dy).abs();
  final ds = off(a), de = off(b);
  if (math.min(ds, de) > kHandleHitRadius) return null;
  return ds <= de ? MaskHandle.start : MaskHandle.end;
}

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

/// [s] after handle [h] was dragged from screen point [from] to [to].
MaskShape dragShape(
  MaskShape s,
  MaskHandle h,
  MaskView v,
  Offset from,
  Offset to,
) {
  final d = to - from;
  final nx = d.dx / v.unitX, ny = d.dy / v.unitY;
  switch (s) {
    case RadialShape():
      var cx = s.cx, cy = s.cy, rx = s.rx, ry = s.ry, angle = s.angle;
      final (c, u, w, a, b) = _radialAxes(s, v);
      switch (h) {
        case MaskHandle.centre:
          cx += nx;
          cy += ny;
        case MaskHandle.right:
          rx = (a + _dot(d, u)) / v.unitX;
        case MaskHandle.left:
          rx = (a - _dot(d, u)) / v.unitX;
        case MaskHandle.bottom:
          ry = (b + _dot(d, w)) / v.unitY;
        case MaskHandle.top:
          ry = (b - _dot(d, w)) / v.unitY;
        case MaskHandle.rotate:
          final f = from - c, t = to - c;
          if (f.distance > 1e-6 && t.distance > 1e-6) {
            final turn = (t.direction - f.direction) * 180 / math.pi;
            angle = (angle + turn + 540) % 360 - 180;
          }
        default:
          return s;
      }
      return RadialShape(
        cx: cx,
        cy: cy,
        rx: rx,
        ry: ry,
        angle: angle,
        feather: s.feather,
        invert: s.invert,
      );
    case LinearShape():
      switch (h) {
        case MaskHandle.start:
          return LinearShape(s.x0 + nx, s.y0 + ny, s.x1, s.y1);
        case MaskHandle.end:
          return LinearShape(s.x0, s.y0, s.x1 + nx, s.y1 + ny);
        case MaskHandle.middle:
          // Both ends move together and stay on the photo.
          final mx = nx
              .clamp(-math.min(s.x0, s.x1), 1 - math.max(s.x0, s.x1))
              .toDouble();
          final my = ny
              .clamp(-math.min(s.y0, s.y1), 1 - math.max(s.y0, s.y1))
              .toDouble();
          return LinearShape(s.x0 + mx, s.y0 + my, s.x1 + mx, s.y1 + my);
        default:
          return s;
      }
    default:
      return s;
  }
}

double _round4(double v) => (v * 10000).round() / 10000;

/// A brush stroke's points as they come: normalised, clamped to the photo,
/// rounded as they are stored, and at least [kStrokeSpacing] apart.
class StrokeRecorder {
  final List<(double, double)> points = [];

  /// Adds (x, y); false when it was too close to the last point or the
  /// stroke is full.
  bool add(double x, double y) {
    if (points.length >= kMaxPoints) return false;
    final p = (_round4(x.clamp(0.0, 1.0)), _round4(y.clamp(0.0, 1.0)));
    if (points.isNotEmpty) {
      final q = points.last;
      final d = math.sqrt(math.pow(p.$1 - q.$1, 2) + math.pow(p.$2 - q.$2, 2));
      if (d < kStrokeSpacing - 1e-9) return false;
    }
    points.add(p);
    return true;
  }
}

/// One one-finger drag on the photo that edits the selected mask: a handle
/// of a radial or linear gradient, or a brush stroke. Each update is shown
/// at once ([PhotoEditorController.previewShape]); [end] keeps it as one
/// undo step, [cancel] drops it.
class MaskDrag {
  MaskDrag._(this._c, this._id, this._index, this._start, this._from);

  final PhotoEditorController _c;
  final String _id;
  final int _index;
  final MaskShape _start;
  final Offset _from;

  /// The handle being dragged (null for a brush stroke).
  MaskHandle? handle;

  /// The brush stroke being painted.
  StrokeRecorder? _stroke;
  BrushStroke? _brush;

  /// Where the finger is, on screen.
  Offset at = Offset.zero;

  /// False for a drag that does nothing (a full brush).
  bool live = true;

  bool get painting => _stroke != null;

  /// Starts a drag at [down] on the selected mask's selected shape, or
  /// returns null when the finger is on nothing to drag (the canvas then
  /// pans). A brush always paints; a full one says so in [toast].
  static MaskDrag? start(
    PhotoEditorController c,
    MaskView v,
    Offset down, {
    required void Function(String message) toast,
  }) {
    final m = c.selectedMask;
    if (m == null || m.components.isEmpty) return null;
    final i = c.selectedComponent;
    final s = m.components[i].shape;
    switch (s) {
      case RadialShape() || LinearShape():
        final h = hitHandle(s, v, down);
        if (h == null) return null;
        c.beginChange();
        return MaskDrag._(c, m.id, i, s, down)
          ..handle = h
          ..at = down;
      case BrushShape():
        final g = MaskDrag._(c, m.id, i, s, down)..at = down;
        if (s.strokes.length >= kMaxStrokes) {
          toast(kStrokesFullMessage);
          return g..live = false;
        }
        c.beginChange();
        g._stroke = StrokeRecorder();
        g._addPoint(v, down);
        return g;
      default:
        return null;
    }
  }

  void _addPoint(MaskView v, Offset p) {
    final (x, y) = v.toNorm(p);
    final st = _stroke!;
    if (!st.add(x, y) && _brush != null) return;
    final s = _start as BrushShape;
    _brush = BrushStroke(
      st.points,
      size: _c.brushSize,
      feather: _c.brushFeather,
      flow: _c.brushFlow,
      erase: _c.brushErase,
    );
    _c.previewShape(_id, _index, BrushShape([...s.strokes, _brush!]));
  }

  /// The finger is at [p].
  void update(MaskView v, Offset p) {
    at = p;
    if (!live) return;
    final h = handle;
    if (h != null) {
      _c.previewShape(_id, _index, dragShape(_start, h, v, _from, p));
    } else if (_stroke != null) {
      _addPoint(v, p);
    }
  }

  /// Keeps the drag as one undo step.
  Future<void> end() async {
    if (!live) return;
    live = false;
    await _c.endChange();
  }

  /// Drops the drag (a second finger came down: it is a pinch).
  void cancel() {
    if (!live) return;
    live = false;
    _c.cancelChange();
  }
}

/// A tap on the photo at [p]: a colour range adds the colour there
/// ([sample] reads it), a brush lays one dab.
Future<void> tapMask(
  PhotoEditorController c,
  MaskView v,
  Offset p, {
  required Future<(double, double, double)?> Function(double x, double y)
  sample,
  required void Function(String message) toast,
}) async {
  final m = c.selectedMask;
  if (m == null || m.components.isEmpty) return;
  final i = c.selectedComponent;
  final s = m.components[i].shape;
  final (x, y) = v.toNorm(p);
  if (x < 0 || x > 1 || y < 0 || y > 1) return;
  switch (s) {
    case ColourRangeShape():
      if (s.samples.length >= kMaxColourSamples) {
        toast(kColoursFullMessage);
        return;
      }
      final colour = await sample(x, y);
      if (colour == null) return;
      // The shape as it is now: it may have changed while the pixel was read.
      final now = c.selectedMask;
      if (now == null || now.id != m.id || i >= now.components.length) return;
      final cur = now.components[i].shape;
      if (cur is! ColourRangeShape) return;
      if (cur.samples.length >= kMaxColourSamples) {
        toast(kColoursFullMessage);
        return;
      }
      await c.updateShape(
        m.id,
        i,
        ColourRangeShape([...cur.samples, colour], refine: cur.refine),
      );
    case BrushShape():
      if (s.strokes.length >= kMaxStrokes) {
        toast(kStrokesFullMessage);
        return;
      }
      final st = StrokeRecorder()..add(x, y);
      await c.updateShape(
        m.id,
        i,
        BrushShape([
          ...s.strokes,
          BrushStroke(
            st.points,
            size: c.brushSize,
            feather: c.brushFeather,
            flow: c.brushFlow,
            erase: c.brushErase,
          ),
        ]),
      );
    default:
      break;
  }
}

/// The selected mask over the photo: its coverage in red, then the handles
/// of its radial or linear shape, and the brush while it paints.
class MaskHandlesPainter extends CustomPainter {
  MaskHandlesPainter({
    required this.view,
    required this.shape,
    required this.overlay,
    required this.active,
    required this.brushAt,
    required this.brushSize,
    required this.brushFeather,
    required this.accent,
  });

  final MaskView view;

  /// The shape whose handles show (null for none).
  final MaskShape? shape;

  /// The coverage of the whole photo, white with coverage in alpha.
  final ui.Image? overlay;
  final MaskHandle? active;

  /// The brush's centre on screen while it paints.
  final Offset? brushAt;
  final double brushSize, brushFeather;
  final Color accent;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _shade = Color(0x66000000);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final img = overlay;
    if (img != null) {
      final v = view;
      final kx = img.width / v.photo.width, ky = img.height / v.photo.height;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(
          v.frame.left * kx,
          v.frame.top * ky,
          v.frame.width * kx,
          v.frame.height * ky,
        ),
        v.photoRect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = const ColorFilter.mode(
            kMaskOverlayColour,
            BlendMode.srcIn,
          ),
      );
    }
    final s = shape;
    if (s is RadialShape) _radial(canvas, s);
    if (s is LinearShape) _linear(canvas, s);
    final b = brushAt;
    if (b != null) {
      final r = brushSize * view.unitLong;
      _ring(canvas, b, r, 1.5);
      final inner = r * (1 - brushFeather / 100);
      if (inner > 2 && inner < r - 2) _ring(canvas, b, inner, 1, faint: true);
    }
    canvas.restore();
  }

  /// A white line with a soft dark edge, so it reads on any photo.
  void _stroke(
    Canvas canvas,
    void Function(Paint p) draw,
    double width, {
    bool faint = false,
  }) {
    draw(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + (faint ? 1 : 2)
        ..color = faint ? const Color(0x1F000000) : _shade,
    );
    draw(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = faint ? const Color(0xB3FFFFFF) : _white,
    );
  }

  void _ring(
    Canvas canvas,
    Offset c,
    double r,
    double width, {
    bool faint = false,
  }) => _stroke(canvas, (p) => canvas.drawCircle(c, r, p), width, faint: faint);

  void _dot(Canvas canvas, Offset c, MaskHandle h, {double r = 6}) {
    final on = h == active;
    canvas.drawCircle(c, r + 1.5, Paint()..color = _shade);
    canvas.drawCircle(c, r, Paint()..color = on ? accent : _white);
    if (h == MaskHandle.centre || h == MaskHandle.middle) {
      canvas.drawCircle(c, r * 0.4, Paint()..color = on ? _white : accent);
    }
  }

  void _radial(Canvas canvas, RadialShape s) {
    final pts = handlePoints(s, view);
    final c = pts[MaskHandle.centre]!;
    final a = s.rx * view.unitX, b = s.ry * view.unitY;
    void oval(double k, double width, {bool faint = false}) {
      _stroke(
        canvas,
        (p) {
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(s.angle * math.pi / 180);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: 2 * a * k,
              height: 2 * b * k,
            ),
            p,
          );
          canvas.restore();
        },
        width,
        faint: faint,
      );
    }

    oval(1, 1.5);
    final inner = 1 - s.feather / 100;
    if (inner > 0.05 && inner < 0.98) oval(inner, 1, faint: true);
    // The rotation dot hangs off the nearest edge dot.
    final rot = pts[MaskHandle.rotate]!;
    var from = pts[MaskHandle.top]!;
    for (final h in [MaskHandle.bottom, MaskHandle.right, MaskHandle.left]) {
      final q = pts[h]!;
      if ((rot - q).distance < (rot - from).distance) from = q;
    }
    _stroke(canvas, (p) => canvas.drawLine(from, rot, p), 1);
    for (final h in [
      MaskHandle.right,
      MaskHandle.left,
      MaskHandle.bottom,
      MaskHandle.top,
      MaskHandle.rotate,
    ]) {
      _dot(canvas, pts[h]!, h, r: 5);
    }
    _dot(canvas, c, MaskHandle.centre, r: 8);
  }

  /// The segment of the line through [p] along [dir] inside [r], if any
  /// (Liang-Barsky).
  static (Offset, Offset)? _clip(Offset p, Offset dir, Rect r) {
    var t0 = -1e9, t1 = 1e9;
    bool edge(double q, double d, double lo, double hi) {
      if (d.abs() < 1e-12) return q >= lo && q <= hi;
      var a = (lo - q) / d, b = (hi - q) / d;
      if (a > b) (a, b) = (b, a);
      t0 = math.max(t0, a);
      t1 = math.min(t1, b);
      return t0 <= t1;
    }

    if (!edge(p.dx, dir.dx, r.left, r.right)) return null;
    if (!edge(p.dy, dir.dy, r.top, r.bottom)) return null;
    return (p + dir * t0, p + dir * t1);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    final d = b - a;
    final len = d.distance;
    if (len < 1) return;
    final n = d / len;
    for (var t = 0.0; t < len; t += 12) {
      canvas.drawLine(a + n * t, a + n * math.min(t + 7, len), p);
    }
  }

  void _linear(Canvas canvas, LinearShape s) {
    final pts = handlePoints(s, view);
    final a = pts[MaskHandle.start]!, b = pts[MaskHandle.end]!;
    final across = _across(a, b);
    final box = view.photoRect;
    final start = _clip(a, across, box);
    final end = _clip(b, across, box);
    if (start != null) {
      _stroke(canvas, (p) => canvas.drawLine(start.$1, start.$2, p), 1.5);
    }
    if (end != null) {
      _stroke(canvas, (p) => _dashed(canvas, end.$1, end.$2, p), 1.5);
    }
    _stroke(canvas, (p) => _dashed(canvas, a, b, p), 1, faint: true);
    _dot(canvas, a, MaskHandle.start);
    _dot(canvas, b, MaskHandle.end);
    _dot(canvas, pts[MaskHandle.middle]!, MaskHandle.middle, r: 8);
  }

  @override
  bool shouldRepaint(MaskHandlesPainter old) =>
      old.view != view ||
      old.shape != shape ||
      old.overlay != overlay ||
      old.active != active ||
      old.brushAt != brushAt ||
      old.brushSize != brushSize ||
      old.brushFeather != brushFeather ||
      old.accent != accent;
}
