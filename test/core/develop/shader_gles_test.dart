import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/develop/shader_developer.dart';

// Impeller's OpenGL ES backend stores images it drew (render targets) bottom
// up, unlike images uploaded from a decoder; only its own drawing code
// corrects for that (see the ImageFilter.shader docs in dart:ui). Desktop and
// test renderers don't do this, so no pixel test here can catch an
// upside-down photo on such phones. These guard the two halves of the fix.
void main() {
  test('develop.frag flips its texture reads on OpenGL ES, not the position', () {
    final src = File('shaders/develop.frag').readAsStringSync();
    final flip = RegExp(
        r'#ifdef\s+IMPELLER_TARGET_OPENGLES\s+uv\.y\s*=\s*1\.0\s*-\s*uv\.y\s*;\s*#endif');
    final m = flip.firstMatch(src);
    expect(m, isNotNull, reason: 'GLES flip of the texture reads is missing');
    expect(src.indexOf('texture(uSrc, uv)'), greaterThan(m!.end),
        reason: 'the flip must come before the first photo read');
    expect(src, isNot(contains('frag.y = uSize.y - frag.y')),
        reason: 'the position (vignette, grain, tiles) must not flip');
  });

  testWidgets('the shader always samples a drawn copy of the source, made once per photo',
      (tester) async {
    await tester.runAsync(() async {
      final dev = await ShaderDeveloper.load();
      final px = Uint8List(16 * 16 * 4);
      for (var i = 0; i < px.length; i += 4) {
        px[i] = 200;
        px[i + 1] = 120;
        px[i + 2] = 60;
        px[i + 3] = 255;
      }
      final src = await imageFromRgba(px, 16, 16);
      final s = EditSettings.resolve([
        SettingsPatch(values: {Setting.exposure: 0.5}),
      ]);
      final a = await dev.develop(src, s);
      final b = await dev.develop(src, s);
      expect(dev.debugDrawnCopies, 1);
      a.dispose();
      b.dispose();
      dev.clearCache();
      src.dispose();
    });
  });
}
