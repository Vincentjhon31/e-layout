import 'package:flutter/cupertino.dart';

import '../../../core/model/layout_doc.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/widgets/labeled_slider.dart';
import '../../../ui/widgets/pressable.dart';
import '../../../ui/widgets/segmented.dart';
import '../color_picker.dart';
import '../editor_controller.dart';
import 'panel_widgets.dart';

/// Fill of a shape, colour of a text or an icon: none, solid, gradient or radial.
class ColorPanel extends StatelessWidget {
  const ColorPanel({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final fill = el.fill;
    final canBeNone = el.type == ElementType.shape || fill.type == FillType.none;
    final gradient = fill.type == FillType.linear || fill.type == FillType.radial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Segmented<FillType>(
          segments: {
            if (canBeNone) FillType.none: 'None',
            FillType.solid: 'Solid',
            FillType.linear: 'Gradient',
            FillType.radial: 'Radial',
          },
          value: fill.type,
          onChanged: c.setFillType,
        ),
        const SizedBox(height: 12),
        if (gradient)
          GradientEditor(controller: c, el: el)
        else if (fill.type == FillType.solid)
          ColorEditor(
            color: fill.color,
            alpha: fill.alpha,
            used: usedColors(c.doc),
            onChanged: (hex, a) => editSelected(c, 'fill', (e) {
              e.fill
                ..type = FillType.solid
                ..color = hex
                ..alpha = a;
            }),
          )
        else
          Text('No fill.', style: AppText.subhead.copyWith(color: AppColors.of(context).secondary)),
      ],
    );
  }
}

/// Edits one piece's gradient: a bar with its colour stops (2 to 8), the
/// position of the chosen stop, its colour, and the angle of a linear one.
class GradientEditor extends StatefulWidget {
  const GradientEditor({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  State<GradientEditor> createState() => _GradientEditorState();
}

class _GradientEditorState extends State<GradientEditor> {
  int _stop = 0;

  void _edit(String key, void Function(Fill f) fn) {
    final c = widget.controller;
    c.change(() {
      final now = c.byId(widget.el.id);
      if (now != null) fn(now.fill);
    }, '$key:${widget.el.id}');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final colors = AppColors.of(context);
    final f = widget.el.fill;
    final stops = f.stops;
    final i = _stop.clamp(0, stops.length - 1);
    final s = stops[i];
    final sorted = [...stops]..sort((a, b) => a.at.compareTo(b.at));
    final bar = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.separator, width: 0.5),
        gradient: LinearGradient(
          colors: [for (final g in sorted) colorOfHex(g.color).withValues(alpha: g.alpha)],
          stops: [for (final g in sorted) g.at.clamp(0.0, 1.0)],
        ),
      ),
      child: const SizedBox(height: 28),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: LayoutBuilder(
            builder: (context, box) {
              const m = 14.0;
              final w = box.maxWidth - m * 2;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(left: m, right: m, top: 0, child: bar),
                  for (var k = 0; k < stops.length; k++)
                    Positioned(
                      left: m + stops[k].at.clamp(0.0, 1.0) * w - 14,
                      top: 14,
                      child: Pressable(
                        onPressed: () => setState(() => _stop = k),
                        semanticLabel: 'Stop ${k + 1}',
                        child: Container(
                          width: 28,
                          height: 30,
                          alignment: Alignment.center,
                          child: Container(
                            width: k == i ? 24 : 20,
                            height: k == i ? 24 : 20,
                            decoration: BoxDecoration(
                              color: colorOfHex(stops[k].color),
                              shape: BoxShape.circle,
                              border: Border.all(color: k == i ? colors.accent : colors.card, width: 3),
                              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 3)],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        PanelTabs(
          tabs: {
            'Stops': () => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LabeledSlider(
                  sliderHeight: 36,
                  label: 'Position of stop ${i + 1} of ${stops.length}',
                  value: s.at * 100,
                  min: 0,
                  max: 100,
                  format: (v) => '${v.round()}%',
                  onChanged: (v) => _edit('stopat', (f) => f.stops[i].at = v.round() / 100),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: PanelButton(
                        label: 'Add a stop',
                        icon: CupertinoIcons.plus,
                        onTap: stops.length < 8
                            ? () {
                                c.addGradientStop(widget.el);
                                setState(() => _stop = widget.controller.byId(widget.el.id)!.fill.stops.length - 1);
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PanelButton(
                        label: 'Remove stop',
                        icon: CupertinoIcons.minus,
                        destructive: true,
                        onTap: stops.length > 2
                            ? () {
                                c.removeGradientStop(widget.el, i);
                                setState(() => _stop = 0);
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            'Colour': () => ColorEditor(
              key: ValueKey('stop-$i'),
              color: s.color,
              alpha: s.alpha,
              used: usedColors(c.doc),
              onChanged: (hex, a) => _edit('stopcolor$i', (f) {
                f.stops[i]
                  ..color = hex
                  ..alpha = a;
              }),
            ),
            if (f.type == FillType.linear)
              'Angle': () => LabeledSlider(
                sliderHeight: 36,
                label: 'Angle',
                value: f.angle,
                min: -360,
                max: 360,
                format: (v) => '${v.round()}°',
                onChanged: (v) => _edit('angle', (f) => f.angle = v.roundToDouble()),
              ),
          },
        ),
      ],
    );
  }
}
