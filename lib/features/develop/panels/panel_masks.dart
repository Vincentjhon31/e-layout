import 'package:flutter/cupertino.dart';

import '../../../core/develop/masks.dart';
import '../../../core/develop/settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/widgets/action_sheet.dart';
import '../../../ui/widgets/app_button.dart';
import '../../../ui/widgets/pressable.dart';
import '../../../ui/widgets/segmented.dart';
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
///
/// On phones ([onDone] set) the panel draws its own title row, so the
/// selected mask's name, the way back to the list and its menu sit where
/// the other tools have their title, and the controls keep their room.
class MasksPanel extends StatelessWidget {
  const MasksPanel({super.key, required this.controller, this.onDone});
  final PhotoEditorController controller;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final m = c.selectedMask;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onDone != null || m != null)
            _TitleRow(controller: c, mask: m, onDone: onDone),
          Expanded(
            child: DevelopPanelShell(
              child: m == null
                  ? _MaskList(controller: c)
                  : _MaskTabs(controller: c, mask: m),
            ),
          ),
        ],
      );
    },
  );
}

// ---------- the title row ----------

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.controller, this.mask, this.onDone});
  final PhotoEditorController controller;
  final Mask? mask;
  final VoidCallback? onDone;

  void _menu(BuildContext context, Mask mask) {
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
            maxLength: kMaxMaskName,
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
    final m = mask;
    final done = onDone;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: m == null
                ? null
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Pressable(
                      key: const ValueKey('mask-back'),
                      onPressed: () => controller.selectMask(null),
                      semanticLabel: 'All masks',
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.chevron_left,
                              size: 20,
                              color: colors.accent,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Masks',
                              style: AppText.button.copyWith(
                                color: colors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: Text(
              m?.name ?? 'Masking',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.headline.copyWith(color: colors.text),
            ),
          ),
          SizedBox(
            width: 88,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (m != null)
                  Pressable(
                    key: const ValueKey('mask-menu'),
                    onPressed: () => _menu(context, m),
                    semanticLabel: 'Mask options',
                    child: SizedBox(
                      width: 40,
                      height: 44,
                      child: Icon(
                        CupertinoIcons.ellipsis_circle,
                        size: 24,
                        color: colors.accent,
                      ),
                    ),
                  ),
                if (done != null)
                  Pressable(
                    onPressed: done,
                    semanticLabel: 'Done',
                    child: Container(
                      height: 44,
                      constraints: const BoxConstraints(minWidth: 44),
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Done',
                        style: AppText.button.copyWith(color: colors.accent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

/// Three slider rows at most per tab, so every tab fits a 320 pt phone.
class _MaskTabs extends StatelessWidget {
  const _MaskTabs({required this.controller, required this.mask});
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

  /// Two sliders to a row; an odd last one takes the whole row.
  Widget _page(List<Setting> list) => SliderPage(
    children: [
      for (var i = 0; i < list.length; i += 2)
        if (i + 1 < list.length)
          SliderPair(
            left: _slider(list[i], _localLabels[list[i]]!),
            right: _slider(list[i + 1], _localLabels[list[i + 1]]!),
          )
        else
          _slider(list[i], _localLabels[list[i]]!),
    ],
  );

  @override
  Widget build(BuildContext context) => PanelTabs(
    tabs: {
      for (final t in kAdjustTabs.entries) t.key: () => _page(t.value),
      'Mask': () => _ShapeTab(controller: controller, mask: mask),
    },
  );
}

/// The mask's adjustment tabs and their settings, in order.
const Map<String, List<Setting>> kAdjustTabs = {
  'Light': [
    Setting.exposure,
    Setting.contrast,
    Setting.highlights,
    Setting.shadows,
    Setting.whites,
    Setting.blacks,
  ],
  'Colour': [
    Setting.temperature,
    Setting.tint,
    Setting.vibrance,
    Setting.saturation,
  ],
  'Effects': [Setting.texture, Setting.clarity, Setting.dehaze],
};

const Map<Setting, String> _localLabels = {
  Setting.exposure: 'Exposure',
  Setting.contrast: 'Contrast',
  Setting.highlights: 'Highlights',
  Setting.shadows: 'Shadows',
  Setting.whites: 'Whites',
  Setting.blacks: 'Blacks',
  Setting.temperature: 'Temperature',
  Setting.tint: 'Tint',
  Setting.vibrance: 'Vibrance',
  Setting.saturation: 'Saturation',
  Setting.texture: 'Texture',
  Setting.clarity: 'Clarity',
  Setting.dehaze: 'Dehaze',
};

String _opName(MaskOp op) => switch (op) {
  MaskOp.add => 'Added',
  MaskOp.subtract => 'Subtracted',
  MaskOp.intersect => 'Overlap only',
};

/// A small pill for picking one shape of the mask.
class _ShapeChip extends StatelessWidget {
  const _ShapeChip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      selected: on,
      child: Pressable(
        onPressed: onTap,
        semanticLabel: label,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: on ? colors.accent : colors.raised,
            borderRadius: BorderRadius.circular(18),
          ),
          // widthFactor keeps the pill as wide as its words.
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.captionStrong.copyWith(
                color: on ? colors.onAccent : colors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One shape at a time: chips pick it when there are several; its title row
/// holds Add, Subtract and Remove, and its controls take one row.
class _ShapeTab extends StatelessWidget {
  const _ShapeTab({required this.controller, required this.mask});
  final PhotoEditorController controller;
  final Mask mask;

  void _combine(BuildContext context, MaskOp op) => showMaskKinds(
    context,
    (shape) => controller.addComponent(mask.id, shape, op),
  );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    final comps = mask.components;
    if (comps.isEmpty) return const SizedBox.shrink();
    final i = c.selectedComponent;
    final comp = comps[i];
    final full = comps.length >= kMaxComponents;
    final title = comp.shape is BrushShape
        ? Align(
            alignment: Alignment.centerLeft,
            child: Segmented<bool>(
              compact: true,
              segments: const {false: 'Brush', true: 'Erase'},
              value: c.brushErase,
              onChanged: (v) => c.setBrush(erase: v),
            ),
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                maskShapeName(comp.shape),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.headline.copyWith(
                  color: colors.text,
                  fontSize: 15,
                ),
              ),
              if (i > 0)
                Text(
                  _opName(comp.op),
                  style: AppText.caption.copyWith(color: colors.secondary),
                ),
            ],
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (comps.length > 1) ...[
          Row(
            children: [
              for (var k = 0; k < comps.length; k++) ...[
                if (k > 0) const SizedBox(width: 4),
                Flexible(
                  child: _ShapeChip(
                    key: ValueKey('mask-shape-$k'),
                    label: 'Shape ${k + 1}',
                    on: k == i,
                    onTap: () => c.selectComponent(k),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
        ],
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Semantics(
                label: i > 0 ? _opName(comp.op) : null,
                child: _Badge(comp.shape, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(child: title),
              AppIconButton(
                key: const ValueKey('mask-op-add'),
                icon: CupertinoIcons.plus_circle,
                label: 'Add a shape',
                onPressed: full ? null : () => _combine(context, MaskOp.add),
              ),
              AppIconButton(
                key: const ValueKey('mask-op-subtract'),
                icon: CupertinoIcons.minus_circle,
                label: 'Subtract a shape',
                onPressed: full
                    ? null
                    : () => _combine(context, MaskOp.subtract),
              ),
              if (comps.length > 1)
                AppIconButton(
                  key: const ValueKey('mask-remove'),
                  icon: CupertinoIcons.trash,
                  label: 'Remove this shape',
                  color: colors.destructive,
                  onPressed: () => c.removeComponent(mask.id, i),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _controls(context, i, comp.shape),
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

  DevelopSlider _brush(
    String key,
    String label,
    double value,
    double min,
    double reset,
    void Function(double v) set,
  ) => DevelopSlider(
    key: ValueKey('mask-brush-$key'),
    label: label,
    value: value,
    min: min,
    max: key == 'size' ? 50 : 100,
    format: (v) => '${v.round()}',
    onStart: () {},
    onChanged: (v) => set(v.roundToDouble()),
    onEnd: () {},
    onReset: () => set(reset),
  );

  Widget _controls(BuildContext context, int i, MaskShape s) {
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
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _number(
                i,
                'feather',
                'Feather',
                s.feather,
                50,
                (v) => radial(feather: v),
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Invert',
                  style: AppText.subhead.copyWith(color: colors.text),
                ),
                SizedBox(
                  height: 36,
                  child: CupertinoSwitch(
                    key: ValueKey('mask-invert-$i'),
                    value: s.invert,
                    activeTrackColor: colors.accent,
                    onChanged: (v) =>
                        c.updateShape(mask.id, i, radial(invert: v)),
                  ),
                ),
              ],
            ),
          ],
        );
      case LinearShape():
        return const PanelNote(
          'Drag a line on the photo, or the middle dot to move both.',
        );
      case BrushShape():
        return _Triple(
          _brush(
            'size',
            'Size',
            c.brushSize * 100,
            1,
            5,
            (v) => c.setBrush(size: v / 100),
          ),
          _brush(
            'feather',
            'Feather',
            c.brushFeather,
            0,
            50,
            (v) => c.setBrush(feather: v),
          ),
          _brush(
            'flow',
            'Flow',
            c.brushFlow,
            0,
            100,
            (v) => c.setBrush(flow: v),
          ),
        );
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
        return _Triple(
          _number(
            i,
            'low',
            'Low',
            s.low * 100,
            50,
            (v) => range(low: (v / 100).clamp(0.0, s.high)),
          ),
          _number(
            i,
            'high',
            'High',
            s.high * 100,
            100,
            (v) => range(high: (v / 100).clamp(s.low, 1.0)),
          ),
          _number(i, 'smooth', 'Smooth', s.smooth, 20, (v) => range(smooth: v)),
        );
      case ColourRangeShape():
        return SliderPair(
          left: _number(
            i,
            'refine',
            'Refine',
            s.refine,
            50,
            (v) => ColourRangeShape(s.samples, refine: v),
          ),
          right: s.samples.isEmpty
              ? const PanelNote('Tap the photo to pick a colour.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Colours',
                      style: AppText.subhead.copyWith(color: colors.text),
                    ),
                    SizedBox(
                      height: 36,
                      child: Row(
                        children: [
                          for (final (r, g, b) in s.samples)
                            Container(
                              width: 18,
                              height: 18,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color.from(
                                  alpha: 1,
                                  red: r,
                                  green: g,
                                  blue: b,
                                ),
                                border: Border.all(color: colors.separator),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      case SubjectShape() || SkyShape() || BackgroundShape():
        return const PanelNote(
          'Found automatically. Brush or subtract to fix it.',
        );
    }
  }
}

/// Three sliders side by side.
class _Triple extends StatelessWidget {
  const _Triple(this.a, this.b, this.c);
  final Widget a, b, c;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: a),
      const SizedBox(width: 12),
      Expanded(child: b),
      const SizedBox(width: 12),
      Expanded(child: c),
    ],
  );
}
