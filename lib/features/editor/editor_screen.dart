import 'package:flutter/cupertino.dart';

import '../../core/model/layout_doc.dart';
import '../../platform/gallery_saver.dart';
import '../../platform/photo_picker.dart';
import '../home/home_controller.dart' show PhotoItem;
import '../layouts/import_layout.dart' show safeFileName;
import '../../ui/app_theme.dart';
import '../../ui/widgets/action_sheet.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/icon_tile.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/segmented.dart';
import '../../ui/widgets/toast.dart';
import 'add_sheets.dart';
import 'editor_canvas.dart';
import 'editor_controller.dart';
import 'editor_shortcuts.dart';
import 'layers_sheet.dart';
import 'layout_settings_sheet.dart';
import 'panels/panels.dart';
import 'text_edit_sheet.dart';

/// The layout editor: a top bar, the canvas, and a strip of tools.
class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.controller,
    required this.picker,
    this.gallery,
    this.photos = const [],
    this.onMoreFonts,
  });

  final EditorController controller;
  final PhotoPicker picker;

  /// Where "Save layout as PNG" goes; the menu item is left out when null.
  final GallerySaver? gallery;

  /// The photos added on Home, for "Preview on".
  final List<PhotoItem> photos;

  /// Opens the fonts screen from the Font panel; the row is left out when null.
  final VoidCallback? onMoreFonts;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with WidgetsBindingObserver {
  EditorController get c => widget.controller;
  bool _closing = false;
  Tool? _tool;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.notice.addListener(_showNotice);
  }

  @override
  void dispose() {
    c.notice.removeListener(_showNotice);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never lose the last change when the app goes to the background.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      c.cancelDrag(keep: true);
      c.flushSave();
    }
  }

  void _showNotice() {
    final text = c.notice.value;
    if (text != null && mounted) showToast(context, text);
  }

  Future<void> _done() async {
    if (_closing) return;
    _closing = true;
    await c.close();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _rename() async {
    final name = await showTextPrompt(
      context,
      title: 'Rename layout',
      initial: c.doc.name,
      confirmLabel: 'Rename',
      placeholder: 'Layout name',
    );
    if (name != null) c.rename(name);
  }

  void _menu() {
    showActionSheet(
      context,
      actions: [
        SheetAction('Preview on', _previewMenu),
        SheetAction('Layout settings', () => showLayoutSettings(context, c)),
        if (widget.gallery != null) SheetAction('Save layout as PNG', _savePng),
      ],
    );
  }

  void _previewMenu() {
    final ready = [
      for (final p in widget.photos)
        if (p.preview != null) p,
    ];
    const most = 8;
    showActionSheet(
      context,
      title: 'Preview on',
      message: ready.length > most ? 'Showing the first $most of ${ready.length} photos.' : null,
      actions: [
        SheetAction('Sample scene', () => c.setPreview(PreviewKind.sample)),
        SheetAction('See-through background', () => c.setPreview(PreviewKind.none)),
        for (final p in ready.take(most)) SheetAction(p.name, () => c.setPreview(PreviewKind.photo, image: p.preview)),
      ],
    );
  }

  bool _savingPng = false;

  Future<void> _savePng() async {
    final gallery = widget.gallery;
    if (gallery == null || _savingPng) return;
    _savingPng = true;
    showToast(context, 'Making the picture');
    try {
      final bytes = await c.layoutPng(3000);
      final name = '${safeFileName(c.doc.name)}.png';
      await gallery.saveImage(bytes, name);
      if (mounted) {
        showToast(context, 'Saved $name to ${gallery.destinationLabel}. It is see-through, 3000 pixels wide.');
      }
    } on SaveCancelledException {
      // The person closed the save dialog.
    } catch (e) {
      debugPrint('Save layout as PNG failed: $e');
      if (mounted) showToast(context, "Couldn't save the picture. $e", icon: CupertinoIcons.exclamationmark_circle);
    } finally {
      _savingPng = false;
    }
  }

  /// The open panel, unless the selection no longer has that tool.
  Tool? get _activeTool {
    final t = _tool;
    if (t == null || !toolAvailable(t, c)) return null;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: CupertinoPageScaffold(
        backgroundColor: colors.page,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => EditorShortcuts(
            controller: c,
            child: Column(
            children: [
              _TopBar(controller: c, onDone: _done, onRename: _rename, onMenu: _menu),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: EditorCanvas(controller: c, onEditText: (el) => showTextEdit(context, c, el)),
                    ),
                    if (!c.shapeFixed)
                      Positioned(
                        top: 10,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Segmented<String>(
                            compact: true,
                            segments: const {'landscape': 'Landscape', 'portrait': 'Portrait', 'square': 'Square'},
                            value: c.ratioName,
                            onChanged: c.setRatio,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_activeTool != null)
                _ToolPanel(
                  controller: c,
                  tool: _activeTool!,
                  onMoreFonts: widget.onMoreFonts,
                  onDone: () => setState(() => _tool = null),
                )
              else
                _ToolStrip(controller: c, picker: widget.picker, onTool: (t) => setState(() => _tool = t)),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.onDone, required this.onRename, required this.onMenu});

  final EditorController controller;
  final VoidCallback onDone, onRename, onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final c = controller;
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              Pressable(
                onPressed: onDone,
                semanticLabel: 'Done',
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  child: Text('Done', style: AppText.button.copyWith(color: colors.accent)),
                ),
              ),
              Expanded(
                child: Pressable(
                  onPressed: onRename,
                  semanticLabel: 'Rename layout',
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.doc.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.headline.copyWith(color: colors.text),
                        ),
                        Text(
                          c.status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label.copyWith(color: c.statusBad ? colors.destructive : colors.secondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AppIconButton(
                icon: CupertinoIcons.arrow_uturn_left,
                label: 'Undo',
                color: colors.accent,
                onPressed: c.canUndo ? c.undo : null,
              ),
              AppIconButton(
                icon: CupertinoIcons.arrow_uturn_right,
                label: 'Redo',
                color: colors.accent,
                onPressed: c.canRedo ? c.redo : null,
              ),
              AppIconButton(
                icon: CupertinoIcons.ellipsis_circle,
                label: 'More',
                color: colors.accent,
                onPressed: onMenu,
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip({required this.controller, required this.picker, required this.onTool});

  final EditorController controller;
  final PhotoPicker picker;
  final void Function(Tool tool) onTool;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final c = controller;
    final tiles = <Widget>[];
    switch (c.selectionKind) {
      case SelectionKind.none:
        tiles.addAll([
          IconTile(icon: CupertinoIcons.textformat, label: 'Text', onPressed: () => showAddText(context, c)),
          IconTile(icon: CupertinoIcons.square_on_circle, label: 'Shape', onPressed: () => showAddShape(context, c)),
          IconTile(icon: CupertinoIcons.star, label: 'Icon', onPressed: () => showAddIcon(context, c)),
          IconTile(
            icon: CupertinoIcons.photo,
            label: 'Picture',
            onPressed: () => addPictureFromFiles(context, c, picker),
          ),
          IconTile(icon: CupertinoIcons.square_stack_3d_up, label: 'Layers', onPressed: () => showLayers(context, c)),
          IconTile(
            icon: CupertinoIcons.slider_horizontal_3,
            label: 'Layout',
            onPressed: () => showLayoutSettings(context, c),
          ),
        ]);
      case SelectionKind.single:
      case SelectionKind.group:
      case SelectionKind.multi:
        final one = c.single;
        final type = one?.type;
        IconTile tool(IconData icon, String label, Tool t) =>
            IconTile(icon: icon, label: label, onPressed: () => onTool(t));
        if (type == ElementType.text) {
          tiles.add(
            IconTile(icon: CupertinoIcons.pencil, label: 'Edit', onPressed: () => showTextEdit(context, c, one!)),
          );
          tiles.add(tool(CupertinoIcons.textformat_alt, 'Font', Tool.font));
          tiles.add(tool(CupertinoIcons.paintbrush, 'Colour', Tool.color));
          tiles.add(tool(CupertinoIcons.square, 'Outline', Tool.outline));
        } else if (type == ElementType.shape) {
          tiles.add(tool(CupertinoIcons.square_on_circle, 'Shape', Tool.shape));
          tiles.add(tool(CupertinoIcons.paintbrush, 'Fill', Tool.color));
          tiles.add(tool(CupertinoIcons.square, 'Border', Tool.outline));
        } else if (type == ElementType.image) {
          tiles.add(
            IconTile(
              icon: CupertinoIcons.arrow_2_squarepath,
              label: 'Replace',
              onPressed: () => replacePictureFromFiles(context, c, one!, picker),
            ),
          );
          tiles.add(tool(CupertinoIcons.crop, 'Fit', Tool.fit));
          tiles.add(
            IconTile(
              icon: CupertinoIcons.wand_stars,
              label: 'See-through',
              width: 80,
              onPressed: () => onTool(Tool.seeThrough),
            ),
          );
          tiles.add(tool(CupertinoIcons.square, 'Border', Tool.outline));
        } else if (type == ElementType.icon) {
          tiles.add(tool(CupertinoIcons.star, 'Icon', Tool.icon));
          tiles.add(tool(CupertinoIcons.paintbrush, 'Colour', Tool.color));
          tiles.add(tool(CupertinoIcons.circle, 'Badge', Tool.badge));
          tiles.add(tool(CupertinoIcons.square, 'Border', Tool.outline));
        }
        if (c.selectionKind == SelectionKind.multi) {
          tiles.add(IconTile(icon: CupertinoIcons.square_stack_3d_up, label: 'Group', onPressed: c.groupSelected));
        }
        if (c.selectedGroup != null) {
          tiles.add(
            IconTile(icon: CupertinoIcons.square_stack_3d_up_slash, label: 'Ungroup', onPressed: c.ungroupSelected),
          );
        }
        if (toolAvailable(Tool.align, c)) {
          tiles.add(tool(CupertinoIcons.rectangle_split_3x1, 'Align', Tool.align));
        }
        if (toolAvailable(Tool.space, c)) {
          tiles.add(tool(CupertinoIcons.arrow_left_right, 'Space', Tool.space));
        }
        tiles.addAll([
          tool(CupertinoIcons.moon, 'Shadow', Tool.shadow),
          tool(CupertinoIcons.circle_lefthalf_fill, 'Opacity', Tool.opacity),
          if (one != null) tool(CupertinoIcons.arrow_up_down_square, 'Position', Tool.position),
          tool(CupertinoIcons.sparkles, 'Effects', Tool.effects),
          IconTile(icon: CupertinoIcons.square_stack_3d_up, label: 'Layers', onPressed: () => showLayers(context, c)),
          IconTile(icon: CupertinoIcons.plus_square_on_square, label: 'Duplicate', onPressed: c.duplicateSelected),
          IconTile(icon: CupertinoIcons.trash, label: 'Delete', destructive: true, onPressed: c.removeSelected),
        ]);
    }
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Center(
            child: ListView(
              key: const ValueKey('tool-strip'),
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: tiles,
            ),
          ),
        ),
      ),
    );
  }
}

/// The tool's controls under the canvas; the canvas stays visible and updates live.
class _ToolPanel extends StatelessWidget {
  const _ToolPanel({required this.controller, required this.tool, required this.onDone, this.onMoreFonts});

  final EditorController controller;
  final Tool tool;
  final VoidCallback onDone;
  final VoidCallback? onMoreFonts;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final h = (MediaQuery.sizeOf(context).height * 0.5).clamp(250.0, 320.0);
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  const SizedBox(width: 88),
                  Expanded(
                    child: Text(
                      toolTitle(tool, controller.single ?? controller.selection.firstOrNull),
                      textAlign: TextAlign.center,
                      style: AppText.headline.copyWith(color: colors.text),
                    ),
                  ),
                  SizedBox(
                    width: 88,
                    child: Pressable(
                      onPressed: onDone,
                      semanticLabel: 'Done',
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.only(right: 16),
                        alignment: Alignment.centerRight,
                        child: Text('Done', style: AppText.button.copyWith(color: colors.accent)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('panel-scroll'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: PanelBody(controller: controller, tool: tool, onMoreFonts: onMoreFonts),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
