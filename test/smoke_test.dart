import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled layouts list has one entry', () async {
    final s = await rootBundle.loadString('assets/layouts/layouts.json');
    expect((jsonDecode(s) as List).length, 1);
  });

  test('font manifest lists 16 layout families plus the Inter UI font', () async {
    final s = await rootBundle.loadString('FontManifest.json');
    final fams = (jsonDecode(s) as List)
        .map((e) => (e as Map)['family'] as String)
        .where((f) => !f.startsWith('packages/'))
        .toList();
    expect(fams.length, 17);
    expect(fams, contains('Inter'));
  });
}
