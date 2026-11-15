import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../core/icons/icon_set.dart';
import '../../../core/model/layout_doc.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/widgets/labeled_slider.dart';
import '../../../ui/widgets/pressable.dart';
import '../../../ui/widgets/segmented.dart';
import '../add_sheets.dart' show IconGlyph;
import '../color_picker.dart';
import '../editor_controller.dart';
import 'panel_widgets.dart';

/// Which kind of shape, and the settings that kind has.
class ShapePanel extends StatelessWidget {
  const ShapePanel({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  static const Map<ShapeKind, String> kinds = {
    ShapeKind.rect: 'Rectangle',
    ShapeKind.ellipse: 'Circle or oval',
    ShapeKind.triangle: 'Triangle',
    ShapeKind.diamond: 'Diamond',
    ShapeKind.polygon: 'Polygon',
    ShapeKind.star: 'Star',
    ShapeKind.arrow: 'Arrow',
    ShapeKind.torn: 'Torn edge',
  };

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final box = c.boxOfEl(el);
    return PanelTabs(
      tabs: {
        'Kind': () => ChipWrap(
          children: [
            for (final e in kinds.entries)
              PanelChip(
                label: e.value,
                on: el.shape == e.key,
                onTap: () => editSelected(c, 'shapekind', (x) => x.shape = e.key),
              ),
          ],
        ),
        'Details': () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (el.shape == ShapeKind.rect)
              LabeledSlider(
                sliderHeight: 36,
                label: 'Corner radius',
                value: el.radius,
                min: 0,
                max: math.max(20, math.min(box.width, box.height) / 2).roundToDouble(),
                onChanged: (v) => editSelected(c, 'radius', (x) => x.radius = v.roundToDouble()),
              ),
            if (el.shape == ShapeKind.polygon)
              LabeledSlider(
                sliderHeight: 36,
                label: 'Sides',
                value: el.sides.toDouble(),
                min: 3,
                max: 12,
                divisions: 9,
                onChanged: (v) => editSelected(c, 'sides', (x) => x.sides = v.round()),
              ),
            if (el.shape == ShapeKind.star) ...[
              LabeledSlider(
                sliderHeight: 36,
                label: 'Points',
                value: el.points.toDouble(),
                min: 3,
                max: 12,
                divisions: 9,
                onChanged: (v) => editSelected(c, 'points', (x) => x.points = v.round()),
              ),
              LabeledSlider(
                sliderHeight: 36,
                label: 'Inner size',
                value: el.inner * 100,
                min: 10,
                max: 95,
                format: (v) => '${v.round()}%',
                onChanged: (v) => editSelected(c, 'inner', (x) => x.inner = v.round() / 100),
              ),
            ],
            if (el.shape == ShapeKind.torn) ...[
              LabeledSlider(
                sliderHeight: 36,
                label: 'Roughness',
                value: el.rough * 100,
                min: 0,
                max: 100,
                format: (v) => '${v.round()}%',
                onChanged: (v) => editSelected(c, 'rough', (x) => x.rough = v.round() / 100),
              ),
              const SizedBox(height: 4),
              PanelButton(
                label: 'Tear again',
                icon: CupertinoIcons.arrow_2_circlepath,
                onTap: () => c.change(() => el.seed = math.Random().nextInt(1000000)),
              ),
            ],
            if (el.shape != ShapeKind.rect &&
                el.shape != ShapeKind.polygon &&
                el.shape != ShapeKind.star &&
                el.shape != ShapeKind.torn)
              const PanelNote('This shape has no more settings.'),
          ],
        ),
      },
    );
  }
}

/// How a picture sits in its box, and its corner radius.
class FitPanel extends StatelessWidget {
  const FitPanel({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final bmp = c.prep.bitmaps[el.asset];
    final box = c.boxOfEl(el);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Segmented<ImageFit>(
          segments: const {ImageFit.contain: 'Whole picture', ImageFit.cover: 'Fill box', ImageFit.stretch: 'Stretch'},
          value: el.fit,
          onChanged: (v) => c.change(() {
            for (final e in c.selection) {
              if (e.type == ElementType.image) e.fit = v;
            }
          }),
        ),
        const SizedBox(height: 4),
        LabeledSlider(
          sliderHeight: 36,
          label: 'Corner radius',
          value: el.radius,
          min: 0,
          max: math.max(20, math.min(box.width, box.height) / 2).roundToDouble(),
          onChanged: (v) => editSelected(c, 'radius', (x) => x.radius = v.roundToDouble()),
        ),
        PanelNote(bmp != null ? '${bmp.width} x ${bmp.height} pixels.' : "This picture couldn't be loaded."),
      ],
    );
  }
}

/// "Make it see-through" for logos on white, and "Fit any photo shape" for
/// whole-frame pictures.
class SeeThroughPanel extends StatefulWidget {
  const SeeThroughPanel({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  State<SeeThroughPanel> createState() => _SeeThroughPanelState();
}

class _SeeThroughPanelState extends State<SeeThroughPanel> {
  double _tolerance = 20;
  bool _busy = false;

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      widget.controller.say("Couldn't change this picture.");
      debugPrint('Picture change failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return PanelTabs(
      tabs: {
        'White background': () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledSlider(
              sliderHeight: 36,
              label: 'How much white to remove',
              value: _tolerance,
              min: 1,
              max: 120,
              onChanged: (v) => setState(() => _tolerance = v.roundToDouble()),
            ),
            PanelButton(
              label: _busy ? 'Working' : 'Make it see-through',
              icon: CupertinoIcons.wand_stars,
              onTap: _busy
                  ? null
                  : () => _run(() async {
                      final ok = await c.makeSeeThrough(widget.el, _tolerance);
                      c.say(ok ? 'The white background is now see-through.' : "This picture couldn't be loaded.");
                    }),
            ),
            const SizedBox(height: 8),
            const PanelNote('For logos saved as JPG: removes the white around the logo and keeps white inside it.'),
          ],
        ),
        'Whole frame': () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            PanelButton(
              label: _busy ? 'Working' : 'Fit any photo shape',
              icon: CupertinoIcons.crop,
              onTap: _busy ? null : () => _run(() => c.splitPicture(widget.el)),
            ),
            const SizedBox(height: 8),
            const PanelNote(
              'For a picture that covers the whole photo with a see-through middle: cuts it into top, bottom and side parts that stay on their edges, so tall and wide photos keep their full size.',
            ),
          ],
        ),
      },
    );
  }
}

/// Which icon, and how thick its lines are.
class IconPanel extends StatelessWidget {
  const IconPanel({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    return PanelTabs(
      tabs: {
        'Icon': () => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final name in IconSet.names)
              Pressable(
                onPressed: () => c.change(() {
                  final now = c.byId(el.id);
                  if (now == null) return;
                  final wasDefault = now.name.endsWith('icon');
                  now.icon = name;
                  if (wasDefault) now.name = '${IconSet.label(name)} icon';
                }),
                semanticLabel: IconSet.label(name),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: name == el.icon ? colors.accent.withValues(alpha: 0.18) : colors.raised,
                    borderRadius: BorderRadius.circular(10),
                    border: name == el.icon ? Border.all(color: colors.accent, width: 2) : null,
                  ),
                  child: CustomPaint(size: const Size(26, 26), painter: IconGlyph(name, colors.text)),
                ),
              ),
          ],
        ),
        'Line': () => LabeledSlider(
          sliderHeight: 36,
          label: 'Line thickness',
          value: el.lineWidth,
          min: 0.5,
          max: 4,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) => editSelected(c, 'linew', (x) => x.lineWidth = (v * 10).round() / 10),
        ),
      },
    );
  }
}

/// The shape behind an icon.
class BadgePanel extends StatelessWidget {
  const BadgePanel({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final bg = el.iconBg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Segmented<IconBgShape>(
          segments: const {IconBgShape.none: 'None', IconBgShape.circle: 'Circle', IconBgShape.square: 'Square'},
          value: bg.shape,
          onChanged: (v) => editSelected(c, 'badge', (x) => x.iconBg.shape = v),
        ),
        const SizedBox(height: 12),
        if (bg.shape != IconBgShape.none)
          ColorEditor(
            color: bg.color,
            alpha: bg.alpha,
            used: usedColors(c.doc),
            onChanged: (hex, a) => editSelected(c, 'badgec', (x) {
              x.iconBg
                ..color = hex
                ..alpha = a;
            }),
          ),
      ],
    );
  }
}
