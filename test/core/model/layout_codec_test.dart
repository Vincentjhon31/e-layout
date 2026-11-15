import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_codec.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/model/layout_ops.dart';

Object? footerJson() =>
    jsonDecode(File('assets/layouts/pio-footer.layout.json').readAsStringSync());

void main() {
  test('reads the PIO footer', () {
    final doc = readLayout(footerJson(), keepIdentity: true);
    expect(doc.elements.length, 9);
    expect(doc.assets.length, 3);
    expect(doc.name, 'PIO footer');
    expect(doc.pinsVersion, 1);
    expect(doc.elements.every((e) => e.pinAuto == null), isTrue);
  });

  test('upgradePins makes everything auto bottom', () {
    final doc = readLayout(footerJson(), keepIdentity: true);
    expect(upgradePins(doc), isTrue);
    expect(doc.elements.every((e) => e.pinAuto == true && e.pin == Pin.bottom), isTrue);
    expect(doc.pinsVersion, 2);
    expect(upgradePins(doc), isFalse);
  });

  test('write/read round trip is stable', () {
    final a = readLayout(footerJson(), keepIdentity: true);
    final j1 = jsonEncode(writeLayout(a));
    final b = readLayout(jsonDecode(j1), keepIdentity: true);
    final j2 = jsonEncode(writeLayout(b));
    final c = readLayout(jsonDecode(j2), keepIdentity: true);
    expect(jsonEncode(writeLayout(c)), j2);
    expect(j2, j1);
  });

  test('envelope is accepted', () {
    final a = readLayout(footerJson(), keepIdentity: true);
    final env = writeLayout(a, envelope: true);
    expect(env['format'], 'pio-photo-layout');
    expect(readLayout(jsonDecode(jsonEncode(env))).elements.length, 9);
  });

  test('bad files fail with the friendly message', () {
    for (final bad in [<String, dynamic>{}, {'version': 1}, null, 5, 'x', []]) {
      expect(() => readLayout(bad),
          throwsA(isA<LayoutFormatException>().having(
              (e) => e.message, 'message', "This file isn't a layout from this tool.")));
    }
  });

  test('width 0, wrong types and absurd values load safely', () {
    final d = readLayout({'version': 2, 'width': 0, 'elements': []});
    expect(d.elements, isEmpty);
    final doc = readLayout({
      'version': 2,
      'elements': [
        {'type': 'shape', 'x': 'abc', 'opacity': 7}
      ]
    });
    expect(doc.elements.single.x, 0);
    expect(doc.elements.single.opacity, 1);
  });

  test('more than 500 elements are cut', () {
    final doc = readLayout({
      'version': 2,
      'elements': List.generate(600, (_) => {'type': 'shape'})
    });
    expect(doc.elements.length, 500);
  });

  test('a doc of width 600 is rescaled by 2; image without asset dropped', () {
    final doc = readLayout({
      'version': 2,
      'width': 600,
      'elements': [
        {'type': 'shape', 'x': 10, 'w': 50, 'h': 20, 'stroke': {'width': 3}},
        {'type': 'image', 'asset': 'nope'},
      ]
    });
    expect(doc.elements.length, 1);
    final e = doc.elements.single;
    expect([e.x, e.w, e.h, e.stroke.width], [20, 100, 40, 6]);
  });

  test('snapshot/restore keeps assets', () {
    final a = readLayout(footerJson(), keepIdentity: true);
    final s = snapshot(a);
    expect(s.contains('base64'), isFalse);
    final b = restore(a, s);
    expect(b.assets.length, 3);
    expect(b.elements.length, 9);
    expect(b.elements.first.id, a.elements.first.id);
  });
}
