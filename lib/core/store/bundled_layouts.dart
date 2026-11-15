import 'dart:convert';

import 'package:flutter/services.dart';

import '../model/layout_codec.dart';
import '../model/layout_doc.dart';
import '../model/layout_ops.dart';

/// The office layouts shipped with the app (assets/layouts/layouts.json). Each
/// gets the id `office:<file name up to the first dot>` and has its pins upgraded.
Future<List<LayoutDoc>> loadBundledLayouts() async {
  final list =
      jsonDecode(await rootBundle.loadString('assets/layouts/layouts.json')) as List;
  final out = <LayoutDoc>[];
  for (final entry in list) {
    final file = (entry as Map)['file'] as String;
    try {
      final doc = readLayout(
          jsonDecode(await rootBundle.loadString('assets/layouts/$file')),
          keepIdentity: true);
      doc.id = 'office:${file.split('.').first}';
      upgradePins(doc);
      out.add(doc);
    } catch (_) {
      // A bad bundled file must not stop the others.
    }
  }
  return out;
}
