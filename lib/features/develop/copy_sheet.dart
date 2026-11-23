import 'package:flutter/cupertino.dart';

import '../../core/develop/settings.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/sheet_scaffold.dart';
import '../../ui/widgets/toast.dart';
import '../home/export_job.dart' show plural;
import 'photo_editor_controller.dart';

const Map<ToolGroup, String> _kGroupNames = {
  ToolGroup.light: 'Light',
  ToolGroup.colour: 'Colour',
  ToolGroup.effects: 'Effects',
  ToolGroup.detail: 'Detail',
};

/// Opens "Copy to all photos". After Copy, [context] shows the toast.
Future<void> showCopyToAll(BuildContext context, PhotoEditorController c) {
  return showAppSheet<void>(
    context,
    (ctx) => CopyToAllSheet(
      controller: c,
      onCopy: (groups, keepSingle) async {
        final photos = plural(c.photos.length - 1, 'photo', 'photos');
        await c.copyToAll(groups, keepSingle: keepSingle);
        if (context.mounted) {
          showToast(
            context,
            'Copied to $photos.',
            icon: CupertinoIcons.checkmark_alt,
          );
        }
      },
    ),
  );
}

/// Which groups of this photo go to the other photos.
class CopyToAllSheet extends StatefulWidget {
  const CopyToAllSheet({
    super.key,
    required this.controller,
    required this.onCopy,
  });

  final PhotoEditorController controller;
  final Future<void> Function(Set<ToolGroup> groups, bool keepSingle) onCopy;

  @override
  State<CopyToAllSheet> createState() => _CopyToAllSheetState();
}

class _CopyToAllSheetState extends State<CopyToAllSheet> {
  final Set<ToolGroup> _groups = ToolGroup.values.toSet();
  bool _keepSingle = true;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final n = widget.controller.photos.length - 1;
    final count = n < 0 ? 0 : n;
    final enabled = _groups.isNotEmpty && count > 0;
    return SheetScaffold(
      title: 'Copy to all photos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: colors.cardIn(context),
              borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final g in ToolGroup.values) ...[
                  _GroupRow(
                    label: _kGroupNames[g]!,
                    on: _groups.contains(g),
                    onPressed: () => setState(() {
                      if (!_groups.remove(g)) _groups.add(g);
                    }),
                  ),
                  Container(height: 0.5, color: colors.separator),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Keep changes made on single photos',
                          style: AppText.body.copyWith(color: colors.text),
                        ),
                      ),
                      const SizedBox(width: 12),
                      CupertinoSwitch(
                        value: _keepSingle,
                        activeTrackColor: colors.accent,
                        onChanged: (v) => setState(() => _keepSingle = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: 'Copy to ${plural(count, 'photo', 'photos')}',
            onPressed: !enabled
                ? null
                : () async {
                    final groups = {..._groups};
                    final keep = _keepSingle;
                    Navigator.of(context).pop();
                    await widget.onCopy(groups, keep);
                  },
          ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.label,
    required this.on,
    required this.onPressed,
  });

  final String label;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      checked: on,
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: label,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    style: AppText.body.copyWith(color: colors.text),
                  ),
                ),
              ),
              Icon(
                on
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                size: 26,
                color: on ? colors.accent : colors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
