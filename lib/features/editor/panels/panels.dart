import 'package:flutter/cupertino.dart';

import '../../../core/model/layout_doc.dart';
import '../editor_controller.dart';
import 'panel_fill.dart';
import 'panel_pieces.dart';
import 'panel_position.dart';
import 'panel_style.dart';
import 'panel_text.dart';

export 'panel_widgets.dart' show editSelected, usedColors;

/// The tools that open a panel under the canvas.
enum Tool {
  font,
  color,
  outline,
  shadow,
  opacity,
  position,
  effects,
  shape,
  fit,
  seeThrough,
  icon,
  badge,
  align,
  space,
}

String toolTitle(Tool t, LayoutElement? el) => switch (t) {
  Tool.font => 'Font',
  Tool.color => el?.type == ElementType.shape ? 'Fill' : 'Colour',
  Tool.outline => el?.type == ElementType.text ? 'Outline' : 'Border',
  Tool.shadow => 'Shadow',
  Tool.opacity => 'Opacity',
  Tool.position => 'Position',
  Tool.effects => 'Effects',
  Tool.shape => 'Shape',
  Tool.fit => 'Fit',
  Tool.seeThrough => 'See-through',
  Tool.icon => 'Icon',
  Tool.badge => 'Badge',
  Tool.align => 'Align',
  Tool.space => 'Space evenly',
};

/// Whether [t] still makes sense for the current selection (it may change
/// under an open panel: undo, delete, a tap on another piece).
bool toolAvailable(Tool t, EditorController c) {
  if (c.selection.isEmpty) return false;
  final type = c.single?.type;
  return switch (t) {
    Tool.font => type == ElementType.text,
    Tool.position => c.single != null,
    Tool.shape => type == ElementType.shape,
    Tool.fit || Tool.seeThrough => type == ElementType.image,
    Tool.icon || Tool.badge => type == ElementType.icon,
    Tool.align => c.selectionKind == SelectionKind.multi || c.selectionKind == SelectionKind.group,
    Tool.space => c.selectionKind == SelectionKind.multi,
    _ => true,
  };
}

/// The body of the panel for [tool]; rebuilds when the document changes.
class PanelBody extends StatelessWidget {
  const PanelBody({super.key, required this.controller, required this.tool, this.onMoreFonts});
  final EditorController controller;
  final Tool tool;

  /// Opens the fonts screen from the Font panel.
  final VoidCallback? onMoreFonts;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final el = c.single ?? (c.selection.isEmpty ? null : c.selection.first);
    if (el == null) return const SizedBox.shrink();
    return switch (tool) {
      Tool.font => FontPanel(controller: c, el: el, onMoreFonts: onMoreFonts),
      Tool.color => ColorPanel(controller: c, el: el),
      Tool.outline => OutlinePanel(controller: c, el: el),
      Tool.shadow => ShadowPanel(controller: c, el: el),
      Tool.opacity => OpacityPanel(controller: c, el: el),
      Tool.position => PositionPanel(controller: c, el: el),
      Tool.effects => EffectsPanel(controller: c, el: el),
      Tool.shape => ShapePanel(controller: c, el: el),
      Tool.fit => FitPanel(controller: c, el: el),
      Tool.seeThrough => SeeThroughPanel(controller: c, el: el),
      Tool.icon => IconPanel(controller: c, el: el),
      Tool.badge => BadgePanel(controller: c, el: el),
      Tool.align => AlignPanel(controller: c),
      Tool.space => SpacePanel(controller: c),
    };
  }
}
