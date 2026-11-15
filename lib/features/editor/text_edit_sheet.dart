import 'package:flutter/cupertino.dart';

import '../../core/model/layout_doc.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/sheet_scaffold.dart';
import 'editor_controller.dart';

/// A simple sheet to change the words of a text piece. The canvas behind
/// updates as you type; one pause in typing is one undo step.
Future<void> showTextEdit(BuildContext context, EditorController c, LayoutElement el) {
  return showAppSheet<void>(context, (_) => TextEditSheet(controller: c, elementId: el.id));
}

class TextEditSheet extends StatefulWidget {
  const TextEditSheet({super.key, required this.controller, required this.elementId});
  final EditorController controller;
  final String elementId;

  @override
  State<TextEditSheet> createState() => _TextEditSheetState();
}

class _TextEditSheetState extends State<TextEditSheet> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.controller.byId(widget.elementId)?.text ?? '');
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _changed(String value) {
    final c = widget.controller;
    final el = c.byId(widget.elementId);
    if (el == null) return;
    final wasDefault = el.name == c.defaultName(el);
    c.change(() {
      final now = c.byId(widget.elementId)!;
      now.text = value;
      c.fitText(now);
      if (wasDefault) now.name = c.defaultName(now);
    }, 'text:${widget.elementId}');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SheetScaffold(
      title: 'Edit text',
      child: CupertinoTextField(
        controller: _text,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        padding: const EdgeInsets.all(14),
        style: AppText.body.copyWith(color: colors.text),
        placeholder: 'Type here',
        placeholderStyle: AppText.body.copyWith(color: colors.secondary),
        decoration: BoxDecoration(color: colors.raised, borderRadius: BorderRadius.circular(AppMetrics.cardRadius)),
        onChanged: _changed,
      ),
    );
  }
}
