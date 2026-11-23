import 'package:flutter/cupertino.dart';

import '../../../core/develop/settings.dart';
import '../../../ui/app_theme.dart';
import '../../editor/panels/panel_widgets.dart';
import '../photo_editor_controller.dart';
import 'curve_editor.dart';
import 'develop_slider.dart';

/// Light: exposure and tone, the tone curve and its parametric zones.
class LightPanel extends StatelessWidget {
  const LightPanel({super.key, required this.controller});
  final PhotoEditorController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      DevelopSlider s(Setting v, String label) =>
          DevelopSlider.setting(c, v, label);
      // Each split keeps its order: at least 5 from its neighbours.
      DevelopSlider split(Setting v, String label) {
        final st = c.settings;
        final lo = switch (v) {
          Setting.curveMidtoneSplit => st[Setting.curveShadowSplit] + 5,
          Setting.curveHighlightSplit => st[Setting.curveMidtoneSplit] + 5,
          _ => v.min,
        };
        final hi = switch (v) {
          Setting.curveShadowSplit => st[Setting.curveMidtoneSplit] - 5,
          Setting.curveMidtoneSplit => st[Setting.curveHighlightSplit] - 5,
          _ => v.max,
        };
        return DevelopSlider.setting(
          c,
          v,
          label,
          limit: (x) {
            // Splits that are already too close (from a preset) still
            // give bounds inside the slider's range.
            final low = lo.clamp(v.min, v.max).toDouble();
            final high = hi.clamp(low, v.max).toDouble();
            return x.clamp(low, high).toDouble();
          },
        );
      }

      return PanelTabs(
        tabs: {
          'Basic': () => SliderPage(
            children: [
              s(Setting.exposure, 'Exposure'),
              s(Setting.contrast, 'Contrast'),
              s(Setting.highlights, 'Highlights'),
            ],
          ),
          'Tone': () => SliderPage(
            children: [
              s(Setting.shadows, 'Shadows'),
              s(Setting.whites, 'Whites'),
              s(Setting.blacks, 'Blacks'),
            ],
          ),
          'Curve': () => _CurveTab(controller: c),
          'Zones': () => SliderPage(
            children: [
              SliderPair(
                left: s(Setting.curveHighlights, 'Highlights'),
                right: s(Setting.curveLights, 'Lights'),
              ),
              SliderPair(
                left: s(Setting.curveDarks, 'Darks'),
                right: s(Setting.curveShadows, 'Shadows'),
              ),
            ],
          ),
          'Splits': () => SliderPage(
            children: [
              split(Setting.curveShadowSplit, 'Shadow split'),
              split(Setting.curveMidtoneSplit, 'Midtone split'),
              split(Setting.curveHighlightSplit, 'Highlight split'),
            ],
          ),
        },
      );
    },
  );
}

/// The point curve with a chip for each channel.
class _CurveTab extends StatefulWidget {
  const _CurveTab({required this.controller});
  final PhotoEditorController controller;

  @override
  State<_CurveTab> createState() => _CurveTabState();
}

class _CurveTabState extends State<_CurveTab> {
  CurveChannel _channel = CurveChannel.master;

  static const _names = {
    CurveChannel.master: 'RGB',
    CurveChannel.red: 'Red',
    CurveChannel.green: 'Green',
    CurveChannel.blue: 'Blue',
  };

  Color _color(BuildContext context) => switch (_channel) {
    CurveChannel.master => AppColors.of(context).text,
    CurveChannel.red => const Color(0xFFE5392E),
    CurveChannel.green => const Color(0xFF2FA84F),
    CurveChannel.blue => const Color(0xFF2B7BE0),
  };

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    // Room left under the tab control and the chips; the square is as wide
    // as the panel, or as tall as that room.
    final room = PanelSpace.of(context) - 42 - 44;
    return LayoutBuilder(
      builder: (context, box) {
        final size = [
          box.maxWidth,
          room,
          320.0,
        ].reduce((a, b) => a < b ? a : b);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChipWrap(
              children: [
                for (final e in _names.entries)
                  PanelChip(
                    label: e.value,
                    on: _channel == e.key,
                    onTap: () => setState(() => _channel = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            CurveEditor(
              size: size < 120 ? 120 : size,
              color: _color(context),
              points: c.settings.curve(_channel),
              onChanged: (pts) => c.setCurve(_channel, pts),
            ),
          ],
        );
      },
    );
  }
}
