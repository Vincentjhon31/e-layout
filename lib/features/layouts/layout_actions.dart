import '../../platform/device_noun.dart';
import 'package:flutter/cupertino.dart';

import '../../ui/widgets/action_sheet.dart';
import '../../ui/widgets/toast.dart';
import '../home/home_controller.dart';

/// Opens the editor on a layout that may be changed (never an office layout).
typedef OpenEditor = Future<void> Function(BuildContext context, LayoutItem item);

/// The actions of one layout card (long-press, or tap the selected card).
Future<void> showLayoutActions(BuildContext context, HomeController c, LayoutItem item, {OpenEditor? openEditor}) {
  return showActionSheet(
    context,
    title: item.doc.name,
    message: item.builtin ? 'Office layout. Changes are made to a copy.' : 'On this $deviceNoun',
    actions: [
      if (openEditor != null) SheetAction('Edit layout', () => editLayout(context, c, item, openEditor)),
      SheetAction('Rename', () => renameLayoutPrompt(context, c, item)),
      SheetAction('Duplicate', () => _guard(context, () => c.duplicateLayout(item), "Couldn't duplicate this layout.")),
      SheetAction('Share layout file', () => _guard(context, () => c.exportLayout(item), "Couldn't share the layout file.")),
      if (!item.builtin) SheetAction('Remove', () => confirmRemoveLayout(context, c, item), destructive: true),
    ],
  );
}

/// The "+" card: a new layout, a layout file someone shared, or a picture.
Future<void> showAddLayout(BuildContext context, HomeController c, {OpenEditor? openEditor}) {
  return showActionSheet(
    context,
    message: 'Import a layout file someone shared, or a PNG with a transparent background.',
    actions: [
      SheetAction('New layout', () async {
        final item = await c.newLayout();
        if (openEditor != null && context.mounted) await openEditor(context, item);
      }),
      SheetAction('Import a layout file', () => _guard(context, c.importLayoutFile, "Couldn't open the file.")),
      SheetAction('Use a picture', () => _guard(context, c.usePicture, "Couldn't open the picture.")),
    ],
  );
}

/// Office layouts are copied first, then the editor opens on the copy.
Future<void> editLayout(BuildContext context, HomeController c, LayoutItem item, OpenEditor openEditor) async {
  final target = await c.editableCopy(item);
  if (context.mounted) await openEditor(context, target);
}

Future<void> renameLayoutPrompt(BuildContext context, HomeController c, LayoutItem item) async {
  final name = await showTextPrompt(
    context,
    title: 'Rename layout',
    message: item.builtin ? 'Office layouts stay as they are, so the new name goes on a copy.' : null,
    initial: item.doc.name,
    confirmLabel: 'Rename',
  );
  if (name != null) await c.renameLayout(item, name);
}

Future<void> confirmRemoveLayout(BuildContext context, HomeController c, LayoutItem item) async {
  final ok = await showConfirm(
    context,
    title: 'Remove "${item.doc.name}"?',
    message: "It is deleted from this $deviceNoun. Photos you already saved don't change.",
    confirmLabel: 'Remove',
    destructive: true,
  );
  if (ok) await c.removeLayout(item);
}

Future<void> _guard(BuildContext context, Future<void> Function() run, String failure) async {
  try {
    await run();
  } catch (e) {
    debugPrint('$failure $e');
    if (context.mounted) showToast(context, failure, icon: CupertinoIcons.exclamationmark_circle);
  }
}
