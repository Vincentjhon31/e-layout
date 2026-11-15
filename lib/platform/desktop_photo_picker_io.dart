import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../features/home/export_job.dart' show naturalCompare;
import 'folder_saver_io.dart' show PickFolderFn;
import 'photo_picker.dart';

/// Pictures the app can open.
const List<String> kPhotoExtensions = ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'];

bool isPhotoFileName(String name) {
  final e = p.extension(name).toLowerCase();
  return e.length > 1 && kPhotoExtensions.contains(e.substring(1));
}

/// A photo on disk. Its bytes are read only when needed.
PickedPhoto photoFromFile(File f) {
  int? size;
  DateTime? modified;
  try {
    final stat = f.statSync();
    size = stat.size;
    modified = stat.modified;
  } catch (_) {}
  return PickedPhoto(
    name: p.basename(f.path),
    path: f.path,
    readBytes: f.readAsBytes,
    size: size,
    modified: modified,
  );
}

/// Every photo in [dir] and its subfolders, in name order.
Future<List<PickedPhoto>> photosInFolder(Directory dir) async {
  final out = <PickedPhoto>[];
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is File && isPhotoFileName(e.path)) out.add(photoFromFile(e));
  }
  out.sort((a, b) => naturalCompare(a.name, b.name));
  return out;
}

/// Windows: a file dialog for photos, plus "Add a folder".
class DesktopPhotoPicker extends DevicePhotoPicker {
  DesktopPhotoPicker({PickFolderFn? pickFolderPath})
      : _pickFolderPath = pickFolderPath ?? (() => FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder of photos'));

  final PickFolderFn _pickFolderPath;

  @override
  bool get canPickFolder => true;

  @override
  Future<List<PickedPhoto>> pickPhotos() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: kPhotoExtensions,
      dialogTitle: 'Choose photos',
    );
    return [
      for (final f in files)
        if (f.path != null) photoFromFile(File(f.path!)),
    ];
  }

  @override
  Future<List<PickedPhoto>> pickFolder() async {
    final path = await _pickFolderPath();
    if (path == null) return [];
    return photosInFolder(Directory(path));
  }
}
