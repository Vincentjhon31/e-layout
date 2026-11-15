import 'package:flutter/cupertino.dart';

import '../../../core/model/layout_doc.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/widgets/pressable.dart';
import '../../../ui/widgets/segmented.dart';
import '../editor_controller.dart';

/// Applies [fn] to every selected piece as one undo step; a drag with the
/// same [key] within 1.2 s stays one step. Texts are re-measured and pieces
/// re-pinned afterwards.
void editSelected(EditorController c, String key, void Function(LayoutElement el) fn, {bool remeasure = false}) {
  c.change(() {
    for (final el in c.selection) {
      fn(el);
      if (remeasure && el.type == ElementType.text) c.fitText(el);
    }
    c.repin(c.selection);
  }, '$key:${c.sel.join(',')}');
}

/// Colours already used by the layout, for the picker's swatches.
List<String> usedColors(LayoutDoc doc) {
  final out = <String>{};
  for (final e in doc.elements) {
    out.add(e.fill.color.toUpperCase());
    if (e.stroke.width > 0) out.add(e.stroke.color.toUpperCase());
    for (final s in e.fill.stops) {
      out.add(s.color.toUpperCase());
    }
  }
  return out.toList();
}

/// A pill button: filled when [on], grey otherwise.
class PanelChip extends StatelessWidget {
  const PanelChip({super.key, required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Pressable(
        onPressed: onTap,
        semanticLabel: label,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: on ? colors.accent : colors.raised, borderRadius: BorderRadius.circular(18)),
          // widthFactor keeps the pill as wide as its words inside a Wrap.
          child: Center(
            widthFactor: 1,
            child: Text(label, style: AppText.subhead.copyWith(color: on ? colors.onAccent : colors.text)),
          ),
        ),
      ),
    );
  }
}

/// A row of chips that wraps onto more lines when it must.
class ChipWrap extends StatelessWidget {
  const ChipWrap({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: children);
}

/// A tinted button for one action inside a panel (44 pt tall).
class PanelButton extends StatelessWidget {
  const PanelButton({super.key, required this.label, required this.onTap, this.icon, this.destructive = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fg = destructive ? colors.destructive : colors.accent;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Pressable(
        onPressed: onTap,
        semanticLabel: label,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: fg.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppMetrics.buttonRadius),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 6)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.button.copyWith(color: fg, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small note under a control.
class PanelNote extends StatelessWidget {
  const PanelNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppText.caption.copyWith(color: AppColors.of(context).secondary));
}

/// A segmented control on top and one page below it. Pages are built lazily,
/// so a tab only costs anything when it is shown.
class PanelTabs extends StatefulWidget {
  const PanelTabs({super.key, required this.tabs});
  final Map<String, Widget Function()> tabs;

  @override
  State<PanelTabs> createState() => _PanelTabsState();
}

class _PanelTabsState extends State<PanelTabs> {
  String? _cur;

  @override
  Widget build(BuildContext context) {
    final keys = widget.tabs.keys.toList();
    final cur = keys.contains(_cur) ? _cur! : keys.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Segmented<String>(
          // Four or more tabs get the small type so every word fits on a 320 pt phone.
          compact: keys.length >= 4,
          segments: {for (final k in keys) k: k},
          value: cur,
          onChanged: (k) => setState(() => _cur = k),
        ),
        const SizedBox(height: 10),
        widget.tabs[cur]!(),
      ],
    );
  }
}
