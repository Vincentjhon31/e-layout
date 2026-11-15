import 'dart:ui' as ui;

import '../model/layout_doc.dart';
import '../model/layout_ops.dart';
import 'layout_painter.dart';
import 'layout_prep.dart';

/// Output size, photo crop and layout scale for one photo.
class PhotoGeometry {
  const PhotoGeometry(this.w, this.h, this.cropX, this.cropY, this.cropW, this.cropH,
      this.s, this.frameH);
  final int w, h;
  final int cropX, cropY, cropW, cropH;
  final double s, frameH;
}

/// render.js photoGeometry() for a photo of [pw] x [ph] pixels.
PhotoGeometry photoGeometry(int pw, int ph, LayoutDoc? doc) {
  if (doc != null && doc.fit == DocFit.crop) {
    final r = doc.ratio;
    var w = pw, h = ph;
    if (pw / ph > r) {
      w = (ph * r).round();
    } else {
      h = (pw / r).round();
    }
    return PhotoGeometry(w, h, ((pw - w) / 2).round(), ((ph - h) / 2).round(), w, h,
        w / doc.width, doc.width / r);
  }
  final width = doc?.width ?? kDesignW;
  return PhotoGeometry(pw, ph, 0, 0, pw, ph, pw / width, width * ph / pw);
}

/// render.js compose(): draws a photo ([src] may be a reduced copy: [k] source
/// pixels per photo pixel) with the layout on top. [out] is output pixels per
/// photo pixel.
void paintComposite(ui.Canvas canvas, ui.Image src, double k, PhotoGeometry g,
    LayoutDoc? doc, LayoutPrep? prep, double out) {
  final dst = ui.Rect.fromLTWH(0, 0, g.w * out, g.h * out);
  final srcRect =
      ui.Rect.fromLTWH(g.cropX * k, g.cropY * k, g.cropW * k, g.cropH * k);
  final down = dst.width < srcRect.width;
  canvas.drawImageRect(
      src,
      srcRect,
      dst,
      ui.Paint()
        ..isAntiAlias = true
        ..filterQuality = down ? ui.FilterQuality.medium : ui.FilterQuality.high);
  if (doc == null) return;
  final px = g.s * out;
  canvas.save();
  canvas.scale(px, px);
  drawLayout(canvas, doc, prep, g.frameH);
  canvas.restore();
}

/// render.js layoutCanvas(): the layout alone on a transparent background.
Future<ui.Image> renderLayoutImage(LayoutDoc doc, LayoutPrep prep, int widthPx,
    [double? previewRatio]) {
  final frameH = frameHeight(doc, previewRatio);
  final px = widthPx / doc.width;
  final w = widthPx < 1 ? 1 : widthPx;
  final h = (frameH * px).round().clamp(1, 1 << 30);
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.scale(px, px);
  drawLayout(canvas, doc, prep, frameH);
  final pic = rec.endRecording();
  final fut = pic.toImage(w, h);
  fut.whenComplete(pic.dispose);
  return fut;
}
