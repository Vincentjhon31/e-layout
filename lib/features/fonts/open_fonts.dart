import 'package:flutter/cupertino.dart';

import '../../core/store/font_store.dart';
import '../../platform/photo_picker.dart';
import 'font_library.dart';
import 'fonts_controller.dart';
import 'fonts_screen.dart';

/// Opens the fonts screen. [onAdded] gets the family of a font that was just
/// added (the editor gives it to the selected text). [source] is the real
/// Fontsource library unless a test passes its own.
Future<void> openFonts(
  BuildContext context, {
  required FontStore store,
  required PhotoPicker picker,
  FontSource? source,
  FontsTab tab = FontsTab.library,
  void Function(String family)? onAdded,
}) async {
  final controller = FontsController(
    source: source ?? FontsourceSource(),
    store: store,
    picker: picker,
    onAdded: onAdded,
  );
  try {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => FontsScreen(controller: controller, initialTab: tab),
      ),
    );
  } finally {
    controller.dispose();
  }
}
