import '../../app_info.dart';
import 'package:flutter/cupertino.dart';

import '../../core/develop/photo_developer.dart';
import '../../core/develop/shader_developer.dart';
import '../../ui/widgets/action_sheet.dart';
import '../about/about_screen.dart';
import '../about/update_controller.dart';
import '../fonts/font_library.dart';
import '../fonts/open_fonts.dart';
import '../layouts/layout_actions.dart';
import '../viewer/photo_viewer.dart';
import 'home_controller.dart';
import 'home_screen.dart';

/// The GPU developer, or null when this device can't load it (photo editing
/// is then off and photos are saved as before).
Future<PhotoDeveloper?> loadDeveloper() async {
  try {
    return await ShaderDeveloper.load();
  } catch (e) {
    debugPrint('Photo editing is not available: $e');
    return null;
  }
}

/// Connects the home screen to the other screens.
HomeActions homeActions(
  HomeController controller, {
  OpenEditor? openEditor,
  FontSource? fontSource,
  UpdateController? updates,
}) {
  // Without a real one (tests) About shows "New versions are on the download page."
  final about = updates ?? UpdateController(settings: controller.settingsStore);
  return HomeActions(
    moreMenu: (context) => _moreMenu(context, controller, fontSource, about),
    layoutActions: (context, item) =>
        showLayoutActions(context, controller, item, openEditor: openEditor),
    addLayout: (context) =>
        showAddLayout(context, controller, openEditor: openEditor),
    openPhoto: (context, photo) {
      final i = controller.readyPhotos.indexOf(photo);
      if (i < 0) return;
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => PhotoViewer(controller: controller, initialIndex: i),
        ),
      );
    },
  );
}

void _moreMenu(
  BuildContext context,
  HomeController controller,
  FontSource? fontSource,
  UpdateController updates,
) {
  showActionSheet(
    context,
    actions: [
      SheetAction(
        'Fonts',
        () => openFonts(
          context,
          store: controller.fontStore,
          picker: controller.picker,
          source: fontSource,
        ),
      ),
      SheetAction(
        'About $kAppName',
        () => Navigator.of(context).push(
          CupertinoPageRoute<void>(
            builder: (_) => AboutScreen(updates: updates),
          ),
        ),
      ),
    ],
  );
}
