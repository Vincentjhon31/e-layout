import 'settings.dart';

/// Limits for masks (see the masking plan's global constraints).
const int kMaxMasks = 8;
const int kMaxComponents = 4;
const int kMaxStrokes = 64;
const int kMaxPoints = 2000;
const int kMaxColourSamples = 5;

/// The settings a mask may adjust locally.
const Set<Setting> kLocalSettings = {
  Setting.exposure,
  Setting.contrast,
  Setting.highlights,
  Setting.shadows,
  Setting.whites,
  Setting.blacks,
  Setting.temperature,
  Setting.tint,
  Setting.vibrance,
  Setting.saturation,
  Setting.texture,
  Setting.clarity,
  Setting.dehaze,
};

double _c(num v, double lo, double hi) {
  final d = v.toDouble();
  if (!d.isFinite) return lo;
  return d.clamp(lo, hi).toDouble();
}

String _cap(String s, int max) => s.length > max ? s.substring(0, max) : s;

double _r(double v) => (v * 10000).round() / 10000;

double _num(Object? v, double def, double lo, double hi) =>
    v is num && v.isFinite ? _c(v, lo, hi) : def;

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// How a component combines with the ones before it.
enum MaskOp { add, subtract, intersect }

/// One brush stroke. Points are normalised `(x, y)`, 0 to 1.
class BrushStroke {
  BrushStroke(
    Iterable<(double, double)> points, {
    double size = 0.05,
    double feather = 50,
    double flow = 100,
    this.erase = false,
  }) : points = List.unmodifiable([
         for (final p in points.take(kMaxPoints))
           (_r(_c(p.$1, 0, 1)), _r(_c(p.$2, 0, 1))),
       ]),
       size = _c(size, 0.005, 0.5),
       feather = _c(feather, 0, 100),
       flow = _c(flow, 0, 100);

  final List<(double, double)> points;

  /// Brush radius as a fraction of the long edge.
  final double size;
  final double feather;
  final double flow;
  final bool erase;

  Map<String, dynamic> toJson() => {
    'points': [
      for (final p in points) ...[_r(p.$1), _r(p.$2)],
    ],
    'size': _r(size),
    'feather': _r(feather),
    'flow': _r(flow),
    'erase': erase,
  };

  factory BrushStroke.fromJson(Map<String, dynamic> json) {
    final raw = json['points'];
    final pts = <(double, double)>[];
    if (raw is List) {
      for (var i = 0; i + 1 < raw.length && pts.length < kMaxPoints; i += 2) {
        final x = raw[i], y = raw[i + 1];
        if (x is num && y is num && x.isFinite && y.isFinite) {
          pts.add((x.toDouble(), y.toDouble()));
        }
      }
    }
    return BrushStroke(
      pts,
      size: _num(json['size'], 0.05, 0.005, 0.5),
      feather: _num(json['feather'], 50, 0, 100),
      flow: _num(json['flow'], 100, 0, 100),
      erase: json['erase'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BrushStroke &&
      other.size == size &&
      other.feather == feather &&
      other.flow == flow &&
      other.erase == erase &&
      _listEq(other.points, points);
  @override
  int get hashCode =>
      Object.hash(size, feather, flow, erase, Object.hashAll(points));
}

/// The area a mask component covers.
sealed class MaskShape {
  const MaskShape();

  Map<String, dynamic> toJson();

  static MaskShape? fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'brush':
        final raw = json['strokes'];
        return BrushShape([
          if (raw is List)
            for (final s in raw.take(kMaxStrokes))
              if (s is Map) BrushStroke.fromJson(Map<String, dynamic>.from(s)),
        ]);
      case 'linear':
        return LinearShape(
          _num(json['x0'], 0.5, 0, 1),
          _num(json['y0'], 0.25, 0, 1),
          _num(json['x1'], 0.5, 0, 1),
          _num(json['y1'], 0.75, 0, 1),
        );
      case 'radial':
        return RadialShape(
          cx: _num(json['cx'], 0.5, 0, 1),
          cy: _num(json['cy'], 0.5, 0, 1),
          rx: _num(json['rx'], 0.25, 0.01, 1),
          ry: _num(json['ry'], 0.25, 0.01, 1),
          angle: _num(json['angle'], 0, -180, 180),
          feather: _num(json['feather'], 50, 0, 100),
          invert: json['invert'] == true,
        );
      case 'luminance':
        return LuminanceRangeShape(
          low: _num(json['low'], 0.5, 0, 1),
          high: _num(json['high'], 1, 0, 1),
          smooth: _num(json['smooth'], 20, 0, 100),
        );
      case 'colour':
        final raw = json['samples'];
        final samples = <(double, double, double)>[];
        if (raw is List) {
          for (final s in raw) {
            if (samples.length >= kMaxColourSamples) break;
            if (s is List &&
                s.length == 3 &&
                s.every((e) => e is num && e.isFinite)) {
              samples.add((
                (s[0] as num).toDouble(),
                (s[1] as num).toDouble(),
                (s[2] as num).toDouble(),
              ));
            }
          }
        }
        return ColourRangeShape(
          samples,
          refine: _num(json['refine'], 50, 0, 100),
        );
      case 'subject':
        return const SubjectShape();
      case 'sky':
        return const SkyShape();
      case 'background':
        return const BackgroundShape();
    }
    return null;
  }
}

class BrushShape extends MaskShape {
  BrushShape(Iterable<BrushStroke> strokes)
    : strokes = List.unmodifiable(strokes.take(kMaxStrokes));

  final List<BrushStroke> strokes;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'brush',
    'strokes': [for (final s in strokes) s.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is BrushShape && _listEq(other.strokes, strokes);
  @override
  int get hashCode => Object.hash('brush', Object.hashAll(strokes));
}

/// A gradient: full effect at `(x0, y0)`, none at `(x1, y1)`.
class LinearShape extends MaskShape {
  LinearShape(double x0, double y0, double x1, double y1)
    : x0 = _c(x0, 0, 1),
      y0 = _c(y0, 0, 1),
      x1 = _c(x1, 0, 1),
      y1 = _c(y1, 0, 1);

  final double x0, y0, x1, y1;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'linear',
    'x0': _r(x0),
    'y0': _r(y0),
    'x1': _r(x1),
    'y1': _r(y1),
  };

  @override
  bool operator ==(Object other) =>
      other is LinearShape &&
      other.x0 == x0 &&
      other.y0 == y0 &&
      other.x1 == x1 &&
      other.y1 == y1;
  @override
  int get hashCode => Object.hash('linear', x0, y0, x1, y1);
}

class RadialShape extends MaskShape {
  RadialShape({
    double cx = .5,
    double cy = .5,
    double rx = .25,
    double ry = .25,
    double angle = 0,
    double feather = 50,
    this.invert = false,
  }) : cx = _c(cx, 0, 1),
       cy = _c(cy, 0, 1),
       rx = _c(rx, 0.01, 1),
       ry = _c(ry, 0.01, 1),
       angle = _c(angle, -180, 180),
       feather = _c(feather, 0, 100);

  final double cx, cy, rx, ry, angle, feather;
  final bool invert;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'radial',
    'cx': _r(cx),
    'cy': _r(cy),
    'rx': _r(rx),
    'ry': _r(ry),
    'angle': _r(angle),
    'feather': _r(feather),
    'invert': invert,
  };

  @override
  bool operator ==(Object other) =>
      other is RadialShape &&
      other.cx == cx &&
      other.cy == cy &&
      other.rx == rx &&
      other.ry == ry &&
      other.angle == angle &&
      other.feather == feather &&
      other.invert == invert;
  @override
  int get hashCode =>
      Object.hash('radial', cx, cy, rx, ry, angle, feather, invert);
}

class LuminanceRangeShape extends MaskShape {
  LuminanceRangeShape({double low = .5, double high = 1, double smooth = 20})
    : low = _c(low, 0, 1),
      high = _c(high, _c(low, 0, 1), 1),
      smooth = _c(smooth, 0, 100);

  final double low, high, smooth;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'luminance',
    'low': _r(low),
    'high': _r(high),
    'smooth': _r(smooth),
  };

  @override
  bool operator ==(Object other) =>
      other is LuminanceRangeShape &&
      other.low == low &&
      other.high == high &&
      other.smooth == smooth;
  @override
  int get hashCode => Object.hash('luminance', low, high, smooth);
}

/// Picked colours, each a normalised `(r, g, b)` with channels 0 to 1.
class ColourRangeShape extends MaskShape {
  ColourRangeShape(
    Iterable<(double, double, double)> samples, {
    double refine = 50,
  }) : samples = List.unmodifiable([
         for (final s in samples.take(kMaxColourSamples))
           (_c(s.$1, 0, 1), _c(s.$2, 0, 1), _c(s.$3, 0, 1)),
       ]),
       refine = _c(refine, 0, 100);

  final List<(double, double, double)> samples;
  final double refine;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'colour',
    'samples': [
      for (final s in samples) [_r(s.$1), _r(s.$2), _r(s.$3)],
    ],
    'refine': _r(refine),
  };

  @override
  bool operator ==(Object other) =>
      other is ColourRangeShape &&
      other.refine == refine &&
      _listEq(other.samples, samples);
  @override
  int get hashCode => Object.hash('colour', refine, Object.hashAll(samples));
}

class SubjectShape extends MaskShape {
  const SubjectShape();
  @override
  Map<String, dynamic> toJson() => {'type': 'subject'};
  @override
  bool operator ==(Object other) => other is SubjectShape;
  @override
  int get hashCode => 'subject'.hashCode;
}

class SkyShape extends MaskShape {
  const SkyShape();
  @override
  Map<String, dynamic> toJson() => {'type': 'sky'};
  @override
  bool operator ==(Object other) => other is SkyShape;
  @override
  int get hashCode => 'sky'.hashCode;
}

class BackgroundShape extends MaskShape {
  const BackgroundShape();
  @override
  Map<String, dynamic> toJson() => {'type': 'background'};
  @override
  bool operator ==(Object other) => other is BackgroundShape;
  @override
  int get hashCode => 'background'.hashCode;
}

class MaskComponent {
  const MaskComponent(this.shape, {this.op = MaskOp.add});

  final MaskShape shape;
  final MaskOp op;

  Map<String, dynamic> toJson() => {...shape.toJson(), 'op': op.name};

  static MaskComponent? fromJson(Map<String, dynamic> json) {
    final shape = MaskShape.fromJson(json);
    if (shape == null) return null;
    final op = MaskOp.values.where((o) => o.name == json['op']);
    return MaskComponent(shape, op: op.isEmpty ? MaskOp.add : op.first);
  }

  @override
  bool operator ==(Object other) =>
      other is MaskComponent && other.shape == shape && other.op == op;
  @override
  int get hashCode => Object.hash(shape, op);
}

/// A named area with local adjustments.
class Mask {
  Mask({
    required String id,
    String name = '',
    Iterable<MaskComponent> components = const [],
    Map<Setting, double> adjust = const {},
    this.visible = true,
  }) : id = _cap(id, 64),
       name = _cap(name, 40),
       components = List.unmodifiable(components.take(kMaxComponents)),
       adjust = Map.unmodifiable({
         for (final e in adjust.entries)
           if (kLocalSettings.contains(e.key)) e.key: e.key.clamp(e.value),
       });

  final String id;
  final String name;
  final List<MaskComponent> components;

  /// Deltas for the local settings only.
  final Map<Setting, double> adjust;
  final bool visible;

  /// True when this mask changes the picture.
  bool get hasEffect => visible && adjust.values.any((v) => v != 0);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'components': [for (final c in components) c.toJson()],
    'adjust': {
      for (final s in Setting.values)
        if (adjust.containsKey(s)) s.name: adjust[s],
    },
    'visible': visible,
  };

  factory Mask.fromJson(Map<String, dynamic> json) {
    final comps = <MaskComponent>[];
    final rawComps = json['components'];
    if (rawComps is List) {
      for (final c in rawComps) {
        if (comps.length >= kMaxComponents) break;
        if (c is Map) {
          final mc = MaskComponent.fromJson(Map<String, dynamic>.from(c));
          if (mc != null) comps.add(mc);
        }
      }
    }
    final byName = {for (final s in Setting.values) s.name: s};
    final adjust = <Setting, double>{};
    final rawAdjust = json['adjust'];
    if (rawAdjust is Map) {
      for (final e in rawAdjust.entries) {
        final s = byName[e.key];
        final v = e.value;
        if (s != null && v is num && v.isFinite) adjust[s] = v.toDouble();
      }
    }
    return Mask(
      id: _cap('${json['id'] ?? ''}', 64),
      name: _cap('${json['name'] ?? ''}', 40),
      components: comps,
      adjust: adjust,
      visible: json['visible'] != false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Mask &&
      other.id == id &&
      other.name == name &&
      other.visible == visible &&
      _listEq(other.components, components) &&
      other.adjust.length == adjust.length &&
      adjust.entries.every((e) => other.adjust[e.key] == e.value);
  @override
  int get hashCode => Object.hash(
    id,
    name,
    visible,
    Object.hashAll(components),
    Object.hashAllUnordered(
      adjust.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

enum LensFocus { subject, point, mask }

/// A depth-style background blur. [amount] 0 to 100; 100 is a disc radius of
/// 2 % of the long edge.
class LensBlur {
  LensBlur({
    double amount = 0,
    this.focus = LensFocus.subject,
    double fx = .5,
    double fy = .5,
    String? maskId,
    double transition = 50,
    double boost = 0,
  }) : maskId = maskId == null ? null : _cap(maskId, 64),
       amount = _c(amount, 0, 100),
       fx = _c(fx, 0, 1),
       fy = _c(fy, 0, 1),
       transition = _c(transition, 0, 100),
       boost = _c(boost, 0, 100);

  static final LensBlur off = LensBlur();

  final double amount;
  final LensFocus focus;
  final double fx, fy;
  final String? maskId;
  final double transition;
  final double boost;

  bool get isOn => amount > 0;

  Map<String, dynamic> toJson() => {
    'amount': _r(amount),
    'focus': focus.name,
    'fx': _r(fx),
    'fy': _r(fy),
    'maskId': maskId,
    'transition': _r(transition),
    'boost': _r(boost),
  };

  factory LensBlur.fromJson(Map<String, dynamic> json) {
    final f = LensFocus.values.where((e) => e.name == json['focus']);
    final m = json['maskId'];
    return LensBlur(
      amount: _num(json['amount'], 0, 0, 100),
      focus: f.isEmpty ? LensFocus.subject : f.first,
      fx: _num(json['fx'], 0.5, 0, 1),
      fy: _num(json['fy'], 0.5, 0, 1),
      maskId: m is String ? m : null,
      transition: _num(json['transition'], 50, 0, 100),
      boost: _num(json['boost'], 0, 0, 100),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LensBlur &&
      other.amount == amount &&
      other.focus == focus &&
      other.fx == fx &&
      other.fy == fy &&
      other.maskId == maskId &&
      other.transition == transition &&
      other.boost == boost;
  @override
  int get hashCode =>
      Object.hash(amount, focus, fx, fy, maskId, transition, boost);
}
