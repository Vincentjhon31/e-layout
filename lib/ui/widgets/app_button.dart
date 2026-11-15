import 'package:flutter/cupertino.dart';

import '../app_theme.dart';
import 'pressable.dart';

enum AppButtonKind { filled, tinted, plain, destructive }

/// The app's buttons: 50 pt tall, radius 12. Disabled when [onPressed] is null.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = AppButtonKind.filled,
    this.icon,
    this.expand = true,
    this.height = AppMetrics.buttonHeight,
  });

  const AppButton.tinted({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
    this.height = AppMetrics.buttonHeight,
  }) : kind = AppButtonKind.tinted;

  const AppButton.plain({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.height = AppMetrics.minTouch,
  }) : kind = AppButtonKind.plain;

  const AppButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
    this.height = AppMetrics.buttonHeight,
  }) : kind = AppButtonKind.destructive;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final enabled = onPressed != null;
    late Color bg, fg;
    switch (kind) {
      case AppButtonKind.filled:
        bg = c.accent;
        fg = c.onAccent;
      case AppButtonKind.tinted:
        bg = c.accent.withValues(alpha: 0.14);
        fg = c.accent;
      case AppButtonKind.plain:
        bg = const Color(0x00000000);
        fg = c.accent;
      case AppButtonKind.destructive:
        bg = c.destructive.withValues(alpha: 0.12);
        fg = c.destructive;
    }
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.button.copyWith(color: fg, fontFeatures: AppText.tabular)),
        ),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: label,
        child: Container(
          height: height,
          constraints: const BoxConstraints(minWidth: AppMetrics.minTouch),
          padding: EdgeInsets.symmetric(horizontal: kind == AppButtonKind.plain ? 8 : 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppMetrics.buttonRadius),
          ),
          alignment: Alignment.center,
          child: ExcludeSemantics(child: content),
        ),
      ),
    );
  }
}

/// A round or square icon-only button with a 44 pt touch area.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.color,
    this.background,
    this.size = AppMetrics.minTouch,
    this.iconSize = 22,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? background;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Opacity(
      opacity: onPressed != null ? 1 : 0.35,
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: label,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: background == null
              ? null
              : BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppMetrics.buttonRadius)),
          child: Icon(icon, size: iconSize, color: color ?? c.accent),
        ),
      ),
    );
  }
}
