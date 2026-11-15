import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/model/layout_ops.dart';

LayoutElement el(ElementType t, {Pin pin = Pin.center}) =>
    LayoutElement.create(t)..pin = pin;

void main() {
  for (final frameH in [800.0, 1600.0]) {
    for (final pin in Pin.values) {
      test('boxOf/setBox round trip pin=$pin frameH=$frameH', () {
        final e = el(ElementType.shape, pin: pin)
          ..x = 30
          ..w = 200
          ..h = 100
          ..top = 40
          ..bottom = 60
          ..cy = 25;
        final box = boxOf(e, frameH);
        final copy = e.clone();
        setBox(copy, box, frameH);
        expect(copy.top, closeTo(e.top, 1e-9));
        expect(copy.bottom, closeTo(e.bottom, 1e-9));
        expect(copy.cy, closeTo(e.cy, 1e-9));
        if (pin == Pin.bottom) {
          expect(box.top, frameH - e.bottom - e.h);
        }
        if (pin == Pin.stretch) {
          expect(box.height, frameH - e.top - e.bottom);
        }
      });
    }
  }

  test('autoPin thresholds', () {
    expect(autoPin(const Rect.fromLTWH(0, 0, 10, 100), 1000), Pin.top);
    expect(autoPin(const Rect.fromLTWH(0, 800, 10, 100), 1000), Pin.bottom);
    expect(autoPin(const Rect.fromLTWH(0, 450, 10, 100), 1000), Pin.center);
  });

  test('pinFor: stretch for full-height shape, never for text', () {
    const box = Rect.fromLTWH(0, 0, 50, 800);
    expect(pinFor(el(ElementType.shape), box, 800), Pin.stretch);
    expect(pinFor(el(ElementType.text), box, 800), isNot(Pin.stretch));
  });

  test('makeGroup gathers non-adjacent pieces and pins them together', () {
    final doc = LayoutDoc.blank();
    final a = el(ElementType.shape)..name = 'a';
    final b = el(ElementType.shape)..name = 'b';
    final c = el(ElementType.shape)..name = 'c';
    final d = el(ElementType.shape)..name = 'd';
    doc.elements.addAll([a, b, c, d]);
    final gid = makeGroup(doc, [a.id, c.id], 800)!;
    final names = doc.elements.map((e) => e.name).toList();
    expect(names, ['b', 'a', 'c', 'd']);
    expect(a.group, gid);
    expect(c.group, gid);
    expect(a.pin, c.pin);
  });

  test('cleanGroups frees a group of one', () {
    final doc = LayoutDoc.blank();
    final a = el(ElementType.shape);
    final b = el(ElementType.shape);
    doc.elements.addAll([a, b]);
    final gid = makeGroup(doc, [a.id, b.id], 800)!;
    doc.elements.remove(b);
    cleanGroups(doc, 800);
    expect(a.group, isNull);
    expect(doc.groups.containsKey(gid), isFalse);
  });

  test('addAsset reuses identical bytes; pruneAssets drops unused', () {
    final doc = LayoutDoc.blank();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final id1 = addAsset(doc, name: 'x', mime: 'image/png', bytes: bytes, w: 1, h: 1);
    final id2 = addAsset(doc,
        name: 'y', mime: 'image/png', bytes: Uint8List.fromList([1, 2, 3]), w: 1, h: 1);
    expect(id2, id1);
    pruneAssets(doc);
    expect(doc.assets, isEmpty);
  });
}
