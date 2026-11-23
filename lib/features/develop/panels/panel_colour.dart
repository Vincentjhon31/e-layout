import 'package:flutter/cupertino.dart';

import '../../../core/develop/settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/widgets/labeled_slider.dart';
import '../../../ui/widgets/pressable.dart';
import '../../editor/panels/panel_widgets.dart';
import '../photo_editor_controller.dart';
import 'develop_slider.dart';

/// Colour: white balance, the look, the colour mixer and the grading.
class ColourPanel extends StatelessWidget {
  const ColourPanel({super.key, required this.controller});
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
              s(Setting.temperature, 'Temperature'),
              s(Setting.tint, 'Tint'),
              SliderPair(
                left: s(Setting.vibrance, 'Vibrance'),
                right: s(Setting.saturation, 'Saturation'),
              ),
            ],
          ),
          'Look': () => _LookTab(controller: c),
          'Mixer': () => _MixerTab(controller: c),
          'Grade': () => _GradingTab(controller: c),
          'Blend': () => SliderPage(
            children: [
              s(Setting.gradeBlending, 'Blending'),
              s(Setting.gradeBalance, 'Balance'),
            ],
          ),
        },
      );
    },
  );
}

/// Black and white, and the colour profile's strength.
class _LookTab extends StatelessWidget {
  const _LookTab({required this.controller});
  final PhotoEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    final st = c.settings;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Black & white',
                  style: AppText.body.copyWith(color: colors.text),
                ),
              ),
              CupertinoSwitch(
                value: st.grayscale,
                activeTrackColor: colors.accent,
                onChanged: (v) => c.setGrayscale(v),
              ),
            ],
          ),
        ),
        if (st.profile.isNone)
          const PanelNote('Presets can bring a colour profile.')
        else ...[
          SizedBox(
            height: 28,
            child: Row(
              children: [
                Text(
                  'Profile',
                  style: AppText.subhead.copyWith(color: colors.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    st.profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppText.subhead.copyWith(color: colors.secondary),
                  ),
                ),
              ],
            ),
          ),
          _AmountSlider(controller: c),
        ],
      ],
    );
  }
}

/// The profile's strength, 0 to 200 %. Only the end of a drag is kept (one
/// undo step); the thumb follows the finger meanwhile.
class _AmountSlider extends StatefulWidget {
  const _AmountSlider({required this.controller});
  final PhotoEditorController controller;

  @override
  State<_AmountSlider> createState() => _AmountSliderState();
}

class _AmountSliderState extends State<_AmountSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return GestureDetector(
      key: const ValueKey('slider-profile-amount'),
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () => c.setProfileAmount(1),
      child: LabeledSlider(
        sliderHeight: 36,
        label: 'Amount',
        value: _drag ?? c.settings.profile.amount,
        min: 0,
        max: 2,
        format: (v) => '${(v * 100).round()}%',
        onChangeStart: (v) => setState(() => _drag = v),
        onChanged: (v) => setState(() => _drag = (v * 100).round() / 100),
        onChangeEnd: (v) {
          final a = (v * 100).round() / 100;
          setState(() => _drag = null);
          c.setProfileAmount(a);
        },
      ),
    );
  }
}

/// One colour of the mixer: its name, dot colour and settings.
class _Band {
  const _Band(this.name, this.color, this.hue, this.sat, this.lum, this.gray);
  final String name;
  final Color color;
  final Setting hue, sat, lum, gray;
}

const List<_Band> _bands = [
  _Band(
    'Red',
    Color(0xFFFF3B30),
    Setting.hueRed,
    Setting.satRed,
    Setting.lumRed,
    Setting.grayRed,
  ),
  _Band(
    'Orange',
    Color(0xFFFF9500),
    Setting.hueOrange,
    Setting.satOrange,
    Setting.lumOrange,
    Setting.grayOrange,
  ),
  _Band(
    'Yellow',
    Color(0xFFFFCC00),
    Setting.hueYellow,
    Setting.satYellow,
    Setting.lumYellow,
    Setting.grayYellow,
  ),
  _Band(
    'Green',
    Color(0xFF34C759),
    Setting.hueGreen,
    Setting.satGreen,
    Setting.lumGreen,
    Setting.grayGreen,
  ),
  _Band(
    'Aqua',
    Color(0xFF00C7BE),
    Setting.hueAqua,
    Setting.satAqua,
    Setting.lumAqua,
    Setting.grayAqua,
  ),
  _Band(
    'Blue',
    Color(0xFF007AFF),
    Setting.hueBlue,
    Setting.satBlue,
    Setting.lumBlue,
    Setting.grayBlue,
  ),
  _Band(
    'Purple',
    Color(0xFFAF52DE),
    Setting.huePurple,
    Setting.satPurple,
    Setting.lumPurple,
    Setting.grayPurple,
  ),
  _Band(
    'Magenta',
    Color(0xFFFF2D92),
    Setting.hueMagenta,
    Setting.satMagenta,
    Setting.lumMagenta,
    Setting.grayMagenta,
  ),
];

/// Eight colour dots, and the sliders of the chosen colour. In black and
/// white the same dots choose which colour's grey mix the slider sets.
class _MixerTab extends StatefulWidget {
  const _MixerTab({required this.controller});
  final PhotoEditorController controller;

  @override
  State<_MixerTab> createState() => _MixerTabState();
}

class _MixerTabState extends State<_MixerTab> {
  int _band = 0;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _choose(int i, double viewport) {
    setState(() => _band = i);
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final to = (i * 44 - (viewport - 44) / 2).clamp(0.0, max).toDouble();
    _scroll.animateTo(
      to,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Widget _dot(int i, AppColors colors, double viewport) => Pressable(
    onPressed: () => _choose(i, viewport),
    semanticLabel: _bands[i].name,
    child: SizedBox(
      key: ValueKey('mixer-${_bands[i].name}'),
      height: 44,
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: i == _band ? colors.text : const Color(0x00000000),
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _bands[i].color,
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final colors = AppColors.of(context);
    final b = _bands[_band];
    final gray = c.settings.grayscale;
    DevelopSlider s(Setting v, String label) =>
        DevelopSlider.setting(c, v, label);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            // Eight 44 pt dots need 352 pt; on a narrower panel the strip
            // scrolls and the chosen dot is kept in view.
            if (box.maxWidth >= _bands.length * 44) {
              return Row(
                children: [
                  for (var i = 0; i < _bands.length; i++)
                    Expanded(child: _dot(i, colors, box.maxWidth)),
                ],
              );
            }
            return SizedBox(
              height: 44,
              child: SingleChildScrollView(
                key: const ValueKey('mixer-strip'),
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _bands.length; i++)
                      SizedBox(width: 44, child: _dot(i, colors, box.maxWidth)),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        if (gray) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Black & white mix',
              style: AppText.captionStrong.copyWith(color: colors.secondary),
            ),
          ),
          s(b.gray, b.name),
        ] else ...[
          SliderPair(left: s(b.hue, 'Hue'), right: s(b.sat, 'Saturation')),
          s(b.lum, 'Luminance'),
        ],
      ],
    );
  }
}

/// Shadows, midtones, highlights and global: a hue, a saturation and a
/// luminance each, as sliders.
class _GradingTab extends StatefulWidget {
  const _GradingTab({required this.controller});
  final PhotoEditorController controller;

  @override
  State<_GradingTab> createState() => _GradingTabState();
}

class _GradingTabState extends State<_GradingTab> {
  int _zone = 0;

  static const _zones = [
    (
      'Shadows',
      Setting.gradeShadowHue,
      Setting.gradeShadowSat,
      Setting.gradeShadowLum,
    ),
    ('Midtones', Setting.gradeMidHue, Setting.gradeMidSat, Setting.gradeMidLum),
    (
      'Highlights',
      Setting.gradeHighHue,
      Setting.gradeHighSat,
      Setting.gradeHighLum,
    ),
    (
      'Global',
      Setting.gradeGlobalHue,
      Setting.gradeGlobalSat,
      Setting.gradeGlobalLum,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final z = _zones[_zone];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One line of chips; on a very narrow phone they shrink to fit.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _zones.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                PanelChip(
                  label: _zones[i].$1,
                  on: i == _zone,
                  onTap: () => setState(() => _zone = i),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        DevelopSlider.setting(c, z.$2, 'Hue'),
        SliderPair(
          left: DevelopSlider.setting(c, z.$3, 'Saturation'),
          right: DevelopSlider.setting(c, z.$4, 'Luminance'),
        ),
      ],
    );
  }
}
