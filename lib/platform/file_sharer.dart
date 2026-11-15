import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

abstract class FileSharer {
  Future<void> shareFiles(List<String> paths);

  /// The button's words ("Share", "Show in folder"); null hides the button.
  String? get buttonLabel => 'Share';

  /// True when [shareFiles] needs files in a scratch folder (the phone's share
  /// sheet). False on a computer, where saved photos are shown where they are.
  bool get needsCopies => true;

  /// Hands one finished file (a layout file) to the person: a save dialog on a
  /// computer. Only used when [needsCopies] is false.
  Future<void> exportFile(String name, Uint8List bytes) async {}
}

/// The phone's share sheet.
class DeviceFileSharer extends FileSharer {
  @override
  String? get buttonLabel => 'Share';

  @override
  bool get needsCopies => true;

  @override
  Future<void> exportFile(String name, Uint8List bytes) async {}

  @override
  Future<void> shareFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    await SharePlus.instance.share(ShareParams(files: [for (final p in paths) XFile(p)]));
  }
}

class FakeFileSharer extends FileSharer {
  FakeFileSharer({this.needsCopies = true, this.buttonLabel = 'Share'});

  @override
  final bool needsCopies;
  @override
  final String? buttonLabel;

  final List<List<String>> shared = [];
  final List<String> exported = [];

  @override
  Future<void> exportFile(String name, Uint8List bytes) async => exported.add(name);

  @override
  Future<void> shareFiles(List<String> paths) async => shared.add(List.of(paths));
}
