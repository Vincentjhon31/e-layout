import '../../platform/device_noun.dart';
import 'package:flutter/cupertino.dart';

import '../../ui/app_theme.dart';
import '../../ui/previews.dart';
import '../../ui/widgets/pressable.dart';
import 'home_controller.dart';

const double kLayoutCardWidth = 132;
const double _thumbHeight = 88;

/// The horizontally scrolling row of layout cards, with a "+" card at the end.
class LayoutStrip extends StatelessWidget {
  const LayoutStrip({
    super.key,
    required this.layouts,
    required this.selectedId,
    required this.onSelect,
    required this.onActions,
    required this.onAdd,
  });

  final List<LayoutItem> layouts;
  final String? selectedId;
  final ValueChanged<LayoutItem> onSelect;
  final ValueChanged<LayoutItem> onActions;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _thumbHeight + 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppMetrics.gutter),
        itemCount: layouts.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          if (i == layouts.length) return _AddCard(onTap: onAdd);
          final item = layouts[i];
          return _LayoutCard(
            item: item,
            selected: item.id == selectedId,
            onTap: () => item.id == selectedId ? onActions(item) : onSelect(item),
            onLongPress: () => onActions(item),
          );
        },
      ),
    );
  }
}

class _LayoutCard extends StatelessWidget {
  const _LayoutCard({required this.item, required this.selected, required this.onTap, required this.onLongPress});

  final LayoutItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Pressable(
      onPressed: onTap,
      onLongPress: onLongPress,
      pressedOpacity: 0.75,
      semanticLabel: '${item.doc.name}${selected ? ', selected' : ''}',
      child: SizedBox(
        width: kLayoutCardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: kLayoutCardWidth,
                  height: _thumbHeight,
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    painter: LayoutThumbPainter(doc: item.doc, prep: item.prep, revision: item.revision),
                  ),
                ),
                if (selected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
                          border: Border.all(color: c.accent, width: 2.5),
                        ),
                      ),
                    ),
                  ),
                if (selected)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _Badge(color: c.accent, icon: CupertinoIcons.checkmark_alt, iconColor: c.onAccent),
                  ),
                if (selected)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: _Badge(
                          color: const Color(0xCC1F2328),
                          icon: CupertinoIcons.ellipsis,
                          iconColor: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(item.doc.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.captionStrong.copyWith(color: c.text, fontSize: 14)),
            Text(item.builtin ? 'Office layout' : 'On this $deviceNoun',
                maxLines: 1, style: AppText.caption.copyWith(color: c.secondary)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.icon, required this.iconColor});
  final Color color;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 15, color: iconColor),
      );
}

class _AddCard extends StatelessWidget {
  const _AddCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Pressable(
      onPressed: onTap,
      semanticLabel: 'Add a layout',
      child: SizedBox(
        width: kLayoutCardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            CustomPaint(
              painter: _DashedBorder(c.secondary.withValues(alpha: 0.6)),
              child: SizedBox(
                width: kLayoutCardWidth,
                height: _thumbHeight,
                child: Icon(CupertinoIcons.add, size: 28, color: c.accent),
              ),
            ),
            const SizedBox(height: 8),
            Text('Add layout', style: AppText.captionStrong.copyWith(color: c.accent, fontSize: 14)),
            Text('New or from a file', maxLines: 1, style: AppText.caption.copyWith(color: c.secondary)),
          ],
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.75), const Radius.circular(AppMetrics.cardRadius));
    final path = Path()..addRRect(rr);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
