import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;

import '../../../core/develop/settings.dart';
import '../../../ui/app_theme.dart';

/// Room kept round the plot so the end points are fully inside the square.
const double _pad = 14;

/// A finger can be this far from a point and still take it (a 44 pt target).
const double _hit = 22;

/// The tone curve as a square: tap on empty space adds a point on the curve,
/// drag moves a point, double-tap on a point removes it. The two end points
/// move up and down only and cannot be removed. Every finished change calls
/// [onChanged] once.
class CurveEditor extends StatefulWidget {
  const CurveEditor({
    super.key,
    required this.points,
    required this.onChanged,
    required this.size,
    required this.color,
  });

  final List<CurvePoint> points;
  final ValueChanged<List<CurvePoint>> onChanged;
  final double size;

  /// The curve's colour (the channel it edits).
  final Color color;

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  List<CurvePoint>? _live;
  int? _drag;
  Offset _lastDown = Offset.zero;

  List<CurvePoint> get _pts => _live ?? _sorted(widget.points);

  static List<CurvePoint> _sorted(List<CurvePoint> p) =>
      [...p]..sort((a, b) => a.x.compareTo(b.x));

  double get _span => widget.size - 2 * _pad;

  Offset _toScreen(CurvePoint p) =>
      Offset(_pad + p.x / 255 * _span, _pad + (1 - p.y / 255) * _span);

  (int, int) _toCurve(Offset o) => (
    ((o.dx - _pad) / _span * 255).round().clamp(0, 255),
    ((1 - (o.dy - _pad) / _span) * 255).round().clamp(0, 255),
  );

  /// The point nearest [o] within reach, or null.
  int? _pointAt(Offset o) {
    int? best;
    var bestD = _hit;
    final pts = _pts;
    for (var i = 0; i < pts.length; i++) {
      final d = (_toScreen(pts[i]) - o).distance;
      if (d <= bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  void _tap(Offset o) {
    if (_pointAt(o) != null) return;
    final pts = _pts;
    final x = _toCurve(o).$1;
    if (x < 1 || x > 254 || pts.any((p) => p.x == x)) return;
    final y = (_curveY(pts, x / 255) * 255).round().clamp(0, 255);
    widget.onChanged(_sorted([...pts, CurvePoint(x, y)]));
  }

  void _remove() {
    final pts = _pts;
    final i = _pointAt(_lastDown);
    if (i == null || i == 0 || i == pts.length - 1 || pts.length <= 2) return;
    widget.onChanged([...pts]..removeAt(i));
  }

  void _move(Offset o) {
    final i = _drag;
    if (i == null) return;
    final pts = [..._pts];
    final (cx, cy) = _toCurve(o);
    var x = pts[i].x;
    if (i > 0 && i < pts.length - 1) {
      x = cx.clamp(pts[i - 1].x + 1, pts[i + 1].x - 1);
    }
    pts[i] = CurvePoint(x, cy);
    setState(() => _live = pts);
  }

  void _end() {
    final live = _live;
    setState(() {
      _live = null;
      _drag = null;
    });
    if (live != null && !_same(live, widget.points)) widget.onChanged(live);
  }

  static bool _same(List<CurvePoint> a, List<CurvePoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        key: const ValueKey('curve-editor'),
        behavior: HitTestBehavior.opaque,
        // A drag takes the point under the finger when it went down, not
        // where the finger was once the drag began.
        dragStartBehavior: DragStartBehavior.down,
        onTapUp: (d) => _tap(d.localPosition),
        onDoubleTapDown: (d) => _lastDown = d.localPosition,
        onDoubleTap: _remove,
        onPanStart: (d) {
          _drag = _pointAt(d.localPosition);
          if (_drag != null) setState(() => _live = [..._pts]);
        },
        onPanUpdate: (d) => _move(d.localPosition),
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        child: CustomPaint(
          painter: _CurvePainter(
            points: _pts,
            color: widget.color,
            back: colors.raised,
            grid: colors.separator,
            handle: colors.card,
            active: _drag,
          ),
        ),
      ),
    );
  }
}

/// The curve through [pts] (sorted), at [x] 0..1, as 0..1: a monotone cubic.
double _curveY(List<CurvePoint> pts, double x) {
  final n = pts.length;
  if (n == 0) return x;
  if (n == 1) return pts.first.y / 255;
  final xs = [for (final p in pts) p.x / 255.0];
  final ys = [for (final p in pts) p.y / 255.0];
  if (x <= xs.first) return ys.first;
  if (x >= xs.last) return ys.last;
  final d = [
    for (var i = 0; i < n - 1; i++) (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]),
  ];
  final m = List<double>.filled(n, 0);
  m[0] = d.first;
  m[n - 1] = d.last;
  for (var i = 1; i < n - 1; i++) {
    m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
    } else {
      final r = math.sqrt(m[i] * m[i] + m[i + 1] * m[i + 1]);
      final lim = 3 * d[i].abs();
      if (r > lim) {
        m[i] *= lim / r;
        m[i + 1] *= lim / r;
      }
    }
  }
  var i = 0;
  while (i < n - 2 && x > xs[i + 1]) {
    i++;
  }
  final h = xs[i + 1] - xs[i];
  final t = (x - xs[i]) / h;
  final t2 = t * t, t3 = t2 * t;
  final y =
      (2 * t3 - 3 * t2 + 1) * ys[i] +
      (t3 - 2 * t2 + t) * h * m[i] +
      (-2 * t3 + 3 * t2) * ys[i + 1] +
      (t3 - t2) * h * m[i + 1];
  return y.clamp(0.0, 1.0);
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.points,
    required this.color,
    required this.back,
    required this.grid,
    required this.handle,
    required this.active,
  });

  final List<CurvePoint> points;
  final Color color, back, grid, handle;
  final int? active;

  @override
  void paint(Canvas canvas, Size size) {
    final span = size.width - 2 * _pad;
    Offset at(double x, double y) =>
        Offset(_pad + x * span, _pad + (1 - y) * span);
    final box = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(10)),
      Paint()..color = back,
    );
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final t = k / 4;
      canvas.drawLine(at(t, 0), at(t, 1), line);
      canvas.drawLine(at(0, t), at(1, t), line);
    }
    final start = at(0, _curveY(points, 0));
    final path = Path()..moveTo(start.dx, start.dy);
    for (var i = 1; i <= 64; i++) {
      final x = i / 64;
      final p = at(x, _curveY(points, x));
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < points.length; i++) {
      final c = at(points[i].x / 255, points[i].y / 255);
      final r = i == active ? 9.0 : 7.0;
      canvas.drawCircle(c, r, Paint()..color = handle);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.points != points ||
      old.color != color ||
      old.back != back ||
      old.active != active;
}
