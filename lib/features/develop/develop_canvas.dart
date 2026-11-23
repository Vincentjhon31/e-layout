import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../../core/develop/photo_developer.dart';
import '../../core/develop/profile_table.dart';
import '../../core/develop/settings.dart';
import '../../core/model/layout_doc.dart';
import '../../core/render/layout_painter.dart';
import '../../core/render/layout_prep.dart';
import '../../core/render/photo_geometry.dart';
import '../../ui/app_theme.dart';
import '../home/home_controller.dart';
import '../viewer/photo_viewer.dart' show decodeScaled, kViewerEdge;
import 'photo_editor_controller.dart';

/// Wait this long after a zoom or pan before rendering at full size.
const Duration kFullSizeDelay = Duration(milliseconds: 150);

/// Decodes [bytes] at full size (upright).
Future<ui.Image> decodeFull(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final desc = await ui.ImageDescriptor.encoded(buffer);
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
    buffer.dispose();
  }
}

/// A part of the photo rendered from the full-size decode.
class _Tile {
  _Tile(
    this.image,
    this.photoId,
    this.outer,
    this.inner,
    this.scale,
    this.key,
    this.look,
  );
  final ui.Image image;
  final int photoId;

  /// What [image] covers and the part of it to show, in photo pixels.
  final Rect outer, inner;

  /// Image pixels per photo pixel.
  final double scale;
  final String key;

  /// The settings it was developed with.
  final String look;
}

/// The photo with its edits (and the layout), fitted in the box. Pinch, or
/// Ctrl+scroll, zooms up to 100 %; press and hold shows the original.
class DevelopCanvas extends StatefulWidget {
  const DevelopCanvas({super.key, required this.controller});

  final PhotoEditorController controller;

  @override
  State<DevelopCanvas> createState() => DevelopCanvasState();
}

class DevelopCanvasState extends State<DevelopCanvas> {
  PhotoEditorController get c => widget.controller;

  Size _view = Size.zero;
  double _dpr = 1;

  // Zoom: 1 is fitted. The photo point (geometry pixels) at the centre of
  // the box, null for the middle of the photo.
  double _z = 1;
  Offset? _focus;
  late int _photoId = c.photo.id;
  bool _layout = true;

  // The source decoded at kViewerEdge.
  int? _srcId;
  ui.Image? _src;

  // The whole photo at the fitted size, without edits.
  int? _fitId;
  String? _fitKey;
  ui.Image? _fit;

  // [_fit] developed; null with neutral settings (then [_fit] is shown).
  int? _shownId;
  String? _shownKey;
  ui.Image? _shown;

  // The full-size decode (one photo at a time) and the part rendered from it.
  int? _fullId;
  ui.Image? _full;
  _Tile? _tile;
  (int, DevelopStats)? _stats;

  bool _busy = false, _again = false, _scheduled = false, _disposed = false;
  Timer? _tileTimer;
  bool _tileWanted = false;

  // Scale gesture start.
  double _z0 = 1;
  Offset _p0 = Offset.zero;

  @override
  void initState() {
    super.initState();
    _layout = c.showLayout;
    c.addListener(_changed);
  }

  @override
  void didUpdateWidget(DevelopCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    c.removeListener(_changed);
    _tileTimer?.cancel();
    if (!_busy) _freeAll();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final id = c.photo.id;
    if (id != _photoId || c.showLayout != _layout) {
      _photoId = id;
      _layout = c.showLayout;
      _z = 1;
      _focus = null;
      _tileTimer?.cancel();
      _tileWanted = false;
    }
    setState(() {});
  }

  // ---------- for tests ----------

  /// Nothing is rendering or waiting to render.
  @visibleForTesting
  bool get idle => !_busy && !_scheduled && !(_tileTimer?.isActive ?? false);

  /// Screen pixels per photo pixel, in percent.
  @visibleForTesting
  int get zoomPercent {
    final p = c.photo;
    return (_scale(_geometry(p)) * _dpr * 100).round();
  }

  /// A part rendered from the full-size photo is on screen.
  @visibleForTesting
  bool get showsFullSize => _tileShown(c.photo) != null;

  // ---------- geometry ----------

  LayoutItem? get _item => c.showLayout ? c.home.current : null;

  PhotoGeometry _geometry(PhotoItem p) =>
      photoGeometry(p.width, p.height, _item?.doc);

  /// Space around the fitted photo.
  double get _inset => _view.width >= 600 ? 24 : 12;

  double _fitScale(PhotoGeometry g) {
    if (g.w <= 0 || g.h <= 0 || _view.isEmpty) return 1;
    final w = _view.width - 2 * _inset, h = _view.height - 2 * _inset;
    if (w <= 0 || h <= 0) {
      return math.min(_view.width / g.w, _view.height / g.h);
    }
    return math.min(w / g.w, h / g.h);
  }

  /// Zoom where one photo pixel is one screen pixel (at least fitted).
  double _maxZoom(PhotoGeometry g) => math.max(1, 1 / _dpr / _fitScale(g));

  /// Points per photo pixel.
  double _scale(PhotoGeometry g) {
    final fit = _fitScale(g);
    if (_z >= _maxZoom(g) - 1e-9) return math.max(fit, 1 / _dpr);
    return fit * _z;
  }

  /// Where the photo's top-left corner is drawn, on whole screen pixels.
  Offset _origin(PhotoGeometry g, double s) {
    final w = g.w * s, h = g.h * s;
    final f = _focus ?? Offset(g.w / 2, g.h / 2);
    double axis(double view, double size, double at) => size <= view
        ? (view - size) / 2
        : (view / 2 - at * s).clamp(view - size, 0.0);
    final x = axis(_view.width, w, f.dx), y = axis(_view.height, h, f.dy);
    return Offset(
      (x * _dpr).roundToDouble() / _dpr,
      (y * _dpr).roundToDouble() / _dpr,
    );
  }

  /// Keeps the photo point under [local] there while zooming to [z].
  void _zoomAround(Offset local, Offset photoPoint, double z) {
    final g = _geometry(c.photo);
    _z = z.clamp(1.0, _maxZoom(g));
    final s = _scale(g);
    _focus = photoPoint - (local - _view.center(Offset.zero)) / s;
    _clampFocus(g);
  }

  void _clampFocus(PhotoGeometry g) {
    final s = _scale(g);
    final o = _origin(g, s);
    _focus = Offset(
      (_view.width / 2 - o.dx) / s,
      (_view.height / 2 - o.dy) / s,
    );
  }

  Offset _toPhoto(Offset local) {
    final g = _geometry(c.photo);
    final s = _scale(g);
    return (local - _origin(g, s)) / s;
  }

  // ---------- gestures ----------

  void _scaleStart(ScaleStartDetails d) {
    _z0 = _z;
    _p0 = _toPhoto(d.localFocalPoint);
  }

  void _scaleUpdate(ScaleUpdateDetails d) {
    setState(() => _zoomAround(d.localFocalPoint, _p0, _z0 * d.scale));
    _waitForFullSize();
  }

  /// Mouse wheel: Ctrl zooms around the pointer, otherwise it pans.
  void _scroll(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final kb = HardwareKeyboard.instance;
    final delta = e.scrollDelta;
    if (kb.isControlPressed || kb.isMetaPressed) {
      final at = _toPhoto(e.localPosition);
      setState(
        () => _zoomAround(e.localPosition, at, _z * math.exp(-delta.dy / 300)),
      );
    } else {
      if (_z <= 1) return;
      final g = _geometry(c.photo);
      final s = _scale(g);
      final move = kb.isShiftPressed && delta.dx == 0
          ? Offset(delta.dy, 0)
          : delta;
      setState(() {
        _focus = (_focus ?? Offset(g.w / 2, g.h / 2)) + move / s;
        _clampFocus(g);
      });
    }
    _waitForFullSize();
  }

  /// Renders the visible part at full size once the view has been still a moment.
  void _waitForFullSize() {
    _tileTimer?.cancel();
    _tileWanted = false;
    _tileTimer = Timer(kFullSizeDelay, () {
      _tileWanted = true;
      _schedule();
    });
  }

  // ---------- rendering ----------

  void _schedule() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) _render();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// One render at a time; a request made meanwhile runs once it ends, with
  /// whatever is wanted by then.
  Future<void> _render() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        try {
          await _work();
        } catch (e) {
          debugPrint('The photo could not be drawn: $e');
        }
      } while (_again && !_disposed);
    } finally {
      _busy = false;
      if (_disposed) _freeAll();
    }
  }

  void _update() {
    if (!_disposed && mounted) setState(() {});
  }

  Future<void> _work() async {
    if (_disposed || _view.isEmpty) return;
    final p = c.photo;
    if (p.width <= 0 || p.height <= 0) return;

    // Another photo: its images go.
    if (_srcId != null && _srcId != p.id) {
      _src?.dispose();
      _src = null;
      _srcId = null;
    }
    if (_fullId != null && _fullId != p.id) _freeFull();
    if (_stats != null && _stats!.$1 != p.id) _stats = null;

    if (_srcId != p.id) {
      ui.Image? img;
      try {
        img = await decodeScaled(await photoBytes(p), kViewerEdge);
      } catch (e) {
        debugPrint('Could not open ${p.name}: $e');
      }
      if (_disposed) {
        img?.dispose();
        return;
      }
      _src = img;
      _srcId = p.id;
      if (c.photo.id != p.id) {
        _again = true;
        return;
      }
    }
    final base = _src ?? p.preview;
    if (base == null) return;

    // The whole photo at the size it is shown, without edits.
    final g = _geometry(p);
    final k = math.min(
      1.0,
      math.min(base.width / p.width, _fitScale(g) * _dpr),
    );
    final w = math.max(1, (p.width * k).round()),
        h = math.max(1, (p.height * k).round());
    final fitKey = '${p.id}|${w}x$h|${identityHashCode(base)}';
    if (_fitKey != fitKey) {
      final img = await scaleImage(base, w, h);
      if (_disposed) {
        img.dispose();
        return;
      }
      _fit?.dispose();
      _fit = img;
      _fitKey = fitKey;
      _fitId = p.id;
      _update();
      if (c.photo.id != p.id) {
        _again = true;
        return;
      }
    }
    final fit = _fit!;

    // Developed: quick tables while a slider moves, fine ones after.
    final s = c.settings;
    final profile = c.home.profileFor(s);
    final lut = c.changing ? 17 : 33;
    final look = _lookKey(s, profile);
    final devKey = '$fitKey|$look|${s.isNeutral ? 0 : lut}';
    if (_shownKey != devKey) {
      ui.Image? out;
      if (!s.isNeutral) {
        final stats = await _statsFor(p, s);
        out = await c.developer.develop(
          fit,
          s,
          profile: profile,
          scale: w / p.width,
          fullSize: Size(w.toDouble(), h.toDouble()),
          lutSize: lut,
          stats: stats,
        );
      }
      if (_disposed) {
        out?.dispose();
        return;
      }
      _shown?.dispose();
      _shown = out;
      _shownKey = devKey;
      _shownId = p.id;
      _update();
      if (c.photo.id != p.id ||
          _lookKey(c.settings, c.home.profileFor(c.settings)) != look) {
        _again = true;
        return;
      }
    }

    await _workTile(p, s, profile, look);
  }

  String _lookKey(EditSettings s, ProfileTable? profile) =>
      '${s.key}|${profile == null ? '' : identityHashCode(profile)}';

  /// Whole-photo values, measured once per photo, when Dehaze needs them.
  Future<DevelopStats?> _statsFor(PhotoItem p, EditSettings s) async {
    if (s[Setting.dehaze] == 0) return null;
    final have = _stats;
    if (have != null && have.$1 == p.id) return have.$2;
    final small = p.preview ?? _fit;
    if (small == null) return null;
    final stats = await measureStats(small);
    _stats = (p.id, stats);
    return stats;
  }

  /// The visible part of the photo (photo pixels) and the render scale, when
  /// the fitted copy is too coarse for this zoom.
  (Rect, double)? _fullSizeView(PhotoItem p) {
    final fit = _fit;
    if (fit == null || _fitId != p.id) return null;
    final g = _geometry(p);
    final s = _scale(g);
    final k = fit.width / p.width;
    final screen = s * _dpr;
    if (k >= 0.999 || screen <= k * 1.05) return null;
    final o = _origin(g, s);
    final x0 = math.max(0.0, -o.dx / s), y0 = math.max(0.0, -o.dy / s);
    final x1 = math.min(g.w.toDouble(), (_view.width - o.dx) / s);
    final y1 = math.min(g.h.toDouble(), (_view.height - o.dy) / s);
    if (x1 <= x0 || y1 <= y0) return null;
    final r = Rect.fromLTRB(
      (x0 + g.cropX).floorToDouble(),
      (y0 + g.cropY).floorToDouble(),
      math.min(p.width.toDouble(), (x1 + g.cropX).ceilToDouble()),
      math.min(p.height.toDouble(), (y1 + g.cropY).ceilToDouble()),
    );
    return (r, math.min(1.0, screen));
  }

  Future<void> _workTile(
    PhotoItem p,
    EditSettings s,
    ProfileTable? profile,
    String look,
  ) async {
    final want = _fullSizeView(p);
    if (want == null) {
      if (_tile != null) {
        _tile!.image.dispose();
        _tile = null;
        _update();
      }
      return;
    }
    if (!_tileWanted || c.comparing || c.changing) return;
    final (inner, ts) = want;
    final key = '${p.id}|$inner|$ts|$look';
    if (_tile?.key == key) return;

    if (_fullId != p.id) {
      _freeFull();
      final img = await decodeFull(await photoBytes(p));
      if (_disposed || c.photo.id != p.id) {
        img.dispose();
        _again = true;
        return;
      }
      _full = img;
      _fullId = p.id;
    }
    final full = _full!;
    final kf = full.width / p.width;
    final fullSize = Size(p.width * ts, p.height * ts);
    final m = s.isNeutral ? 0 : c.developer.margin(s, ts, fullSize: fullSize);
    final mp = (m / ts).ceilToDouble();
    final outer = Rect.fromLTRB(
      math.max(0, inner.left - mp),
      math.max(0, inner.top - mp),
      math.min(p.width.toDouble(), inner.right + mp),
      math.min(p.height.toDouble(), inner.bottom + mp),
    );
    final ow = math.max(1, (outer.width * ts).round()),
        oh = math.max(1, (outer.height * ts).round());
    final crop = await recordImage(
      ow,
      oh,
      (cv) => cv.drawImageRect(
        full,
        Rect.fromLTRB(
          outer.left * kf,
          outer.top * kf,
          outer.right * kf,
          outer.bottom * kf,
        ),
        Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()),
        Paint()
          ..filterQuality = ts < 1 || kf != 1
              ? FilterQuality.medium
              : FilterQuality.none,
      ),
    );
    var out = crop;
    if (!s.isNeutral) {
      try {
        final stats = await _statsFor(p, s);
        out = await c.developer.develop(
          crop,
          s,
          profile: profile,
          scale: ts,
          origin: Offset(outer.left * ts, outer.top * ts),
          fullSize: fullSize,
          lutSize: 33,
          stats: stats,
        );
      } finally {
        crop.dispose();
      }
    }
    if (_disposed) {
      out.dispose();
      return;
    }
    _tile?.image.dispose();
    _tile = _Tile(out, p.id, outer, inner, ts, key, look);
    _update();
    _again = true; // the view may have moved meanwhile
  }

  /// The tile, when it belongs on screen now.
  _Tile? _tileShown(PhotoItem p) {
    final t = _tile;
    if (t == null ||
        t.photoId != p.id ||
        c.comparing ||
        _fullSizeView(p) == null) {
      return null;
    }
    final s = c.settings;
    if (t.look != _lookKey(s, c.home.profileFor(s))) return null;
    return t;
  }

  void _freeFull() {
    _full?.dispose();
    _full = null;
    _fullId = null;
    _tile?.image.dispose();
    _tile = null;
  }

  void _freeAll() {
    _src?.dispose();
    _src = null;
    _fit?.dispose();
    _fit = null;
    _shown?.dispose();
    _shown = null;
    _freeFull();
  }

  // ---------- drawing ----------

  /// What to draw for [p]: the render, or Home's small copy while it comes.
  ui.Image? _imageFor(PhotoItem p) {
    final fit = _fitId == p.id ? _fit : null;
    if (c.comparing) return fit ?? p.preview;
    if (_shownId == p.id) return _shown ?? fit;
    return p.developed ?? p.preview;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    _dpr = MediaQuery.devicePixelRatioOf(context);
    final p = c.photo;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (size != _view) {
          _view = size;
          if (_focus != null) _clampFocus(_geometry(p));
        }
        _schedule();
        final img = _imageFor(p);
        final g = _geometry(p);
        final s = _scale(g);
        final item = _item;
        return Listener(
          onPointerSignal: _scroll,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _scaleStart,
            onScaleUpdate: _scaleUpdate,
            onScaleEnd: (_) => _waitForFullSize(),
            onLongPressStart: (_) => c.setComparing(true),
            onLongPressEnd: (_) => c.setComparing(false),
            onLongPressCancel: () => c.setComparing(false),
            child: RepaintBoundary(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: colors.page,
                      child: img == null
                          ? const SizedBox.expand()
                          : CustomPaint(
                              size: Size.infinite,
                              painter: _DevelopPainter(
                                image: img,
                                photoWidth: p.width,
                                g: g,
                                scale: s,
                                origin: _origin(g, s),
                                doc: item?.doc,
                                prep: item?.prep,
                                revision: item?.revision ?? 0,
                                tile: _tileShown(p),
                                dpr: _dpr,
                              ),
                            ),
                    ),
                  ),
                  if (c.comparing)
                    const Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(child: _OriginalLabel()),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Background of the small labels over the photo.
Color overlayPill(BuildContext context) => AppColors.of(context).isDark
    ? const Color(0xE63A3A3C)
    : const Color(0x99000000);

class _OriginalLabel extends StatelessWidget {
  const _OriginalLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: overlayPill(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'Original',
        style: AppText.captionStrong.copyWith(color: const Color(0xFFFFFFFF)),
      ),
    );
  }
}

class _DevelopPainter extends CustomPainter {
  _DevelopPainter({
    required this.image,
    required this.photoWidth,
    required this.g,
    required this.scale,
    required this.origin,
    required this.doc,
    required this.prep,
    required this.revision,
    required this.tile,
    required this.dpr,
  });

  final ui.Image image;
  final int photoWidth;
  final PhotoGeometry g;
  final double scale;
  final Offset origin;
  final LayoutDoc? doc;
  final LayoutPrep? prep;
  final int revision;
  final _Tile? tile;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final k = image.width / photoWidth;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(origin.dx, origin.dy);
    final t = tile;
    if (t == null) {
      paintComposite(canvas, image, k, g, doc, prep, scale);
    } else {
      // The photo, the full-size part over it, then the layout on top.
      paintComposite(canvas, image, k, g, null, null, scale);
      final src = Rect.fromLTWH(
        (t.inner.left - t.outer.left) * t.scale,
        (t.inner.top - t.outer.top) * t.scale,
        t.inner.width * t.scale,
        t.inner.height * t.scale,
      );
      final dst = Rect.fromLTWH(
        (t.inner.left - g.cropX) * scale,
        (t.inner.top - g.cropY) * scale,
        t.inner.width * scale,
        t.inner.height * scale,
      );
      final exact = (scale * dpr - t.scale).abs() < 1e-6;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, g.w * scale, g.h * scale));
      canvas.drawImageRect(
        t.image,
        src,
        dst,
        Paint()
          ..filterQuality = exact ? FilterQuality.none : FilterQuality.medium,
      );
      canvas.restore();
      final d = doc;
      if (d != null) {
        final px = g.s * scale;
        canvas.save();
        canvas.scale(px, px);
        drawLayout(canvas, d, prep, g.frameH);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DevelopPainter old) =>
      old.image != image ||
      old.scale != scale ||
      old.origin != origin ||
      old.doc != doc ||
      old.prep != prep ||
      old.revision != revision ||
      old.tile != tile ||
      old.g.w != g.w ||
      old.g.h != g.h;
}
