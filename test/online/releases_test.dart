import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/online/releases.dart';

const sha = 'a3f5c0b1d2e3f40516273849a0b1c2d3e4f5061728394a5b6c7d8e9f00112233';

Map<String, Object?> latest() => {
      'updated_at': '2026-11-15T08:00:00+00:00',
      'page': 'https://pio.bongabong.gov.ph/download/',
      'android': {
        'version': '1.0.0',
        'build': 1,
        'date': '2026-11-15',
        'whats_new': ['One', 'Two', 3, null],
        'download': 'https://pio.bongabong.gov.ph/api/download.php?file=e-layout-1.0.0.apk',
        'name': 'e-layout-1.0.0.apk',
        'size': 56941479,
        'sha256': sha,
        'url': 'https://pio.bongabong.gov.ph/download/files/e-layout-1.0.0.apk',
      },
      'windows': null,
    };

void main() {
  test('compareVersions', () {
    expect(compareVersions('1.10.0+1', '1.9.0+9'), greaterThan(0));
    expect(compareVersions('v1.0.0+2', '1.0.0+1'), greaterThan(0));
    expect(compareVersions('1.0.0', '1.0.0+0'), 0);
    expect(compareVersions('1.0.0-beta', '1.0.0'), 0);
    expect(compareVersions('0.9.9+5', '1.0.0+1'), lessThan(0));
    expect(compareVersions('1.0.0+3', '1.0.0+12'), lessThan(0));
  });

  test('fromLatest reads the android entry', () {
    final r = ReleaseInfo.fromLatest(latest(), 'android')!;
    expect(r.version, '1.0.0');
    expect(r.build, 1);
    expect(r.downloadUrl, 'https://pio.bongabong.gov.ph/api/download.php?file=e-layout-1.0.0.apk');
    expect(r.sha256, sha);
    expect(r.size, 56941479);
    expect(r.date, '2026-11-15');
    expect(r.pageUrl, 'https://pio.bongabong.gov.ph/download/');
    expect(r.whatsNew, ['One', 'Two']);
  });

  test('the download address falls back to url, then page', () {
    final m = latest();
    (m['android'] as Map).remove('download');
    expect(ReleaseInfo.fromLatest(m, 'android')!.downloadUrl, 'https://pio.bongabong.gov.ph/download/files/e-layout-1.0.0.apk');
    (m['android'] as Map).remove('url');
    expect(ReleaseInfo.fromLatest(m, 'android')!.downloadUrl, 'https://pio.bongabong.gov.ph/download/');
  });

  test('a null or missing platform and broken input give null', () {
    expect(ReleaseInfo.fromLatest(latest(), 'windows'), isNull);
    expect(ReleaseInfo.fromLatest(latest(), 'ios'), isNull);
    expect(ReleaseInfo.fromLatest('nonsense', 'android'), isNull);
    expect(ReleaseInfo.fromLatest(null, 'android'), isNull);
  });

  test('isNewerThan compares version and build', () {
    final r = ReleaseInfo.fromLatest(latest(), 'android')!;
    expect(r.isNewerThan('1.0.0', 1), isFalse);
    expect(r.isNewerThan('0.9.0', 5), isTrue);
    expect(r.isNewerThan('1.0.0', 0), isTrue);
    expect(r.isNewerThan('1.0.1', 1), isFalse);
  });

  test('isNewerDeployment', () {
    expect(isNewerDeployment({'version': '1.0.1', 'build_number': '2'}, '1.0.0', 1), isTrue);
    expect(isNewerDeployment({'version': '1.0.0', 'build_number': '1'}, '1.0.0', 1), isFalse);
    expect(isNewerDeployment({'version': '1.0.0', 'build_number': '2'}, '1.0.0', 1), isTrue);
    expect(isNewerDeployment('junk', '1.0.0', 1), isFalse);
    expect(isNewerDeployment(null, '1.0.0', 1), isFalse);
    expect(isNewerDeployment({'version': 3}, '1.0.0', 1), isFalse);
  });
}
