import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/ui/app_theme.dart';

bool _fontsLoaded = false;

/// Registers every font in FontManifest.json (layout fonts, Inter and the
/// Cupertino icon font) so goldens show real type instead of boxes.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final fam in manifest) {
    final name = (fam as Map)['family'] as String;
    final loader = FontLoader(name);
    for (final f in fam['fonts'] as List) {
      loader.addFont(rootBundle.load((f as Map)['asset'] as String));
    }
    await loader.load();
  }
  _fontsLoaded = true;
}

/// A phone: 390x844 points at 2x (or [size]).
void setPhone(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// Wraps [child] in the app theme for a golden.
Widget themed(Widget child, Brightness brightness) => CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(brightness),
      home: child,
    );
