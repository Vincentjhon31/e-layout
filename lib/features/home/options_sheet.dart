import 'package:flutter/cupertino.dart';

import '../../core/export/photo_exporter.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/labeled_slider.dart';
import '../../ui/widgets/segmented.dart';
import '../../ui/widgets/sheet_scaffold.dart';
import 'home_controller.dart';

/// File format, quality and the text added to file names.
class OptionsSheet extends StatefulWidget {
  const OptionsSheet({super.key, required this.controller});
  final HomeController controller;

  @override
  State<OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<OptionsSheet> {
  late final TextEditingController _suffix =
      TextEditingController(text: widget.controller.settings.suffix);

  @override
  void dispose() {
    _suffix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final s = widget.controller.settings;
        final png = s.format == OutputFormat.png;
        final example = '${outputStem('IMG_1234.jpg', s.suffix)}.${png ? 'png' : 'jpg'}';
        return SheetScaffold(
          title: 'Options',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppGroup(
                header: 'Format',
                footer: png
                    ? 'PNG keeps every detail but makes larger files.'
                    : 'JPG files are small and open everywhere.',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Segmented<OutputFormat>(
                      segments: const {OutputFormat.jpeg: 'JPG', OutputFormat.png: 'PNG (larger files)'},
                      value: s.format,
                      onChanged: (v) => widget.controller.updateSettings((x) => x.format = v),
                    ),
                  ),
                ],
              ),
              if (!png) ...[
                const SizedBox(height: 20),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: LabeledSlider(
                    label: 'Quality',
                    value: s.quality.toDouble(),
                    min: 70,
                    max: 100,
                    divisions: 30,
                    format: (v) => '${v.round()}%',
                    onChanged: (v) => widget.controller.updateSettings((x) => x.quality = v.round()),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              AppGroup(
                header: 'Add to file names',
                footer: 'Saved as $example',
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: CupertinoTextField(
                      controller: _suffix,
                      placeholder: 'Nothing',
                      style: AppText.body.copyWith(color: c.text),
                      decoration: null,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      clearButtonMode: OverlayVisibilityMode.editing,
                      autocorrect: false,
                      onChanged: (v) => widget.controller.updateSettings((x) => x.suffix = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
