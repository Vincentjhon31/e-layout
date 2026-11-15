import 'package:flutter/cupertino.dart';

import '../app_theme.dart';

/// A label, its value in tabular figures, and a slider underneath.
/// [onChangeStart] and [onChangeEnd] bracket one gesture (one undo step).
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.divisions,
    this.format,
    this.sliderHeight = 40,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  /// Height of the slider row; panels under the editor canvas use less.
  final double sliderHeight;

  /// How the value is written next to the label.
  final String Function(double)? format;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final v = value.clamp(min, max).toDouble();
    final text = format != null ? format!(value) : value.round().toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: AppText.subhead.copyWith(color: c.text)),
            ),
            Text(
              text,
              style: AppText.subhead.copyWith(color: c.secondary, fontFeatures: AppText.tabular),
            ),
          ],
        ),
        SizedBox(
          height: sliderHeight,
          child: CupertinoSlider(
            value: v,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: c.accent,
            onChanged: onChanged,
            onChangeStart: onChangeStart,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}
