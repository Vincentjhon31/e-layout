import 'package:flutter/cupertino.dart';

import '../app_theme.dart';
import 'pressable.dart';

/// One row of an [AppActionSheet].
class SheetAction {
  const SheetAction(this.label, this.onPressed, {this.destructive = false});
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
}

/// A flat iOS-style action sheet (no blur): an optional title and message,
/// a group of actions, and a separate Cancel button.
class AppActionSheet extends StatelessWidget {
  const AppActionSheet({super.key, this.title, this.message, required this.actions, this.cancelLabel = 'Cancel'});

  final String? title;
  final String? message;
  final List<SheetAction> actions;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final surface = c.isDark ? c.raised : c.card;
    final rows = <Widget>[];
    if (title != null || message != null) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          children: [
            if (title != null)
              Text(title!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.captionStrong.copyWith(color: c.secondary)),
            if (title != null && message != null) const SizedBox(height: 2),
            if (message != null)
              Text(message!, textAlign: TextAlign.center, style: AppText.caption.copyWith(color: c.secondary)),
          ],
        ),
      ));
    }
    for (final a in actions) {
      if (rows.isNotEmpty) rows.add(Container(height: 0.5, color: c.separator));
      rows.add(_SheetRow(
        label: a.label,
        color: a.destructive ? c.destructive : c.accent,
        onPressed: () {
          Navigator.of(context).pop();
          a.onPressed();
        },
      ));
    }
    return SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppMetrics.sheetRadius)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(mainAxisSize: MainAxisSize.min, children: rows),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppMetrics.sheetRadius)),
                  clipBehavior: Clip.antiAlias,
                  child: _SheetRow(
                    label: cancelLabel,
                    color: c.accent,
                    strong: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.label, required this.color, required this.onPressed, this.strong = false});
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool strong;

  @override
  Widget build(BuildContext context) => Pressable(
        onPressed: onPressed,
        semanticLabel: label,
        pressedOpacity: 0.5,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ExcludeSemantics(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (strong ? AppText.headline : AppText.body).copyWith(color: color, fontSize: 18)),
          ),
        ),
      );
}

/// Shows an [AppActionSheet]; completes when it closes.
Future<void> showActionSheet(BuildContext context,
    {String? title, String? message, required List<SheetAction> actions}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (_) => AppActionSheet(title: title, message: message, actions: actions),
  );
}

/// A flat alert box: title, message, an optional field, Cancel and a main button.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.field,
    required this.confirmLabel,
    required this.onConfirm,
    this.destructive = false,
    this.cancelLabel = 'Cancel',
  });

  final String title;
  final String? message;
  final Widget? field;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final bool destructive;

  /// Null for a box with only the main button.
  final String? cancelLabel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final surface = c.isDark ? c.raised : c.card;
    Widget button(String label, Color color, bool strong, VoidCallback onTap) => Expanded(
          child: Pressable(
            onPressed: onTap,
            semanticLabel: label,
            child: Container(
              height: 50,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ExcludeSemantics(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (strong ? AppText.headline : AppText.body).copyWith(color: color)),
              ),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Container(
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppMetrics.sheetRadius)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(title, textAlign: TextAlign.center, style: AppText.headline.copyWith(color: c.text)),
                        if (message != null) ...[
                          const SizedBox(height: 6),
                          Text(message!,
                              textAlign: TextAlign.center, style: AppText.subhead.copyWith(color: c.secondary)),
                        ],
                        if (field != null) ...[const SizedBox(height: 14), field!],
                      ],
                    ),
                  ),
                  Container(height: 0.5, color: c.separator),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (cancelLabel != null) ...[
                          button(cancelLabel!, c.accent, false, () => Navigator.of(context).pop()),
                          Container(width: 0.5, color: c.separator),
                        ],
                        button(confirmLabel, destructive ? c.destructive : c.accent, true, onConfirm),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks a yes-or-no question. True when the main button was tapped.
Future<bool> showConfirm(BuildContext context,
    {required String title, String? message, required String confirmLabel, bool destructive = false}) async {
  final ok = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AppDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
      onConfirm: () => Navigator.of(ctx).pop(true),
    ),
  );
  return ok ?? false;
}

/// Asks for a line of text. Null when cancelled.
Future<String?> showTextPrompt(BuildContext context,
    {required String title, String? message, String initial = '', required String confirmLabel, String? placeholder}) {
  return showCupertinoDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _TextPrompt(
        title: title, message: message, initial: initial, confirmLabel: confirmLabel, placeholder: placeholder),
  );
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt(
      {required this.title, this.message, required this.initial, required this.confirmLabel, this.placeholder});
  final String title;
  final String? message;
  final String initial;
  final String confirmLabel;
  final String? placeholder;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final TextEditingController _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(_text.text);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppDialog(
      title: widget.title,
      message: widget.message,
      confirmLabel: widget.confirmLabel,
      onConfirm: _done,
      field: CupertinoTextField(
        controller: _text,
        autofocus: true,
        placeholder: widget.placeholder,
        clearButtonMode: OverlayVisibilityMode.editing,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _done(),
        style: AppText.body.copyWith(color: c.text),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: c.isDark ? c.card : c.raised,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
