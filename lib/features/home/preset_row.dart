import 'package:flutter/cupertino.dart';

import '../../core/develop/batch_look.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/pressable.dart';

/// What the preset row shows for [look]: the shared preset's name, "Custom"
/// for a shared look without a name, or "None" (shared masks and lens blur
/// are no preset).
String presetRowValue(BatchLook look) {
  final name = look.sharedName;
  if (name != null) return name;
  return look.sharedPresetIsEmpty ? 'None' : 'Custom';
}

/// "Preset", the current look at the right, and a chevron. Opens the picker.
class PresetRow extends StatelessWidget {
  const PresetRow({super.key, required this.look, required this.onTap});

  final BatchLook look;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppMetrics.gutter,
        8,
        AppMetrics.gutter,
        0,
      ),
      child: Pressable(
        onPressed: onTap,
        pressedOpacity: 0.7,
        semanticLabel: 'Preset, ${presetRowValue(look)}',
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.cardIn(context),
            borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Text('Preset', style: AppText.body.copyWith(color: c.text)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    presetRowValue(look),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(color: c.secondary),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: c.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
