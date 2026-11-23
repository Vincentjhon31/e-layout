import 'package:flutter/cupertino.dart';

import '../../../core/develop/settings.dart';
import '../../../ui/widgets/labeled_slider.dart';
import '../photo_editor_controller.dart';

/// How a setting's value is written next to its label: a sign when the range
/// crosses zero ("+20", "0", "-15"), two decimals for exposure ("+0.70"),
/// one for the sharpen radius, degrees for hues of the grading wheels.
String formatSetting(Setting s, double v) {
  if (s == Setting.exposure) {
    final r = (v * 100).round() / 100;
    if (r == 0) return '0.00';
    final t = r.abs().toStringAsFixed(2);
    return r > 0 ? '+$t' : '-$t';
  }
  if (s == Setting.sharpenRadius) return v.toStringAsFixed(1);
  if (s.name.startsWith('grade') && s.name.endsWith('Hue')) {
    return '${v.round()}°';
  }
  final n = v.round();
  if (s.min < 0) return n > 0 ? '+$n' : '$n';
  return '$n';
}

/// The panel's room, so a control that can use any size (the curve) fits.
class PanelSpace extends InheritedWidget {
  const PanelSpace({super.key, required this.height, required super.child});

  /// The height the open tool's controls have.
  final double height;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelSpace>()?.height ??
      double.infinity;

  @override
  bool updateShouldNotify(PanelSpace old) => height != old.height;
}

/// The frame of a tool's controls: they should all fit; if one ever does not
/// (a very large text size), the panel scrolls instead of clipping.
class DevelopPanelShell extends StatelessWidget {
  const DevelopPanelShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      key: const ValueKey('develop-panel-scroll'),
      child: PanelSpace(height: box.maxHeight, child: child),
    ),
  );
}

/// A column of slider rows.
class SliderPage extends StatelessWidget {
  const SliderPage({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}

/// Two sliders side by side, for tools with more sliders than rows.
class SliderPair extends StatelessWidget {
  const SliderPair({super.key, required this.left, required this.right});
  final Widget left, right;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: left),
      const SizedBox(width: 16),
      Expanded(child: right),
    ],
  );
}

/// A slider for one setting. A drag is one undo step; a double-tap on the
/// row puts the neutral value back.
class DevelopSlider extends StatelessWidget {
  const DevelopSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    required this.onReset,
    required this.format,
  });

  /// A slider bound to [s] of [c]'s photo. [limit] narrows the dragged value
  /// (the curve's split points keep their order).
  factory DevelopSlider.setting(
    PhotoEditorController c,
    Setting s,
    String label, {
    double Function(double v)? limit,
  }) {
    final step = switch (s) {
      Setting.exposure => 100.0,
      Setting.sharpenRadius => 10.0,
      _ => 1.0,
    };
    return DevelopSlider(
      key: ValueKey('slider-${s.name}'),
      label: label,
      value: c.settings[s],
      min: s.min,
      max: s.max,
      format: (v) => formatSetting(s, v),
      onStart: c.beginChange,
      onChanged: (v) {
        final r = (v * step).round() / step;
        c.preview(s, limit == null ? r : limit(r));
      },
      onEnd: c.endChange,
      onReset: () => c.setValue(s, s.neutral),
    );
  }

  final String label;
  final double value;
  final double min;
  final double max;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  final VoidCallback onReset;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onDoubleTap: onReset,
    child: LabeledSlider(
      sliderHeight: 36,
      label: label,
      value: value,
      min: min,
      max: max,
      format: format,
      onChangeStart: (_) => onStart(),
      onChanged: onChanged,
      onChangeEnd: (_) => onEnd(),
    ),
  );
}
