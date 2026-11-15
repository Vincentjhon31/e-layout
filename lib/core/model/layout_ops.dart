import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'layout_doc.dart';

export 'layout_doc.dart' show uid;

/// model.js frameHeight().
double frameHeight(LayoutDoc doc, [double? previewRatio]) =>
    doc.width /
    (doc.fit == DocFit.crop ? doc.ratio : (previewRatio ?? kRatios['landscape']!));

/// The element's box in design units, for a frame of the given height.
Rect boxOf(LayoutElement el, double frameH) {
  double y;
  var h = el.h;
  switch (el.pin) {
    case Pin.top:
      y = el.top;
    case Pin.bottom:
      y = frameH - el.bottom - el.h;
    case Pin.stretch:
      y = el.top;
      h = math.max(1, frameH - el.top - el.bottom);
    case Pin.center:
      y = frameH / 2 + el.cy - el.h / 2;
  }
  return Rect.fromLTWH(el.x, y, el.w, h);
}

/// Stores a box back into the fields of the element's pin.
void setBox(LayoutElement el, Rect box, double frameH) {
  el.x = box.left;
  el.w = math.max(1, box.width);
  el.h = math.max(1, box.height);
  switch (el.pin) {
    case Pin.top:
      el.top = box.top;
    case Pin.bottom:
      el.bottom = frameH - box.top - el.h;
    case Pin.stretch:
      el.top = box.top;
      el.bottom = frameH - box.top - el.h;
    case Pin.center:
      el.cy = box.top + el.h / 2 - frameH / 2;
  }
}

void setPin(LayoutElement el, Pin pin, double frameH) {
  final box = boxOf(el, frameH);
  el.pin = pin;
  setBox(el, box, frameH);
}

Pin autoPin(Rect box, double frameH) {
  final c = box.top + box.height / 2;
  if (c < frameH * 0.4) return Pin.top;
  if (c > frameH * 0.6) return Pin.bottom;
  return Pin.center;
}

/// The pin a piece should have where it sits now. A shape running from the top
/// edge to the bottom edge stretches.
Pin pinFor(LayoutElement el, Rect box, double frameH) {
  final fullHeight = el.type == ElementType.shape &&
      box.top <= frameH * 0.05 &&
      box.top + box.height >= frameH * 0.95;
  return fullHeight ? Pin.stretch : autoPin(box, frameH);
}

LayoutElement place(LayoutElement el, Rect box, double frameH) {
  el.pin = pinFor(el, box, frameH);
  setBox(el, box, frameH);
  return el;
}

/// After a piece moves: re-pin it to the part of the photo it now sits in,
/// unless the person chose a pin or it belongs to a group.
void autoRepin(LayoutElement el, double frameH) {
  if (el.pinAuto == false || el.group != null) return;
  final box = boxOf(el, frameH);
  final pin = pinFor(el, box, frameH);
  if (pin != el.pin) {
    el.pin = pin;
    setBox(el, box, frameH);
  }
}

/// Layouts made before pins followed their pieces: re-pin every piece once.
bool upgradePins(LayoutDoc doc) {
  if (doc.pinsVersion >= 2) return false;
  final base = frameHeight(doc);
  for (final el in doc.elements) {
    if (el.pinAuto != null) continue;
    if (el.pin == Pin.stretch || doc.fit == DocFit.crop) {
      el.pinAuto = false;
      continue;
    }
    final need = el.pin == Pin.top
        ? el.top + el.h
        : el.pin == Pin.bottom
            ? el.bottom + el.h
            : el.h + 2 * el.cy.abs();
    final fh = math.max(base, need);
    el.pinAuto = true;
    autoRepin(el, fh);
  }
  doc.pinsVersion = 2;
  return true;
}

LayoutElement duplicateElement(LayoutElement el) {
  final copy = el.clone();
  copy.id = uid('e');
  return copy;
}

// ---------- groups ----------

List<LayoutElement> membersOf(LayoutDoc doc, String gid) =>
    doc.elements.where((e) => e.group == gid).toList();

Rect unionBox(List<LayoutElement> list, double frameH) {
  var l = double.infinity, t = double.infinity;
  var r = double.negativeInfinity, b = double.negativeInfinity;
  for (final el in list) {
    final x = boxOf(el, frameH);
    l = math.min(l, x.left);
    t = math.min(t, x.top);
    r = math.max(r, x.right);
    b = math.max(b, x.bottom);
  }
  return Rect.fromLTWH(l, t, r - l, b - t);
}

/// Gives every piece of a group the group's pin.
void groupPin(LayoutDoc doc, String gid, double frameH) {
  final g = doc.groups[gid];
  final members = membersOf(doc, gid);
  if (g == null || members.isEmpty) return;
  final pin = !g.pinAuto ? g.pin : autoPin(unionBox(members, frameH), frameH);
  g.pin = pin;
  for (final el in members) {
    if (el.pin != pin) setPin(el, pin, frameH);
  }
}

String nextGroupName(LayoutDoc doc) {
  final used = doc.groups.values.map((g) => g.name).toSet();
  for (var n = 1;; n++) {
    if (!used.contains('Group $n')) return 'Group $n';
  }
}

/// Puts each group's pieces next to each other (at its topmost piece), drops
/// groups that lost their pieces, and frees the last piece of a group of one.
void cleanGroups(LayoutDoc doc, [double? frameH]) {
  for (final el in doc.elements) {
    if (el.group != null && !doc.groups.containsKey(el.group)) el.group = null;
  }
  for (final gid in doc.groups.keys.toList()) {
    final members = membersOf(doc, gid);
    if (members.length < 2) {
      for (final el in members) {
        el.group = null;
        el.pinAuto = true;
        if (frameH != null) autoRepin(el, frameH);
      }
      doc.groups.remove(gid);
      continue;
    }
    final idx = [for (final m in members) doc.elements.indexOf(m)];
    final top = idx.reduce(math.max);
    if (top - idx.reduce(math.min) + 1 == members.length) continue;
    final rest = doc.elements.where((e) => e.group != gid).toList();
    final below =
        doc.elements.sublist(0, top).where((e) => e.group != gid).length;
    rest.insertAll(below, members);
    doc.elements
      ..clear()
      ..addAll(rest);
  }
}

/// Groups the given pieces. Returns the new group id, or null if fewer than two.
String? makeGroup(LayoutDoc doc, List<String> ids, double frameH) {
  final members = doc.elements.where((e) => ids.contains(e.id)).toList();
  if (members.length < 2) return null;
  final gid = uid('g');
  doc.groups[gid] = GroupInfo(name: nextGroupName(doc));
  for (final el in members) {
    el.group = gid;
  }
  cleanGroups(doc, frameH);
  groupPin(doc, gid, frameH);
  return gid;
}

void ungroup(LayoutDoc doc, String gid, double frameH) {
  for (final el in membersOf(doc, gid)) {
    el.group = null;
    el.pinAuto = true;
    autoRepin(el, frameH);
  }
  doc.groups.remove(gid);
}

// ---------- assets ----------

bool _sameBytes(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Adds a picture; returns the existing id when identical bytes are already there.
String addAsset(LayoutDoc doc,
    {required String name,
    required String mime,
    required Uint8List bytes,
    required int w,
    required int h}) {
  for (final e in doc.assets.entries) {
    if (_sameBytes(e.value.bytes, bytes)) return e.key;
  }
  final id = uid('a');
  doc.assets[id] = LayoutAsset(
      name: name.isEmpty ? 'Image' : name, mime: mime, bytes: bytes, w: w, h: h);
  return id;
}

void pruneAssets(LayoutDoc doc) {
  final used = {
    for (final e in doc.elements)
      if (e.type == ElementType.image) e.asset,
  };
  doc.assets.removeWhere((id, _) => !used.contains(id));
}

/// A layout made from one picture. [placement]: footer, header, center, frame.
LayoutDoc fromImage(String name, LayoutAsset asset, String placement) {
  final doc = LayoutDoc.blank(name);
  final id = addAsset(doc,
      name: asset.name, mime: asset.mime, bytes: asset.bytes, w: asset.w, h: asset.h);
  final el = LayoutElement.create(ElementType.image)
    ..name = name
    ..asset = id
    ..fit = ImageFit.stretch
    ..x = 0
    ..w = kDesignW
    ..pinAuto = false;
  if (placement == 'frame') {
    doc.fit = DocFit.crop;
    doc.ratio = asset.w / asset.h;
    el
      ..pin = Pin.stretch
      ..top = 0
      ..bottom = 0
      ..h = kDesignW / doc.ratio;
  } else if (placement == 'center') {
    el
      ..pin = Pin.center
      ..cy = 0
      ..h = kDesignW * asset.h / asset.w;
  } else {
    el
      ..pin = placement == 'header' ? Pin.top : Pin.bottom
      ..top = 0
      ..bottom = 0
      ..h = kDesignW * asset.h / asset.w;
  }
  doc.elements.add(el);
  return doc;
}

/// One part of a split frame picture. [edge]: top, bottom, left, right.
class FramePart {
  FramePart(this.edge, this.x, this.y, this.w, this.h, this.png);
  final String edge;
  final int x, y, w, h;
  final Uint8List png;
}

const Map<String, String> _partNames = {
  'top': 'Top part',
  'bottom': 'Bottom part',
  'left': 'Left border',
  'right': 'Right border',
};

/// Pieces for the parts of a split frame picture. [box] is where the whole
/// picture sat, in design units, inside a frame of height [frameH].
List<LayoutElement> partsToElements(LayoutDoc doc, String name,
    List<FramePart> parts, int W, int H, Rect box, double frameH) {
  final kx = box.width / W;
  final ky = box.height / H;
  return [
    for (final p in parts)
      () {
        final label = _partNames[p.edge] ?? 'Part';
        final asset = addAsset(doc,
            name: '$name: ${label.toLowerCase()}',
            mime: 'image/png',
            bytes: p.png,
            w: p.w,
            h: p.h);
        final el = LayoutElement.create(ElementType.image)
          ..name = label
          ..asset = asset
          ..fit = ImageFit.stretch
          ..pinAuto = false
          ..pin = p.edge == 'top'
              ? Pin.top
              : p.edge == 'bottom'
                  ? Pin.bottom
                  : Pin.stretch;
        setBox(
            el,
            Rect.fromLTWH(box.left + p.x * kx, box.top + p.y * ky, p.w * kx, p.h * ky),
            frameH);
        return el;
      }(),
  ];
}

/// A layout made from a frame picture that was split into parts.
LayoutDoc fromParts(String name, List<FramePart> parts, int W, int H) {
  final doc = LayoutDoc.blank(name);
  final frameH = kDesignW * H / W;
  doc.elements.addAll(partsToElements(
      doc, name, parts, W, H, Rect.fromLTWH(0, 0, kDesignW, frameH), frameH));
  return doc;
}
