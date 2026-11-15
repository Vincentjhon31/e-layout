import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Design width: every layout is drawn on a frame 1200 units wide.
const double kDesignW = 1200;

const Map<String, double> kRatios = {
  'landscape': 3 / 2,
  'portrait': 3 / 4,
  'square': 1,
  'wide': 16 / 9,
  'tall': 4 / 5,
};

/// Canvas 2D composite operation names, same order as model.js BLENDS.
const List<String> kBlends = [
  'source-over', 'multiply', 'screen', 'overlay', 'darken', 'lighten',
  'color-dodge', 'color-burn', 'hard-light', 'soft-light', 'difference',
  'exclusion', 'hue', 'saturation', 'color', 'luminosity', //
];

enum ElementType { text, shape, image, icon }

enum Pin { top, center, bottom, stretch }

enum FillType { none, solid, linear, radial }

enum ShapeKind { rect, ellipse, triangle, diamond, polygon, star, arrow, torn }

enum ImageFit { contain, cover, stretch }

enum TextAlignH { left, center, right }

enum IconBgShape { none, circle, square }

enum DocFit { keep, crop }

class GradientStop {
  GradientStop(this.at, this.color, this.alpha);
  double at;
  String color;
  double alpha;

  GradientStop clone() => GradientStop(at, color, alpha);
  Map<String, dynamic> toJson() => {'at': jn(at), 'color': color, 'alpha': jn(alpha)};
}

class Fill {
  Fill({
    this.type = FillType.solid,
    this.color = '#2481C3',
    this.alpha = 1,
    this.angle = 90,
    List<GradientStop>? stops,
  }) : stops = stops ??
            [GradientStop(0, '#2481C3', 0), GradientStop(1, '#2481C3', 1)];

  FillType type;
  String color;
  double alpha;
  double angle;
  List<GradientStop> stops;

  Fill clone() => Fill(
      type: type,
      color: color,
      alpha: alpha,
      angle: angle,
      stops: [for (final s in stops) s.clone()]);

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'color': color,
        'alpha': jn(alpha),
        'angle': jn(angle),
        'stops': [for (final s in stops) s.toJson()],
      };
}

class Stroke {
  Stroke({this.width = 0, this.color = '#14212E', this.alpha = 1});
  double width;
  String color;
  double alpha;

  Stroke clone() => Stroke(width: width, color: color, alpha: alpha);
  Map<String, dynamic> toJson() =>
      {'width': jn(width), 'color': color, 'alpha': jn(alpha)};
}

class ShadowSpec {
  ShadowSpec({
    this.on = false,
    this.color = '#000000',
    this.alpha = 0.35,
    this.blur = 8,
    this.x = 0,
    this.y = 3,
  });
  bool on;
  String color;
  double alpha;
  double blur;
  double x;
  double y;

  ShadowSpec clone() =>
      ShadowSpec(on: on, color: color, alpha: alpha, blur: blur, x: x, y: y);
  Map<String, dynamic> toJson() => {
        'on': on,
        'color': color,
        'alpha': jn(alpha),
        'blur': jn(blur),
        'x': jn(x),
        'y': jn(y),
      };
}

class Effects {
  Effects({
    this.blur = 0,
    this.brightness = 100,
    this.contrast = 100,
    this.saturate = 100,
    this.grayscale = 0,
  });
  double blur, brightness, contrast, saturate, grayscale;

  Effects clone() => Effects(
      blur: blur,
      brightness: brightness,
      contrast: contrast,
      saturate: saturate,
      grayscale: grayscale);
  Map<String, dynamic> toJson() => {
        'blur': jn(blur),
        'brightness': jn(brightness),
        'contrast': jn(contrast),
        'saturate': jn(saturate),
        'grayscale': jn(grayscale),
      };
}

class IconBg {
  IconBg({this.shape = IconBgShape.circle, this.color = '#FFFFFF', this.alpha = 1});
  IconBgShape shape;
  String color;
  double alpha;

  IconBg clone() => IconBg(shape: shape, color: color, alpha: alpha);
  Map<String, dynamic> toJson() =>
      {'shape': shape.name, 'color': color, 'alpha': jn(alpha)};
}

/// One piece of a layout. A single mutable class for all four types, like the
/// JS object; fields of other types are kept at their defaults and not written.
class LayoutElement {
  LayoutElement._(this.id, this.type);

  /// Defaults of model.js newElement().
  factory LayoutElement.create(ElementType type) {
    final el = LayoutElement._(uid('e'), type);
    switch (type) {
      case ElementType.text:
        el
          ..name = 'Text'
          ..text = 'Your text here'
          ..font = 'Barlow'
          ..weight = 700
          ..size = 56
          ..fill.color = '#FFFFFF'
          ..shadow =
              ShadowSpec(on: true, color: '#000000', alpha: 0.35, blur: 6, x: 0, y: 2);
      case ElementType.shape:
        el
          ..name = 'Shape'
          ..w = 240
          ..h = 160;
      case ElementType.image:
        el
          ..name = 'Image'
          ..fill.type = FillType.none
          ..stroke.color = '#FFFFFF';
      case ElementType.icon:
        el
          ..name = 'Icon'
          ..w = 64
          ..h = 64;
    }
    return el;
  }

  String id;
  ElementType type;
  String name = '';
  bool visible = true;
  bool locked = false;
  double x = 0, w = 200, h = 100;
  Pin pin = Pin.center;
  bool? pinAuto = true;
  double top = 0, bottom = 0, cy = 0;
  String? group;
  double rotation = 0, skewX = 0, skewY = 0;
  bool flipX = false, flipY = false;
  double opacity = 1;
  String blend = 'source-over';
  Fill fill = Fill();
  Stroke stroke = Stroke();
  ShadowSpec shadow = ShadowSpec();
  double radius = 0;
  Effects effects = Effects();
  // text
  String text = '';
  String font = 'Barlow';
  int weight = 400;
  bool italic = false;
  double size = 48;
  TextAlignH align = TextAlignH.left;
  double letterSpacing = 0;
  double lineHeight = 1.2;
  bool upper = false;
  // shape
  ShapeKind shape = ShapeKind.rect;
  int sides = 6;
  int points = 5;
  double inner = 0.45;
  int seed = 7;
  double rough = 0.5;
  // image
  String? asset;
  ImageFit fit = ImageFit.contain;
  // icon
  String icon = 'phone';
  double lineWidth = 2;
  IconBg iconBg = IconBg();

  /// Deep copy, same id.
  LayoutElement clone() {
    final c = LayoutElement._(id, type)
      ..name = name
      ..visible = visible
      ..locked = locked
      ..x = x
      ..w = w
      ..h = h
      ..pin = pin
      ..pinAuto = pinAuto
      ..top = top
      ..bottom = bottom
      ..cy = cy
      ..group = group
      ..rotation = rotation
      ..skewX = skewX
      ..skewY = skewY
      ..flipX = flipX
      ..flipY = flipY
      ..opacity = opacity
      ..blend = blend
      ..fill = fill.clone()
      ..stroke = stroke.clone()
      ..shadow = shadow.clone()
      ..radius = radius
      ..effects = effects.clone()
      ..text = text
      ..font = font
      ..weight = weight
      ..italic = italic
      ..size = size
      ..align = align
      ..letterSpacing = letterSpacing
      ..lineHeight = lineHeight
      ..upper = upper
      ..shape = shape
      ..sides = sides
      ..points = points
      ..inner = inner
      ..seed = seed
      ..rough = rough
      ..asset = asset
      ..fit = fit
      ..icon = icon
      ..lineWidth = lineWidth
      ..iconBg = iconBg.clone();
    return c;
  }

  /// Common keys plus only the keys of this element's own type.
  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'type': type.name,
      'name': name,
      'visible': visible,
      'locked': locked,
      'x': jn(x),
      'w': jn(w),
      'h': jn(h),
      'pin': pin.name,
      if (pinAuto != null) 'pinAuto': pinAuto,
      'top': jn(top),
      'bottom': jn(bottom),
      'cy': jn(cy),
      if (group != null) 'group': group,
      'rotation': jn(rotation),
      'skewX': jn(skewX),
      'skewY': jn(skewY),
      'flipX': flipX,
      'flipY': flipY,
      'opacity': jn(opacity),
      'blend': blend,
      'fill': fill.toJson(),
      'stroke': stroke.toJson(),
      'shadow': shadow.toJson(),
      'radius': jn(radius),
      'effects': effects.toJson(),
    };
    switch (type) {
      case ElementType.text:
        m.addAll({
          'text': text,
          'font': font,
          'weight': weight,
          'italic': italic,
          'size': jn(size),
          'align': align.name,
          'letterSpacing': jn(letterSpacing),
          'lineHeight': jn(lineHeight),
          'upper': upper,
        });
      case ElementType.shape:
        m.addAll({
          'shape': shape.name,
          'sides': sides,
          'points': points,
          'inner': jn(inner),
          'seed': seed,
          'rough': jn(rough),
        });
      case ElementType.image:
        m.addAll({'asset': asset, 'fit': fit.name});
      case ElementType.icon:
        m.addAll({
          'icon': icon,
          'lineWidth': jn(lineWidth),
          'iconBg': iconBg.toJson(),
        });
    }
    return m;
  }
}

int _uidCounter = 0;
final math.Random _uidRandom = math.Random();

/// model.js uid(): prefix + time + counter + four random base-36 characters.
String uid(String prefix) {
  _uidCounter = (_uidCounter + 1) % 1000000;
  final r = _uidRandom.nextInt(1679616).toRadixString(36).padLeft(4, '0'); // 36^4
  return '${prefix}_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
      '${_uidCounter.toRadixString(36)}$r';
}

/// Whole doubles become ints so written files look like the web app's.
Object jn(double v) => v == v.truncateToDouble() && v.abs() < 1e15 ? v.toInt() : v;

class GroupInfo {
  GroupInfo({this.name = 'Group', this.pin = Pin.center, this.pinAuto = true});
  String name;
  Pin pin;
  bool pinAuto;

  GroupInfo clone() => GroupInfo(name: name, pin: pin, pinAuto: pinAuto);
  Map<String, dynamic> toJson() =>
      {'name': name, 'pin': pin.name, 'pinAuto': pinAuto};
}

class LayoutAsset {
  LayoutAsset({
    required this.name,
    required this.mime,
    required this.bytes,
    required this.w,
    required this.h,
  });
  String name;
  String mime;
  Uint8List bytes;
  int w;
  int h;
  String? _dataUrl;

  /// `data:<mime>;base64,...`, built once.
  String get dataUrl =>
      _dataUrl ??= 'data:$mime;base64,${base64Encode(bytes)}';

  LayoutAsset clone() =>
      LayoutAsset(name: name, mime: mime, bytes: bytes, w: w, h: h);
}

class EmbeddedFont {
  EmbeddedFont({
    required this.weight,
    required this.style,
    required this.mime,
    required this.variable,
    required this.bytes,
  });
  int weight;
  String style;
  String mime;
  bool variable;
  Uint8List bytes;
}

class LayoutDoc {
  LayoutDoc({
    this.version = 2,
    this.pinsVersion = 2,
    required this.id,
    required this.name,
    this.width = kDesignW,
    this.fit = DocFit.keep,
    double? ratio,
    List<LayoutElement>? elements,
    Map<String, GroupInfo>? groups,
    Map<String, LayoutAsset>? assets,
    Map<String, List<EmbeddedFont>>? fonts,
    int? created,
    int? updated,
  })  : ratio = ratio ?? kRatios['landscape']!,
        elements = elements ?? [],
        groups = groups ?? {},
        assets = assets ?? {},
        fonts = fonts ?? {},
        created = created ?? DateTime.now().millisecondsSinceEpoch,
        updated = updated ?? DateTime.now().millisecondsSinceEpoch;

  /// model.js newLayout().
  factory LayoutDoc.blank([String? name]) => LayoutDoc(
        id: uid('L'),
        name: name ?? 'Untitled layout',
      );

  int version;
  int pinsVersion;
  String id;
  String name;
  double width;
  DocFit fit;
  double ratio;
  List<LayoutElement> elements;
  Map<String, GroupInfo> groups;
  Map<String, LayoutAsset> assets;
  Map<String, List<EmbeddedFont>> fonts;
  int created;
  int updated;

  LayoutDoc clone() => LayoutDoc(
        version: version,
        pinsVersion: pinsVersion,
        id: id,
        name: name,
        width: width,
        fit: fit,
        ratio: ratio,
        elements: [for (final e in elements) e.clone()],
        groups: {for (final e in groups.entries) e.key: e.value.clone()},
        assets: {for (final e in assets.entries) e.key: e.value.clone()},
        fonts: {
          for (final e in fonts.entries) e.key: List<EmbeddedFont>.of(e.value),
        },
        created: created,
        updated: updated,
      );
}
