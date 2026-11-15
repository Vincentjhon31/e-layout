import 'package:flutter/cupertino.dart';

import '../app_theme.dart';
import 'pressable.dart';

enum NoteKind { info, warning, error }

/// An inset note (the web app's notices), with an optional action button.
class NoteBox extends StatelessWidget {
  const NoteBox({
    super.key,
    required this.kind,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.busy = false,
  });

  final NoteKind kind;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Shows "Working" on the action while it runs.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    late Color bg, fg, iconColor;
    late IconData icon;
    switch (kind) {
      case NoteKind.info:
        bg = c.accent.withValues(alpha: 0.10);
        fg = c.text;
        iconColor = c.accent;
        icon = CupertinoIcons.info_circle_fill;
      case NoteKind.warning:
        bg = c.warningBg;
        fg = c.warningText;
        iconColor = c.warningText;
        icon = CupertinoIcons.exclamationmark_triangle_fill;
      case NoteKind.error:
        bg = c.destructive.withValues(alpha: 0.12);
        fg = c.text;
        iconColor = c.destructive;
        icon = CupertinoIcons.xmark_octagon_fill;
    }
    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppMetrics.cardRadius)),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: AppText.subhead.copyWith(color: fg)),
                if (actionLabel != null) ...[
                  const SizedBox(height: 8),
                  Pressable(
                    onPressed: busy ? null : onAction,
                    semanticLabel: actionLabel,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.separator),
                      ),
                      child: Text(busy ? 'Working' : actionLabel!,
                          style: AppText.captionStrong.copyWith(color: c.accent, fontSize: 15)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
