import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../../core/develop/auto_masks.dart';
import '../../core/develop/mask_raster.dart';
import '../../core/develop/masks.dart';
import '../../core/develop/photo_developer.dart';
import '../../core/develop/profile_table.dart';
import '../../core/develop/settings.dart';
import '../../core/model/layout_doc.dart';
import '../../core/render/layout_painter.dart';
import '../../core/render/layout_prep.dart';
import '../../core/render/photo_geometry.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/toast.dart';
import '../home/home_controller.dart';
import '../viewer/photo_viewer.dart' show decodeScaled, kViewerEdge;
import 'mask_handles.dart';
import 'photo_editor_controller.dart';

/// Height of the band at the top of the canvas for the labels over it.
const double kCanvasTopBand = 52;

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
///
/// With the Masking panel open and a mask selected, one finger edits the
/// selected shape on the photo (a handle, a brush stroke, a colour sample);
/// two fingers still zoom and pan. The mask shows in red while "Show mask"
/// is on and while a handle or the brush is dragged.
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

  // The photo whose full-size decode failed (not tried again).
  int? _fullFailedId;
  _Tile? _tile;
  (int, DevelopStats)? _stats;

  bool _busy = false, _again = false, _scheduled = false, _disposed = false;
  Timer? _tileTimer;
  bool _tileWanted = false;

  // Scale gesture start.
  double _z0 = 1;
  Offset _p0 = Offset.zero;

  // Fingers down, and whether this touch has had two (then it only zooms
  // and pans until every finger is up). Where the first one came down.
  int _pointers = 0;
  bool _multi = false;
  Offset? _downAt;
  MaskDrag? _maskDrag;

  // The selected mask's coverage of the fitted photo, for the red overlay:
  // the photo and mask it shows, and its key (photo, image, components).
  Future<MaskRasterizer>? _rasterizer;
  ui.Image? _overlay;
  (int, String)? _overlayOf;
  String? _overlayKey;
  bool _overlayBusy = false, _overlayAgain = false, _overlayScheduled = false;

  // The pixels of the image colour samples are read from.
  ui.Image? _pixelsOf;
  Uint8List? _pixels;

  // Bumped each time the fitted photo is replaced: the overlay's key.
  int _fitSerial = 0;

  // The scale gesture under way belongs to the brush (the Listener paints).
  bool _scaleIgnored = false;

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
    // A drag still going is dropped once the tree is done.
    final drag = _maskDrag;
    if (drag != null) scheduleMicrotask(drag.cancel);
    _pixels = null;
    _pixelsOf = null;
    if (!_busy) _freeAll();
    if (!_overlayBusy) _freeOverlay();
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
      // Another photo: the drag ended with it (showPhoto kept it).
      _maskDrag = null;
      _pixels = null;
      _pixelsOf = null;
    }
    setState(() {});
  }

  // ---------- for tests ----------

  /// Nothing is rendering or waiting to render.
  @visibleForTesting
  bool get idle =>
      !_busy &&
      !_scheduled &&
      !(_tileTimer?.isActive ?? false) &&
      !_overlayBusy &&
      !_overlayScheduled;

  /// Screen pixels per photo pixel, in percent.
  @visibleForTesting
  int get zoomPercent {
    final p = c.photo;
    return (_scale(_geometry(p)) * _dpr * 100).round();
  }

  /// The full-size decode is held.
  @visibleForTesting
  bool get holdsFullSize => _full != null;

  /// A part rendered from the full-size photo is on screen.
  @visibleForTesting
  bool get showsFullSize => _tileShown(c.photo) != null;

  /// How the photo is shown now, for mask positions.
  @visibleForTesting
  MaskView get maskView {
    final p = c.photo;
    final g = _geometry(p);
    return _maskView(p, g, _scale(g));
  }

  /// The selected mask's coverage is on screen in red, or the lens blur's
  /// in-focus map of a subject or mask in green.
  @visibleForTesting
  bool get showsMaskOverlay => _overlayShown() != null;

  /// The lens blur's in-focus area is on screen in green (a subject or
  /// mask map, or the soft disc of a point).
  @visibleForTesting
  bool get showsFocusOverlay =>
      _lensShowsFocus && (_lensPoint || _overlayShown() != null);

  /// Zooms to [z] (1 is fitted) around the middle of the box.
  @visibleForTesting
  void zoomTo(double z) {
    final at = _view.center(Offset.zero);
    setState(() => _zoomAround(at, _toPhoto(at), z));
    _waitForFullSize();
  }

  // ---------- geometry ----------

  LayoutItem? get _item => c.showLayout ? c.home.current : null;

  PhotoGeometry _geometry(PhotoItem p) =>
      photoGeometry(p.width, p.height, _item?.doc);

  /// Space around the fitted photo.
  double get _inset => _view.width >= 600 ? 24 : 12;

  /// Where the fitted photo goes: inside the inset, under the band at the
  /// top that holds the "Layout" and "Original" labels.
  Rect get _fitArea {
    final r = Rect.fromLTRB(
      _inset,
      math.max(_inset, kCanvasTopBand),
      _view.width - _inset,
      _view.height - _inset,
    );
    return r.width > 0 && r.height > 0 ? r : Offset.zero & _view;
  }

  double _fitScale(PhotoGeometry g) {
    if (g.w <= 0 || g.h <= 0 || _view.isEmpty) return 1;
    final a = _fitArea;
    return math.min(a.width / g.w, a.height / g.h);
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
    final a = _fitArea;
    // Smaller than the box: centred in the fit area, kept inside the box.
    double axis(double view, double size, double at, double middle) =>
        size <= view
        ? (middle - size / 2).clamp(0.0, view - size)
        : (view / 2 - at * s).clamp(view - size, 0.0);
    final x = axis(_view.width, w, f.dx, a.center.dx);
    final y = axis(_view.height, h, f.dy, a.center.dy);
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

  MaskView _maskView(PhotoItem p, PhotoGeometry g, double s) => MaskView(
    photo: Size(p.width.toDouble(), p.height.toDouble()),
    frame: Rect.fromLTWH(
      g.cropX.toDouble(),
      g.cropY.toDouble(),
      g.w.toDouble(),
      g.h.toDouble(),
    ),
    scale: s,
    origin: _origin(g, s),
    reach: Rect.fromLTRB(0, kCanvasTopBand, _view.width, _view.height),
  );

  /// The shape one finger edits on the photo: the selected shape of the
  /// selected mask, with the Masking panel open, when it is one with
  /// handles, a brush or a colour range.
  MaskShape? get _maskTarget {
    if (c.panel != ToolPanel.masks || c.comparing) return null;
    final m = c.selectedMask;
    if (m == null || m.components.isEmpty) return null;
    final s = m.components[c.selectedComponent].shape;
    return editsOnPhoto(s) ? s : null;
  }

  /// The Lens blur panel is open on the photo with the edits showing.
  bool get _lensOn => c.panel == ToolPanel.blur && !c.comparing;

  /// A tap on the photo moves the focus point.
  bool get _lensPoint => _lensOn && c.lensBlur.focus == LensFocus.point;

  /// "Show focus" is on in the Lens blur panel.
  bool get _lensShowsFocus => _lensOn && c.showFocus;

  // ---------- gestures ----------

  void _pointerDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers == 1) {
      _downAt = e.localPosition;
      return;
    }
    // A second finger: a pinch, never a mask edit.
    _multi = true;
    final drag = _maskDrag;
    if (drag != null) {
      _maskDrag = null;
      drag.cancel();
      setState(() {});
    }
  }

  /// One finger on a brush paints from where it came down, on every move
  /// (the scale gesture only starts after its slop).
  void _pointerMove(PointerMoveEvent e) {
    if (_pointers != 1 || _multi) return;
    var drag = _maskDrag;
    if (drag == null) {
      final down = _downAt;
      if (down == null || _maskTarget is! BrushShape) return;
      drag = MaskDrag.start(c, maskView, down, toast: _toast);
      if (drag == null) return;
      _maskDrag = drag;
    } else if (!drag.isBrush) {
      return;
    }
    drag.update(maskView, e.localPosition);
    setState(() {});
  }

  void _pointerUp(PointerEvent e) {
    _pointers = math.max(0, _pointers - 1);
    if (_pointers > 0) return;
    final drag = _maskDrag;
    if (drag != null && drag.isBrush) {
      // The last finger is up: the stroke is one undo step.
      _maskDrag = null;
      if (e is PointerCancelEvent) {
        drag.cancel();
      } else {
        drag.end();
      }
      setState(() {});
    } else if (drag == null &&
        !_multi &&
        e is PointerUpEvent &&
        _downAt != null &&
        _maskTarget is BrushShape) {
      // A tap on a brush: a one-point stroke, a dab.
      MaskDrag.start(c, maskView, _downAt!, toast: _toast)?.end();
    }
    _multi = false;
    _downAt = null;
  }

  void _toast(String message) {
    if (mounted) showToast(context, message);
  }

  void _scaleStart(ScaleStartDetails d) {
    _scaleIgnored = false;
    final down = _downAt;
    if (d.pointerCount == 1 && !_multi) {
      // One finger on a brush: the Listener paints, nothing pans.
      if ((_maskDrag?.isBrush ?? false) || _maskTarget is BrushShape) {
        _scaleIgnored = true;
        return;
      }
    }
    if (d.pointerCount == 1 && !_multi && down != null && _maskTarget != null) {
      final drag = MaskDrag.start(c, maskView, down, toast: _toast);
      if (drag != null) {
        _maskDrag = drag;
        drag.update(maskView, d.localFocalPoint);
        setState(() {});
        return;
      }
    }
    _z0 = _z;
    _p0 = _toPhoto(d.localFocalPoint);
  }

  void _scaleUpdate(ScaleUpdateDetails d) {
    if (_scaleIgnored) return;
    final drag = _maskDrag;
    if (drag != null) {
      drag.update(maskView, d.localFocalPoint);
      setState(() {});
      return;
    }
    setState(() => _zoomAround(d.localFocalPoint, _p0, _z0 * d.scale));
    _waitForFullSize();
  }

  void _scaleEnd(ScaleEndDetails d) {
    if (_scaleIgnored) {
      _scaleIgnored = false;
      return;
    }
    final drag = _maskDrag;
    if (drag == null || drag.isBrush) {
      _waitForFullSize();
      return;
    }
    _maskDrag = null;
    // A finger came down meanwhile: the pinch takes over.
    if (d.pointerCount > 0) {
      drag.cancel();
    } else {
      drag.end();
    }
    setState(() {});
  }

  void _tapUp(TapUpDetails d) {
    if (_lensPoint) {
      // The tap, through the view, so zoom and pan do not matter; taps off
      // the photo are ignored.
      final (x, y) = maskView.toNorm(d.localPosition);
      if (x < 0 || x > 1 || y < 0 || y > 1) return;
      c.setLens(lensWith(c.lensBlur, fx: x, fy: y));
      return;
    }
    if (_maskTarget == null) return;
    tapMask(c, maskView, d.localPosition, sample: _sampleAt, toast: _toast);
  }

  /// The colour of the photo at normalised (x, y), 0 to 1 per channel.
  ///
  /// It is read from the photo without its edits, which is what the colour
  /// range compares against (MaskRasterizer reads the source), so a sample
  /// picked after a change of colour still selects the pixels tapped.
  Future<(double, double, double)?> _sampleAt(double x, double y) async {
    final p = c.photo;
    final img = (_fitId == p.id ? _fit : null) ?? p.preview;
    if (img == null) return null;
    if (!identical(_pixelsOf, img) || _pixels == null) {
      final px = await readRgba(img);
      _pixelsOf = img;
      _pixels = px;
    }
    final px = _pixels!;
    final w = img.width, h = img.height;
    if (px.length < w * h * 4) return null;
    final ix = (x * w).floor().clamp(0, w - 1);
    final iy = (y * h).floor().clamp(0, h - 1);
    final i = (iy * w + ix) * 4;
    return (px[i] / 255, px[i + 1] / 255, px[i + 2] / 255);
  }

  // ---------- the mask overlay ----------

  /// The selected mask, when its coverage should be on screen: "Show mask"
  /// is on, or a handle or the brush is being dragged.
  Mask? get _overlayMask {
    if (_lensShowsFocus) return _lensFocusMask;
    if (c.panel != ToolPanel.masks || c.comparing) return null;
    final m = c.selectedMask;
    if (m == null || m.components.isEmpty) return null;
    final dragging = _maskDrag?.live ?? false;
    return c.showOverlay || dragging ? m : null;
  }

  /// The mask whose coverage is the lens blur's in-focus area: the chosen
  /// mask, or the subject (also for a mask that is gone, as the render
  /// does). A point has no mask: its disc is drawn without an image.
  Mask? get _lensFocusMask {
    final l = c.lensBlur;
    if (l.focus == LensFocus.point) return null;
    if (l.focus == LensFocus.mask) {
      for (final m in c.masks) {
        if (m.id == l.maskId && m.components.isNotEmpty) {
          return Mask(id: m.id, components: m.components);
        }
      }
    }
    return Mask(
      id: 'lens subject',
      components: [MaskComponent(const SubjectShape())],
    );
  }

  /// The overlay image when it belongs on screen now.
  ui.Image? _overlayShown() {
    final m = _overlayMask;
    final o = _overlayOf;
    if (m == null || o == null) return null;
    return o.$1 == c.photo.id && o.$2 == m.id ? _overlay : null;
  }

  void _scheduleOverlay() {
    if (_overlayScheduled || _disposed) return;
    final m = _overlayMask;
    if (m == null && _overlay == null) return;
    _overlayScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayScheduled = false;
      if (!_disposed) _drawOverlay();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// One overlay render at a time, like [_render].
  Future<void> _drawOverlay() async {
    if (_overlayBusy) {
      _overlayAgain = true;
      return;
    }
    _overlayBusy = true;
    try {
      do {
        _overlayAgain = false;
        try {
          await _overlayWork();
        } catch (e) {
          debugPrint('The mask could not be drawn: $e');
          _overlayKey = null;
        }
      } while (_overlayAgain && !_disposed);
    } finally {
      _overlayBusy = false;
      if (_disposed) _freeOverlay();
    }
  }

  Future<void> _overlayWork() async {
    if (_disposed) return;
    final m = _overlayMask;
    final p = c.photo;
    final base = _fitId == p.id ? _fit : null;
    if (m == null) {
      // Not shown: the image goes.
      if (_overlay != null) {
        _freeOverlay();
        _update();
      }
      return;
    }
    if (base == null) return;
    // Only what the coverage depends on is in the key.
    final key =
        '${p.id}|$_fitSerial|${base.width}x${base.height}|'
        '${jsonEncode([for (final k in m.components) k.toJson()])}';
    if (key == _overlayKey) return;
    final raster = await (_rasterizer ??= MaskRasterizer.load());
    // The tile rule: at most 2048 px a side goes to the shader.
    final fitK = math.min(1.0, 2048 / math.max(base.width, base.height));
    final src = fitK < 1
        ? await scaleImage(
            base,
            math.max(1, (base.width * fitK).floor()),
            math.max(1, (base.height * fitK).floor()),
          )
        : base;
    final AutoMaps? auto;
    try {
      auto =
          m.components.any(
            (x) =>
                x.shape is SubjectShape ||
                x.shape is SkyShape ||
                x.shape is BackgroundShape,
          )
          ? await c.home.autoMapsFor(
              p,
              // Asked as if the mask changed the photo, so they are made.
              EditSettings.resolve([
                SettingsPatch(
                  masks: [
                    Mask(
                      id: m.id,
                      components: m.components,
                      adjust: const {Setting.exposure: 1},
                    ),
                  ],
                ),
              ]),
            )
          : null;
    } catch (e) {
      if (!identical(src, base)) src.dispose();
      rethrow;
    }
    final ui.Image cov;
    try {
      cov = await raster.coverage(
        Mask(id: m.id, components: m.components),
        src: src,
        origin: Offset.zero,
        fullSize: Size(src.width.toDouble(), src.height.toDouble()),
        scale: src.width / p.width,
        auto: auto,
      );
    } finally {
      auto?.dispose();
      if (!identical(src, base)) src.dispose();
    }
    if (_disposed) {
      cov.dispose();
      return;
    }
    _overlay?.dispose();
    _overlay = cov;
    _overlayOf = (p.id, m.id);
    _overlayKey = key;
    _update();
    // The mask may have moved on meanwhile.
    _overlayAgain = true;
  }

  void _freeOverlay() {
    _overlay?.dispose();
    _overlay = null;
    _overlayOf = null;
    _overlayKey = null;
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
      _fitSerial++;
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
        // Null when the maps could not be computed: the render is kept as
        // done all the same, so a failure is tried again only when the
        // settings change (Home does not cache the failure).
        final auto = await c.home.autoMapsFor(p, s);
        try {
          out = await c.developer.develop(
            fit,
            s,
            profile: profile,
            scale: w / p.width,
            fullSize: Size(w.toDouble(), h.toDouble()),
            lutSize: lut,
            stats: stats,
            auto: auto,
          );
        } finally {
          auto?.dispose();
        }
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

  /// Whole-photo values, measured once per photo, when Dehaze (global or in
  /// a mask) needs them.
  Future<DevelopStats?> _statsFor(PhotoItem p, EditSettings s) async {
    if (!needsStats(s)) return null;
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
    if (fit == null || _fitId != p.id || _fullFailedId == p.id) return null;
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
      // Back at a size the fitted copy covers: the full-size photo goes.
      if (_tile != null || _full != null) {
        _freeFull();
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
      final ui.Image img;
      try {
        img = await decodeFull(await photoBytes(p));
      } catch (e) {
        // Not tried again for this photo: the fitted copy stays enlarged.
        debugPrint('Could not open ${p.name} at full size: $e');
        _fullFailedId = p.id;
        return;
      }
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
        // As in _work: a tile made without maps that failed is kept too.
        final auto = await c.home.autoMapsFor(p, s);
        try {
          out = await c.developer.develop(
            crop,
            s,
            profile: profile,
            scale: ts,
            origin: Offset(outer.left * ts, outer.top * ts),
            fullSize: fullSize,
            lutSize: 33,
            stats: stats,
            auto: auto,
          );
        } finally {
          auto?.dispose();
        }
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
    // A render still in flight when the editor closed leaves blurs behind.
    c.developer.clearCache();
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
        _scheduleOverlay();
        final img = _imageFor(p);
        final g = _geometry(p);
        final s = _scale(g);
        final item = _item;
        final target = _maskTarget;
        final overlay = _overlayShown();
        final drag = _maskDrag;
        final painting = drag != null && drag.live && drag.painting;
        final lens = _lensOn;
        final lensPoint = _lensPoint;
        final tappable = target is ColourRangeShape || lensPoint;
        return Listener(
          onPointerSignal: _scroll,
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          onPointerCancel: _pointerUp,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: tappable ? _tapUp : null,
            onScaleStart: _scaleStart,
            onScaleUpdate: _scaleUpdate,
            onScaleEnd: _scaleEnd,
            // Holding still on a mask edit is not a press for the original.
            onLongPressStart: target != null
                ? null
                : (_) => c.setComparing(true),
            onLongPressEnd: target != null
                ? null
                : (_) => c.setComparing(false),
            onLongPressCancel: target != null
                ? null
                : () => c.setComparing(false),
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
                  if (img != null &&
                      (target != null || overlay != null || lensPoint))
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: MaskHandlesPainter(
                            view: _maskView(p, g, s),
                            shape:
                                target is RadialShape || target is LinearShape
                                ? target
                                : null,
                            overlay: overlay,
                            overlayColour: lens
                                ? kFocusOverlayColour
                                : kMaskOverlayColour,
                            focusPoint: lensPoint ? c.lensBlur : null,
                            showFocusDisc: lensPoint && c.showFocus,
                            active: drag?.handle,
                            brushAt: painting ? drag.at : null,
                            brushSize: c.brushSize,
                            brushFeather: c.brushFeather,
                            accent: colors.accent,
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
      // The tile's own pixels per photo pixel (its size was rounded).
      final sx = t.image.width / t.outer.width;
      final sy = t.image.height / t.outer.height;
      final src = Rect.fromLTWH(
        (t.inner.left - t.outer.left) * sx,
        (t.inner.top - t.outer.top) * sy,
        t.inner.width * sx,
        t.inner.height * sy,
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
