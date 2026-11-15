import 'dart:convert';
import 'dart:typed_data';

import '../icons/icon_set.dart';
import 'layout_doc.dart';
import 'layout_ops.dart';

class LayoutFormatException implements Exception {
  LayoutFormatException([this.message = "This file isn't a layout from this tool."]);
  final String message;
  @override
  String toString() => message;
}

final RegExp _imageData =
    RegExp(r'^data:image/(png|jpeg|webp|gif|avif);base64,([A-Za-z0-9+/=]+)$');
final RegExp _fontMime = RegExp(
    r'^(font/(ttf|otf|woff|woff2)|application/(x-font-ttf|x-font-otf|font-woff|font-sfnt|octet-stream)|)$');
final RegExp _idRe = RegExp(r'^[\w-]{1,64}$');
final RegExp _hexRe = RegExp(r'^#[0-9a-fA-F]{6}$');
final RegExp _b64Re = RegExp(r'^[A-Za-z0-9+/=]+$');
final RegExp _ctrlRe = RegExp(r'[\u0000-\u001f]');

double _num(Object? v, double def, double min, double max) =>
    v is num && v.isFinite ? v.toDouble().clamp(min, max).toDouble() : def;
String _str(Object? v, String def, int max) =>
    v is String ? (v.length > max ? v.substring(0, max) : v) : def;
bool _bool(Object? v, bool def) => v is bool ? v : def;
String _hex(Object? v, String def) =>
    v is String && _hexRe.hasMatch(v) ? v.toUpperCase() : def;
String _cleanName(Object? v, String def) {
  final s = _str(v, def, 80).replaceAll(_ctrlRe, '').trim();
  return s.isEmpty ? def : s;
}

T _pick<T extends Enum>(Object? v, List<T> values, T def) {
  if (v is String) {
    for (final e in values) {
      if (e.name == v) return e;
    }
  }
  return def;
}

int _round(double v) => v.round();

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : null;

Fill _cleanFill(Object? raw, Fill def) {
  final f = _map(raw);
  if (f == null) return def.clone();
  final stops = <GradientStop>[];
  if (f['stops'] is List) {
    for (final s in (f['stops'] as List).take(8)) {
      final m = _map(s);
      stops.add(GradientStop(_num(m?['at'], 0, 0, 1), _hex(m?['color'], '#000000'),
          _num(m?['alpha'], 1, 0, 1)));
    }
  }
  return Fill(
    type: _pick(f['type'], FillType.values, def.type),
    color: _hex(f['color'], def.color),
    alpha: _num(f['alpha'], def.alpha, 0, 1),
    angle: _num(f['angle'], 90, -360, 360),
    stops: stops.length >= 2 ? stops : [for (final s in def.stops) s.clone()],
  );
}

LayoutElement? _cleanElement(
    Object? rawIn, double scale, Map<String, LayoutAsset> assets, bool keepId) {
  final raw = _map(rawIn);
  if (raw == null) return null;
  ElementType? type;
  for (final t in ElementType.values) {
    if (t.name == raw['type']) type = t;
  }
  if (type == null) return null;
  final el = LayoutElement.create(type);
  if (keepId && raw['id'] is String && (raw['id'] as String).isNotEmpty) {
    el.id = raw['id'] as String;
  }
  double d(Object? v, double def, double min, double max) => _num(v, def, min, max);
  el
    ..name = _cleanName(raw['name'], el.name)
    ..visible = _bool(raw['visible'], true)
    ..locked = _bool(raw['locked'], false)
    ..x = d(raw['x'], 0, -1e5, 1e5) * scale
    ..w = d(raw['w'], el.w, 1, 1e5) * scale
    ..h = d(raw['h'], el.h, 1, 1e5) * scale
    ..pin = _pick(raw['pin'], Pin.values, Pin.center)
    ..pinAuto = raw['pinAuto'] is bool ? raw['pinAuto'] as bool : null
    ..group = raw['group'] is String && _idRe.hasMatch(raw['group'] as String)
        ? raw['group'] as String
        : null
    ..top = d(raw['top'], 0, -1e5, 1e5) * scale
    ..bottom = d(raw['bottom'], 0, -1e5, 1e5) * scale
    ..cy = d(raw['cy'], 0, -1e5, 1e5) * scale
    ..rotation = d(raw['rotation'], 0, -360, 360)
    ..skewX = d(raw['skewX'], 0, -80, 80)
    ..skewY = d(raw['skewY'], 0, -80, 80)
    ..flipX = _bool(raw['flipX'], false)
    ..flipY = _bool(raw['flipY'], false)
    ..opacity = d(raw['opacity'], 1, 0, 1)
    ..blend = kBlends.contains(raw['blend']) ? raw['blend'] as String : 'source-over'
    ..fill = _cleanFill(raw['fill'], el.fill)
    ..radius = d(raw['radius'], 0, 0, 1e4) * scale;
  final st = _map(raw['stroke']) ?? {};
  el.stroke = Stroke(
      width: d(st['width'], 0, 0, 500) * scale,
      color: _hex(st['color'], el.stroke.color),
      alpha: d(st['alpha'], 1, 0, 1));
  final sh = _map(raw['shadow']) ?? {};
  el.shadow = ShadowSpec(
      on: _bool(sh['on'], el.shadow.on),
      color: _hex(sh['color'], '#000000'),
      alpha: d(sh['alpha'], 0.35, 0, 1),
      blur: d(sh['blur'], 8, 0, 500) * scale,
      x: d(sh['x'], 0, -500, 500) * scale,
      y: d(sh['y'], 3, -500, 500) * scale);
  final fx = _map(raw['effects']) ?? {};
  el.effects = Effects(
      blur: d(fx['blur'], 0, 0, 100) * scale,
      brightness: d(fx['brightness'], 100, 0, 300),
      contrast: d(fx['contrast'], 100, 0, 300),
      saturate: d(fx['saturate'], 100, 0, 300),
      grayscale: d(fx['grayscale'], 0, 0, 100));

  switch (type) {
    case ElementType.text:
      el
        ..text = _str(raw['text'], el.text, 4000)
        ..font = _cleanName(raw['font'], 'Barlow')
        ..weight = _round(d(raw['weight'], 400, 100, 900) / 100) * 100
        ..italic = _bool(raw['italic'], false)
        ..size = d(raw['size'], 48, 1, 5000) * scale
        ..align = _pick(raw['align'], TextAlignH.values, TextAlignH.left)
        ..letterSpacing = d(raw['letterSpacing'], 0, -100, 500) * scale
        ..lineHeight = d(raw['lineHeight'], 1.2, 0.5, 4)
        ..upper = _bool(raw['upper'], false);
    case ElementType.shape:
      el
        ..shape = _pick(raw['shape'], ShapeKind.values, ShapeKind.rect)
        ..sides = _round(d(raw['sides'], 6, 3, 12))
        ..points = _round(d(raw['points'], 5, 3, 12))
        ..inner = d(raw['inner'], 0.45, 0.1, 0.95)
        ..seed = _round(d(raw['seed'], 7, 0, 1e6))
        ..rough = d(raw['rough'], 0.5, 0, 1);
    case ElementType.image:
      final a = raw['asset'];
      if (a is! String || !assets.containsKey(a)) return null;
      el
        ..asset = a
        ..fit = _pick(raw['fit'], ImageFit.values, ImageFit.contain);
    case ElementType.icon:
      final bg = _map(raw['iconBg']) ?? {};
      el
        ..icon = raw['icon'] is String && IconSet.has(raw['icon'] as String)
            ? raw['icon'] as String
            : 'star'
        ..lineWidth = d(raw['lineWidth'], 2, 0.5, 4)
        ..iconBg = IconBg(
            shape: _pick(bg['shape'], IconBgShape.values, IconBgShape.circle),
            color: _hex(bg['color'], '#FFFFFF'),
            alpha: d(bg['alpha'], 1, 0, 1));
  }
  return el;
}

/// model.js sanitize(): validates a layout read from a file. Accepts the export
/// envelope or a bare layout. Throws [LayoutFormatException] when it is not one.
LayoutDoc readLayout(Object? json, {bool keepIdentity = false}) =>
    _read(json, keepIdentity, null);

LayoutDoc _read(Object? json, bool keepIdentity, Map<String, LayoutAsset>? useAssets) {
  final top = _map(json);
  final raw = top != null && top['format'] == 'pio-photo-layout'
      ? _map(top['layout'])
      : top;
  if (raw == null || raw['version'] != 2 || raw['elements'] is! List) {
    throw LayoutFormatException();
  }
  final doc = LayoutDoc.blank(_cleanName(raw['name'], 'Imported layout'));
  final scale = kDesignW / _num(raw['width'], kDesignW, 10, 1e5);
  if (keepIdentity) {
    final id = raw['id'];
    if (id is String && id.isNotEmpty) doc.id = id;
    final c = raw['created'], u = raw['updated'];
    if (c is num && c.isFinite) doc.created = c.toInt();
    if (u is num && u.isFinite) doc.updated = u.toInt();
  }
  doc.fit = raw['fit'] == 'crop' ? DocFit.crop : DocFit.keep;
  doc.ratio = _num(raw['ratio'], kRatios['landscape']!, 0.2, 5);
  doc.pinsVersion = _num(raw['pinsVersion'], 1, 1, 99).toInt();

  final assets = <String, LayoutAsset>{};
  final rawAssets = useAssets != null ? <String, dynamic>{} : (_map(raw['assets']) ?? {});
  for (final e in rawAssets.entries) {
    final a = _map(e.value);
    final data = a?['data'];
    if (!_idRe.hasMatch(e.key) ||
        a == null ||
        data is! String ||
        data.length > 40e6) {
      continue;
    }
    final m = _imageData.firstMatch(data);
    if (m == null) continue;
    Uint8List bytes;
    try {
      bytes = base64Decode(m.group(2)!);
    } catch (_) {
      continue;
    }
    assets[e.key] = LayoutAsset(
      name: _cleanName(a['name'], 'Image'),
      mime: 'image/${m.group(1)}',
      bytes: bytes,
      w: _num(a['w'], 1, 1, 1e5).toInt(),
      h: _num(a['h'], 1, 1, 1e5).toInt(),
    );
  }
  if (useAssets != null) assets.addAll(useAssets);
  doc.assets = assets;

  final els = <LayoutElement>[];
  for (final e in (raw['elements'] as List).take(500)) {
    final c = _cleanElement(e, scale, assets, keepIdentity);
    if (c != null) els.add(c);
  }
  doc.elements = els;

  doc.groups = {};
  for (final e in (_map(raw['groups']) ?? {}).entries) {
    final g = _map(e.value);
    if (!_idRe.hasMatch(e.key) || g == null) continue;
    doc.groups[e.key] = GroupInfo(
      name: _cleanName(g['name'], 'Group'),
      pin: _pick(g['pin'], [Pin.top, Pin.center, Pin.bottom], Pin.center),
      pinAuto: _bool(g['pinAuto'], true),
    );
  }
  cleanGroups(doc);

  final fonts = <String, List<EmbeddedFont>>{};
  for (final e in (_map(raw['fonts']) ?? {}).entries) {
    final name = _cleanName(e.key, '');
    if (name.isEmpty || e.value is! List) continue;
    final faces = <EmbeddedFont>[];
    for (final fv in (e.value as List).take(18)) {
      final f = _map(fv);
      final data = f?['data'];
      if (f == null || data is! String || data.length >= 15e6 || !_b64Re.hasMatch(data)) {
        continue;
      }
      Uint8List bytes;
      try {
        bytes = base64Decode(data);
      } catch (_) {
        continue;
      }
      final mime = f['mime'] is String && _fontMime.hasMatch(f['mime'] as String)
          ? f['mime'] as String
          : '';
      faces.add(EmbeddedFont(
        weight: _round(_num(f['weight'], 400, 100, 900) / 100) * 100,
        style: f['style'] == 'italic' ? 'italic' : 'normal',
        mime: mime,
        variable: f['variable'] == true,
        bytes: bytes,
      ));
    }
    fonts[name] = faces;
  }
  doc.fonts = fonts;
  return doc;
}

Map<String, dynamic> _docMap(LayoutDoc doc, {bool withBinary = true}) => {
      'version': doc.version,
      'pinsVersion': doc.pinsVersion,
      'id': doc.id,
      'name': doc.name,
      'width': jn(doc.width),
      'fit': doc.fit.name,
      'ratio': jn(doc.ratio),
      'elements': [for (final e in doc.elements) e.toJson()],
      'groups': {for (final e in doc.groups.entries) e.key: e.value.toJson()},
      if (withBinary)
        'assets': {
          for (final e in doc.assets.entries)
            e.key: {
              'name': e.value.name,
              'data': e.value.dataUrl,
              'w': e.value.w,
              'h': e.value.h,
            },
        },
      if (withBinary)
        'fonts': {
          for (final e in doc.fonts.entries)
            e.key: [
              for (final f in e.value)
                {
                  'weight': f.weight,
                  'style': f.style,
                  'mime': f.mime,
                  'variable': f.variable,
                  'data': base64Encode(f.bytes),
                },
            ],
        },
      'created': doc.created,
      'updated': doc.updated,
    };

/// With [envelope]: `{format: 'pio-photo-layout', version: 2, layout: {...}}`.
Map<String, dynamic> writeLayout(LayoutDoc doc, {bool envelope = false}) {
  final m = _docMap(doc);
  return envelope
      ? {'format': 'pio-photo-layout', 'version': 2, 'layout': m}
      : m;
}

/// JSON without assets and fonts, for undo history.
String snapshot(LayoutDoc doc) => jsonEncode(_docMap(doc, withBinary: false));

/// Rebuilds a document from a snapshot, keeping [doc]'s assets and fonts.
LayoutDoc restore(LayoutDoc doc, String snap) {
  final back = _read(jsonDecode(snap), true, doc.assets);
  back.fonts = doc.fonts;
  return back;
}
