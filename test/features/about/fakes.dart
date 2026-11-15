import 'dart:async';

import 'package:pio_photo_layout/online/net.dart';
import 'package:pio_photo_layout/online/releases.dart';
import 'package:pio_photo_layout/platform/app_updater.dart';
import 'package:pio_photo_layout/platform/web_version.dart';

ReleaseInfo release110({int? size}) => ReleaseInfo(
      version: '1.1.0',
      build: 2,
      date: '2026-12-01',
      whatsNew: const ['Share your layouts with other offices.', 'Photos save faster.'],
      downloadUrl: 'https://pio.bongabong.gov.ph/api/download.php?file=e-layout-1.1.0.apk',
      pageUrl: 'https://pio.bongabong.gov.ph/download/',
      sha256: 'a' * 64,
      size: size ?? (54.1 * 1048576).round(),
    );

class FakeUpdater implements AppUpdater {
  FakeUpdater({this.release, this.error});
  ReleaseInfo? release;
  Object? error;
  int checks = 0;
  StreamController<double?>? downloads;
  int downloadStarts = 0;

  @override
  Future<ReleaseInfo?> latest() async {
    checks++;
    if (error != null) throw error!;
    return release;
  }

  @override
  Stream<double?> downloadAndInstall(ReleaseInfo release) {
    downloadStarts++;
    downloads = StreamController<double?>();
    return downloads!.stream;
  }
}

class FakeWeb implements WebVersionWatcher {
  FakeWeb(this.json);
  Object? json;
  Object? error;
  bool reloaded = false;

  @override
  Future<Object?> deployedVersionJson() async {
    if (error != null) throw error!;
    return json;
  }

  @override
  void reload() => reloaded = true;
}

const offline = NetException(kOfflineMessage);
