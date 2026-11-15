import 'package:flutter/cupertino.dart';

import '../../platform/photo_picker.dart';
import '../fonts/font_library.dart';
import '../fonts/fonts_screen.dart' show FontsTab;
import '../fonts/open_fonts.dart';
import '../home/home_controller.dart';
import '../layouts/layout_actions.dart';
import 'editor_controller.dart';
import 'editor_screen.dart';

/// The function Home hands to the layout actions: opens the editor on a
/// layout, autosaving through the home screen's layout store, and brings the
/// changed layout (and its pictures) back to Home when the editor closes.
OpenEditor openEditorFor(HomeController home, PhotoPicker picker, {FontSource? fontSource}) {
  return (BuildContext context, LayoutItem item) async {
    final editor = EditorController(doc: item.doc, prep: item.prep, onSave: (doc) => home.layoutStore.save(doc));
    try {
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => EditorScreen(
            controller: editor,
            picker: picker,
            gallery: home.saver,
            photos: home.readyPhotos,
            onMoreFonts: () => openFonts(
              context,
              store: home.fontStore,
              picker: picker,
              source: fontSource,
              tab: FontsTab.library,
              onAdded: editor.setFont,
            ),
          ),
        ),
      );
      item.doc = editor.doc;
      await home.layoutChanged(item);
    } finally {
      editor.dispose();
    }
  };
}
