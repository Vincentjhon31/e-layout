import 'package:flutter/cupertino.dart';

import '../app_theme.dart';
import 'pressable.dart';

/// A labelled icon, 64 wide, for the editor's tool strip.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.selected = false,
    this.destructive = false,
    this.width = 64,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool destructive;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = destructive ? c.destructive : (selected ? c.accent : c.text);
    return Opacity(
      opacity: onPressed == null ? 0.35 : 1,
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: label,
        child: SizedBox(
          width: width,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 32,
                decoration: BoxDecoration(
                  color: selected ? c.accent.withValues(alpha: 0.14) : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: fg),
              ),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(color: destructive ? c.destructive : c.secondary)),
            ],
          ),
        ),
      ),
    );
  }
}
