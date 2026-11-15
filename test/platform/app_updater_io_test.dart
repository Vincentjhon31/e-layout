import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pio_photo_layout/online/net.dart';
import 'package:pio_photo_layout/online/releases.dart';
import 'package:pio_photo_layout/platform/app_updater_io.dart';

final fakeApk = Uint8List.fromList(List.generate(300 * 1024, (i) => (i * 31 + 7) & 255));
final apkSha = sha256.convert(fakeApk).toString();

Map<String, Object?> latestJson({String? sha, String version = '1.1.0', int build = 2}) => {
      'page': 'https://pio.bongabong.gov.ph/download/',
      'android': {
        'version': version,
        'build': build,
        'whats_new': ['One'],
        'download': 'https://pio.bongabong.gov.ph/api/download.php?file=e-layout-$version.apk',
        'sha256': sha ?? apkSha,
        'size': fakeApk.length,
      },
      'windows': {
        'version': version,
        'build': build,
        'download': 'https://pio.bongabong.gov.ph/api/download.php?file=e-layout-$version-setup.exe',
        'sha256': apkSha,
        'size': fakeApk.length,
      },
    };

class Server {
  Server({this.sha, this.stallAfter, this.version = '1.1.0', this.build = 2});
  final String? sha;
  final int? stallAfter;
  final String version;
  final int build;
  int fileRequests = 0;

  MockClient get client => MockClient.streaming((req, body) async {
        await body.drain<void>();
        if (req.url.path.endsWith('latest.json')) {
          final bytes = utf8.encode(jsonEncode(latestJson(sha: sha, version: version, build: build)));
          return http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length);
        }
        fileRequests++;
        Stream<List<int>> chunks() async* {
          const size = 20 * 1024;
          for (var o = 0; o < fakeApk.length; o += size) {
            if (stallAfter != null && o >= stallAfter!) {
              await Completer<void>().future; // never sends again
            }
            await Future<void>.delayed(const Duration(milliseconds: 1));
            yield fakeApk.sublist(o, (o + size).clamp(0, fakeApk.length));
          }
        }

        return http.StreamedResponse(chunks(), 200, contentLength: fakeApk.length);
      });
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('updater_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  DownloadPageUpdater make(Server s, {List<File>? installed, String platformKey = 'android', Duration? stall}) =>
      DownloadPageUpdater(
        net: Net(client: s.client),
        platformKey: platformKey,
        downloadDirectory: dir,
        install: (f) async => installed?.add(f),
        version: '1.0.0',
        build: 1,
        stallTimeout: stall ?? const Duration(seconds: 5),
      );

  Future<ReleaseInfo> release(DownloadPageUpdater u) async => (await u.latest())!;

  test('progress rises and ends at 1, the file is named, install runs once', () async {
    final installed = <File>[];
    final u = make(Server(), installed: installed);
    final r = await release(u);
    expect(r.isNewerThan('1.0.0', 1), isTrue);
    final values = await u.downloadAndInstall(r).toList();
    final nums = values.whereType<double>().toList();
    expect(nums.last, 1);
    for (var i = 1; i < nums.length; i++) {
      expect(nums[i], greaterThan(nums[i - 1]));
    }
    expect(nums.length, greaterThan(3));
    expect(installed, hasLength(1));
    expect(installed.single.path.replaceAll('\\', '/'), endsWith('e-layout-1.1.0-2.apk'));
    expect(installed.single.readAsBytesSync(), fakeApk);
    expect(dir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
  });

  test('the Windows file is the setup program', () async {
    final installed = <File>[];
    final u = make(Server(), installed: installed, platformKey: 'windows');
    await u.downloadAndInstall(await release(u)).drain<void>();
    expect(installed.single.path.replaceAll('\\', '/'), endsWith('e-layout-1.1.0-2-setup.exe'));
  });

  test('a wrong SHA-256 fails, deletes the file and never installs', () async {
    final installed = <File>[];
    final u = make(Server(sha: 'a' * 64), installed: installed);
    final r = await release(u);
    await expectLater(u.downloadAndInstall(r).drain<void>(), throwsA(isA<NetException>()));
    expect(installed, isEmpty);
    expect(dir.listSync(), isEmpty);
  });

  test('an intact earlier download is reused without fetching again', () async {
    final s = Server();
    final installed = <File>[];
    final u = make(s, installed: installed);
    final r = await release(u);
    await u.downloadAndInstall(r).drain<void>();
    expect(s.fileRequests, 1);
    await u.downloadAndInstall(r).drain<void>();
    expect(s.fileRequests, 1);
    expect(installed, hasLength(2));
  });

  test('cancelling half-way deletes the .part', () async {
    final s = Server();
    final u = make(s);
    final r = await release(u);
    final got = Completer<void>();
    late StreamSubscription<double?> sub;
    sub = u.downloadAndInstall(r).listen((v) {
      if (v != null && v > 0.3 && !got.isCompleted) got.complete();
    });
    await got.future;
    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('a stalled stream fails with a NetException and leaves no .part', () async {
    final u = make(Server(stallAfter: 100 * 1024), stall: const Duration(milliseconds: 100));
    final r = await release(u);
    await expectLater(u.downloadAndInstall(r).drain<void>(), throwsA(isA<NetException>()));
    expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('latest() with the same version published is not newer', () async {
    final u = make(Server(version: '1.0.0', build: 1));
    final r = await release(u);
    expect(r.isNewerThan('1.0.0', 1), isFalse);
  });

  test('latest() offline throws a NetException', () async {
    final u = DownloadPageUpdater(
      net: Net(client: MockClient((_) async => throw http.ClientException('x'))),
      platformKey: 'android',
      downloadDirectory: dir,
      install: (_) async {},
    );
    await expectLater(u.latest(), throwsA(isA<NetException>()));
  });
}
