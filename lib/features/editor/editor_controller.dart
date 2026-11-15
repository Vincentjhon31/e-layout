import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/analysis/frame_split.dart';
import '../../core/analysis/remove_white.dart';
import '../../core/codec/png_encoder.dart';
import '../../core/fonts/font_registry.dart';
import '../../core/geometry/affine.dart';
import '../../core/icons/icon_set.dart';
import '../../core/model/layout_codec.dart' as codec;
import '../../core/model/layout_doc.dart';
import '../../core/model/layout_ops.dart' as ops;
import '../../core/render/layout_painter.dart';
import '../../core/render/layout_prep.dart';
import '../../core/render/text_layout.dart';
import 'editor_geometry.dart';

const double _rad = math.pi / 180;

/// editor.js TEXT_PRESETS.
class TextPreset {
  const TextPreset(this.label, this.text, this.font, this.weight, this.size);
  final String label, text, font;
  final int weight;
  final double size;
}

const List<TextPreset> kTextPresets = [
  TextPreset('Heading', 'Add a heading', 'Montserrat', 800, 72),
  TextPreset('Subheading', 'Add a subheading', 'Montserrat', 700, 44),
  TextPreset('Body text', 'Add some text', 'Open Sans', 400, 30),
  TextPreset('Script', 'Add a tagline', 'Dancing Script', 400, 52),
];

/// editor.js SHAPE_PRESETS. [band] is footer, header or torn for the full-width bands.
class ShapePreset {
  const ShapePreset(
    this.label, {
    this.shape = ShapeKind.rect,
    this.w = 0,
    this.h = 0,
    this.radius = 0,
    this.sides,
    this.points,
    this.inner,
    this.color,
    this.band,
  });
  final String label;
  final ShapeKind shape;
  final double w, h, radius;
  final int? sides, points;
  final double? inner;
  final String? color;
  final String? band;
}

const List<ShapePreset> kShapePresets = [
  ShapePreset('Rectangle', w: 260, h: 160),
  ShapePreset('Rounded rectangle', radius: 28, w: 260, h: 160),
  ShapePreset('Circle', shape: ShapeKind.ellipse, w: 180, h: 180),
  ShapePreset('Triangle', shape: ShapeKind.triangle, w: 200, h: 180),
  ShapePreset('Diamond', shape: ShapeKind.diamond, w: 180, h: 180),
  ShapePreset('Hexagon', shape: ShapeKind.polygon, sides: 6, w: 190, h: 190),
  ShapePreset('Star', shape: ShapeKind.star, points: 5, inner: 0.45, w: 190, h: 190),
  ShapePreset('Arrow', shape: ShapeKind.arrow, w: 240, h: 120),
  ShapePreset('Line', w: 320, h: 6, radius: 3, color: '#FFFFFF'),
  ShapePreset('Footer band', band: 'footer'),
  ShapePreset('Header band', band: 'header'),
  ShapePreset('Torn edge', band: 'torn'),
];

/// What the canvas shows behind the layout.
enum PreviewKind { sample, none, photo }

enum SelectionKind { none, single, group, multi }

enum DragKind { move, resize, rotate }

/// What a finger put down on the canvas picked up.
enum DownTarget { handle, piece, nothing }

/// A piece's state before a change, so a whole drag scales or turns from the same start.
class ItemStart {
  ItemStart(this.el, this.box, this.rot, this.size, this.ls, this.sw, this.radius, this.sb, this.sx, this.sy, this.fb);
  final LayoutElement el;
  final ui.Rect box;
  final double rot, size, ls, sw, radius, sb, sx, sy, fb;
}

class _Drag {
  _Drag(this.kind, this.start, this.before);
  final DragKind kind;
  final ui.Offset start;
  final String before;
  Handle? hd;
  LayoutElement? el;
  ui.Rect box = ui.Rect.zero;
  double rotation = 0, size = 0, ls = 0, sw = 0, delta = 0;
  Affine m = Affine.identity;
  List<ItemStart>? items;
  ui.Rect bb = ui.Rect.zero;
  bool moved = false;
  bool snapped = false;
  String? drill;
  String? untoggle;
}

/// The editor's document, selection, history and autosave (editor.js `ed`).
class EditorController extends ChangeNotifier {
  EditorController({
    required this.doc,
    required this.prep,
    required this.onSave,
    this.saveDelay = const Duration(milliseconds: 500),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    ops.cleanGroups(doc);
  }

  static const int historyLimit = 120;

  LayoutDoc doc;
  final LayoutPrep prep;
  final Future<void> Function(LayoutDoc doc) onSave;
  final Duration saveDelay;
  final DateTime Function() clock;

  /// Selected piece ids, in layer order.
  List<String> sel = [];

  /// Groups opened in the layers list.
  final Set<String> expanded = {};

  /// Long-press started picking several pieces: taps add or remove pieces.
  bool picking = false;

  /// Screen points per design unit (set by the canvas; thresholds use it).
  double zoom = 1;

  /// Bumped on every change so painters repaint.
  int revision = 0;

  // Preview.
  PreviewKind preview = PreviewKind.sample;
  ui.Image? photo;
  String ratioName = 'landscape';

  // Snapping guides while dragging.
  List<Guide> guides = [];

  /// Short messages for the person (shown as a toast by the screen).
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);
  String status = 'All changes saved';
  bool statusBad = false;

  final List<String> _history = [];
  final List<String> _future = [];
  String? _lastKey;
  DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _saveTimer;
  Future<void> _saving = Future<void>.value();
  _Drag? _drag;
  int _insertCount = 0;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void say(String text) {
    notice.value = null;
    notice.value = text;
  }

  // ---------- frame ----------

  double get ratioValue => photo != null && doc.fit == DocFit.keep && preview == PreviewKind.photo
      ? photo!.width / photo!.height
      : kRatios[ratioName]!;

  double get frameH => ops.frameHeight(doc, ratioValue);

  /// The Landscape / Portrait / Square buttons do nothing for a cropped layout or a real photo.
  bool get shapeFixed => doc.fit == DocFit.crop || (photo != null && preview == PreviewKind.photo);

  ui.Rect boxOfEl(LayoutElement el) => ops.boxOf(el, frameH);

  void setRatio(String name) {
    if (!kRatios.containsKey(name)) return;
    ratioName = name;
    revision++;
    _notify();
  }

  /// Shows the sample scene, the see-through checker, or [image] (owned by the caller).
  void setPreview(PreviewKind kind, {ui.Image? image}) {
    preview = kind;
    photo = kind == PreviewKind.photo ? image : null;
    if (kind == PreviewKind.photo && image == null) preview = PreviewKind.sample;
    revision++;
    _notify();
  }

  // ---------- selection ----------

  LayoutElement? byId(String? id) {
    if (id == null) return null;
    for (final e in doc.elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  List<LayoutElement> get selection => [
    for (final e in doc.elements)
      if (sel.contains(e.id)) e,
  ];

  LayoutElement? get single {
    final s = selection;
    return s.length == 1 ? s.first : null;
  }

  /// The group whose pieces are exactly the selection, if any.
  String? get selectedGroup {
    final s = selection;
    if (s.length < 2 || s.first.group == null || !s.every((e) => e.group == s.first.group)) return null;
    return ops.membersOf(doc, s.first.group!).length == s.length ? s.first.group : null;
  }

  SelectionKind get selectionKind {
    if (sel.isEmpty) return SelectionKind.none;
    if (sel.length == 1) return SelectionKind.single;
    return selectedGroup != null ? SelectionKind.group : SelectionKind.multi;
  }

  /// What a tap on this piece selects: its whole group, unless already working inside that group.
  /// How many pieces or whole groups are selected.
  int get unitsOfSelection => unitsOf(selection).length;

  List<String> unitOf(LayoutElement el) {
    if (el.group == null) return [el.id];
    final cur = single;
    if (cur != null && cur.group == el.group) return [el.id];
    return [for (final m in ops.membersOf(doc, el.group!)) m.id];
  }

  /// Selected things as units: whole groups and loose pieces, bottom to top.
  List<List<LayoutElement>> unitsOf(List<LayoutElement> list) {
    final out = <List<LayoutElement>>[];
    final seen = <String>{};
    for (final el in list) {
      final g = el.group;
      if (g != null) {
        if (seen.contains(g)) continue;
        final inList = list.where((x) => x.group == g).toList();
        if (inList.length == ops.membersOf(doc, g).length) {
          seen.add(g);
          out.add(inList);
          continue;
        }
      }
      out.add([el]);
    }
    return out;
  }

  void select(Iterable<String> ids) {
    final want = ids.toSet();
    sel = [
      for (final e in doc.elements)
        if (want.contains(e.id)) e.id,
    ];
    final one = single;
    if (one?.group != null) expanded.add(one!.group!);
    if (sel.isEmpty) picking = false;
    _notify();
  }

  /// Adds a piece (or its whole group) to the selection, or takes it out.
  void toggleInSelection(LayoutElement el) {
    final unit = el.group != null ? [for (final m in ops.membersOf(doc, el.group!)) m.id] : [el.id];
    select(sel.contains(el.id) ? sel.where((id) => !unit.contains(id)) : [...sel, ...unit]);
  }

  /// Long-press on a piece: start picking several pieces with taps.
  void startPicking(LayoutElement el) {
    picking = true;
    if (!sel.contains(el.id)) {
      select([
        ...sel,
        ...(el.group != null ? [for (final m in ops.membersOf(doc, el.group!)) m.id] : [el.id]),
      ]);
    } else {
      _notify();
    }
  }

  void stopPicking() {
    picking = false;
    _notify();
  }

  // ---------- geometry ----------

  List<Handle> handles() {
    final s = selection;
    if (s.isEmpty || s.any((e) => e.locked)) return const [];
    return s.length == 1 ? handlesOf(s.first, frameH, zoom) : multiHandles(s, frameH, zoom);
  }

  LayoutElement? elementAt(ui.Offset p, {double slop = 12}) => elementAtIn(doc, p, frameH, zoom, slop: slop);

  List<ItemStart> startOf(List<LayoutElement> list) => [
    for (final el in list)
      ItemStart(
        el,
        boxOfEl(el),
        el.rotation,
        el.size,
        el.letterSpacing,
        el.stroke.width,
        el.radius,
        el.shadow.blur,
        el.shadow.x,
        el.shadow.y,
        el.effects.blur,
      ),
  ];

  void moveItems(List<ItemStart> items, double dx, double dy) {
    final fh = frameH;
    for (final it in items) {
      ops.setBox(it.el, it.box.shift(ui.Offset(dx, dy)), fh);
    }
  }

  /// Scales pieces by [k] around [anchor], keeping their angles; sizes of text, borders and shadows follow.
  void scaleItems(List<ItemStart> items, ui.Offset anchor, double k) {
    final fh = frameH;
    for (final it in items) {
      final el = it.el, box = it.box;
      final cx = anchor.dx + (box.center.dx - anchor.dx) * k;
      final cy = anchor.dy + (box.center.dy - anchor.dy) * k;
      el.stroke.width = it.sw * k;
      el.radius = it.radius * k;
      el.shadow.blur = it.sb * k;
      el.shadow.x = it.sx * k;
      el.shadow.y = it.sy * k;
      el.effects.blur = it.fb * k;
      var w = box.width * k;
      var h = box.height * k;
      if (el.type == ElementType.text) {
        el.size = math.max(2, it.size * k);
        el.letterSpacing = it.ls * k;
        final l = layoutText(el);
        w = l.w;
        h = l.h;
      }
      ops.setBox(el, ui.Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h), fh);
    }
  }

  /// Turns pieces around [c] by [deg] degrees.
  void turnItems(List<ItemStart> items, ui.Offset c, double deg) {
    final fh = frameH;
    final a = deg * _rad;
    final cos = math.cos(a), sin = math.sin(a);
    for (final it in items) {
      final box = it.box;
      final dx = box.center.dx - c.dx, dy = box.center.dy - c.dy;
      final nx = c.dx + dx * cos - dy * sin;
      final ny = c.dy + dx * sin + dy * cos;
      it.el.rotation = round1(wrapDeg(it.rot + deg));
      ops.setBox(it.el, ui.Rect.fromLTWH(nx - box.width / 2, ny - box.height / 2, box.width, box.height), fh);
    }
  }

  /// After pieces moved: groups pin their pieces together, loose pieces follow their own position.
  void repin(Iterable<LayoutElement> list) {
    final fh = frameH;
    final groups = <String>{};
    for (final el in list) {
      if (el.group != null) {
        groups.add(el.group!);
      } else {
        ops.autoRepin(el, fh);
      }
    }
    for (final g in groups) {
      ops.groupPin(doc, g, fh);
    }
  }

  /// Re-measures a text piece after its words or font changed, keeping its alignment.
  void fitText(LayoutElement el) {
    final l = layoutText(el);
    final oldW = el.w;
    if (el.align == TextAlignH.center) el.x += (oldW - l.w) / 2;
    if (el.align == TextAlignH.right) el.x += oldW - l.w;
    el.w = l.w;
    el.h = l.h;
  }

  String defaultName(LayoutElement el) {
    if (el.type == ElementType.text) {
      final first = el.text.split('\n').first;
      final s = first.length > 28 ? first.substring(0, 28) : first;
      return s.isEmpty ? 'Text' : s;
    }
    if (el.type == ElementType.icon) return '${IconSet.label(el.icon)} icon';
    return el.name.isNotEmpty ? el.name : el.type.name;
  }

  // ---------- history and saving ----------

  int get historyLength => _history.length;
  bool get canUndo => _history.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;

  void _pushHistory(String snap) {
    _history.add(snap);
    if (_history.length > historyLimit) _history.removeAt(0);
    _future.clear();
  }

  /// Runs [fn] as one undoable step. Steps with the same [key] within 1.2 s
  /// join into one (a slider drag is one step).
  void change(VoidCallback fn, [String? key]) {
    final now = clock();
    if (!(key != null && key == _lastKey && now.difference(_lastTime) < const Duration(milliseconds: 1200))) {
      _pushHistory(codec.snapshot(doc));
    }
    _lastKey = key;
    _lastTime = now;
    fn();
    changed();
  }

  void changed() {
    doc.updated = clock().millisecondsSinceEpoch;
    revision++;
    _scheduleSave();
    _notify();
  }

  void undo() {
    if (_history.isEmpty) return;
    _future.add(codec.snapshot(doc));
    doc = codec.restore(doc, _history.removeLast());
    _afterTimeTravel();
  }

  void redo() {
    if (_future.isEmpty) return;
    _history.add(codec.snapshot(doc));
    doc = codec.restore(doc, _future.removeLast());
    _afterTimeTravel();
  }

  void _afterTimeTravel() {
    _lastKey = null;
    sel = sel.where((id) => byId(id) != null).toList();
    changed();
  }

  void _scheduleSave() {
    status = 'Saving';
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () {
      flushSave();
    });
  }

  bool get savePending => _saveTimer != null;

  /// Writes the layout now (autosave runs this after a pause in changes).
  Future<void> flushSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final d = doc;
    _saving = _saving
        .then((_) => onSave(d))
        .then(
          (_) {
            if (_saveTimer == null) {
              status = 'All changes saved';
              statusBad = false;
            }
          },
          onError: (Object e) {
            status = 'Not saved: $e';
            statusBad = true;
            say(status);
          },
        );
    return _saving;
  }

  /// Leaving the editor: the last change is written, unused pictures dropped.
  Future<void> close() async {
    cancelDrag(keep: true);
    if (_saveTimer != null) flushSave();
    await _saving;
    ops.pruneAssets(doc);
    try {
      await onSave(doc);
    } catch (e) {
      debugPrint('Layout not saved: $e');
    }
  }

  void rename(String name) {
    final clean = name.replaceAll(RegExp(r'[\u0000-\u001f]'), '').trim();
    if (clean.isEmpty || clean == doc.name) return;
    change(() => doc.name = clean.length > 80 ? clean.substring(0, 80) : clean);
  }

  // ---------- dragging ----------

  bool get dragging => _drag != null;
  DragKind? get dragKind => _drag?.kind;

  /// Degrees turned so far by a turn handle of several pieces.
  double get dragDelta => _drag?.delta ?? 0;

  /// A finger went down at [p] (design units): grab a handle or a piece.
  DownTarget beginDrag(ui.Offset p) {
    _drag = null;
    final before = codec.snapshot(doc);
    final hd = handleAt(handles(), p, zoom);
    if (hd != null && !hd.multi) {
      final el = single!;
      final b = boxOfEl(el);
      _drag = _Drag(hd.kind == HandleKind.resize ? DragKind.resize : DragKind.rotate, p, before)
        ..hd = hd
        ..el = el
        ..box = b
        ..rotation = el.rotation
        ..size = el.size
        ..ls = el.letterSpacing
        ..sw = el.stroke.width
        ..m = matrixOf(el, b);
      return DownTarget.handle;
    }
    if (hd != null) {
      final list = selection;
      _drag = _Drag(hd.kind == HandleKind.resize ? DragKind.resize : DragKind.rotate, p, before)
        ..hd = hd
        ..items = startOf(list)
        ..bb = bboxOfAll(list, frameH);
      return DownTarget.handle;
    }
    final el = elementAt(p);
    if (el == null) return DownTarget.nothing;
    final inSel = sel.contains(el.id);
    String? untoggle;
    if (picking) {
      if (inSel) {
        untoggle = el.id;
      } else {
        toggleInSelection(el);
      }
    } else if (!inSel) {
      select(unitOf(el));
    }
    final list = selection;
    if (!list.any((x) => x.locked)) {
      _drag = _Drag(DragKind.move, p, before)
        ..items = startOf(list)
        ..untoggle = untoggle
        ..drill = !picking && inSel && list.length > 1 ? el.id : null;
    }
    return DownTarget.piece;
  }

  /// The finger moved to [p]. True when a snap just took hold (for a light haptic).
  bool updateDrag(ui.Offset p) {
    final d = _drag;
    if (d == null) return false;
    var snapped = false;
    switch (d.kind) {
      case DragKind.move:
        snapped = _moveDrag(d, p);
      case DragKind.resize:
        d.hd!.multi ? _scaleDrag(d, p) : _resizeDrag(d, p);
      case DragKind.rotate:
        snapped = d.hd!.multi ? _turnDrag(d, p) : _rotateDrag(d, p);
    }
    final fresh = snapped && !d.snapped;
    d.snapped = snapped;
    revision++;
    _notify();
    return fresh;
  }

  bool _moveDrag(_Drag d, ui.Offset p) {
    final dx = p.dx - d.start.dx, dy = p.dy - d.start.dy;
    if (!d.moved && math.sqrt(dx * dx + dy * dy) * zoom < 3) return false; // still a tap
    d.moved = true;
    moveItems(d.items!, dx, dy);
    final fh = frameH;
    final moving = {for (final it in d.items!) it.el};
    final bb = bboxOfAll(moving, fh);
    final others = [
      for (final o in doc.elements)
        if (!moving.contains(o) && o.visible) bboxOf(o, fh),
    ];
    final s = snapMove(bb, others, doc.width, fh, zoom);
    guides = s.guides;
    if (s.guides.isNotEmpty) moveItems(d.items!, dx + s.dx, dy + s.dy);
    return s.guides.isNotEmpty;
  }

  /// Corner of the box around several pieces: scales them all, keeping the opposite corner still.
  void _scaleDrag(_Drag d, ui.Offset p) {
    final bb = d.bb, hd = d.hd!;
    final a = ui.Offset(hd.hx != 0 ? bb.left : bb.right, hd.hy != 0 ? bb.top : bb.bottom);
    final c = ui.Offset(hd.hx != 0 ? bb.right : bb.left, hd.hy != 0 ? bb.bottom : bb.top);
    final vx = c.dx - a.dx, vy = c.dy - a.dy;
    final len2 = vx * vx + vy * vy;
    final k = math.max(0.05, ((p.dx - a.dx) * vx + (p.dy - a.dy) * vy) / (len2 == 0 ? 1 : len2));
    scaleItems(d.items!, a, k);
  }

  bool _turnDrag(_Drag d, ui.Offset p) {
    final c = d.bb.center;
    var deg = (math.atan2(p.dy - c.dy, p.dx - c.dx) - math.atan2(d.start.dy - c.dy, d.start.dx - c.dx)) / _rad;
    final raw = wrapDeg(deg);
    deg = snapAngle(raw);
    d.delta = deg;
    turnItems(d.items!, c, deg);
    return deg != raw;
  }

  void _resizeDrag(_Drag d, ui.Offset p) {
    final el = d.el!;
    final hx = d.hd!.hx, hy = d.hd!.hy;
    final b = d.box, m = d.m;
    final lin = Affine(m.a, m.b, m.c, m.d, 0, 0);
    final inv = lin.inverted();
    if (inv == null) return;
    final ax = (hx == 0.5 ? 0.5 : 1 - hx) * b.width;
    final ay = (hy == 0.5 ? 0.5 : 1 - hy) * b.height;
    final anchor = m.apply(ui.Offset(ax, ay));
    final v = inv.apply(p - anchor);
    var w = hx == 0.5 ? b.width : math.max(4.0, hx == 1 ? v.dx : -v.dx);
    var h = hy == 0.5 ? b.height : math.max(4.0, hy == 1 ? v.dy : -v.dy);
    final corner = hx != 0.5 && hy != 0.5;
    // Corners keep the proportions of text, pictures and icons; shapes stretch freely.
    final keepRatio = el.type == ElementType.text || (corner && el.type != ElementType.shape);
    if (keepRatio && corner) {
      final k = math.max(w / b.width, h / b.height);
      w = b.width * k;
      h = b.height * k;
    }
    if (el.type == ElementType.text) {
      final k = w / b.width;
      el.size = math.max(2, d.size * k);
      el.letterSpacing = d.ls * k;
      el.stroke.width = d.sw * k;
      final l = layoutText(el);
      w = l.w;
      h = l.h;
    }
    // Keep the opposite corner (or edge) where it was.
    final nax = (hx == 0.5 ? 0.5 : 1 - hx) * w;
    final nay = (hy == 0.5 ? 0.5 : 1 - hy) * h;
    final off = lin.apply(ui.Offset(nax - w / 2, nay - h / 2));
    final cx = anchor.dx - off.dx, cy = anchor.dy - off.dy;
    ops.setBox(el, ui.Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h), frameH);
  }

  bool _rotateDrag(_Drag d, ui.Offset p) {
    final c = d.m.apply(ui.Offset(d.box.width / 2, d.box.height / 2));
    final a0 = math.atan2(d.start.dy - c.dy, d.start.dx - c.dx);
    final a1 = math.atan2(p.dy - c.dy, p.dx - c.dx);
    final raw = wrapDeg(d.rotation + (a1 - a0) / _rad);
    final r = snapAngle(raw);
    d.el!.rotation = round1(r);
    return r != raw;
  }

  /// The finger lifted: the drag becomes one undo step.
  void endDrag() {
    final d = _drag;
    if (d == null) return;
    _drag = null;
    guides = [];
    if (d.kind == DragKind.move && !d.moved) {
      final un = byId(d.untoggle);
      if (un != null) {
        toggleInSelection(un);
      } else if (d.drill != null) {
        select([d.drill!]);
      } else {
        _notify();
      }
      return;
    }
    repin(d.items != null ? d.items!.map((it) => it.el) : [d.el!]);
    if (codec.snapshot(doc) != d.before) {
      _pushHistory(d.before);
      _lastKey = null;
      changed();
    } else {
      _notify();
    }
  }

  /// A second finger arrived (or the editor is closing): undo what the drag did, unless [keep].
  void cancelDrag({bool keep = false}) {
    final d = _drag;
    _drag = null;
    guides = [];
    if (d == null) return;
    if (keep) {
      if (d.kind != DragKind.move || d.moved) {
        repin(d.items != null ? d.items!.map((it) => it.el) : [d.el!]);
        if (codec.snapshot(doc) != d.before) {
          _pushHistory(d.before);
          changed();
        }
      }
      return;
    }
    if (codec.snapshot(doc) != d.before) {
      doc = codec.restore(doc, d.before);
      sel = sel.where((id) => byId(id) != null).toList();
      revision++;
    }
    _notify();
  }

  // ---------- adding pieces ----------

  void insert(LayoutElement el, {bool placed = false}) {
    final fh = frameH;
    if (!placed) {
      final off = (_insertCount++ % 6) * 18.0;
      ops.place(el, ui.Rect.fromLTWH((doc.width - el.w) / 2 + off, (fh - el.h) / 2 + off, el.w, el.h), fh);
    }
    if (el.name.isEmpty) el.name = defaultName(el);
    change(() => doc.elements.add(el));
    select([el.id]);
  }

  LayoutElement addText(TextPreset p) {
    final el = LayoutElement.create(ElementType.text)
      ..text = p.text
      ..font = p.font
      ..weight = p.weight
      ..size = p.size;
    el.name = defaultName(el);
    fitText(el);
    insert(el);
    return el;
  }

  LayoutElement addShape(ShapePreset p) {
    final fh = frameH;
    final el = LayoutElement.create(ElementType.shape);
    if (p.band != null) {
      final w = doc.width;
      el
        ..x = 0
        ..w = w;
      if (p.band == 'footer') {
        el
          ..name = 'Footer band'
          ..h = 250
          ..pin = Pin.bottom
          ..bottom = 0
          ..fill.type = FillType.linear
          ..fill.angle = 90
          ..fill.stops = [
            GradientStop(0, '#2481C3', 0),
            GradientStop(0.5, '#2481C3', 0.55),
            GradientStop(1, '#2481C3', 1),
          ];
      } else if (p.band == 'header') {
        el
          ..name = 'Header band'
          ..h = 100
          ..pin = Pin.top
          ..top = 0
          ..fill.color = '#14467F'
          ..fill.alpha = 0.92;
      } else {
        el
          ..name = 'Torn edge band'
          ..shape = ShapeKind.torn
          ..h = 170
          ..pin = Pin.bottom
          ..bottom = 0
          ..rough = 0.5
          ..fill.color = '#22488C'
          ..fill.alpha = 0.92;
      }
      ops.setBox(el, ops.boxOf(el, fh), fh);
      insert(el, placed: true);
      return el;
    }
    el
      ..name = p.label
      ..shape = p.shape
      ..w = p.w
      ..h = p.h
      ..radius = p.radius;
    if (p.sides != null) el.sides = p.sides!;
    if (p.points != null) el.points = p.points!;
    if (p.inner != null) el.inner = p.inner!;
    if (p.color != null) el.fill.color = p.color!;
    insert(el);
    return el;
  }

  LayoutElement addIcon(String name) {
    final el = LayoutElement.create(ElementType.icon)
      ..icon = name
      ..name = '${IconSet.label(name)} icon';
    insert(el);
    return el;
  }

  /// Stores a picture file as an asset and decodes it for drawing.
  Future<(String id, String name, int w, int h)> _registerPicture(String fileName, Uint8List bytes) async {
    final img = await decodeImageBytes(bytes);
    final stem = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final name = stem.isEmpty ? 'Picture' : stem;
    final ext = fileName.split('.').last.toLowerCase();
    final mime = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    final w = img.width, h = img.height;
    final id = ops.addAsset(doc, name: name, mime: mime, bytes: bytes, w: w, h: h);
    if (prep.bitmaps.containsKey(id)) {
      img.dispose();
    } else {
      prep.bitmaps[id] = img;
    }
    return (id, name, w, h);
  }

  /// A picture file becomes a piece, about a third of the frame wide at most.
  Future<LayoutElement> addPicture(String fileName, Uint8List bytes) async {
    final (id, name, w, h) = await _registerPicture(fileName, bytes);
    final k = math.min(1.0, math.min(doc.width * 0.35 / w, frameH * 0.5 / h));
    final el = LayoutElement.create(ElementType.image)
      ..name = name
      ..asset = id
      ..w = w * k
      ..h = h * k;
    insert(el);
    return el;
  }

  /// Another picture in the same space, fitted inside the old box.
  Future<void> replacePicture(LayoutElement el, String fileName, Uint8List bytes) async {
    final elId = el.id;
    final (id, name, w, h) = await _registerPicture(fileName, bytes);
    change(() {
      final now = byId(elId);
      if (now == null) return;
      final b = boxOfEl(now);
      final k = math.min(b.width / w, b.height / h);
      now
        ..asset = id
        ..name = name;
      ops.setBox(
        now,
        ui.Rect.fromLTWH(b.left + (b.width - w * k) / 2, b.top + (b.height - h * k) / 2, w * k, h * k),
        frameH,
      );
      repin([now]);
    });
  }

  /// editor.js removeWhite: the white around a logo becomes see-through.
  /// Returns false when the picture is not loaded.
  Future<bool> makeSeeThrough(LayoutElement el, double tolerance) async {
    final elId = el.id;
    final assetId = el.asset;
    final asset = doc.assets[assetId];
    final bmp = prep.bitmaps[assetId];
    if (asset == null || bmp == null) return false;
    final data = await bmp.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return false;
    final w = bmp.width, h = bmp.height;
    final px = Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    removeWhitePixels(px, w, h, tolerance);
    final png = encodePng(px, w, h);
    final id = ops.addAsset(doc, name: '${asset.name} (clear background)', mime: 'image/png', bytes: png, w: w, h: h);
    if (!prep.bitmaps.containsKey(id)) prep.bitmaps[id] = await decodeImageBytes(png);
    change(() {
      final now = byId(elId);
      if (now != null) now.asset = id;
    });
    return true;
  }

  /// editor.js splitPicture: a full-frame picture with a see-through middle
  /// becomes edge parts that stay on their edges.
  Future<void> splitPicture(LayoutElement el) async {
    final fh = frameH;
    final b = boxOfEl(el);
    if (b.width < doc.width * 0.9 || b.height < fh * 0.9) {
      say('First make the picture cover the whole photo (drag its corners to the edges), then try again.');
      return;
    }
    final before = codec.snapshot(doc);
    final result = await fitAnyShape(doc, prep, fh, [el.id]);
    if (result.split == 0) {
      say("This picture has no see-through middle, so it can't be cut into edge parts.");
      return;
    }
    final wasCrop = doc.fit == DocFit.crop;
    if (wasCrop) doc.fit = DocFit.keep;
    ops.cleanGroups(doc, frameH);
    _pushHistory(before);
    _lastKey = null;
    sel = [];
    changed();
    say(wasCrop ? 'Cut into edge parts, and photos are no longer cropped.' : 'Cut into edge parts.');
  }

  /// The layout alone, see-through, [width] pixels wide (editor.js downloadPng).
  Future<Uint8List> layoutPng(int width) async {
    final fh = frameH;
    final k = width / doc.width;
    final height = (fh * k).round();
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.scale(k, k);
    drawLayout(canvas, doc, prep, fh);
    final img = await rec.endRecording().toImage(width, height);
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('The picture was too big to make.');
      return Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } finally {
      img.dispose();
    }
  }

  // ---------- fill, position ----------

  /// Gives every selected text this font (a font just added from the fonts screen).
  void setFont(String family) {
    if (!selection.any((e) => e.type == ElementType.text)) return;
    final reg = FontRegistry.instance;
    change(() {
      for (final e in selection) {
        if (e.type != ElementType.text) continue;
        e.font = family;
        e.weight = reg.nearestWeight(family, e.weight);
        fitText(e);
      }
      repin(selection);
    });
  }

  void setFillType(FillType t) => change(() {
    for (final e in selection) {
      e.fill.type = t;
    }
  }, 'filltype:${sel.join(',')}');

  /// A new colour stop between the last two, with the last one's colour (at most 8).
  void addGradientStop(LayoutElement el) {
    if (el.fill.stops.length >= 8) return;
    change(() {
      final sorted = [...el.fill.stops]..sort((a, b) => a.at.compareTo(b.at));
      final last = sorted.last;
      final prev = sorted.length > 1 ? sorted[sorted.length - 2].at : 0.0;
      el.fill.stops.add(GradientStop(((prev + last.at) / 2 * 100).round() / 100, last.color, last.alpha));
    });
  }

  /// Takes stop [i] out; false when only two are left.
  bool removeGradientStop(LayoutElement el, int i) {
    if (el.fill.stops.length <= 2 || i < 0 || i >= el.fill.stops.length) return false;
    change(() => el.fill.stops.removeAt(i));
    return true;
  }

  /// "Stays at": auto, top, center, bottom or stretch.
  void setPinChoice(String v) {
    final el = single;
    if (el == null || el.group != null) return;
    change(() {
      if (v == 'auto') {
        el.pinAuto = true;
        ops.autoRepin(el, frameH);
      } else {
        el.pinAuto = false;
        ops.setPin(el, Pin.values.firstWhere((p) => p.name == v), frameH);
      }
    });
  }

  void flip({required bool horizontal}) => change(() {
    for (final e in selection) {
      if (horizontal) {
        e.flipX = !e.flipX;
      } else {
        e.flipY = !e.flipY;
      }
    }
  });

  // ---------- arranging ----------

  /// The layer order as units: a whole group, or a piece on its own (bottom to top).
  List<List<LayoutElement>> topUnits() {
    final out = <List<LayoutElement>>[];
    for (final el in doc.elements) {
      if (el.group != null && out.isNotEmpty && out.last.first.group == el.group) {
        out.last.add(el);
      } else {
        out.add([el]);
      }
    }
    return out;
  }

  /// Tidies groups after pieces were added, removed or moved between groups.
  void settleGroups(Iterable<String?> gids) {
    final fh = frameH;
    ops.cleanGroups(doc, fh);
    for (final g in gids.toSet()) {
      if (g != null && doc.groups.containsKey(g)) ops.groupPin(doc, g, fh);
    }
  }

  void removeSelected() {
    final list = selection;
    if (list.isEmpty) return;
    final i = doc.elements.indexOf(list.first);
    change(() {
      doc.elements.removeWhere(list.contains);
      settleGroups(list.map((e) => e.group));
    });
    final next = doc.elements.isEmpty ? null : doc.elements[math.min(i, doc.elements.length - 1)];
    select(next != null && list.length == 1 ? unitOf(next) : const []);
  }

  /// Copies of pieces. A whole group copies as a new group; a piece taken from inside a group stays in that group.
  (List<LayoutElement>, Map<String, GroupInfo>) copiesOf(List<LayoutElement> list, bool rename) {
    final whole = {
      for (final u in unitsOf(list))
        if (u.length > 1) u.first.group!,
    };
    final newGroup = <String, String>{};
    final groups = <String, GroupInfo>{};
    final copies = [
      for (final el in list)
        () {
          final copy = ops.duplicateElement(el);
          if (rename) copy.name = '${el.name} copy';
          final g = el.group;
          if (g != null && whole.contains(g)) {
            if (!newGroup.containsKey(g)) {
              newGroup[g] = uid('g');
              final info = doc.groups[g]!;
              groups[newGroup[g]!] = GroupInfo(name: '${info.name} copy', pin: info.pin, pinAuto: info.pinAuto);
            }
            copy.group = newGroup[g];
          }
          return copy;
        }(),
    ];
    return (copies, groups);
  }

  void duplicateSelected() {
    final list = selection;
    if (list.isEmpty) return;
    final fh = frameH;
    final (copies, groups) = copiesOf(list, true);
    for (final c in copies) {
      final b = ops.boxOf(c, fh);
      ops.setBox(c, b.shift(const ui.Offset(20, 20)), fh);
    }
    change(() {
      doc.groups.addAll(groups);
      final arr = doc.elements;
      // Copies that stay in a group go right above their original; the rest above the topmost selected piece or group.
      final free = <LayoutElement>[];
      for (var i = 0; i < copies.length; i++) {
        final c = copies[i];
        if (c.group != null && c.group == list[i].group) {
          arr.insert(arr.indexOf(list[i]) + 1, c);
        } else {
          free.add(c);
        }
      }
      final tops = [
        for (final e in list)
          e.group != null ? ops.membersOf(doc, e.group!).map(arr.indexOf).reduce(math.max) : arr.indexOf(e),
      ];
      arr.insertAll(tops.reduce(math.max) + 1, free);
      settleGroups(copies.map((c) => c.group));
    });
    select(copies.map((c) => c.id));
  }

  /// Bring forward (+1) / send backward (-1). Groups move as a block; a piece inside a group moves among its group.
  void moveLayers(int delta) {
    final list = selection;
    if (list.isEmpty) return;
    final arr = doc.elements;
    final one = single;
    List<LayoutElement> order;
    if (one != null && one.group != null) {
      final idx = ops.membersOf(doc, one.group!).map(arr.indexOf).toList();
      final i = arr.indexOf(one);
      final j = (i + delta).clamp(idx.reduce(math.min), idx.reduce(math.max));
      order = [...arr]
        ..removeAt(i)
        ..insert(j, one);
    } else {
      final units = topUnits();
      bool picked(List<LayoutElement> u) => u.any((e) => sel.contains(e.id));
      final steps = [for (var i = 0; i < units.length; i++) i];
      for (final i in delta > 0 ? steps.reversed : steps) {
        final j = i + delta;
        if (!picked(units[i]) || j < 0 || j >= units.length || picked(units[j])) continue;
        final t = units[i];
        units[i] = units[j];
        units[j] = t;
      }
      order = [for (final u in units) ...u];
    }
    var same = true;
    for (var i = 0; i < order.length; i++) {
      if (!identical(order[i], arr[i])) same = false;
    }
    if (same) return;
    change(
      () => arr
        ..clear()
        ..addAll(order),
    );
  }

  /// One piece or one group lines up with the photo; several line up with each other.
  void align(String where) {
    final list = selection;
    if (list.isEmpty || list.any((e) => e.locked)) return;
    final fh = frameH;
    final units = unitsOf(list);
    final ref = units.length == 1 ? ui.Rect.fromLTWH(0, 0, doc.width, fh) : bboxOfAll(list, fh);
    change(() {
      for (final u in units) {
        final bb = bboxOfAll(u, fh);
        var dx = 0.0, dy = 0.0;
        if (where == 'left') dx = ref.left - bb.left;
        if (where == 'center') dx = ref.center.dx - bb.center.dx;
        if (where == 'right') dx = ref.right - bb.right;
        if (where == 'top') dy = ref.top - bb.top;
        if (where == 'middle') dy = ref.center.dy - bb.center.dy;
        if (where == 'bottom') dy = ref.bottom - bb.bottom;
        moveItems(startOf(u), dx, dy);
      }
      repin(list);
    });
  }

  /// Equal gaps between three or more pieces (or groups), keeping the outer two where they are.
  void distribute(String axis) {
    final list = selection;
    final units = unitsOf(list);
    if (units.length < 3 || list.any((e) => e.locked)) return;
    final fh = frameH;
    final x = axis == 'x';
    double lo(ui.Rect r) => x ? r.left : r.top;
    double hi(ui.Rect r) => x ? r.right : r.bottom;
    final items = [for (final u in units) (u, bboxOfAll(u, fh))]..sort((a, b) => lo(a.$2).compareTo(lo(b.$2)));
    final start = lo(items.first.$2);
    final end = items.map((it) => hi(it.$2)).reduce(math.max);
    final total = items.fold<double>(0, (s, it) => s + hi(it.$2) - lo(it.$2));
    final gap = (end - start - total) / (items.length - 1);
    change(() {
      var at = start;
      for (final (u, bb) in items) {
        final d = at - lo(bb);
        moveItems(startOf(u), x ? d : 0, x ? 0 : d);
        at += hi(bb) - lo(bb) + gap;
      }
      repin(list);
    });
  }

  void groupSelected() {
    final list = selection;
    if (unitsOf(list).length < 2) {
      say(
        selectionKind == SelectionKind.group
            ? 'These pieces are already a group.'
            : 'Select two or more pieces to group them: long-press a piece, then tap the others.',
      );
      return;
    }
    String? gid;
    change(() => gid = ops.makeGroup(doc, [for (final e in list) e.id], frameH));
    if (gid != null) select([for (final e in ops.membersOf(doc, gid!)) e.id]);
    picking = false;
    say('Grouped. Tap a piece of the group again to change it on its own.');
  }

  void ungroupSelected() {
    final list = selection;
    final gids = {
      for (final e in list)
        if (e.group != null) e.group!,
    };
    if (gids.isEmpty) return;
    final ids = [
      for (final g in gids)
        for (final e in ops.membersOf(doc, g)) e.id,
    ];
    change(() {
      for (final g in gids) {
        ops.ungroup(doc, g, frameH);
      }
    });
    select(ids);
    say('Ungrouped. The pieces are still selected, so you can move them together or tap one.');
  }

  /// Takes one piece out of its group and puts it just above the group.
  void takeOutOfGroup(LayoutElement el) {
    final gid = el.group;
    if (gid == null) return;
    change(() {
      final arr = doc.elements;
      final members = ops.membersOf(doc, gid);
      final last = arr.indexOf(members.last);
      arr.remove(el);
      arr.insert(last, el);
      el.group = null;
      el.pinAuto = true;
      ops.autoRepin(el, frameH);
      settleGroups([gid]);
    });
    select([el.id]);
  }

  // ---------- layers ----------

  void toggleVisible(String id) {
    final el = byId(id);
    if (el == null) return;
    change(() => byId(id)!.visible = !el.visible);
  }

  void toggleLocked(String id) {
    final el = byId(id);
    if (el == null) return;
    change(() => byId(id)!.locked = !el.locked);
    // A locked piece cannot stay selected for dragging; handles hide, outline stays.
  }

  /// An empty name keeps the old one.
  void renamePiece(String id, String name) {
    final clean = name.replaceAll(RegExp(r'[ -]'), '').trim();
    final el = byId(id);
    if (el == null || clean.isEmpty || clean == el.name) return;
    change(() => byId(id)!.name = clean.length > 60 ? clean.substring(0, 60) : clean);
  }

  /// Layers list drag: the unit shown at [from] (topmost first) ends up shown
  /// at [to] (the index after the move, as `ReorderableList.onReorderItem` reports it).
  void reorderUnit(int from, int to) {
    final units = topUnits().reversed.toList();
    if (from < 0 || from >= units.length) return;
    final target = to.clamp(0, units.length - 1);
    if (target == from) return;
    final saved = sel;
    sel = [for (final e in units[from]) e.id];
    final steps = (from - target).abs(), dir = from > target ? 1 : -1;
    final marks = _history.length;
    for (var i = 0; i < steps; i++) {
      moveLayers(dir);
    }
    // One drag is one undo step.
    if (_history.length > marks + 1) _history.removeRange(marks + 1, _history.length);
    sel = saved;
    _notify();
  }

  /// The layout keeps each photo's shape, or crops every photo to [ratio].
  void setFit(DocFit fit, {double? ratio}) {
    change(() {
      doc.fit = fit;
      if (ratio != null) doc.ratio = ratio;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    notice.dispose();
    super.dispose();
  }
}
