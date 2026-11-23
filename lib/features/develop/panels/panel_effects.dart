import 'package:flutter/cupertino.dart';

import '../../../core/develop/settings.dart';
import '../../editor/panels/panel_widgets.dart';
import '../photo_editor_controller.dart';
import 'develop_slider.dart';

/// Effects: texture and clarity, the vignette and the grain.
class EffectsPanel extends StatelessWidget {
  const EffectsPanel({super.key, required this.controller});
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
          'Basic': () => SliderPage(
            children: [
              s(Setting.texture, 'Texture'),
              s(Setting.clarity, 'Clarity'),
              s(Setting.dehaze, 'Dehaze'),
            ],
          ),
          'Vignette': () => SliderPage(
            children: [
              s(Setting.vignetteAmount, 'Amount'),
              SliderPair(
                left: s(Setting.vignetteMidpoint, 'Midpoint'),
                right: s(Setting.vignetteRoundness, 'Roundness'),
              ),
              SliderPair(
                left: s(Setting.vignetteFeather, 'Feather'),
                right: s(Setting.vignetteHighlights, 'Highlights'),
              ),
            ],
          ),
          'Grain': () => SliderPage(
            children: [
              s(Setting.grainAmount, 'Amount'),
              s(Setting.grainSize, 'Size'),
              s(Setting.grainRoughness, 'Roughness'),
            ],
          ),
        },
      );
    },
  );
}
