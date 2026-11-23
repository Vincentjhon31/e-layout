import 'package:flutter/cupertino.dart';

import '../home/home_controller.dart';
import 'photo_editor_controller.dart';
import 'photo_editor_screen.dart';

/// Opens the photo editor full screen on [photo]. With [replace] it takes the
/// current page's place (the viewer), so "Done" goes back to Home. Does
/// nothing when photo editing is not available.
Future<void> openPhotoEditor(
  BuildContext context,
  HomeController home,
  PhotoItem photo, {
  bool replace = false,
}) async {
  final developer = home.developer;
  if (developer == null) return;
  final editor = PhotoEditorController(
    home: home,
    photoId: photo.id,
    developer: developer,
  );
  final route = CupertinoPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => PhotoEditorScreen(controller: editor),
  );
  final nav = Navigator.of(context);
  try {
    await (replace ? nav.pushReplacement<void, void>(route) : nav.push(route));
  } finally {
    editor.dispose();
    developer.clearCache();
  }
}
