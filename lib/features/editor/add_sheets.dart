import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../core/icons/icon_set.dart';
import '../../core/model/layout_doc.dart';
import '../../platform/photo_picker.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/sheet_scaffold.dart';
import '../../ui/widgets/toast.dart';
import 'editor_controller.dart';

/// "Text": a few starting styles.
Future<void> showAddText(BuildContext context, EditorController c) {
  return showAppSheet<void>(
    context,
    (ctx) => SheetScaffold(
      title: 'Add text',
      child: Column(
        children: [
          for (final p in kTextPresets)
            _TextRow(
              preset: p,
              onTap: () {
                Navigator.pop(ctx);
                c.addText(p);
              },
            ),
        ],
      ),
    ),
  );
}

class _TextRow extends StatelessWidget {
  const _TextRow({required this.preset, required this.onTap});
  final TextPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final big = preset.weight >= 700;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onPressed: onTap,
        semanticLabel: preset.label,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: colors.cardIn(context), borderRadius: BorderRadius.circular(AppMetrics.cardRadius)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  preset.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: preset.font,
                    fontSize: big ? 22 : 19,
                    fontWeight: FontWeight.values[(preset.weight ~/ 100 - 1).clamp(0, 8)],
                    color: colors.text,
                  ),
                ),
              ),
              Icon(CupertinoIcons.plus_circle, size: 22, color: colors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Shape": the shapes of the web editor.
Future<void> showAddShape(BuildContext context, EditorController c) {
  return showAppSheet<void>(
    context,
    (ctx) => SheetScaffold(
      title: 'Add a shape',
      child: _Grid(
        children: [
          for (final p in kShapePresets)
            _GridTile(
              label: p.label,
              glyph: CustomPaint(size: const Size(40, 40), painter: _ShapeGlyph(p, AppColors.of(ctx).accent)),
              onTap: () {
                Navigator.pop(ctx);
                c.addShape(p);
              },
            ),
        ],
      ),
    ),
  );
}

/// "Icon": the 22 icons of the web editor.
Future<void> showAddIcon(BuildContext context, EditorController c) {
  return showAppSheet<void>(
    context,
    (ctx) => SheetScaffold(
      title: 'Add an icon',
      child: _Grid(
        children: [
          for (final name in IconSet.names)
            _GridTile(
              label: IconSet.label(name),
              glyph: CustomPaint(size: const Size(32, 32), painter: IconGlyph(name, AppColors.of(ctx).text)),
              onTap: () {
                Navigator.pop(ctx);
                c.addIcon(name);
              },
            ),
        ],
      ),
    ),
  );
}

/// "Picture": a logo or any picture from the phone's files.
Future<void> addPictureFromFiles(BuildContext context, EditorController c, PhotoPicker picker) async {
  try {
    final files = await picker.pickFiles(extensions: ['png', 'jpg', 'jpeg', 'webp']);
    for (final f in files) {
      await c.addPicture(f.name, await f.readBytes());
    }
  } catch (e) {
    debugPrint("Couldn't add the picture: $e");
    if (context.mounted) showToast(context, "Couldn't open that picture.", icon: CupertinoIcons.exclamationmark_circle);
  }
}

/// "Replace": another picture in the same space.
Future<void> replacePictureFromFiles(
  BuildContext context,
  EditorController c,
  LayoutElement el,
  PhotoPicker picker,
) async {
  try {
    final files = await picker.pickFiles(extensions: ['png', 'jpg', 'jpeg', 'webp']);
    if (files.isEmpty) return;
    await c.replacePicture(el, files.first.name, await files.first.readBytes());
  } catch (e) {
    debugPrint("Couldn't replace the picture: $e");
    if (context.mounted) showToast(context, "Couldn't open that picture.", icon: CupertinoIcons.exclamationmark_circle);
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final cols = box.maxWidth >= 360 ? 4 : 3;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      },
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.label, required this.glyph, required this.onTap});
  final String label;
  final Widget glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Pressable(
      onPressed: onTap,
      semanticLabel: label,
      child: Container(
        height: 86,
        decoration: BoxDecoration(color: colors.cardIn(context), borderRadius: BorderRadius.circular(AppMetrics.cardRadius)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 40, child: Center(child: glyph)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: colors.secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small drawing of an icon from the icon set.
class IconGlyph extends CustomPainter {
  IconGlyph(this.name, this.color);
  final String name;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    for (final part in IconSet.parts(name)) {
      canvas.drawPath(
        part.path,
        Paint()
          ..color = color
          ..style = part.fill ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(IconGlyph old) => old.name != name || old.color != color;
}

class _ShapeGlyph extends CustomPainter {
  _ShapeGlyph(this.preset, this.color);
  final ShapePreset preset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final r = Offset.zero & size;
    if (preset.band != null) {
      final band = preset.band == 'header'
          ? Rect.fromLTWH(2, 6, size.width - 4, 12)
          : Rect.fromLTWH(2, size.height - 20, size.width - 4, 14);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(2, 2, size.width - 4, size.height - 4), const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: 0.4),
      );
      if (preset.band == 'torn') {
        final path = Path()..moveTo(band.left, band.top + 3);
        for (var x = band.left; x < band.right; x += 5) {
          path.lineTo(x + 2.5, band.top + (((x - band.left) ~/ 5).isEven ? 0 : 4));
        }
        path
          ..lineTo(band.right, band.bottom)
          ..lineTo(band.left, band.bottom)
          ..close();
        canvas.drawPath(path, paint);
      } else {
        canvas.drawRect(band, paint);
      }
      return;
    }
    switch (preset.shape) {
      case ShapeKind.ellipse:
        canvas.drawOval(r.deflate(4), paint);
      case ShapeKind.triangle:
        canvas.drawPath(
          Path()
            ..moveTo(size.width / 2, 5)
            ..lineTo(size.width - 4, size.height - 6)
            ..lineTo(4, size.height - 6)
            ..close(),
          paint,
        );
      case ShapeKind.diamond:
        canvas.drawPath(
          Path()
            ..moveTo(size.width / 2, 3)
            ..lineTo(size.width - 3, size.height / 2)
            ..lineTo(size.width / 2, size.height - 3)
            ..lineTo(3, size.height / 2)
            ..close(),
          paint,
        );
      case ShapeKind.polygon:
        canvas.drawPath(_poly(size, preset.sides ?? 6, false, 0), paint);
      case ShapeKind.star:
        canvas.drawPath(_poly(size, preset.points ?? 5, true, preset.inner ?? 0.45), paint);
      case ShapeKind.arrow:
        canvas.drawPath(
          Path()
            ..moveTo(3, size.height * 0.36)
            ..lineTo(size.width * 0.58, size.height * 0.36)
            ..lineTo(size.width * 0.58, size.height * 0.16)
            ..lineTo(size.width - 3, size.height / 2)
            ..lineTo(size.width * 0.58, size.height * 0.84)
            ..lineTo(size.width * 0.58, size.height * 0.64)
            ..lineTo(3, size.height * 0.64)
            ..close(),
          paint,
        );
      default:
        if (preset.h <= 10) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(2, size.height / 2 - 2, size.width - 4, 4), const Radius.circular(2)),
            paint,
          );
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(3, 8, size.width - 6, size.height - 16),
              Radius.circular(preset.radius > 0 ? 8 : 2),
            ),
            paint,
          );
        }
    }
  }

  Path _poly(Size size, int n, bool star, double inner) {
    final c = size.center(Offset.zero);
    final rad = size.width / 2 - 3;
    final path = Path();
    final steps = star ? n * 2 : n;
    for (var i = 0; i < steps; i++) {
      final rr = star && i.isOdd ? rad * inner : rad;
      final a = -math.pi / 2 + i * 2 * math.pi / steps;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_ShapeGlyph old) => old.preset != preset || old.color != color;
}
