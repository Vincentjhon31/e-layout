import '../online/net.dart';
import 'web_version_io.dart' if (dart.library.js_interop) 'web_version_web.dart' as impl;

/// The website only: finds out whether a newer version is deployed and reloads.
abstract class WebVersionWatcher {
  /// The deployed version.json (Flutter writes it next to index.html).
  Future<Object?> deployedVersionJson();

  /// Loads the newest version of the site.
  void reload();
}

/// Null everywhere except the website.
WebVersionWatcher? createWebVersionWatcher(Net net) => impl.createWebVersionWatcher(net);
