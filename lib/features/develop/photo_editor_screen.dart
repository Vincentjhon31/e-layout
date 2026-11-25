import 'package:flutter/cupertino.dart';

import '../../ui/app_theme.dart';
import '../../ui/widgets/action_sheet.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/icon_tile.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/toast.dart';
import 'copy_sheet.dart';
import 'develop_canvas.dart';
import 'filmstrip.dart';
import 'panels/develop_slider.dart';
import 'panels/panel_colour.dart';
import 'panels/panel_detail.dart';
import 'panels/panel_effects.dart';
import 'panels/panel_light.dart';
import 'panels/panel_blur.dart';
import 'panels/panel_masks.dart';
import 'panels/panel_presets.dart';
import 'photo_editor_controller.dart';
import 'save_preset_sheet.dart';
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
  ToolPanel.masks => 'Masking',
  ToolPanel.blur => 'Lens blur',
};

IconData toolIcon(ToolPanel p) => switch (p) {
  ToolPanel.presets => CupertinoIcons.rectangle_stack,
  ToolPanel.light => CupertinoIcons.sun_max,
  ToolPanel.colour => CupertinoIcons.drop,
  ToolPanel.effects => CupertinoIcons.sparkles,
  ToolPanel.detail => CupertinoIcons.triangle,
  ToolPanel.masks => CupertinoIcons.circle_lefthalf_fill,
  ToolPanel.blur => CupertinoIcons.camera_viewfinder,
};

/// The controls of [panel]. On phones [onDone] closes the panel; the
/// Masking panel then draws its own title row (it holds the mask's name).
Widget toolPanelBody(
  BuildContext context,
  PhotoEditorController c,
  ToolPanel panel, {
  VoidCallback? onDone,
}) {
  switch (panel) {
    case ToolPanel.presets:
      return PresetsPanel(controller: c);
    case ToolPanel.light:
      return DevelopPanelShell(child: LightPanel(controller: c));
    case ToolPanel.colour:
      return DevelopPanelShell(child: ColourPanel(controller: c));
    case ToolPanel.effects:
      return DevelopPanelShell(child: EffectsPanel(controller: c));
    case ToolPanel.detail:
      return DevelopPanelShell(child: DetailPanel(controller: c));
    case ToolPanel.masks:
      return MasksPanel(controller: c, onDone: onDone);
    case ToolPanel.blur:
      return DevelopPanelShell(child: BlurPanel(controller: c));
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
        SheetAction('Copy to all', () => showCopyToAll(context, c)),
        SheetAction('Save as preset', () => showSavePreset(context, c)),
        SheetAction('Reset this photo', _reset, enabled: c.hasOwnChanges),
      ],
    );
  }

  Future<void> _reset() async {
    await c.resetPhoto();
    if (mounted) {
      showToast(
        context,
        'This photo is back to the shared preset.',
        icon: CupertinoIcons.checkmark_alt,
      );
    }
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
            select: () => (
              c.home.current != null,
              c.showLayout,
              c.panel == ToolPanel.masks && c.selectedMaskId != null,
              c.showOverlay,
            ),
            builder: (context) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.panel == ToolPanel.masks && c.selectedMaskId != null)
                  _OverlayToggle(
                    on: c.showOverlay,
                    onPressed: () => c.setShowOverlay(!c.showOverlay),
                  ),
                if (c.home.current != null) ...[
                  const SizedBox(width: 8),
                  _LayoutToggle(on: c.showLayout, onPressed: c.toggleLayout),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Show mask": the selected mask's area in red on the photo. The pill is
/// accent-filled while on, so on and off read apart at a glance.
class _OverlayToggle extends StatelessWidget {
  const _OverlayToggle({required this.on, required this.onPressed});
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fg = on ? colors.onAccent : const Color(0xFFFFFFFF);
    return Semantics(
      toggled: on,
      child: Pressable(
        key: const ValueKey('show-mask'),
        onPressed: onPressed,
        semanticLabel: 'Show mask',
        child: SizedBox(
          height: AppMetrics.minTouch,
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: on ? colors.accent : overlayPill(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    on
                        ? CupertinoIcons.circle_lefthalf_fill
                        : CupertinoIcons.circle,
                    size: 16,
                    color: fg,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Show mask',
                    style: AppText.captionStrong.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
          // Every tool fits on a 320 pt phone: tiles narrow to 44 at most.
          child: LayoutBuilder(
            builder: (context, box) {
              final tile = ((box.maxWidth - 8) / ToolPanel.values.length).clamp(
                44.0,
                64.0,
              );
              return Center(
                child: ListView(
                  key: const ValueKey('tool-strip'),
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  children: [
                    for (final p in ToolPanel.values)
                      IconTile(
                        icon: toolIcon(p),
                        label: toolTitle(p),
                        width: tile,
                        onPressed: () => onTool(p),
                      ),
                  ],
                ),
              );
            },
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
            if (panel != ToolPanel.masks)
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
                            style: AppText.button.copyWith(
                              color: colors.accent,
                            ),
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
                child: toolPanelBody(
                  context,
                  controller,
                  panel,
                  onDone: onDone,
                ),
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
            // Seven tools are too many words for a segmented control this
            // narrow, so they are the phone's tiles, the open one tinted.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth / ToolPanel.values.length;
                  return Row(
                    children: [
                      for (final p in ToolPanel.values)
                        IconTile(
                          icon: toolIcon(p),
                          label: toolTitle(p),
                          width: w,
                          selected: p == panel,
                          onPressed: () => controller.setPanel(p),
                        ),
                    ],
                  );
                },
              ),
            ),
            Container(height: 0.5, color: colors.separator),
            const SizedBox(height: 12),
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
