import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'gallery_saver.dart';

/// Asks for a folder; null when the person cancels.
typedef PickFolderFn = Future<String?> Function();

/// Asks where to save one file (and writes it); returns its path, or null when cancelled.
typedef SaveDialogFn = Future<String?> Function(String name, Uint8List bytes);

/// The Windows app's way of saving: "Save N photos" asks for a folder each
/// time and writes every photo there. Port of the web app's `writeToFolder`:
/// a file that is already in the folder is never overwritten, the new one gets
/// `name (2).jpg` instead.
class FolderSaver extends GallerySaver {
  FolderSaver({required this.pickFolder, this.saveDialog});

  final PickFolderFn pickFolder;

  /// One photo outside a batch (the viewer's "Save this photo", "Save layout
  /// as PNG") asks for a file name here.
  final SaveDialogFn? saveDialog;

  String? _folder;
  String? _last;

  @override
  String get destinationLabel {
    final f = _folder ?? _last;
    return f == null ? 'the folder you chose' : p.basename(f);
  }

  @override
  Future<bool> beginBatch(int count) async {
    final f = await pickFolder();
    if (f == null) return false;
    _folder = f;
    return true;
  }

  @override
  Future<void> endBatch({required bool keep}) async {
    _last = _folder ?? _last;
    _folder = null;
  }

  @override
  Future<String?> saveImage(Uint8List bytes, String fileName) async {
    final folder = _folder;
    if (folder == null) {
      final ask = saveDialog;
      if (ask == null) throw const SaveCancelledException();
      final path = await ask(fileName, bytes);
      if (path == null) throw const SaveCancelledException();
      _last = p.dirname(path);
      return path;
    }
    return writeUnique(folder, fileName, bytes);
  }
}

/// Writes [bytes] as [name] in [folder] and returns the path. Never replaces
/// an existing file: `a.jpg` becomes `a (2).jpg`, `a (3).jpg` and so on.
Future<String> writeUnique(String folder, String name, Uint8List bytes) async {
  final ext = p.extension(name);
  final stem = ext.isEmpty ? name : name.substring(0, name.length - ext.length);
  var candidate = name;
  for (var n = 2;; n++) {
    final file = File(p.join(folder, candidate));
    try {
      // An exclusive create fails when the name is taken, so nothing is ever replaced.
      await file.create(exclusive: true);
    } on PathExistsException {
      candidate = '$stem ($n)$ext';
      continue;
    } on FileSystemException {
      if (await file.exists()) {
        candidate = '$stem ($n)$ext';
        continue;
      }
      rethrow;
    }
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
