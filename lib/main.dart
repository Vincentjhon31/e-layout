import 'package:flutter/cupertino.dart';

import 'app.dart';
import 'core/store/batch_store.dart';
import 'core/store/layout_store.dart';
import 'core/store/preset_store.dart';
import 'core/store/settings_store.dart';
import 'features/about/update_controller.dart';
import 'features/editor/open_editor.dart';
import 'features/home/home_controller.dart';
import 'features/home/home_screen.dart';
import 'features/home/home_wiring.dart';
import 'online/net.dart';
import 'platform/app_updater.dart';
import 'platform/device_noun.dart';
import 'platform/platform_services.dart';
import 'platform/temp_files.dart';
import 'platform/web_version.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final services = createPlatformServices();
  deviceNoun = services.deviceNoun;
  final picker = services.picker;
  final controller = HomeController(
    layoutStore: createLayoutStore(),
    settingsStore: SettingsStore(),
    picker: picker,
    saver: services.saver,
    sharer: services.sharer,
    temp: createTempFiles(),
    presetStore: createPresetStore(),
    batchStore: createBatchStore(),
    developerLoad: loadDeveloper(),
  );
  controller.init();
  // The only online parts: update checks (and the font library, which has its own client).
  final net = Net();
  final updates = UpdateController(
    updater: createAppUpdater(net),
    web: createWebVersionWatcher(net),
    settings: SettingsStore(),
  );
  runApp(PioApp(
    home: HomeScreen(
      controller: controller,
      updates: updates,
      actions: homeActions(controller, openEditor: openEditorFor(controller, picker), updates: updates),
    ),
  ));
}
