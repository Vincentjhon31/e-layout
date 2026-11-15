import '../online/net.dart';
import '../online/releases.dart';
import 'app_updater_web.dart' if (dart.library.io) 'app_updater_io.dart' as impl;

/// Checks the download page for a newer version and installs it.
abstract class AppUpdater {
  /// The newest release for this platform; null when none is published.
  /// Throws [NetException] when offline.
  Future<ReleaseInfo?> latest();

  /// Downloads and installs [release]. Progress is 0 to 1, null while the size
  /// is unknown. Cancel the subscription to stop. Errors are [NetException]s.
  Stream<double?> downloadAndInstall(ReleaseInfo release);
}

/// Android and Windows: [DownloadPageUpdater]. Other platforms and the website: null.
AppUpdater? createAppUpdater(Net net) => impl.createAppUpdater(net);
