import 'package:flutter/cupertino.dart';

import '../../core/develop/settings.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/action_sheet.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/icon_tile.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/segmented.dart';
import '../../ui/widgets/sheet_scaffold.dart';
import '../../ui/widgets/toast.dart';
import '../home/export_job.dart' show plural;
import 'develop_canvas.dart';
import 'filmstrip.dart';
import 'photo_editor_controller.dart';
import 'select_builder.dart';

/// Windows at least this wide get the tools as a panel beside the photo.
/// Home has no single switch point: its grid gains columns from 744 pt and
/// computers open at least 900 wide, so 900 is where a window counts as wide.
const double kEditorWideWidth = 900;

/// Width of the tool panel on wide windows.
const double kEditorSidePanel = 360;

String toolTitle(ToolPanel p) => switch (p) {
  ToolPanel.presets => 'Presets',
  ToolPanel.light => 'Light',
  ToolPanel.colour => 'Colour',
  ToolPanel.effects => 'Effects',
  ToolPanel.detail => 'Detail',
};

IconData toolIcon(ToolPanel p) => switch (p) {
  ToolPanel.presets => CupertinoIcons.rectangle_stack,
  ToolPanel.light => CupertinoIcons.sun_max,
  ToolPanel.colour => CupertinoIcons.drop,
  ToolPanel.effects => CupertinoIcons.sparkles,
  ToolPanel.detail => CupertinoIcons.triangle,
};

/// The controls of [panel]. Tasks 17 and 18 fill these in; until then each
/// is an empty area of the panel's size.
Widget toolPanelBody(
  BuildContext context,
  PhotoEditorController c,
  ToolPanel panel,
) {
  switch (panel) {
    case ToolPanel.presets:
      return const SizedBox.expand();
    case ToolPanel.light:
      return const SizedBox.expand();
    case ToolPanel.colour:
      return const SizedBox.expand();
    case ToolPanel.effects:
      return const SizedBox.expand();
    case ToolPanel.detail:
      return const SizedBox.expand();
  }
}

/// The photo editor: a top bar, the photo, the filmstrip and the tools.
class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, required this.controller});

  final PhotoEditorController controller;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen>
    with WidgetsBindingObserver {
  PhotoEditorController get c => widget.controller;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_closeWhenEmpty);
  }

  @override
  void dispose() {
    c.removeListener(_closeWhenEmpty);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Home lost every photo (cleared elsewhere): nothing is left to edit.
  void _closeWhenEmpty() {
    if (!c.empty || _closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A slider still held when the app goes away keeps its value.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (c.changing) c.endChange();
    }
  }

  Future<void> _done() async {
    if (_closing) return;
    _closing = true;
    if (c.changing) await c.endChange();
    if (mounted) Navigator.of(context).pop();
  }

  void _menu() {
    showActionSheet(
      context,
      actions: [
        SheetAction('Copy to all', _copyToAll),
        SheetAction('Save as preset', _saveAsPreset),
        SheetAction('Reset this photo', _reset),
      ],
    );
  }

  void _copyToAll() {
    final n = c.photos.length - 1;
    final photos = plural(n, 'photo', 'photos');
    showAppSheet<void>(
      context,
      (ctx) => SheetScaffold(
        title: 'Copy to all photos',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "This photo's light, colour, effects and detail go to every photo. Changes made on single photos stay.",
              style: AppText.subhead.copyWith(
                color: AppColors.of(ctx).secondary,
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Copy to $photos',
              onPressed: n <= 0
                  ? null
                  : () async {
                      Navigator.of(ctx).pop();
                      await c.copyToAll(
                        ToolGroup.values.toSet(),
                        keepSingle: true,
                      );
                      if (mounted) {
                        showToast(
                          context,
                          'Copied to $photos.',
                          icon: CupertinoIcons.checkmark_alt,
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _saveAsPreset() {
    showAppSheet<void>(
      context,
      (ctx) => _SavePresetSheet(
        onSave: (name) async {
          try {
            await c.saveAsPreset(name);
          } catch (e) {
            debugPrint('Could not save the preset: $e');
            if (mounted) {
              showToast(
                context,
                "Couldn't save the preset.",
                icon: CupertinoIcons.exclamationmark_circle,
              );
            }
            return;
          }
          if (mounted) {
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

  Future<void> _reset() async {
    if (!c.hasOwnChanges) {
      showToast(context, 'This photo already follows the shared preset.');
      return;
    }
    await c.resetPhoto();
    if (mounted) showToast(context, 'This photo is back to the shared preset.');
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
        // Only what the frame shows: a slider's ticks redraw the canvas
        // and the panel, not the bars around them.
        child: SelectBuilder(
          listenable: c,
          select: () => c.panel,
          builder: (context) => LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= kEditorWideWidth;
              final top = _TopBar(controller: c, onDone: _done, onMenu: _menu);
              final photo = _PhotoArea(controller: c);
              if (wide) {
                final panel = c.panel ?? ToolPanel.presets;
                return Column(
                  children: [
                    top,
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(child: photo),
                                SafeArea(
                                  top: false,
                                  right: false,
                                  child: Filmstrip(controller: c),
                                ),
                              ],
                            ),
                          ),
                          _SidePanel(controller: c, panel: panel),
                        ],
                      ),
                    ),
                  ],
                );
              }
              final panel = c.panel;
              return Column(
                children: [
                  top,
                  Expanded(child: photo),
                  Filmstrip(controller: c),
                  if (panel != null)
                    _PanelArea(
                      controller: c,
                      panel: panel,
                      onDone: () => c.setPanel(null),
                    )
                  else
                    _ToolStrip(onTool: c.setPanel),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.onDone,
    required this.onMenu,
  });

  final PhotoEditorController controller;
  final VoidCallback onDone, onMenu;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SelectBuilder(
      listenable: c,
      select: () => (
        c.photo.id,
        c.photo.name,
        c.index,
        c.photos.length,
        c.canUndo,
        c.canRedo,
      ),
      builder: (context) => _bar(context),
    );
  }

  Widget _bar(BuildContext context) {
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
                  child: Text(
                    'Done',
                    style: AppText.button.copyWith(color: colors.accent),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      c.photo.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.headline.copyWith(color: colors.text),
                    ),
                    Text(
                      '${c.index + 1} of ${c.photos.length}',
                      style: AppText.label.copyWith(
                        color: colors.secondary,
                        fontFeatures: AppText.tabular,
                      ),
                    ),
                  ],
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

/// The canvas with the "Layout" switch in its corner.
class _PhotoArea extends StatelessWidget {
  const _PhotoArea({required this.controller});
  final PhotoEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Stack(
      children: [
        Positioned.fill(child: DevelopCanvas(controller: c)),
        // In the band the canvas keeps free at its top, off the photo.
        Positioned(
          top: 4,
          right: 8,
          child: SelectBuilder(
            listenable: c,
            select: () => (c.home.current != null, c.showLayout),
            builder: (context) => c.home.current == null
                ? const SizedBox.shrink()
                : _LayoutToggle(on: c.showLayout, onPressed: c.toggleLayout),
          ),
        ),
      ],
    );
  }
}

class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({required this.on, required this.onPressed});
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const white = Color(0xFFFFFFFF);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: on ? 'Hide the layout' : 'Show the layout',
      child: SizedBox(
        height: AppMetrics.minTouch,
        child: Center(
          widthFactor: 1,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: overlayPill(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  on ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  size: 16,
                  color: white,
                ),
                const SizedBox(width: 6),
                Text(
                  'Layout',
                  style: AppText.captionStrong.copyWith(color: white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip({required this.onTool});
  final ValueChanged<ToolPanel> onTool;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
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
              children: [
                for (final p in ToolPanel.values)
                  IconTile(
                    icon: toolIcon(p),
                    label: toolTitle(p),
                    onPressed: () => onTool(p),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tool's panel in place of the strip; the photo stays visible above it.
class _PanelArea extends StatelessWidget {
  const _PanelArea({
    required this.controller,
    required this.panel,
    required this.onDone,
  });

  final PhotoEditorController controller;
  final ToolPanel panel;
  final VoidCallback onDone;

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
                      toolTitle(panel),
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
                        child: Text(
                          'Done',
                          style: AppText.button.copyWith(color: colors.accent),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: toolPanelBody(context, controller, panel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wide windows: the current tool beside the photo, the tools as a row on top.
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.controller, required this.panel});

  final PhotoEditorController controller;
  final ToolPanel panel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: kEditorSidePanel,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(left: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Segmented<ToolPanel>(
                compact: true,
                segments: {for (final p in ToolPanel.values) p: toolTitle(p)},
                value: panel,
                onChanged: controller.setPanel,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: toolPanelBody(context, controller, panel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Save as preset": a name, then Save. (Task 18 gives it its final form.)
class _SavePresetSheet extends StatefulWidget {
  const _SavePresetSheet({required this.onSave});
  final Future<void> Function(String name) onSave;

  @override
  State<_SavePresetSheet> createState() => _SavePresetSheetState();
}

class _SavePresetSheetState extends State<_SavePresetSheet> {
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
            maxLength: 80,
            style: AppText.body.copyWith(color: colors.text),
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
