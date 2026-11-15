import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/fonts/font_files.dart';

Uint8List barlow() => File('assets/fonts/barlow-700.ttf').readAsBytesSync();

/// A WOFF 1.0 file made from a TTF: every table deflated when that is smaller.
Uint8List makeWoff(Uint8List ttf) {
  final d = ByteData.sublistView(ttf);
  final n = d.getUint16(4);
  final tables = <(String, int, Uint8List, Uint8List)>[];
  for (var i = 0; i < n; i++) {
    final p = 12 + i * 16;
    final tag = String.fromCharCodes(ttf.sublist(p, p + 4));
    final checksum = d.getUint32(p + 4);
    final data = Uint8List.sublistView(ttf, d.getUint32(p + 8), d.getUint32(p + 8) + d.getUint32(p + 12));
    final z = Uint8List.fromList(zlib.encode(data));
    tables.add((tag, checksum, data, z.length < data.length ? z : data));
  }
  var size = 44 + 20 * n;
  final offsets = <int>[];
  for (final t in tables) {
    offsets.add(size);
    size += (t.$4.length + 3) & ~3;
  }
  final out = Uint8List(size);
  final o = ByteData.sublistView(out);
  out.setRange(0, 4, 'wOFF'.codeUnits);
  o.setUint32(4, d.getUint32(0));
  o.setUint32(8, size);
  o.setUint16(12, n);
  for (var i = 0; i < n; i++) {
    final p = 44 + i * 20;
    final (tag, checksum, orig, stored) = tables[i];
    out.setRange(p, p + 4, tag.codeUnits);
    o.setUint32(p + 4, offsets[i]);
    o.setUint32(p + 8, stored.length);
    o.setUint32(p + 12, orig.length);
    o.setUint32(p + 16, checksum);
    out.setRange(offsets[i], offsets[i] + stored.length, stored);
  }
  return out;
}

void main() {
  test('fontInfo reads Barlow Bold from its own tables', () {
    final info = fontInfo(barlow())!;
    expect(info.family, 'Barlow');
    expect(info.weight, 700);
    expect(info.italic, isFalse);
    expect(info.variable, isFalse);
  });

  test('fontInfo gives null for something that is not a font', () {
    expect(fontInfo(Uint8List.fromList(List.filled(40, 1))), isNull);
    expect(fontInfo(Uint8List(3)), isNull);
  });

  test('a WOFF reads the same way and converts back to a loadable font', () async {
    final woff = makeWoff(barlow());
    expect(isWoff(woff), isTrue);
    final info = fontInfo(woff)!;
    expect(info.family, 'Barlow');
    expect(info.weight, 700);
    final back = woffToSfnt(woff)!;
    final again = fontInfo(back)!;
    expect(again.family, 'Barlow');
    expect(again.weight, 700);
    expect(again.italic, isFalse);
    // Same tables, byte for byte.
    final a = ByteData.sublistView(barlow()), b = ByteData.sublistView(back);
    expect(b.getUint16(4), a.getUint16(4));
    await ui.loadFontFromList(back, fontFamily: 'WoffRoundTrip');
  });

  test('a broken WOFF is not converted', () {
    final woff = makeWoff(barlow());
    expect(woffToSfnt(Uint8List.sublistView(woff, 0, 200)), isNull);
    expect(woffToSfnt(barlow()), isNull);
  });

  test('describeFile reads family, weight and italic from the file name', () {
    final a = describeFile('Montserrat-BoldItalic.ttf');
    expect((a.family, a.weight, a.style), ('Montserrat', 700, 'italic'));
    final b = describeFile('OpenSans-SemiBold.otf');
    expect((b.family, b.weight, b.style), ('Open Sans', 600, 'normal'));
    final c = describeFile('Pacifico.ttf');
    expect((c.family, c.weight, c.style), ('Pacifico', 400, 'normal'));
  });

  test('WOFF2 is refused with the plain words', () {
    final problems = <String>[];
    final faces = facesFromFile('Font.woff2', Uint8List.fromList('wOF2....'.codeUnits + List.filled(40, 0)), problems);
    expect(faces, isEmpty);
    expect(problems.single, contains("WOFF2 font files can't be used on this phone. Use the TTF or OTF file instead."));
  });

  test('a TTF file and a WOFF file give a face each', () {
    final problems = <String>[];
    final ttf = facesFromFile('Barlow-Bold.ttf', barlow(), problems).single;
    expect((ttf.family, ttf.weight, ttf.style, ttf.mime), ('Barlow', 700, 'normal', 'font/ttf'));
    final woff = facesFromFile('Barlow-Bold.woff', makeWoff(barlow()), problems).single;
    expect((woff.family, woff.weight), ('Barlow', 700));
    expect(isWoff(woff.bytes), isFalse);
    expect(problems, isEmpty);
  });

  test('a ZIP prefers the fixed-weight files and skips the variable one', () {
    final zip = Archive()
      ..addFile(ArchiveFile('static/Barlow-Bold.ttf', barlow().length, barlow()))
      ..addFile(ArchiveFile('Barlow[wght].ttf', barlow().length, barlow()))
      ..addFile(ArchiveFile('__MACOSX/._Barlow-Bold.ttf', 4, [1, 2, 3, 4]))
      ..addFile(ArchiveFile('readme.txt', 2, [65, 66]));
    final bytes = Uint8List.fromList(ZipEncoder().encode(zip));
    final problems = <String>[];
    final faces = facesFromFile('Barlow.zip', bytes, problems);
    expect(faces.length, 1);
    expect(faces.single.variable, isFalse);
    expect(problems, isEmpty);
  });

  test('a ZIP with no fonts and a broken ZIP say so', () {
    final zip = Archive()..addFile(ArchiveFile('readme.txt', 2, [65, 66]));
    final p1 = <String>[];
    expect(facesFromFile('x.zip', Uint8List.fromList(ZipEncoder().encode(zip)), p1), isEmpty);
    expect(p1.single, 'x.zip has no font files inside');
    final p2 = <String>[];
    expect(facesFromFile('y.zip', Uint8List.fromList(List.filled(100, 7)), p2), isEmpty);
    expect(p2.single, "y.zip: this ZIP file can't be read");
    final p3 = <String>[];
    expect(facesFromFile('notes.pdf', Uint8List(10), p3), isEmpty);
    expect(p3.single, "notes.pdf isn't a font file");
  });
}
