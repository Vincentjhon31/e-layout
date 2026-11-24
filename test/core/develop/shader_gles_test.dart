import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Impeller's OpenGL ES backend reverses the y axis of FlutterFragCoord
// (see the ImageFilter.shader docs in dart:ui). Desktop and test renderers
// don't, so no pixel test here can catch an upside-down photo on such phones.
// This guards that the shader flips the fragment position itself on GLES,
// before anything (sampling, vignette, grain, tile origin) uses it.
void main() {
  test('develop.frag flips the fragment position on OpenGL ES before using it', () {
    final src = File('shaders/develop.frag').readAsStringSync();
    final flip = RegExp(
        r'#ifdef\s+IMPELLER_TARGET_OPENGLES\s+frag\.y\s*=\s*uSize\.y\s*-\s*frag\.y\s*;\s*#endif');
    final m = flip.firstMatch(src);
    expect(m, isNotNull, reason: 'GLES y-flip of frag is missing');
    // It must come before the first use of frag.
    final firstUse = src.indexOf('frag / uSize');
    expect(firstUse, greaterThan(m!.end));
  });
}
