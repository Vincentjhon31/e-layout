import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'desktop_photo_picker_io.dart';
import 'file_sharer.dart';
import 'folder_saver_io.dart';
import 'gallery_saver.dart';
import 'photo_picker.dart';
import 'platform_services.dart';

/// The phone: gallery, share sheet. Windows: folders and Explorer.
PlatformServices createServices() {
  if (defaultTargetPlatform == TargetPlatform.windows) {
    return PlatformServices(
      kind: DeviceKind.windows,
      picker: DesktopPhotoPicker(),
      saver: FolderSaver(
        pickFolder: () => FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder for the finished photos'),
        saveDialog: saveWithDialog,
      ),
      sharer: WindowsFileSharer(),
    );
  }
  return PlatformServices(
    kind: DeviceKind.phone,
    picker: DevicePhotoPicker(),
    saver: PhoneGallerySaver(),
    sharer: DeviceFileSharer(),
  );
}

/// A "Save as" dialog; returns the chosen path, or null when cancelled.
Future<String?> saveWithDialog(String name, Uint8List bytes) async {
  final uri = await FilePicker.saveFile(
    fileName: name,
    bytes: bytes,
    dialogTitle: 'Save',
    mimeType: name.toLowerCase().endsWith('.png') ? 'image/png' : 'application/octet-stream',
  );
  return uri?.toFilePath();
}

/// Windows has no share sheet: "Show in folder" opens Explorer on the saved
/// photo, and a layout file is saved where the person says.
class WindowsFileSharer extends FileSharer {
  @override
  String? get buttonLabel => 'Show in folder';

  @override
  bool get needsCopies => false;

  @override
  Future<void> shareFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    // `explorer /select,<path>` opens the folder with the first photo highlighted.
    final first = paths.first.replaceAll('/', r'\');
    await Process.start('explorer.exe', ['/select,$first']);
  }

  @override
  Future<void> exportFile(String name, Uint8List bytes) async {
    await saveWithDialog(name, bytes);
  }
}
