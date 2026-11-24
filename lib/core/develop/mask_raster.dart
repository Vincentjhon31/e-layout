import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'masks.dart';
import 'photo_developer.dart';

// Uniform layout of shaders/mask_range.frag, in the order they are set below.
// Keep this copy and the one at the top of the shader the same.
//   float index  name     meaning
//    0, 1        uSize    output (= source) size, px
//    2           uMode    0 = luminance range, 1 = colour range
//    3           uLow     luminance: lower end, 0..1
//    4           uHigh    luminance: upper end, 0..1
//    5           uSmooth  luminance: Smooth/100
//    6           uTol     colour: tolerance (OkLab distance)
//    7           uCount   colour: samples in use, 0..5
//    8..22       uS0..uS4 colour: samples in OkLab (L, a, b)
// Samplers: 0 uSrc (a drawn image).

/// The automatic coverage maps of a photo (Task 4's `AutoMaps`).
///
/// Each map covers the whole photo, at any size (it is stretched), with
/// coverage 0 to 1 in its alpha, like [MaskRasterizer.coverage]'s output.
abstract class AutoMapsSource {
  ui.Image get subject;
  ui.Image get sky;
}

/// Colour range: the OkLab distance at which a pixel leaves the selection for
/// a Refine of 0 to 100. Full selection up to half of it, none past it.
/// Ported from LightCraft `color_range_tolerance` (masks.rs, MIT OR
/// Apache-2.0).
double colourRangeTolerance(double refine) =>
    0.015 + 0.06 * (refine / 100).clamp(0.0, 1.0);

double _toLin(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _cbrt(double v) => v <= 0 ? 0 : math.pow(v, 1 / 3).toDouble();

/// OkLab (L, a, b) of an sRGB-encoded colour, as the range shader computes
/// it (Bjorn Ottosson's matrices).
(double, double, double) oklabOf(double r, double g, double b) {
  final lr = _toLin(r), lg = _toLin(g), lb = _toLin(b);
  final l = _cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  final m = _cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  final s = _cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  return (
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  );
}

/// LightCraft `smooth` (smoothstep from 0 to 1).
double _smooth(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// Gradient stops for a smoothstep fall from 1 at [inner] to 0 at 1.
const int _kSteps = 8;

const ui.Color _white = ui.Color(0xFFFFFFFF);
const ui.Color _black = ui.Color(0xFF000000);

ui.Color _alpha(double a) =>
    ui.Color.fromARGB((a.clamp(0.0, 1.0) * 255).round(), 255, 255, 255);

/// Turns opaque grey into white with that grey as its alpha.
const List<double> _greyToAlpha = [
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  1, 0, 0, 0, 0, //
];

/// Dabs a mask's brush strokes lay in all, at most (plus each stroke's two
/// end dabs). 64 strokes of realistic drags fit well inside it: a smallest
/// brush (radius 0.5 % of the long edge) lays 800 dabs per long edge of path.
const int kMaxBrushDabs = 262144;

/// Distance between dabs of a brush of radius [r] px: LightCraft
/// `dab_spacing` (masks.rs), a quarter of the radius, at least half a pixel.
double dabSpacing(double r) => math.max(r / 4, 0.5);

/// A stroke's brush radius in px: `size × long edge`, at least half a pixel
/// (LightCraft `brush_dabs`).
double brushRadius(BrushStroke st, double long) =>
    math.max(st.size * long, 0.5);

double _pathLength(List<ui.Offset> pts) {
  var sum = 0.0;
  ui.Offset? prev;
  for (final q in pts) {
    if (!q.dx.isFinite || !q.dy.isFinite) continue;
    final p = prev;
    if (p != null) sum += (q - p).distance;
    prev = q;
  }
  return sum;
}

/// Dab centres along the path [pts], [step] px apart by arc length, from the
/// first point to the last (after LightCraft `push_dabs`, masks.rs). The
/// spacing carries across segments, so dense points lay no extra dabs.
/// Points that do not move or are not finite lay nothing.
List<ui.Offset> brushDabs(List<ui.Offset> pts, double step) {
  assert(step > 0);
  final out = <ui.Offset>[];
  ui.Offset? prev;
  var since = 0.0; // path length from the last dab to prev
  for (final q in pts) {
    if (!q.dx.isFinite || !q.dy.isFinite) continue;
    final p = prev;
    if (p == null) {
      out.add(q);
      prev = q;
      continue;
    }
    final seg = (q - p).distance;
    if (!(seg > 1e-6)) continue;
    var t = step - since;
    while (t <= seg) {
      out.add(ui.Offset.lerp(p, q, t / seg)!);
      t += step;
    }
    since = seg - (t - step);
    prev = q;
  }
  if (prev != null && since > 1e-6) out.add(prev);
  return out;
}

/// The dabs of each of [s]'s strokes on a photo of [full] render px, in
/// photo px (empty for a stroke with no flow).
///
/// Past [cap] dabs, spacing widens by one factor for all paint strokes, so
/// they thin evenly and none is dropped. Erase strokes are budgeted first
/// and keep their spacing unless they alone pass [cap]. The plan depends
/// only on the mask and the photo size, never on the region drawn.
List<List<ui.Offset>> planBrushDabs(
  BrushShape s,
  ui.Size full, {
  int cap = kMaxBrushDabs,
}) {
  final long = math.max(full.width, full.height);
  final n = s.strokes.length;
  final pts = <List<ui.Offset>>[];
  final steps = <double>[];
  var eraseNeed = 0.0, paintNeed = 0.0;
  for (final st in s.strokes) {
    final p = [
      for (final q in st.points)
        ui.Offset(q.$1 * full.width, q.$2 * full.height),
    ];
    final step = dabSpacing(brushRadius(st, long));
    final k = st.flow > 0 ? _pathLength(p) / step : 0.0;
    pts.add(p);
    steps.add(step);
    if (st.erase) {
      eraseNeed += k;
    } else {
      paintNeed += k;
    }
  }
  final room = math.max(cap - 2 * n, 1).toDouble();
  final eraseK = eraseNeed > room ? eraseNeed / room : 1.0;
  final paintRoom = math.max(room - eraseNeed / eraseK, 1.0);
  final paintK = paintNeed > paintRoom ? paintNeed / paintRoom : 1.0;
  return [
    for (var i = 0; i < n; i++)
      if (s.strokes[i].flow <= 0)
        const <ui.Offset>[]
      else
        brushDabs(pts[i], steps[i] * (s.strokes[i].erase ? eraseK : paintK)),
  ];
}

bool _isRange(MaskShape s) => s is LuminanceRangeShape || s is ColourRangeShape;

/// Draws mask coverage: white images with coverage 0 to 1 in alpha.
///
/// Ported from LightCraft (MIT OR Apache-2.0), crates/pipeline/src/masks.rs,
/// with these e-Layout choices:
///  - Luminance range reads Rec.709 luma of the display-referred sRGB
///    source, re-encoded to sRGB (a grey's level is its value), not
///    LightCraft's log luminance mapped from -8 to +4 EV.
///  - Colour range has no select tone map and takes OkLab from linear sRGB.
///  - Brush flow is per stroke (the stroke layer's opacity), not per dab.
///  - Gradient fall-offs are 8-step approximations of LightCraft's
///    smoothstep.
///
/// Coverage depends only on the photo position: a region's pixels match the
/// same pixels of a render of the whole photo. Positions in a [Mask] are
/// normalised to the whole photo; brush sizes are a fraction of its long edge.
class MaskRasterizer {
  MaskRasterizer._(this._program);

  static Future<MaskRasterizer> load() async =>
      MaskRasterizer._(await ui.FragmentProgram.fromAsset(_asset));

  static const String _asset = 'shaders/mask_range.frag';

  final ui.FragmentProgram _program;

  /// How many drawn copies of a source this rasteriser has made, for tests.
  @visibleForTesting
  int debugDrawnCopies = 0;

  /// The coverage of [m] over [src], a drawn image the size of [src].
  ///
  /// [src] is the render region at [scale]; [origin] is its top-left in
  /// render pixels of the whole photo, and [fullSize] the whole photo in
  /// render pixels. Range components read [src]; Subject, Sky and Background
  /// read [auto], and cover nothing without it. The first component adds;
  /// the others add (max), subtract (`a·(1 − c)`) or intersect (`a·c`).
  Future<ui.Image> coverage(
    Mask m, {
    required ui.Image src,
    required ui.Offset origin,
    required ui.Size fullSize,
    required double scale,
    AutoMapsSource? auto,
  }) async {
    assert(scale > 0);
    // The tile rule: every texture sent to a shader is at most 2048 px.
    assert(src.width <= 2048 && src.height <= 2048);
    final w = src.width, h = src.height;
    final region = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final full = fullSize;
    final usable =
        full.width.isFinite &&
        full.height.isFinite &&
        !full.isEmpty &&
        origin.dx.isFinite &&
        origin.dy.isFinite;
    final comps = usable ? m.components : const <MaskComponent>[];

    // Range components are drawn first, each into its own image, so the
    // shader's fragment position is always the region's pixel.
    final ranges = <int, ui.Image>{};
    ui.Image? drawn;
    try {
      if (comps.any((c) => _isRange(c.shape))) {
        // The shader flips its reads on GLES, so it must sample a drawn
        // image, whatever the caller passed (see ShaderDeveloper).
        drawn = await copyImage(src);
        debugDrawnCopies++;
        for (var i = 0; i < comps.length; i++) {
          final s = comps[i].shape;
          if (_isRange(s)) ranges[i] = await _range(s, drawn, w, h);
        }
      }

      return await recordImage(w, h, (c) {
        c.saveLayer(
          region,
          ui.Paint()..colorFilter = const ui.ColorFilter.matrix(_greyToAlpha),
        );
        // Coverage is built as opaque grey, so lighten is the max and
        // modulate the product.
        c.drawPaint(ui.Paint()..color = _black);
        for (var i = 0; i < comps.length; i++) {
          final op = i == 0 ? MaskOp.add : comps[i].op;
          c.saveLayer(
            region,
            ui.Paint()
              ..blendMode = op == MaskOp.add
                  ? ui.BlendMode.lighten
                  : ui.BlendMode.modulate,
          );
          // Subtract multiplies by 1 − c: black coverage over white.
          final sub = op == MaskOp.subtract;
          c.drawPaint(ui.Paint()..color = sub ? _white : _black);
          c.saveLayer(
            region,
            sub
                ? (ui.Paint()
                    ..colorFilter = const ui.ColorFilter.mode(
                      _black,
                      ui.BlendMode.srcIn,
                    ))
                : ui.Paint(),
          );
          final r = ranges[i];
          if (r != null) {
            c.drawImage(r, ui.Offset.zero, ui.Paint());
          } else {
            c.save();
            c.translate(-origin.dx, -origin.dy);
            _drawShape(c, comps[i].shape, full, region.shift(origin), auto);
            c.restore();
          }
          c.restore();
          c.restore();
        }
        c.restore();
      });
    } finally {
      for (final r in ranges.values) {
        r.dispose();
      }
      drawn?.dispose();
    }
  }

  /// Draws [s]'s coverage in white alpha, in whole-photo render pixels.
  void _drawShape(
    ui.Canvas c,
    MaskShape s,
    ui.Size full,
    ui.Rect view,
    AutoMapsSource? auto,
  ) {
    final fw = full.width, fh = full.height;
    switch (s) {
      case RadialShape():
        _radial(c, s, fw, fh);
      case LinearShape():
        _linear(c, s, fw, fh);
      case BrushShape():
        _brush(c, s, fw, fh, view);
      case SubjectShape():
        if (auto != null) _stretch(c, auto.subject, fw, fh, null);
      case SkyShape():
        if (auto != null) _stretch(c, auto.sky, fw, fh, null);
      case BackgroundShape():
        if (auto != null) {
          c.drawPaint(ui.Paint()..color = _white);
          _stretch(c, auto.subject, fw, fh, ui.BlendMode.dstOut);
        }
      case LuminanceRangeShape():
      case ColourRangeShape():
        break; // drawn by _range
    }
  }

  /// An oval at `(cx·W, cy·H)` with radii `(rx·W, ry·H)`, turned by `angle`
  /// degrees (clockwise on screen): full inside `1 − feather/100` of the
  /// radius, falling as a smoothstep to 0 at the edge (LightCraft
  /// `shape_alpha` Radial).
  void _radial(ui.Canvas c, RadialShape s, double fw, double fh) {
    final inner = 1 - math.max(s.feather / 100, 0.01);
    final colors = <ui.Color>[];
    final stops = <double>[];
    for (var k = 0; k <= _kSteps; k++) {
      final a = 1 - _smooth(k / _kSteps);
      colors.add(_alpha(s.invert ? 1 - a : a));
      stops.add(inner + (1 - inner) * k / _kSteps);
    }
    if (inner > 0) {
      colors.insert(0, colors.first);
      stops.insert(0, 0);
    }
    final t = s.angle * math.pi / 180;
    final co = math.cos(t), si = math.sin(t);
    final sx = s.rx * fw, sy = s.ry * fh;
    final matrix = Float64List.fromList([
      co * sx, si * sx, 0, 0, //
      -si * sy, co * sy, 0, 0, //
      0, 0, 1, 0, //
      s.cx * fw, s.cy * fh, 0, 1, //
    ]);
    c.drawPaint(
      ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset.zero,
          1,
          colors,
          stops,
          ui.TileMode.clamp,
          matrix,
        ),
    );
  }

  /// Full at `(x0, y0)`, none at `(x1, y1)`, a smoothstep between and
  /// clamped beyond both ends (LightCraft `shape_alpha` Linear).
  void _linear(ui.Canvas c, LinearShape s, double fw, double fh) {
    final a = ui.Offset(s.x0 * fw, s.y0 * fh);
    final b = ui.Offset(s.x1 * fw, s.y1 * fh);
    if ((b - a).distance < 1e-6) {
      // No direction: LightCraft's t is 0 everywhere, so full coverage.
      c.drawPaint(ui.Paint()..color = _white);
      return;
    }
    c.drawPaint(
      ui.Paint()
        ..shader = ui.Gradient.linear(
          a,
          b,
          [for (var k = 0; k <= _kSteps; k++) _alpha(1 - _smooth(k / _kSteps))],
          [for (var k = 0; k <= _kSteps; k++) k / _kSteps],
        ),
    );
  }

  /// Each stroke a run of soft round dabs ([planBrushDabs]), each one full
  /// inside `radius × (1 − feather/100)` and falling as a smoothstep to 0 at
  /// the radius (LightCraft `dab_alpha`, masks.rs), with at least a pixel of
  /// fall-off. Dabs build up within a stroke with srcOver, `1 − Π(1 − a)`
  /// (LightCraft `accumulate`). Flow is per stroke, not per dab: it is the
  /// opacity of the stroke's layer, which is drawn over the strokes before
  /// it, or clears them (`dstOut`) for an erase stroke.
  ///
  /// Dabs are radial gradients, so every pixel's coverage is a function of
  /// its photo position only. (A stroked path's anti-aliasing changed with
  /// the region drawn, by up to 27/255.) Only dabs that touch [view], the
  /// region in photo px, are drawn, in a layer bounded to them.
  void _brush(ui.Canvas c, BrushShape s, double fw, double fh, ui.Rect view) {
    final long = math.max(fw, fh);
    final plan = planBrushDabs(s, ui.Size(fw, fh));
    for (var i = 0; i < s.strokes.length; i++) {
      final st = s.strokes[i];
      final r = brushRadius(st, long);
      final near = view.inflate(r + 1);
      final inView = [
        for (final d in plan[i])
          if (near.contains(d)) d,
      ];
      if (inView.isEmpty) continue;
      var minX = inView.first.dx, maxX = minX;
      var minY = inView.first.dy, maxY = minY;
      for (final d in inView) {
        minX = math.min(minX, d.dx);
        maxX = math.max(maxX, d.dx);
        minY = math.min(minY, d.dy);
        maxY = math.max(maxY, d.dy);
      }
      final bounds = ui.Rect.fromLTRB(
        minX,
        minY,
        maxX,
        maxY,
      ).inflate(r + 1).intersect(view);
      if (bounds.isEmpty) continue;

      // Full inside the hard core, at least a pixel of fall-off.
      final hard = math.max(0.0, math.min(1 - st.feather / 100, (r - 1) / r));
      final colors = <ui.Color>[];
      final stops = <double>[];
      if (hard > 0) {
        colors.add(_white);
        stops.add(0);
      }
      for (var k = 0; k <= _kSteps; k++) {
        colors.add(_alpha(1 - _smooth(k / _kSteps)));
        stops.add(hard + (1 - hard) * k / _kSteps);
      }
      final dab = ui.Paint()
        ..shader = ui.Gradient.radial(ui.Offset.zero, r, colors, stops);
      final box = ui.Rect.fromCircle(center: ui.Offset.zero, radius: r + 1);

      c.saveLayer(
        bounds,
        ui.Paint()
          ..color = _alpha(st.flow / 100)
          ..blendMode = st.erase ? ui.BlendMode.dstOut : ui.BlendMode.srcOver,
      );
      for (final d in inView) {
        c.save();
        c.translate(d.dx, d.dy);
        c.drawRect(box, dab);
        c.restore();
      }
      c.restore();
    }
  }

  /// [img] stretched over the whole photo.
  void _stretch(
    ui.Canvas c,
    ui.Image img,
    double fw,
    double fh,
    ui.BlendMode? mode,
  ) {
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
    if (mode != null) paint.blendMode = mode;
    c.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, fw, fh),
      paint,
    );
  }

  /// A range component's coverage of [drawn], [w] x [h].
  Future<ui.Image> _range(MaskShape s, ui.Image drawn, int w, int h) async {
    final sh = _program.fragmentShader();
    try {
      var i = 0;
      void f(double v) => sh.setFloat(i++, v);
      f(w.toDouble());
      f(h.toDouble());
      final samples = <(double, double, double)>[];
      if (s is LuminanceRangeShape) {
        f(0);
        f(s.low);
        f(s.high);
        f(s.smooth / 100);
        f(0);
        f(0);
      } else if (s is ColourRangeShape) {
        f(1);
        f(0);
        f(0);
        f(0);
        f(colourRangeTolerance(s.refine));
        final n = math.min(s.samples.length, kMaxColourSamples);
        f(n.toDouble());
        for (final p in s.samples.take(n)) {
          samples.add(oklabOf(p.$1, p.$2, p.$3));
        }
      }
      for (var k = 0; k < kMaxColourSamples; k++) {
        final p = k < samples.length ? samples[k] : (0.0, 0.0, 0.0);
        f(p.$1);
        f(p.$2);
        f(p.$3);
      }
      // Every read is at a texel centre: no filtering.
      sh.setImageSampler(0, drawn, filterQuality: ui.FilterQuality.none);
      return await recordImage(
        w,
        h,
        (c) => c.drawRect(
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint()..shader = sh,
        ),
      );
    } finally {
      sh.dispose();
    }
  }
}
