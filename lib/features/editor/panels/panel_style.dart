import 'package:flutter/cupertino.dart';

import '../../../core/model/layout_doc.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/widgets/labeled_slider.dart';
import '../color_picker.dart';
import '../editor_controller.dart';
import 'panel_widgets.dart';

class OutlinePanel extends StatelessWidget {
  const OutlinePanel({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LabeledSlider(
          sliderHeight: 36,
          label: 'Thickness',
          value: el.stroke.width,
          min: 0,
          max: 40,
          format: (v) => v == 0 ? 'None' : v.toStringAsFixed(1),
          onChanged: (v) => editSelected(c, 'strokew', (e) => e.stroke.width = (v * 2).round() / 2),
        ),
        if (el.stroke.width > 0)
          ColorEditor(
            color: el.stroke.color,
            alpha: el.stroke.alpha,
            used: usedColors(c.doc),
            onChanged: (hex, a) => editSelected(c, 'strokec', (e) {
              e.stroke
                ..color = hex
                ..alpha = a;
            }),
          ),
      ],
    );
  }
}

class ShadowPanel extends StatelessWidget {
  const ShadowPanel({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    final s = el.shadow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Shadow', style: AppText.body.copyWith(color: colors.text)),
            ),
            CupertinoSwitch(
              value: s.on,
              activeTrackColor: colors.accent,
              onChanged: (v) => editSelected(c, 'shadowon', (e) => e.shadow.on = v),
            ),
          ],
        ),
        if (s.on)
          PanelTabs(
            tabs: {
              'Size': () => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LabeledSlider(
                    sliderHeight: 36,
                    label: 'Blur',
                    value: s.blur,
                    min: 0,
                    max: 60,
                    onChanged: (v) => editSelected(c, 'shadowblur', (e) => e.shadow.blur = v.roundToDouble()),
                  ),
                  LabeledSlider(
                    sliderHeight: 36,
                    label: 'Across',
                    value: s.x,
                    min: -40,
                    max: 40,
                    onChanged: (v) => editSelected(c, 'shadowx', (e) => e.shadow.x = v.roundToDouble()),
                  ),
                  LabeledSlider(
                    sliderHeight: 36,
                    label: 'Down',
                    value: s.y,
                    min: -40,
                    max: 40,
                    onChanged: (v) => editSelected(c, 'shadowy', (e) => e.shadow.y = v.roundToDouble()),
                  ),
                ],
              ),
              'Colour': () => ColorEditor(
                color: s.color,
                alpha: s.alpha,
                used: usedColors(c.doc),
                onChanged: (hex, a) => editSelected(c, 'shadowc', (e) {
                  e.shadow
                    ..color = hex
                    ..alpha = a;
                }),
              ),
            },
          ),
      ],
    );
  }
}

const Map<String, String> kBlendNames = {
  'source-over': 'Normal',
  'multiply': 'Multiply',
  'screen': 'Screen',
  'overlay': 'Overlay',
  'darken': 'Darken',
  'lighten': 'Lighten',
  'color-dodge': 'Colour dodge',
  'color-burn': 'Colour burn',
  'hard-light': 'Hard light',
  'soft-light': 'Soft light',
  'difference': 'Difference',
  'exclusion': 'Exclusion',
  'hue': 'Hue',
  'saturation': 'Saturation',
  'color': 'Colour',
  'luminosity': 'Luminosity',
};

/// Opacity, and the blend mode (how the piece mixes with the photo under it).
class OpacityPanel extends StatelessWidget {
  const OpacityPanel({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    return PanelTabs(
      tabs: {
        'Opacity': () => LabeledSlider(
          sliderHeight: 36,
          label: 'Opacity',
          value: el.opacity * 100,
          min: 0,
          max: 100,
          format: (v) => '${v.round()}%',
          onChanged: (v) => editSelected(controller, 'opacity', (e) => e.opacity = v.round() / 100),
        ),
        'Blending': () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ChipWrap(
              children: [
                for (final b in kBlends)
                  PanelChip(
                    label: kBlendNames[b] ?? b,
                    on: el.blend == b,
                    onTap: () => controller.change(() {
                      for (final e in controller.selection) {
                        e.blend = b;
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const PanelNote('How the piece mixes with the photo under it.'),
          ],
        ),
      },
    );
  }
}

class EffectsPanel extends StatelessWidget {
  const EffectsPanel({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final fx = el.effects;
    final plain = fx.blur == 0 && fx.brightness == 100 && fx.contrast == 100 && fx.saturate == 100 && fx.grayscale == 0;
    String pct(double v) => '${v.round()}%';
    return PanelTabs(
      tabs: {
        'Blur': () => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledSlider(
              sliderHeight: 36,
              label: 'Blur',
              value: fx.blur,
              min: 0,
              max: 40,
              format: (v) => v.toStringAsFixed(1),
              onChanged: (v) => editSelected(c, 'fxblur', (e) => e.effects.blur = (v * 2).round() / 2),
            ),
            LabeledSlider(
              sliderHeight: 36,
              label: 'Black and white',
              value: fx.grayscale,
              min: 0,
              max: 100,
              format: pct,
              onChanged: (v) => editSelected(c, 'fxgray', (e) => e.effects.grayscale = v.roundToDouble()),
            ),
            const SizedBox(height: 4),
            PanelButton(label: 'Reset effects', onTap: plain ? null : () => _reset(c)),
          ],
        ),
        'Light': () => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledSlider(
              sliderHeight: 36,
              label: 'Brightness',
              value: fx.brightness,
              min: 0,
              max: 200,
              format: pct,
              onChanged: (v) => editSelected(c, 'fxbright', (e) => e.effects.brightness = v.roundToDouble()),
            ),
            LabeledSlider(
              sliderHeight: 36,
              label: 'Contrast',
              value: fx.contrast,
              min: 0,
              max: 200,
              format: pct,
              onChanged: (v) => editSelected(c, 'fxcontrast', (e) => e.effects.contrast = v.roundToDouble()),
            ),
            LabeledSlider(
              sliderHeight: 36,
              label: 'Saturation',
              value: fx.saturate,
              min: 0,
              max: 200,
              format: pct,
              onChanged: (v) => editSelected(c, 'fxsat', (e) => e.effects.saturate = v.roundToDouble()),
            ),
          ],
        ),
      },
    );
  }

  static void _reset(EditorController c) => editSelected(c, 'fxreset', (e) {
    e.effects
      ..blur = 0
      ..brightness = 100
      ..contrast = 100
      ..saturate = 100
      ..grayscale = 0;
  });
}
