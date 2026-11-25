import 'package:flutter/cupertino.dart';

import '../../../core/develop/masks.dart';
import '../../../core/develop/settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/widgets/action_sheet.dart';
import '../../../ui/widgets/app_button.dart';
import '../../../ui/widgets/pressable.dart';
import '../../editor/panels/panel_widgets.dart';
import '../photo_editor_controller.dart';
import 'develop_slider.dart';

/// The add sheet's rows, in order, and the shape each one starts with.
final Map<String, MaskShape Function()> kMaskKinds = {
  'Subject': () => const SubjectShape(),
  'Sky': () => const SkyShape(),
  'Background': () => const BackgroundShape(),
  'Brush': () => BrushShape(const []),
  'Linear gradient': () => LinearShape(.5, .25, .5, .75),
  'Radial gradient': () => RadialShape(),
  'Brightness range': () => LuminanceRangeShape(),
  'Colour range': () => ColourRangeShape(const []),
};

/// What a shape is called in the panel.
String maskShapeName(MaskShape s) => switch (s) {
  SubjectShape() => 'Subject',
  SkyShape() => 'Sky',
  BackgroundShape() => 'Background',
  BrushShape() => 'Brush',
  LinearShape() => 'Linear gradient',
  RadialShape() => 'Radial gradient',
  LuminanceRangeShape() => 'Brightness range',
  ColourRangeShape() => 'Colour range',
};

/// The small square that stands for a mask: an icon per kind of shape on a
/// colour of its own, like the rows of the iOS Settings app.
(IconData, Color) _badge(MaskShape s) => switch (s) {
  SubjectShape() => (CupertinoIcons.person_fill, const Color(0xFFFF9500)),
  SkyShape() => (CupertinoIcons.cloud_sun_fill, const Color(0xFF0A84FF)),
  BackgroundShape() => (CupertinoIcons.photo_fill, const Color(0xFF5856D6)),
  BrushShape() => (CupertinoIcons.paintbrush_fill, const Color(0xFFFF2D55)),
  LinearShape() => (
    CupertinoIcons.square_split_1x2_fill,
    const Color(0xFF30A2B8),
  ),
  RadialShape() => (
    CupertinoIcons.smallcircle_fill_circle,
    const Color(0xFF34A853),
  ),
  LuminanceRangeShape() => (
    CupertinoIcons.sun_max_fill,
    const Color(0xFF8E8E93),
  ),
  ColourRangeShape() => (CupertinoIcons.eyedropper, const Color(0xFFE5392E)),
};

class _Badge extends StatelessWidget {
  const _Badge(this.shape, {this.size = 30});
  final MaskShape shape;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _badge(shape);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.6, color: const Color(0xFFFFFFFF)),
    );
  }
}

/// Opens the sheet of shapes; [onPick] gets a new shape of the chosen kind.
Future<void> showMaskKinds(
  BuildContext context,
  void Function(MaskShape shape) onPick,
) => showActionSheet(
  context,
  actions: [
    for (final e in kMaskKinds.entries)
      SheetAction(e.key, () => onPick(e.value())),
  ],
);

/// Masking: the photo's masks, and the selected mask's adjustments and
/// shapes.
class MasksPanel extends StatelessWidget {
  const MasksPanel({super.key, required this.controller});
  final PhotoEditorController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final m = c.selectedMask;
      if (m == null) {
        return DevelopPanelShell(child: _MaskList(controller: c));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MaskHeader(controller: c, mask: m),
          Expanded(
            child: DevelopPanelShell(
              child: PanelTabs(
                tabs: {
                  'Adjust': () => _AdjustTab(controller: c, mask: m),
                  'Mask': () => _ShapesTab(controller: c, mask: m),
                },
              ),
            ),
          ),
        ],
      );
    },
  );
}

// ---------- the list ----------

class _MaskList extends StatelessWidget {
  const _MaskList({required this.controller});
  final PhotoEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    final masks = c.masks;
    final full = masks.length >= kMaxMasks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelButton(
          key: const ValueKey('mask-add'),
          label: 'Add mask',
          icon: CupertinoIcons.plus,
          onTap: full ? null : () => showMaskKinds(context, c.addMask),
        ),
        if (full) ...[
          const SizedBox(height: 6),
          const PanelNote('8 masks is the most for one photo.'),
        ],
        const SizedBox(height: 4),
        if (masks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text(
                  'No masks yet.',
                  style: AppText.subhead.copyWith(color: colors.text),
                ),
                const SizedBox(height: 2),
                Text(
                  'A mask changes only part of the photo.',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: colors.secondary),
                ),
              ],
            ),
          ),
        for (var i = 0; i < masks.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: Container(height: 0.5, color: colors.separator),
            ),
          _MaskRow(controller: c, mask: masks[i]),
        ],
      ],
    );
  }
}

String _summary(Mask m) {
  final first = m.components.isEmpty
      ? 'No shape'
      : maskShapeName(m.components.first.shape);
  final more = m.components.length - 1;
  final parts = [
    first,
    if (more == 1) '1 more shape',
    if (more > 1) '$more more shapes',
    if (!m.visible) 'Hidden',
  ];
  return parts.join(' · ');
}

class _MaskRow extends StatelessWidget {
  const _MaskRow({required this.controller, required this.mask});
  final PhotoEditorController controller;
  final Mask mask;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final m = mask;
    return Pressable(
      key: ValueKey('mask-row-${m.id}'),
      onPressed: () => controller.selectMask(m.id),
      semanticLabel: m.name,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Opacity(
              opacity: m.visible ? 1 : 0.4,
              child: m.components.isEmpty
                  ? const SizedBox(width: 30)
                  : _Badge(m.components.first.shape),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(
                      color: m.visible ? colors.text : colors.secondary,
                    ),
                  ),
                  Text(
                    _summary(m),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: colors.secondary),
                  ),
                ],
              ),
            ),
            AppIconButton(
              key: ValueKey('mask-eye-${m.id}'),
              icon: m.visible ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
              label: m.visible ? 'Hide this mask' : 'Show this mask',
              color: m.visible ? colors.accent : colors.secondary,
              onPressed: () => controller.setMaskVisible(m.id, !m.visible),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: colors.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- one mask ----------

class _MaskHeader extends StatelessWidget {
  const _MaskHeader({required this.controller, required this.mask});
  final PhotoEditorController controller;
  final Mask mask;

  void _menu(BuildContext context) {
    final c = controller;
    final id = mask.id;
    showActionSheet(
      context,
      title: mask.name,
      actions: [
        SheetAction('Rename', () async {
          final name = await showTextPrompt(
            context,
            title: 'Rename mask',
            initial: mask.name,
            confirmLabel: 'Rename',
          );
          if (name != null) await c.renameMask(id, name);
        }),
        SheetAction('Delete mask', () => c.deleteMask(id), destructive: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final c = controller;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Pressable(
            key: const ValueKey('mask-back'),
            onPressed: () => c.selectMask(null),
            semanticLabel: 'All masks',
            child: SizedBox(
              width: 32,
              height: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Icon(
                  CupertinoIcons.chevron_left,
                  size: 22,
                  color: colors.accent,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              mask.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.headline.copyWith(color: colors.text),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            child: Center(
              child: PanelChip(
                label: 'Show mask',
                on: c.showOverlay,
                onTap: () => c.setShowOverlay(!c.showOverlay),
              ),
            ),
          ),
          Pressable(
            key: const ValueKey('mask-menu'),
            onPressed: () => _menu(context),
            semanticLabel: 'Mask options',
            child: SizedBox(
              width: 40,
              height: 44,
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  CupertinoIcons.ellipsis_circle,
                  size: 24,
                  color: colors.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const List<(Setting, String)> _localSliders = [
  (Setting.exposure, 'Exposure'),
  (Setting.contrast, 'Contrast'),
  (Setting.highlights, 'Highlights'),
  (Setting.shadows, 'Shadows'),
  (Setting.whites, 'Whites'),
  (Setting.blacks, 'Blacks'),
  (Setting.temperature, 'Temperature'),
  (Setting.tint, 'Tint'),
  (Setting.vibrance, 'Vibrance'),
  (Setting.saturation, 'Saturation'),
  (Setting.texture, 'Texture'),
  (Setting.clarity, 'Clarity'),
  (Setting.dehaze, 'Dehaze'),
];

/// The 13 local settings, two to a row.
class _AdjustTab extends StatelessWidget {
  const _AdjustTab({required this.controller, required this.mask});
  final PhotoEditorController controller;
  final Mask mask;

  DevelopSlider _slider(Setting s, String label) {
    final c = controller;
    final id = mask.id;
    final step = s == Setting.exposure ? 100.0 : 1.0;
    return DevelopSlider(
      key: ValueKey('slider-${s.name}'),
      label: label,
      value: mask.adjust[s] ?? s.neutral,
      min: s.min,
      max: s.max,
      format: (v) => formatSetting(s, v),
      onStart: c.beginChange,
      onChanged: (v) => c.previewMaskValue(id, s, (v * step).round() / step),
      onEnd: c.endChange,
      onReset: () => c.setMaskValue(id, s, s.neutral),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < _localSliders.length; i += 2) {
      final (s, l) = _localSliders[i];
      if (i + 1 < _localSliders.length) {
        final (s2, l2) = _localSliders[i + 1];
        rows.add(SliderPair(left: _slider(s, l), right: _slider(s2, l2)));
      } else {
        rows.add(_slider(s, l));
      }
    }
    return SliderPage(children: rows);
  }
}

String _opName(MaskOp op) => switch (op) {
  MaskOp.add => 'Added',
  MaskOp.subtract => 'Subtracted',
  MaskOp.intersect => 'Overlap only',
};

/// Each shape's controls, then Add and Subtract to combine more shapes.
class _ShapesTab extends StatelessWidget {
  const _ShapesTab({required this.controller, required this.mask});
  final PhotoEditorController controller;
  final Mask mask;

  void _combine(BuildContext context, MaskOp op) => showMaskKinds(
    context,
    (shape) => controller.addComponent(mask.id, shape, op),
  );

  @override
  Widget build(BuildContext context) {
    final comps = mask.components;
    final full = comps.length >= kMaxComponents;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < comps.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          _ComponentHeader(
            controller: controller,
            mask: mask,
            index: i,
            removable: comps.length > 1,
          ),
          ..._controls(context, i, comps[i].shape),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: PanelButton(
                key: const ValueKey('mask-op-add'),
                label: 'Add',
                icon: CupertinoIcons.plus,
                onTap: full ? null : () => _combine(context, MaskOp.add),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PanelButton(
                key: const ValueKey('mask-op-subtract'),
                label: 'Subtract',
                icon: CupertinoIcons.minus,
                onTap: full ? null : () => _combine(context, MaskOp.subtract),
              ),
            ),
          ],
        ),
        if (full) ...[
          const SizedBox(height: 6),
          const PanelNote('4 shapes is the most for one mask.'),
        ],
      ],
    );
  }

  /// A 0 to 100 slider for one number of shape [i]; a drag is one step.
  DevelopSlider _number(
    int i,
    String key,
    String label,
    double value,
    double neutral,
    MaskShape Function(double v) make,
  ) {
    final c = controller;
    final id = mask.id;
    return DevelopSlider(
      key: ValueKey('mask-$key-$i'),
      label: label,
      value: value,
      min: 0,
      max: 100,
      format: (v) => '${v.round()}',
      onStart: c.beginChange,
      onChanged: (v) => c.previewShape(id, i, make(v.roundToDouble())),
      onEnd: c.endChange,
      onReset: () => c.updateShape(id, i, make(neutral)),
    );
  }

  List<Widget> _controls(BuildContext context, int i, MaskShape s) {
    final c = controller;
    final colors = AppColors.of(context);
    switch (s) {
      case RadialShape():
        RadialShape radial({double? feather, bool? invert}) => RadialShape(
          cx: s.cx,
          cy: s.cy,
          rx: s.rx,
          ry: s.ry,
          angle: s.angle,
          feather: feather ?? s.feather,
          invert: invert ?? s.invert,
        );
        return [
          _number(
            i,
            'feather',
            'Feather',
            s.feather,
            50,
            (v) => radial(feather: v),
          ),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Invert',
                    style: AppText.subhead.copyWith(color: colors.text),
                  ),
                ),
                CupertinoSwitch(
                  key: ValueKey('mask-invert-$i'),
                  value: s.invert,
                  activeTrackColor: colors.accent,
                  onChanged: (v) =>
                      c.updateShape(mask.id, i, radial(invert: v)),
                ),
              ],
            ),
          ),
        ];
      case LinearShape():
        return const [PanelNote('Drag the lines on the photo to move it.')];
      case BrushShape():
        return [
          ChipWrap(
            children: [
              PanelChip(
                label: 'Brush',
                on: !c.brushErase,
                onTap: () => c.setBrush(erase: false),
              ),
              PanelChip(
                label: 'Erase',
                on: c.brushErase,
                onTap: () => c.setBrush(erase: true),
              ),
            ],
          ),
          const SizedBox(height: 6),
          DevelopSlider(
            key: const ValueKey('mask-brush-size'),
            label: 'Size',
            value: c.brushSize * 100,
            min: 1,
            max: 50,
            format: (v) => '${v.round()}',
            onStart: () {},
            onChanged: (v) => c.setBrush(size: v.roundToDouble() / 100),
            onEnd: () {},
            onReset: () => c.setBrush(size: 0.05),
          ),
          SliderPair(
            left: DevelopSlider(
              key: const ValueKey('mask-brush-feather'),
              label: 'Feather',
              value: c.brushFeather,
              min: 0,
              max: 100,
              format: (v) => '${v.round()}',
              onStart: () {},
              onChanged: (v) => c.setBrush(feather: v.roundToDouble()),
              onEnd: () {},
              onReset: () => c.setBrush(feather: 50),
            ),
            right: DevelopSlider(
              key: const ValueKey('mask-brush-flow'),
              label: 'Flow',
              value: c.brushFlow,
              min: 0,
              max: 100,
              format: (v) => '${v.round()}',
              onStart: () {},
              onChanged: (v) => c.setBrush(flow: v.roundToDouble()),
              onEnd: () {},
              onReset: () => c.setBrush(flow: 100),
            ),
          ),
        ];
      case LuminanceRangeShape():
        LuminanceRangeShape range({
          double? low,
          double? high,
          double? smooth,
        }) => LuminanceRangeShape(
          low: low ?? s.low,
          high: high ?? s.high,
          smooth: smooth ?? s.smooth,
        );
        return [
          SliderPair(
            left: _number(
              i,
              'low',
              'Low',
              s.low * 100,
              50,
              (v) => range(low: (v / 100).clamp(0.0, s.high)),
            ),
            right: _number(
              i,
              'high',
              'High',
              s.high * 100,
              100,
              (v) => range(high: (v / 100).clamp(s.low, 1.0)),
            ),
          ),
          _number(i, 'smooth', 'Smooth', s.smooth, 20, (v) => range(smooth: v)),
        ];
      case ColourRangeShape():
        return [
          if (s.samples.isEmpty)
            const PanelNote('Tap the photo to pick a colour.')
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (final (r, g, b) in s.samples)
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.from(alpha: 1, red: r, green: g, blue: b),
                        border: Border.all(color: colors.separator),
                      ),
                    ),
                ],
              ),
            ),
          _number(
            i,
            'refine',
            'Refine',
            s.refine,
            50,
            (v) => ColourRangeShape(s.samples, refine: v),
          ),
        ];
      case SubjectShape() || SkyShape() || BackgroundShape():
        return const [
          PanelNote('Found automatically. Brush or subtract to fix it.'),
        ];
    }
  }
}

class _ComponentHeader extends StatelessWidget {
  const _ComponentHeader({
    required this.controller,
    required this.mask,
    required this.index,
    required this.removable,
  });

  final PhotoEditorController controller;
  final Mask mask;
  final int index;
  final bool removable;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final comp = mask.components[index];
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          _Badge(comp.shape, size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              maskShapeName(comp.shape),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.headline.copyWith(
                color: colors.text,
                fontSize: 15,
              ),
            ),
          ),
          if (index > 0) ...[
            const SizedBox(width: 8),
            Text(
              _opName(comp.op),
              style: AppText.caption.copyWith(color: colors.secondary),
            ),
          ],
          const Spacer(),
          if (removable)
            AppIconButton(
              key: ValueKey('mask-remove-$index'),
              icon: CupertinoIcons.xmark_circle_fill,
              label: 'Remove this shape',
              iconSize: 20,
              color: colors.secondary,
              onPressed: () => controller.removeComponent(mask.id, index),
            ),
        ],
      ),
    );
  }
}
