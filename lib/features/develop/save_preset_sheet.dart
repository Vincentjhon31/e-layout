import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../ui/app_theme.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/sheet_scaffold.dart';
import '../../ui/widgets/toast.dart';
import 'photo_editor_controller.dart';

/// Longest preset name.
const int kPresetNameMax = 80;

/// Opens "Save as preset". After Save, [context] shows the toast.
Future<void> showSavePreset(BuildContext context, PhotoEditorController c) {
  return showAppSheet<void>(
    context,
    (ctx) => SavePresetSheet(
      onSave: (name) async {
        try {
          await c.saveAsPreset(name);
        } catch (e) {
          debugPrint('Could not save the preset: $e');
          if (context.mounted) {
            showToast(
              context,
              "Couldn't save the preset.",
              icon: CupertinoIcons.exclamationmark_circle,
            );
          }
          return;
        }
        if (context.mounted) {
          showToast(
            context,
            'Saved "$name".',
            icon: CupertinoIcons.checkmark_alt,
          );
        }
      },
    ),
  );
}

/// "Save as preset": a name, then Save.
class SavePresetSheet extends StatefulWidget {
  const SavePresetSheet({super.key, required this.onSave});
  final Future<void> Function(String name) onSave;

  @override
  State<SavePresetSheet> createState() => _SavePresetSheetState();
}

class _SavePresetSheetState extends State<SavePresetSheet> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SheetScaffold(
      title: 'Save as preset',
      doneLabel: 'Cancel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoTextField(
            controller: _name,
            autofocus: true,
            placeholder: 'Preset name',
            placeholderStyle: AppText.body.copyWith(color: colors.secondary),
            // Stops typing at the limit without a counter.
            inputFormatters: [LengthLimitingTextInputFormatter(kPresetNameMax)],
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            style: AppText.body.copyWith(color: colors.text),
            decoration: BoxDecoration(
              color: colors.raised,
              borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
            ),
            clearButtonMode: OverlayVisibilityMode.editing,
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: _name,
            builder: (context, _) {
              final name = _name.text.trim();
              return AppButton(
                label: 'Save',
                onPressed: name.isEmpty
                    ? null
                    : () async {
                        Navigator.of(context).pop();
                        await widget.onSave(name);
                      },
              );
            },
          ),
        ],
      ),
    );
  }
}
