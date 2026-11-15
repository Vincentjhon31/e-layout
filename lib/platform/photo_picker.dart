import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// A photo or file the person picked. Bytes are read only when needed.
class PickedPhoto {
  PickedPhoto({
    required this.name,
    required this.readBytes,
    this.path,
    this.size,
    this.modified,
  });

  final String name;
  final String? path;
  final Future<Uint8List> Function() readBytes;
  final int? size;
  final DateTime? modified;

  /// app.js fileKey(): name, size and date.
  String get key => '$name|${size ?? ''}|${modified?.millisecondsSinceEpoch ?? ''}';
}

abstract class PhotoPicker {
  /// Photos from the gallery, untouched (no resizing or recompression).
  Future<List<PickedPhoto>> pickPhotos();

  /// True where a whole folder can be added (Windows).
  bool get canPickFolder => false;

  /// Every photo in a folder the person chooses and its subfolders.
  Future<List<PickedPhoto>> pickFolder() async => [];

  /// Any files (layout files, pictures, fonts).
  Future<List<PickedPhoto>> pickFiles({List<String>? extensions});
}

/// image_picker for photos, file_picker for files.
class DevicePhotoPicker extends PhotoPicker {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<List<PickedPhoto>> pickPhotos() async {
    final files = await _picker.pickMultiImage();
    final out = <PickedPhoto>[];
    for (final f in files) {
      int? size;
      DateTime? modified;
      try {
        size = await f.length();
        modified = await f.lastModified();
      } catch (_) {}
      out.add(PickedPhoto(
          name: f.name, path: f.path, readBytes: f.readAsBytes, size: size, modified: modified));
    }
    return out;
  }

  @override
  Future<List<PickedPhoto>> pickFiles({List<String>? extensions}) async {
    final files = await FilePicker.pickFiles(
      type: extensions == null ? FileType.any : FileType.custom,
      allowedExtensions: extensions,
    );
    return [
      for (final f in files)
        PickedPhoto(name: f.name, path: f.path, readBytes: f.readAsBytes, size: await f.length()),
    ];
  }
}

/// Returns prepared lists, for tests.
class FakePhotoPicker extends PhotoPicker {
  List<PickedPhoto> nextPhotos = [];
  List<PickedPhoto> nextFiles = [];

  @override
  Future<List<PickedPhoto>> pickPhotos() async => nextPhotos;

  @override
  Future<List<PickedPhoto>> pickFiles({List<String>? extensions}) async => nextFiles;
}
