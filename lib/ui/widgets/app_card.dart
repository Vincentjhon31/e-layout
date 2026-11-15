import 'package:flutter/cupertino.dart';

import '../app_theme.dart';

/// A white (dark: graphite) rounded card on the page background.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(color: c.cardIn(context), borderRadius: BorderRadius.circular(AppMetrics.cardRadius)),
      padding: padding,
      child: child,
    );
  }
}

/// Rows in a card separated by hairlines, like an iOS grouped list.
class AppGroup extends StatelessWidget {
  const AppGroup({super.key, required this.children, this.header, this.footer});

  final List<Widget> children;
  final String? header;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Container(height: 0.5, color: c.separator),
        ));
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(header!.toUpperCase(), style: AppText.section.copyWith(color: c.secondary)),
          ),
        Container(
          decoration: BoxDecoration(color: c.cardIn(context), borderRadius: BorderRadius.circular(AppMetrics.cardRadius)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(footer!, style: AppText.caption.copyWith(color: c.secondary)),
          ),
      ],
    );
  }
}

/// One row of an [AppGroup]: a label at the left and a control at the right.
class AppRow extends StatelessWidget {
  const AppRow({super.key, required this.label, this.trailing, this.onTap, this.detail});

  final String label;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final row = Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.body.copyWith(color: c.text)),
                if (detail != null)
                  Text(detail!, style: AppText.caption.copyWith(color: c.secondary)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row);
  }
}
