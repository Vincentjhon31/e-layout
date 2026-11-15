import 'package:flutter/cupertino.dart';

import '../../../core/fonts/font_registry.dart';
import '../../../core/model/layout_doc.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/widgets/labeled_slider.dart';
import '../../../ui/widgets/pressable.dart';
import '../../../ui/widgets/segmented.dart';
import '../editor_controller.dart';
import 'panel_widgets.dart';

/// Height of one font row in the list; the list shows exactly three.
const double kFontRow = 48;

/// The type settings of one text, in three pages so each one fits the panel
/// without scrolling: Font (the list), Style (weight, italic, capitals,
/// alignment) and Size (size, letter spacing, line height).
class FontPanel extends StatelessWidget {
  const FontPanel({super.key, required this.controller, required this.el, this.onMoreFonts});
  final EditorController controller;
  final LayoutElement el;

  /// Opens the fonts screen ("More fonts"); the row is left out when null.
  final VoidCallback? onMoreFonts;

  @override
  Widget build(BuildContext context) {
    return PanelTabs(
      tabs: {
        'Font': () => _FontList(controller: controller, el: el, onMoreFonts: onMoreFonts),
        'Style': () => _StylePage(controller: controller, el: el),
        'Size': () => _SizePage(controller: controller, el: el),
      },
    );
  }
}

class _FontList extends StatelessWidget {
  const _FontList({required this.controller, required this.el, this.onMoreFonts});
  final EditorController controller;
  final LayoutElement el;
  final VoidCallback? onMoreFonts;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    final reg = FontRegistry.instance;
    final families = [for (final f in reg.builtIn) f.family];
    final extra = onMoreFonts != null ? 1 : 0;
    return SizedBox(
      height: kFontRow * 3,
      child: ListView.builder(
        key: const ValueKey('font-list'),
        itemExtent: kFontRow,
        padding: EdgeInsets.zero,
        itemCount: families.length + extra,
        itemBuilder: (context, i) {
          if (i == families.length) {
            return Pressable(
              onPressed: onMoreFonts,
              semanticLabel: 'More fonts',
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.plus_circle, size: 20, color: colors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('More fonts', style: AppText.body.copyWith(color: colors.accent)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          final family = families[i];
          final on = family == el.font;
          return Pressable(
            onPressed: () => editSelected(c, 'font', (e) {
              e.font = family;
              e.weight = reg.nearestWeight(family, e.weight);
            }, remeasure: true),
            semanticLabel: family,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: on ? colors.accent.withValues(alpha: 0.14) : colors.raised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        family,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: family, fontSize: 18, color: colors.text),
                      ),
                    ),
                    if (on) Icon(CupertinoIcons.checkmark_alt, size: 18, color: colors.accent),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StylePage extends StatelessWidget {
  const _StylePage({required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final weights = FontRegistry.instance.weightsFor(el.font);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChipWrap(
          children: [
            for (final w in weights)
              PanelChip(
                label: weightName(w),
                on: el.weight == w,
                onTap: () => editSelected(c, 'weight', (e) => e.weight = w, remeasure: true),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ChipWrap(
          children: [
            PanelChip(
              label: 'Italic',
              on: el.italic,
              onTap: () => editSelected(c, 'italic', (e) => e.italic = !e.italic, remeasure: true),
            ),
            PanelChip(
              label: 'ABC',
              on: el.upper,
              onTap: () => editSelected(c, 'upper', (e) => e.upper = !e.upper, remeasure: true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Segmented<TextAlignH>(
          segments: const {TextAlignH.left: 'Left', TextAlignH.center: 'Centre', TextAlignH.right: 'Right'},
          value: el.align,
          onChanged: (a) => editSelected(c, 'align', (e) => e.align = a, remeasure: true),
        ),
      ],
    );
  }
}

class _SizePage extends StatelessWidget {
  const _SizePage({required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LabeledSlider(
          sliderHeight: 36,
          label: 'Size',
          value: el.size,
          min: 8,
          max: 300,
          onChanged: (v) => editSelected(c, 'size', (e) => e.size = v.roundToDouble(), remeasure: true),
        ),
        LabeledSlider(
          sliderHeight: 36,
          label: 'Letter spacing',
          value: el.letterSpacing,
          min: -5,
          max: 40,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) => editSelected(c, 'ls', (e) => e.letterSpacing = (v * 2).round() / 2, remeasure: true),
        ),
        LabeledSlider(
          sliderHeight: 36,
          label: 'Line height',
          value: el.lineHeight,
          min: 0.8,
          max: 2.5,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) => editSelected(c, 'lh', (e) => e.lineHeight = (v * 20).round() / 20, remeasure: true),
        ),
      ],
    );
  }
}

String weightName(int w) => switch (w) {
  100 => 'Thin',
  200 => 'Extra light',
  300 => 'Light',
  400 => 'Regular',
  500 => 'Medium',
  600 => 'Semibold',
  700 => 'Bold',
  800 => 'Extra bold',
  900 => 'Black',
  _ => '$w',
};
