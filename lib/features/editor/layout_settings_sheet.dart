import 'package:flutter/cupertino.dart';

import '../../core/model/layout_doc.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/segmented.dart';
import '../../ui/widgets/sheet_scaffold.dart';
import 'editor_controller.dart';

/// editor.js CROP_RATIOS.
const List<(String, double)> kCropRatios = [
  ('1:1 square', 1),
  ('4:5 portrait', 4 / 5),
  ('3:4 portrait', 3 / 4),
  ('3:2 landscape', 3 / 2),
  ('16:9 wide', 16 / 9),
  ('9:16 story', 9 / 16),
];

Future<void> showLayoutSettings(BuildContext context, EditorController c) {
  return showAppSheet<void>(context, (_) => LayoutSettingsSheet(controller: c));
}

/// Keep each photo's shape, or crop every photo to one shape.
class LayoutSettingsSheet extends StatelessWidget {
  const LayoutSettingsSheet({super.key, required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    return SheetScaffold(
      title: 'Layout settings',
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final crop = c.doc.fit == DocFit.crop;
          final ratios = [...kCropRatios];
          if (!ratios.any((r) => (r.$2 - c.doc.ratio).abs() < 0.0001)) {
            ratios.insert(0, ('${c.doc.ratio.toStringAsFixed(2)}:1 (this layout)', c.doc.ratio));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Same look as the Options sheet on Home: a header, a white group, a footnote.
              AppGroup(
                header: 'Photo shape',
                footer: crop
                    ? 'Every photo is trimmed to this shape, centred, and the layout covers it exactly.'
                    : "Each piece stays pinned to its edge (top, bottom or centre) and everything scales with the photo's width. Check portrait photos with the Portrait button.",
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Segmented<DocFit>(
                      segments: const {DocFit.keep: 'Keep each photo', DocFit.crop: 'Crop to one shape'},
                      value: c.doc.fit,
                      onChanged: (v) {
                        if (v == c.doc.fit) return;
                        c.setFit(v, ratio: v == DocFit.crop ? c.ratioValue : null);
                      },
                    ),
                  ),
                ],
              ),
              if (crop) ...[
                const SizedBox(height: 20),
                AppGroup(
                  header: 'Crop photos to',
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final r in ratios)
                            Pressable(
                              onPressed: () => c.setFit(DocFit.crop, ratio: r.$2),
                              semanticLabel: r.$1,
                              child: Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: (r.$2 - c.doc.ratio).abs() < 0.0001 ? colors.accent : colors.raised,
                                  borderRadius: BorderRadius.circular(19),
                                ),
                                child: Center(
                                  widthFactor: 1,
                                  child: Text(
                                    r.$1,
                                    style: AppText.subhead.copyWith(
                                      color: (r.$2 - c.doc.ratio).abs() < 0.0001 ? colors.onAccent : colors.text,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
