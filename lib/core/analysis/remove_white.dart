import 'dart:typed_data';

/// Port of editor.js `removeWhite`: makes the white that is connected to the
/// picture's edges see-through, edits [rgba] (straight alpha) in place and
/// returns how many pixels were cleared. White enclosed by the artwork stays.
///
/// [tolerance] is how far from pure white a pixel may be, per channel on
/// average (the JS multiplies it by 3 and compares the channel sum).
int removeWhitePixels(Uint8List rgba, int w, int h, double tolerance) {
  final tol = tolerance * 3;
  bool near(int i) => 765 - rgba[i] - rgba[i + 1] - rgba[i + 2] <= tol && rgba[i + 3] > 0;

  final seen = Uint8List(w * h); // 1 = visited, 2 = white and connected to an edge
  final stack = <int>[];
  for (var x = 0; x < w; x++) {
    stack
      ..add(x)
      ..add((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    stack
      ..add(y * w)
      ..add(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    if (seen[p] != 0) continue;
    seen[p] = 1;
    if (!near(p * 4)) continue;
    seen[p] = 2;
    final x = p % w;
    if (x > 0) stack.add(p - 1);
    if (x < w - 1) stack.add(p + 1);
    if (p >= w) stack.add(p - w);
    if (p < w * (h - 1)) stack.add(p + w);
  }

  var cleared = 0;
  for (var p = 0; p < w * h; p++) {
    if (seen[p] == 2) {
      rgba[p * 4 + 3] = 0;
      cleared++;
      continue;
    }
    // Soften the edge: partly white pixels next to removed ones become partly clear.
    final x = p % w;
    final nb = (x > 0 && seen[p - 1] == 2) ||
        (x < w - 1 && seen[p + 1] == 2) ||
        (p >= w && seen[p - w] == 2) ||
        (p < w * (h - 1) && seen[p + w] == 2);
    if (nb) {
      final i = p * 4;
      final white = (rgba[i] + rgba[i + 1] + rgba[i + 2]) / 765;
      final k = (1 - (white - 0.6) / 0.4).clamp(0.15, 1.0);
      rgba[i + 3] = (rgba[i + 3] * k).round();
    }
  }
  return cleared;
}
