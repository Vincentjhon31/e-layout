import 'package:flutter/cupertino.dart';

import '../../../core/model/layout_doc.dart';
import '../../../core/model/layout_ops.dart' as ops;
import '../../../ui/widgets/labeled_slider.dart';
import '../editor_controller.dart';
import 'panel_widgets.dart';

const Map<String, String> _pinWords = {
  'top': 'the top',
  'center': 'the middle',
  'bottom': 'the bottom',
  'stretch': 'both the top and the bottom',
};

/// Place, size, turn, tilt, flip, "Stays at" and align to the photo, in
/// three pages: Place, Turn and Stays.
class PositionPanel extends StatelessWidget {
  const PositionPanel({super.key, required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    return PanelTabs(
      tabs: {
        'Place': () => _Place(controller: controller, el: el),
        'Turn': () => _Turn(controller: controller, el: el),
        'Tilt': () => _Tilt(controller: controller, el: el),
        'Stays': () => _Stays(controller: controller, el: el),
        'Align': () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _AlignChips(controller),
            const SizedBox(height: 10),
            const PanelNote('Lines this piece up with the photo.'),
          ],
        ),
      },
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final fh = c.frameH;
    final b = c.boxOfEl(el);
    final text = el.type == ElementType.text;
    // Pictures and icons keep their proportions when one side changes.
    final linked = el.type == ElementType.image || el.type == ElementType.icon;
    void box(Rect Function(Rect b) f) => c.change(() {
      final now = c.byId(el.id);
      if (now == null) return;
      ops.setBox(now, f(c.boxOfEl(now)), c.frameH);
      c.repin([now]);
    }, 'box:${el.id}');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LabeledSlider(
          sliderHeight: 36,
          label: 'Across',
          value: b.left,
          min: -c.doc.width / 2,
          max: c.doc.width * 1.5 - b.width,
          onChanged: (v) => box((r) => Rect.fromLTWH(v.roundToDouble(), r.top, r.width, r.height)),
        ),
        LabeledSlider(
          sliderHeight: 36,
          label: 'Down',
          value: b.top,
          min: -fh / 2,
          max: fh * 1.5 - b.height,
          onChanged: (v) => box((r) => Rect.fromLTWH(r.left, v.roundToDouble(), r.width, r.height)),
        ),
        if (!text)
          LabeledSlider(
            sliderHeight: 36,
            label: 'Width',
            value: b.width,
            min: 4,
            max: c.doc.width * 1.5,
            onChanged: (v) => box(
              (r) => Rect.fromLTWH(
                r.left,
                r.top,
                v.roundToDouble(),
                linked ? r.height * v.roundToDouble() / r.width : r.height,
              ),
            ),
          ),
        if (!text)
          LabeledSlider(
            sliderHeight: 36,
            label: 'Height',
            value: b.height,
            min: 4,
            max: fh * 1.5,
            onChanged: (v) => box(
              (r) => Rect.fromLTWH(
                r.left,
                r.top,
                linked ? r.width * v.roundToDouble() / r.height : r.width,
                v.roundToDouble(),
              ),
            ),
          ),
        if (text) const PanelNote('Change the size of a text in its Font panel.'),
      ],
    );
  }
}

class _Turn extends StatelessWidget {
  const _Turn({required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LabeledSlider(
          sliderHeight: 36,
          label: 'Turn',
          value: el.rotation,
          min: -180,
          max: 180,
          format: (v) => '${v.round()}°',
          onChanged: (v) => editSelected(c, 'rotate', (e) => e.rotation = v.roundToDouble()),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: PanelButton(
                label: 'Flip left-right', onTap: () => c.flip(horizontal: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PanelButton(
                label: 'Flip up-down', onTap: () => c.flip(horizontal: false),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Tilt extends StatelessWidget {
  const _Tilt({required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LabeledSlider(
          sliderHeight: 36,
          label: 'Tilt sideways',
          value: el.skewX,
          min: -70,
          max: 70,
          format: (v) => '${v.round()}°',
          onChanged: (v) => editSelected(c, 'skewx', (e) => e.skewX = v.roundToDouble()),
        ),
        LabeledSlider(
          sliderHeight: 36,
          label: 'Tilt up or down',
          value: el.skewY,
          min: -70,
          max: 70,
          format: (v) => '${v.round()}°',
          onChanged: (v) => editSelected(c, 'skewy', (e) => e.skewY = v.roundToDouble()),
        ),
      ],
    );
  }
}

class _Stays extends StatelessWidget {
  const _Stays({required this.controller, required this.el});
  final EditorController controller;
  final LayoutElement el;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final group = el.group != null ? c.doc.groups[el.group] : null;
    final current = el.pinAuto == false ? el.pin.name : 'auto';
    final words = _pinWords[el.pin.name] ?? 'the middle';
    final note = group != null
        ? 'Stays at $words together with the rest of ${group.name}. To change this, select the whole group.'
        : el.pinAuto == false
        ? 'Stays at $words, wherever you move it.'
        : "Now: stays at $words, because that's the part of the photo it sits in. Move it and this follows.";
    const choices = {'auto': 'Auto', 'top': 'Top', 'center': 'Middle', 'bottom': 'Bottom', 'stretch': 'Stretch'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (group == null) const PanelNote('Stays at, on taller or wider photos'),
        if (group == null) const SizedBox(height: 6),
        if (group == null)
          ChipWrap(
            children: [
              for (final e in choices.entries)
                PanelChip(label: e.value, on: current == e.key, onTap: () => c.setPinChoice(e.key)),
            ],
          ),
        if (group == null) const SizedBox(height: 8),
        PanelNote(note),
      ],
    );
  }
}

class _AlignChips extends StatelessWidget {
  const _AlignChips(this.controller);
  final EditorController controller;

  @override
  Widget build(BuildContext context) => ChipWrap(
    children: [
      for (final e in kAlignChoices.entries) PanelChip(label: e.value, on: false, onTap: () => controller.align(e.key)),
    ],
  );
}

const Map<String, String> kAlignChoices = {
  'left': 'Left',
  'center': 'Centre',
  'right': 'Right',
  'top': 'Top',
  'middle': 'Middle',
  'bottom': 'Bottom',
};

/// Several pieces line up with each other.
class AlignPanel extends StatelessWidget {
  const AlignPanel({super.key, required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final one = c.selectionKind != SelectionKind.multi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChipWrap(
          children: [
            for (final e in kAlignChoices.entries) PanelChip(label: e.value, on: false, onTap: () => c.align(e.key)),
          ],
        ),
        const SizedBox(height: 10),
        PanelNote(one ? 'Lines this group up with the photo.' : 'Lines the pieces up with each other.'),
      ],
    );
  }
}

/// Equal gaps between three or more pieces.
class SpacePanel extends StatelessWidget {
  const SpacePanel({super.key, required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ok = c.unitsOfSelection >= 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChipWrap(
          children: [
            PanelChip(label: 'Across', on: false, onTap: ok ? () => c.distribute('x') : null),
            PanelChip(label: 'Up and down', on: false, onTap: ok ? () => c.distribute('y') : null),
          ],
        ),
        const SizedBox(height: 10),
        PanelNote(
          ok
              ? 'Makes the gaps between the pieces equal. The outer two stay where they are.'
              : 'Select three or more pieces to space them evenly.',
        ),
      ],
    );
  }
}
