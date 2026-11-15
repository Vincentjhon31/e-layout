import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import '../online/net.dart';
import '../online/releases.dart';
import 'app_updater.dart';

AppUpdater? createAppUpdater(Net net) {
  if (kIsWeb) return null;
  if (Platform.isAndroid || Platform.isWindows) return DownloadPageUpdater(net: net);
  return null;
}

const _damaged = 'The downloaded update is damaged. Try again, or download it from the PIO website.';

/// Reads latest.json from the download page, downloads the file for this
/// platform (with a progress bar, a stall limit and a SHA-256 check) and hands
/// it to the installer.
class DownloadPageUpdater implements AppUpdater {
  DownloadPageUpdater({
    required this.net,
    Uri? latestUri,
    String? platformKey,
    this.downloadDirectory,
    this.install,
    this.version = kAppVersion,
    this.build = kAppBuild,
    this.stallTimeout = const Duration(seconds: 30),
  })  : latestUri = latestUri ?? kLatestJsonUrl,
        platformKey = platformKey ?? (Platform.isWindows ? 'windows' : 'android');

  final Net net;
  final Uri latestUri;
  final String platformKey;
  final String version;
  final int build;
  final Duration stallTimeout;
  /// Where updates are downloaded; null means the app's temporary folder (tests pass their own).
  final Directory? downloadDirectory;

  /// Opens the installer; null means the real one for this platform (tests pass their own).
  final Future<void> Function(File file)? install;

  static const _channel = MethodChannel('elayout/app_update');

  @override
  Future<ReleaseInfo?> latest() async => ReleaseInfo.fromLatest(await net.getJson(latestUri), platformKey);

  Future<Directory> _dir() async => downloadDirectory ?? Directory(p.join((await getTemporaryDirectory()).path, 'updates'));

  String _fileName(ReleaseInfo r) => 'e-layout-${r.version}-${r.build}${platformKey == 'windows' ? '-setup.exe' : '.apk'}';

  Future<void> _runInstaller(File file) async {
    if (install != null) return install!(file);
    if (platformKey == 'windows') {
      await Process.start(file.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART'], mode: ProcessStartMode.detached);
      exit(0);
    }
    await _channel.invokeMethod<void>('installApk', {'path': file.path});
  }

  static Future<String> _sha(File f) async => (await sha256.bind(f.openRead()).first).toString();

  @override
  Stream<double?> downloadAndInstall(ReleaseInfo release) {
    late final StreamController<double?> out;
    StreamSubscription<List<int>>? sub;
    IOSink? sink;
    File? part;
    var cancelled = false;
    var failed = false;

    Future<void> dropPart() async {
      try {
        await sink?.close();
      } catch (_) {}
      sink = null;
      try {
        if (part != null && await part!.exists()) await part!.delete();
      } catch (_) {}
    }

    Future<void> fail(Object error) async {
      await dropPart();
      if (!out.isClosed) {
        out.addError(error is NetException ? error : const NetException(kOfflineMessage));
        await out.close();
      }
    }

    Future<void> finish(File file) async {
      if (!out.isClosed) out.add(1);
      try {
        await _runInstaller(file);
      } catch (e) {
        await fail(NetException('The installer could not be opened. $e'));
        return;
      }
      if (!out.isClosed) await out.close();
    }

    Future<void> run() async {
      try {
        final dir = await _dir();
        await dir.create(recursive: true);
        final target = File(p.join(dir.path, _fileName(release)));
        // An intact earlier download is reused.
        if (release.sha256 != null && await target.exists() && await _sha(target) == release.sha256) {
          await finish(target);
          return;
        }
        for (final e in dir.listSync()) {
          try {
            e.deleteSync(recursive: true);
          } catch (_) {}
        }
        part = File('${target.path}.part');
        final req = http.Request('GET', Uri.parse(release.downloadUrl))..headers['User-Agent'] = 'elayout-app';
        final res = await net.client.send(req).timeout(const Duration(seconds: 15));
        if (cancelled) return;
        if (res.statusCode != 200) {
          await res.stream.drain<void>();
          await fail(const NetException(kServerTroubleMessage));
          return;
        }
        final total = (res.contentLength != null && res.contentLength! > 0) ? res.contentLength : release.size;
        sink = part!.openWrite();
        var received = 0;
        var lastPercent = -1;
        if (total == null) out.add(null);
        final done = Completer<void>();
        sub = res.stream.timeout(stallTimeout).listen(
          (chunk) {
            sink!.add(chunk);
            received += chunk.length;
            if (total != null && total > 0) {
              final percent = (received * 100 ~/ total).clamp(0, 99);
              if (percent != lastPercent) {
                lastPercent = percent;
                out.add(percent / 100);
              }
            }
          },
          onError: (Object e) async {
            if (done.isCompleted) return;
            failed = true;
            done.complete();
            unawaited(sub?.cancel() ?? Future<void>.value());
            await fail(e is TimeoutException ? const NetException(kNoAnswerMessage) : const NetException(kOfflineMessage));
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          // Not cancelOnError: a cancel is awaited before the error is delivered,
          // and a source that is stuck never finishes cancelling.
          cancelOnError: false,
        );
        await done.future;
        if (cancelled || failed || out.isClosed) return;
        await sink!.flush();
        await sink!.close();
        sink = null;
        await part!.rename(target.path);
        part = null;
        if (release.sha256 != null && await _sha(target) != release.sha256) {
          await target.delete();
          await fail(const NetException(_damaged));
          return;
        }
        await finish(target);
      } catch (e) {
        if (!cancelled) await fail(e is TimeoutException ? const NetException(kNoAnswerMessage) : e);
      }
    }

    out = StreamController<double?>(
      onListen: () => unawaited(run()),
      onCancel: () async {
        cancelled = true;
        // Not awaited: a source that is stuck would otherwise hold the cancel back.
        unawaited(sub?.cancel() ?? Future<void>.value());
        await dropPart();
      },
    );
    return out.stream;
  }
}
