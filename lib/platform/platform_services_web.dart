import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_sharer.dart';
import 'photo_picker.dart';
import 'platform_services.dart';
import 'zip_saver.dart';

/// The website: photos are picked in the browser and saved as one ZIP.
PlatformServices createServices() => PlatformServices(
      kind: DeviceKind.web,
      picker: DevicePhotoPicker(),
      saver: ZipSaver(download: (name, parts) => downloadParts(name, parts)),
      sharer: WebFileSharer(),
    );

/// Starts a browser download. The pieces are joined by the Blob, not copied.
Future<void> downloadParts(String name, List<Uint8List> parts) async {
  final ext = name.contains('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';
  const types = {'zip': 'application/zip', 'jpg': 'image/jpeg', 'png': 'image/png', 'json': 'application/json'};
  final mime = types[ext] ?? 'application/octet-stream';
  final blob = web.Blob([for (final p in parts) p.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();
  Timer(const Duration(minutes: 2), () => web.URL.revokeObjectURL(url));
}

/// The website has no share button; a layout file just downloads.
class WebFileSharer extends FileSharer {
  @override
  String? get buttonLabel => null;

  @override
  bool get needsCopies => false;

  @override
  Future<void> shareFiles(List<String> paths) async {}

  @override
  Future<void> exportFile(String name, Uint8List bytes) =>
      downloadParts(name, [bytes]);
}
