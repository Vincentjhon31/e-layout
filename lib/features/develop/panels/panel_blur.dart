import 'package:flutter/cupertino.dart';

import '../../../core/develop/masks.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/widgets/action_sheet.dart';
import '../../../ui/widgets/pressable.dart';
import '../../../ui/widgets/segmented.dart';
import '../../editor/panels/panel_widgets.dart';
import '../photo_editor_controller.dart';
import 'develop_slider.dart';

/// Lens blur: how much the background blurs, what stays sharp, and how
/// softly the blur starts. Tapping the photo moves a Point focus.
class BlurPanel extends StatelessWidget {
  const BlurPanel({super.key, required this.controller});
  final PhotoEditorController controller;

  DevelopSlider _slider(
    String key,
    String label,
    double value,
    LensBlur Function(LensBlur l, double v) change,
    double neutral,
  ) {
    final c = controller;
    return DevelopSlider(
      key: ValueKey(key),
      label: label,
      value: value,
      min: 0,
      max: 100,
      format: (v) => '${v.round()}',
      onStart: c.beginChange,
      onChanged: (v) => c.previewLens(change(c.lensBlur, v.roundToDouble())),
      onEnd: c.endChange,
      onReset: () => c.setLens(change(c.lensBlur, neutral)),
    );
  }

  /// Chooses the focus. Mask needs a mask: the selected one, or the first.
  void _focus(LensFocus f) {
    final c = controller;
    final l = c.lensBlur;
    if (f == LensFocus.mask) {
      final masks = c.masks;
      if (masks.isEmpty) return;
      final has = masks.any((m) => m.id == l.maskId);
      final id = has ? l.maskId! : (c.selectedMaskId ?? masks.first.id);
      c.setLens(lensWith(l, focus: f, maskId: id));
    } else {
      c.setLens(lensWith(l, focus: f));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final l = c.lensBlur;
      final colors = AppColors.of(context);
      // Full 44 pt rows where the panel has room (small phones keep them tight).
      final roomy = PanelSpace.of(context) >= 250;
      final hint =
          l.focus == LensFocus.mask &&
          !c.masks.any((m) => m.id == l.maskId && m.components.isNotEmpty);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _slider(
            'slider-lens-amount',
            'Amount',
            l.amount,
            (l, v) => lensWith(l, amount: v),
            0,
          ),
          if (l.amount <= 0)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: PanelNote('Raise Amount to blur the background.'),
            ),
          SizedBox(height: l.focus == LensFocus.mask ? 2 : 4),
          Segmented<LensFocus>(
            key: const ValueKey('lens-focus'),
            segments: const {
              LensFocus.subject: 'Subject',
              LensFocus.point: 'Point',
              LensFocus.mask: 'Mask',
            },
            value: l.focus,
            disabled: c.masks.isEmpty ? const {LensFocus.mask} : const {},
            onChanged: _focus,
          ),
          if (l.focus == LensFocus.mask) ...[
            const SizedBox(height: 3),
            _MaskPicker(controller: c, roomy: roomy),
            // The render keeps the subject sharp without a usable mask.
            if (hint) const _FocusHint(),
          ],
          // Tight only when the mask picker needs the room (small phones).
          SizedBox(height: l.focus == LensFocus.mask ? (hint ? 0 : 2) : 8),
          SliderPair(
            left: _slider(
              'slider-lens-transition',
              'Transition',
              l.transition,
              (l, v) => lensWith(l, transition: v),
              50,
            ),
            right: _slider(
              'slider-lens-boost',
              'Bokeh highlights',
              l.boost,
              (l, v) => lensWith(l, boost: v),
              0,
            ),
          ),
          SizedBox(
            height: roomy ? 44 : 32,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Show focus',
                    style: AppText.subhead.copyWith(color: colors.text),
                  ),
                ),
                CupertinoSwitch(
                  key: const ValueKey('lens-show-focus'),
                  value: c.showFocus,
                  activeTrackColor: colors.accent,
                  onChanged: c.setShowFocus,
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// Under the mask picker while no mask is chosen: what the render does
/// meanwhile. Tight lines, so the panel still fits.
class _FocusHint extends StatelessWidget {
  const _FocusHint();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      'Until you choose one, the subject stays sharp.',
      style: AppText.caption.copyWith(
        color: AppColors.of(context).secondary,
        height: 1.1,
      ),
    ),
  );
}

/// The mask that stays sharp: one row that opens the list of masks by name.
/// A mask that is gone (deleted, or undone away) shows "Choose a mask".
class _MaskPicker extends StatelessWidget {
  const _MaskPicker({required this.controller, required this.roomy});
  final PhotoEditorController controller;
  final bool roomy;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    Mask? chosen;
    for (final m in c.masks) {
      if (m.id == c.lensBlur.maskId) chosen = m;
    }
    return Pressable(
      key: const ValueKey('lens-mask-picker'),
      semanticLabel: chosen?.name ?? 'Choose a mask',
      onPressed: () => showActionSheet(
        context,
        title: 'Keep this mask sharp',
        actions: [
          for (final m in c.masks)
            SheetAction(
              m.name,
              () => c.setLens(lensWith(c.lensBlur, maskId: m.id)),
            ),
        ],
      ),
      child: Container(
        height: roomy ? 44 : 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.raised,
          borderRadius: BorderRadius.circular(AppMetrics.buttonRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                chosen?.name ?? 'Choose a mask',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.subhead.copyWith(
                  color: chosen == null ? colors.secondary : colors.text,
                ),
              ),
            ),
            Icon(
              CupertinoIcons.chevron_up_chevron_down,
              size: 16,
              color: colors.secondary,
            ),
          ],
        ),
      ),
    );
  }
}
