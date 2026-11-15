import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app_info.dart';
import '../../core/store/settings_store.dart';
import '../../online/net.dart';
import '../../online/releases.dart';
import '../../platform/app_updater.dart';
import '../../platform/web_version.dart';
import 'update_dialogs.dart';

sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpToDate extends UpdateState {
  const UpToDate();
}

class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.release);
  final ReleaseInfo release;
}

/// No internet. [message] is the sentence to show.
class UpdateOffline extends UpdateState {
  const UpdateOffline(this.message);
  final String message;
}

/// The website answered badly (or not at all).
class UpdateFailed extends UpdateState {
  const UpdateFailed(this.message);
  final String message;
}

/// The website version only: a newer version is deployed.
class WebReloadReady extends UpdateState {
  const WebReloadReady(this.version);
  final String version;
}

/// This platform has no in-app updates (the download page is the way).
class UpdatesNotOffered extends UpdateState {
  const UpdatesNotOffered();
}

/// Looks for a newer version. Never throws; read [state].
class UpdateController extends ChangeNotifier {
  UpdateController({
    this.updater,
    this.web,
    required this.settings,
    this.version = kAppVersion,
    this.build = kAppBuild,
  });

  final AppUpdater? updater;
  final WebVersionWatcher? web;
  final SettingsStore settings;
  final String version;
  final int build;

  UpdateState _state = const UpdateIdle();
  UpdateState get state => _state;

  bool _disposed = false;

  void _set(UpdateState s) {
    _state = s;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Asks the website. Sets [state]; never throws.
  Future<void> check() async {
    if (updater == null && web == null) {
      _set(const UpdatesNotOffered());
      return;
    }
    _set(const UpdateChecking());
    try {
      if (updater != null) {
        final r = await updater!.latest();
        _set(r != null && r.isNewerThan(version, build) ? UpdateAvailable(r) : const UpToDate());
      } else {
        final json = await web!.deployedVersionJson();
        if (isNewerDeployment(json, version, build)) {
          _set(WebReloadReady((json as Map)['version'] as String));
        } else {
          _set(const UpToDate());
        }
      }
    } on NetException catch (e) {
      _set(e.message == kOfflineMessage ? UpdateOffline(e.message) : UpdateFailed(e.message));
    } catch (_) {
      _set(const UpdateFailed(kServerTroubleMessage));
    }
  }

  /// Quiet check at start: nothing when offline, and the "Update available"
  /// box at most once per new version.
  Future<void> checkAtStart(BuildContext context) async {
    await check();
    final s = _state;
    if (s is! UpdateAvailable || updater == null) return;
    final key = '${s.release.version}+${s.release.build}';
    try {
      if (await settings.readValue('update_prompted') == key) return;
      await settings.writeValue('update_prompted', key);
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    unawaited(showUpdateAvailable(context, this, s.release));
  }

  /// The website version: loads the newest version.
  void reload() => web?.reload();
}
