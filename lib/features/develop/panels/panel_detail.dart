import 'package:flutter/cupertino.dart';

import '../../../core/develop/settings.dart';
import '../../editor/panels/panel_widgets.dart';
import '../photo_editor_controller.dart';
import 'develop_slider.dart';

/// Detail: sharpening and noise reduction.
class DetailPanel extends StatelessWidget {
  const DetailPanel({super.key, required this.controller});
  final PhotoEditorController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      DevelopSlider s(Setting v, String label) =>
          DevelopSlider.setting(c, v, label);
      return PanelTabs(
        tabs: {
          'Sharpening': () => SliderPage(
            children: [
              s(Setting.sharpenAmount, 'Amount'),
              SliderPair(
                left: s(Setting.sharpenRadius, 'Radius'),
                right: s(Setting.sharpenDetail, 'Detail'),
              ),
              s(Setting.sharpenMasking, 'Masking'),
            ],
          ),
          'Noise': () => SliderPage(
            children: [
              s(Setting.noiseLuminance, 'Luminance'),
              s(Setting.noiseDetail, 'Detail'),
              s(Setting.noiseContrast, 'Contrast'),
            ],
          ),
          'Colour noise': () => SliderPage(
            children: [
              s(Setting.noiseColour, 'Colour'),
              s(Setting.noiseColourDetail, 'Colour detail'),
              s(Setting.noiseColourSmoothness, 'Smoothness'),
            ],
          ),
        },
      );
    },
  );
}
