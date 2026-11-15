import 'package:flutter/cupertino.dart';

import '../app_theme.dart';

/// A sliding segmented control with the app's type.
class Segmented<T extends Object> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  /// Value to label, in display order.
  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// Smaller type, for the control floating over the editor canvas.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = (compact ? AppText.caption : AppText.subhead).copyWith(color: c.text);
    return CupertinoSlidingSegmentedControl<T>(
      groupValue: value,
      backgroundColor: c.raised,
      thumbColor: AppColors.brightnessOf(context) == Brightness.dark ? const Color(0xFF636366) : c.card,
      padding: const EdgeInsets.all(2),
      onValueChanged: (v) {
        if (v != null) onChanged(v);
      },
      children: {
        for (final e in segments.entries)
          e.key: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 7),
            child: Text(e.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: e.key == value ? style.copyWith(fontWeight: FontWeight.w600) : style),
          ),
      },
    );
  }
}
