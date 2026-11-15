import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/model/layout_doc.dart';
import '../../core/render/layout_painter.dart';
import '../../core/render/sample_scene.dart';
import '../../ui/app_theme.dart';
import 'editor_controller.dart';
import 'editor_geometry.dart';

/// The drawing area of the editor: the layout over a preview, the selection
/// with its handles, and the touch gestures.
///
/// One finger drags a piece or a handle, or pans the view when it starts on
/// empty space. Two fingers pinch and pan. A tap on empty space deselects,
/// a double-tap on a text asks to edit it, a long press starts picking
/// several pieces.
class EditorCanvas extends StatefulWidget {
  const EditorCanvas({super.key, required this.controller, this.onEditText});

  final EditorController controller;
  final void Function(LayoutElement el)? onEditText;

  @override
  State<EditorCanvas> createState() => EditorCanvasState();
}

enum _Mode { idle, drag, pan, pinch, ignore }

class EditorCanvasState extends State<EditorCanvas> {
  // Room around the frame: the top has the shape control, the bottom the turn handle.
  static const EdgeInsets _room = EdgeInsets.fromLTRB(20, 60, 20, 56);
  static const double _tapSlop = 8;

  Size _area = Size.zero;
  double _userZoom = 1;
  Offset _pan = Offset.zero;

  final Map<int, Offset> _pointers = {};
  _Mode _mode = _Mode.idle;
  Offset _downAt = Offset.zero;
  bool _moved = false;
  DownTarget _target = DownTarget.nothing;
  String? _downEl;
  Timer? _longPress;
  String? _lastTapEl;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Pinch start.
  double _pinchDist = 1;
  double _pinchZoom = 1;
  Offset _pinchDesign = Offset.zero;

  EditorController get c => widget.controller;

  double get _frameW => c.doc.width;
  double get _frameH => c.frameH;

  double get _baseScale {
    final w = math.max(1.0, _area.width - _room.horizontal);
    final h = math.max(1.0, _area.height - _room.vertical);
    return math.min(w / _frameW, h / _frameH);
  }

  double get scale => _baseScale * _userZoom;

  Offset get _origin {
    final room = Rect.fromLTRB(_room.left, _room.top, _area.width - _room.right, _area.height - _room.bottom);
    final s = scale;
    return room.center - Offset(_frameW * s / 2, _frameH * s / 2) + _pan;
  }

  /// Design units to screen points (relative to this widget).
  Offset toScreen(Offset design) {
    final box = context.findRenderObject() as RenderBox?;
    final o = toLocalPoint(design);
    return box == null ? o : box.localToGlobal(o);
  }

  /// Design units to points inside this widget.
  Offset toLocalPoint(Offset design) => _origin + design * scale;

  Offset toDesign(Offset local) => (local - _origin) / scale;

  @override
  void dispose() {
    _longPress?.cancel();
    super.dispose();
  }

  Offset _local(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  void _down(PointerDownEvent e) {
    final local = _local(e.position);
    _pointers[e.pointer] = local;
    _longPress?.cancel();
    if (_pointers.length == 1) {
      c.zoom = scale;
      _downAt = local;
      _moved = false;
      final p = toDesign(local);
      _target = c.beginDrag(p);
      if (_target == DownTarget.nothing) {
        _mode = _Mode.pan;
        _downEl = null;
      } else {
        _mode = _Mode.drag;
        _downEl = _target == DownTarget.piece ? c.elementAt(p)?.id : null;
        if (_downEl != null) {
          _longPress = Timer(const Duration(milliseconds: 500), _onLongPress);
        }
      }
    } else if (_pointers.length == 2) {
      if (_mode == _Mode.drag) c.cancelDrag();
      _mode = _Mode.pinch;
      final pts = _pointers.values.toList();
      _pinchDist = math.max(1, (pts[0] - pts[1]).distance);
      _pinchZoom = _userZoom;
      _pinchDesign = toDesign((pts[0] + pts[1]) / 2);
    } else {
      _mode = _Mode.ignore;
    }
  }

  void _onLongPress() {
    if (_mode != _Mode.drag || _moved || _downEl == null) return;
    final el = c.byId(_downEl);
    if (el == null) return;
    HapticFeedback.mediumImpact();
    c.startPicking(el);
    _downEl = null;
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    final local = _local(e.position);
    final before = _pointers[e.pointer]!;
    _pointers[e.pointer] = local;
    switch (_mode) {
      case _Mode.drag:
        if (!_moved && (local - _downAt).distance > _tapSlop) {
          _moved = true;
          _longPress?.cancel();
        }
        if (c.updateDrag(toDesign(local))) HapticFeedback.selectionClick();
      case _Mode.pan:
        if (!_moved && (local - _downAt).distance > _tapSlop) _moved = true;
        if (_moved) {
          setState(() => _pan += local - before);
        }
      case _Mode.pinch:
        if (_pointers.length < 2) return;
        final pts = _pointers.values.toList();
        final dist = math.max(1.0, (pts[0] - pts[1]).distance);
        final mid = (pts[0] + pts[1]) / 2;
        setState(() {
          _userZoom = (_pinchZoom * dist / _pinchDist).clamp(1.0, 8.0);
          _pan = Offset.zero;
          _pan = mid - toLocalPoint(_pinchDesign);
        });
        c.zoom = scale;
      case _Mode.idle:
      case _Mode.ignore:
        break;
    }
  }

  void _up(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    _longPress?.cancel();
    if (_mode == _Mode.pinch || _mode == _Mode.ignore) {
      if (_pointers.isEmpty) _mode = _Mode.idle;
      if (_mode == _Mode.pinch && _pointers.length == 1) _mode = _Mode.ignore;
      return;
    }
    if (_pointers.isNotEmpty) return;
    final mode = _mode;
    _mode = _Mode.idle;
    if (mode == _Mode.drag) {
      final tapped = !_moved;
      final el = _downEl == null ? null : c.byId(_downEl);
      c.endDrag();
      if (tapped && _target == DownTarget.piece) _tapOnPiece(c.byId(_downEl) ?? el);
    } else if (mode == _Mode.pan && !_moved) {
      _lastTapEl = null;
      if (c.picking) c.stopPicking();
      if (c.sel.isNotEmpty) c.select([]);
    }
    _downEl = null;
  }

  void _tapOnPiece(LayoutElement? el) {
    if (el == null) return;
    final now = DateTime.now();
    if (_lastTapEl == el.id && now.difference(_lastTapTime) < const Duration(milliseconds: 350)) {
      _lastTapEl = null;
      if (el.type == ElementType.text && !c.picking && widget.onEditText != null) widget.onEditText!(el);
      return;
    }
    _lastTapEl = el.id;
    _lastTapTime = now;
  }

  void _cancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    _longPress?.cancel();
    if (_mode == _Mode.drag) c.cancelDrag(keep: true);
    if (_pointers.isEmpty) _mode = _Mode.idle;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final dark = AppColors.brightnessOf(context) == Brightness.dark;
    return LayoutBuilder(
      builder: (context, box) {
        _area = box.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _cancel,
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              c.zoom = scale;
              return CustomPaint(
                size: box.biggest,
                painter: _CanvasPainter(
                  c: c,
                  origin: _origin,
                  scale: scale,
                  background: dark ? const Color(0xFF111113) : const Color(0xFFE4E7EC),
                  accent: colors.accent,
                  revision: c.revision,
                  selection: c.sel.join(','),
                  dragging: c.dragging,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.c,
    required this.origin,
    required this.scale,
    required this.background,
    required this.accent,
    required this.revision,
    required this.selection,
    required this.dragging,
  });

  final EditorController c;
  final Offset origin;
  final double scale;
  final Color background;
  final Color accent;
  final int revision;
  final String selection;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final doc = c.doc;
    final fw = doc.width, fh = c.frameH;
    final frame = Rect.fromLTWH(0, 0, fw, fh);

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale, scale);
    canvas.clipRect(frame);
    switch (c.preview) {
      case PreviewKind.sample:
        paintSampleScene(canvas, Size(fw, fh));
      case PreviewKind.none:
        paintChecker(canvas, Size(fw, fh), 24);
      case PreviewKind.photo:
        final img = c.photo;
        if (img == null) {
          paintSampleScene(canvas, Size(fw, fh));
        } else {
          canvas.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            frame,
            Paint()..filterQuality = FilterQuality.medium,
          );
        }
    }
    drawLayout(canvas, doc, c.prep, fh);
    canvas.restore();

    // Overlay in screen points, so lines stay thin at every zoom.
    Offset s(Offset p) => origin + p * scale;
    final screenFrame = Rect.fromLTWH(origin.dx, origin.dy, fw * scale, fh * scale);
    canvas.drawRect(
      screenFrame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x33000000),
    );

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = accent;
    for (final el in c.selection) {
      if (!el.visible) continue;
      final pts = [for (final p in cornersOf(el, fh)) s(p)];
      final path = Path()..addPolygon(pts, true);
      canvas.drawPath(path, line..color = el.locked ? accent.withValues(alpha: 0.5) : accent);
    }
    line.color = accent;

    if (c.selection.length > 1) {
      final bb = bboxOfAll(c.selection, fh);
      final r = Rect.fromPoints(s(bb.topLeft), s(bb.bottomRight));
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = accent.withValues(alpha: 0.6),
      );
    }

    final guide = Paint()
      ..strokeWidth = 1
      ..color = accent;
    for (final g in c.guides) {
      if (g.x != null) {
        final x = origin.dx + g.x! * scale;
        canvas.drawLine(Offset(x, screenFrame.top), Offset(x, screenFrame.bottom), guide);
      }
      if (g.y != null) {
        final y = origin.dy + g.y! * scale;
        canvas.drawLine(Offset(screenFrame.left, y), Offset(screenFrame.right, y), guide);
      }
    }

    for (final h in c.handles()) {
      final at = s(h.at);
      if (h.kind == HandleKind.rotate) {
        if (h.from != null) canvas.drawLine(s(h.from!), at, line);
        _dot(canvas, at, 11, true);
        final icon = Path()..addArc(Rect.fromCircle(center: at, radius: 4.2), -2.4, 4.6);
        canvas.drawPath(
          icon,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round
            ..color = accent,
        );
      } else {
        _dot(canvas, at, h.hx == 0.5 || h.hy == 0.5 ? 6 : 8, false);
      }
    }
  }

  void _dot(Canvas canvas, Offset at, double r, bool big) {
    canvas.drawCircle(at + const Offset(0, 1), r, Paint()..color = const Color(0x33000000));
    canvas.drawCircle(at, r, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => true;
}
