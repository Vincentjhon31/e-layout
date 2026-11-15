import 'package:flutter/cupertino.dart';

import '../app_theme.dart';
import 'pressable.dart';

/// A bottom sheet: grabber, title, "Done", and a scrolling body.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.child,
    this.onDone,
    this.doneLabel = 'Done',
    this.leading,
    this.maxHeightFactor = 0.9,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
  });

  final String title;
  final Widget child;

  /// Defaults to closing the sheet.
  final VoidCallback? onDone;
  final String doneLabel;
  final Widget? leading;
  final double maxHeightFactor;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final mq = MediaQuery.of(context);
    final body = InSheet(child: Padding(padding: padding, child: child));
    return Container(
      constraints: BoxConstraints(maxHeight: mq.size.height * maxHeightFactor),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppMetrics.sheetRadius)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(color: c.separator, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  SizedBox(width: 88, child: Align(alignment: Alignment.centerLeft, child: leading)),
                  Expanded(
                    child: Text(title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.headline.copyWith(color: c.text)),
                  ),
                  SizedBox(
                    width: 88,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Pressable(
                        onPressed: onDone ?? () => Navigator.of(context).maybePop(),
                        semanticLabel: doneLabel,
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.centerRight,
                          child: Text(doneLabel, style: AppText.button.copyWith(color: c.accent)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (scrollable)
              Flexible(child: SingleChildScrollView(child: body))
            else
              Flexible(child: body),
          ],
        ),
      ),
    );
  }
}

/// Shows [child] (normally a [SheetScaffold]) as a modal bottom sheet.
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (ctx) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMetrics.sheetMaxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: builder(ctx),
          ),
        ),
      ),
    ),
  );
}
