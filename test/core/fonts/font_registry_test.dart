import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/fonts/font_registry.dart';
import 'package:pio_photo_layout/core/model/layout_codec.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';

void main() {
  final r = FontRegistry.instance;
  test('weights and kinds', () {
    expect(r.builtIn.length, 16);
    expect(r.weightsFor('Barlow'), [400, 500, 600, 700, 800]);
    expect(r.nearestWeight('Oswald', 800), 600);
    expect(r.nearestWeight('Oswald', 500), 400);
    expect(r.kind('Comic Sans MS'), 'unknown');
    expect(r.kind('Pacifico'), 'built-in');
    expect(r.weightsFor('Whatever'), [400, 700]);
  });
  test('missing', () {
    final footer = readLayout(
        jsonDecode(File('assets/layouts/pio-footer.layout.json').readAsStringSync()));
    expect(r.missing(footer), isEmpty);
    final doc = LayoutDoc.blank()
      ..elements.add(LayoutElement.create(ElementType.text)..font = 'Nope Sans');
    expect(r.missing(doc), ['Nope Sans']);
  });
}
