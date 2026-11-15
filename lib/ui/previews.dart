import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/model/layout_doc.dart';
import '../core/model/layout_ops.dart';
import '../core/render/layout_painter.dart';
import '../core/render/layout_prep.dart';
import '../core/render/photo_geometry.dart';
import '../core/render/sample_scene.dart';

/// A photo (or its small copy) with the layout on top, fitted inside the box
/// and centred. Drawn live with the same code as the saved photos.
class CompositePainter extends CustomPainter {
  CompositePainter({
    required this.image,
    required this.photoWidth,
    required this.photoHeight,
    required this.doc,
    required this.prep,
    this.revision = 0,
    this.cover = false,
  });

  final ui.Image image;
  final int photoWidth, photoHeight;
  final LayoutDoc? doc;
  final LayoutPrep? prep;
  final int revision;

  /// Fill the box (cropping) instead of fitting inside it.
  final bool cover;

  @override
  void paint(Canvas canvas, Size size) {
    final g = photoGeometry(photoWidth, photoHeight, doc);
    final fx = size.width / g.w, fy = size.height / g.h;
    final out = cover ? math.max(fx, fy) : math.min(fx, fy);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate((size.width - g.w * out) / 2, (size.height - g.h * out) / 2);
    paintComposite(canvas, image, image.width / photoWidth, g, doc, prep, out);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CompositePainter old) =>
      old.image != image || old.doc != doc || old.prep != prep || old.revision != revision || old.cover != cover;
}

/// A layout drawn on the sample scene, fitted inside the box.
class LayoutThumbPainter extends CustomPainter {
  LayoutThumbPainter({required this.doc, required this.prep, this.revision = 0, this.previewRatio});

  final LayoutDoc doc;
  final LayoutPrep? prep;
  final int revision;
  final double? previewRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final fh = frameHeight(doc, previewRatio);
    final s = math.min(size.width / doc.width, size.height / fh);
    final w = doc.width * s, h = fh * s;
    canvas.save();
    canvas.translate((size.width - w) / 2, (size.height - h) / 2);
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h));
    paintSampleScene(canvas, Size(w, h));
    canvas.scale(s, s);
    drawLayout(canvas, doc, prep, fh);
    canvas.restore();
  }

  @override
  bool shouldRepaint(LayoutThumbPainter old) =>
      old.doc != doc || old.prep != prep || old.revision != revision || old.previewRatio != previewRatio;
}
