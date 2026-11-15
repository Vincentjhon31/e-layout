import 'package:flutter/cupertino.dart';

import '../../core/model/layout_doc.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/action_sheet.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/sheet_scaffold.dart';
import 'editor_controller.dart';

Future<void> showLayers(BuildContext context, EditorController c) {
  return showAppSheet<void>(context, (_) => LayersSheet(controller: c));
}

IconData iconOfType(ElementType t) => switch (t) {
  ElementType.text => CupertinoIcons.textformat,
  ElementType.shape => CupertinoIcons.square_on_circle,
  ElementType.image => CupertinoIcons.photo,
  ElementType.icon => CupertinoIcons.star,
};

/// Every piece, topmost first. Tap to select, drag the handle to reorder,
/// long-press to rename, the eye hides, the padlock locks. A group is one
/// row that opens to show its pieces. "Select" turns on picking several
/// pieces, to Group or Delete them.
class LayersSheet extends StatefulWidget {
  const LayersSheet({super.key, required this.controller});
  final EditorController controller;

  @override
  State<LayersSheet> createState() => _LayersSheetState();
}

class _LayersSheetState extends State<LayersSheet> {
  bool _select = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final colors = AppColors.of(context);
    return SheetScaffold(
      title: 'Layers',
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      leading: Pressable(
        onPressed: () => setState(() => _select = !_select),
        semanticLabel: _select ? 'Stop selecting' : 'Select',
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Text(_select ? 'Cancel' : 'Select', style: AppText.button.copyWith(color: colors.accent)),
        ),
      ),
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final units = c.topUnits().reversed.toList();
          if (units.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Nothing here yet. Add text, a shape, an icon or a picture.',
                textAlign: TextAlign.center,
                style: AppText.subhead.copyWith(color: colors.secondary),
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                  child: ReorderableList(
                    shrinkWrap: true,
                    itemCount: units.length,
                    onReorderItem: c.reorderUnit,
                    itemBuilder: (context, i) => _UnitRow(
                      key: ValueKey(units[i].first.id),
                      index: i,
                      unit: units[i],
                      controller: c,
                      selectMode: _select,
                    ),
                  ),
                ),
              ),
              if (_select) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppButton.tinted(
                        label: 'Group',
                        onPressed: c.unitsOfSelection >= 2 ? c.groupSelected : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppButton.destructive(
                        label: c.sel.isEmpty ? 'Delete' : 'Delete ${c.sel.length}',
                        onPressed: c.sel.isEmpty ? null : c.removeSelected,
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

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    super.key,
    required this.index,
    required this.unit,
    required this.controller,
    this.selectMode = false,
  });
  final bool selectMode;
  final int index;
  final List<LayoutElement> unit;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final grouped = unit.first.group != null && c.doc.groups.containsKey(unit.first.group);
    final open = grouped && c.expanded.contains(unit.first.group);
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Row(
          index: index,
          controller: c,
          el: unit.first,
          label: grouped ? 'Group of ${unit.length}' : null,
          groupIds: grouped ? [for (final e in unit) e.id] : null,
          open: open,
          selectMode: selectMode,
        ),
        if (open)
          for (final e in unit.reversed) _Row(index: -1, controller: c, el: e, indent: true, selectMode: selectMode),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.index,
    required this.controller,
    required this.el,
    this.label,
    this.groupIds,
    this.open = false,
    this.indent = false,
    this.selectMode = false,
  });
  final bool selectMode;
  final int index;
  final EditorController controller;
  final LayoutElement el;
  final String? label;
  final List<String>? groupIds;
  final bool open;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    final selected = groupIds != null ? groupIds!.every(c.sel.contains) : c.sel.contains(el.id);
    final name = label ?? (el.name.isEmpty ? c.defaultName(el) : el.name);
    return Container(
      height: 52,
      margin: EdgeInsets.only(left: indent ? 28 : 0, bottom: 4),
      decoration: BoxDecoration(
        color: selected ? colors.accent.withValues(alpha: 0.14) : colors.cardIn(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (selectMode)
            SizedBox(
              width: 40,
              height: 52,
              child: Icon(
                selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                size: 22,
                color: selected ? colors.accent : colors.secondary,
              ),
            )
          else if (index >= 0)
            ReorderableDragStartListener(
              index: index,
              child: SizedBox(
                width: 40,
                height: 52,
                child: Icon(CupertinoIcons.line_horizontal_3, size: 20, color: colors.secondary),
              ),
            )
          else
            const SizedBox(width: 12),
          Icon(
            groupIds != null ? CupertinoIcons.square_stack_3d_up : iconOfType(el.type),
            size: 20,
            color: el.visible ? colors.text : colors.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Pressable(
              onPressed: () {
                if (selectMode) {
                  c.toggleInSelection(el);
                } else if (groupIds != null) {
                  final g = el.group!;
                  c.expanded.contains(g) ? c.expanded.remove(g) : c.expanded.add(g);
                  c.select(groupIds!);
                } else {
                  c.select([el.id]);
                }
              },
              onLongPress: () async {
                final n = await showTextPrompt(
                  context,
                  title: 'Rename',
                  initial: name,
                  confirmLabel: 'Rename',
                  placeholder: 'Name',
                );
                if (n != null) c.renamePiece(el.id, n);
              },
              semanticLabel: name,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(
                    color: el.visible ? colors.text : colors.secondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
          _Small(
            icon: el.visible ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
            label: el.visible ? 'Hide' : 'Show',
            onTap: () => groupIds != null ? _each((id) => c.toggleVisible(id)) : c.toggleVisible(el.id),
          ),
          _Small(
            icon: el.locked ? CupertinoIcons.lock_fill : CupertinoIcons.lock_open,
            label: el.locked ? 'Unlock' : 'Lock',
            onTap: () => groupIds != null ? _each((id) => c.toggleLocked(id)) : c.toggleLocked(el.id),
          ),
        ],
      ),
    );
  }

  void _each(void Function(String id) f) => groupIds!.forEach(f);
}

class _Small extends StatelessWidget {
  const _Small({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Pressable(
      onPressed: onTap,
      semanticLabel: label,
      child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20, color: colors.secondary)),
    );
  }
}
