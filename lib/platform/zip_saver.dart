import 'dart:typed_data';

import 'gallery_saver.dart';
import 'zip_writer.dart';

/// Starts a browser download of [parts] (joined) named [name].
typedef DownloadFn = Future<void> Function(String name, List<Uint8List> parts);

/// The website's way of saving: a batch becomes one ZIP download named
/// `PIO-photos-<yyyy-mm-dd>.zip`; a single photo downloads on its own.
class ZipSaver extends GallerySaver {
  ZipSaver({required this.download, DateTime Function()? today, this.limit = kZipLimit})
      : _today = today ?? DateTime.now;

  final DownloadFn download;
  final DateTime Function() _today;
  final int limit;

  ZipWriter? _zip;

  @override
  String get destinationLabel => 'your Downloads folder';

  @override
  Future<bool> beginBatch(int count) async {
    _zip = ZipWriter(limit: limit);
    return true;
  }

  @override
  Future<String?> saveImage(Uint8List bytes, String fileName) async {
    final zip = _zip;
    if (zip == null) {
      await download(fileName, [bytes]);
      return null;
    }
    try {
      zip.add(fileName, bytes, _today());
    } on ZipTooLargeException {
      throw const SaveStoppedException(zipTooLargeMessage);
    } on OutOfMemoryError {
      throw const SaveStoppedException('The browser has no memory left for more photos in this ZIP.');
    }
    return null;
  }

  @override
  Future<void> endBatch({required bool keep}) async {
    final zip = _zip;
    _zip = null;
    if (zip == null || !keep || zip.count == 0) return;
    final d = _today();
    String two(int n) => n.toString().padLeft(2, '0');
    await download('PIO-photos-${d.year}-${two(d.month)}-${two(d.day)}.zip', zip.finishParts());
  }

  @override
  String resultLine(int saved, String size) =>
      'Downloaded ${saved == 1 ? '1 photo' : '$saved photos'} in a ZIP ($size).';

  @override
  String cancelledLine(int saved) => 'Cancelled. Nothing was downloaded.';

  @override
  String savedOneLine(String name) => 'Downloaded $name.';
}
