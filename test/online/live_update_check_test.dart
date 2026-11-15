// Checks the app's update code against the real download page. Skipped unless the
// environment variable ELAYOUT_LIVE=1 is set (it needs internet and a published release):
//
//   ELAYOUT_LIVE=1 flutter test test/online/live_update_check_test.dart
import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/app_info.dart';
import 'package:pio_photo_layout/online/net.dart';
import 'package:pio_photo_layout/online/releases.dart';

void main() {
  final live = Platform.environment['ELAYOUT_LIVE'] == '1';

  test('the live latest.json lists Android and Windows downloads the app can read', () async {
    final net = Net();
    addTearDown(net.close);
    final json = await net.getJson(kLatestJsonUrl);
    for (final key in ['android', 'windows']) {
      final info = ReleaseInfo.fromLatest(json, key);
      expect(info, isNotNull, reason: 'latest.json has no "$key" entry');
      expect(info!.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(info.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: '$key sha256');
      expect(info.size, greaterThan(1000000), reason: '$key size');
      expect(info.whatsNew, isNotEmpty, reason: '$key notes');
      expect(info.downloadUrl, startsWith('https://pio.bongabong.gov.ph/'));
    }
  }, skip: live ? false : 'set ELAYOUT_LIVE=1 to run against the live site');

  test('the running version is not older than the published one (so no update is offered for it)', () async {
    final net = Net();
    addTearDown(net.close);
    final info = ReleaseInfo.fromLatest(await net.getJson(kLatestJsonUrl), 'android');
    expect(info, isNotNull);
    expect(info!.isNewerThan(kAppVersion, kAppBuild), isFalse,
        reason: 'the live site has a newer version than this code');
  }, skip: live ? false : 'set ELAYOUT_LIVE=1 to run against the live site');
}
