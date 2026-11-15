import 'dart:math' as math;
import 'dart:ui' as ui;

/// editor.js sampleCanvas(): a made-up landscape (sky, clouds, hills) used
/// to preview layouts without a real photo. Drawn 1200x1200 and scaled to
/// cover [size], centred, like the editor does.
void paintSampleScene(ui.Canvas canvas, ui.Size size) {
  final k = math.max(size.width / 1200, size.height / 1200);
  canvas.save();
  canvas.clipRect(ui.Offset.zero & size);
  canvas.translate((size.width - 1200 * k) / 2, (size.height - 1200 * k) / 2);
  canvas.scale(k, k);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 1200, 1200),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset.zero,
        const ui.Offset(0, 1200),
        const [ui.Color(0xFF9CC3DE), ui.Color(0xFFD9E6EC), ui.Color(0xFF9DB58A), ui.Color(0xFF5E7F55)],
        const [0, 0.55, 0.56, 1],
      ),
  );
  final cloud = ui.Paint()..color = const ui.Color.fromRGBO(255, 255, 255, 0.55);
  for (final (x, y, r) in const [(260.0, 260.0, 70.0), (340.0, 240.0, 90.0), (430.0, 270.0, 60.0), (860.0, 180.0, 60.0), (930.0, 160.0, 80.0)]) {
    canvas.drawCircle(ui.Offset(x, y), r, cloud);
  }
  final hill = ui.Path()
    ..moveTo(0, 700)
    ..quadraticBezierTo(300, 560, 640, 690)
    ..quadraticBezierTo(940, 790, 1200, 640)
    ..lineTo(1200, 1200)
    ..lineTo(0, 1200)
    ..close();
  canvas.drawPath(hill, ui.Paint()..color = const ui.Color(0xFF7C9A6E));
  canvas.restore();
}

/// editor.js checker(): the see-through background.
void paintChecker(ui.Canvas canvas, ui.Size size, double cell) {
  canvas.drawRect(ui.Offset.zero & size, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  final p = ui.Paint()..color = const ui.Color(0xFFE3E8EE);
  for (var y = 0.0; y < size.height; y += cell) {
    final row = (y / cell).floor();
    for (var x = (row % 2) * cell; x < size.width; x += cell * 2) {
      canvas.drawRect(ui.Rect.fromLTWH(x, y, cell, cell), p);
    }
  }
}

/// The sample scene as a picture of [w] x [h] pixels (used as a stand-in photo).
Future<ui.Image> sampleSceneImage(int w, int h) {
  final rec = ui.PictureRecorder();
  paintSampleScene(ui.Canvas(rec), ui.Size(w.toDouble(), h.toDouble()));
  final pic = rec.endRecording();
  final f = pic.toImage(w, h);
  f.whenComplete(pic.dispose);
  return f;
}
